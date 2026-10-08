import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/achievement_progress.dart';
import '../models/material_guide.dart';
import '../state/ecoscan_store.dart';
import '../widgets/eco_brand.dart';

class LearnScreen extends StatelessWidget {
  const LearnScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Aprender')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Descubra o destino certo',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        const Text(
          'Identifique o material, confira a cor da lixeira e prepare o descarte. Separe materiais diferentes e siga a coleta da sua cidade.',
        ),
        const SizedBox(height: 20),
        for (final guide in MaterialGuide.all)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.delete_outline,
                          color: guide.color,
                          size: 32,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            guide.name,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      guide.bin == 'Coleta especial'
                          ? guide.bin
                          : 'Lixeira ${guide.bin.toLowerCase()}',
                      style: TextStyle(
                        color: guide.color,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(guide.instruction),
                    const SizedBox(height: 8),
                    Text(
                      guide.exclusions,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final records = context.watch<EcoScanStore>().detections;
    return Scaffold(
      appBar: AppBar(title: const Text('Estatísticas')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Distribuição por material',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text('${records.length} análises salvas'),
          const SizedBox(height: 24),
          for (final material in MaterialGuide.all)
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Builder(
                builder: (context) {
                  final count = records
                      .where((r) => r.category == material.name)
                      .length;
                  return Column(
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text(material.name)),
                          Text(count.toString()),
                        ],
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: records.isEmpty ? 0 : count / records.length,
                        color: material.color,
                        minHeight: 11,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ],
                  );
                },
              ),
            ),
          const SizedBox(height: 12),
          Text(
            'Nível ecológico',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 10),
          Text(achievementLevel(ecoPoints(context.read<EcoScanStore>()))),
        ],
      ),
    );
  }
}

int ecoPoints(EcoScanStore store) {
  final records = store.detections;
  final categories = records.map((r) => r.category).toSet().length;
  final recycled = records
      .where((r) => MaterialGuide.byName(r.category)?.recyclable == true)
      .length;
  final bonus =
      records
          .where(
            (r) => const [
              'Papel',
              'Plástico',
              'Vidro',
              'Metal',
              'Orgânico',
              'Eletrônico',
            ].contains(r.category),
          )
          .length *
      5;
  return records.length * 10 + recycled * 5 + categories * 10 + bonus;
}

String achievementLevel(int points) {
  if (points >= 2000) return '👑 Lenda do EcoScan';
  if (points >= 1000) return '🏆 Mestre Sustentável';
  if (points >= 500) return '🌎 Protetor do Planeta';
  if (points >= 250) return '🌿 Guardião dos Materiais';
  if (points >= 100) return '♻️ Aprendiz da Reciclagem';
  return '🌱 Iniciante Verde';
}

class AchievementsScreen extends StatelessWidget {
  const AchievementsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final store = context.watch<EcoScanStore>();
    final scans = store.scanCount;
    final categories = store.detections.map((r) => r.category).toSet().length;
    final points = ecoPoints(store);
    final medals = AchievementProgress.build(
      scans: scans,
      categories: categories,
      exploredMap: store.exploredMap,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Conquistas')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    achievementLevel(points),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '$points pontos',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    scans == 0
                        ? 'Primeiro passo: salve uma análise e descubra o destino correto.'
                        : 'Descubra novos materiais e avance na sua jornada ecológica.',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          for (final medal in medals)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Text(
                        medal.icon,
                        style: TextStyle(
                          fontSize: 30,
                          color: medal.isUnlocked ? null : Colors.grey,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              medal.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            LinearProgressIndicator(
                              value: medal.fraction,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${medal.displayedCurrent} / ${medal.target}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Icon(
                        medal.isUnlocked
                            ? Icons.verified
                            : Icons.lock_outline,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class CreatorsScreen extends StatelessWidget {
  const CreatorsScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Criadores')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Center(child: EcoBrand(size: 100)),
        const SizedBox(height: 24),
        ListTile(
          leading: const CircleAvatar(child: Text('MV')),
          title: const Row(
            children: [
              Expanded(child: Text('Marcos Vinicius')),
              SizedBox(width: 8),
              Text(
                'RGM 33712816',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          subtitle: Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('Desenvolvimento / Projeto'),
              TextButton.icon(
                onPressed: () => launchUrl(
                  Uri.parse('https://github.com/Marcos-Ara'),
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.code_rounded, size: 17),
                label: const Text('GitHub'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'EcoScan AI\nEscaneie. Descubra. Descarte melhor.',
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );
}
