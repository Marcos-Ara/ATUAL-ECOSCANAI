import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/detection_record.dart';
import '../models/eco_point.dart';
import '../models/learning_sample.dart';
import '../services/firebase_account_backup_service.dart';

class EcoScanStore extends ChangeNotifier {
  EcoScanStore._(this._preferences);
  final SharedPreferences _preferences;
  String? userId;
  final List<DetectionRecord> _detections = [];
  final List<LearningSample> _learningSamples = [];
  final Set<String> _knownAchievementIds = <String>{};
  int _cloudRestoreDepth = 0;
  List<DetectionRecord> get detections => List.unmodifiable(_detections);
  List<LearningSample> get learningSamples =>
      List.unmodifiable(_learningSamples);
  int get learningSampleCount => _learningSamples.length;
  Set<String> get knownAchievementIds =>
      Set<String>.unmodifiable(_knownAchievementIds);
  bool get isRestoringCloudData => _cloudRestoreDepth > 0;

  void beginCloudRestore() => _cloudRestoreDepth++;

  void endCloudRestore() {
    if (_cloudRestoreDepth > 0) _cloudRestoreDepth--;
  }

  int get scanCount => _detections.length;
  String _detectionsKeyFor(String? uid) =>
      'ecoscan.detections.v2.${uid ?? 'signed-out'}';
  String get _detectionsKey => _detectionsKeyFor(userId);
  String _scanDeletionsKeyFor(String uid) => 'ecoscan.deleted_scans.v1.$uid';
  String _pendingScanUploadsKeyFor(String uid) =>
      'ecoscan.pending_scan_uploads.v1.$uid';
  String _scanUploadQueuePrimedKeyFor(String uid) =>
      'ecoscan.scan_upload_queue_primed.v1.$uid';
  String _pendingCorrectionUploadsKeyFor(String uid) =>
      'ecoscan.pending_correction_uploads.v1.$uid';
  String _correctionUploadQueuePrimedKeyFor(String uid) =>
      'ecoscan.correction_upload_queue_primed.v1.$uid';
  String _achievementsKeyFor(String uid) =>
      'ecoscan.achievements.v1.$uid';
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
  List<String> get pendingScanUploadIds => userId == null
      ? const []
      : _readPendingIds(_pendingScanUploadsKeyFor(userId!));
  List<String> get pendingCorrectionUploadIds => userId == null
      ? const []
      : _readPendingIds(_pendingCorrectionUploadsKeyFor(userId!));
  bool get hasPendingAccountSync {
    final owner = userId;
    if (owner == null || owner == 'guest-local') return false;
    return pendingScanUploadIds.isNotEmpty ||
        pendingScanDeletionIds.isNotEmpty ||
        pendingCorrectionUploadIds.isNotEmpty ||
        (_preferences.getBool(_scanUploadQueuePrimedKeyFor(owner)) != true &&
            _detections.isNotEmpty) ||
        (_preferences.getBool(_correctionUploadQueuePrimedKeyFor(owner)) !=
                true &&
            _learningSamples.isNotEmpty) ||
        _preferences.getBool(_pendingSettingsKeyFor(owner)) == true ||
        _preferences.getBool(_pendingPhotoKeyFor(owner)) == true;
  }
  String get _photoKey => 'ecoscan.profile.v2.${userId ?? 'signed-out'}';
  String _remotePhotoKeyFor(String uid) => 'ecoscan.profile.remote.v1.$uid';
  String _pendingSettingsKeyFor(String uid) =>
      'ecoscan.settings.pending.v1.$uid';
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

  /// Converts existing account scans into a durable outbox once. New scans
  /// enter the same queue at creation time, so retries never need to reupload
  /// the complete account history.
  Future<void> primePendingScanUploadQueue() async {
    final owner = userId;
    if (owner == null || owner == 'guest-local') return;
    if (_preferences.getBool(_scanUploadQueuePrimedKeyFor(owner)) == true) {
      return;
    }
    await _addPendingIds(
      _pendingScanUploadsKeyFor(owner),
      _detections.map((record) => record.id),
    );
    if (!await _preferences.setBool(
      _scanUploadQueuePrimedKeyFor(owner),
      true,
    )) {
      throw StateError('Não foi possível preparar a fila de leituras.');
    }
  }

