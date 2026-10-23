import 'dart:convert';

import 'package:ecoscan_mobile/models/detection_record.dart';
import 'package:ecoscan_mobile/models/learning_sample.dart';
import 'package:ecoscan_mobile/state/ecoscan_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('histórico e foto separados por conta', () async {
    final store = await EcoScanStore.load();
    store.switchUser('ana');
    await store.setProfilePhoto('photo-a.jpg');
    await store.addDetection(
      DetectionRecord(
        id: '1',
        name: 'Plástico',
        category: 'Plástico',
        bin: 'Vermelha',
        destination: 'Reciclagem',
        confidence: .9,
        imagePath: '',
        detectedAt: DateTime(2026, 9, 16),
      ),
    );
    store.switchUser('bia');
    expect(store.detections, isEmpty);
    expect(store.profilePhoto, isEmpty);
    store.switchUser('ana');
    expect(store.scanCount, 1);
    expect(store.profilePhoto, 'photo-a.jpg');
    store.switchUser(null);
    expect(store.detections, isEmpty);
    store.dispose();
  });

  test('conquistas já vistas permanecem salvas no aparelho', () async {
    final store = await EcoScanStore.load();
    store.switchUser('ana');
    await store.rememberAchievementIds(const {'primeiro_scan', 'reciclador'});
    store.dispose();

    final restored = await EcoScanStore.load();
    restored.switchUser('ana');

    expect(
      restored.knownAchievementIds,
      containsAll({'primeiro_scan', 'reciclador'}),
    );
    restored.dispose();
  });

  test('transfere o trabalho local do visitante para a primeira conta', () async {
    final record = DetectionRecord(
      id: 'guest-scan',
      name: 'Plástico',
      category: 'Plástico',
      bin: 'Vermelha',
      destination: 'Reciclagem',
      confidence: .9,
      imagePath: 'guest-photo.jpg',
      detectedAt: DateTime(2026, 10, 20),
    );
    final sample = LearningSample(
      id: 'guest-sample',
      createdAt: DateTime(2026, 10, 20),
      source: 'gallery',
      detector: 'yolo26n',
      thumbnailDataUrl: 'data:image/jpeg;base64,AA==',
      detections: const [],
    );
    SharedPreferences.setMockInitialValues({
      'ecoscan.detections.v2.guest-local': jsonEncode([record.toJson()]),
      'ecoscan.learning.v1.guest-local': jsonEncode([sample.toJson()]),
      'ecoscan.profile.v2.guest-local': 'guest-avatar.jpg',
    });
    final store = await EcoScanStore.load();

    await store.switchUserWithGuestData('ana');

    expect(store.detections.single.id, 'guest-scan');
    expect(store.learningSamples.single.id, 'guest-sample');
    expect(store.profilePhoto, 'guest-avatar.jpg');
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getBool('ecoscan.profile.pending.v1.ana'), isTrue);
    store.dispose();
  });

  test('exclui várias leituras de uma vez e guarda tombstones', () async {
    final store = await EcoScanStore.load();
    store.switchUser('ana');
    final records = [
      for (final id in ['scan-1', 'scan-2', 'scan-3'])
        DetectionRecord(
          id: id,
          name: 'Plástico',
          category: 'Plástico',
          bin: 'Vermelha',
          destination: 'Reciclagem',
          confidence: .9,
          imagePath: '',
          detectedAt: DateTime(2026, 10, 19),
        ),
    ];
    for (final record in records) {
      await store.addDetection(record);
    }

    await store.removeDetections([records[0], records[2]]);

    expect(store.detections.map((record) => record.id), ['scan-2']);
    expect(store.pendingScanDeletionIds.toSet(), {'scan-1', 'scan-3'});
    store.dispose();
  });

  test('fila de amostras é local, separada e não limita a 30', () async {
    final store = await EcoScanStore.load();
    store.switchUser('ana');
    for (var index = 0; index < 35; index++) {
      await store.addLearningSample(
        LearningSample(
          id: '$index',
          createdAt: DateTime(2026, 9, 29),
          source: 'gallery',
          detector: 'yolo26n',
          thumbnailDataUrl: 'data:image/jpeg;base64,AA==',
          detections: const [],
        ),
      );
    }
    expect(store.learningSampleCount, 35);
    expect(store.learningSamples.first.id, '34');
    store.switchUser('bia');
    expect(store.learningSamples, isEmpty);
    store.switchUser('ana');
    expect(store.learningSampleCount, 35);
    await store.removeLearningSamples(const ['34', '33']);
    expect(store.learningSampleCount, 33);
    expect(store.learningSamples.first.id, '32');
    await store.clearLearningSamples();
    expect(store.learningSamples, isEmpty);
    store.dispose();
  });

  test('correção informada permanece ao salvar e carregar amostra', () {
    final sample = LearningSample(
      id: 'report-1',
      createdAt: DateTime(2026, 10, 8),
      source: 'camera',
      detector: 'yoloe-26n-live',
      thumbnailDataUrl: 'data:image/jpeg;base64,AA==',
      detections: const [],
      reportedLabel: 'Garrafa de vidro',
      reportedBin: 'Verde — Vidro',
      reportNote: 'Tampa separada',
      aiDetected: true,
      originalLabel: 'Garrafa de plástico',
      originalConfidence: .71,
    );

    final restored = LearningSample.fromJson(sample.toJson());
    expect(restored.reportedLabel, 'Garrafa de vidro');
    expect(restored.reportedBin, 'Verde — Vidro');
    expect(restored.reportNote, 'Tampa separada');
    expect(restored.aiDetected, isTrue);
    expect(restored.originalLabel, 'Garrafa de plástico');
    expect(restored.originalConfidence, .71);
  });
}
