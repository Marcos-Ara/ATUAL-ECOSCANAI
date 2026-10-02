import 'package:latlong2/latlong.dart';

enum EcoPointCategory { recycling, disposal }

class EcoPoint {
  const EcoPoint({
    required this.id,
    required this.name,
    required this.type,
    required this.category,
    required this.latitude,
    required this.longitude,
    this.distanceMeters,
    this.address,
    this.phone,
    this.website,
    this.openingHours,
    this.isOpen,
    this.acceptedMaterialIds = const [],
    this.acceptedMaterialsDescription,
    this.district,
    this.administrativeArea,
    this.access,
    this.source = 'osm',
    this.sourceUrl,
  });

  final String id;
  final String name;
  final String type;
  final EcoPointCategory category;
  final double latitude;
  final double longitude;
  final double? distanceMeters;
  final String? address;
  final String? phone;
  final String? website;
  final String? openingHours;
  final bool? isOpen;
  final List<String> acceptedMaterialIds;
  final String? acceptedMaterialsDescription;
  final String? district;
  final String? administrativeArea;
  final String? access;
  final String source;
  final String? sourceUrl;

  LatLng get position => LatLng(latitude, longitude);
  String get coordinateKey =>
      '${latitude.toStringAsFixed(5)}|${longitude.toStringAsFixed(5)}';

  EcoPoint withDistanceFrom(LatLng origin) {
    final distance = const Distance().as(LengthUnit.Meter, origin, position);
    return copyWith(distanceMeters: distance);
  }

  EcoPoint copyWith({double? distanceMeters}) {
    return EcoPoint(
      id: id,
      name: name,
      type: type,
      category: category,
      latitude: latitude,
      longitude: longitude,
      distanceMeters: distanceMeters ?? this.distanceMeters,
      address: address,
      phone: phone,
      website: website,
      openingHours: openingHours,
      isOpen: isOpen,
      acceptedMaterialIds: acceptedMaterialIds,
      acceptedMaterialsDescription: acceptedMaterialsDescription,
      district: district,
      administrativeArea: administrativeArea,
      access: access,
      source: source,
      sourceUrl: sourceUrl,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type,
    'category': category.name,
    'latitude': latitude,
    'longitude': longitude,
    'distanceMeters': distanceMeters,
    'address': address,
    'phone': phone,
    'website': website,
    'openingHours': openingHours,
    'isOpen': isOpen,
    'acceptedMaterialIds': acceptedMaterialIds,
    'acceptedMaterialsDescription': acceptedMaterialsDescription,
    'district': district,
    'administrativeArea': administrativeArea,
    'access': access,
    'source': source,
    'sourceUrl': sourceUrl,
  };

  factory EcoPoint.fromJson(Map<String, dynamic> json) {
    return EcoPoint(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'EcoPonto',
      type: json['type']?.toString() ?? 'Ponto de descarte',
      category: json['category'] == EcoPointCategory.disposal.name
          ? EcoPointCategory.disposal
          : EcoPointCategory.recycling,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      distanceMeters: (json['distanceMeters'] as num?)?.toDouble(),
      address: json['address']?.toString(),
      phone: json['phone']?.toString(),
      website: json['website']?.toString(),
      openingHours: json['openingHours']?.toString(),
      isOpen: json['isOpen'] is bool ? json['isOpen'] as bool : null,
      acceptedMaterialIds: json['acceptedMaterialIds'] is List
          ? (json['acceptedMaterialIds'] as List)
                .map((item) => item.toString())
                .toList(growable: false)
          : const [],
      acceptedMaterialsDescription:
          json['acceptedMaterialsDescription']?.toString(),
      district: json['district']?.toString(),
      administrativeArea: json['administrativeArea']?.toString(),
      access: json['access']?.toString(),
      source: json['source']?.toString() ?? 'osm',
      sourceUrl: json['sourceUrl']?.toString(),
    );
  }
}
