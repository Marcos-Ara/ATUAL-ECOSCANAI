import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'live_yolo_camera_contract.dart';

class LiveYoloCameraController {
  bool get isInitialized => false;
  bool get isTorchEnabled => false;

  Future<Uint8List?> capturePhoto({bool withOverlays = false}) async => null;
  Future<void> pause() async {}
  Future<void> resume() async {}
  Future<void> setTorchMode(bool enabled) async {}
  Future<void> switchCamera() async {}
  Future<void> tapToFocus(double x, double y) async {}
}

class LiveYoloCamera extends StatelessWidget {
  const LiveYoloCamera({
    required this.modelPath,
    required this.controller,
    required this.onResult,
    required this.onPerformanceMetrics,
    required this.onModelLoad,
    required this.onModelError,
    this.confidenceThreshold = 0.25,
    this.iouThreshold = 0.50,
    super.key,
  });

  final String modelPath;
  final LiveYoloCameraController controller;
  final ValueChanged<List<LiveYoloDetection>> onResult;
  final ValueChanged<LiveYoloMetrics> onPerformanceMetrics;
  final VoidCallback onModelLoad;
  final ValueChanged<String> onModelError;
  final double confidenceThreshold;
  final double iouThreshold;

  @override
  Widget build(BuildContext context) => const ColoredBox(
    color: Colors.black,
    child: Center(
      child: Text(
        'Scanner YOLO ao vivo disponível no Android/iOS.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white70),
      ),
    ),
  );
}
