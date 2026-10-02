import 'dart:typed_data';

import 'waste_classifier.dart';

Future<void> warmupWebScanner() async {}
void setWebPreviewBrightness(double value) {}
Future<Uint8List> prepareWebImage(Uint8List bytes, {int maxSize = 960, double brightness = 1}) async => bytes;
Future<List<LabelCandidate>> classifyWebImage(Uint8List bytes, {bool live = false}) async =>
    const <LabelCandidate>[];
