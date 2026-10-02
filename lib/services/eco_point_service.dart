import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../core/app_config.dart';
import '../core/backend_config.dart';
import '../models/eco_point.dart';

/// Complete official catalog: bundled GeoSampa snapshot first, Supabase refresh.
/// No location, search radius, map API key or Edge Function is needed to load it.
class EcoPointService {
  EcoPointService({http.Client? client, AssetBundle? bundle})
    : _client = client ?? http.Client(),
      _bundle = bundle ?? rootBundle;

  final http.Client _client;
  final AssetBundle _bundle;

  Future<List<EcoPoint>> loadBundledCatalog() async {
    return parseGeoSampa(
      await _bundle.loadString('assets/data/ecopoints_geosampa.geojson'),
    );
  }

  Future<List<EcoPoint>> fetchCatalog() async {
    final points = <EcoPoint>[];
    // Explicit pagination avoids silently losing records if the dataset grows.
    const pageSize = 500;
    for (var offset = 0; ; offset += pageSize) {
      final uri = Uri.parse('${BackendConfig.supabaseUrl}/rest/v1/ecopoints')
          .replace(
            queryParameters: {
              'select': '*',
              'source': 'eq.geosampa',
              'is_active': 'eq.true',
              'order': 'id.asc',
              'offset': '$offset',
              'limit': '$pageSize',
            },
          );
      final response = await _client
          .get(
            uri,
            headers: {
              'apikey': BackendConfig.supabasePublicKey,
              'Accept': 'application/json',
            },
          )
          .timeout(AppConfig.requestTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw const FormatException('Catálogo remoto indisponível.');
      }
      final rows = jsonDecode(utf8.decode(response.bodyBytes));
      if (rows is! List) throw const FormatException('Catálogo inválido.');
      for (final raw in rows.whereType<Map>()) {
        final row = Map<String, dynamic>.from(raw);
        final latitude = _toDouble(row['latitude']);
        final longitude = _toDouble(row['longitude']);
        if (!_validCoordinates(latitude, longitude)) continue;
        points.add(
          EcoPoint.fromJson({
            ...row,
            'latitude': latitude,
            'longitude': longitude,
            'openingHours': row['opening_hours'],
            'acceptedMaterialIds': row['accepted_material_ids'],
            'acceptedMaterialsDescription':
                row['accepted_materials_description'],
            'administrativeArea': row['administrative_area'],
            'sourceUrl': row['source_url'],
          }),
        );
      }
      if (rows.length < pageSize) break;
    }
    return _deduplicate(points);
  }

  static bool _validCoordinates(double? lat, double? lon) =>
      lat != null &&
      lon != null &&
      lat.isFinite &&
      lon.isFinite &&
      lat >= -90 &&
      lat <= 90 &&
      lon >= -180 &&
      lon <= 180;

  static List<EcoPoint> parseGeoSampa(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic> || decoded['features'] is! List) {
      throw const FormatException('Resposta GeoSampa inválida.');
    }
    final points = <EcoPoint>[];
    for (final raw in (decoded['features'] as List).whereType<Map>()) {
      final feature = Map<String, dynamic>.from(raw);
      final geometry = feature['geometry'];
      final properties = feature['properties'];
      if (geometry is! Map || properties is! Map) continue;
      final coordinates = geometry['coordinates'];
      if (coordinates is! List || coordinates.length < 2) continue;
      final longitude = _toDouble(coordinates[0]);
      final latitude = _toDouble(coordinates[1]);
      if (!_validCoordinates(latitude, longitude)) {
        throw const FormatException(
          'Converta as coordenadas GeoSampa para WGS84.',
        );
      }
      final values = Map<String, dynamic>.from(properties);
      final common = _nonEmpty(values['tx_recebimento_comum']?.toString());
      final special = _nonEmpty(
        values['tx_recebimento_diferenciado']?.toString(),
      );
      final acceptedDescription = [?common, ?special].join(' · ');
      final identifier = values['cd_identificador_ecoponto'] ?? feature['id'];
      points.add(
        EcoPoint(
          id: 'geosampa:${identifier ?? '$latitude,$longitude'}',
          name: _nonEmpty(values['nm_ecoponto']?.toString()) ?? 'Ecoponto',
          type: 'Ecoponto oficial da Prefeitura de São Paulo',
          category: EcoPointCategory.recycling,
          latitude: latitude!,
          longitude: longitude!,
          address: _nonEmpty(values['nm_endereco']?.toString()),
          openingHours: _nonEmpty(values['tx_atendimento']?.toString()),
          acceptedMaterialIds: _materialsFromText(acceptedDescription),
          acceptedMaterialsDescription: acceptedDescription.isEmpty
              ? null
              : acceptedDescription,
          district: _nonEmpty(values['nm_distrito']?.toString()),
          administrativeArea: _nonEmpty(values['nm_subprefeitura']?.toString()),
          access: 'official',
          source: 'geosampa',
          sourceUrl: 'https://geosampa.prefeitura.sp.gov.br/',
        ),
      );
    }
    return _deduplicate(points);
  }

  static List<EcoPoint> _deduplicate(Iterable<EcoPoint> items) {
    final unique = <String, EcoPoint>{};
    for (final item in items) {
      unique[item.id] = item;
    }
    return unique.values.toList(growable: false);
  }

  static List<String> _materialsFromText(String text) {
    final value = text.toLowerCase();
    final materials = <String>[];
    void addIf(bool condition, String id) {
      if (condition) materials.add(id);
    }

    addIf(value.contains('plastic') || value.contains('plástico'), 'plastic');
    addIf(value.contains('glass') || value.contains('vidro'), 'glass');
    addIf(value.contains('paper') || value.contains('papel'), 'paper');
    addIf(
      value.contains('cardboard') || value.contains('papelão'),
      'cardboard',
    );
    addIf(value.contains('metal') || value.contains('alumin'), 'metal');
    addIf(
      value.contains('electronic') || value.contains('eletrôn'),
      'electronic',
    );
    addIf(value.contains('battery') || value.contains('bateria'), 'battery');
    addIf(value.contains('organic') || value.contains('orgânico'), 'organic');
    if (value.contains('recicláveis secos') ||
        value.contains('reciclaveis secos')) {
      materials.addAll(const ['plastic', 'glass', 'paper', 'metal']);
    }
    addIf(
      value.contains('entulho') ||
          value.contains('volumoso') ||
          value.contains('gesso'),
      'special',
    );
    return materials.toSet().toList(growable: false);
  }

  static String? _nonEmpty(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static double? _toDouble(Object? value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '');

  void dispose() => _client.close();
}
