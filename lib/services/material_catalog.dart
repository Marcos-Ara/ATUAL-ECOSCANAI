import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/material_guide.dart';
import 'waste_classifier.dart';

/// Snapshot of the same public Supabase knowledge base used by the website.
/// Scan latency and availability do not depend on a network request.
class MaterialCatalog {
  MaterialCatalog.fromJson(Map<String, dynamic> json) {
    for (final row in _rows(json['yoloe_classes'])) {
      _yoloe[WasteClassifier.normalize(row['label']?.toString() ?? '')] = row;
    }
    for (final row in _rows(json['objects'])) {
      if (row['is_active'] == false) continue;
      _objects[row['object_id'].toString()] = row;
      final label = WasteClassifier.normalize(
        row['detection_class']?.toString() ?? '',
      );
      if (label.isNotEmpty) _byLabel.putIfAbsent(label, () => []).add(row);
    }
    for (final row in _rows(json['variants'])) {
      _variants[row['variant_id'].toString()] = row;
      _byObject.putIfAbsent(row['object_id'].toString(), () => []).add(row);
    }
    for (final row in _rows(json['aliases'])) {
      if (row['is_active'] == false) continue;
      final variant = _variants[row['variant_id']?.toString()];
      final object = _objects[row['object_id']?.toString()];
      final label = WasteClassifier.normalize(
        row['normalized_alias']?.toString() ?? '',
      );
      if (label.isNotEmpty && (variant ?? object) != null) {
        _byLabel.putIfAbsent(label, () => []).add(variant ?? object!);
      }
    }
  }
  final _objects = <String, Map<String, dynamic>>{};
  final _variants = <String, Map<String, dynamic>>{};
  final _byObject = <String, List<Map<String, dynamic>>>{};
  final _byLabel = <String, List<Map<String, dynamic>>>{};
  final _yoloe = <String, Map<String, dynamic>>{};

  static Iterable<Map<String, dynamic>> _rows(dynamic value) => value is List
      ? value.whereType<Map>().map((e) => Map<String, dynamic>.from(e))
      : const [];
  static Future<MaterialCatalog> load() async {
    final content = await rootBundle.loadString('assets/data/catalog.json');
    return MaterialCatalog.fromJson(
      jsonDecode(content) as Map<String, dynamic>,
    );
  }

  WasteClassification classify(List<LabelCandidate> candidates) {
    // The YOLO pipeline supplies only the selected object. Match its exact
    // prompt instead of allowing a generic heuristic to replace its material.
    if (candidates.length == 1) {
      final candidate = candidates.single;
      final prompt = _yoloe[WasteClassifier.normalize(candidate.label)];
      final floor = (prompt?['minimum_confidence'] as num?)?.toDouble() ?? .35;
      if (prompt != null &&
          candidate.confidence.isFinite &&
          candidate.confidence >= floor) {
        final material = prompt['material_id']?.toString();
        return WasteClassification(
          material: material == null ? null : MaterialGuide.byId(material),
          confidence: candidate.confidence,
          source: 'catalog-yoloe',
          detectedObject: prompt['object_name']?.toString(),
          instruction: prompt['instruction']?.toString(),
        );
      }
    }
    final direct = WasteClassifier.classifyCandidates(candidates);
    final scores = <String, double>{};
    final possible = <String, MaterialGuide>{};
    for (final candidate in candidates) {
      if (!candidate.confidence.isFinite || candidate.confidence < 0.60) {
        continue;
      }
      final matches =
          _byLabel[WasteClassifier.normalize(candidate.label)] ?? const [];
      for (final match in matches) {
        final guide = MaterialGuide.fromDatabase(match);
        final variants = _byObject[match['object_id'].toString()] ?? const [];
        final isVariant = match['variant_id'] != null;
        final special = guide?.id == 'special' || guide?.id == 'electronic';
        if (!isVariant && variants.isNotEmpty && !special) {
          for (final variant in variants) {
            final choice = MaterialGuide.fromDatabase(variant);
            if (choice != null) possible[choice.id] = choice;
          }
          // Bottle/cup/etc can have several materials. Never pick the first row.
          continue;
        }
        if (!isVariant && match['is_ambiguous'] == true && !special) {
          if (guide != null) possible[guide.id] = guide;
          continue;
        }
        if (guide != null) {
          final previous = scores[guide.id] ?? 0;
          if (candidate.confidence > previous) {
            scores[guide.id] = candidate.confidence;
          }
        }
      }
    }
    if (direct.isKnown) scores[direct.material!.id] = direct.confidence;
    for (final special in ['special', 'electronic']) {
      if ((scores[special] ?? 0) >= (special == 'electronic' ? 0.50 : 0.7)) {
        return WasteClassification(
          material: MaterialGuide.byId(special),
          confidence: scores[special]!,
          source: 'catalog',
        );
      }
    }
    final ranked = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (ranked.isNotEmpty) {
      if (ranked.length == 1 || ranked.first.value - ranked[1].value >= 0.15) {
        return WasteClassification(
          material: MaterialGuide.byId(ranked.first.key),
          confidence: ranked.first.value,
          source: 'catalog',
        );
      }
      for (final score in ranked) {
        possible[score.key] = MaterialGuide.byId(score.key);
      }
    }
    for (final choice in direct.options) {
      possible[choice.id] = choice;
    }
    return WasteClassification(options: possible.values.toList());
  }
}
