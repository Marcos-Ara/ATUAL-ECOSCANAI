import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/learning_sample.dart';
import '../state/ecoscan_store.dart';
import 'firebase_account_backup_service.dart';

/// Keeps user corrections and their photos private in the account backup.
/// Training samples are still uploaded to ecoscan-training only after consent.
class CorrectionBackupSyncService {
  CorrectionBackupSyncService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<bool> saveSample(LearningSample sample) async {
    final user = _client.auth.currentUser;
    if (user == null) return false;

    final bytes = _decodeDataUrl(sample.thumbnailDataUrl);
    final safeId = sample.id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    if (safeId.isEmpty) {
      throw StateError('A correção não tem um identificador válido.');
    }
    String? path;
    if (bytes != null && bytes.isNotEmpty) {
      path = '${user.id}/correcoes/$safeId.jpg';
      await _client.storage.from('ecoscan-account-data').uploadBinary(
        path,
        bytes,
        fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
      );
    }
    if (_client.auth.currentUser?.id != user.id) return false;

    await _client.from('correcoes_usuario').upsert(
      {
        'usuario_id': user.id,
        'id_correcao_cliente': sample.id,
        'caminho_imagem': path,
        'origem': sample.source,
        'mecanismo_deteccao': sample.detector,
        'deteccoes': sample.detections,
        'rotulo_informado_usuario': sample.reportedLabel,
        'lixeira_informada_usuario': sample.reportedBin,
        'observacao': sample.reportNote,
        'detectado_por_ia': sample.aiDetected ?? false,
        'rotulo_original': sample.originalLabel,
        'confianca_original': sample.originalConfidence,
        'criado_em': sample.createdAt.toUtc().toIso8601String(),
        'atualizado_em': DateTime.now().toUtc().toIso8601String(),
      },
      onConflict: 'usuario_id,id_correcao_cliente',
    );
    if (_client.auth.currentUser?.id != user.id) return false;
    await FirebaseAccountBackupService.shared.saveCorrection(
      user.id,
      sample,
      supabaseImagePath: path,
    );
    return _client.auth.currentUser?.id == user.id;
  }

  /// Uploads local corrections, then restores account corrections not yet
  /// submitted to training. This runs on sign-in and when the app resumes.
  Future<bool> syncAndRestore(EcoScanStore store) async {
    final user = _client.auth.currentUser;
    if (user == null || store.userId != user.id) return false;

    final uploadsSucceeded = await uploadPending(store);
    if (store.userId != user.id || _client.auth.currentUser?.id != user.id) {
      return false;
    }

    final restored = <LearningSample>[];
    const pageSize = 100;
    for (var start = 0; ; start += pageSize) {
      final rows = await _client
          .from('correcoes_usuario')
          .select(
            'id_correcao_cliente,caminho_imagem,origem,mecanismo_deteccao,'
            'deteccoes,rotulo_informado_usuario,lixeira_informada_usuario,'
            'observacao,detectado_por_ia,rotulo_original,confianca_original,criado_em',
          )
          .eq('usuario_id', user.id)
          .isFilter('enviada_para_revisao_em', null)
          .order('criado_em', ascending: false)
          .range(start, start + pageSize - 1);

      final localIds = store.learningSamples.map((sample) => sample.id).toSet();
      for (var batchStart = 0; batchStart < rows.length; batchStart += 8) {
        if (store.userId != user.id ||
            _client.auth.currentUser?.id != user.id) {
          return false;
        }
        final batchEnd = (batchStart + 8).clamp(0, rows.length).toInt();
        final batch = rows.sublist(batchStart, batchEnd);
        final samples = await Future.wait<LearningSample?>(
          batch.map((row) async {
            final id = row['id_correcao_cliente']?.toString() ?? '';
            if (id.isEmpty || localIds.contains(id)) return null;
            final path = row['caminho_imagem']?.toString() ?? '';
            if (path.isEmpty) {
              return _sampleFromRow(row, Uint8List(0));
            }
            try {
              final bytes = await _client.storage
                  .from('ecoscan-account-data')
                  .download(path);
              if (bytes.isEmpty) return null;
              return _sampleFromRow(row, bytes);
            } catch (_) {
              // Metadata remains in the cloud and can be retried later.
              return null;
            }
          }),
        );
        if (store.userId != user.id ||
            _client.auth.currentUser?.id != user.id) {
          return false;
        }
        for (final sample in samples.whereType<LearningSample>()) {
          if (localIds.add(sample.id)) restored.add(sample);
        }
      }
      if (rows.length < pageSize) break;
    }
    if (store.userId == user.id &&
        _client.auth.currentUser?.id == user.id &&
        restored.isNotEmpty) {
      await store.mergeCloudLearningSamples(restored);
    }
    return uploadsSucceeded &&
        store.userId == user.id &&
        _client.auth.currentUser?.id == user.id;
  }

