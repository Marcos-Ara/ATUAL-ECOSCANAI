import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/detection_record.dart';
import '../models/eco_point.dart';
import '../models/learning_sample.dart';

class EcoScanStore extends ChangeNotifier {
  EcoScanStore._(this._preferences);
  final SharedPreferences _preferences;
  String? userId;
  final List<DetectionRecord> _detections = [];
  final List<LearningSample> _learningSamples = [];
  bool _restoringCloudData = false;
  List<DetectionRecord> get detections => List.unmodifiable(_detections);
  List<LearningSample> get learningSamples =>
      List.unmodifiable(_learningSamples);
  int get learningSampleCount => _learningSamples.length;
  bool get isRestoringCloudData => _restoringCloudData;
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
  String _remotePhotoKeyFor(String uid) => 'ecoscan.profile.remote.v1.$uid';
  String _pendingPhotoKeyFor(String uid) =>
      'ecoscan.profile.pending.v1.$uid';
  String get _learningKey =>
      'ecoscan.learning.v1.${userId ?? 'signed-out'}';
  String _learningKeyFor(String? uid) =>
      'ecoscan.learning.v1.${uid ?? 'signed-out'}';
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

  /// Moves the visitor's locally saved work into the first account they use.
  /// The visitor copy stays on the device if the cloud is offline.
  Future<void> switchUserWithGuestData(String? uid) async {
    if (uid == null || uid == 'guest-local') {
      switchUser(uid);
      return;
    }

    final migrationKey = 'ecoscan.guest_data_migrated_to.v1';
    final migratedTo = _preferences.getString(migrationKey);
    if (migratedTo == null || migratedTo == uid) {
      final guestRecords = _decodeRecords(
        _preferences.getString(_detectionsKeyFor('guest-local')),
      );
      final accountRecords = _decodeRecords(
        _preferences.getString(_detectionsKeyFor(uid)),
      );
      final recordsById = <String, DetectionRecord>{
        for (final record in accountRecords)
          if (record.id.isNotEmpty) record.id: record,
        for (final record in guestRecords)
          if (record.id.isNotEmpty) record.id: record,
      };
      if (recordsById.isNotEmpty &&
          !await _preferences.setString(
            _detectionsKeyFor(uid),
            jsonEncode(
              recordsById.values.map((record) => record.toJson()).toList(),
            ),
          )) {
        throw StateError('Não foi possível transferir o histórico do visitante.');
      }

      final guestSamples = _decodeLearningSamples(
        _preferences.getString(_learningKeyFor('guest-local')),
      );
      final accountSamples = _decodeLearningSamples(
        _preferences.getString(_learningKeyFor(uid)),
      );
      final samplesById = <String, LearningSample>{
        for (final sample in accountSamples) sample.id: sample,
        for (final sample in guestSamples) sample.id: sample,
      };
      if (samplesById.isNotEmpty &&
          !await _preferences.setString(
            _learningKeyFor(uid),
            jsonEncode(
              samplesById.values.map((sample) => sample.toJson()).toList(),
            ),
          )) {
        throw StateError('Não foi possível transferir as correções do visitante.');
      }

      final targetPhotoKey = 'ecoscan.profile.v2.$uid';
      final guestPhoto =
          _preferences.getString('ecoscan.profile.v2.guest-local');
      if ((_preferences.getString(targetPhotoKey) ?? '').isEmpty &&
          guestPhoto?.isNotEmpty == true) {
        if (!await _preferences.setString(targetPhotoKey, guestPhoto!)) {
          throw StateError('Não foi possível transferir a foto do visitante.');
        }
        await _preferences.setBool(_pendingPhotoKeyFor(uid), true);
      }
      if (!await _preferences.setString(migrationKey, uid)) {
        throw StateError('Não foi possível concluir a transferência da conta.');
      }
    }
    switchUser(uid);
  }

  Future<void> setDarkMode(bool value) async {
    await _preferences.setBool('ecoscan.dark', value);
    notifyListeners();
    await _syncCloudSettings();
  }

  Future<void> setSounds(bool value) async {
    await _preferences.setBool('ecoscan.sounds', value);
    notifyListeners();
    await _syncCloudSettings();
  }

  Future<void> setNotifications(bool value) async {
    await _preferences.setBool('ecoscan.notices', value);
    notifyListeners();
    await _syncCloudSettings();
  }

  Future<void> markMapExplored() async {
    if (userId == null) return;
    await _preferences.setBool('ecoscan.map.${userId!}', true);
    notifyListeners();
    await _syncCloudSettings();
  }

