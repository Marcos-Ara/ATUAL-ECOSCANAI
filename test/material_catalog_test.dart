import 'dart:convert';
import 'dart:io';

import 'package:ecoscan_mobile/services/material_catalog.dart';
import 'package:ecoscan_mobile/services/waste_classifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late MaterialCatalog catalog;
  setUpAll(() {
    catalog = MaterialCatalog.fromJson(
      jsonDecode(File('assets/data/catalog.json').readAsStringSync())
          as Map<String, dynamic>,
    );
  });
  test('catálogo real prioriza coleta de eletrônico', () {
    final result = catalog.classify(const [
      LabelCandidate('keyboard', .94),
      LabelCandidate('plastic', .82),
    ]);
    expect(result.category, 'Eletrônico');
    expect(result.bin, 'Coleta especial');
  });
  test('garrafa genérica oferece opções e não inventa material', () {
    final result = catalog.classify(const [LabelCandidate('bottle', .96)]);
    expect(result.isKnown, isFalse);
    expect(result.options.map((m) => m.id), containsAll(['plastic', 'glass']));
  });
  test('plástico explícito gera lixeira vermelha e só material no título', () {
    final result = catalog.classify(const [
      LabelCandidate('plastic bottle', .93),
    ]);
    expect(result.name, 'Plástico');
    expect(result.bin, 'Vermelha');
  });
  test('catálogo completo sem listas aninhadas', () {
    final data =
        jsonDecode(File('assets/data/catalog.json').readAsStringSync()) as Map;
    expect((data['objects'] as List).length, greaterThan(100));
    expect((data['objects'] as List).first, isA<Map>());
    expect((data['aliases'] as List).length, greaterThan(200));
  });
  test(
    'todos os prompts têm tradução e destino local sem inflar confiança',
    () {
      final profile =
          jsonDecode(File('assets/data/yoloe_classes.json').readAsStringSync())
              as Map;
      final classes = profile['classes'] as List;
      expect(classes, hasLength(57));
      for (final row in classes.cast<Map>()) {
        final candidates = [LabelCandidate(row['label'] as String, .36)];
        final result = WasteClassifier.finalizeAutomatic(
          catalog.classify(candidates),
          candidates,
        );
        expect(
          result.detectedObject,
          row['object_name'],
          reason: row['label'] as String,
        );
        expect(
          result.material?.id,
          row['material_id'],
          reason: row['label'] as String,
        );
        expect(result.confidence, .36);
        expect(result.destination, isNotEmpty);
      }
    },
  );
  test('baixa confiança não confirma o material de um prompt', () {
    final result = catalog.classify(const [LabelCandidate('food waste', .1)]);
    expect(result.isKnown, isFalse);
  });
}
