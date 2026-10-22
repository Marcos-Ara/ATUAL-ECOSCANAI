import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_config.dart';
import '../models/detection_record.dart';
import '../models/material_guide.dart';
import '../services/scan_sync_service.dart';
import '../state/ecoscan_store.dart';
import '../widgets/app_image.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final Set<String> _selectedIds = <String>{};
  bool _selecting = false;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<EcoScanStore>();
    final records = store.detections;
    final selectedCount = records
        .where((record) => _selectedIds.contains(record.id))
        .length;
    final allSelected = records.isNotEmpty && selectedCount == records.length;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _selecting
              ? '$selectedCount ${selectedCount == 1 ? 'selecionada' : 'selecionadas'}'
              : 'Histórico',
        ),
        actions: [
          if (_selecting) ...[
            IconButton(
              tooltip: allSelected ? 'Desmarcar todas' : 'Selecionar todas',
              onPressed: () => setState(() {
                if (allSelected) {
                  _selectedIds.clear();
                } else {
                  _selectedIds
                    ..clear()
                    ..addAll(records.map((record) => record.id));
                }
              }),
              icon: Icon(
                allSelected ? Icons.deselect_rounded : Icons.select_all_rounded,
              ),
            ),
            IconButton(
              tooltip: 'Cancelar seleção',
              onPressed: () => setState(() {
                _selecting = false;
                _selectedIds.clear();
              }),
              icon: const Icon(Icons.close_rounded),
            ),
          ] else if (records.isNotEmpty) ...[
            IconButton(
              tooltip: 'Selecionar leituras',
              onPressed: () => setState(() => _selecting = true),
              icon: const Icon(Icons.checklist_rounded),
            ),
            IconButton(
              tooltip: 'Limpar histórico',
              onPressed: () => _clear(context, store),
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
          ],
        ],
      ),
      bottomNavigationBar: _selecting && selectedCount > 0
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: FilledButton.icon(
                  onPressed: () => _deleteSelected(store, records),
                  icon: const Icon(Icons.delete_outline),
                  label: Text(
                    'Excluir $selectedCount ${selectedCount == 1 ? 'leitura' : 'leituras'}',
                  ),
                ),
              ),
            )
          : null,
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
                final selected = _selectedIds.contains(record.id);
                return Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(12),
                    onTap: () {
                      if (_selecting) {
                        _toggle(record);
                      } else {
                        Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => DetectionDetailScreen(record: record),
                          ),
                        );
                      }
                    },
                    onLongPress: () {
                      if (!_selecting) {
                        setState(() {
                          _selecting = true;
                          _selectedIds.add(record.id);
                        });
                      }
                    },
                    leading: _selecting
                        ? Checkbox(
                            value: selected,
                            onChanged: (_) => _toggle(record),
                          )
                        : ClipRRect(
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
                      MaterialGuide.byName(record.category)?.displayName ??
                          record.category,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      '${record.bin}\n${_date(record.detectedAt)}',
                    ),
                    isThreeLine: true,
                    trailing: _selecting
                        ? null
                        : IconButton(
                            tooltip: 'Excluir análise',
                            onPressed: () => _deleteOne(context, store, record),
                            icon: const Icon(Icons.delete_outline),
                          ),
                  ),
                );
              },
            ),
    );
  }

  void _toggle(DetectionRecord record) {
    if (record.id.isEmpty) return;
    setState(() {
      if (!_selectedIds.add(record.id)) _selectedIds.remove(record.id);
    });
  }

  Future<void> _deleteSelected(
    EcoScanStore store,
    List<DetectionRecord> records,
  ) async {
    final chosen = records
        .where((record) => _selectedIds.contains(record.id))
        .toList(growable: false);
    if (chosen.isEmpty) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir leituras selecionadas?'),
        content: Text(
          '${chosen.length} ${chosen.length == 1 ? 'leitura será removida' : 'leituras serão removidas'} deste aparelho. A exclusão também será sincronizada com sua conta quando houver conexão.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    try {
      await store.removeDetections(chosen);
      _syncPendingDeletions(store);
      if (!mounted) return;
      setState(() {
        _selectedIds.clear();
        _selecting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${chosen.length} ${chosen.length == 1 ? 'leitura excluída' : 'leituras excluídas'}.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível excluir as leituras: $error')),
      );
    }
  }

  static Future<void> _deleteOne(
    BuildContext context,
    EcoScanStore store,
    DetectionRecord record,
  ) async {
    try {
      await store.removeDetection(record);
      _syncPendingDeletions(store);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível excluir a leitura: $error')),
      );
    }
  }

  static Future<void> _clear(BuildContext context, EcoScanStore store) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Limpar histórico?'),
        content: const Text(
          'As análises serão removidas deste aparelho e, quando houver conexão, da conta e dos outros aparelhos. As fotos locais também serão apagadas.',
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
    if (approved == true) {
      await store.clearHistory();
      _syncPendingDeletions(store);
    }
  }

  static void _syncPendingDeletions(EcoScanStore store) {
    if (!AppConfig.syncSupabaseHistory) return;
    unawaited(ScanSyncService().reconcileDeletions(store).catchError((_) {}));
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
            material?.displayName ?? record.category,
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
              final store = context.read<EcoScanStore>();
              await store.removeDetection(record);
              _HistoryScreenState._syncPendingDeletions(store);
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
