import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/detection_record.dart';
import '../models/eco_point.dart';
import '../models/learning_sample.dart';

class EcoScanStore extends ChangeNotifier {
  EcoScanStore._(this._preferences);
  final SharedPreferences _preferences;
  String? userId;
  final List<DetectionRecord> _detections = [];
  final List<LearningSample> _learningSamples = [];
  List<DetectionRecord> get detections => List.unmodifiable(_detections);
  List<LearningSample> get learningSamples =>
      List.unmodifiable(_learningSamples);
  int get learningSampleCount => _learningSamples.length;
  int get scanCount => _detections.length;
  String _detectionsKeyFor(String? uid) =>
      'ecoscan.detections.v2.${uid ?? 'signed-out'}';
  String get _detectionsKey => _detectionsKeyFor(userId);
  String _scanDeletionsKeyFor(String uid) => 'ecoscan.deleted_scans.v1.$uid';
  List<String> _pendingScanDeletionsFor(String uid) {
    try {
      final decoded = jsonDecode(
        _preferences.getString(_scanDeletionsKeyFor(uid)) ?? '[]',
      );
      if (decoded is List) {
        return decoded
            .map((value) => value.toString())
            .where((id) => id.isNotEmpty)
            .toSet()
            .toList(growable: true);
      }
    } catch (_) {}
    return <String>[];
  }
  List<String> get pendingScanDeletionIds => userId == null
      ? const []
      : _pendingScanDeletionsFor(userId!);
  String get _photoKey => 'ecoscan.profile.v2.${userId ?? 'signed-out'}';
  String get _learningKey =>
      'ecoscan.learning.v1.${userId ?? 'signed-out'}';
  String get profilePhoto => _preferences.getString(_photoKey) ?? '';
  bool get darkMode => _preferences.getBool('ecoscan.dark') ?? true;
  bool get sounds => _preferences.getBool('ecoscan.sounds') ?? true;
  bool get notifications => _preferences.getBool('ecoscan.notices') ?? true;
  bool get exploredMap =>
      _preferences.getBool('ecoscan.map.${userId ?? ''}') ?? false;

  static Future<EcoScanStore> load() async =>
      EcoScanStore._(await SharedPreferences.getInstance());

  void switchUser(String? uid) {
    if (uid == userId) return;
    userId = uid;
    _detections.clear();
    _learningSamples.clear();
    if (uid != null) {
      try {
        final decoded = jsonDecode(
          _preferences.getString(_detectionsKey) ?? '[]',
        );
        if (decoded is List) {
          _detections.addAll(
            decoded.whereType<Map>().map(
              (e) => DetectionRecord.fromJson(Map<String, dynamic>.from(e)),
            ),
          );
          _detections.sort((a, b) => b.detectedAt.compareTo(a.detectedAt));
        }
      } catch (_) {
        _detections.clear();
      }
      try {
        final decoded = jsonDecode(
          _preferences.getString(_learningKey) ?? '[]',
        );
        if (decoded is List) {
          _learningSamples.addAll(
            decoded.whereType<Map>().map(
              (item) => LearningSample.fromJson(
                Map<String, dynamic>.from(item),
              ),
            ),
          );
        }
      } catch (_) {
        _learningSamples.clear();
      }
    }
    notifyListeners();
  }

  Future<void> setDarkMode(bool value) async {
    await _preferences.setBool('ecoscan.dark', value);
    notifyListeners();
  }

  Future<void> setSounds(bool value) async {
    await _preferences.setBool('ecoscan.sounds', value);
    notifyListeners();
  }

  Future<void> setNotifications(bool value) async {
    await _preferences.setBool('ecoscan.notices', value);
    notifyListeners();
  }

  Future<void> markMapExplored() async {
    if (userId == null) return;
    await _preferences.setBool('ecoscan.map.${userId!}', true);
    notifyListeners();
  }

  Future<void> setProfilePhoto(String path) async {
    if (userId == null) return;
    final oldPath = profilePhoto;
    await _preferences.setString(_photoKey, path);
    notifyListeners();
    if (oldPath != path) await _deleteImage(oldPath);
  }

  Future<void> addDetection(DetectionRecord record) async {
    if (userId == null) throw StateError('Entre na sua conta antes de salvar.');
    final owner = userId;
    final next = [record, ..._detections];
    final success = await _preferences.setString(
      _detectionsKey,
      jsonEncode(next.map((d) => d.toJson()).toList()),
    );
    if (!success) throw StateError('Não foi possível salvar a análise.');
    if (userId != owner) return;
    _detections.insert(0, record);
    notifyListeners();
  }

  /// Merges cloud history into this account while keeping local image files.
  Future<void> mergeCloudDetections(Iterable<DetectionRecord> incoming) async {
    if (userId == null) return;
    final owner = userId;
    final byId = <String, DetectionRecord>{
      for (final record in _detections)
        if (record.id.isNotEmpty) record.id: record,
    };
    for (final record in incoming) {
      if (record.id.isNotEmpty) byId.putIfAbsent(record.id, () => record);
    }
    final merged = byId.values.toList()
      ..sort((a, b) => b.detectedAt.compareTo(a.detectedAt));
    final success = await _preferences.setString(
      _detectionsKeyFor(owner),
      jsonEncode(merged.map((record) => record.toJson()).toList()),
    );
    if (!success) throw StateError('Não foi possível restaurar o histórico.');
    if (userId != owner) return;
    _detections
      ..clear()
      ..addAll(merged);
    notifyListeners();
  }

