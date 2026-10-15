import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/detection_record.dart';
import '../state/ecoscan_store.dart';

/// Registra no Supabase as análises que o usuário salvou no histórico.
///
/// O app usa apenas a chave pública. A tabela `leituras_scan` aplica RLS e aceita
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

    await _client.from('leituras_scan').upsert(
      _payload(user.id, record),
      onConflict: 'usuario_id,id_leitura_cliente',
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
      await _client.from('leituras_scan').upsert(
        batch,
        onConflict: 'usuario_id,id_leitura_cliente',
      );
    }
  }

  Future<Set<String>> fetchDeletedIds() async {
    if (_client.auth.currentUser == null) return const {};

    const pageSize = 500;
    final ids = <String>{};
    for (var start = 0; ; start += pageSize) {
      final rows = await _client
          .from('exclusoes_leitura')
          .select('id_leitura_cliente')
          .order('id_leitura_cliente', ascending: true)
          .range(start, start + pageSize - 1);
      for (final raw in rows) {
        if (raw['id_leitura_cliente'] != null) {
          ids.add(raw['id_leitura_cliente'].toString());
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
      }).map((row) => {
        'usuario_id': row['user_id'],
        'id_leitura_cliente': row['client_scan_id'],
        'excluido_em': row['deleted_at'],
      }).toList(growable: false);
      await _client.from('exclusoes_leitura').upsert(
        batch,
        onConflict: 'usuario_id,id_leitura_cliente',
      );
      await _client
          .from('leituras_scan')
          .delete()
          .eq('usuario_id', user.id)
          .inFilter('id_leitura_cliente', ids.sublist(start, end));
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
          .from('historico_leituras_usuario')
          .select(
            'id_leitura_cliente,nome_objeto,nome_material,categoria,cor_lixeira,'
            'destino,confianca,origem,mecanismo_deteccao,analisado_em,objeto_id,'
            'variante_id,rotulo_detectado,indice_classe,confirmado_pelo_usuario',
          )
          .order('analisado_em', ascending: false)
          .order('id_leitura_cliente', ascending: true)
          .range(start, start + pageSize - 1);

      for (final raw in rows) {
        final row = raw;
        records.add(
          DetectionRecord(
            id: row['id_leitura_cliente']?.toString() ?? '',
            name: row['nome_material']?.toString() ?? '',
            category: row['categoria']?.toString() ?? '',
            bin: row['cor_lixeira']?.toString() ?? '',
            destination: row['destino']?.toString() ?? '',
            confidence: (row['confianca'] as num?)?.toDouble() ?? 0,
            imagePath: '',
            detectedAt:
                DateTime.tryParse(row['analisado_em']?.toString() ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0),
            source: row['origem']?.toString() ?? 'camera',
            confirmedByUser: row['confirmado_pelo_usuario'] == true,
            detectedObject: row['nome_objeto']?.toString(),
            detector: row['mecanismo_deteccao']?.toString(),
            objectId: row['objeto_id']?.toString(),
            variantId: row['variante_id']?.toString(),
            detectionLabel: row['rotulo_detectado']?.toString(),
            classIndex: (row['indice_classe'] as num?)?.toInt(),
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
    'usuario_id': userId,
    'id_leitura_cliente': record.id,
    'nome_objeto': record.detectedObject,
    'nome_material': record.name,
    'categoria': record.category,
    'cor_lixeira': record.bin,
    'destino': record.destination,
    'confianca': record.confidence,
    'origem': record.source,
    'mecanismo_deteccao': record.detector,
    'analisado_em': record.detectedAt.toUtc().toIso8601String(),
    // Scan location is device-local; it is not part of account history sync.
    'latitude': null,
    'longitude': null,
    // A manual material correction may describe a different object than the
    // detector linked. Keep the corrected label, but drop that old relation.
    'objeto_id': record.confirmedByUser
        ? null
        : int.tryParse(record.objectId ?? ''),
    'variante_id': record.confirmedByUser
        ? null
        : int.tryParse(record.variantId ?? ''),
    'rotulo_detectado': record.detectionLabel,
    'indice_classe': record.classIndex,
    'confirmado_pelo_usuario': record.confirmedByUser,
    'material_id': _materialId(record.category),
  };

  static String? _materialId(String category) => switch (category.trim()) {
    'Plástico' => 'plastico',
    'Papel' => 'papel',
    'Papelão' => 'papelao',
    'Vidro' => 'vidro',
    'Metal' => 'metal',
    'Orgânico' => 'organico',
    'Rejeito' => 'rejeito',
    'Eletrônico' => 'eletronico',
    'Descarte especial' => 'especial',
    _ => null,
  };
}
