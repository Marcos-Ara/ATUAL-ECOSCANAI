import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/detection_record.dart';
import '../models/material_guide.dart';
import '../state/ecoscan_store.dart';
import '../widgets/app_image.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final store = context.watch<EcoScanStore>();
    final records = store.detections;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Histórico'),
        actions: [
          if (records.isNotEmpty)
            TextButton(
              onPressed: () => _clear(context, store),
              child: const Text('Limpar'),
            ),
        ],
      ),
      body: records.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.history, size: 60),
                    SizedBox(height: 18),
                    Text(
                      'Nenhuma análise salva ainda',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Use a câmera ou a galeria e toque em Salvar análise.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: records.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final record = records[index];
                return Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(12),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => DetectionDetailScreen(record: record),
                      ),
                    ),
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: AppImage(
                        source: record.imagePath,
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                        fallback: const SizedBox.square(
                          dimension: 64,
                          child: Icon(Icons.image_outlined),
                        ),
                      ),
                    ),
                    title: Text(
                      record.category,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      '${record.detectedObject ?? record.bin}\n${_date(record.detectedAt)}',
                    ),
                    isThreeLine: true,
                    trailing: IconButton(
                      tooltip: 'Excluir análise',
                      onPressed: () => store.removeDetection(record),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ),
                );
              },
            ),
    );
  }

  static Future<void> _clear(BuildContext context, EcoScanStore store) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Limpar histórico?'),
        content: const Text(
          'As análises e fotos desta conta serão removidas deste aparelho.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Limpar'),
          ),
        ],
      ),
    );
    if (approved == true) await store.clearHistory();
  }
}

class DetectionDetailScreen extends StatelessWidget {
  const DetectionDetailScreen({required this.record, super.key});
  final DetectionRecord record;
  @override
  Widget build(BuildContext context) {
    final material = MaterialGuide.byName(record.category);
    return Scaffold(
      appBar: AppBar(title: const Text('Análise salva')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: AppImage(
              source: record.imagePath,
              height: 300,
              fit: BoxFit.contain,
              fallback: const SizedBox(
                height: 180,
                child: Icon(Icons.image_outlined, size: 60),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            record.category,
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: 8),
          Text(
            record.bin == 'Coleta especial'
                ? record.bin
                : 'Lixeira ${record.bin.toLowerCase()}',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: material?.color,
            ),
          ),
          const SizedBox(height: 16),
          Text(record.destination, style: const TextStyle(height: 1.6)),
          const SizedBox(height: 16),
          Text(_date(record.detectedAt)),
          Text(
            record.source == 'gallery' ? 'Imagem da galeria' : 'Foto da câmera',
          ),
          if (record.detectedObject?.isNotEmpty == true)
            Text('Objeto detectado: ${record.detectedObject}'),
          if (record.detector?.isNotEmpty == true)
            Text('Detector: ${record.detector}'),
          Text(
            record.confirmedByUser
                ? 'Material confirmado por você'
                : 'Material sugerido pela análise da imagem',
          ),
          if (record.latitude != null && record.longitude != null) ...[
            const SizedBox(height: 18),
            OutlinedButton.icon(
              icon: const Icon(Icons.map_outlined),
              label: const Text('Ver local da captura'),
              onPressed: () async {
                final uri = Uri.https('www.google.com', '/maps/search/', {
                  'api': '1',
                  'query':
                      '${record.latitude},${record.longitude}',
                });
                if (!await launchUrl(
                      uri,
                      mode: LaunchMode.externalApplication,
                    ) &&
                    context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Não foi possível abrir o mapa.'),
                    ),
                  );
                }
              },
            ),
          ],
          const SizedBox(height: 18),
          OutlinedButton.icon(
            icon: const Icon(Icons.delete_outline),
            label: const Text('Excluir análise'),
            onPressed: () async {
              await context.read<EcoScanStore>().removeDetection(record);
              if (context.mounted) Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }
}

String _date(DateTime date) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(date.day)}/${two(date.month)}/${date.year} às ${two(date.hour)}:${two(date.minute)}';
}