  /// Restaura as preferências da conta no login. Se ainda não houver registro
  /// remoto, envia as preferências já salvas neste aparelho.
  Future<void> syncAccountSettings() async {
    final owner = userId;
    if (owner == null) return;
    try {
      final client = Supabase.instance.client;
      if (client.auth.currentUser?.id != owner) return;
      final row = await client
          .from('configuracoes_usuario')
          .select(
            'tema,sons_ativos,avisos_ativos,mapa_explorado,caminho_foto_perfil',
          )
          .eq('usuario_id', owner)
          .maybeSingle();
      if (row == null) {
        await _syncCloudSettings();
        return;
      }
      await _preferences.setBool('ecoscan.dark', row['tema'] == 'escuro');
      await _preferences.setBool(
        'ecoscan.sounds',
        row['sons_ativos'] == true,
      );
      await _preferences.setBool(
        'ecoscan.notices',
        row['avisos_ativos'] == true,
      );
      await _preferences.setBool(
        'ecoscan.map.$owner',
        row['mapa_explorado'] == true,
      );
      final remotePhoto = row['caminho_foto_perfil']?.toString() ?? '';
      var hasPendingPhoto =
          _preferences.getBool(_pendingPhotoKeyFor(owner)) == true;
      if (remotePhoto.isEmpty && profilePhoto.isNotEmpty) {
        hasPendingPhoto = true;
        await _preferences.setBool(_pendingPhotoKeyFor(owner), true);
      }
      if (remotePhoto.isNotEmpty) {
        await _preferences.setString(_remotePhotoKeyFor(owner), remotePhoto);
        if (!hasPendingPhoto) await _restoreProfilePhoto(owner, remotePhoto);
      }
      if (hasPendingPhoto) await _syncCloudSettings();
      if (userId == owner) notifyListeners();
    } catch (_) {
      // Preferências locais continuam disponíveis quando a nuvem está offline.
    }
  }

  Future<void> _syncCloudSettings() async {
    final owner = userId;
    if (owner == null) return;
    try {
      final client = Supabase.instance.client;
      if (client.auth.currentUser?.id != owner) return;
      final remotePhoto = await _uploadProfilePhoto(owner, profilePhoto) ??
          _preferences.getString(_remotePhotoKeyFor(owner));
      if (userId != owner || client.auth.currentUser?.id != owner) return;
      await client.from('configuracoes_usuario').upsert(
        {
          'usuario_id': owner,
          'tema': darkMode ? 'escuro' : 'claro',
          'sons_ativos': sounds,
          'avisos_ativos': notifications,
          'mapa_explorado': exploredMap,
          'caminho_foto_perfil': remotePhoto,
          'atualizado_em': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'usuario_id',
      );
      if (userId == owner) {
        await _preferences.remove(_pendingPhotoKeyFor(owner));
      }
    } catch (_) {
      // A sincronização de preferências será tentada novamente no próximo login.
    }
  }

  Future<void> setProfilePhoto(String path) async {
    final owner = userId;
    if (owner == null) return;
    final oldPath = profilePhoto;
    await _preferences.setString('ecoscan.profile.v2.$owner', path);
    await _preferences.setBool(_pendingPhotoKeyFor(owner), true);
    if (userId == owner) notifyListeners();
    if (userId == owner) await _syncCloudSettings();
    if (oldPath != path) await _deleteImage(oldPath);
  }

  Future<String?> _uploadProfilePhoto(String owner, String source) async {
    if (source.isEmpty) return null;
    final bytes = await _readImageBytes(source);
    if (bytes == null || bytes.isEmpty) return null;
    final contentType = _imageContentType(source);
    final storagePath = '$owner/profile/avatar.jpg';
    await Supabase.instance.client.storage
        .from('ecoscan-account-data')
        .uploadBinary(
          storagePath,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: true),
        );
    await _preferences.setString(_remotePhotoKeyFor(owner), storagePath);
    return storagePath;
  }

  Future<void> _restoreProfilePhoto(String owner, String storagePath) async {
    if (userId != owner ||
        Supabase.instance.client.auth.currentUser?.id != owner) {
      return;
    }
    final bytes = await Supabase.instance.client.storage
        .from('ecoscan-account-data')
        .download(storagePath);
    if (userId != owner || bytes.isEmpty) return;

    String localPath;
    if (kIsWeb) {
      localPath = 'data:image/jpeg;base64,${base64Encode(bytes)}';
    } else {
      final documents = await getApplicationDocumentsDirectory();
      final directory = Directory(
        p.join(documents.path, 'ecoscan', owner, 'profile'),
      );
      await directory.create(recursive: true);
      final file = File(p.join(directory.path, 'cloud_avatar.jpg'));
      await file.writeAsBytes(bytes, flush: true);
      localPath = file.path;
    }
    if (userId != owner) return;
    await _preferences.setString('ecoscan.profile.v2.$owner', localPath);
  }

  Future<Uint8List?> _readImageBytes(String source) async {
    if (source.startsWith('data:image/')) {
      final comma = source.indexOf(',');
      if (comma < 0 || !source.substring(0, comma).contains(';base64')) {
        return null;
      }
      try {
        return base64Decode(source.substring(comma + 1));
      } catch (_) {
        return null;
      }
    }
    if (source.startsWith('http://') || source.startsWith('https://') || kIsWeb) {
      return null;
    }
    try {
      final file = File(source);
      return await file.exists() ? await file.readAsBytes() : null;
    } catch (_) {
      return null;
    }
  }

