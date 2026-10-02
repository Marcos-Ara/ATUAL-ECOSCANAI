import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_session.dart';
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
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation;
  Timer? _timer;
  bool _introComplete = false;
  @override
  void initState() {
    super.initState();
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
    _timer?.cancel();
    _animation.dispose();
    super.dispose();
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
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) store.switchUser(sessionUserId);
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return MainShell(key: ValueKey(sessionUserId));
  }
}
