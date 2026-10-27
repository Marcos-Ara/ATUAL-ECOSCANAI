import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_config.dart';
import '../services/account_data_sync_service.dart';
import '../services/auth_session.dart';
import '../state/ecoscan_store.dart';
import 'auth_screen.dart';
import 'main_shell.dart';

class SessionGate extends StatefulWidget {
  const SessionGate({super.key});
  @override
  State<SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<SessionGate>
    with WidgetsBindingObserver {
  Timer? _pendingSyncTimer;
  AppLifecycleState _lifecycleState = AppLifecycleState.resumed;
  bool _switchingUser = false;
  bool _initialRestoreInProgress = false;
  bool _initialRestoreFailed = false;
  String? _activeRestoreUserId;
  String? _restoredUserId;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lifecycleState =
        WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;
    _pendingSyncTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _retryPendingAccountSync();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pendingSyncTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
    if (!mounted || !AppConfig.syncSupabaseHistory) return;
    final auth = context.read<AuthSession>();
    final userId = auth.account?.uid;
    if (auth.isGuest || userId == null) return;
    final store = context.read<EcoScanStore>();
    if (store.userId != userId) return;
    if (state == AppLifecycleState.resumed && _restoredUserId != userId) {
      _startInitialRestore(store, userId);
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      // Flush the local outbox before the operating system may suspend us.
      unawaited(AccountDataSyncService.shared.syncPending(store));
    } else if (state == AppLifecycleState.resumed &&
        _restoredUserId == userId) {
      unawaited(_syncAccount(store, userId));
    }
  }

  void _retryPendingAccountSync() {
    if (!mounted ||
        !AppConfig.syncSupabaseHistory ||
        _lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    final auth = context.read<AuthSession>();
    final userId = auth.account?.uid;
    if (auth.isGuest || userId == null) return;
    final store = context.read<EcoScanStore>();
    if (store.userId != userId) return;
    if (_restoredUserId != userId) {
      if (!_initialRestoreInProgress) _startInitialRestore(store, userId);
      return;
    }
    if (store.hasPendingAccountSync) {
      unawaited(AccountDataSyncService.shared.syncPending(store));
    }
  }

  Future<bool> _syncAccount(EcoScanStore store, String userId) async {
    if (store.userId != userId) return false;
    var restored = false;
    try {
      restored = await AccountDataSyncService.shared.restoreAccount(store);
    } catch (_) {
      // The local history remains usable and the account retries in background.
    } finally {
      if (mounted && AppConfig.syncSupabaseHistory) {
        final auth = context.read<AuthSession>();
        final currentUserId = auth.account?.uid;
        final currentStore = context.read<EcoScanStore>();
        if (!auth.isGuest &&
            currentUserId != null &&
            currentUserId != userId &&
            currentStore.userId == currentUserId) {
          unawaited(_syncAccount(currentStore, currentUserId));
        }
      }
    }
    return restored;
  }

  void _startInitialRestore(EcoScanStore store, String userId) {
    if (_initialRestoreInProgress ||
        _restoredUserId == userId ||
        store.userId != userId) {
      return;
    }
    _initialRestoreInProgress = true;
    _initialRestoreFailed = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_finishInitialRestore(store, userId));
    });
  }

  Future<void> _finishInitialRestore(
    EcoScanStore store,
    String userId,
  ) async {
    final restored = await _syncAccount(store, userId);
    if (!mounted || _activeRestoreUserId != userId) return;
    final auth = context.read<AuthSession>();
    if (auth.isGuest || auth.account?.uid != userId || store.userId != userId) {
      _initialRestoreInProgress = false;
      return;
    }
    setState(() {
      _initialRestoreInProgress = false;
      _initialRestoreFailed = !restored;
      if (restored) _restoredUserId = userId;
    });
    if (store.hasPendingAccountSync) {
      unawaited(AccountDataSyncService.shared.syncPending(store));
    }
  }

  Widget _preparingAccountScreen() {
    return Scaffold(
      backgroundColor: const Color(0xFF071008),
      body: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFF9BF29E)),
            SizedBox(height: 14),
            Text(
              'Preparando sua conta',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthSession>();
    if (auth.account == null && !auth.isGuest) return const AuthScreen();
    if (!auth.isGuest && auth.passwordRecovery) {
      return const PasswordRecoveryScreen();
    }
    if (!auth.isGuest && auth.account?.verified == false) {
      return const VerificationScreen();
    }

    final sessionUserId = auth.isGuest
        ? AuthSession.guestUserId
        : auth.account!.uid;
    if (_activeRestoreUserId != sessionUserId) {
      _activeRestoreUserId = sessionUserId;
      _restoredUserId = null;
      _initialRestoreFailed = false;
      _initialRestoreInProgress = false;
    }
    final store = context.watch<EcoScanStore>();
    if (store.userId != sessionUserId) {
      if (!_switchingUser) {
        _switchingUser = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          unawaited(() async {
            try {
              await store.switchUserWithGuestData(sessionUserId);
            } catch (_) {
              // Keep the account accessible; the guest copy remains local and
              // the transfer can be retried the next time this account opens.
              store.switchUser(sessionUserId);
            }
            if (!mounted) return;
            setState(() => _switchingUser = false);
          }());
        });
      }
      return _preparingAccountScreen();
    }
    if (!auth.isGuest && AppConfig.syncSupabaseHistory) {
      if (_restoredUserId != sessionUserId &&
          !_initialRestoreInProgress &&
          !_initialRestoreFailed) {
        _startInitialRestore(store, sessionUserId);
      }
    }
    return MainShell(key: ValueKey(sessionUserId));
  }
}