  String _imageContentType(String source) {
    final lower = source.toLowerCase();
    if (lower.startsWith('data:image/png')) return 'image/png';
    if (lower.startsWith('data:image/webp')) return 'image/webp';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
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
      if (record.id.isEmpty) continue;
      final existing = byId[record.id];
      if (existing == null) {
        byId[record.id] = record;
      } else if (record.imagePath.startsWith('https://') &&
          (existing.imagePath.isEmpty ||
              existing.imagePath.startsWith('https://') ||
              existing.imagePath.startsWith('http://'))) {
        byId[record.id] = DetectionRecord.fromJson({
          ...existing.toJson(),
          'imagePath': record.imagePath,
        });
      }
    }
    final merged = byId.values.toList()
      ..sort((a, b) => b.detectedAt.compareTo(a.detectedAt));
    final success = await _preferences.setString(
      _detectionsKeyFor(owner),
      jsonEncode(merged.map((record) => record.toJson()).toList()),
    );
    if (!success) throw StateError('Não foi possível restaurar o histórico.');
    if (userId != owner) return;
    _restoringCloudData = true;
    try {
      _detections
        ..clear()
        ..addAll(merged);
      notifyListeners();
    } finally {
      _restoringCloudData = false;
    }
  }

  Future<void> removeDetection(DetectionRecord record) async {
    await removeDetections([record]);
  }

  /// Removes several saved scans in one local write and queues one batch of
  /// cloud tombstones so deleted scans do not return on the next sync.
  Future<void> removeDetections(Iterable<DetectionRecord> records) async {
    final owner = userId;
    if (owner == null) return;
    final ids = records
        .map((record) => record.id)
        .where((id) => id.isNotEmpty)
        .toSet();
    if (ids.isEmpty) return;

    final removed = _detections
        .where((record) => ids.contains(record.id))
        .toList(growable: false);
    if (removed.isEmpty) return;
    await _rememberScanDeletions(owner, ids);

    final next = _detections
        .where((record) => !ids.contains(record.id))
        .toList(growable: false);
    final success = await _preferences.setString(
      _detectionsKeyFor(owner),
      jsonEncode(next.map((record) => record.toJson()).toList()),
    );
    if (!success) {
      await acknowledgeScanDeletions(ids, userIdOverride: owner);
      throw StateError('Não foi possível excluir as análises.');
    }
    if (userId == owner) {
      _detections
        ..clear()
        ..addAll(next);
      notifyListeners();
    }
    for (final record in removed) {
      await _deleteImage(record.imagePath);
    }
  }

  Future<void> clearHistory() async {
    await removeDetections(List<DetectionRecord>.of(_detections));
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

  /// Restores private correction drafts after the user signs in again.
  Future<void> mergeCloudLearningSamples(
    Iterable<LearningSample> incoming,
  ) async {
    final owner = userId;
    if (owner == null) return;
    final byId = <String, LearningSample>{
      for (final sample in _learningSamples)
        if (sample.id.isNotEmpty) sample.id: sample,
    };
    for (final sample in incoming) {
      if (sample.id.isNotEmpty && sample.thumbnailDataUrl.isNotEmpty) {
        byId[sample.id] = sample;
      }
    }
    final merged = byId.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final success = await _preferences.setString(
      _learningKeyFor(owner),
      jsonEncode(merged.map((sample) => sample.toJson()).toList()),
    );
    if (!success) throw StateError('Não foi possível restaurar as correções.');
    if (userId != owner) return;
    _restoringCloudData = true;
    try {
      _learningSamples
        ..clear()
        ..addAll(merged);
      notifyListeners();
    } finally {
      _restoringCloudData = false;
    }
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

  Future<void> updateLearningSample(LearningSample updated) async {
    if (userId == null) return;
    final owner = userId;
    final index = _learningSamples.indexWhere((item) => item.id == updated.id);
    if (index < 0) return;
    final next = List<LearningSample>.of(_learningSamples)..[index] = updated;
    final success = await _preferences.setString(
      _learningKey,
      jsonEncode(next.map((item) => item.toJson()).toList()),
    );
    if (!success) throw StateError('Não foi possível salvar a edição local.');
    if (userId == owner) {
      _learningSamples
        ..clear()
        ..addAll(next);
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

  static List<DetectionRecord> _decodeRecords(String? json) {
    try {
      final decoded = jsonDecode(json ?? '[]');
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((item) => DetectionRecord.fromJson(Map<String, dynamic>.from(item)))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  static List<LearningSample> _decodeLearningSamples(String? json) {
    try {
      final decoded = jsonDecode(json ?? '[]');
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((item) => LearningSample.fromJson(Map<String, dynamic>.from(item)))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }
}
