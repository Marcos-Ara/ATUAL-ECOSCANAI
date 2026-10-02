/* EcoScan browser inference.
   Photos stay in the browser; only TensorFlow model files are downloaded.

   Strategy:
   - live camera: light COCO-SSD for responsiveness;
   - gallery/photo: the more accurate COCO-SSD MobileNet v2 detector first,
     then MobileNet classification only on the detected object crop;
   - disagreements are resolved conservatively. A phone-shaped object is never
     shown as a TV just because one detector produced a stronger generic score.
*/
(() => {
  'use strict';

  const scripts = new Map();
  let cocoLitePromise;
  let cocoAccuratePromise;
  let mobilePromise;
  let active;

  function loadScript(url) {
    if (!scripts.has(url)) {
      scripts.set(url, new Promise((resolve, reject) => {
        const tag = document.createElement('script');
        const timer = setTimeout(() => {
          tag.remove();
          scripts.delete(url);
          reject(new Error('MODEL_TIMEOUT'));
        }, 25000);
        tag.src = url;
        tag.async = true;
        tag.onload = () => {
          clearTimeout(timer);
          resolve();
        };
        tag.onerror = () => {
          clearTimeout(timer);
          scripts.delete(url);
          tag.remove();
          reject(new Error('MODEL_NETWORK'));
        };
        document.head.appendChild(tag);
      }));
    }
    return scripts.get(url);
  }

  async function runtime() {
    await loadScript('https://cdn.jsdelivr.net/npm/@tensorflow/tfjs@4.22.0/dist/tf.min.js');
    await tf.ready();
  }

  async function ensureCocoScript() {
    await runtime();
    await loadScript('https://cdn.jsdelivr.net/npm/@tensorflow-models/coco-ssd@2.2.3/dist/coco-ssd.min.js');
  }

  function cocoLite() {
    return cocoLitePromise ??= (async () => {
      await ensureCocoScript();
      return cocoSsd.load({base: 'lite_mobilenet_v2'});
    })().catch(error => {
      cocoLitePromise = undefined;
      throw error;
    });
  }

  function cocoAccurate() {
    return cocoAccuratePromise ??= (async () => {
      await ensureCocoScript();
      // coco-ssd documents mobilenet_v2 as its highest-accuracy base.
      return cocoSsd.load({base: 'mobilenet_v2'});
    })().catch(error => {
      cocoAccuratePromise = undefined;
      throw error;
    });
  }

  function mobile() {
    return mobilePromise ??= (async () => {
      await runtime();
      await loadScript('https://cdn.jsdelivr.net/npm/@tensorflow-models/mobilenet@2.1.1/dist/mobilenet.min.js');
      // Full-width MobileNet is used only for still photos. It is slower than
      // the old 0.75 model, but static scans prioritize precision over FPS.
      return mobilenet.load({version: 2, alpha: 1.0});
    })().catch(error => {
      mobilePromise = undefined;
      throw error;
    });
  }

  function openImage(url) {
    return new Promise((resolve, reject) => {
      const image = new Image();
      image.onload = () => resolve(image);
      image.onerror = () => reject(new Error('IMAGE_FORMAT'));
      image.src = url;
    });
  }

  async function prepare(url, maxSize, brightness) {
    const image = await openImage(url);
    const ratio = Math.min(1, maxSize / Math.max(image.width, image.height));
    const canvas = document.createElement('canvas');
    canvas.width = Math.max(1, Math.round(image.width * ratio));
    canvas.height = Math.max(1, Math.round(image.height * ratio));
    const ctx = canvas.getContext('2d', {willReadFrequently: false});
    if (!ctx) throw new Error('CANVAS_UNAVAILABLE');
    const factor = Math.max(1, Math.min(1.6, Number(brightness) || 1));
    ctx.filter = 'brightness(' + factor + ')';
    ctx.drawImage(image, 0, 0, canvas.width, canvas.height);
    return canvas;
  }

  function paddedCrop(image, bbox) {
    const [x, y, w, h] = bbox;
    const padX = w * 0.14;
    const padY = h * 0.14;
    const sx = Math.max(0, x - padX);
    const sy = Math.max(0, y - padY);
    const sw = Math.min(image.width - sx, w + padX * 2);
    const sh = Math.min(image.height - sy, h + padY * 2);
    const canvas = document.createElement('canvas');
    canvas.width = 224;
    canvas.height = 224;
    const context = canvas.getContext('2d');
    if (!context) throw new Error('CANVAS_UNAVAILABLE');
    context.drawImage(image, sx, sy, sw, sh, 0, 0, 224, 224);
    return canvas;
  }

  function normalize(label) {
    return String(label || '').trim().toLowerCase()
      .replace(/[_-]+/g, ' ').replace(/\s+/g, ' ');
  }

  function addLabel(map, label, confidence) {
    const clean = String(label || '').trim();
    const score = Number(confidence) || 0;
    if (!clean || !Number.isFinite(score)) return;
    const key = normalize(clean);
    const previous = map.get(key);
    if (!previous || score > previous.confidence) {
      map.set(key, {label: clean, confidence: Math.max(0, Math.min(1, score))});
    }
  }

  async function classifyMobile(model, input, labels) {
    const classes = await model.classify(input, 8);
    let best = 0;
    for (const item of classes) {
      const probability = Number(item.probability) || 0;
      best = Math.max(best, probability);
      // ImageNet splits probability among synonyms. We pass moderate evidence
      // to Dart but never manufacture or boost the measured score.
      if (probability < 0.10) continue;
      for (const label of String(item.className || '').split(',')) {
        addLabel(labels, label, probability);
      }
    }
    return best;
  }

  const phoneTerms = [
    'cell phone', 'cellular telephone', 'cellular phone', 'cellphone',
    'mobile phone', 'smartphone', 'digital cellular phone',
  ];

  function phoneEvidence(labels) {
    let best = 0;
    for (const [key, value] of labels) {
      if (phoneTerms.some(term => key === term || key.includes(term))) {
        best = Math.max(best, value.confidence);
      }
    }
    return best;
  }

  function removeTvIfPhoneShaped(labels, primary, ranked, image) {
    if (!primary || normalize(primary.class) !== 'tv') return;
    const [x, y, w, h] = primary.bbox;
    if (!(w > 0 && h > 0)) return;
    const aspect = h / w;
    const areaRatio = (w * h) / Math.max(1, image.width * image.height);
    const detectorPhone = ranked.find(item =>
      normalize(item.class) === 'cell phone' && Number(item.score) >= 0.16);
    const classifierPhone = phoneEvidence(labels);

    // A conventional TV/screen is landscape. If the detector calls a tall,
    // isolated product photo a TV while another model sees a phone, prefer the
    // phone evidence. If no phone evidence exists, reject only extremely tall
    // TV boxes rather than confidently displaying a clearly inconsistent name.
    const phoneLikeShape = aspect >= 1.30 && areaRatio <= 0.82;
    const extremelyTall = aspect >= 1.65 && areaRatio <= 0.75;
    if ((phoneLikeShape && classifierPhone >= 0.12) || detectorPhone || extremelyTall) {
      labels.delete('tv');
      labels.delete('television');
      if (detectorPhone) addLabel(labels, 'cell phone', detectorPhone.score);
    }
  }

  window.ecoscanPrepareImage = async (url, maxSize, brightness) =>
    (await prepare(url, maxSize, brightness)).toDataURL('image/jpeg', 0.9);

  window.ecoscanWarmup = async () => {
    // The live detector is the only blocking warm-up. Still-photo models start
    // in the background so opening Scanner remains quick.
    await cocoLite();
    void cocoAccurate().catch(() => null);
    void mobile().catch(() => null);
  };

  window.ecoscanSetPreviewBrightness = value => {
    const visit = root => {
      for (const video of root.querySelectorAll('video')) {
        video.style.filter = 'brightness(' + Math.max(1, Math.min(1.6, value)) + ')';
      }
      for (const element of root.querySelectorAll('*')) {
        if (element.shadowRoot) visit(element.shadowRoot);
      }
    };
    visit(document);
  };

  window.ecoscanClassifyImage = (url, live) => {
    // Never queue camera frames behind a long GPU inference.
    if (active) return Promise.reject(new Error('SCANNER_BUSY'));

    active = (async () => {
      const image = await openImage(url);
      const detector = live ? await cocoLite() : await cocoAccurate();
      const minimumObjectScore = live ? 0.32 : 0.16;
      const objects = await detector.detect(image, live ? 6 : 10, minimumObjectScore);
      const ranked = objects.map(p => {
        const [x, y, w, h] = p.bbox;
        const distance = Math.hypot(
          (x + w / 2) / image.width - 0.5,
          (y + h / 2) / image.height - 0.5,
        );
        const area = Math.min(1, (w * h) / Math.max(1, image.width * image.height));
        // Prefer central/prominent objects without modifying the model score
        // exposed to the user.
        return {...p, rank: p.score * (1 - Math.min(0.48, distance)) * (0.82 + Math.min(0.18, area))};
      }).sort((a, b) => b.rank - a.rank);

      const primary = ranked[0];
      const labels = new Map();
      if (primary) {
        addLabel(
          labels,
          primary.class === 'mouse' ? 'computer mouse' : primary.class,
          primary.score,
        );
      }

      if (live) {
        return [...labels.values()].sort((a, b) => b.confidence - a.confidence);
      }

      try {
        const model = await mobile();
        const input = primary ? paddedCrop(image, primary.bbox) : image;
        const cropBest = await classifyMobile(model, input, labels);

        // Product/catalogue photos often have large blank margins. A second
        // pass on the full frame is useful only when the object crop was weak.
        if (primary && cropBest < 0.24) {
          await classifyMobile(model, image, labels);
        }
        removeTvIfPhoneShaped(labels, primary, ranked, image);
      } catch (error) {
        if (!labels.size) throw error;
      }

      return [...labels.values()]
        .sort((a, b) => b.confidence - a.confidence)
        .slice(0, 14);
    })().finally(() => {
      active = undefined;
    });

    return active;
  };
})();
