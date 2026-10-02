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
      await _client.storage.from('ecoscan-training').uploadBinary(
        path,
        bytes,
        fileOptions: const FileOptions(
          contentType: 'image/jpeg',
          upsert: true,
        ),
      );
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
          'consented_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'user_id,client_sample_id',
      );
      uploaded.add(sample.id);
    }
    return List.unmodifiable(uploaded);
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
