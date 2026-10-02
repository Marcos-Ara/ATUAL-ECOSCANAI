import 'dart:io';

import 'package:ecoscan_mobile/services/scan_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory temporary;
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('ecoscan_scan_test_');
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => temporary.path,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('google_mlkit_image_labeler'),
      (call) async {
        if (call.method == 'vision#closeImageLabelDetector') return null;
        final data = (call.arguments as Map)['imageData'] as Map;
        expect(await File(data['path'] as String).exists(), isTrue);
        return [
          {'text': 'Plastic bottle', 'confidence': .93, 'index': 1},
        ];
      },
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('google_mlkit_object_detector'),
      (_) async => null,
    );
  });
  tearDown(() async {
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('google_mlkit_image_labeler'),
      null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('google_mlkit_object_detector'),
      null,
    );
    await temporary.delete(recursive: true);
  });
  test(
    'normaliza a imagem da câmera/galeria e entrega material e lixeira',
    () async {
      final input = File('${temporary.path}/source.png');
      await input.writeAsBytes(
        img.encodePng(img.Image(width: 1800, height: 900)),
      );
      final scanner = ScanService();
      final result = await scanner.analyze(input.path);
      final output = img.decodeJpg(await File(result.imagePath).readAsBytes())!;
      expect(output.width, 1440);
      expect(output.height, 720);
      expect(result.classification.category, 'Plástico');
      expect(result.classification.bin, 'Vermelha');
      expect(await input.exists(), isTrue);
      await scanner.close();
    },
  );
  test('foto inválida não cria resultado falso', () async {
    final input = File('${temporary.path}/invalid.jpg')
      ..writeAsStringSync('not an image');
    final scanner = ScanService();
    await expectLater(
      scanner.analyze(input.path),
      throwsA(isA<FormatException>()),
    );
    await scanner.close();
  });
}
