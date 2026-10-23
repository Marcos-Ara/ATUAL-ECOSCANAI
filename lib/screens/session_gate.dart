import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_config.dart';
import '../services/auth_session.dart';
import '../services/correction_backup_sync_service.dart';
import '../services/scan_sync_service.dart';
import '../state/ecoscan_store.dart';
import '../widgets/eco_brand.dart';
import 'auth_screen.dart';
import 'main_shell.dart';

class SessionGate extends StatefulWidget {
  const SessionGate({super.key});
  @override
  State<SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<SessionGate>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _animation;
  Timer? _timer;
  Timer? _slowRestoreTimer;
  bool _introComplete = false;
  bool _syncingAccount = false;
  bool _switchingUser = false;
  bool _initialRestoreInProgress = false;
  bool _initialRestoreFailed = false;
  bool _showLocalFallback = false;
  String? _activeRestoreUserId;
  String? _restoredUserId;
  String? _localFallbackUserId;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _animation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
    _timer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) {
        _animation.stop();
        setState(() => _introComplete = true);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _slowRestoreTimer?.cancel();
    _animation.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted || !AppConfig.syncSupabaseHistory) return;
    final auth = context.read<AuthSession>();
    final userId = auth.account?.uid;
    if (auth.isGuest || userId == null) return;
    final store = context.read<EcoScanStore>();
    if (store.userId != userId) return;
    if (state == AppLifecycleState.resumed && _restoredUserId != userId) {
      if (_localFallbackUserId == userId) {
        unawaited(_syncAccount(store, userId));
      } else {
        _startInitialRestore(store, userId);
      }
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      // Each action is persisted immediately; this is an extra opportunity to
      // flush anything that is waiting when the app moves out of view.
      unawaited(_syncAccount(store, userId));
    } else if (state == AppLifecycleState.resumed &&
        _restoredUserId == userId) {
      unawaited(_syncAccount(store, userId));
    }
  }

  Future<bool> _syncAccount(EcoScanStore store, String userId) async {
    if (_syncingAccount || store.userId != userId) return false;
    _syncingAccount = true;
    var restored = false;
    try {
      if (!await store.syncAccountSettings()) return false;
      if (!mounted || store.userId != userId) return false;
      final sync = ScanSyncService();
      await sync.reconcileDeletions(store);
      if (!mounted || store.userId != userId) return false;
      await sync.syncAll(store.detections);
      if (!mounted || store.userId != userId) return false;
      final cloudRecords = await sync.fetchAll();
      if (!mounted || store.userId != userId) return false;
      await store.mergeCloudDetections(cloudRecords);
      if (!mounted || store.userId != userId) return false;
      await CorrectionBackupSyncService().syncAndRestore(store);
      if (!mounted || store.userId != userId) return false;
      final unlocked = await sync.fetchUnlockedAchievementIds();
      if (!mounted || store.userId != userId) return false;
      await store.rememberAchievementIds(unlocked);
      restored = true;
    } catch (_) {
      // The local history remains usable and will retry on the next resume.
    } finally {
      _syncingAccount = false;
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
    _showLocalFallback = false;
    _slowRestoreTimer?.cancel();
    _slowRestoreTimer = Timer(const Duration(seconds: 12), () {
      if (!mounted ||
          _activeRestoreUserId != userId ||
          _restoredUserId == userId) {
        return;
      }
      setState(() => _showLocalFallback = true);
    });
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
    _slowRestoreTimer?.cancel();
    setState(() {
      _initialRestoreInProgress = false;
      _initialRestoreFailed = !restored;
      _showLocalFallback = !restored;
      if (restored) _restoredUserId = userId;
    });
  }

  void _retryRestore(EcoScanStore store, String userId) {
    setState(() {
      _localFallbackUserId = null;
      _initialRestoreFailed = false;
      _showLocalFallback = false;
    });
    _startInitialRestore(store, userId);
  }

  void _continueWithLocalData(String userId) {
    setState(() {
      _localFallbackUserId = userId;
      _initialRestoreFailed = false;
    });
  }

  Widget _restoreLoadingScreen({required bool preparing}) {
    return Scaffold(
      backgroundColor: const Color(0xFF071008),
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            colors: [Color(0xFF16371C), Color(0xFF071008)],
            radius: 0.85,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const EcoBrand(size: 92, ring: true),
                  const SizedBox(height: 24),
                  Text(
                    preparing ? 'Preparando seus dados' : 'Carregando seus dados',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 23,
                      fontWeight: FontWeight.w800,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    preparing
                        ? 'Abrindo seu histórico e suas preferências.'
                        : 'Estamos buscando seu histórico, suas correções e suas conquistas salvas.',
                    style: const TextStyle(
                      color: Color(0xBBE9FAEB),
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  const SizedBox(
                    width: 30,
                    height: 30,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: Color(0xFF9BF29E),
                    ),
                  ),
                  if (!preparing && (_showLocalFallback || _initialRestoreFailed)) ...[
                    const SizedBox(height: 22),
                    const Text(
                      'A conexão está demorando. Você pode tentar de novo ou abrir com os dados já guardados neste aparelho.',
                      style: TextStyle(color: Color(0xFFD5E4D6), height: 1.45),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _initialRestoreInProgress
                          ? null
                          : () {
                              final auth = context.read<AuthSession>();
                              final store = context.read<EcoScanStore>();
                              final userId = auth.account?.uid;
                              if (userId != null) {
                                _retryRestore(store, userId);
                              }
                            },
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(
                        _initialRestoreInProgress
                            ? 'Carregamento em andamento'
                            : 'Tentar novamente',
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        final userId = context.read<AuthSession>().account?.uid;
                        if (userId != null) _continueWithLocalData(userId);
                      },
                      child: const Text('Continuar com dados deste aparelho'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthSession>();
    if (!_introComplete) {
      return Scaffold(
        backgroundColor: const Color(0xFF071008),
        body: Container(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              colors: [Color(0xFF16371C), Color(0xFF071008)],
              radius: 0.8,
            ),
          ),
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedBuilder(
                      animation: _animation,
                      builder: (_, child) => Transform.scale(
                        scale:
                            1 + 0.04 * math.sin(_animation.value * math.pi * 2),
                        child: child,
                      ),
                      child: const EcoBrand(size: 140, ring: true),
                    ),
                    const SizedBox(height: 24),
                    const Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: 'EcoScan '),
                          TextSpan(
                            text: 'AI',
                            style: TextStyle(color: Color(0xFF77DF7B)),
                          ),
                        ],
                      ),
                      style: TextStyle(
                        fontSize: 42,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -2,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Escaneie. Descubra. Descarte melhor.',
                      style: TextStyle(color: Color(0xBBE9FAEB), fontSize: 13),
                    ),
                  ],
                ),
              ),
              const Positioned(
                left: 80,
                right: 80,
                bottom: 80,
                child: LinearProgressIndicator(
                  minHeight: 3,
                  color: Color(0xFF9BF29E),
                  backgroundColor: Color(0x22FFFFFF),
                ),
              ),
            ],
          ),
        ),
      );
    }
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
      _localFallbackUserId = null;
      _initialRestoreFailed = false;
      _showLocalFallback = false;
      _initialRestoreInProgress = false;
      _slowRestoreTimer?.cancel();
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
      return _restoreLoadingScreen(preparing: true);
    }
    if (!auth.isGuest && AppConfig.syncSupabaseHistory) {
      if (_localFallbackUserId == sessionUserId) {
        return MainShell(key: ValueKey(sessionUserId));
      }
      if (_restoredUserId != sessionUserId) {
        if (!_initialRestoreInProgress && !_initialRestoreFailed) {
          _startInitialRestore(store, sessionUserId);
        }
        return _restoreLoadingScreen(preparing: false);
      }
    }
    return MainShell(key: ValueKey(sessionUserId));
  }
}
