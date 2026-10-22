import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_config.dart';
import '../services/auth_session.dart';
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
  bool _introComplete = false;
  bool _syncingAccount = false;
  bool _switchingUser = false;
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
    _animation.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed ||
        !mounted ||
        !AppConfig.syncSupabaseHistory) {
      return;
    }
    final auth = context.read<AuthSession>();
    final userId = auth.account?.uid;
    if (auth.isGuest || userId == null) return;
    final store = context.read<EcoScanStore>();
    if (store.userId == userId) unawaited(_syncAccount(store, userId));
  }

  Future<void> _syncAccount(EcoScanStore store, String userId) async {
    if (_syncingAccount || store.userId != userId) return;
    _syncingAccount = true;
    try {
      await store.syncAccountSettings();
      if (!mounted || store.userId != userId) return;
      final sync = ScanSyncService();
      await sync.reconcileDeletions(store);
      if (!mounted || store.userId != userId) return;
      await sync.syncAll(store.detections);
      if (!mounted || store.userId != userId) return;
      final cloudRecords = await sync.fetchAll();
      if (!mounted || store.userId != userId) return;
      await store.mergeCloudDetections(cloudRecords);
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
            final currentAuth = context.read<AuthSession>();
            if (!currentAuth.isGuest &&
                currentAuth.account?.uid == sessionUserId &&
                AppConfig.syncSupabaseHistory) {
              unawaited(_syncAccount(store, sessionUserId));
            }
            setState(() => _switchingUser = false);
          }());
        });
      }
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return MainShell(key: ValueKey(sessionUserId));
  }
}
