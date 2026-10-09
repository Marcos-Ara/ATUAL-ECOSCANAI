import 'dart:typed_data';

import 'package:flutter/material.dart';

class CorrectionReport {
  const CorrectionReport({
    required this.label,
    required this.bin,
    required this.note,
    required this.aiDetected,
  });

  final String label;
  final String bin;
  final String note;
  final bool aiDetected;
}

class CorrectionReportDialog extends StatefulWidget {
  const CorrectionReportDialog({
    required this.imageBytes,
    required this.originalLabel,
    required this.originalConfidence,
    required this.aiDetected,
    super.key,
  });

  final Uint8List imageBytes;
  final String? originalLabel;
  final double? originalConfidence;
  final bool aiDetected;

  @override
  State<CorrectionReportDialog> createState() => _CorrectionReportDialogState();
}

class _CorrectionReportDialogState extends State<CorrectionReportDialog> {
  static const _bins = <String>[
    'Azul — Papel',
    'Vermelha — Plástico',
    'Verde — Vidro',
    'Amarela — Metal',
    'Marrom — Orgânico',
    'Cinza — Rejeito',
    'Coleta especial',
    'Outro',
  ];

  final _labelController = TextEditingController();
  final _noteController = TextEditingController();
  String _bin = _bins.first;
  late bool _aiDetected = widget.aiDetected;
  bool _review = false;

  @override
  void initState() {
    super.initState();
    _labelController.text = widget.originalLabel ?? '';
  }

  @override
  void dispose() {
    _labelController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final original = widget.originalLabel?.trim();
    final hasOriginal = original?.isNotEmpty == true;
    final confidence = widget.originalConfidence;
    return AlertDialog(
      title: Text(_review ? 'Revise sua correção' : 'Corrigir identificação'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.memory(
                  widget.imageBytes,
                  height: 170,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => const SizedBox(
                    height: 120,
                    child: Center(child: Icon(Icons.broken_image_outlined)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                hasOriginal
                    ? 'Sugestão original da IA: $original${confidence == null ? '' : ' · ${(confidence * 100).round()}%'}'
                    : 'A IA não encontrou um objeto com confiança suficiente.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              if (!_review) ...[
                TextField(
                  controller: _labelController,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Qual é o objeto correto?',
                    hintText: 'Ex.: garrafa de vidro',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _bin,
                  decoration: const InputDecoration(
                    labelText: 'Material / destino correto',
                    border: OutlineInputBorder(),
                  ),
                  items: _bins
                      .map((bin) => DropdownMenuItem(value: bin, child: Text(bin)))
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value != null) setState(() => _bin = value);
                  },
                ),
                const SizedBox(height: 6),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('A IA encontrou algum objeto?'),
                  value: _aiDetected,
                  onChanged: (value) => setState(() => _aiDetected = value),
                ),
                TextField(
                  controller: _noteController,
                  textCapitalization: TextCapitalization.sentences,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: _bin == 'Outro' ? 'Explique o material' : 'Observação (opcional)',
                    border: const OutlineInputBorder(),
                  ),
                ),
              ] else ...[
                _ReviewLine(label: 'Objeto correto', value: _labelController.text.trim()),
                _ReviewLine(label: 'Material / destino', value: _bin),
                _ReviewLine(label: 'IA encontrou objeto', value: _aiDetected ? 'Sim' : 'Não'),
                if (_noteController.text.trim().isNotEmpty)
                  _ReviewLine(label: 'Observação', value: _noteController.text.trim()),
                const SizedBox(height: 6),
                const Text(
                  'Ao confirmar, a correção ficará salva neste aparelho. Ela só será enviada se você aceitar o envio em Configurações.',
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            if (_review) {
              setState(() => _review = false);
            } else {
              Navigator.pop(context);
            }
          },
          child: Text(_review ? 'Voltar' : 'Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _review ? _confirm : _reviewCorrection,
          icon: Icon(_review ? Icons.check_circle_outline : Icons.fact_check_outlined),
          label: Text(_review ? 'Confirmar correção' : 'Revisar correção'),
        ),
      ],
    );
  }

  void _reviewCorrection() {
    final label = _labelController.text.trim();
    if (label.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe qual é o objeto correto.')),
      );
      return;
    }
    if (_bin == 'Outro' && _noteController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Explique o material escolhido em “Outro”.')),
      );
      return;
    }
    setState(() => _review = true);
  }

  void _confirm() => Navigator.pop(
    context,
    CorrectionReport(
      label: _labelController.text.trim(),
      bin: _bin,
      note: _noteController.text.trim(),
      aiDetected: _aiDetected,
    ),
  );
}

class _ReviewLine extends StatelessWidget {
  const _ReviewLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 142, child: Text(label)),
        Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w700))),
      ],
    ),
  );
}