  /// Converts existing private corrections into the durable outbox once.
  Future<void> primePendingCorrectionUploadQueue() async {
    final owner = userId;
    if (owner == null || owner == 'guest-local') return;
    if (_preferences.getBool(_correctionUploadQueuePrimedKeyFor(owner)) ==
        true) {
      return;
    }
    await _addPendingIds(
      _pendingCorrectionUploadsKeyFor(owner),
      _learningSamples.map((sample) => sample.id),
    );
    if (!await _preferences.setBool(
      _correctionUploadQueuePrimedKeyFor(owner),
      true,
    )) {
      throw StateError('Não foi possível preparar a fila de correções.');
    }
  }

  Future<void> queueScanUpload(String id, {String? userIdOverride}) async {
    final owner = userIdOverride ?? userId;
    if (owner == null || owner == 'guest-local' || id.isEmpty) return;
    await _addPendingIds(_pendingScanUploadsKeyFor(owner), [id]);
  }

  Future<void> acknowledgeScanUploads(
    Iterable<String> ids, {
    String? userIdOverride,
  }) async {
    final owner = userIdOverride ?? userId;
    if (owner == null || owner == 'guest-local') return;
    await _removePendingIds(_pendingScanUploadsKeyFor(owner), ids);
    await _persistPendingScans(owner);
  }

  Future<void> queueCorrectionUpload(
    String id, {
    String? userIdOverride,
  }) async {
    final owner = userIdOverride ?? userId;
    if (owner == null || owner == 'guest-local' || id.isEmpty) return;
    await _addPendingIds(_pendingCorrectionUploadsKeyFor(owner), [id]);
  }

  Future<void> acknowledgeCorrectionUploads(
    Iterable<String> ids, {
    String? userIdOverride,
  }) async {
    final owner = userIdOverride ?? userId;
    if (owner == null || owner == 'guest-local') return;
    await _removePendingIds(_pendingCorrectionUploadsKeyFor(owner), ids);
    await _persistPendingCorrections(owner);
  }

