import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/achievement_progress.dart';
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
  final Map<String, int> _retryFailures = <String, int>{};
  final Map<String, DateTime> _retryAfter = <String, DateTime>{};

  Future<bool> restoreAccount(EcoScanStore store) async {
    final uid = _client.auth.currentUser?.id;
    final restored = await _runLocked(store, () => _restore(store));
    if (uid != null && restored) _clearRetryState(uid);
    return restored;
  }

  Future<bool> savePendingBeforeExit(EcoScanStore store) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return store.userId == 'guest-local' || store.userId == null;
    final saved = await _runLocked(store, () => _savePending(store, uid));
    if (saved) _clearRetryState(uid);
    return saved;
  }

  /// Retries the durable local outbox without downloading the full account
  /// history. Safe to call after reconnecting or on a foreground timer.
  Future<bool> syncPending(EcoScanStore store) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null || store.userId != uid) return false;
    if (!store.hasPendingAccountSync) return true;
    final retryAfter = _retryAfter[uid];
    if (retryAfter != null && DateTime.now().isBefore(retryAfter)) return false;

    final saved = await _runLocked(store, () => _savePending(store, uid));
    if (saved) {
      _clearRetryState(uid);
      return true;
    }
    final failures = (_retryFailures[uid] ?? 0) + 1;
    _retryFailures[uid] = failures;
    final exponent = (failures - 1).clamp(0, 5).toInt();
    final seconds = (30 * (1 << exponent)).clamp(30, 900).toInt();
    _retryAfter[uid] = DateTime.now().add(Duration(seconds: seconds));
    return false;
  }

  void _clearRetryState(String uid) {
    _retryFailures.remove(uid);
    _retryAfter.remove(uid);
  }

  Future<bool> _runLocked(
    EcoScanStore store,
    Future<bool> Function() operation,
  ) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null || store.userId != uid) return false;

    final existing = _inFlight[uid];
    if (existing != null) return existing;

    final result = Completer<bool>();
    final running = result.future;
    _inFlight[uid] = running;
    var success = false;
    try {
      success = await operation();
      return success;
    } catch (_) {
      return false;
    } finally {
      if (!result.isCompleted) result.complete(success);
      if (identical(_inFlight[uid], running)) _inFlight.remove(uid);
    }
  }

  Future<bool> _restore(EcoScanStore store) async {
    store.beginCloudRestore();
    try {
      return await _restoreFromSupabase(store);
    } finally {
      store.endCloudRestore();
    }
  }

  Future<bool> _restoreFromSupabase(EcoScanStore store) async {
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
      await store.primePendingScanUploadQueue();
      final scansSaved = await scanSync
          .syncPending(store)
          .timeout(const Duration(seconds: 35));
      success = success && scansSaved;
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
      await store.primePendingCorrectionUploadQueue();
      final correctionsSaved = await correctionSync
          .syncAndRestore(store)
          .timeout(const Duration(seconds: 35));
      success = success && correctionsSaved;
    } catch (_) {
      success = false;
    }

    if (!_isCurrent(store, uid)) return false;
    var unlocked = <String>{};
    try {
      unlocked = await scanSync
          .fetchUnlockedAchievementIds()
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      // If the achievement query is unavailable, derive unlocked IDs from
      // the restored account state so reinstalling cannot replay old toasts.
      success = false;
      unlocked = AchievementProgress.build(
        scans: store.scanCount,
        categories: store.detections
            .map((record) => record.category)
            .toSet()
            .length,
        exploredMap: store.exploredMap,
        previouslyUnlocked: store.knownAchievementIds,
      ).where((item) => item.isUnlocked).map((item) => item.id).toSet();
    }
    unlocked.addAll(
      AchievementProgress.build(
        scans: store.scanCount,
        categories: store.detections
            .map((record) => record.category)
            .toSet()
            .length,
        exploredMap: store.exploredMap,
        previouslyUnlocked: store.knownAchievementIds,
      ).where((item) => item.isUnlocked).map((item) => item.id),
    );
    if (!_isCurrent(store, uid)) return false;
    await store.rememberAchievementIds(unlocked);

    if (!_isCurrent(store, uid)) return false;
    await store.discardSyncedAccountCache();
    return success && _isCurrent(store, uid);
  }

  Future<bool> _savePending(EcoScanStore store, String uid) async {
    if (!_isCurrent(store, uid)) return false;
    try {
      await store.primePendingScanUploadQueue();
      await store.primePendingCorrectionUploadQueue();
    } catch (_) {
      return false;
    }
    if (!store.hasPendingAccountSync) {
      await store.discardSyncedAccountCache();
      return true;
    }

    var success = true;
    final scanSync = ScanSyncService(client: _client);
    final correctionSync = CorrectionBackupSyncService(client: _client);

    try {
      final settingsSaved = await store
          .syncPendingAccountSettings()
          .timeout(const Duration(seconds: 12));
      success = success && settingsSaved;
    } catch (_) {
      success = false;
    }

    if (!_isCurrent(store, uid)) return false;
    try {
      if (store.pendingScanDeletionIds.isNotEmpty) {
        await scanSync
            .reconcileDeletions(store)
            .timeout(const Duration(seconds: 20));
      }
      final scansSaved = await scanSync
          .syncPending(store)
          .timeout(const Duration(seconds: 35));
      success = success && scansSaved;
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
    if (!_isCurrent(store, uid)) return false;
    if (success && _isCurrent(store, uid)) {
      await store.discardSyncedAccountCache();
    }
    return success && _isCurrent(store, uid);
  }

  bool _isCurrent(EcoScanStore store, String uid) =>
      store.userId == uid && _client.auth.currentUser?.id == uid;
}
