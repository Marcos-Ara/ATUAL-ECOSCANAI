import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:ultralytics_yolo/ultralytics_yolo.dart';

import '../models/object_detection.dart';
import 'yolo_backend_contract.dart';

YoloBackend createYoloBackend(String modelPath) =>
    _UltralyticsYoloBackend(modelPath);

class _UltralyticsYoloBackend implements YoloBackend {
  _UltralyticsYoloBackend(this.modelName);

  @override
  final String modelName;

  YOLO? _model;

  @override
  bool get isReady => _model?.isInitialized == true;

  @override
  Future<bool> load() async {
    if (isReady) return true;
    if (!Platform.isAndroid && !Platform.isIOS) return false;
    final model = YOLO(
      modelPath: modelName,
      task: YOLOTask.detect,
      useGpu: true,
      numItemsThreshold: 30,
    );
    try {
      if (!await model.loadModel()) {
        await _disposeSafely(model);
        return false;
      }
      _model = model;
      return true;
    } catch (_) {
      await _disposeSafely(model);
      return false;
    }
  }

  @override
  Future<List<ObjectDetection>> detect(Uint8List imageBytes) async {
    final model = _model;
    if (model == null || !model.isInitialized) return const [];
    final raw = await model.predict(
      imageBytes,
      confidenceThreshold: 0.35,
      iouThreshold: 0.50,
    );
    final boxes = raw['boxes'];
    if (boxes is! List) return const [];
    final detections = <ObjectDetection>[];
    for (final item in boxes) {
      if (item is! Map) continue;
      try {
        final parsed = YOLOResult.fromMap(Map<String, dynamic>.from(item));
        final label = parsed.className.trim();
        final box = _safeNormalizedRect(parsed.normalizedBox);
        final confidence = parsed.confidence;
        if (label.isEmpty ||
            !confidence.isFinite ||
            confidence <= 0 ||
            box.isEmpty) {
          continue;
        }
        detections.add(
          ObjectDetection(
            label: label,
            confidence: confidence.clamp(0.0, 1.0).toDouble(),
            normalizedBox: box,
            backend: _isEcoScanModel(modelName)
                ? 'yoloe-26n'
                : 'yolo26n',
            classIndex: parsed.classIndex,
          ),
        );
      } catch (_) {
        // Ignore one malformed box without discarding the entire frame.
      }
    }
    return List.unmodifiable(detections);
  }

  @override
  Future<void> close() async {
    final model = _model;
    _model = null;
    if (model != null) await _disposeSafely(model);
  }

  static bool _isEcoScanModel(String value) =>
      value.toLowerCase().contains('yoloe');

  static Rect _safeNormalizedRect(Rect value) {
    if (!value.left.isFinite ||
        !value.top.isFinite ||
        !value.right.isFinite ||
        !value.bottom.isFinite) {
      return Rect.zero;
    }
    final left = value.left.clamp(0.0, 1.0).toDouble();
    final top = value.top.clamp(0.0, 1.0).toDouble();
    final right = value.right.clamp(0.0, 1.0).toDouble();
    final bottom = value.bottom.clamp(0.0, 1.0).toDouble();
    if (right <= left || bottom <= top) return Rect.zero;
    return Rect.fromLTRB(left, top, right, bottom);
  }

  static Future<void> _disposeSafely(YOLO model) async {
    try {
      await model.dispose();
    } catch (_) {}
  }
}
