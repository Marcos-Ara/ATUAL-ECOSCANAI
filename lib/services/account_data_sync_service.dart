import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../state/ecoscan_store.dart';
import 'correction_backup_sync_service.dart';
import 'scan_sync_service.dart';

/// Coordinates cloud restore, background sync, and the last save attempt.
/// Every mutation is written locally first; this service flushes pending data
/// when connectivity is available.
class AccountDataSyncService {
  AccountDataSyncService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  static final AccountDataSyncService shared = AccountDataSyncService();

  final SupabaseClient _client;
  final Map<String, Future<bool>> _inFlight = <String, Future<bool>>{};

  Future<bool> restoreAccount(EcoScanStore store) =>
      _runLocked(store, () => _restore(store));

  Future<bool> savePendingBeforeExit(EcoScanStore store) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return store.userId == 'guest-local' || store.userId == null;
    return _runLocked(store, () => _savePending(store, uid));
  }

  Future<bool> _runLocked(
    EcoScanStore store,
    Future<bool> Function() operation,
  ) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null || store.userId != uid) return false;

    final existing = _inFlight[uid];
    if (existing != null) {
      final completed = await existing;
      if (completed || store.userId != uid || _client.auth.currentUser?.id != uid) {
        return completed;
      }
    }

    final result = Completer<bool>();
    final running = result.future;
    _inFlight[uid] = running;
    store.setAccountDataSyncing(uid, true);
    var success = false;
    try {
      success = await operation();
      return success;
    } catch (_) {
      return false;
    } finally {
      store.setAccountDataSyncing(uid, false);
      if (!result.isCompleted) result.complete(success);
      if (identical(_inFlight[uid], running)) _inFlight.remove(uid);
    }
  }

  Future<bool> _restore(EcoScanStore store) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null || store.userId != uid) return false;
    var success = true;
    final scanSync = ScanSyncService(client: _client);
    final correctionSync = CorrectionBackupSyncService(client: _client);

    try {
      final settingsSaved = await store
          .syncAccountSettings()
          .timeout(const Duration(seconds: 12));
      success = success && settingsSaved;
    } catch (_) {
      success = false;
    }

    if (!_isCurrent(store, uid)) return false;
    try {
      await scanSync
          .reconcileDeletions(store)
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      success = false;
    }

    if (!_isCurrent(store, uid)) return false;
    try {
      await scanSync
          .syncAll(store.detections)
          .timeout(const Duration(seconds: 35));
    } catch (_) {
      success = false;
    }

    if (!_isCurrent(store, uid)) return false;
    try {
      final records = await scanSync
          .fetchAll()
          .timeout(const Duration(seconds: 35));
      if (!_isCurrent(store, uid)) return false;
      await store.mergeCloudDetections(records);
    } catch (_) {
      success = false;
    }

    if (!_isCurrent(store, uid)) return false;
    try {
      final correctionsSaved = await correctionSync
          .syncAndRestore(store)
          .timeout(const Duration(seconds: 35));
      success = success && correctionsSaved;
    } catch (_) {
      success = false;
    }

    if (!_isCurrent(store, uid)) return false;
    try {
      final unlocked = await scanSync
          .fetchUnlockedAchievementIds()
          .timeout(const Duration(seconds: 15));
      if (!_isCurrent(store, uid)) return false;
      await store.rememberAchievementIds(unlocked);
    } catch (_) {
      success = false;
    }
    return success && _isCurrent(store, uid);
  }

  Future<bool> _savePending(EcoScanStore store, String uid) async {
    if (!_isCurrent(store, uid)) return false;
    var success = true;
    final scanSync = ScanSyncService(client: _client);
    final correctionSync = CorrectionBackupSyncService(client: _client);

    try {
      final settingsSaved = await store
          .syncAccountSettings()
          .timeout(const Duration(seconds: 12));
      success = success && settingsSaved;
    } catch (_) {
      success = false;
    }

    if (!_isCurrent(store, uid)) return false;
    try {
      await scanSync
          .reconcileDeletions(store)
          .timeout(const Duration(seconds: 20));
      await scanSync
          .syncAll(store.detections)
          .timeout(const Duration(seconds: 35));
    } catch (_) {
      success = false;
    }

    if (!_isCurrent(store, uid)) return false;
    try {
      final correctionsSaved = await correctionSync
          .uploadPending(store)
          .timeout(const Duration(seconds: 35));
      success = success && correctionsSaved;
    } catch (_) {
      success = false;
    }
    return success && _isCurrent(store, uid);
  }

  bool _isCurrent(EcoScanStore store, String uid) =>
      store.userId == uid && _client.auth.currentUser?.id == uid;
}
