const test = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const path = require('node:path');
const root = path.join(__dirname, '..');

function scannerHarness(objects,classes=[]) {
  const observed={cocoLoads:0,mobileLoads:0,detects:0,scripts:[],filters:[]};
  const fakeCanvas={width:0,height:0,toDataURL:()=> 'data:image/jpeg;base64,ZmFrZQ==',
    getContext:()=>({drawImage(){},set filter(value){observed.filters.push(value);}})};
  const context={
    window:{},setTimeout,clearTimeout,Promise,Map,Set,Math,Number,String,
    Image:class {constructor(){this.width=640;this.height=480;}set src(_){queueMicrotask(()=>this.onload());}},
    document:{
      createElement:type=>type==='canvas'?Object.create(fakeCanvas):{remove(){}},
      head:{appendChild:tag=>{observed.scripts.push(tag.src);queueMicrotask(()=>tag.onload());}},
    },
    tf:{ready:async()=>{}},
    cocoSsd:{load:async()=>{observed.cocoLoads++; return {detect:async()=>{
      observed.detects++;return typeof objects==='function'?objects():objects;
    }};}},
    mobilenet:{load:async()=>{observed.mobileLoads++;return {classify:async()=>classes};}},
  };
  vm.runInNewContext(fs.readFileSync(path.join(root,'web/scanner.js'),'utf8'),context);
  return {window:context.window,observed};
}
test('model scripts do not block login startup',()=>{
  assert.equal(scannerHarness([]).observed.scripts.length,0);
});
test('live mouse scan uses one model and preserves measured confidence',async()=>{
  const h=scannerHarness([{class:'mouse',score:.63,bbox:[220,170,200,100]}]);
  const labels=await h.window.ecoscanClassifyImage('fixture',true);
  assert.equal(labels[0].label,'computer mouse');
  assert.equal(labels[0].confidence,.63);
  assert.equal(h.observed.mobileLoads,0);
  await h.window.ecoscanClassifyImage('fixture',true);
  assert.equal(h.observed.cocoLoads,1);
});
test('overlapping frames are rejected instead of queuing GPU jobs',async()=>{
  let finish;
  const h=scannerHarness(()=>new Promise(resolve=>finish=resolve));
  const first=h.window.ecoscanClassifyImage('fixture',true);
  await assert.rejects(h.window.ecoscanClassifyImage('fixture',true),/SCANNER_BUSY/);
  await new Promise(resolve=>setImmediate(resolve));
  finish([]);
  await first;
  assert.equal(h.observed.detects,1);
});
test('central phone wins over background laptop without invented scores',async()=>{
  const h=scannerHarness([
    {class:'laptop',score:.9,bbox:[0,0,80,60]},
    {class:'cell phone',score:.8,bbox:[270,190,100,100]},
  ]);
  const labels=await h.window.ecoscanClassifyImage('fixture',true);
  assert.equal(labels[0].label,'cell phone');
  assert.equal(labels[0].confidence,.8);
});

test('portrait smartphone photo is not reported as television when phone evidence exists',async()=>{
  const h=scannerHarness(
    [{class:'tv',score:.52,bbox:[270,35,100,390]}],
    [{className:'cellular telephone, cellular phone, cellphone, mobile phone',probability:.24}],
  );
  const labels=await h.window.ecoscanClassifyImage('fixture',false);
  assert.ok(labels.some(item=>item.label==='cellular telephone' && item.confidence===.24));
  assert.ok(!labels.some(item=>item.label==='tv' || item.label==='television'));
});

test('gallery keeps moderate-confidence cellular telephone synonym',async()=>{
  const h=scannerHarness([], [
    {className:'cellular telephone, cellular phone, cellphone, cell, mobile phone',probability:.24},
    {className:'remote control, remote',probability:.09},
  ]);
  const labels=await h.window.ecoscanClassifyImage('fixture',false);
  assert.ok(labels.some(item=>item.label==='cellular telephone' && item.confidence===.24));
  assert.ok(labels.some(item=>item.label==='mobile phone' && item.confidence===.24));
});
test('bottle material is not inferred from its color or low-probability label',async()=>{
  const h=scannerHarness([{class:'bottle',score:.9,bbox:[250,120,100,200]}],
    [{className:'wine bottle',probability:.08}]);
  const labels=await h.window.ecoscanClassifyImage('fixture',false);
  assert.equal(labels.length,1);
  assert.equal(labels[0].label,'bottle');
});
test('browser preprocessing applies bounded brightness',async()=>{
  const h=scannerHarness([]);
  const data=await h.window.ecoscanPrepareImage('fixture',640,9);
  assert.ok(data.startsWith('data:image/jpeg'));
  assert.equal(h.observed.filters[0],'brightness(1.6)');
});

test('map source no longer contains CARTO raster API-key basemap',()=>{
  const dart=fs.readFileSync(path.join(root,'lib/screens/map_screen.dart'),'utf8');
  assert.ok(dart.includes('tiles.openfreemap.org/styles/liberty'));
  assert.ok(dart.includes('tiles.openfreemap.org/styles/dark'));
  assert.ok(!dart.includes('basemaps.cartocdn.com'));
});

test('extremely tall product is rejected as TV when there is no supporting phone label',async()=>{
  const h=scannerHarness(
    [{class:'tv',score:.52,bbox:[270,25,95,410]}],
    [{className:'hand-held computer',probability:.11}],
  );
  const labels=await h.window.ecoscanClassifyImage('fixture',false);
  assert.ok(!labels.some(item=>item.label==='tv' || item.label==='television'));
});

test('guest mode and map controller wiring remain present in Dart source',()=>{
  const auth=fs.readFileSync(path.join(root,'lib/services/auth_session.dart'),'utf8');
  const gate=fs.readFileSync(path.join(root,'lib/screens/session_gate.dart'),'utf8');
  const controller=fs.readFileSync(path.join(root,'lib/state/eco_point_controller.dart'),'utf8');
  assert.ok(auth.includes("guestUserId = 'guest-local'"));
  assert.ok(auth.includes('void continueAsGuest()'));
  assert.ok(gate.includes('auth.isGuest'));
  assert.ok(controller.includes("package:flutter/foundation.dart"));
});
