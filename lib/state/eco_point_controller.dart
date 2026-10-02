import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../core/app_config.dart';
import '../models/eco_point.dart';
import '../services/eco_point_service.dart';
import '../services/waste_classifier.dart';
import 'ecoscan_store.dart';

enum MapTileStyle { dark, streets, satellite }

class EcoPointController extends ChangeNotifier {
  EcoPointController({
    required EcoPointService service,
    required EcoScanStore store,
  }) : this._(service, store);

  EcoPointController._(this._service, this._store);

  final EcoPointService _service;
  final EcoScanStore _store;
  final Map<String, EcoPoint> _points = {};
  bool _initialized = false;
  bool _disposed = false;
  bool _isSearching = false;
  bool _isLocating = false;
  String _status = 'Carregando o catálogo de EcoPontos de São Paulo…';
  String _searchText = '';
  String? _materialFilter;
  LatLng? _userLocation;
  LatLng _lastMapCenter = const LatLng(
    AppConfig.defaultLatitude,
    AppConfig.defaultLongitude,
  );
  int _nearbyRadiusMeters = 5000;
  EcoPointCategory? _categoryFilter;
  MapTileStyle _tileStyle = MapTileStyle.streets;

  bool get isSearching => _isSearching;
  bool get isLocating => _isLocating;
  bool get isBusy => _isSearching || _isLocating;
  String get status => _status;
  LatLng? get userLocation => _userLocation;
  MapTileStyle get tileStyle => _tileStyle;
  EcoPointCategory? get categoryFilter => _categoryFilter;
  int get totalCount => _points.length;
  int get nearbyRadiusMeters => _nearbyRadiusMeters;
  String get activeQuery => _searchText;
  bool get usesMapCenter => _userLocation == null;

  /// Every official record stays on the map, regardless of location or filters.
  List<EcoPoint> get allPoints {
    final items = _points.values.toList();
    items.sort((a, b) {
      final result = (a.distanceMeters ?? double.infinity).compareTo(
        b.distanceMeters ?? double.infinity,
      );
      return result != 0 ? result : a.id.compareTo(b.id);
    });
    return items;
  }

  /// Filters only the bottom results bar, never the map catalog.
  List<EcoPoint> get filteredPoints {
    final query = WasteClassifier.normalize(_searchText);
    return allPoints
        .where((point) {
          if (_categoryFilter != null && point.category != _categoryFilter) {
            return false;
          }
          final material = _materialFilter;
          if (material != null && material.isNotEmpty) {
            return point.acceptedMaterialIds.contains(material);
          }
          if (query.isEmpty) return true;
          return WasteClassifier.normalize(
            '${point.name} ${point.type} ${point.address ?? ''} '
            '${point.acceptedMaterialsDescription ?? ''} '
            '${point.district ?? ''} ${point.administrativeArea ?? ''}',
          ).contains(query);
        })
        .toList(growable: false);
  }

  List<EcoPoint> get nearbyPoints => filteredPoints
      .where(
        (point) =>
            (point.distanceMeters ?? double.infinity) <= _nearbyRadiusMeters,
      )
      .take(10)
      .toList(growable: false);

  Future<void> initialize({bool locate = true, bool refresh = true}) async {
    if (_initialized || _disposed) return;
    _initialized = true;
    try {
      final cached = await _store.loadCachedEcoPoints();
      if (_disposed) return;
      _merge(cached.where((p) => p.source == 'geosampa'));
      _merge(await _service.loadBundledCatalog());
      if (_disposed) return;
      _status =
          '$totalCount EcoPontos de São Paulo no mapa. Lista por proximidade.';
      notifyListeners();
      await _store.saveEcoPoints(allPoints);
    } catch (_) {
      _status = 'Não foi possível ler o catálogo local. Tente atualizar.';
      notifyListeners();
    }
    if (_disposed) return;
    if (refresh && AppConfig.useSupabaseEcoPoints) {
      unawaited(refreshCatalog());
    }
    if (locate) unawaited(locateAndSearch());
  }

  Future<void> refreshCatalog() async {
    if (_isSearching || _disposed) return;
    if (!AppConfig.useSupabaseEcoPoints) {
      _status = '$totalCount EcoPontos no mapa. Catálogo local GeoSampa.';
      notifyListeners();
      return;
    }
    _isSearching = true;
    _status = 'Atualizando o catálogo completo…';
    notifyListeners();
    try {
      final remote = await _service.fetchCatalog();
      if (_disposed) return;
      if (remote.isNotEmpty) {
        // A complete remote snapshot replaces old records, including removals.
        _points.clear();
        _merge(remote);
        await _store.saveEcoPoints(allPoints);
        _status = '$totalCount EcoPontos no mapa. Catálogo atualizado.';
      } else {
        _status = '$totalCount EcoPontos no mapa. Catálogo local disponível.';
      }
    } catch (_) {
      _status =
          '$totalCount EcoPontos no mapa. Usando o catálogo local GeoSampa.';
    } finally {
      _isSearching = false;
      notifyListeners();
    }
  }

  Future<void> locateAndSearch() async {
    if (_isLocating || _disposed) return;
    _isLocating = true;
    notifyListeners();
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw const _LocationMessage(
          'Localização desativada. Lista pelo centro do mapa.',
        );
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw const _LocationMessage(
          'Localização não autorizada. Lista pelo centro do mapa.',
        );
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      if (_disposed) return;
      _userLocation = LatLng(position.latitude, position.longitude);
      _recalculateDistances();
      _status = '$totalCount EcoPontos no mapa. Lista próxima de você.';
    } on _LocationMessage catch (error) {
      _status = error.message;
    } catch (_) {
      _status = 'Localização indisponível. Lista pelo centro do mapa.';
    } finally {
      _isLocating = false;
      notifyListeners();
    }
  }

  void onMapMoved(LatLng center, double zoom) {
    if (_disposed || center == _lastMapCenter) return;
    _lastMapCenter = center;
    if (_userLocation == null) {
      _recalculateDistances();
      notifyListeners();
    }
  }

  Future<void> submitSearch(String value, {String? materialId}) async {
    _searchText = value.trim();
    _materialFilter = materialId;
    notifyListeners();
  }

  void setSearchText(String value) {
    _searchText = value;
    _materialFilter = null;
    notifyListeners();
  }

  void setNearbyRadius(int meters) {
    _nearbyRadiusMeters = meters.clamp(1000, 25000).toInt();
    notifyListeners();
  }

  void setCategoryFilter(EcoPointCategory? category) {
    _categoryFilter = category;
    notifyListeners();
  }

  void setTileStyle(MapTileStyle style) {
    _tileStyle = style;
    notifyListeners();
  }

  void _merge(Iterable<EcoPoint> incoming) {
    if (_disposed) return;
    for (final point in incoming) {
      _points[point.id] = point.withDistanceFrom(
        _userLocation ?? _lastMapCenter,
      );
    }
  }

  void _recalculateDistances() {
    final origin = _userLocation ?? _lastMapCenter;
    for (final key in _points.keys.toList()) {
      _points[key] = _points[key]!.withDistanceFrom(origin);
    }
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class _LocationMessage implements Exception {
  const _LocationMessage(this.message);
  final String message;
}
