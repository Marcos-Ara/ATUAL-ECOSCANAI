import 'dart:io';

import 'package:ecoscan_mobile/models/object_detection.dart';
import 'package:ecoscan_mobile/services/scan_service.dart';
import 'package:ecoscan_mobile/services/supabase_material_resolver.dart';
import 'package:ecoscan_mobile/services/waste_classifier.dart';
import 'package:ecoscan_mobile/services/yolo_backend_contract.dart';
import 'package:ecoscan_mobile/services/yolo_model_repository.dart';
import 'package:ecoscan_mobile/services/yolo_model_repository_contract.dart';
import 'package:ecoscan_mobile/services/yolo_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

class NoRemoteModel implements YoloModelRepositoryPlatform {
  @override
  Future<String?> resolvePreferredModel() async => null;
}

class FakeBackend implements YoloBackend {
  @override
  final modelName = 'ecoscan_yoloe26n_w8a32.tflite';
  @override
  bool isReady = false;
  List<ObjectDetection> objects = [];
  @override
  Future<bool> load() async => isReady = true;
  @override
  Future<List<ObjectDetection>> detect(Uint8List bytes) async => objects;
  @override
  Future<void> close() async {
    isReady = false;
  }
}

class CountingResolver extends SupabaseMaterialResolver {
  int calls = 0;
  @override
  Future<WasteClassification?> resolve(List<LabelCandidate> candidates) async {
    calls++;
    return null;
  }
}

ObjectDetection object(String label) => ObjectDetection(
  label: label,
  confidence: .8,
  normalizedBox: const Rect.fromLTWH(.3, .2, .3, .5),
  backend: 'yoloe-26n',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory folder;
  late File image;
  late FakeBackend backend;
  late CountingResolver resolver;
  late ScanService scanner;
  int mlKitCalls = 0;

  setUp(() async {
    folder = await Directory.systemTemp.createTemp('ecoscan_yolo_pipeline_');
    image = File('${folder.path}/source.jpg');
    await image.writeAsBytes(
      img.encodeJpg(img.Image(width: 1600, height: 800)),
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => folder.path,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('google_mlkit_image_labeler'),
      (_) async {
        mlKitCalls++;
        return [
          {'text': 'Television', 'confidence': .99, 'index': 0},
        ];
      },
    );
    backend = FakeBackend();
    resolver = CountingResolver();
    mlKitCalls = 0;
    scanner = ScanService(
      yolo: YoloService(
        backendFactory: (_) => backend,
        modelRepository: YoloModelRepository(implementation: NoRemoteModel()),
      ),
      resolver: resolver,
    );
  });
  tearDown(() async {
    await scanner.close();
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('google_mlkit_image_labeler'),
      null,
    );
    await folder.delete(recursive: true);
  });

  test(
    'duas leituras confirmam YOLOE sem ML Kit substituir seu material',
    () async {
      backend.objects = [object('plastic bottle')];
      final first = await scanner.analyzeFile(XFile(image.path), live: true);
      expect(first.selectedDetection, isNull);
      expect(first.classification.isKnown, isFalse);
      final second = await scanner.analyzeFile(XFile(image.path), live: true);
      expect(second.classification.material?.id, 'plastic');
      expect(second.classification.detectedObject, 'Garrafa plástica');
      expect(second.detector, 'yoloe-26n');
      expect(img.decodeJpg(second.imageBytes)!.width, 640);
      expect(mlKitCalls, 0);
      expect(resolver.calls, 0);
      backend.objects = [];
      final empty = await scanner.analyzeFile(XFile(image.path), live: true);
      expect(empty.classification.isKnown, isFalse);
      expect(empty.selectedDetection, isNull);
      expect(mlKitCalls, 0);
    },
  );

  test(
    'label inconclusivo usa RPC só na foto, nunca no frame ao vivo',
    () async {
      backend.objects = [object('unmapped object')];
      await scanner.analyzeFile(XFile(image.path), live: true);
      await scanner.analyzeFile(XFile(image.path), live: true);
      expect(resolver.calls, 0);
      await scanner.analyzeFile(XFile(image.path));
      expect(resolver.calls, 1);
    },
  );

  test(
    'foto confirma diretamente e reset ao vivo exige consenso novamente',
    () async {
      backend.objects = [object('battery')];
      final photo = await scanner.analyzeFile(XFile(image.path));
      expect(photo.classification.material?.id, 'special');
      await scanner.analyzeFile(XFile(image.path), live: true);
      final confirmed = await scanner.analyzeFile(
        XFile(image.path),
        live: true,
      );
      expect(confirmed.classification.material?.id, 'special');
      scanner.resetLiveSession();
      final newSession = await scanner.analyzeFile(
        XFile(image.path),
        live: true,
      );
      expect(newSession.selectedDetection, isNull);
    },
  );
}
