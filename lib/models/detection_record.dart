class DetectionRecord {
  const DetectionRecord({
    required this.id,
    required this.name,
    required this.category,
    required this.bin,
    required this.destination,
    required this.confidence,
    required this.imagePath,
    required this.detectedAt,
    this.source = 'camera',
    this.confirmedByUser = false,
    this.latitude,
    this.longitude,
    this.detectedObject,
    this.detector,
    this.objectId,
    this.variantId,
    this.detectionLabel,
    this.classIndex,
  });

  final String id;
  final String name;
  final String category;
  final String bin;
  final String destination;
  final double confidence;
  final String imagePath;
  final DateTime detectedAt;
  final String source;
  final bool confirmedByUser;
  final double? latitude;
  final double? longitude;
  final String? detectedObject;
  final String? detector;
  final String? objectId;
  final String? variantId;
  final String? detectionLabel;
  final int? classIndex;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'category': category,
    'bin': bin,
    'destination': destination,
    'confidence': confidence,
    'imagePath': imagePath,
    'detectedAt': detectedAt.toIso8601String(),
    'source': source,
    'confirmedByUser': confirmedByUser,
    'latitude': latitude,
    'longitude': longitude,
    'detectedObject': detectedObject,
    'detector': detector,
    'objectId': objectId,
    'variantId': variantId,
    'detectionLabel': detectionLabel,
    'classIndex': classIndex,
  };

  factory DetectionRecord.fromJson(Map<String, dynamic> json) {
    return DetectionRecord(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Objeto analisado',
      category: json['category']?.toString() ?? 'Verificar material',
      bin: json['bin']?.toString() ?? 'Consulte a coleta local',
      destination:
          json['destination']?.toString() ?? 'Verifique antes de descartar',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      imagePath: json['imagePath']?.toString() ?? '',
      source: json['source']?.toString() ?? 'camera',
      confirmedByUser: json['confirmedByUser'] == true,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      detectedObject: json['detectedObject']?.toString(),
      detector: json['detector']?.toString(),
      objectId: json['objectId']?.toString(),
      variantId: json['variantId']?.toString(),
      detectionLabel: json['detectionLabel']?.toString(),
      classIndex: (json['classIndex'] as num?)?.toInt(),
      detectedAt:
          DateTime.tryParse(json['detectedAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}
