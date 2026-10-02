import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'waste_classifier.dart';

/// Bridge para o classificador TensorFlow.js declarado em web/index.html.
/// Usa a API moderna de interoperabilidade JS do Dart (compatível com Web/Wasm).
@JS('ecoscanClassifyImage')
external JSPromise<JSAny?> _ecoscanClassifyImage(JSString dataUrl, JSBoolean live);

@JS('ecoscanPrepareImage')
external JSPromise<JSString> _prepare(JSString url, JSNumber size, JSNumber brightness);
@JS('ecoscanWarmup')
external JSPromise<JSAny?> _warmup();
@JS('ecoscanSetPreviewBrightness')
external void _previewBrightness(JSNumber value);
void setWebPreviewBrightness(double value) => _previewBrightness(value.toJS);

Future<void> warmupWebScanner() async {
  await _warmup().toDart.timeout(const Duration(seconds: 45));
}

Future<Uint8List> prepareWebImage(Uint8List bytes, {int maxSize = 960, double brightness = 1}) async {
  final url = 'data:image/jpeg;base64,${base64Encode(bytes)}';
  final prepared = await _prepare(url.toJS, maxSize.toJS, brightness.toJS).toDart
      .timeout(const Duration(seconds: 15));
  return base64Decode(prepared.toDart.split(',').last);
}

Future<List<LabelCandidate>> classifyWebImage(Uint8List bytes, {bool live = false}) async {
  if (bytes.isEmpty) return const <LabelCandidate>[];

  final dataUrl = 'data:image/jpeg;base64,${base64Encode(bytes)}';

  final raw = await _ecoscanClassifyImage(dataUrl.toJS, live.toJS).toDart
      .timeout(const Duration(seconds: 45));
  final converted = raw.dartify();

  if (converted is! List) return const <LabelCandidate>[];

  final labels = <LabelCandidate>[];
  for (final item in converted) {
    if (item is! Map) continue;

    final label = item['label']?.toString().trim() ?? '';
    final rawConfidence = item['confidence'];
    final confidence = rawConfidence is num
        ? rawConfidence.toDouble()
        : double.tryParse(rawConfidence?.toString() ?? '') ?? 0;

    if (label.isNotEmpty && confidence.isFinite) {
      labels.add(
        LabelCandidate(label, confidence.clamp(0, 1).toDouble()),
      );
    }
  }

  labels.sort((a, b) => b.confidence.compareTo(a.confidence));
  return labels;
}
