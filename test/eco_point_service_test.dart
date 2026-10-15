import 'dart:convert';

import 'package:ecoscan_mobile/services/eco_point_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('catálogo convertido preserva os 128 dados oficiais', () async {
    final service = EcoPointService();
    final points = await service.loadBundledCatalog();
    expect(points, hasLength(128));
    expect(points.map((p) => p.id).toSet(), hasLength(128));
    final bresser = points.firstWhere((p) => p.name == 'Bresser');
    expect(bresser.latitude, closeTo(-23.54340338, 0.00000001));
    expect(bresser.longitude, closeTo(-46.60646234, 0.00000001));
    expect(bresser.address, contains('Giuseppe Cesari'));
    expect(bresser.district, 'Brás');
    expect(bresser.administrativeArea, 'Mooca');
    expect(bresser.openingHours, contains('6h às 22h'));
    expect(
      bresser.acceptedMaterialIds,
      containsAll(['special', 'plastic', 'glass', 'paper', 'metal']),
    );
    expect(bresser.acceptedMaterialIds, isNot(contains('battery')));
    service.dispose();
  });

  test('recusa GeoJSON projetado sem conversão para WGS84', () {
    expect(
      () => EcoPointService.parseGeoSampa(
        jsonEncode({
          'features': [
            {
              'geometry': {
                'coordinates': [336018.945, 7395405.1371],
              },
              'properties': {},
            },
          ],
        }),
      ),
      throwsFormatException,
    );
  });

  test(
    'Supabase pagina sem filtros de localização e mantém detalhes',
    () async {
      var calls = 0;
      final service = EcoPointService(
        client: MockClient((request) async {
          calls++;
          expect(request.url.host, 'kekcfxoiyufskltnzlie.supabase.co');
          expect(request.url.queryParameters, isNot(contains('latitude')));
          expect(request.headers['apikey'], startsWith('sb_publishable_'));
          final offset = int.parse(request.url.queryParameters['offset']!);
          return http.Response(
            jsonEncode(
              List.generate(
                offset == 0 ? 500 : 1,
                (i) => {
                  'ponto_id': offset + i + 1,
                  'nome': 'Bresser',
                  'tipo': 'Oficial',
                  'categoria': 'reciclagem',
                  'latitude': -23.54,
                  'longitude': -46.60,
                  'fonte': 'geosampa',
                  'horario_atendimento': '6h às 22h',
                  'descricao_materiais_aceitos': 'Plástico',
                  'subprefeitura': 'Mooca',
                  'materiais_ponto_ecologico': [
                    {'material_id': 'plastico'},
                  ],
                },
              ),
            ),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      final points = await service.fetchCatalog();
      expect(calls, 2);
      expect(points, hasLength(501));
      expect(points.first.openingHours, '6h às 22h');
      expect(points.first.acceptedMaterialIds, ['plastic']);
      expect(points.first.administrativeArea, 'Mooca');
      service.dispose();
    },
  );
}