  /// Flushes corrections from this device to the private account backup.
  /// Failed items remain local and are retried on the next sync.
  Future<bool> uploadPending(EcoScanStore store) async {
    final user = _client.auth.currentUser;
    if (user == null || store.userId != user.id) return false;

    await store.primePendingCorrectionUploadQueue();
    if (store.pendingCorrectionUploadIds.isEmpty) return true;

    final sentIds = await _fetchSubmittedIds(user.id);
    if (store.userId != user.id || _client.auth.currentUser?.id != user.id) {
      return false;
    }
    if (sentIds.isNotEmpty) await store.removeLearningSamples(sentIds);

    var success = true;
    final samplesById = <String, LearningSample>{
      for (final sample in store.learningSamples) sample.id: sample,
    };
    for (final id in store.pendingCorrectionUploadIds) {
      if (store.userId != user.id ||
          _client.auth.currentUser?.id != user.id) {
        return false;
      }
      if (sentIds.contains(id)) continue;
      final sample = samplesById[id];
      if (sample == null) {
        await store.acknowledgeCorrectionUploads(
          [id],
          userIdOverride: user.id,
        );
        continue;
      }
      try {
        if (await saveSample(sample)) {
          await store.acknowledgeCorrectionUploads(
            [id],
            userIdOverride: user.id,
          );
        } else {
          success = false;
        }
      } catch (_) {
        // Keep the local copy; report failure so the exit flow can retry.
        success = false;
      }
    }
    return success &&
        store.userId == user.id &&
        _client.auth.currentUser?.id == user.id;
  }

  Future<Set<String>> _fetchSubmittedIds(String userId) async {
    final ids = <String>{};
    const pageSize = 500;
    for (var start = 0; ; start += pageSize) {
      final rows = await _client
          .from('correcoes_usuario')
          .select('id_correcao_cliente,enviada_para_revisao_em')
          .eq('usuario_id', userId)
          .not('enviada_para_revisao_em', 'is', null)
          .range(start, start + pageSize - 1);
      for (final row in rows) {
        final id = row['id_correcao_cliente']?.toString() ?? '';
        if (id.isNotEmpty) ids.add(id);
      }
      if (rows.length < pageSize) break;
    }
    return ids;
  }

  Future<Set<String>> fetchSubmittedIds(String userId) =>
      _fetchSubmittedIds(userId);

  Future<void> markSubmitted(Iterable<String> sampleIds) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    final ids = sampleIds.where((id) => id.isNotEmpty).toSet().toList();
    if (ids.isEmpty) return;
    await _client
        .from('correcoes_usuario')
        .update({
          'enviada_para_revisao_em': DateTime.now().toUtc().toIso8601String(),
          'atualizado_em': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('usuario_id', user.id)
        .inFilter('id_correcao_cliente', ids);
  }

  static LearningSample _sampleFromRow(
    Map<String, dynamic> row,
    Uint8List bytes,
  ) {
    final rawDetections = row['deteccoes'];
    final detections = rawDetections is List
        ? rawDetections
              .whereType<Map>()
              .map((value) => Map<String, dynamic>.from(value))
              .toList(growable: false)
        : const <Map<String, dynamic>>[];
    final confidence = row['confianca_original'];
    return LearningSample(
      id: row['id_correcao_cliente']?.toString() ?? '',
      createdAt:
          DateTime.tryParse(row['criado_em']?.toString() ?? '') ??
          DateTime.now(),
      source: row['origem']?.toString() ?? 'unknown',
      detector: row['mecanismo_deteccao']?.toString() ?? 'unknown',
      thumbnailDataUrl: bytes.isEmpty
          ? ''
          : 'data:image/jpeg;base64,${base64Encode(bytes)}',
      detections: detections,
      reportedLabel: row['rotulo_informado_usuario']?.toString(),
      reportedBin: row['lixeira_informada_usuario']?.toString(),
      reportNote: row['observacao']?.toString(),
      aiDetected: row['detectado_por_ia'] is bool
          ? row['detectado_por_ia'] as bool
          : null,
      originalLabel: row['rotulo_original']?.toString(),
      originalConfidence: confidence is num
          ? confidence.toDouble()
          : double.tryParse(confidence?.toString() ?? ''),
    );
  }

  static Uint8List? _decodeDataUrl(String value) {
    const prefix = 'data:image/jpeg;base64,';
    if (!value.startsWith(prefix)) return null;
    try {
      return base64Decode(value.substring(prefix.length));
    } catch (_) {
      return null;
    }
  }
}
