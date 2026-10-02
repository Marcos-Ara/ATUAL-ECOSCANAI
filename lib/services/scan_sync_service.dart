import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/detection_record.dart';

/// Registra no Supabase as análises que o usuário salvou no histórico.
///
/// O app usa apenas a chave pública. A tabela `fato_scan` aplica RLS e aceita
/// somente registros do próprio usuário autenticado.
class ScanSyncService {
  ScanSyncService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<void> upsert(DetectionRecord record) async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    await _client.from('fato_scan').upsert(
      _payload(user.id, record),
      onConflict: 'user_id,client_scan_id',
    );
  }

  Future<void> syncAll(Iterable<DetectionRecord> records) async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    final items = records.toList(growable: false);
    for (var start = 0; start < items.length; start += 50) {
      final end = (start + 50).clamp(0, items.length).toInt();
      final batch = items
          .sublist(start, end)
          .map((record) => _payload(user.id, record))
          .toList(growable: false);
      if (batch.isEmpty) continue;
      await _client.from('fato_scan').upsert(
        batch,
        onConflict: 'user_id,client_scan_id',
      );
    }
  }

  static Map<String, dynamic> _payload(
    String userId,
    DetectionRecord record,
  ) => <String, dynamic>{
    'user_id': userId,
    'client_scan_id': record.id,
    'object_name': record.detectedObject,
    'material_name': record.name,
    'category_name': record.category,
    'bin_name': record.bin,
    'destination': record.destination,
    'confidence': record.confidence,
    'source': record.source,
    'detector': record.detector,
    'detected_at': record.detectedAt.toUtc().toIso8601String(),
    'latitude': record.latitude,
    'longitude': record.longitude,
  };
}
