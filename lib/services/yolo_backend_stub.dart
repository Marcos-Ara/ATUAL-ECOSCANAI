import 'dart:typed_data';

import '../models/object_detection.dart';
import 'yolo_backend_contract.dart';

YoloBackend createYoloBackend(String modelPath) =>
    _UnsupportedYoloBackend(modelPath);

class _UnsupportedYoloBackend implements YoloBackend {
  const _UnsupportedYoloBackend(this.modelName);

  @override
  final String modelName;

  @override
  bool get isReady => false;

  @override
  Future<bool> load() async => false;

  @override
  Future<List<ObjectDetection>> detect(Uint8List imageBytes) async => const [];

  @override
  Future<void> close() async {}
}
