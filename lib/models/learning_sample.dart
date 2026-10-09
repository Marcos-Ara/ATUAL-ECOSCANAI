class LearningSample {
  const LearningSample({
    required this.id,
    required this.createdAt,
    required this.source,
    required this.detector,
    required this.thumbnailDataUrl,
    required this.detections,
    this.reportedLabel,
    this.reportedBin,
    this.reportNote,
    this.aiDetected,
    this.originalLabel,
    this.originalConfidence,
  });

  final String id;
  final DateTime createdAt;
  final String source;
  final String detector;
  final String thumbnailDataUrl;
  final List<Map<String, dynamic>> detections;
  final String? reportedLabel;
  final String? reportedBin;
  final String? reportNote;
  final bool? aiDetected;
  final String? originalLabel;
  final double? originalConfidence;

  Map<String, dynamic> toJson() => {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'source': source,
    'detector': detector,
    'thumbnailDataUrl': thumbnailDataUrl,
    'detections': detections,
    'reportedLabel': reportedLabel,
    'reportedBin': reportedBin,
    'reportNote': reportNote,
    'aiDetected': aiDetected,
    'originalLabel': originalLabel,
    'originalConfidence': originalConfidence,
  };

  factory LearningSample.fromJson(Map<String, dynamic> json) {
    final rawDetections = json['detections'];
    final rawConfidence = json['originalConfidence'];
    return LearningSample(
      id: json['id']?.toString() ?? '',
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      source: json['source']?.toString() ?? 'unknown',
      detector: json['detector']?.toString() ?? 'unknown',
      thumbnailDataUrl: json['thumbnailDataUrl']?.toString() ?? '',
      reportedLabel: json['reportedLabel']?.toString(),
      reportedBin: json['reportedBin']?.toString(),
      reportNote: json['reportNote']?.toString(),
      aiDetected: json['aiDetected'] is bool ? json['aiDetected'] as bool : null,
      originalLabel: json['originalLabel']?.toString(),
      originalConfidence: rawConfidence is num
          ? rawConfidence.toDouble()
          : double.tryParse(rawConfidence?.toString() ?? ''),
      detections: rawDetections is List
          ? rawDetections
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList(growable: false)
          : const [],
    );
  }
}
