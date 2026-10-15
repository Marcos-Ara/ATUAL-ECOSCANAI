import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/detection_record.dart';
import '../state/ecoscan_store.dart';

/// Registra no Supabase as análises que o usuário salvou no histórico.
///
/// O app usa apenas a chave pública. A tabela `fato_scan` aplica RLS e aceita
/// somente registros do próprio usuário autenticado.
class ScanSyncService {
  ScanSyncService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<void> reconcileDeletions(EcoScanStore store) async {
    final user = _client.auth.currentUser;
    if (user == null || store.userId != user.id) return;

    final cloudDeletedIds = await fetchDeletedIds();
    if (store.userId != user.id) return;
    await store.applyCloudScanDeletions(cloudDeletedIds);
    if (store.userId != user.id) return;

    final pendingIds = {
      ...cloudDeletedIds,
      ...store.pendingScanDeletionIds,
    }.toList(growable: false);
    if (pendingIds.isEmpty) return;
    await syncDeletedIds(pendingIds);
    if (store.userId != user.id) return;
    await store.acknowledgeScanDeletions(pendingIds);
  }

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

    final deletedIds = await fetchDeletedIds();
    final items = records
        .where((record) => !deletedIds.contains(record.id))
        .toList(growable: false);
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

  Future<Set<String>> fetchDeletedIds() async {
    if (_client.auth.currentUser == null) return const {};

    const pageSize = 500;
    final ids = <String>{};
    for (var start = 0; ; start += pageSize) {
      final rows = await _client
          .from('fato_scan_deletions')
          .select('client_scan_id')
          .order('client_scan_id', ascending: true)
          .range(start, start + pageSize - 1);
      for (final raw in rows) {
        if (raw is Map && raw['client_scan_id'] != null) {
          ids.add(raw['client_scan_id'].toString());
        }
      }
      if (rows.length < pageSize) break;
    }
    return ids;
  }

  Future<void> syncDeletedIds(Iterable<String> clientScanIds) async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    final ids = clientScanIds.where((id) => id.isNotEmpty).toSet().toList();
    for (var start = 0; start < ids.length; start += 50) {
      final end = (start + 50).clamp(0, ids.length).toInt();
      final batch = ids.sublist(start, end).map((id) => {
        'user_id': user.id,
        'client_scan_id': id,
        'deleted_at': DateTime.now().toUtc().toIso8601String(),
      }).toList(growable: false);
      await _client.from('fato_scan_deletions').upsert(
        batch,
        onConflict: 'user_id,client_scan_id',
      );
      await _client
          .from('fato_scan')
          .delete()
          .eq('user_id', user.id)
          .inFilter('client_scan_id', ids.sublist(start, end));
    }
  }

  /// Restores the signed-in user's cloud history without exposing another
  /// account's rows. Images stay on the device and are never downloaded here.
  Future<List<DetectionRecord>> fetchAll() async {
    if (_client.auth.currentUser == null) return const [];

    const pageSize = 500;
    final records = <DetectionRecord>[];
    for (var start = 0; ; start += pageSize) {
      final rows = await _client
          .from('ecoscan_user_history')
          .select(
            'client_scan_id,object_name,material_name,category_name,bin_name,'
            'destination,confidence,source,detector,detected_at,object_id,'
            'variant_id,detection_label,class_index,confirmed_by_user',
          )
          .order('detected_at', ascending: false)
          .order('client_scan_id', ascending: true)
          .range(start, start + pageSize - 1);

      for (final raw in rows) {
        if (raw is! Map) continue;
        final row = Map<String, dynamic>.from(raw);
        records.add(
          DetectionRecord(
            id: row['client_scan_id']?.toString() ?? '',
            name: row['material_name']?.toString() ?? '',
            category: row['category_name']?.toString() ?? '',
            bin: row['bin_name']?.toString() ?? '',
            destination: row['destination']?.toString() ?? '',
            confidence: (row['confidence'] as num?)?.toDouble() ?? 0,
            imagePath: '',
            detectedAt:
                DateTime.tryParse(row['detected_at']?.toString() ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0),
            source: row['source']?.toString() ?? 'camera',
            confirmedByUser: row['confirmed_by_user'] == true,
            detectedObject: row['object_name']?.toString(),
            detector: row['detector']?.toString(),
            objectId: row['object_id']?.toString(),
            variantId: row['variant_id']?.toString(),
            detectionLabel: row['detection_label']?.toString(),
            classIndex: (row['class_index'] as num?)?.toInt(),
          ),
        );
      }
      if (rows.length < pageSize) break;
    }
    return records;
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
    // Scan location is device-local; it is not part of account history sync.
    'latitude': null,
    'longitude': null,
    // A manual material correction may describe a different object than the
    // detector linked. Keep the corrected label, but drop that old relation.
    'object_id': record.confirmedByUser
        ? null
        : int.tryParse(record.objectId ?? ''),
    'variant_id': record.confirmedByUser
        ? null
        : int.tryParse(record.variantId ?? ''),
    'detection_label': record.detectionLabel,
    'class_index': record.classIndex,
    'confirmed_by_user': record.confirmedByUser,
  };
}
