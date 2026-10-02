class LearningSample {
  const LearningSample({
    required this.id,
    required this.createdAt,
    required this.source,
    required this.detector,
    required this.thumbnailDataUrl,
    required this.detections,
  });

  final String id;
  final DateTime createdAt;
  final String source;
  final String detector;
  final String thumbnailDataUrl;
  final List<Map<String, dynamic>> detections;

  Map<String, dynamic> toJson() => {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'source': source,
    'detector': detector,
    'thumbnailDataUrl': thumbnailDataUrl,
    'detections': detections,
  };

  factory LearningSample.fromJson(Map<String, dynamic> json) {
    final rawDetections = json['detections'];
    return LearningSample(
      id: json['id']?.toString() ?? '',
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      source: json['source']?.toString() ?? 'unknown',
      detector: json['detector']?.toString() ?? 'unknown',
      thumbnailDataUrl: json['thumbnailDataUrl']?.toString() ?? '',
      detections: rawDetections is List
          ? rawDetections
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList(growable: false)
          : const [],
    );
  }
}
