import 'package:ecoscan_mobile/services/waste_classifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('somente material no título', () {
    final result = WasteClassifier.classifyCandidates(const [
      LabelCandidate('plastic bottle', .94),
    ]);
    expect(result.name, 'Plástico');
    expect(result.bin, 'Vermelha');
  });
  test('não confunde trechos de palavras', () {
    for (final word in [
      'candle',
      'candy',
      'tinny',
      'plantation',
      'mobile home',
      'glasses',
    ]) {
      expect(
        WasteClassifier.classifyCandidates([LabelCandidate(word, .99)]).isKnown,
        isFalse,
        reason: word,
      );
    }
  });
  test('baixa confiança não inventa material e pede nova foto', () {
    final raw = WasteClassifier.classifyCandidates(const [
      LabelCandidate('plastic', .3),
    ]);
    final result = WasteClassifier.finalizeAutomatic(
      raw,
      const [LabelCandidate('plastic', .3)],
    );
    expect(result.isKnown, isFalse);
    expect(result.source, 'ai-unresolved');
    expect(result.destination, contains('Tire outra foto'));
  });
  test('evidências conflitantes não exibem confirmação manual', () {
    final candidates = const [
      LabelCandidate('plastic', .85),
      LabelCandidate('glass bottle', .87),
    ];
    final raw = WasteClassifier.classifyCandidates(candidates);
    final result = WasteClassifier.finalizeAutomatic(raw, candidates);
    expect(result.isManual, isFalse);
    expect(result.source, isNot('manual'));
  });
  test('rótulo fraco não recebe confiança artificial', () {
    const candidates = [LabelCandidate('glass bottle', .18)];
    final raw = WasteClassifier.classifyCandidates(candidates);
    final result = WasteClassifier.finalizeAutomatic(raw, candidates);
    expect(result.isKnown, isFalse);
    expect(result.confidence, 0);
    expect(result.isManual, isFalse);
  });
  for (final label in ['computer', 'desktop computer', 'monitor', 'screen',
      'computer keyboard', 'computer mouse', 'cell phone', 'laptop', 'tv', 'remote']) {
    test('$label resolve para coleta especial sem confirmar material', () {
      final candidates = [LabelCandidate(label, .6), const LabelCandidate('plastic', .9)];
      final result = WasteClassifier.finalizeAutomatic(
        WasteClassifier.classifyCandidates(candidates), candidates);
      expect(result.material?.id, 'electronic');
      expect(result.bin, 'Coleta especial');
      expect(result.confidence, .6);
      expect(result.destination, contains('Não coloque nas lixeiras comuns'));
    });
  }

  test('celular específico vence TV genérica em conflito medido', () {
    const candidates = [
      LabelCandidate('tv', .52),
      LabelCandidate('cellular telephone', .24),
    ];
    final result = WasteClassifier.finalizeAutomatic(
      WasteClassifier.classifyCandidates(candidates),
      candidates,
    );
    expect(result.material?.id, 'electronic');
    expect(result.detectedObject, 'Celular');
    expect(result.confidence, .24);
  });

  test('celular específico com confiança moderada continua sendo eletrônico', () {
    const candidates = [LabelCandidate('cellular telephone', .24)];
    final result = WasteClassifier.finalizeAutomatic(
      WasteClassifier.classifyCandidates(candidates),
      candidates,
    );
    expect(result.material?.id, 'electronic');
    expect(result.detectedObject, 'Celular');
    expect(result.bin, 'Coleta especial');
  });
  test('conflito real permanece inconclusivo', () {
    const candidates = [LabelCandidate('glass bottle', .8), LabelCandidate('plastic bottle', .81)];
    final result = WasteClassifier.finalizeAutomatic(
        WasteClassifier.classifyCandidates(candidates), candidates);
    expect(result.isKnown, isFalse);
  });
  test('não extrai lata de candy nem material de confiança inválida', () {
    expect(WasteClassifier.bestObjectName(const [LabelCandidate('candy', .9)]), isNull);
    expect(WasteClassifier.classifyCandidates(const [LabelCandidate('glass', double.nan)]).isKnown, isFalse);
    expect(WasteClassifier.classifyCandidates(const [LabelCandidate('water bottle', .99)]).isKnown, isFalse);
  });
}
