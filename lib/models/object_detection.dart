import 'dart:math' as math;
import 'dart:ui' show Rect;

class ObjectDetection {
  const ObjectDetection({
    required this.label,
    required this.confidence,
    required this.normalizedBox,
    required this.backend,
    this.classIndex,
  });

  final String label;
  final double confidence;
  final Rect normalizedBox;
  final String backend;
  final int? classIndex;

  bool get isValid =>
      label.trim().isNotEmpty &&
      confidence.isFinite &&
      confidence > 0 &&
      confidence <= 1 &&
      normalizedBox.left.isFinite &&
      normalizedBox.top.isFinite &&
      normalizedBox.right.isFinite &&
      normalizedBox.bottom.isFinite &&
      normalizedBox.width > 0 &&
      normalizedBox.height > 0;

  ObjectDetection copyWith({
    String? label,
    double? confidence,
    Rect? normalizedBox,
    String? backend,
    int? classIndex,
  }) => ObjectDetection(
    label: label ?? this.label,
    confidence: confidence ?? this.confidence,
    normalizedBox: normalizedBox ?? this.normalizedBox,
    backend: backend ?? this.backend,
    classIndex: classIndex ?? this.classIndex,
  );
}

abstract final class DetectionTargetSelector {
  static const target = Rect.fromLTWH(0.07, 0.08, 0.86, 0.84);

  static ObjectDetection? select(
    Iterable<ObjectDetection> detections, {
    Rect region = target,
  }) {
    if (!_validRect(region)) return null;
    ObjectDetection? best;
    var bestScore = -double.infinity;
    for (final detection in detections) {
      if (!detection.isValid) continue;
      final box = detection.normalizedBox;
      final overlap = box.intersect(region);
      final overlapArea = overlap.isEmpty
          ? 0.0
          : overlap.width * overlap.height;
      final boxArea = math.max(0.0001, box.width * box.height);
      final coverage = (overlapArea / boxArea).clamp(0.0, 1.0).toDouble();
      final center = box.center;
      if (!region.contains(center) || coverage < 0.35) continue;
      final distance = (center - region.center).distance;
      final centrality = (1 - distance / 0.72).clamp(0.0, 1.0).toDouble();
      final size = math.sqrt(boxArea).clamp(0.0, 1.0).toDouble();
      final score =
          detection.confidence * 0.42 +
          coverage * 0.32 +
          centrality * 0.21 +
          size * 0.05;
      if (score > bestScore) {
        best = detection;
        bestScore = score;
      }
    }
    return best;
  }

  static bool _validRect(Rect value) =>
      value.left.isFinite &&
      value.top.isFinite &&
      value.right.isFinite &&
      value.bottom.isFinite &&
      value.width > 0 &&
      value.height > 0;
}

class DetectionStabilizer {
  DetectionStabilizer({this.windowSize = 4, this.minimumHits = 2})
    : assert(windowSize > 0),
      assert(minimumHits > 0 && minimumHits <= windowSize);

  final int windowSize;
  final int minimumHits;
  final List<ObjectDetection?> _recent = [];
  ObjectDetection? _stable;
  int _emptyFrames = 0;

  ObjectDetection? add(ObjectDetection? current) {
    if (current != null && !current.isValid) current = null;
    _recent.add(current);
    if (_recent.length > windowSize) _recent.removeAt(0);
    if (current == null || !current.isValid) {
      _emptyFrames++;
      if (_emptyFrames >= minimumHits) reset();
      // Do not draw or classify a box which is absent from the current frame.
      return null;
    }
    _emptyFrames = 0;
    final stable = _stable;
    if (stable != null && _sameObject(stable, current)) {
      _stable = current;
      return current;
    }
    final hits = _recent
        .where((item) => item != null && _sameObject(item, current!))
        .length;
    if (hits >= minimumHits) {
      _stable = current;
      _recent
        ..clear()
        ..add(current);
      return current;
    }
    // One conflicting label at the same position may be flicker. A different
    // position is a new object and must earn its own confirmations.
    if (stable != null && _overlap(stable, current) >= 0.15) return stable;
    return null;
  }

  void reset() {
    _recent.clear();
    _stable = null;
    _emptyFrames = 0;
  }

  static String _normalize(String value) => value.trim().toLowerCase();

  static bool _sameObject(ObjectDetection a, ObjectDetection b) =>
      _normalize(a.label) == _normalize(b.label) && _overlap(a, b) >= 0.15;

  static double _overlap(ObjectDetection a, ObjectDetection b) {
    final intersection = a.normalizedBox.intersect(b.normalizedBox);
    if (intersection.isEmpty) return 0;
    final area = intersection.width * intersection.height;
    final union =
        a.normalizedBox.width * a.normalizedBox.height +
        b.normalizedBox.width * b.normalizedBox.height -
        area;
    return union > 0 ? area / union : 0;
  }
}
