import 'dart:ui' show Rect;

class LiveYoloDetection {
  const LiveYoloDetection({
    required this.classIndex,
    required this.className,
    required this.confidence,
    required this.normalizedBox,
  });

  final int classIndex;
  final String className;
  final double confidence;
  final Rect normalizedBox;
}

class LiveYoloMetrics {
  const LiveYoloMetrics({
    required this.fps,
    required this.processingTimeMs,
    required this.frameNumber,
  });

  final double fps;
  final double processingTimeMs;
  final int frameNumber;
}
