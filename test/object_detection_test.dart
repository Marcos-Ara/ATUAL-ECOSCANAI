import 'dart:ui';

import 'package:ecoscan_mobile/models/object_detection.dart';
import 'package:flutter_test/flutter_test.dart';

ObjectDetection detection(String label, double confidence, Rect box) =>
    ObjectDetection(
      label: label,
      confidence: confidence,
      normalizedBox: box,
      backend: 'test',
    );

void main() {
  test('objeto dentro da moldura vence fundo mais confiante', () {
    final selected = DetectionTargetSelector.select([
      detection('television', .96, const Rect.fromLTWH(.01, .01, .20, .18)),
      detection('bottle', .72, const Rect.fromLTWH(.38, .28, .24, .46)),
    ]);
    expect(selected?.label, 'bottle');
  });

  test('caixas inválidas são ignoradas', () {
    final selected = DetectionTargetSelector.select([
      detection('bad', .9, const Rect.fromLTWH(double.nan, 0, .2, .2)),
      detection('paper', .7, const Rect.fromLTWH(.3, .3, .3, .3)),
    ]);
    expect(selected?.label, 'paper');
  });

  test('estabilizador exige consenso para trocar a classe', () {
    final stabilizer = DetectionStabilizer(windowSize: 4, minimumHits: 2);
    final bottle = detection('bottle', .8, const Rect.fromLTWH(.3, .2, .3, .5));
    final keyboard = detection(
      'keyboard',
      .8,
      const Rect.fromLTWH(.2, .4, .6, .2),
    );
    expect(stabilizer.add(bottle), isNull);
    expect(stabilizer.add(bottle)?.label, 'bottle');
    expect(stabilizer.add(keyboard)?.label, 'bottle');
    expect(stabilizer.add(keyboard)?.label, 'keyboard');
  });

  test('objeto fora da moldura não gera seleção', () {
    expect(
      DetectionTargetSelector.select([
        detection('television', .99, const Rect.fromLTWH(0, 0, .1, .1)),
      ]),
      isNull,
    );
  });

  test('mesma classe em posições diferentes exige novas confirmações', () {
    final stabilizer = DetectionStabilizer();
    final a = detection('battery', .8, const Rect.fromLTWH(.2, .2, .15, .2));
    final b = detection('battery', .8, const Rect.fromLTWH(.65, .6, .15, .2));
    expect(stabilizer.add(a), isNull);
    expect(stabilizer.add(b), isNull);
    expect(stabilizer.add(b), b);
  });

  test('objeto desaparecido não mantém classificação e reset limpa votos', () {
    final stabilizer = DetectionStabilizer();
    final a = detection('battery', .8, const Rect.fromLTWH(.3, .3, .2, .2));
    stabilizer.add(a);
    expect(stabilizer.add(a), a);
    expect(stabilizer.add(null), isNull);
    expect(stabilizer.add(null), isNull);
    expect(stabilizer.add(a), isNull);
    stabilizer.reset();
    expect(stabilizer.add(a), isNull);
  });
}
