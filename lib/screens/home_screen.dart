import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_theme.dart';
import '../models/material_guide.dart';
import '../services/auth_session.dart';
import '../state/ecoscan_store.dart';
import '../widgets/account_avatar.dart';
import 'community_screens.dart';
import 'history_screen.dart';
import 'profile_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    required this.onOpenMap,
    required this.onOpenScanner,
    super.key,
  });
  final VoidCallback onOpenMap;
  final VoidCallback onOpenScanner;
  void _open(BuildContext context, Widget screen) =>
      Navigator.push(context, MaterialPageRoute<void>(builder: (_) => screen));
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthSession>();
    final user = auth.account;
    final store = context.watch<EcoScanStore>();
    final name = auth.isGuest
        ? 'Visitante'
        : user?.name.isNotEmpty == true
        ? user!.name.split(' ').first
        : 'usuário';
    final records = store.detections;
    final recycled = records
        .where((r) => MaterialGuide.byName(r.category)?.recyclable == true)
        .length;
    final organic = records.where((r) => r.category == 'Orgânico').length;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      auth.isGuest ? 'Modo visitante' : 'Bem-vindo de volta',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Olá, $name!',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ],
                ),
              ),
              AccountAvatar(
                onTap: auth.isGuest
                    ? null
                    : () => _open(context, const ProfileScreen()),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: _Stat(
                  value: records.length,
                  label: 'Detectados',
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _Stat(
                  value: recycled,
                  label: 'Recicláveis',
                  color: AppColors.blue,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _Stat(
                  value: organic,
                  label: 'Orgânicos',
                  color: const Color(0xFFDE8A00),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onOpenScanner,
            icon: const Icon(Icons.center_focus_strong, size: 26),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 22),
              backgroundColor: AppColors.primaryDark,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            label: const Text(
              'Iniciar Escaneamento',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 20),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.28,
            children: [
              _Menu(
                icon: Icons.history,
                title: 'Histórico',
                onTap: () => _open(context, const HistoryScreen()),
              ),
              _Menu(
                icon: Icons.bar_chart,
                title: 'Estatísticas',
                onTap: () => _open(context, const StatsScreen()),
              ),
              _Menu(
                icon: Icons.school_outlined,
                title: 'Aprender',
                onTap: () => _open(context, const LearnScreen()),
              ),
              _Menu(
                icon: Icons.emoji_events_outlined,
                title: 'Conquistas',
                onTap: () => _open(context, const AchievementsScreen()),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              contentPadding: const EdgeInsets.all(18),
              leading: const Icon(
                Icons.map_outlined,
                size: 34,
                color: AppColors.primary,
              ),
              title: const Text(
                'EcoPontos',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              subtitle: const Text(
                'Encontrar locais de descarte perto de você',
              ),
              trailing: const Icon(Icons.north_east),
              onTap: onOpenMap,
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              contentPadding: const EdgeInsets.all(18),
              leading: const Icon(
                Icons.people_outline,
                color: AppColors.primary,
                size: 30,
              ),
              title: const Text(
                'Criadores',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: const Text('Quem fez o EcoScan AI'),
              onTap: () => _open(context, const CreatorsScreen()),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Escaneie. Descubra. Descarte melhor.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, required this.color});
  final int value;
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 6),
      child: Column(
        children: [
          Text(
            '$value',
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    ),
  );
}

class _Menu extends StatelessWidget {
  const _Menu({required this.icon, required this.title, required this.onTap});
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 31, color: AppColors.primary),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    ),
  );
}