  Future<void> removeDetection(DetectionRecord record) async {
    if (userId == null) return;
    final owner = userId!;
    final next = _detections.where((d) => d.id != record.id).toList();
    if (record.id.isNotEmpty) {
      await _rememberScanDeletions(owner, [record.id]);
    }
    final success = await _preferences.setString(
      _detectionsKeyFor(owner),
      jsonEncode(next.map((d) => d.toJson()).toList()),
    );
    if (!success) {
      if (record.id.isNotEmpty) {
        await acknowledgeScanDeletions([record.id], userIdOverride: owner);
      }
      throw StateError('Não foi possível excluir a análise.');
    }
    if (userId == owner) {
      _detections
        ..clear()
        ..addAll(next);
      notifyListeners();
    }
    await _deleteImage(record.imagePath);
  }

  Future<void> clearHistory() async {
    if (userId == null) return;
    final owner = userId!;
    final records = List<DetectionRecord>.of(_detections);
    final deletedIds = records
        .map((record) => record.id)
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
    await _rememberScanDeletions(owner, deletedIds);
    final images = records.map((d) => d.imagePath).toList();
    if (!await _preferences.remove(_detectionsKeyFor(owner))) {
      await acknowledgeScanDeletions(deletedIds, userIdOverride: owner);
      throw StateError('Não foi possível limpar o histórico.');
    }
    if (userId == owner) {
      _detections.clear();
      notifyListeners();
    }
    for (final image in images) {
      await _deleteImage(image);
    }
  }

  Future<void> _rememberScanDeletions(
    String owner,
    Iterable<String> ids,
  ) async {
    final pending = _pendingScanDeletionsFor(owner)..addAll(ids);
    if (!await _preferences.setString(
      _scanDeletionsKeyFor(owner),
      jsonEncode(pending.toSet().toList()),
    )) {
      throw StateError('Não foi possível guardar a exclusão pendente.');
    }
  }

  Future<void> acknowledgeScanDeletions(
    Iterable<String> ids, {
    String? userIdOverride,
  }) async {
    final owner = userIdOverride ?? userId;
    if (owner == null) return;
    final acknowledged = ids.toSet();
    if (acknowledged.isEmpty) return;
    final pending = _pendingScanDeletionsFor(owner)
      ..removeWhere(acknowledged.contains);
    if (!await _preferences.setString(
      _scanDeletionsKeyFor(owner),
      jsonEncode(pending),
    )) {
      throw StateError('Não foi possível confirmar a sincronização.');
    }
  }

  Future<void> applyCloudScanDeletions(Iterable<String> ids) async {
    if (userId == null) return;
    final owner = userId!;
    final deleted = ids.toSet();
    if (deleted.isEmpty) return;
    final removed = _detections
        .where((record) => deleted.contains(record.id))
        .toList(growable: false);
    final remaining = _detections
        .where((record) => !deleted.contains(record.id))
        .toList(growable: false);
    if (removed.isNotEmpty) {
      final success = await _preferences.setString(
        _detectionsKeyFor(owner),
        jsonEncode(remaining.map((record) => record.toJson()).toList()),
      );
      if (!success) throw StateError('Não foi possível atualizar o histórico.');
    }
    await acknowledgeScanDeletions(deleted, userIdOverride: owner);
    if (userId != owner) return;
    _detections
      ..clear()
      ..addAll(remaining);
    notifyListeners();
    for (final record in removed) {
      await _deleteImage(record.imagePath);
    }
  }

  Future<void> addLearningSample(LearningSample sample) async {
    if (userId == null) return;
    final owner = userId;
    final next = [sample, ..._learningSamples];
    final success = await _preferences.setString(
      _learningKey,
      jsonEncode(next.map((item) => item.toJson()).toList()),
    );
    if (!success) throw StateError('Não foi possível guardar a amostra local.');
    if (userId != owner) return;
    _learningSamples
      ..clear()
      ..addAll(next);
    notifyListeners();
  }

  Future<void> clearLearningSamples() async {
    if (userId == null) return;
    final owner = userId;
    if (!await _preferences.remove(_learningKey)) {
      throw StateError('Não foi possível limpar as amostras locais.');
    }
    if (userId == owner) {
      _learningSamples.clear();
      notifyListeners();
    }
  }

  Future<void> removeLearningSamples(Iterable<String> sampleIds) async {
    if (userId == null) return;
    final ids = sampleIds.toSet();
    if (ids.isEmpty) return;
    final owner = userId;
    final next = _learningSamples
        .where((sample) => !ids.contains(sample.id))
        .toList(growable: false);
    final success = await _preferences.setString(
      _learningKey,
      jsonEncode(next.map((item) => item.toJson()).toList()),
    );
    if (!success) throw StateError('Não foi possível atualizar as amostras.');
    if (userId == owner) {
      _learningSamples
        ..clear()
        ..addAll(next);
      notifyListeners();
    }
  }

  Future<List<EcoPoint>> loadCachedEcoPoints() async {
    try {
      final data = jsonDecode(
        _preferences.getString('ecoscan_geosampa_catalog_v2') ?? '[]',
      ) as List;
      return data
          .whereType<Map>()
          .map((e) => EcoPoint.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveEcoPoints(Iterable<EcoPoint> points) async {
    await _preferences.setString(
      'ecoscan_geosampa_catalog_v2',
      jsonEncode(points.map((e) => e.toJson()).toList()),
    );
  }

  static Future<void> _deleteImage(String imagePath) async {
    if (imagePath.isEmpty ||
        kIsWeb ||
        imagePath.startsWith('data:image/') ||
        imagePath.startsWith('http://') ||
        imagePath.startsWith('https://')) {
      return;
    }
    try {
      final documents = await getApplicationDocumentsDirectory();
      final root = p.join(documents.path, 'ecoscan');
      if (!p.isWithin(root, p.normalize(imagePath))) return;
      final file = File(imagePath);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
