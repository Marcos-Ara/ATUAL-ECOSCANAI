import 'package:ecoscan_mobile/models/eco_point.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  test('calcula e preserva a distância de um EcoPonto', () {
    const point = EcoPoint(
      id: '1',
      name: 'Teste',
      type: 'Reciclagem',
      category: EcoPointCategory.recycling,
      latitude: -23.5505,
      longitude: -46.6333,
    );

    final nearby = point.withDistanceFrom(const LatLng(-23.5510, -46.6333));

    expect(nearby.distanceMeters, isNotNull);
    expect(nearby.distanceMeters!, greaterThan(50));
    expect(nearby.distanceMeters!, lessThan(60));
  });

  test('preserva metadados oficiais no cache', () {
    const point = EcoPoint(
      id: 'geosampa:1',
      name: 'Bresser',
      type: 'Ecoponto oficial',
      category: EcoPointCategory.recycling,
      latitude: -23.5434,
      longitude: -46.6064,
      district: 'Brás',
      administrativeArea: 'Mooca',
      acceptedMaterialsDescription: 'Entulho e recicláveis secos',
      source: 'geosampa',
    );
    final restored = EcoPoint.fromJson(point.toJson());
    expect(restored.district, 'Brás');
    expect(restored.administrativeArea, 'Mooca');
    expect(restored.acceptedMaterialsDescription, contains('recicláveis'));
    expect(restored.source, 'geosampa');
  });
}
