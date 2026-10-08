import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/achievement_progress.dart';
import '../state/ecoscan_store.dart';
import 'download_screen.dart';
import 'home_screen.dart';
import 'map_screen.dart';
import 'scanner_screen.dart';
import 'settings_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _selected = 0;
  int _mapRevision = 0;
  String? _mapSearch;
  String? _mapMaterialId;
  EcoScanStore? _store;
  String? _storeUserId;
  Set<String> _unlockedBefore = {};
  final List<AchievementProgress> _achievementQueue = [];
  OverlayEntry? _achievementEntry;
  Timer? _achievementTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final store = context.watch<EcoScanStore>();
    if (identical(store, _store)) return;
    _store?.removeListener(_onStoreChanged);
    _store = store;
    _storeUserId = store.userId;
    _unlockedBefore = _unlockedAchievements(store);
    store.addListener(_onStoreChanged);
  }

  Set<String> _unlockedAchievements(EcoScanStore store) =>
      _achievementProgress(store)
          .where((achievement) => achievement.isUnlocked)
          .map((achievement) => achievement.id)
          .toSet();

  List<AchievementProgress> _achievementProgress(EcoScanStore store) =>
      AchievementProgress.build(
        scans: store.scanCount,
        categories: store.detections
            .map((record) => record.category)
            .toSet()
            .length,
        exploredMap: store.exploredMap,
      );

  void _onStoreChanged() {
    final store = _store;
    if (!mounted || store == null) return;
    final unlocked = _unlockedAchievements(store);
    if (_storeUserId != store.userId) {
      _achievementQueue.clear();
      _achievementTimer?.cancel();
      _achievementEntry?.remove();
      _achievementEntry = null;
      _storeUserId = store.userId;
      _unlockedBefore = unlocked;
      return;
    }
    final newlyUnlocked = unlocked.difference(_unlockedBefore);
    _unlockedBefore = unlocked;
    if (newlyUnlocked.isEmpty) return;
    _achievementQueue.addAll(
      _achievementProgress(store).where(
        (achievement) => newlyUnlocked.contains(achievement.id),
      ),
    );
    _showNextAchievementToast();
  }

  void _showNextAchievementToast() {
    if (_achievementEntry != null || _achievementQueue.isEmpty || !mounted) {
      return;
    }
    final achievement = _achievementQueue.removeAt(0);
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    _achievementEntry = OverlayEntry(
      builder: (context) {
        final width = math
            .min(360.0, MediaQuery.sizeOf(context).width - 24)
            .toDouble();
        return Positioned(
          top: MediaQuery.paddingOf(context).top + 12,
          left: 12,
          child: TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 260),
            tween: Tween(begin: 0, end: 1),
            builder: (context, value, child) => Transform.translate(
              offset: Offset(-18 * (1 - value), 0),
              child: Opacity(opacity: value, child: child),
            ),
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: width,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF111A15),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFF70C779),
                    width: 1.5,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black45,
                      blurRadius: 18,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Text(achievement.icon, style: const TextStyle(fontSize: 30)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'CONQUISTA DESBLOQUEADA',
                            style: TextStyle(
                              color: Color(0xFF8FE69A),
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.1,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            achievement.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.verified_rounded,
                      color: Color(0xFF8FE69A),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
    overlay.insert(_achievementEntry!);
    _achievementTimer = Timer(const Duration(seconds: 4), () {
      _achievementEntry?.remove();
      _achievementEntry = null;
      _showNextAchievementToast();
    });
  }

  @override
  void dispose() {
    _store?.removeListener(_onStoreChanged);
    _achievementTimer?.cancel();
    _achievementEntry?.remove();
    super.dispose();
  }

  void _select(int index) {
    setState(() => _selected = index);
  }

  @override
  Widget build(BuildContext context) => PopScope<void>(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && _selected != 0) setState(() => _selected = 0);
    },
    child: Scaffold(
      body: switch (_selected) {
        0 => HomeScreen(
          onOpenMap: () => _select(2),
          onOpenScanner: () => _select(1),
        ),
        1 => ScannerScreen(
          onFindNearby: (result) {
            setState(() {
              _mapSearch = result.detectedObject ?? result.name;
              _mapMaterialId = result.material?.id;
              _mapRevision++;
              _selected = 2;
            });
          },
        ),
        2 => EcoPointsScreen(
          key: ValueKey(_mapRevision),
          initialSearch: _mapSearch,
          initialMaterialId: _mapMaterialId,
        ),
        3 when kIsWeb => const DownloadScreen(),
        _ => SettingsScreen(onOpenMap: () => _select(2)),
      },
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selected,
        onDestinationSelected: _select,
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Início',
          ),
          const NavigationDestination(
            icon: Icon(Icons.center_focus_weak),
            selectedIcon: Icon(Icons.center_focus_strong),
            label: 'Scan',
          ),
          const NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: 'Mapa',
          ),
          if (kIsWeb)
            const NavigationDestination(
              icon: Icon(Icons.download_outlined),
              selectedIcon: Icon(Icons.download_rounded),
              label: 'Baixar',
            ),
          const NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Config',
          ),
        ],
      ),
    ),
  );
}
