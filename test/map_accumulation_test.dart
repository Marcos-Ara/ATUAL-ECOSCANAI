import 'package:ecoscan_mobile/models/eco_point.dart';
import 'package:ecoscan_mobile/services/eco_point_service.dart';
import 'package:ecoscan_mobile/state/eco_point_controller.dart';
import 'package:ecoscan_mobile/state/ecoscan_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OfflineService extends EcoPointService {
  int calls = 0;
  @override
  Future<List<EcoPoint>> fetchCatalog() async {
    calls++;
    throw const FormatException('offline');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late OfflineService service;
  late EcoScanStore store;
  late EcoPointController controller;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    service = OfflineService();
    store = await EcoScanStore.load();
    controller = EcoPointController(service: service, store: store);
    await controller.initialize(locate: false, refresh: false);
  });
  tearDown(() {
    controller.dispose();
    service.dispose();
    store.dispose();
  });

  test('todos os 128 pontos aparecem sem GPS e sem rede', () async {
    expect(controller.allPoints, hasLength(128));
    expect(await store.loadCachedEcoPoints(), hasLength(128));
    controller.onMapMoved(const LatLng(-22.9068, -43.1729), 15);
    expect(controller.allPoints, hasLength(128));
    expect(controller.nearbyPoints, isEmpty);
    expect(service.calls, 0);
  });

  test('lista mostra só os dez mais próximos no raio selecionado', () {
    controller.onMapMoved(const LatLng(-23.54340338, -46.60646234), 15);
    final near = controller.nearbyPoints;
    expect(near, isNotEmpty);
    expect(near.length, lessThanOrEqualTo(10));
    expect(near.first.name, 'Bresser');
    for (var i = 0; i < near.length; i++) {
      expect(near[i].distanceMeters, lessThanOrEqualTo(5000));
      if (i > 0) {
        expect(
          near[i].distanceMeters,
          greaterThanOrEqualTo(near[i - 1].distanceMeters!),
        );
      }
    }
    controller.setNearbyRadius(25000);
    expect(controller.nearbyPoints.length, 10);
    expect(controller.allPoints, hasLength(128));
  });

  test('filtros e buscas sem resultado não removem marcadores', () {
    controller.setSearchText('nao existe esse endereco xyz');
    expect(controller.nearbyPoints, isEmpty);
    expect(controller.allPoints, hasLength(128));
    controller.setCategoryFilter(EcoPointCategory.disposal);
    expect(controller.filteredPoints, isEmpty);
    expect(controller.allPoints, hasLength(128));
  });

  test('falha no Supabase preserva todos os pontos locais', () async {
    await controller.refreshCatalog();
    expect(controller.allPoints, hasLength(128));
    expect(controller.status, contains('local'));
  });

  test('material não aceito não recebe indicação de destino', () async {
    await controller.submitSearch('bateria', materialId: 'battery');
    expect(controller.nearbyPoints, isEmpty);
    expect(controller.allPoints, hasLength(128));
  });
}
