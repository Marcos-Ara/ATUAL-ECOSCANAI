import 'package:flutter/material.dart';
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
        _ => SettingsScreen(onOpenMap: () => _select(2)),
      },
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selected,
        onDestinationSelected: _select,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Início',
          ),
          NavigationDestination(
            icon: Icon(Icons.center_focus_weak),
            selectedIcon: Icon(Icons.center_focus_strong),
            label: 'Scan',
          ),
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: 'Mapa',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Config',
          ),
        ],
      ),
    ),
  );
}
