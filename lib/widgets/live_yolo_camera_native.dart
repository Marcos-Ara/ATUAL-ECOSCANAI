import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

import 'live_yolo_camera_contract.dart';

class LiveYoloCameraController {
  final YOLOViewController _inner = YOLOViewController();

  bool get isInitialized => _inner.isInitialized;
  bool get isTorchEnabled => _inner.isTorchEnabled;

  Future<Uint8List?> capturePhoto({bool withOverlays = false}) =>
      _inner.capturePhoto(withOverlays: withOverlays);

  Future<void> pause() => _inner.pause();
  Future<void> resume() => _inner.resume();
  Future<void> setTorchMode(bool enabled) => _inner.setTorchMode(enabled);
  Future<void> switchCamera() => _inner.switchCamera();
  Future<void> tapToFocus(double x, double y) => _inner.tapToFocus(x, y);
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
  Widget build(BuildContext context) {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(
          child: Text(
            'Scanner YOLO ao vivo disponível no Android/iOS.',
            style: TextStyle(color: Colors.white70),
          ),
        ),
      );
    }

    return YOLOView(
      modelPath: modelPath,
      task: YOLOTask.detect,
      controller: controller._inner,
      cameraResolution: '720p',
      confidenceThreshold: confidenceThreshold,
      iouThreshold: iouThreshold,
      useGpu: true,
      lensFacing: LensFacing.back,
      onResult: (results) {
        onResult(
          results
              .map(
                (result) => LiveYoloDetection(
                  classIndex: result.classIndex,
                  className: result.className,
                  confidence: result.confidence,
                  normalizedBox: result.normalizedBox,
                ),
              )
              .toList(growable: false),
        );
      },
      onPerformanceMetrics: (metrics) {
        onPerformanceMetrics(
          LiveYoloMetrics(
            fps: metrics.fps,
            processingTimeMs: metrics.processingTimeMs,
            frameNumber: metrics.frameNumber,
          ),
        );
      },
      onModelLoad: (_, _) => onModelLoad(),
      onModelError: (error, _, _) => onModelError(error.toString()),
    );
  }
}
