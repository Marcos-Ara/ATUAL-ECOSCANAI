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
            'supabase/migrations/202610080001_learning_reports.sql e tente '
            'enviar novamente. As amostras continuam salvas neste aparelho.',
          );
        }
        throw StateError(
          'Falha ao enviar a imagem para o bucket ecoscan-training: ${_safeError(error)}',
        );
      }
      try {
        await _client.from('ecoscan_training_samples').upsert(
          {
            'user_id': user.id,
            'client_sample_id': sample.id,
            'storage_path': path,
            'source': sample.source,
            'detector': sample.detector,
            'detections': sample.detections,
            'status': 'pending',
            'verified_label': null,
            'annotations': const <Map<String, dynamic>>[],
            'user_reported_label': sample.reportedLabel,
            'user_reported_bin': sample.reportedBin,
            'report_note': sample.reportNote,
            'ai_detected': sample.aiDetected,
            'original_label': sample.originalLabel,
            'original_confidence': sample.originalConfidence,
            'consented_at': DateTime.now().toUtc().toIso8601String(),
          },
          onConflict: 'user_id,client_sample_id',
        );
      } catch (error) {
        throw StateError(
          'A imagem chegou ao bucket, mas o banco recusou o registro. '
          'Confira a migração SQL learning_reports: ${_safeError(error)}',
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
