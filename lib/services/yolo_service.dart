import 'dart:typed_data';
import 'dart:ui' show Rect;

import '../models/object_detection.dart';
import 'yolo_backend_contract.dart';
import 'yolo_backend_stub.dart'
    if (dart.library.io) 'yolo_backend_native.dart'
    as platform;
import 'yolo_model_repository.dart';

class YoloDetectionResult {
  const YoloDetectionResult({
    required this.detections,
    required this.selected,
    required this.modelName,
  });

  final List<ObjectDetection> detections;
  final ObjectDetection? selected;
  final String modelName;
}

class YoloService {
  YoloService({
    String? modelPath,
    YoloModelRepository? modelRepository,
    YoloBackend Function(String)? backendFactory,
  }) : _preferredModel =
           modelPath ??
           const String.fromEnvironment(
             'ECOSCAN_YOLO_MODEL',
             defaultValue: 'assets/models/ecoscan_yoloe26n_w8a32.tflite',
           ),
       _modelRepository = modelRepository ?? YoloModelRepository(),
       _backendFactory = backendFactory ?? platform.createYoloBackend;

  final String _preferredModel;
  final YoloModelRepository _modelRepository;
  final YoloBackend Function(String) _backendFactory;
  final DetectionStabilizer _stabilizer = DetectionStabilizer();
  YoloBackend? _backend;
  Future<bool>? _loading;
  bool _closed = false;
  bool _loadAttempted = false;

  bool get isReady => _backend?.isReady == true;
  String get modelName => _backend?.modelName ?? _preferredModel;

  Future<bool> warmup() async {
    if (_closed) return false;
    if (isReady) return true;
    final current = _loading;
    if (current != null) return current;
    if (_loadAttempted) return false;
    _loadAttempted = true;
    final operation = _loadPreferredThenFallback();
    _loading = operation;
    try {
      return await operation;
    } finally {
      if (identical(_loading, operation)) _loading = null;
    }
  }

  Future<bool> _loadPreferredThenFallback() async {
    final managedModel = await _modelRepository.resolvePreferredModel();
    final candidates = <String>{
      ?managedModel,
      _preferredModel,
      if (_preferredModel != 'yolo26n') 'yolo26n',
    };
    for (final candidate in candidates) {
      if (_closed) return false;
      final backend = _backendFactory(candidate);
      try {
        if (await backend.load()) {
          _backend = backend;
          return true;
        }
      } catch (_) {
        // Continue to the official model, then ScanService falls back to ML Kit.
      }
      await backend.close();
    }
    return false;
  }

  Future<YoloDetectionResult?> detect(
    Uint8List imageBytes, {
    required bool live,
  }) async {
    if (_closed) return null;
    if (!live) _stabilizer.reset();
    if (!isReady && !await warmup()) return null;
    try {
      final detections = await _backend!.detect(imageBytes);
      final current = DetectionTargetSelector.select(
        detections,
        region: live
            ? DetectionTargetSelector.target
            : const Rect.fromLTWH(0, 0, 1, 1),
      );
      final selected = live ? _stabilizer.add(current) : current;
      return YoloDetectionResult(
        detections: detections,
        selected: selected,
        modelName: modelName,
      );
    } catch (_) {
      _stabilizer.reset();
      return null;
    }
  }

  void resetLiveSession() => _stabilizer.reset();

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _stabilizer.reset();
    final loading = _loading;
    if (loading != null) {
      try {
        await loading;
      } catch (_) {}
    }
    final backend = _backend;
    _backend = null;
    if (backend != null) await backend.close();
  }
}