  List<String> _readPendingIds(String key) {
    try {
      final decoded = jsonDecode(_preferences.getString(key) ?? '[]');
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

  Future<void> _addPendingIds(String key, Iterable<String> ids) async {
    final next = _readPendingIds(key)..addAll(ids.where((id) => id.isNotEmpty));
    if (!await _preferences.setString(key, jsonEncode(next.toSet().toList()))) {
      throw StateError('Não foi possível guardar a sincronização pendente.');
    }
  }

  Future<void> _removePendingIds(String key, Iterable<String> ids) async {
    final removed = ids.toSet();
    if (removed.isEmpty) return;
    final remaining = _readPendingIds(key)..removeWhere(removed.contains);
    if (!await _preferences.setString(key, jsonEncode(remaining))) {
      throw StateError('Não foi possível confirmar a sincronização.');
    }
  }

  Future<void> _persistPendingScans(String owner) async {
    final records = owner == userId
        ? List<DetectionRecord>.of(_detections)
        : _decodeRecords(_preferences.getString(_detectionsKeyFor(owner)));

    // Once Supabase confirms the upload, keep only the small outbox on disk.
    // Supabase owns the full history; Firebase stores only the latest action.
    final pending = _readPendingIds(_pendingScanUploadsKeyFor(owner)).toSet();
    final cache =
        _preferences.getBool(_scanUploadQueuePrimedKeyFor(owner)) == true
        ? records.where((record) => pending.contains(record.id)).toList()
        : records;
    final cachedIds = cache.map((record) => record.id).toSet();
    final obsoleteImages = records
          .where((record) => !cachedIds.contains(record.id))
          .map((record) => record.imagePath)
          .toList(growable: false);
    if (!await _preferences.setString(
      _detectionsKeyFor(owner),
      jsonEncode(cache.map((record) => record.toJson()).toList()),
    )) {
      throw StateError('Não foi possível atualizar a fila de leituras.');
    }
    for (final path in obsoleteImages) {
      await _deleteImage(path);
    }
  }

  Future<void> _persistPendingCorrections(String owner) async {
    final samples = owner == userId
        ? List<LearningSample>.of(_learningSamples)
        : _decodeLearningSamples(_preferences.getString(_learningKeyFor(owner)));
    final pending =
        _readPendingIds(_pendingCorrectionUploadsKeyFor(owner)).toSet();
    final cache =
        _preferences.getBool(_correctionUploadQueuePrimedKeyFor(owner)) == true
        ? samples.where((sample) => pending.contains(sample.id)).toList()
        : samples;
    if (!await _preferences.setString(
      _learningKeyFor(owner),
      jsonEncode(cache.map((sample) => sample.toJson()).toList()),
    )) {
      throw StateError('Não foi possível atualizar a fila de correções.');
    }
  }

  List<DetectionRecord> _recordsToCache(
    String owner,
    Iterable<DetectionRecord> records,
  ) {
    if (_preferences.getBool(_scanUploadQueuePrimedKeyFor(owner)) != true) {
      return records.toList(growable: false);
    }
    final pending = _readPendingIds(_pendingScanUploadsKeyFor(owner)).toSet();
    return records
        .where((record) => pending.contains(record.id))
        .toList(growable: false);
  }

  List<LearningSample> _samplesToCache(
    String owner,
    Iterable<LearningSample> samples,
  ) {
    if (_preferences.getBool(_correctionUploadQueuePrimedKeyFor(owner)) !=
        true) {
      return samples.toList(growable: false);
    }
    final pending =
        _readPendingIds(_pendingCorrectionUploadsKeyFor(owner)).toSet();
    return samples
        .where((sample) => pending.contains(sample.id))
        .toList(growable: false);
  }

  /// Removes confirmed account history from disk while retaining pending
  /// uploads. In-memory records stay available until the session ends.
  Future<void> discardSyncedAccountCache() async {
    final owner = userId;
    if (owner == null || owner == 'guest-local') return;
    await _persistPendingScans(owner);
    await _persistPendingCorrections(owner);
  }

  void switchUser(String? uid) {
    if (uid == userId) return;
    userId = uid;
    _detections.clear();
    _learningSamples.clear();
    _knownAchievementIds.clear();
    if (uid != null) {
      _knownAchievementIds.addAll(
        _decodeIds(_preferences.getString(_achievementsKeyFor(uid))),
      );
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

      final knownAchievements = <String>{
        ..._decodeIds(_preferences.getString(_achievementsKeyFor(uid))),
        ..._decodeIds(
          _preferences.getString(_achievementsKeyFor('guest-local')),
        ),
      };
      if (knownAchievements.isNotEmpty &&
          !await _preferences.setString(
            _achievementsKeyFor(uid),
            jsonEncode(knownAchievements.toList()),
          )) {
        throw StateError('Não foi possível transferir as conquistas do visitante.');
      }
      if (_preferences.getBool('ecoscan.map.guest-local') == true) {
        await _preferences.setBool('ecoscan.map.$uid', true);
        await _preferences.setBool(_pendingSettingsKeyFor(uid), true);
      }
      if (_preferences.getBool(_pendingSettingsKeyFor('guest-local')) == true) {
        await _preferences.setBool(_pendingSettingsKeyFor(uid), true);
      }
      if (!await _preferences.setString(migrationKey, uid)) {
        throw StateError('Não foi possível concluir a transferência da conta.');
      }
    }
    switchUser(uid);
  }

  Future<void> setDarkMode(bool value) async {
    await _preferences.setBool('ecoscan.dark', value);
    await _markCloudSettingsPending();
    notifyListeners();
    await _syncCloudSettings();
  }

  Future<void> setSounds(bool value) async {
    await _preferences.setBool('ecoscan.sounds', value);
    await _markCloudSettingsPending();
    notifyListeners();
    await _syncCloudSettings();
  }

  Future<void> setNotifications(bool value) async {
    await _preferences.setBool('ecoscan.notices', value);
    await _markCloudSettingsPending();
    notifyListeners();
    await _syncCloudSettings();
  }

  Future<void> markMapExplored() async {
    if (userId == null) return;
    await _preferences.setBool('ecoscan.map.${userId!}', true);
    await _markCloudSettingsPending();
    notifyListeners();
    await _syncCloudSettings();
  }

  /// Remembers achievements already earned or already announced on this
  /// installation. Cloud achievements are merged here during account restore.
  Future<void> rememberAchievementIds(Iterable<String> achievementIds) async {
    final owner = userId;
    if (owner == null) return;
    final next = <String>{
      ..._knownAchievementIds,
      ...achievementIds.where((id) => id.isNotEmpty),
    };
    if (next.length == _knownAchievementIds.length) return;
    if (!await _preferences.setString(
      _achievementsKeyFor(owner),
      jsonEncode(next.toList()..sort()),
    )) {
      throw StateError('Não foi possível salvar as conquistas da conta.');
    }
    if (userId != owner) return;
    _knownAchievementIds
      ..clear()
      ..addAll(next);
    notifyListeners();
  }

  /// Restaura as preferências da conta no login. Se ainda não houver registro
  /// remoto, envia as preferências já salvas neste aparelho.
  Future<bool> syncAccountSettings() async {
    final owner = userId;
    if (owner == null) return false;
    try {
      final client = Supabase.instance.client;
      if (client.auth.currentUser?.id != owner) return false;
      if (_preferences.getBool(_pendingSettingsKeyFor(owner)) == true ||
          _preferences.getBool(_pendingPhotoKeyFor(owner)) == true) {
        return await _syncCloudSettings();
      }
      final row = await client
          .from('configuracoes_usuario')
          .select(
            'tema,sons_ativos,avisos_ativos,mapa_explorado,caminho_foto_perfil',
          )
          .eq('usuario_id', owner)
          .maybeSingle();
      if (row == null) {
        return await _syncCloudSettings();
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
      if (hasPendingPhoto) return await _syncCloudSettings();
      if (userId == owner) notifyListeners();
      return true;
    } catch (_) {
      // Preferências locais continuam disponíveis quando a nuvem está offline.
      return false;
    }
  }

  /// Sends account settings only when this device has a known local change.
  /// Used by the retry loop so it does not read/write settings on every pass.
  Future<bool> syncPendingAccountSettings() async {
    final owner = userId;
    if (owner == null) return false;
    if (_preferences.getBool(_pendingSettingsKeyFor(owner)) != true &&
        _preferences.getBool(_pendingPhotoKeyFor(owner)) != true) {
      return true;
    }
    return _syncCloudSettings();
  }

  Future<bool> _syncCloudSettings() async {
    final owner = userId;
    if (owner == null) return false;
    try {
      final client = Supabase.instance.client;
      if (client.auth.currentUser?.id != owner) return false;
      final shouldRecordLatestAction =
          _preferences.getBool(_pendingSettingsKeyFor(owner)) == true ||
          _preferences.getBool(_pendingPhotoKeyFor(owner)) == true;
      final remotePhoto = await _uploadProfilePhoto(owner, profilePhoto) ??
          _preferences.getString(_remotePhotoKeyFor(owner));
      if (userId != owner || client.auth.currentUser?.id != owner) return false;
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
      if (shouldRecordLatestAction &&
          FirebaseAccountBackupService.shared.isAvailable) {
        await FirebaseAccountBackupService.shared.saveSettings(
          owner,
          darkMode: darkMode,
          sounds: sounds,
          notifications: notifications,
          mapExplored: exploredMap,
          profilePhoto: profilePhoto,
        );
      }
      if (userId == owner) {
        await _preferences.remove(_pendingPhotoKeyFor(owner));
        await _preferences.remove(_pendingSettingsKeyFor(owner));
      }
      return userId == owner && client.auth.currentUser?.id == owner;
    } catch (_) {
      // A sincronização de preferências será tentada novamente no próximo login.
      return false;
    }
  }

  Future<void> setProfilePhoto(String path) async {
    final owner = userId;
    if (owner == null) return;
    final oldPath = profilePhoto;
    await _preferences.setString('ecoscan.profile.v2.$owner', path);
    await _preferences.setBool(_pendingPhotoKeyFor(owner), true);
    await _markCloudSettingsPending();
    if (userId == owner) notifyListeners();
    if (userId == owner) await _syncCloudSettings();
    if (oldPath != path) await _deleteImage(oldPath);
  }

  Future<void> _markCloudSettingsPending() async {
    final owner = userId;
    if (owner == null) return;
    await _preferences.setBool(_pendingSettingsKeyFor(owner), true);
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
    try {
      await queueScanUpload(record.id, userIdOverride: owner);
      if (owner != 'guest-local') await _persistPendingScans(owner!);
    } catch (_) {
      if (owner != 'guest-local') {
        await _preferences.remove(_scanUploadQueuePrimedKeyFor(owner!));
      }
    }
    notifyListeners();
  }

  /// Merges cloud history into this account while keeping local image files.
  Future<void> mergeCloudDetections(Iterable<DetectionRecord> incoming) async {
    if (userId == null) return;
    final owner = userId!;
    final byId = <String, DetectionRecord>{
      for (final record in _detections)
        if (record.id.isNotEmpty) record.id: record,
    };
    for (final record in incoming) {
      if (record.id.isEmpty) continue;
      final existing = byId[record.id];
      if (existing == null) {
        byId[record.id] = record;
      } else if (record.imagePath.isNotEmpty &&
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
      jsonEncode(
        _recordsToCache(owner, merged)
            .map((record) => record.toJson())
            .toList(),
      ),
    );
    if (!success) throw StateError('Não foi possível restaurar o histórico.');
    if (userId != owner) return;
    beginCloudRestore();
    try {
      _detections
        ..clear()
        ..addAll(merged);
      notifyListeners();
    } finally {
      endCloudRestore();
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
      jsonEncode(
        _recordsToCache(owner, next)
            .map((record) => record.toJson())
            .toList(),
      ),
    );
    if (!success) {
      await acknowledgeScanDeletions(ids, userIdOverride: owner);
      throw StateError('Não foi possível excluir as análises.');
    }
    await acknowledgeScanUploads(ids, userIdOverride: owner);
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
        jsonEncode(
          _recordsToCache(owner, remaining)
              .map((record) => record.toJson())
              .toList(),
        ),
      );
      if (!success) throw StateError('Não foi possível atualizar o histórico.');
    }
    await acknowledgeScanDeletions(deleted, userIdOverride: owner);
    await acknowledgeScanUploads(deleted, userIdOverride: owner);
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
    try {
      await queueCorrectionUpload(sample.id, userIdOverride: owner);
      if (owner != null && owner != 'guest-local') {
        await _persistPendingCorrections(owner);
      }
    } catch (_) {
      if (owner != null && owner != 'guest-local') {
        await _preferences.remove(_correctionUploadQueuePrimedKeyFor(owner));
      }
    }
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
      if (sample.id.isNotEmpty) {
        byId[sample.id] = sample;
      }
    }
    final merged = byId.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final success = await _preferences.setString(
      _learningKeyFor(owner),
      jsonEncode(
        _samplesToCache(owner, merged)
            .map((sample) => sample.toJson())
            .toList(),
      ),
    );
    if (!success) throw StateError('Não foi possível restaurar as correções.');
    if (userId != owner) return;
    beginCloudRestore();
    try {
      _learningSamples
        ..clear()
        ..addAll(merged);
      notifyListeners();
    } finally {
      endCloudRestore();
    }
  }

  Future<void> clearLearningSamples() async {
    if (userId == null) return;
    final owner = userId;
    final ids = _learningSamples.map((sample) => sample.id).toList();
    if (!await _preferences.remove(_learningKey)) {
      throw StateError('Não foi possível limpar as amostras locais.');
    }
    _learningSamples.clear();
    await acknowledgeCorrectionUploads(
      ids,
      userIdOverride: owner,
    );
    if (userId == owner) {
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
    if (userId != owner) return;
    _learningSamples
      ..clear()
      ..addAll(next);
    try {
      await queueCorrectionUpload(updated.id, userIdOverride: owner);
      if (owner != null && owner != 'guest-local') {
        await _persistPendingCorrections(owner);
      }
    } catch (_) {
      if (owner != null && owner != 'guest-local') {
        await _preferences.remove(_correctionUploadQueuePrimedKeyFor(owner));
      }
    }
    notifyListeners();
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
      jsonEncode(
        _samplesToCache(owner!, next).map((item) => item.toJson()).toList(),
      ),
    );
    if (!success) throw StateError('Não foi possível atualizar as amostras.');
    if (userId != owner) return;
    _learningSamples
      ..clear()
      ..addAll(next);
    await acknowledgeCorrectionUploads(ids, userIdOverride: owner);
    notifyListeners();
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

  static Set<String> _decodeIds(String? json) {
    try {
      final decoded = jsonDecode(json ?? '[]');
      if (decoded is! List) return <String>{};
      return decoded
          .map((value) => value.toString())
          .where((id) => id.isNotEmpty)
          .toSet();
    } catch (_) {
      return <String>{};
    }
  }
}
