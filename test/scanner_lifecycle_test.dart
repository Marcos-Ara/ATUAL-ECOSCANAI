import 'dart:async';
import 'dart:typed_data';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:ecoscan_mobile/screens/scanner_screen.dart';
import 'package:ecoscan_mobile/services/scan_service.dart';
import 'package:ecoscan_mobile/services/waste_classifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeCamera extends CameraPlatform {
  int captures = 0;
  int releases = 0;
  final errors = StreamController<CameraErrorEvent>.broadcast();
  @override
  Future<List<CameraDescription>> availableCameras() async => [
    const CameraDescription(name: 'test-back', lensDirection: CameraLensDirection.back, sensorOrientation: 90),
  ];
  @override
  Future<int> createCameraWithSettings(CameraDescription description, MediaSettings settings) async => 1;
  @override
  Future<void> initializeCamera(int cameraId, {ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown}) async {}
  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
    Stream.value(CameraInitializedEvent(cameraId, 640, 480, ExposureMode.auto, false, FocusMode.auto, false));
  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) => errors.stream;
  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() => const Stream.empty();
  @override
  Widget buildPreview(int cameraId) => const ColoredBox(color: Colors.grey);
  @override
  Future<XFile> takePicture(int cameraId) async {
    captures++;
    return XFile.fromData(Uint8List(0), name: 'synthetic-camera.jpg');
  }
  @override
  Future<void> dispose(int cameraId) async { releases++; }
}

class ControlledScan extends ScanService {
  final requests = <Completer<ScanResult>>[];
  bool closed = false;
  @override
  Future<void> warmup() async {}
  @override
  Future<ScanResult> analyzeFile(XFile file, {bool live = false, double brightness = 1}) {
    final result = Completer<ScanResult>();
    requests.add(result);
    return result.future;
  }
  void finish(int index) => requests[index].complete(ScanResult(
    imagePath: '', imageBytes: Uint8List(0),
    classification: WasteClassifier.classifyCandidates(const [LabelCandidate('computer', .88)]),
  ));
  @override
  Future<void> close() async { closed = true; }
}

void main() {
  testWidgets('live não sobrepõe leituras e descarta análise pausada', (tester) async {
    final previous = CameraPlatform.instance;
    final camera = FakeCamera();
    final scan = ControlledScan();
    CameraPlatform.instance = camera;
    addTearDown(() { CameraPlatform.instance = previous; });
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ScannerScreen(scanner: scan))));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 900));
    expect(camera.captures, 1);
    expect(scan.requests, hasLength(1));
    await tester.pump(const Duration(seconds: 5));
    expect(scan.requests, hasLength(1), reason: 'Não pode sobrepor inferências');
    await tester.tap(find.byType(FilterChip));
    await tester.pump();
    expect(find.text('Foto'), findsOneWidget);
    scan.finish(0);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Computador'), findsNothing, reason: 'Resultado antigo não deve aparecer');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);
  });
}
