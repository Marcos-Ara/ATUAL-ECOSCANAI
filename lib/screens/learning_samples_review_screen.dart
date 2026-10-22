import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/learning_sample.dart';
import '../models/material_guide.dart';
import '../services/correction_backup_sync_service.dart';
import '../services/learning_sync_service.dart';
import '../state/ecoscan_store.dart';

class LearningSamplesReviewScreen extends StatefulWidget {
  const LearningSamplesReviewScreen({super.key});

  @override
  State<LearningSamplesReviewScreen> createState() =>
      _LearningSamplesReviewScreenState();
}

class _LearningSamplesReviewScreenState
    extends State<LearningSamplesReviewScreen> {
  final Set<String> _selected = <String>{};
  final Map<String, _SampleDraft> _drafts = <String, _SampleDraft>{};
  bool _initialized = false;
  bool _consent = false;
  bool _sending = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    for (final sample in context.read<EcoScanStore>().learningSamples) {
      _drafts[sample.id] = _SampleDraft(
        sample,
        initialLabel: _categoryForSample(sample),
      );
    }
  }

  @override
  void dispose() {
    for (final draft in _drafts.values) {
      draft.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<EcoScanStore>();
    final samples = store.learningSamples;
    final selectedCount = _selected.where(
      (id) => samples.any((sample) => sample.id == id),
    ).length;
    return Scaffold(
      appBar: AppBar(title: const Text('Revisar amostras')),
      body: SafeArea(
        child: samples.isEmpty
            ? _emptyState(context)
            : Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                      children: [
                        _intro(context, samples.length, selectedCount),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: () => setState(() {
                              if (selectedCount == samples.length) {
                                _selected.clear();
                              } else {
                                _selected
                                  ..clear()
                                  ..addAll(samples.map((sample) => sample.id));
                              }
                            }),
                            icon: Icon(
                              selectedCount == samples.length
                                  ? Icons.deselect_rounded
                                  : Icons.select_all_rounded,
                            ),
                            label: Text(
                              selectedCount == samples.length
                                  ? 'Desmarcar todas'
                                  : 'Selecionar todas',
                            ),
                          ),
                        ),
                        for (final sample in samples)
                          _sampleCard(context, sample),
                        const SizedBox(height: 8),
                        Card(
                          child: CheckboxListTile(
                            value: _consent,
                            onChanged: _sending
                                ? null
                                : (value) => setState(
                                    () => _consent = value ?? false,
                                  ),
                            controlAffinity: ListTileControlAffinity.leading,
                            title: const Text('Confirmo o envio com consentimento'),
                            subtitle: const Text(
                              'As fotos e informações das amostras marcadas serão enviadas ao EcoScan para revisão. O envio não treina o YOLO automaticamente.',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: selectedCount == 0 || _sending
                                ? null
                                : () => _deleteSelected(samples),
                            icon: const Icon(Icons.delete_outline),
                            label: Text(
                              'Excluir $selectedCount ${selectedCount == 1 ? 'leitura' : 'leituras'} selecionadas',
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: selectedCount == 0 || !_consent || _sending
                                ? null
                                : () => _send(context, samples),
                            icon: _sending
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.cloud_upload_outlined),
                            label: Text(
                              _sending
                                  ? 'Enviando para revisão…'
                                  : 'Enviar $selectedCount ${selectedCount == 1 ? 'amostra' : 'amostras'}',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _intro(BuildContext context, int total, int selected) => Card(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Confira antes de enviar',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          Text(
            '$total ${total == 1 ? 'correção salva' : 'correções salvas'} · $selected selecionada${selected == 1 ? '' : 's'}',
          ),
          const SizedBox(height: 6),
          const Text(
            'Veja a foto, confirme a categoria e marque somente o que deseja compartilhar. Cada envio fica pendente de revisão.',
          ),
        ],
      ),
    ),
  );

  Widget _sampleCard(BuildContext context, LearningSample sample) {
    final draft = _drafts.putIfAbsent(
      sample.id,
      () => _SampleDraft(sample, initialLabel: _categoryForSample(sample)),
    );
    final selected = _selected.contains(sample.id);
    final theme = Theme.of(context);
    final category = _categoryForSample(sample);
    final details = <String>[
      _sourceName(sample.source),
      _date(sample.createdAt),
      if (sample.originalConfidence != null)
        '${(sample.originalConfidence! * 100).round()}% de confiança',
      if (sample.aiDetected != null)
        sample.aiDetected == true
            ? 'IA sugeriu uma categoria'
            : 'IA sem categoria segura',
    ].join(' · ');
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CheckboxListTile(
            value: selected,
            onChanged: _sending
                ? null
                : (value) => setState(() {
                    if (value == true) {
                      _selected.add(sample.id);
                    } else {
                      _selected.remove(sample.id);
                    }
                  }),
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(
              category.isNotEmpty
                  ? 'Leitura: $category'
                  : 'Leitura sem identificação segura',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(details),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: AspectRatio(
                aspectRatio: 1.25,
                child: _sampleImage(sample.thumbnailDataUrl),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: _detectionSuggestions(context, sample),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
            child: Text(
              'Informações que serão enviadas',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
            child: Column(
              children: [
                TextField(
                  controller: draft.label,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Categoria correta',
                    prefixIcon: Icon(Icons.label_outline),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: draft.bin,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Material ou destino correto',
                    prefixIcon: Icon(Icons.recycling_outlined),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: draft.note,
                  textCapitalization: TextCapitalization.sentences,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Observação (opcional)',
                    prefixIcon: Icon(Icons.notes_rounded),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                if (draft.isDirty)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _sending
                          ? null
                          : () => _saveDraft(context, sample, draft),
                      icon: const Icon(Icons.save_outlined),
                        label: const Text('Salvar correção'),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _detectionSuggestions(BuildContext context, LearningSample sample) {
    final category = _categoryForSample(sample);
    if (category.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Categoria sugerida pela IA',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [Chip(label: Text(category))],
        ),
      ],
    );
  }

  String _categoryForSample(LearningSample sample) {
    final reported = MaterialGuide.byName(sample.reportedLabel ?? '');
    if (reported != null) return reported.displayName;
    final original = MaterialGuide.byName(sample.originalLabel ?? '');
    if (original != null) return original.displayName;
    final reportedDestination = MaterialGuide.fromDatabase({
      'categoria': sample.reportedBin,
      'nome_material': sample.reportedBin,
    });
    return reportedDestination?.displayName ?? '';
  }

  Widget _sampleImage(String dataUrl) {
    try {
      final comma = dataUrl.indexOf(',');
      final bytes = base64Decode(comma < 0 ? dataUrl : dataUrl.substring(comma + 1));
      return Image.memory(
        bytes,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => const _ImagePlaceholder(),
      );
    } catch (_) {
      return const _ImagePlaceholder();
    }
  }

  Widget _emptyState(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.photo_library_outlined,
            size: 54,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 12),
          Text('Nenhuma amostra salva', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          const Text(
            'Quando você corrigir uma identificação, a amostra aparecerá aqui para revisão e envio.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );

  Future<void> _saveDraft(
    BuildContext context,
    LearningSample original,
    _SampleDraft draft,
  ) async {
    if (draft.label.text.trim().isEmpty) {
      _message('Informe a categoria correta antes de salvar.');
      return;
    }
    try {
      final updated = _applyDraft(original, draft);
      await context.read<EcoScanStore>().updateLearningSample(updated);
      draft.markSaved();
      var cloudSaved = false;
      try {
        cloudSaved = await CorrectionBackupSyncService().saveSample(updated);
      } catch (_) {
        // A edição fica no aparelho e será enviada no próximo retorno à rede.
      }
      if (mounted) {
        setState(() {});
        _message(
          cloudSaved
              ? 'Correção atualizada na sua conta.'
              : 'Edição salva neste aparelho; será sincronizada quando houver conexão.',
        );
      }
    } catch (error) {
      if (mounted) _message('Não foi possível salvar a edição: $error');
    }
  }

  Future<void> _deleteSelected(List<LearningSample> samples) async {
    final chosen = samples
        .where((sample) => _selected.contains(sample.id))
        .toList(growable: false);
    if (chosen.isEmpty || _sending) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir leituras selecionadas?'),
        content: Text(
          '${chosen.length} ${chosen.length == 1 ? 'amostra será removida' : 'amostras serão removidas'} deste aparelho. Elas não serão enviadas ao Supabase.',
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
    setState(() => _sending = true);
    try {
      await context.read<EcoScanStore>().removeLearningSamples(
        chosen.map((sample) => sample.id),
      );
      if (!mounted) return;
      for (final sample in chosen) {
        _selected.remove(sample.id);
        _drafts.remove(sample.id)?.dispose();
      }
      setState(() => _consent = false);
      _message(
        '${chosen.length} ${chosen.length == 1 ? 'leitura excluída' : 'leituras excluídas'} deste aparelho.',
      );
    } catch (error) {
      if (mounted) {
        _message('Não foi possível excluir as leituras: $error');
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _send(
    BuildContext context,
    List<LearningSample> samples,
  ) async {
    final chosen = samples
        .where((sample) => _selected.contains(sample.id))
        .toList(growable: false);
    if (chosen.isEmpty || !_consent || _sending) return;
    for (final sample in chosen) {
      if ((_drafts[sample.id]?.label.text.trim() ?? '').isEmpty) {
        _message('Preencha o nome correto de cada amostra selecionada.');
        return;
      }
    }
    setState(() => _sending = true);
    try {
      final store = context.read<EcoScanStore>();
      final updated = <LearningSample>[];
      for (final sample in chosen) {
        final draft = _drafts[sample.id]!;
        final value = _applyDraft(sample, draft);
        if (draft.isDirty) await store.updateLearningSample(value);
        draft.markSaved();
        updated.add(value);
      }
      final uploaded = await LearningSyncService().uploadWithConsent(updated);
      await store.removeLearningSamples(uploaded);
      for (final id in uploaded) {
        _drafts.remove(id)?.dispose();
      }
      if (!mounted || !context.mounted) return;
      if (uploaded.isEmpty) {
        _message('Nenhuma foto válida foi enviada. As amostras continuam salvas.');
      } else {
        final message =
            '${uploaded.length} ${uploaded.length == 1 ? 'amostra enviada' : 'amostras enviadas'} para revisão no Supabase.';
        if (store.learningSampleCount == 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message)),
          );
          Navigator.of(context).pop();
        } else {
          setState(() {
            _selected.removeAll(uploaded);
            _consent = false;
          });
          _message(message);
        }
      }
    } catch (error) {
      if (mounted) {
        final detail = error.toString().replaceFirst('Bad state: ', '').trim();
        _message(
          detail.isEmpty
              ? 'Falha no envio. As amostras continuam salvas neste aparelho.'
              : 'Falha no envio; as amostras continuam salvas. $detail',
          duration: const Duration(seconds: 8),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  LearningSample _applyDraft(LearningSample sample, _SampleDraft draft) =>
      sample.copyWith(
        reportedLabel: draft.label.text.trim(),
        reportedBin: draft.bin.text.trim(),
        reportNote: draft.note.text.trim(),
        clearReportedLabel: draft.label.text.trim().isEmpty,
        clearReportedBin: draft.bin.text.trim().isEmpty,
        clearReportNote: draft.note.text.trim().isEmpty,
      );

  void _message(String message, {Duration duration = const Duration(seconds: 4)}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), duration: duration));
  }

  static String _sourceName(String source) => switch (source) {
    'gallery' => 'Galeria',
    'camera' => 'Câmera',
    _ => 'Origem desconhecida',
  };

  static String _date(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
}

class _SampleDraft {
  _SampleDraft(LearningSample sample, {required String initialLabel})
    : label = TextEditingController(
        text: MaterialGuide.byName(sample.reportedLabel ?? '')?.displayName ??
            initialLabel,
      ),
      bin = TextEditingController(text: sample.reportedBin ?? ''),
      note = TextEditingController(text: sample.reportNote ?? ''),
      _savedLabel = MaterialGuide.byName(
            sample.reportedLabel ?? '',
          )?.displayName ??
          initialLabel.trim(),
      _savedBin = (sample.reportedBin ?? '').trim(),
      _savedNote = (sample.reportNote ?? '').trim();

  final TextEditingController label;
  final TextEditingController bin;
  final TextEditingController note;
  String _savedLabel;
  String _savedBin;
  String _savedNote;

  bool get isDirty =>
      label.text.trim() != _savedLabel ||
      bin.text.trim() != _savedBin ||
      note.text.trim() != _savedNote;

  void markSaved() {
    _savedLabel = label.text.trim();
    _savedBin = bin.text.trim();
    _savedNote = note.text.trim();
  }

  void dispose() {
    label.dispose();
    bin.dispose();
    note.dispose();
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder();

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: const Center(child: Icon(Icons.broken_image_outlined, size: 40)),
  );
}
