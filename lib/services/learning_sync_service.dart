import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/learning_sample.dart';

class LearningSyncService {
  LearningSyncService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<List<String>> uploadWithConsent(
    Iterable<LearningSample> samples,
  ) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw StateError('Entre em uma conta para enviar amostras.');
    }
    final uploaded = <String>[];
    for (final sample in samples) {
      final bytes = _decodeDataUrl(sample.thumbnailDataUrl);
      if (bytes == null || bytes.isEmpty) continue;
      final path = '${user.id}/${sample.id}.jpg';
      try {
        await _client.storage.from('ecoscan-training').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: true,
          ),
        );
      } catch (error) {
        if (_isMissingBucket(error)) {
          throw StateError(
            'O bucket privado ecoscan-training não existe no projeto Supabase '
            'conectado ao app. No SQL Editor desse mesmo projeto, execute '
            'supabase/ECOSCAN_SUPABASE_NOVO.sql e tente '
            'enviar novamente. As amostras continuam salvas neste aparelho.',
          );
        }
        throw StateError(
          'Falha ao enviar a imagem para o bucket ecoscan-training: ${_safeError(error)}',
        );
      }
      try {
        await _client.from('amostras_treinamento').upsert(
          {
            'usuario_id': user.id,
            'id_amostra_cliente': sample.id,
            'caminho_arquivo': path,
            'origem': sample.source,
            'mecanismo_deteccao': sample.detector,
            'deteccoes': sample.detections,
            'situacao': 'pendente',
            'rotulo_confirmado': null,
            'anotacoes': const <Map<String, dynamic>>[],
            'rotulo_informado_usuario': sample.reportedLabel,
            'lixeira_informada_usuario': sample.reportedBin,
            'observacao': sample.reportNote,
            'detectado_por_ia': sample.aiDetected,
            'rotulo_original': sample.originalLabel,
            'confianca_original': sample.originalConfidence,
            'consentido_em': DateTime.now().toUtc().toIso8601String(),
          },
          onConflict: 'usuario_id,id_amostra_cliente',
        );
      } catch (error) {
        throw StateError(
          'A imagem chegou ao bucket, mas o banco recusou o registro. '
          'Confira se a instalação do banco em português terminou: ${_safeError(error)}',
        );
      }
      uploaded.add(sample.id);
    }
    return List.unmodifiable(uploaded);
  }

  static String _safeError(Object error) {
    final text = error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    return text.length > 240 ? '${text.substring(0, 240)}…' : text;
  }

  static bool _isMissingBucket(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('bucket not found') ||
        (message.contains('404') && message.contains('bucket'));
  }

  static Uint8List? _decodeDataUrl(String value) {
    final separator = value.indexOf(',');
    if (!value.startsWith('data:image/jpeg;base64,') || separator < 0) {
      return null;
    }
    try {
      return base64Decode(value.substring(separator + 1));
    } catch (_) {
      return null;
    }
  }
}
