import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/material_guide.dart';
import 'waste_classifier.dart';

/// Resolves detector labels against the EcoScan knowledge base in Supabase.
///
/// The RPC already created for this project accepts `p_alias text`.
/// ScanService resolves against the bundled catalog first for speed/offline use
/// and calls this resolver only when the local result is still unresolved.
class SupabaseMaterialResolver {
  SupabaseMaterialResolver({SupabaseClient? client}) : this._(client);

  SupabaseMaterialResolver._(this._client);

  final SupabaseClient? _client;

  Future<WasteClassification?> resolve(List<LabelCandidate> candidates) async {
    final ranked =
        candidates
            .where((item) {
              if (!item.confidence.isFinite) return false;
              final minimum = WasteClassifier.isStrongSpecificLabel(item.label)
                  ? WasteClassifier.minimumConfidenceForLabel(item.label)
                  : 0.50;
              return item.confidence >= minimum;
            })
            .toList(growable: false)
          ..sort((a, b) => b.confidence.compareTo(a.confidence));

    for (final candidate in ranked.take(4)) {
      final alias = WasteClassifier.normalize(candidate.label);
      if (alias.isEmpty) continue;
      try {
        final client = _client ?? Supabase.instance.client;
        final data = await client.rpc(
          'find_ecoscan_object',
          params: {'p_alias': alias},
        );
        final row = _firstRow(data);
        if (row == null) continue;
        final material = MaterialGuide.fromDatabase(row);
        if (material == null) continue;
        final objectName = (row['object_name'] ?? row['variant_name'] ?? '')
            .toString()
            .trim();
        final instruction =
            (row['preparation_instructions'] ??
                    row['recommendation'] ??
                    row['destination'])
                ?.toString()
                .trim();
        return WasteClassification(
          material: material,
          confidence: candidate.confidence,
          source: 'supabase',
          instruction: instruction?.isNotEmpty == true ? instruction : null,
          detectedObject: objectName.isNotEmpty
              ? objectName
              : WasteClassifier.bestObjectName(candidates),
        );
      } catch (_) {
        // The caller intentionally falls back to the bundled catalog.
        return null;
      }
    }
    return null;
  }

  static Map<String, dynamic>? _firstRow(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is List && value.isNotEmpty && value.first is Map) {
      return Map<String, dynamic>.from(value.first as Map);
    }
    return null;
  }
}
