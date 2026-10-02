import 'dart:typed_data';

import '../models/object_detection.dart';

abstract interface class YoloBackend {
  String get modelName;
  bool get isReady;

  Future<bool> load();
  Future<List<ObjectDetection>> detect(Uint8List imageBytes);
  Future<void> close();
}
