import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../core/app_config.dart';
import '../core/app_theme.dart';
import '../models/detection_record.dart';
import '../models/learning_sample.dart';
import '../models/object_detection.dart';
import '../services/auth_session.dart';
import '../services/scan_service.dart';
import '../services/scan_sync_service.dart';
import '../services/waste_classifier.dart';
import '../services/web_image_labeler.dart';
import '../state/eco_point_controller.dart';
import '../state/ecoscan_store.dart';
import '../widgets/live_yolo_camera.dart';
import 'correction_report_dialog.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({this.scanner, this.onFindNearby, super.key});
  final ScanService? scanner;
  final ValueChanged<WasteClassification>? onFindNearby;
  @override
  State<ScannerScreen> createState() => ScannerScreenState();
}

class ScannerScreenState extends State<ScannerScreen>
    with WidgetsBindingObserver {
  late final _scanner = widget.scanner ?? ScanService();
  final _picker = ImagePicker();
  final _liveYoloController = LiveYoloCameraController();
  static const _liveYoloModel = String.fromEnvironment(
    'ECOSCAN_YOLO_MODEL',
    defaultValue: 'assets/models/ecoscan_yoloe26n_w8a32.tflite',
  );

  // O modelo incluído nesta base é LiteRT/TFLite para Android. iOS continua
  // no fluxo anterior até recebermos o equivalente Core ML.
  bool get _useNativeYoloView => !kIsWeb && Platform.isAndroid;

  CameraController? _camera;
  List<CameraDescription> _cameras = [];
  Future<void> _cameraQueue = Future.value();
  Future<void>? _scanTask;
  Timer? _liveTimer;
  bool _active = true;
  bool _selecting = false;
  bool _loading = true;
  bool _busy = false;
  bool _manualCaptureInProgress = false;
  bool _live = true;
  bool _flash = false;
  bool _saved = false;
  bool _saving = false;
  bool _preparingAi = true;
  double _brightness = 1.2;
  double _maxExposure = 0;
  double _zoom = 1;
  double _minZoom = 1;
  double _maxZoom = 3;
  bool _hardwareZoom = false;
  double get _previewScale => _hardwareZoom ? 1 : _zoom;
  bool _adjustingLight = false;
  int _revision = 0;
  int _cameraIndex = 0;
  int _liveFailures = 0;
  String? _cameraError;
  String? _scanError;
  String? _photoPath;
  Uint8List? _photoBytes;
  String _source = 'camera';
  WasteClassification? _result;
  List<ObjectDetection> _detections = const [];
  ObjectDetection? _selectedDetection;
  String _detector = 'unknown';
  bool _liveModelReady = false;
  bool _processingLiveDetections = false;
  bool _returnToLiveRequested = false;
  int _nativeEmptyFrames = 0;
  double? _liveFps;
  double? _liveInferenceMs;
  int? _liveClassIndex;
  DateTime? _lastMetricsUpdate;
  _LiveSnapshot? _lastKnownLiveSnapshot;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_warmup());
    unawaited(_boot());
  }

  Future<void> _warmup() async {
    try {
      if (_useNativeYoloView) {
        // YOLOView carrega o modelo da câmera nativamente. Aqui preparamos só
        // o catálogo local para nenhum frame depender de rede.
        await _scanner.prepareLocalCatalog();
      } else {
        await _scanner.warmup();
      }
    } catch (_) {
      // Foto/galeria ainda podem tentar carregar o modelo sob demanda.
    } finally {
      if (mounted && !_useNativeYoloView) {
        setState(() => _preparingAi = false);
        _scheduleLive();
      }
    }
  }

  void showLiveScanner() {
    if (!mounted) return;
    if (_busy || _saving || _selecting) {
      _returnToLiveRequested = true;
      return;
    }
    if (_live) return;
    final oldPhoto = _photoPath;
    setState(() {
      _live = true;
      _photoPath = null;
      _photoBytes = null;
      _result = null;
      _detections = const [];
      _selectedDetection = null;
      _detector = 'unknown';
      _saved = false;
      _scanError = null;
      _nativeEmptyFrames = 0;
      _liveClassIndex = null;
      _lastKnownLiveSnapshot = null;
      _revision++;
      if (_useNativeYoloView) {
        _liveModelReady = false;
        _preparingAi = true;
      }
    });
    if (oldPhoto != null) unawaited(_deleteTemp(oldPhoto));
    _scanner.resetLiveSession();
    if (_useNativeYoloView) {
      unawaited(_resumeNativeLiveCamera());
    } else if (_camera?.value.isInitialized != true) {
      unawaited(_openCamera());
    } else {
      _scheduleLive();
    }
  }

  void _applyQueuedLiveReturn() {
    if (!_returnToLiveRequested ||
        !mounted ||
        _busy ||
        _saving ||
        _selecting) {
      return;
    }
    _returnToLiveRequested = false;
    showLiveScanner();
  }

  Future<void> _boot() async {
    // Android may kill the process while its gallery picker is open.
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final lost = await _picker.retrieveLostData();
        if (!mounted) return;
        if (lost.files?.isNotEmpty == true) {
          _live = false;
          await _analyzeFile(lost.files!.first, fromGallery: true);
        } else if (lost.exception != null) {
          setState(
            () => _scanError =
                'Não foi possível recuperar a foto. Selecione-a novamente.',
          );
        }
      } catch (_) {}
    }
    if (!mounted) return;
    if (_useNativeYoloView) {
      setState(() => _loading = false);
    } else {
      await _openCamera();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _active = true;
      if (!_selecting) {
        if (_useNativeYoloView) {
          unawaited(_resumeNativeLiveCamera());
        } else {
          unawaited(_openCamera());
        }
      }
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _active = false;
      _revision++;
      _liveTimer?.cancel();
      if (_useNativeYoloView) {
        unawaited(_pauseNativeLiveCamera());
      } else {
        unawaited(_releaseCamera());
      }
    }
  }

  Future<void> _pauseNativeLiveCamera() async {
    try {
      await _liveYoloController.pause();
    } catch (_) {}
  }

  Future<void> _resumeNativeLiveCamera() async {
    if (!_active || _selecting || !_live) return;
    try {
      await _liveYoloController.resume();
    } catch (_) {}
  }

  Future<void> _releaseCamera() {
    _cameraQueue = _cameraQueue.then((_) async {
      final scan = _scanTask;
      if (scan != null) {
        try {
          await scan;
        } catch (_) {}
      }
      final camera = _camera;
      _camera = null;
      if (camera != null) {
        try {
          await camera.dispose();
        } catch (_) {}
      }
    });
    return _cameraQueue;
  }

  Future<void> _openCamera({bool switchLens = false}) {
    if (_useNativeYoloView) {
      if (mounted) setState(() => _loading = false);
      return Future.value();
    }
    final request = ++_revision;
    _liveTimer?.cancel();
    _cameraQueue = _cameraQueue.then((_) async {
      if (!mounted || !_active || _selecting) return;
      setState(() {
        _loading = true;
        _cameraError = null;
      });
      try {
        if (_scanTask != null) await _scanTask;
        if (_cameras.isEmpty) {
          _cameras = await availableCameras();
          final back = _cameras.indexWhere(
            (c) => c.lensDirection == CameraLensDirection.back,
          );
          _cameraIndex = back < 0 ? 0 : back;
        } else if (switchLens && _cameras.length > 1) {
          _cameraIndex = (_cameraIndex + 1) % _cameras.length;
        }
        if (_cameras.isEmpty) {
          throw CameraException('NoCamera', 'Nenhuma câmera encontrada.');
        }
        final previous = _camera;
        _camera = null;
        await previous?.dispose();
        if (!mounted || !_active || request != _revision) return;
        final camera = CameraController(
          _cameras[_cameraIndex],
          ResolutionPreset.high,
          enableAudio: false,
        );
        _camera = camera;
        await camera.initialize();
        if (!mounted || !_active || request != _revision) {
          _camera = null;
          await camera.dispose();
          return;
        }
        if (kIsWeb) {
          _minZoom = 1;
          _maxZoom = 3;
          _zoom = _zoom.clamp(_minZoom, _maxZoom).toDouble();
          _hardwareZoom = false;
        } else {
          try {
            _minZoom = await camera.getMinZoomLevel();
            _maxZoom = await camera.getMaxZoomLevel();
            _zoom = _zoom.clamp(_minZoom, _maxZoom).toDouble();
            try {
              await camera.setZoomLevel(_zoom);
              _hardwareZoom = true;
            } catch (_) {
              _hardwareZoom = false;
            }
          } catch (_) {
            _minZoom = 1;
            _maxZoom = 1;
            _zoom = _zoom.clamp(_minZoom, _maxZoom).toDouble();
            _hardwareZoom = false;
          }
        }
        if (!kIsWeb) {
          try {
            await camera.setFocusMode(FocusMode.auto);
          } catch (_) {}
          try {
            await camera.setExposureMode(ExposureMode.auto);
            _maxExposure = await camera.getMaxExposureOffset();
            if (_maxExposure > 0) {
              await camera.setExposureOffset(((_brightness - 1) * 2).clamp(0, _maxExposure));
            }
          } catch (_) {}
          try {
            await camera.setFlashMode(FlashMode.off);
          } catch (_) {}
        }
        if (!mounted || !_active || request != _revision) return;
        setState(() {
          _loading = false;
          _flash = false;
        });
        if (kIsWeb) setWebPreviewBrightness(_brightness);
        _scheduleLive();
      } on CameraException catch (error) {
        if (mounted) {
          setState(() {
            _loading = false;
            _cameraError = error.code.toLowerCase().contains('denied')
                ? (kIsWeb
                      ? 'Permita a câmera nas permissões deste site no navegador. Você também pode selecionar uma foto.'
                      : 'Permita a câmera nas configurações do celular. Você também pode selecionar uma foto.')
                : 'Não foi possível abrir a câmera. Tente novamente ou escolha uma foto.';
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            _loading = false;
            _cameraError = 'A câmera não respondeu. Tente novamente.';
          });
        }
      }
    });
    return _cameraQueue;
  }

  void _scheduleLive() {
    _liveTimer?.cancel();
    if (_useNativeYoloView) return;
    if (!_scanner.supportsAutomaticLabeling ||
        !_live ||
        !_active ||
        !mounted ||
        _selecting ||
        _saving) {
      return;
    }
    _liveTimer = Timer(const Duration(milliseconds: 650), () {
      if (!_busy && !_preparingAi && _camera?.value.isInitialized == true) {
        unawaited(_capture(automatic: true));
      } else {
        _scheduleLive();
      }
    });
  }

  Future<void> _capture({bool automatic = false}) async {
    if (_useNativeYoloView) {
      if (!automatic) await _captureNativeStill();
      return;
    }
    if (_busy ||
        _saving ||
        _selecting ||
        !_active ||
        _camera?.value.isInitialized != true) {
      return;
    }
    _liveTimer?.cancel();
    final request = _revision;
    setState(() {
      _busy = true;
      _manualCaptureInProgress = !automatic;
      _scanError = null;
    });
    final operation = _captureWork(request, automatic);
    _scanTask = operation;
    try {
      await operation;
    } finally {
      _scanTask = null;
      if (mounted) {
        setState(() {
          _busy = false;
          _manualCaptureInProgress = false;
        });
      }
      _applyQueuedLiveReturn();
      _scheduleLive();
    }
  }

  Future<void> _captureNativeStill() async {
    if (_busy || _saving || _selecting || !_active || !_liveModelReady) return;
    final liveFallback = _freshLiveFallback();
    var resumeCameraInFinally = true;
    setState(() {
      _busy = true;
      _manualCaptureInProgress = true;
      _scanError = null;
    });
    String? rawPath;
    try {
      // Primeiro captura o frame enquanto a câmera está ativa. Depois pausamos o
      // stream durante a inferência única para não disputar GPU com o YOLOView.
      final bytes = await _liveYoloController.capturePhoto(withOverlays: false);
      if (bytes == null || bytes.isEmpty) {
        throw const FormatException('Não foi possível capturar a imagem da câmera.');
      }
      final temp = await getTemporaryDirectory();
      rawPath = p.join(
        temp.path,
        'ecoscan_live_capture_${DateTime.now().microsecondsSinceEpoch}.jpg',
      );
      await File(rawPath).writeAsBytes(bytes, flush: true);
      await _pauseNativeLiveCamera();
      final analysis = _withLiveFallback(
        await _scanner.analyzeFile(XFile(rawPath)),
        liveFallback,
      );
      if (!mounted) {
        await _deleteTemp(analysis.imagePath);
        return;
      }
      await _accept(analysis, fromGallery: false);
      if (mounted && _active && _live) {
        await _resumeNativeLiveCamera();
        resumeCameraInFinally = false;
      }
      await _showCaptureResult(analysis);
    } catch (error) {
      if (mounted) setState(() => _scanError = _errorText(error));
    } finally {
      if (rawPath != null) await _deleteTemp(rawPath);
      if (resumeCameraInFinally && mounted && _active && _live) {
        unawaited(_resumeNativeLiveCamera());
      }
      if (mounted) {
        setState(() {
          _busy = false;
          _manualCaptureInProgress = false;
        });
      }
      _applyQueuedLiveReturn();
    }
  }

  Future<void> _showCaptureResult(ScanResult analysis) async {
    if (!mounted) return;
    final result = analysis.classification;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          result.isKnown ? 'Resultado da foto' : 'Foto analisada',
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420, maxHeight: 540),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (analysis.imageBytes.isNotEmpty) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.memory(
                      analysis.imageBytes,
                      height: 180,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const SizedBox(
                        height: 100,
                        child: Center(child: Icon(Icons.broken_image_outlined)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                _MaterialResult(result: result),
                const SizedBox(height: 12),
                const Text(
                  'Ao continuar, você volta para a leitura ao vivo.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop(),
            icon: const Icon(Icons.center_focus_strong),
            label: const Text('Continuar escaneando'),
          ),
        ],
      ),
    );
  }

  Future<void> _onNativeLiveResults(List<LiveYoloDetection> raw) async {
    if (!_useNativeYoloView ||
        !_live ||
        !_active ||
        _selecting ||
        _saving ||
        _busy ||
        _processingLiveDetections) {
      return;
    }
    _processingLiveDetections = true;
    try {
      final detections = raw
          .map(
            (item) => ObjectDetection(
              label: item.className,
              confidence: item.confidence.clamp(0.0, 1.0).toDouble(),
              normalizedBox: item.normalizedBox,
              backend: 'yoloe-26n-live',
              classIndex: item.classIndex,
            ),
          )
          .where((item) => item.isValid)
          .toList(growable: false);
      final analysis = await _scanner.analyzeLiveDetections(detections);
      if (!mounted || !_live || !_active) return;

      final stable = analysis.selectedDetection;
      setState(() {
        _detections = analysis.detections;
        _detector = 'yoloe-26n-live';
        if (stable != null) {
          _nativeEmptyFrames = 0;
          _selectedDetection = stable;
          _liveClassIndex = stable.classIndex;
          _result = analysis.classification;
          if (analysis.classification.isKnown) {
            _lastKnownLiveSnapshot = _LiveSnapshot(
              classification: analysis.classification,
              detections: analysis.detections,
              selectedDetection: stable,
              detector: 'yoloe-26n-live',
              capturedAt: DateTime.now(),
            );
          } else {
            _lastKnownLiveSnapshot = null;
          }
          _saved = false;
          _scanError = null;
        } else if (detections.isEmpty) {
          _nativeEmptyFrames++;
          if (_nativeEmptyFrames >= 2) {
            _lastKnownLiveSnapshot = null;
            _selectedDetection = null;
            _liveClassIndex = null;
            _result = null;
          }
        } else {
          _lastKnownLiveSnapshot = null;
        }
      });
    } catch (_) {
      // Um frame ruim não derruba o scanner; o próximo frame tenta novamente.
    } finally {
      _processingLiveDetections = false;
    }
  }

  void _onNativeMetrics(LiveYoloMetrics metrics) {
    final now = DateTime.now();
    final previous = _lastMetricsUpdate;
    if (previous != null && now.difference(previous).inMilliseconds < 450) {
      return;
    }
    _lastMetricsUpdate = now;
    if (!mounted) return;
    setState(() {
      _liveFps = metrics.fps;
      _liveInferenceMs = metrics.processingTimeMs;
    });
  }

  void _onNativeModelLoad() {
    if (!mounted) return;
    setState(() {
      _liveModelReady = true;
      _preparingAi = false;
      _cameraError = null;
    });
  }

  void _onNativeModelError(String error) {
    if (!mounted) return;
    setState(() {
      _liveModelReady = false;
      _preparingAi = false;
      _cameraError =
          'O YOLO-E não carregou. Feche e abra o scanner novamente. ($error)';
    });
  }

  Future<void> _switchNativeCamera() async {
    if (_busy || !_liveModelReady) return;
    try {
      await _liveYoloController.switchCamera();
      if (mounted) setState(() => _flash = false);
    } catch (_) {
      if (mounted) _notice('Não foi possível trocar a câmera.');
    }
  }

  Future<void> _captureWork(int request, bool automatic) async {
    final liveFallback = automatic ? null : _freshLiveFallback();
    XFile? photo;
    try {
      final camera = _camera!;
      photo = await camera.takePicture();
      if (camera.value.isPreviewPaused) {
        try {
          await camera.resumePreview();
        } catch (_) {}
      }
      final analysis = _withLiveFallback(
        await _scanner.analyzeFile(photo, live: automatic, brightness: _brightness),
        liveFallback,
      );
      if (!mounted || request != _revision || !_active) {
        await _deleteTemp(analysis.imagePath);
        return;
      }
      _liveFailures = 0;
      await _accept(
        analysis,
        fromGallery: false,
        liveFrame: automatic,
      );
      if (!automatic) await _showCaptureResult(analysis);
    } catch (error) {
      if (!mounted || request != _revision) return;
      _liveFailures++;
      setState(() {
        _scanError = _errorText(error);
        if (automatic && _liveFailures >= 3) _live = false;
      });
    } finally {
      if (photo != null && !kIsWeb) {
        try {
          await File(photo.path).delete();
        } catch (_) {}
      }
    }
  }

  Future<void> _analyzeFile(
    XFile file, {
    required bool fromGallery,
  }) async {
    if (_busy || !mounted) return;
    final request = ++_revision;
    setState(() {
      _busy = true;
      _scanError = null;
      _live = false;
    });
    final operation = () async {
      try {
        final analysis = await _scanner.analyzeFile(file);
        if (!mounted || request != _revision) {
          await _deleteTemp(analysis.imagePath);
          return;
        }
        await _accept(
          analysis,
          fromGallery: fromGallery,
        );
      } catch (error) {
        if (mounted) setState(() => _scanError = _errorText(error));
      }
    }();
    _scanTask = operation;
    try {
      await operation;
    } finally {
      _scanTask = null;
      if (mounted) setState(() => _busy = false);
      _applyQueuedLiveReturn();
    }
  }

  Future<void> _accept(
    ScanResult result, {
    required bool fromGallery,
    bool liveFrame = false,
  }) async {
    final previous = _photoPath;
    final source = fromGallery ? 'gallery' : 'camera';
    setState(() {
      _photoPath = result.imagePath;
      _photoBytes = result.imageBytes;
      _result = result.classification;
      _source = source;
      _detections = result.detections;
      _selectedDetection = result.selectedDetection;
      _detector = result.detector;
      _saved = false;
      _scanError = null;
    });
    if (liveFrame && result.classification.isKnown) {
      _lastKnownLiveSnapshot = _LiveSnapshot(
        classification: result.classification,
        detections: result.detections,
        selectedDetection: result.selectedDetection,
        detector: result.detector,
        capturedAt: DateTime.now(),
      );
    } else if (liveFrame) {
      _lastKnownLiveSnapshot = null;
    }
    if (previous != null && previous != result.imagePath) {
      await _deleteTemp(previous);
    }
  }

  _LiveSnapshot? _freshLiveFallback() {
    final snapshot = _lastKnownLiveSnapshot;
    if (!_live ||
        snapshot == null ||
        DateTime.now().difference(snapshot.capturedAt) >
            const Duration(seconds: 2)) {
      return null;
    }
    return snapshot;
  }

  ScanResult _withLiveFallback(ScanResult still, _LiveSnapshot? fallback) {
    if (still.classification.isKnown || fallback == null) return still;
    return ScanResult(
      imagePath: still.imagePath,
      imageBytes: still.imageBytes,
      classification: fallback.classification,
      detections: fallback.detections.isEmpty
          ? still.detections
          : fallback.detections,
      selectedDetection: fallback.selectedDetection ?? still.selectedDetection,
      detector: fallback.detector,
    );
  }

  Future<void> _reportCorrection() async {
    if (_busy || _saving || _selecting || !mounted) return;
    final wasLive = _live;
    final original =
        _selectedDetection ??
        _lastKnownLiveSnapshot?.selectedDetection ??
        (_detections.isEmpty
            ? null
            : _detections.reduce(
                (a, b) => a.confidence >= b.confidence ? a : b,
              ));
    final currentResult = _result;
    Uint8List? imageBytes;
    String? temporaryPhotoPath;
    setState(() {
      _busy = true;
      _scanError = null;
    });
    _liveTimer?.cancel();
    try {
      if (!wasLive && _photoBytes != null) {
        imageBytes = _photoBytes;
      } else if (_useNativeYoloView) {
        imageBytes = await _liveYoloController.capturePhoto(withOverlays: false);
        await _pauseNativeLiveCamera();
      } else {
        final camera = _camera;
        if (camera?.value.isInitialized == true) {
          final photo = await camera!.takePicture();
          temporaryPhotoPath = photo.path;
          imageBytes = await photo.readAsBytes();
          if (camera.value.isPreviewPaused) {
            try {
              await camera.resumePreview();
            } catch (_) {}
          }
        } else {
          imageBytes = _photoBytes;
        }
      }
      final capturedImageBytes = imageBytes;
      if (capturedImageBytes == null || capturedImageBytes.isEmpty) {
        throw const FormatException(
          'Não foi possível capturar a imagem para a correção.',
        );
      }
      if (!mounted) return;
      final store = context.read<EcoScanStore>();
      final report = await showDialog<CorrectionReport>(
        context: context,
        builder: (_) => CorrectionReportDialog(
          imageBytes: capturedImageBytes,
          originalLabel: original?.label ??
              currentResult?.detectionLabel ??
              currentResult?.detectedObject,
          originalConfidence: original?.confidence ??
              (currentResult?.isKnown == true
                  ? currentResult!.confidence
                  : null),
          aiDetected: original != null || currentResult?.isKnown == true,
        ),
      );
      if (report == null || !mounted) return;
      final thumbnail = await _scanner.learningThumbnailDataUrl(
        capturedImageBytes,
      );
      if (!mounted) return;
      await store.addLearningSample(
        LearningSample(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          createdAt: DateTime.now(),
          source: wasLive ? 'camera' : _source,
          detector: _detector,
          thumbnailDataUrl: thumbnail,
          detections: _detections
              .map((item) => <String, dynamic>{
                    'label': item.label,
                    'confidence': item.confidence,
                    'left': item.normalizedBox.left,
                    'top': item.normalizedBox.top,
                    'right': item.normalizedBox.right,
                    'bottom': item.normalizedBox.bottom,
                    'backend': item.backend,
                  })
              .toList(growable: false),
          reportedLabel: report.label,
          reportedBin: report.bin,
          reportNote: report.note,
          aiDetected: report.aiDetected,
          originalLabel: original?.label ??
              currentResult?.detectionLabel ??
              currentResult?.detectedObject,
          originalConfidence: original?.confidence ??
              (currentResult?.isKnown == true
                  ? currentResult!.confidence
                  : null),
        ),
      );
      if (mounted) {
        _notice(
          'Correção salva neste aparelho. Você pode enviar com consentimento em Configurações.',
        );
      }
    } catch (error) {
      if (mounted) {
        _notice(
          error is FormatException
              ? error.message
              : 'Não foi possível salvar a correção: $error',
        );
      }
    } finally {
      if (temporaryPhotoPath != null) await _deleteTemp(temporaryPhotoPath);
      if (mounted && wasLive && _active) {
        if (_useNativeYoloView) {
          unawaited(_resumeNativeLiveCamera());
        } else {
          _scheduleLive();
        }
      }
      if (mounted) setState(() => _busy = false);
      _applyQueuedLiveReturn();
    }
  }

  Future<void> _selectPhoto() async {
    if (_busy || _saving || _selecting) return;
    final wasLive = _live;
    setState(() {
      _selecting = true;
      _live = false;
      _scanError = null;
    });
    _revision++;
    _liveTimer?.cancel();
    if (_useNativeYoloView) {
      await _pauseNativeLiveCamera();
    } else {
      await _releaseCamera();
    }
    try {
      final photo = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1800,
        maxHeight: 1800,
        imageQuality: 94,
      );
      if (!mounted) return;
      if (photo != null) {
        await _analyzeFile(photo, fromGallery: true);
      } else if (mounted) {
        setState(() => _live = wasLive);
      }
    } on PlatformException {
      if (mounted) {
        setState(() {
          _live = wasLive;
          _scanError =
              'Não foi possível abrir a galeria. Confira a permissão de fotos.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _live = wasLive;
          _scanError = 'Não foi possível selecionar a foto.';
        });
      }
    } finally {
      _selecting = false;
      if (_returnToLiveRequested && mounted) {
        _returnToLiveRequested = false;
        showLiveScanner();
      } else if (mounted && _active) {
        if (_useNativeYoloView && _live) {
          unawaited(_resumeNativeLiveCamera());
        } else if (!_useNativeYoloView) {
          unawaited(_openCamera());
        }
      }
    }
  }

  Future<void> _toggleFlash() async {
    if (_useNativeYoloView) {
      if (_busy || !_liveModelReady) return;
      try {
        final next = !_flash;
        await _liveYoloController.setTorchMode(next);
        if (mounted) setState(() => _flash = next);
      } catch (_) {
        if (mounted) _notice('O flash não está disponível nesta câmera.');
      }
      return;
    }
    final camera = _camera;
    if (camera?.value.isInitialized != true || _busy) return;
    try {
      await camera!.setFlashMode(_flash ? FlashMode.off : FlashMode.torch);
      if (mounted) setState(() => _flash = !_flash);
    } catch (_) {
      if (mounted) _notice('O flash não está disponível nesta câmera.');
    }
  }

  Future<void> _setBrightness(double value) async {
    setState(() => _brightness = value);
    if (kIsWeb) {
      setWebPreviewBrightness(value);
    } else if (_camera?.value.isInitialized == true && _maxExposure > 0 && !_adjustingLight) {
      _adjustingLight = true;
      try {
        await _camera!.setExposureOffset(((value - 1) * 2).clamp(0, _maxExposure));
      } catch (_) {
        if (mounted) _notice('Esta câmera não permite ajustar a exposição.');
      } finally {
        _adjustingLight = false;
      }
    }
  }

  Future<void> _setZoom(double value) async {
    final next = value.clamp(_minZoom, _maxZoom).toDouble();
    if (mounted) setState(() => _zoom = next);
    final camera = _camera;
    if (!_useNativeYoloView && !kIsWeb && camera?.value.isInitialized == true) {
      try {
        await camera!.setZoomLevel(next);
        if (mounted) setState(() => _hardwareZoom = true);
      } catch (_) {
        if (mounted) setState(() => _hardwareZoom = false);
      }
    }
  }

  Future<void> _focus(TapDownDetails details, Size size) async {
    if (_useNativeYoloView) {
      if (!_liveModelReady || _busy) return;
      final x = (details.localPosition.dx / size.width).clamp(0.0, 1.0);
      final y = (details.localPosition.dy / size.height).clamp(0.0, 1.0);
      try {
        await _liveYoloController.tapToFocus(x, y);
      } catch (_) {}
      return;
    }
    if (kIsWeb) return;
    final camera = _camera;
    if (camera?.value.isInitialized != true || _busy) return;
    final point = Offset(
      (details.localPosition.dx / size.width).clamp(0, 1),
      (details.localPosition.dy / size.height).clamp(0, 1),
    );
    try {
      await camera!.setFocusPoint(point);
      await camera.setExposurePoint(point);
    } catch (_) {}
  }

  Future<void> _save() async {
    if (_saving ||
        _busy ||
        _saved ||
        _result?.isKnown != true ||
        (_photoPath == null && !_useNativeYoloView)) {
      return;
    }
    final store = context.read<EcoScanStore>();
    final uid = store.userId;
    if (uid == null) return;
    final result = _result!;
    var image = _photoPath;
    final location = _source == 'camera'
        ? context.read<EcoPointController>().userLocation
        : null;
    setState(() {
      _saving = true;
      _live = false;
    });
    _liveTimer?.cancel();
    String? savedPath;
    String? liveCapturePath;
    try {
      if (_useNativeYoloView && image == null) {
        final bytes = await _liveYoloController.capturePhoto(withOverlays: false);
        if (bytes == null || bytes.isEmpty) {
          throw const FormatException('Não foi possível capturar a imagem atual.');
        }
        final temp = await getTemporaryDirectory();
        liveCapturePath = p.join(
          temp.path,
          'ecoscan_history_${DateTime.now().microsecondsSinceEpoch}.jpg',
        );
        await File(liveCapturePath).writeAsBytes(bytes, flush: true);
        image = liveCapturePath;
        await _pauseNativeLiveCamera();
      }
      if (image == null) return;
      final now = DateTime.now();
      if (kIsWeb) {
        final bytes = _photoBytes;
        savedPath = bytes == null ? '' : await _scanner.historyDataUrl(bytes);
      } else {
        final documents = await getApplicationDocumentsDirectory();
        final folder = Directory(p.join(documents.path, 'ecoscan', uid, 'scans'));
        await folder.create(recursive: true);
        savedPath = p.join(folder.path, '${now.microsecondsSinceEpoch}.jpg');
        await File(image).copy(savedPath);
        if (!mounted || store.userId != uid) {
          await File(savedPath).delete();
          return;
        }
      }
      if (!mounted || store.userId != uid) return;
      final persistedImage = savedPath;
      final record = DetectionRecord(
        id: now.microsecondsSinceEpoch.toString(),
        name: result.name,
        category: result.category,
        bin: result.bin,
        destination: result.destination,
        confidence: result.confidence,
        imagePath: persistedImage,
        detectedAt: now,
        source: _source,
        confirmedByUser: result.isManual,
        latitude: location?.latitude,
        longitude: location?.longitude,
        detectedObject: result.detectedObject ?? _selectedDetection?.label,
        detector: _detector,
        objectId: result.objectId,
        variantId: result.variantId,
        detectionLabel: result.detectionLabel ?? _selectedDetection?.label,
        classIndex: result.classIndex ?? _selectedDetection?.classIndex,
      );

      await store.addDetection(record);

      var synced = false;
      if (uid != AuthSession.guestUserId && AppConfig.syncSupabaseHistory) {
        try {
          await ScanSyncService().upsert(record);
          synced = true;
        } catch (_) {
          // O histórico local continua salvo. O banco será ligado depois da
          // validação do scanner e da criação do schema definitivo.
        }
      }

      if (mounted) {
        setState(() => _saved = true);
        if (store.sounds) unawaited(SystemSound.play(SystemSoundType.click));
        if (store.notifications) {
          _notice(
            uid == AuthSession.guestUserId
                ? 'Análise salva neste aparelho.'
                : synced
                ? 'Análise salva no histórico e no banco de dados.'
                : 'Análise salva no histórico local.',
          );
        }
      }
    } catch (_) {
      if (!kIsWeb && savedPath != null && savedPath.isNotEmpty) {
        try {
          await File(savedPath).delete();
        } catch (_) {}
      }
      if (mounted) _notice('Não foi possível salvar. Tente novamente.');
    } finally {
      if (liveCapturePath != null) await _deleteTemp(liveCapturePath);
      if (mounted) setState(() => _saving = false);
      _applyQueuedLiveReturn();
    }
  }


  void _notice(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  static String _errorText(Object error) => error is FormatException
      ? error.message
      : 'A análise não terminou. Aproxime o material, melhore a luz e tente novamente.';
  static Future<void> _deleteTemp(String path) async {
    if (kIsWeb || path.isEmpty) return;
    try {
      await File(path).delete();
    } catch (_) {}
  }

  @override
  void dispose() {
    _active = false;
    _revision++;
    _liveTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    if (_useNativeYoloView) unawaited(_pauseNativeLiveCamera());
    unawaited(
      _releaseCamera().then((_) async {
        await _scanner.close();
        final photo = _photoPath;
        if (photo != null) await _deleteTemp(photo);
      }),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final camera = _camera;
    final captureReady = _useNativeYoloView
        ? _liveModelReady
        : camera?.value.isInitialized == true;
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return ListView(
            padding: EdgeInsets.zero,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 10, 12),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Scanner',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    FilterChip(
                      label: Text(_live ? '● AO VIVO' : 'Foto'),
                      selected: _live,
                      onSelected: _saving
                          ? null
                          : (_) {
                              final live = !_live;
                              final hadPhoto = live && _photoBytes != null;
                              final oldPhoto = live ? _photoPath : null;
                              setState(() {
                                _live = live;
                                _scanError = null;
                                _liveFailures = 0;
                                _revision++;
                                if (live) {
                                  _photoPath = null;
                                  _photoBytes = null;
                                  _result = null;
                                  _detections = const [];
                                  _selectedDetection = null;
                                  _detector = 'unknown';
                                  _lastKnownLiveSnapshot = null;
                                  _nativeEmptyFrames = 0;
                                  _liveClassIndex = null;
                                  _saved = false;
                                  if (_useNativeYoloView && hadPhoto) {
                                    _liveModelReady = false;
                                    _preparingAi = true;
                                  }
                                }
                              });
                              if (oldPhoto != null) {
                                unawaited(_deleteTemp(oldPhoto));
                              }
                              if (live) {
                                _scanner.resetLiveSession();
                                if (_useNativeYoloView) {
                                  unawaited(_resumeNativeLiveCamera());
                                } else {
                                  _scheduleLive();
                                }
                              } else {
                                _liveTimer?.cancel();
                                if (_useNativeYoloView) {
                                  unawaited(_pauseNativeLiveCamera());
                                }
                              }
                            },
                    ),
                    IconButton(
                      tooltip: 'Flash',
                      onPressed: _busy ? null : _toggleFlash,
                      icon: Icon(_flash ? Icons.flash_on : Icons.flash_off),
                    ),
                    IconButton(
                      tooltip: 'Trocar câmera',
                      onPressed: _busy
                          ? null
                          : _useNativeYoloView
                          ? (_liveModelReady ? _switchNativeCamera : null)
                          : (_cameras.length < 2
                                ? null
                                : () => _openCamera(switchLens: true)),
                      icon: const Icon(Icons.cameraswitch_outlined),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: (constraints.maxHeight * 0.68).clamp(380.0, 620.0),
                child: ColoredBox(
                  color: Colors.black,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (!_live && _photoBytes != null)
                        Image.memory(
                          _photoBytes!,
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                          errorBuilder: (_, _, _) => const Icon(
                            Icons.image_outlined,
                            color: Colors.white,
                          ),
                        )
                      else if (_useNativeYoloView)
                        LayoutBuilder(
                          builder: (context, box) => Stack(
                            fit: StackFit.expand,
                            children: [
                              Transform.scale(
                                scale: _previewScale,
                                child: LiveYoloCamera(
                                  key: ValueKey('yolo-live-$_revision'),
                                  modelPath: _liveYoloModel,
                                  controller: _liveYoloController,
                                  confidenceThreshold: 0.25,
                                  iouThreshold: 0.50,
                                  onResult: (items) {
                                    unawaited(_onNativeLiveResults(items));
                                  },
                                  onPerformanceMetrics: _onNativeMetrics,
                                  onModelLoad: _onNativeModelLoad,
                                  onModelError: _onNativeModelError,
                                ),
                              ),
                              GestureDetector(
                                behavior: HitTestBehavior.translucent,
                                onTapDown: (details) =>
                                    _focus(details, box.biggest),
                              ),
                            ],
                          ),
                        )
                      else if (camera?.value.isInitialized == true)
                        Transform.scale(
                          scale: _previewScale,
                          child: _CameraPreviewCover(
                            camera: camera!,
                            detections: _detections,
                            selected: _selectedDetection,
                            onFocus: _focus,
                          ),
                        ),
                      if ((_loading ||
                              (_useNativeYoloView && _preparingAi)) &&
                          _photoBytes == null)
                        Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const CircularProgressIndicator(),
                              const SizedBox(height: 12),
                              Text(
                                _useNativeYoloView
                                    ? 'Carregando YOLO-E…'
                                    : 'Abrindo câmera…',
                                style: const TextStyle(color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      if (_cameraError != null && _photoBytes == null)
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.no_photography_outlined,
                                  size: 38,
                                  color: Colors.white,
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  _cameraError!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.white),
                                ),
                                TextButton(
                                  onPressed: () {
                                    if (_useNativeYoloView) {
                                      setState(() {
                                        _cameraError = null;
                                        _preparingAi = true;
                                        _liveModelReady = false;
                                        _revision++;
                                      });
                                    } else {
                                      unawaited(_openCamera());
                                    }
                                  },
                                  child: const Text('Tentar novamente'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (_live && (_useNativeYoloView || camera?.value.isInitialized == true))
                        IgnorePointer(
                          child: Center(
                            child: FractionallySizedBox(
                              widthFactor: 0.90,
                              heightFactor: 0.88,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: AppColors.primary,
                                    width: 2,
                                  ),
                                  borderRadius: BorderRadius.circular(24),
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (_useNativeYoloView && _live && _liveModelReady)
                        Positioned(
                          left: 12,
                          top: 12,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.72),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              child: DefaultTextStyle(
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('YOLO-E ● ATIVO'),
                                    if (_liveFps != null)
                                      Text(
                                        'FPS: ${_liveFps!.toStringAsFixed(1)}',
                                      ),
                                    if (_liveInferenceMs != null)
                                      Text(
                                        'Inferência: ${_liveInferenceMs!.toStringAsFixed(0)} ms',
                                      ),
                                    if (_selectedDetection != null)
                                      Text(
                                        'Objeto: ${_selectedDetection!.label} · ${(_selectedDetection!.confidence * 100).round()}%',
                                      ),
                                    if (_liveClassIndex != null)
                                      Text('Classe: $_liveClassIndex'),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (_busy)
                        const Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: LinearProgressIndicator(minHeight: 3),
                        ),
                      if (_manualCaptureInProgress)
                        Positioned.fill(
                          child: ColoredBox(
                            color: Color(0x99000000),
                            child: Center(
                              child: Container(
                                margin: const EdgeInsets.all(24),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 22,
                                  vertical: 18,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF14221A),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: AppColors.primary.withValues(
                                      alpha: 0.7,
                                    ),
                                  ),
                                ),
                                child: const Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    CircularProgressIndicator(),
                                    SizedBox(height: 12),
                                    Text(
                                      'Foto capturada. Analisando…',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!_useNativeYoloView && (kIsWeb || _maxExposure > 0))
                      Row(children: [
                        const Icon(Icons.brightness_6_outlined, size: 20),
                        const SizedBox(width: 8),
                        const Text('Claridade'),
                        Expanded(child: Slider(
                          value: _brightness,
                          min: 1, max: 1.6, divisions: 6,
                          label: '+${((_brightness - 1) * 100).round()}%',
                          onChanged: _busy ? null : (value) => _setBrightness(value),
                        )),
                      ]),
                    if (_maxZoom > _minZoom + 0.01)
                      Row(
                        children: [
                          const Icon(Icons.zoom_in, size: 20),
                          const SizedBox(width: 8),
                          const Text('Zoom'),
                          Expanded(
                            child: Slider(
                              value: _zoom.clamp(_minZoom, _maxZoom).toDouble(),
                              min: _minZoom,
                              max: _maxZoom,
                              divisions: ((_maxZoom - _minZoom) * 2)
                                  .round()
                                  .clamp(1, 20)
                                  .toInt(),
                              label: '${_zoom.toStringAsFixed(1)}×',
                              onChanged: _busy || _saving
                                  ? null
                                  : (value) => unawaited(_setZoom(value)),
                            ),
                          ),
                          SizedBox(
                            width: 40,
                            child: Text('${_zoom.toStringAsFixed(1)}×'),
                          ),
                        ],
                      ),
                    if (_preparingAi && !_useNativeYoloView)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 10),
                        child: Text(kIsWeb
                            ? 'Preparando IA… No primeiro uso, o modelo é baixado pela internet.'
                            : 'Preparando IA… Verificando o modelo e as atualizações disponíveis.'),
                      ),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed:
                                _busy ||
                                    _saving ||
                                    _selecting ||
                                    !captureReady
                                ? null
                                : () => _capture(),
                            icon: const Icon(Icons.camera_alt_outlined),
                            label: Text(_busy ? 'Analisando…' : 'Fotografar'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _busy || _saving || _selecting
                                ? null
                                : _selectPhoto,
                            icon: const Icon(Icons.photo_library_outlined),
                            label: const Text('Galeria'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (_scanError != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          _scanError!,
                          style: const TextStyle(color: AppColors.danger),
                        ),
                      ),
                    OutlinedButton.icon(
                      onPressed: _busy || _saving || _selecting
                          ? null
                          : _reportCorrection,
                      icon: const Icon(Icons.feedback_outlined),
                      label: const Text(
                        'Objeto identificado incorretamente ou não encontrado?',
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_live && result?.isKnown == false)
                      const Text('Para detalhar o material, toque em Fotografar. A leitura ao vivo continua automaticamente.'),
                    if (result == null)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          'Aponte para um objeto por vez ou escolha uma foto. A IA identifica o objeto, estima o material e informa automaticamente a lixeira correta — sem confirmação manual.',
                          textAlign: TextAlign.center,
                        ),
                      )
                    else ...[
                      _MaterialResult(result: result),
                      if (_selectedDetection != null ||
                          _detector != 'unknown') ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            if (_selectedDetection case final detection?)
                              Chip(
                                avatar: const Icon(
                                  Icons.center_focus_strong,
                                  size: 16,
                                ),
                                label: Text(
                                  '${detection.label} · ${(detection.confidence * 100).round()}%',
                                ),
                              ),
                            Chip(
                              avatar: const Icon(Icons.memory, size: 16),
                              label: Text(_detector),
                            ),
                            if (result.source == 'supabase')
                              const Chip(
                                avatar: Icon(Icons.cloud_done_outlined, size: 16),
                                label: Text('Base EcoScan'),
                              ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 12),
                      if (!result.isKnown)
                        OutlinedButton.icon(
                          onPressed: _busy || _saving ? null : _selectPhoto,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Tentar outra foto'),
                        )
                      else
                        FilledButton.icon(
                          onPressed: _busy || _saving || _saved
                              ? null
                              : _save,
                          icon: Icon(
                            _saved ? Icons.check : Icons.bookmark_add_outlined,
                          ),
                          label: Text(
                            _saved
                                ? 'Salvo no histórico'
                                : _saving
                                ? 'Salvando…'
                                : 'Salvar análise',
                          ),
                        ),
                      if (result.isKnown && widget.onFindNearby != null) ...[
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: _busy || _saving
                              ? null
                              : () => widget.onFindNearby!(result),
                          icon: const Icon(Icons.location_on_outlined),
                          label: const Text('Encontrar local próximo'),
                        ),
                      ],
                    ],
                    if (!_live)
                      TextButton.icon(
                        onPressed: _busy || _saving
                            ? null
                            : showLiveScanner,
                        icon: const Icon(Icons.center_focus_strong),
                        label: const Text('Voltar ao scanner ao vivo'),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _LiveSnapshot {
  const _LiveSnapshot({
    required this.classification,
    required this.detections,
    required this.selectedDetection,
    required this.detector,
    required this.capturedAt,
  });

  final WasteClassification classification;
  final List<ObjectDetection> detections;
  final ObjectDetection? selectedDetection;
  final String detector;
  final DateTime capturedAt;
}

class _CameraPreviewCover extends StatelessWidget {
  const _CameraPreviewCover({
    required this.camera,
    required this.detections,
    required this.selected,
    required this.onFocus,
  });

  final CameraController camera;
  final List<ObjectDetection> detections;
  final ObjectDetection? selected;
  final Future<void> Function(TapDownDetails details, Size size) onFocus;

  @override
  Widget build(BuildContext context) {
    final portrait =
        MediaQuery.orientationOf(context) == Orientation.portrait;
    final previewAspect = portrait
        ? 1 / camera.value.aspectRatio
        : camera.value.aspectRatio;
    const logicalHeight = 1000.0;
    final logicalWidth = logicalHeight * previewAspect;

    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        alignment: Alignment.center,
        child: SizedBox(
          width: logicalWidth,
          height: logicalHeight,
          child: CameraPreview(
            camera,
            child: LayoutBuilder(
              builder: (context, box) => Stack(
                fit: StackFit.expand,
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (details) => onFocus(details, box.biggest),
                  ),
                  if (detections.isNotEmpty)
                    IgnorePointer(
                      child: CustomPaint(
                        painter: _DetectionOverlayPainter(
                          detections: detections,
                          selected: selected,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DetectionOverlayPainter extends CustomPainter {
  const _DetectionOverlayPainter({
    required this.detections,
    required this.selected,
  });

  final List<ObjectDetection> detections;
  final ObjectDetection? selected;

  @override
  void paint(Canvas canvas, Size size) {
    final normalPaint = Paint()
      ..color = const Color(0xFFFFB74D)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final selectedPaint = Paint()
      ..color = AppColors.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    for (final detection in detections) {
      final box = _scale(detection.normalizedBox, size);
      canvas.drawRRect(
        RRect.fromRectAndRadius(box, const Radius.circular(8)),
        normalPaint,
      );
    }

    final target = selected;
    if (target == null) return;
    final box = _scale(target.normalizedBox, size);
    canvas.drawRRect(
      RRect.fromRectAndRadius(box, const Radius.circular(10)),
      selectedPaint,
    );
    final label = TextPainter(
      text: TextSpan(
        text: '${target.label} ${(target.confidence * 100).round()}%',
        style: const TextStyle(
          color: Colors.black,
          backgroundColor: AppColors.primary,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: size.width * 0.8);
    label.paint(
      canvas,
      Offset(
        box.left,
        (box.top - label.height - 3).clamp(0.0, size.height).toDouble(),
      ),
    );
  }

  static Rect _scale(Rect value, Size size) => Rect.fromLTRB(
    value.left * size.width,
    value.top * size.height,
    value.right * size.width,
    value.bottom * size.height,
  );

  @override
  bool shouldRepaint(covariant _DetectionOverlayPainter oldDelegate) =>
      !identical(oldDelegate.detections, detections) ||
      oldDelegate.selected != selected;
}

class _MaterialResult extends StatelessWidget {
  const _MaterialResult({required this.result});
  final WasteClassification result;

  @override
  Widget build(BuildContext context) {
    final color = result.material?.color ?? AppColors.muted;
    final confidence = (result.confidence * 100).clamp(0, 100).round();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            result.isKnown ? 'IDENTIFICADO PELA IA' : 'ANÁLISE INCONCLUSIVA',
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
          if (result.detectedObject != null) ...[
            const SizedBox(height: 8),
            Text(
              result.detectedObject!,
              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900),
            ),
          ],
          const SizedBox(height: 10),
          if (result.isKnown) ...[
            Row(
              children: [
                Expanded(
                  child: _ResultInfo(
                    title: result.material?.id == 'electronic' ? 'Categoria' : 'Material',
                    value: result.name,
                    color: color,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ResultInfo(
                    title: 'Confiança',
                    value: confidence > 0 ? '$confidence%' : 'Estimativa',
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  Icon(
                    result.material!.id == 'electronic' ||
                            result.material!.id == 'special'
                        ? Icons.location_on
                        : Icons.delete_rounded,
                    color: color,
                    size: 42,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Destino',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                        ),
                        Text(
                          result.bin == 'Coleta especial'
                              ? result.bin
                              : 'Lixeira ${result.bin.toLowerCase()}',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: color,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(result.destination, style: const TextStyle(height: 1.5)),
        ],
      ),
    );
  }
}

class _ResultInfo extends StatelessWidget {
  const _ResultInfo({
    required this.title,
    required this.value,
    required this.color,
  });

  final String title;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      );
}
