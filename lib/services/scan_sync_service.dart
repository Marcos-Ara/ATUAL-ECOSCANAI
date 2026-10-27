import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/detection_record.dart';
import '../models/material_guide.dart';
import '../state/ecoscan_store.dart';
import 'firebase_account_backup_service.dart';

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

    final payload = await _recordPayload(user.id, record);
    await _client.from('leituras_scan').upsert(
      payload,
      onConflict: 'usuario_id,id_leitura_cliente',
    );
    if (_client.auth.currentUser?.id != user.id) return;
    await FirebaseAccountBackupService.shared.saveScan(
      user.id,
      record,
      supabaseImagePath: payload['caminho_imagem']?.toString(),
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
      final batch = <Map<String, dynamic>>[];
      for (final record in items.sublist(start, end)) {
        batch.add(await _recordPayload(user.id, record));
      }
      if (batch.isEmpty) continue;
      await _client.from('leituras_scan').upsert(
        batch,
        onConflict: 'usuario_id,id_leitura_cliente',
      );
    }
  }

  /// Flushes only scans that have not yet received a successful cloud ACK.
  /// Each scan is acknowledged separately so a network failure leaves the
  /// remaining IDs in the local outbox for the next retry.
  Future<bool> syncPending(EcoScanStore store) async {
    final user = _client.auth.currentUser;
    if (user == null || store.userId != user.id) return false;

    final recordsById = <String, DetectionRecord>{
      for (final record in store.detections)
        if (record.id.isNotEmpty) record.id: record,
    };
    var success = true;
    for (final id in store.pendingScanUploadIds) {
      if (store.userId != user.id || _client.auth.currentUser?.id != user.id) {
        return false;
      }
      final record = recordsById[id];
      if (record == null) {
        // A local deletion owns this ID now; it must not be recreated by an
        // older pending upload marker.
        await store.acknowledgeScanUploads([id], userIdOverride: user.id);
        continue;
      }
      try {
        await upsert(record);
        if (store.userId != user.id ||
            _client.auth.currentUser?.id != user.id) {
          return false;
        }
        await store.acknowledgeScanUploads(
          [id],
          userIdOverride: user.id,
        );
      } catch (_) {
        success = false;
      }
    }
    return success &&
        store.userId == user.id &&
        _client.auth.currentUser?.id == user.id;
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
      await _client.storage.from('ecoscan-account-data').remove(
        ids.sublist(start, end).map((id) => _scanImagePath(user.id, id)).toList(),
      );
    }
    await FirebaseAccountBackupService.shared.deleteScans(user.id, ids);
  }

  /// Restores only the signed-in user's history and creates short-lived private
  /// image URLs for display in the app.
  Future<List<DetectionRecord>> fetchAll() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return const [];

    const pageSize = 500;
    final records = <DetectionRecord>[];
    for (var start = 0; ; start += pageSize) {
      final rows = await _client
          .from('historico_leituras_usuario')
          .select(
            'id_leitura_cliente,nome_objeto,nome_material,categoria,cor_lixeira,'
            'destino,confianca,origem,mecanismo_deteccao,analisado_em,latitude,longitude,objeto_id,'
            'variante_id,rotulo_detectado,indice_classe,confirmado_pelo_usuario,'
            'caminho_imagem',
          )
          .order('analisado_em', ascending: false)
          .order('id_leitura_cliente', ascending: true)
          .range(start, start + pageSize - 1);

      if (_client.auth.currentUser?.id != userId) return const [];
      final signedUrls = await _signedImageUrls(rows, userId);
      if (_client.auth.currentUser?.id != userId) return const [];
      for (final raw in rows) {
        final row = raw;
        final imageStoragePath = row['caminho_imagem']?.toString() ?? '';
        final imageUrl = signedUrls[imageStoragePath] ?? '';
        records.add(
          DetectionRecord(
            id: row['id_leitura_cliente']?.toString() ?? '',
            name: row['nome_material']?.toString() ?? '',
            category: row['categoria']?.toString() ?? '',
            bin: row['cor_lixeira']?.toString() ?? '',
            destination: row['destino']?.toString() ?? '',
            confidence: (row['confianca'] as num?)?.toDouble() ?? 0,
            imagePath: imageUrl,
            detectedAt:
                DateTime.tryParse(row['analisado_em']?.toString() ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0),
            source: row['origem']?.toString() ?? 'camera',
            confirmedByUser: row['confirmado_pelo_usuario'] == true,
            latitude: (row['latitude'] as num?)?.toDouble(),
            longitude: (row['longitude'] as num?)?.toDouble(),
            detectedObject: MaterialGuide.displayNameFor(
              row['categoria']?.toString() ?? '',
            ),
            detector: row['mecanismo_deteccao']?.toString(),
            objectId: row['objeto_id']?.toString(),
            variantId: row['variante_id']?.toString(),
            detectionLabel: null,
            classIndex: (row['indice_classe'] as num?)?.toInt(),
          ),
        );
      }
      if (rows.length < pageSize) break;
    }
    return records;
  }

  Future<Set<String>> fetchUnlockedAchievementIds() async {
    final user = _client.auth.currentUser;
    if (user == null) return const <String>{};
    final rows = await _client
        .from('conquistas_usuario')
        .select('conquista_id,desbloqueada_em')
        .eq('usuario_id', user.id);
    if (_client.auth.currentUser?.id != user.id) return const <String>{};
    return rows
        .where((row) => row['desbloqueada_em'] != null)
        .map((row) => row['conquista_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  Future<Map<String, String>> _signedImageUrls(
    List<Map<String, dynamic>> rows,
    String userId,
  ) async {
    final paths = rows
        .map((row) => row['caminho_imagem']?.toString() ?? '')
        .where((path) => path.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final signedUrls = <String, String>{};
    for (var start = 0; start < paths.length; start += 16) {
      if (_client.auth.currentUser?.id != userId) break;
      final end = (start + 16).clamp(0, paths.length).toInt();
      final batch = paths.sublist(start, end);
      final results = await Future.wait(
        batch.map((path) async {
          if (_client.auth.currentUser?.id != userId) return '';
          try {
            return await _client.storage
                .from('ecoscan-account-data')
                .createSignedUrl(path, 60 * 60 * 24);
          } catch (_) {
            // Keep the history visible if an older scan has no stored image.
            return '';
          }
        }),
      );
      if (_client.auth.currentUser?.id != userId) break;
      for (var index = 0; index < batch.length; index++) {
        signedUrls[batch[index]] = results[index];
      }
    }
    return signedUrls;
  }

  Future<Map<String, dynamic>> _recordPayload(
    String userId,
    DetectionRecord record,
  ) async {
    final imageStoragePath = await _backupScanImage(userId, record);
    return _payload(userId, record, imageStoragePath);
  }

  Future<String?> _backupScanImage(
    String userId,
    DetectionRecord record,
  ) async {
    if (record.imagePath.isEmpty) return null;
    final storagePath = _scanImagePath(userId, record.id);
    if (record.imagePath.startsWith('https://') ||
        record.imagePath.startsWith('http://')) {
      return storagePath;
    }

    final preferences = await SharedPreferences.getInstance();
    final syncedKey = 'ecoscan.image_backup.v1.$userId.${record.id}';
    if (preferences.getBool(syncedKey) == true) return storagePath;

    final bytes = await _imageBytes(record.imagePath);
    if (bytes == null || bytes.isEmpty) return null;
    await _client.storage.from('ecoscan-account-data').uploadBinary(
      storagePath,
      bytes,
      fileOptions: FileOptions(
        contentType: _imageContentType(record.imagePath),
        upsert: true,
      ),
    );
    await preferences.setBool(syncedKey, true);
    return storagePath;
  }

  static String _scanImagePath(String userId, String scanId) {
    final safeId = scanId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return '$userId/leituras/$safeId.jpg';
  }

  static Future<Uint8List?> _imageBytes(String source) async {
    if (source.startsWith('data:image/')) {
      final comma = source.indexOf(',');
      if (comma < 0 || !source.substring(0, comma).contains(';base64')) {
        return null;
      }
      try {
        return base64Decode(source.substring(comma + 1));
      } catch (_) {
        return null;
      }
    }
    if (kIsWeb) return null;
    try {
      final file = File(source);
      return await file.exists() ? await file.readAsBytes() : null;
    } catch (_) {
      return null;
    }
  }

  static String _imageContentType(String source) {
    final lower = source.toLowerCase();
    if (lower.startsWith('data:image/png') || lower.endsWith('.png')) {
      return 'image/png';
    }
    if (lower.startsWith('data:image/webp') || lower.endsWith('.webp')) {
      return 'image/webp';
    }
    return 'image/jpeg';
  }

  static Map<String, dynamic> _payload(
    String userId,
    DetectionRecord record,
    String? imageStoragePath,
  ) => <String, dynamic>{
    'usuario_id': userId,
    'id_leitura_cliente': record.id,
    'nome_objeto': MaterialGuide.displayNameFor(record.category),
    'nome_material': record.name,
    'categoria': record.category,
    'cor_lixeira': record.bin,
    'destino': record.destination,
    'confianca': record.confidence,
    'origem': record.source,
    'mecanismo_deteccao': record.detector,
    'analisado_em': record.detectedAt.toUtc().toIso8601String(),
    'latitude': record.latitude,
    'longitude': record.longitude,
    // A manual material correction may describe a different object than the
    // detector linked. Keep the corrected label, but drop that old relation.
    'objeto_id': record.confirmedByUser
        ? null
        : int.tryParse(record.objectId ?? ''),
    'variante_id': record.confirmedByUser
        ? null
        : int.tryParse(record.variantId ?? ''),
    'rotulo_detectado': null,
    'indice_classe': record.classIndex,
    'confirmado_pelo_usuario': record.confirmedByUser,
    'material_id': _materialId(record.category),
    'caminho_imagem': imageStoragePath,
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
