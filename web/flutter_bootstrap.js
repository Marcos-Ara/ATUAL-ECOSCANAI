{{flutter_js}}
{{flutter_build_config}}

// Use the renderer shipped with the Web build, including when a CDN is blocked.
_flutter.loader.load({
  config: {
    canvasKitBaseUrl: new URL('canvaskit/', document.baseURI).href,
  },
});
