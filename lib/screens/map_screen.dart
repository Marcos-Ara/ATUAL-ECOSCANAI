import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart' as vt;
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_config.dart';
import '../core/app_theme.dart';
import '../models/eco_point.dart';
import '../state/eco_point_controller.dart';
import '../state/ecoscan_store.dart';

class EcoPointsScreen extends StatefulWidget {
  const EcoPointsScreen({
    this.initialSearch,
    this.initialMaterialId,
    super.key,
  });

  final String? initialSearch;
  final String? initialMaterialId;

  @override
  State<EcoPointsScreen> createState() => _EcoPointsScreenState();
}

class _EcoPointsScreenState extends State<EcoPointsScreen> {
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();
  bool _mapReady = false;
  bool _initialSearchApplied = false;

  @override
  void dispose() {
    _searchController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _initializeMap() async {
    if (_mapReady) return;
    _mapReady = true;
    final controller = context.read<EcoPointController>();
    await controller.initialize();
    if (!mounted) return;
    final initialSearch = widget.initialSearch?.trim() ?? '';
    if (!_initialSearchApplied && initialSearch.isNotEmpty) {
      _initialSearchApplied = true;
      _searchController.text = initialSearch;
      await controller.submitSearch(
        initialSearch,
        materialId: widget.initialMaterialId,
      );
    }
    if (mounted) _showAllPoints();
  }

  void _showAllPoints() {
    final points = context.read<EcoPointController>().allPoints;
    if (points.isEmpty || !_mapReady) return;
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(points.map((p) => p.position).toList()),
        padding: EdgeInsets.fromLTRB(
          48,
          160,
          48,
          MediaQuery.sizeOf(context).height * 0.30 + 32,
        ),
        maxZoom: 13,
      ),
    );
  }

  Future<void> _centerOnUser() async {
    final controller = context.read<EcoPointController>();
    await controller.locateAndSearch();
    if (!mounted) return;
    final location = controller.userLocation;
    if (location != null) _mapController.move(location, 15);
  }

  Future<void> _openDirections(EcoPoint point) async {
    final uri = Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'destination': '${point.latitude},${point.longitude}',
      'travelmode': 'driving',
    });
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível abrir o aplicativo de mapas.'),
        ),
      );
    }
  }

  void _showPoint(EcoPoint point) {
    unawaited(context.read<EcoScanStore>().markMapExplored());
    _mapController.move(point.position, 16);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 4, 22, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(point.name, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 6),
                Text(
                  point.type,
                  style: const TextStyle(color: AppColors.muted),
                ),
                if (point.source == 'geosampa') ...[
                  const SizedBox(height: 8),
                  const Chip(
                    avatar: Icon(Icons.verified_outlined, size: 17),
                    label: Text('Fonte oficial GeoSampa'),
                  ),
                ],
                if (point.address?.isNotEmpty == true) ...[
                  const SizedBox(height: 8),
                  Text(point.address!),
                ],
                if (point.district?.isNotEmpty == true ||
                    point.administrativeArea?.isNotEmpty == true) ...[
                  const SizedBox(height: 6),
                  Text(
                    [
                      if (point.district?.isNotEmpty == true)
                        'Distrito: ${point.district}',
                      if (point.administrativeArea?.isNotEmpty == true)
                        'Subprefeitura: ${point.administrativeArea}',
                    ].join(' · '),
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
                if (point.isOpen != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    point.isOpen! ? 'Aberto agora' : 'Fechado agora',
                    style: TextStyle(
                      color: point.isOpen!
                          ? AppColors.primary
                          : AppColors.danger,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                if (point.openingHours?.isNotEmpty == true) ...[
                  const SizedBox(height: 6),
                  Text(
                    point.openingHours!,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
                if (point.acceptedMaterialsDescription?.isNotEmpty == true) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Recebe: ${point.acceptedMaterialsDescription}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ] else if (point.acceptedMaterialIds.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Materiais informados: ${point.acceptedMaterialIds.join(', ')}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
                const SizedBox(height: 14),
                if (point.phone?.isNotEmpty == true ||
                    point.website?.isNotEmpty == true)
                  Wrap(
                    spacing: 8,
                    children: [
                      if (point.phone?.isNotEmpty == true)
                        OutlinedButton.icon(
                          onPressed: () =>
                              launchUrl(Uri(scheme: 'tel', path: point.phone)),
                          icon: const Icon(Icons.phone_outlined),
                          label: const Text('Ligar'),
                        ),
                      if (point.website?.isNotEmpty == true)
                        OutlinedButton.icon(
                          onPressed: () => launchUrl(
                            Uri.parse(point.website!),
                            mode: LaunchMode.externalApplication,
                          ),
                          icon: const Icon(Icons.language_outlined),
                          label: const Text('Site'),
                        ),
                    ],
                  ),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => _openDirections(point),
                    icon: const Icon(Icons.directions_rounded),
                    label: Text(
                      'Abrir rota${_distanceText(point.distanceMeters)}',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<EcoPointController>();
    final points = controller.allPoints;
    final nearbyPoints = controller.nearbyPoints;
    final initialCenter =
        controller.userLocation ??
        const LatLng(AppConfig.defaultLatitude, AppConfig.defaultLongitude);

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: initialCenter,
            initialZoom: 10.5,
            minZoom: 3,
            maxZoom: 19,
            onMapReady: () => unawaited(_initializeMap()),
            onPositionChanged: (camera, hasGesture) {
              controller.onMapMoved(camera.center, camera.zoom);
            },
          ),
          children: [
            if (controller.tileStyle == MapTileStyle.satellite)
              TileLayer(
                urlTemplate:
                    'https://server.arcgisonline.com/ArcGIS/rest/services/'
                    'World_Imagery/MapServer/tile/{z}/{y}/{x}',
                userAgentPackageName: AppConfig.packageName,
                maxZoom: 19,
              )
            else
              _OpenFreeMapLayer(style: controller.tileStyle),
            MarkerLayer(
              markers: [
                for (var index = 0; index < points.length; index++)
                  Marker(
                    point: points[index].position,
                    width: 44,
                    height: 52,
                    alignment: Alignment.topCenter,
                    child: _EcoPointMarker(
                      number: index + 1,
                      category: points[index].category,
                      onTap: () => _showPoint(points[index]),
                    ),
                  ),
                if (controller.userLocation case final location?)
                  Marker(
                    point: location,
                    width: 34,
                    height: 34,
                    child: const _UserMarker(),
                  ),
              ],
            ),
            SimpleAttributionWidget(
              source: Text(
                controller.tileStyle == MapTileStyle.satellite
                    ? 'Esri · OpenStreetMap contributors'
                    : 'OpenFreeMap · © OpenMapTiles · OpenStreetMap',
                style: const TextStyle(fontSize: 9),
              ),
              backgroundColor: const Color(0xB307100B),
              onTap: () => launchUrl(
                Uri.parse(
                  controller.tileStyle == MapTileStyle.satellite
                      ? 'https://www.esri.com/'
                      : 'https://openfreemap.org/',
                ),
              ),
            ),
          ],
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        onChanged: controller.setSearchText,
                        onSubmitted: (value) =>
                            unawaited(controller.submitSearch(value)),
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: 'Buscar EcoPonto, material ou endereço',
                          prefixIcon: const Icon(Icons.search_rounded),
                          suffixIcon: _searchController.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Limpar busca',
                                  onPressed: () {
                                    _searchController.clear();
                                    controller.setSearchText('');
                                    setState(() {});
                                  },
                                  icon: const Icon(Icons.close_rounded),
                                ),
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 12,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 9),
                    _MapAction(
                      icon: Icons.layers_outlined,
                      child: PopupMenuButton<MapTileStyle>(
                        tooltip: 'Estilo do mapa',
                        initialValue: controller.tileStyle,
                        onSelected: controller.setTileStyle,
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: MapTileStyle.dark,
                            child: Text('Escuro'),
                          ),
                          PopupMenuItem(
                            value: MapTileStyle.streets,
                            child: Text('Ruas'),
                          ),
                          PopupMenuItem(
                            value: MapTileStyle.satellite,
                            child: Text('Satélite'),
                          ),
                        ],
                        icon: const Icon(Icons.layers_outlined),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 340),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xE6101A13),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (controller.isBusy)
                          const Padding(
                            padding: EdgeInsets.only(right: 9),
                            child: SizedBox(
                              width: 13,
                              height: 13,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        else
                          const Padding(
                            padding: EdgeInsets.only(right: 7),
                            child: Icon(
                              Icons.eco_outlined,
                              size: 15,
                              color: AppColors.primary,
                            ),
                          ),
                        Flexible(
                          child: Text(
                            controller.status,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 10.5,
                              height: 1.25,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          right: 14,
          bottom: MediaQuery.sizeOf(context).height * 0.29,
          child: Column(
            children: [
              FloatingActionButton.small(
                heroTag: 'map-refresh',
                tooltip: 'Atualizar catálogo completo',
                onPressed: controller.isSearching
                    ? null
                    : controller.refreshCatalog,
                child: const Icon(Icons.refresh_rounded),
              ),
              const SizedBox(height: 9),
              FloatingActionButton.small(
                heroTag: 'map-all',
                tooltip: 'Ver todos os EcoPontos de São Paulo',
                onPressed: points.isEmpty ? null : _showAllPoints,
                child: const Icon(Icons.zoom_out_map_rounded),
              ),
              const SizedBox(height: 9),
              FloatingActionButton.small(
                heroTag: 'map-location',
                tooltip: 'Minha localização',
                onPressed: controller.isLocating ? null : _centerOnUser,
                child: const Icon(Icons.my_location_rounded),
              ),
            ],
          ),
        ),
        _PointsSheet(
          points: nearbyPoints,
          usesMapCenter: controller.usesMapCenter,
          radiusMeters: controller.nearbyRadiusMeters,
          onRadius: controller.setNearbyRadius,
          totalCount: controller.totalCount,
          onPointTap: _showPoint,
          onDirections: _openDirections,
        ),
      ],
    );
  }
}

class _OpenFreeMapLayer extends StatefulWidget {
  const _OpenFreeMapLayer({required this.style});

  final MapTileStyle style;

  @override
  State<_OpenFreeMapLayer> createState() => _OpenFreeMapLayerState();
}

class _OpenFreeMapLayerState extends State<_OpenFreeMapLayer> {
  dynamic _style;
  Object? _error;
  int _loadGeneration = 0;

  String get _styleUrl => widget.style == MapTileStyle.dark
      ? 'https://tiles.openfreemap.org/styles/dark'
      : 'https://tiles.openfreemap.org/styles/liberty';

  @override
  void initState() {
    super.initState();
    _loadStyle();
  }

  @override
  void didUpdateWidget(covariant _OpenFreeMapLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.style != widget.style) _loadStyle();
  }

  Future<void> _loadStyle() async {
    final generation = ++_loadGeneration;
    final previous = _style;
    _style = null;
    _error = null;
    if (mounted) setState(() {});
    try {
      previous?.dispose();
    } catch (_) {}

    try {
      final loaded = await vt.StyleReader(uri: _styleUrl).read();
      if (!mounted || generation != _loadGeneration) {
        loaded.dispose();
        return;
      }
      setState(() => _style = loaded);
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _error = error);
    }
  }

  @override
  void dispose() {
    _loadGeneration++;
    try {
      _style?.dispose();
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = _style;
    if (style != null) {
      return vt.VectorTileLayer(
        theme: style.theme,
        tileProviders: style.providers,
        rasterSources: style.rasterSources,
        sprites: style.sprites,
        tileFadeDuration: const Duration(milliseconds: 120),
        labelFadeDuration: const Duration(milliseconds: 120),
      );
    }

    return ColoredBox(
      color: widget.style == MapTileStyle.dark
          ? const Color(0xFF101713)
          : const Color(0xFFE7EEE8),
      child: Center(
        child: _error == null
            ? const SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              )
            : FilledButton.tonalIcon(
                onPressed: _loadStyle,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Recarregar mapa'),
              ),
      ),
    );
  }
}

class _MapAction extends StatelessWidget {
  const _MapAction({required this.icon, required this.child});

  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppColors.border),
      ),
      child: SizedBox(width: 52, height: 52, child: child),
    );
  }
}

class _EcoPointMarker extends StatelessWidget {
  const _EcoPointMarker({
    required this.number,
    required this.category,
    required this.onTap,
  });

  final int number;
  final EcoPointCategory category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = category == EcoPointCategory.recycling
        ? AppColors.primary
        : AppColors.danger;
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          Icon(
            Icons.location_on_rounded,
            color: Colors.black.withValues(alpha: 0.42),
            size: 48,
          ),
          Icon(Icons.location_on_rounded, color: color, size: 45),
          Positioned(
            top: 8,
            child: Container(
              constraints: const BoxConstraints(minWidth: 20),
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                number > 999 ? '999+' : '$number',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UserMarker extends StatelessWidget {
  const _UserMarker();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.blue.withValues(alpha: 0.23),
        border: Border.all(color: Colors.white, width: 2),
      ),
      padding: const EdgeInsets.all(7),
      child: const DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.blue,
        ),
      ),
    );
  }
}

class _PointsSheet extends StatelessWidget {
  const _PointsSheet({
    required this.points,
    required this.totalCount,
    required this.usesMapCenter,
    required this.radiusMeters,
    required this.onRadius,
    required this.onPointTap,
    required this.onDirections,
  });

  final List<EcoPoint> points;
  final int totalCount;
  final bool usesMapCenter;
  final int radiusMeters;
  final ValueChanged<int> onRadius;
  final ValueChanged<EcoPoint> onPointTap;
  final ValueChanged<EcoPoint> onDirections;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      minChildSize: 0.17,
      initialChildSize: 0.30,
      maxChildSize: 0.66,
      snap: true,
      builder: (context, scrollController) {
        return DecoratedBox(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
            border: Border(top: BorderSide(color: AppColors.border)),
            boxShadow: [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 24,
                offset: Offset(0, -6),
              ),
            ],
          ),
          child: Material(
            type: MaterialType.transparency,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
            clipBehavior: Clip.antiAlias,
            child: CustomScrollView(
              controller: scrollController,
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 9, 16, 10),
                    child: Column(
                      children: [
                        Container(
                          width: 42,
                          height: 4,
                          decoration: BoxDecoration(
                            color: AppColors.border,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'EcoPontos próximos',
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            Text(
                              '$totalCount no mapa',
                              style: const TextStyle(
                                color: AppColors.muted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          usesMapCenter
                              ? 'Até 10 próximos do centro do mapa · ${radiusMeters ~/ 1000} km'
                              : 'Até 10 próximos de você · ${radiusMeters ~/ 1000} km',
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            for (final km in const [5, 10, 25])
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                child: ChoiceChip(
                                  label: Text('$km km'),
                                  selected: radiusMeters == km * 1000,
                                  onSelected: (_) => onRadius(km * 1000),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (points.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Nenhum EcoPonto próximo corresponde aos filtros. '
                          'Amplie a distância ou limpe a busca. Todos os pontos continuam no mapa.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.muted),
                        ),
                      ),
                    ),
                  )
                else
                  SliverList.separated(
                    itemCount: points.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, indent: 70),
                    itemBuilder: (context, index) {
                      final point = points[index];
                      return ListTile(
                        onTap: () => onPointTap(point),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        leading: CircleAvatar(
                          backgroundColor:
                              (point.category == EcoPointCategory.recycling
                                      ? AppColors.primary
                                      : AppColors.danger)
                                  .withValues(alpha: 0.14),
                          child: Icon(
                            point.category == EcoPointCategory.recycling
                                ? Icons.recycling_rounded
                                : Icons.delete_outline_rounded,
                            color: point.category == EcoPointCategory.recycling
                                ? AppColors.primary
                                : AppColors.danger,
                          ),
                        ),
                        title: Text(
                          point.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${_distanceText(point.distanceMeters).replaceFirst(' · ', '')} · '
                          '${point.address ?? point.type}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: IconButton(
                          tooltip: 'Abrir rota',
                          onPressed: () => onDirections(point),
                          icon: const Icon(
                            Icons.directions_rounded,
                            color: AppColors.primary,
                          ),
                        ),
                      );
                    },
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 16)),
              ],
            ),
          ),
        );
      },
    );
  }
}

String _distanceText(double? meters) {
  if (meters == null) return '';
  if (meters < 1000) return ' · ${meters.round()} m';
  return ' · ${(meters / 1000).toStringAsFixed(1)} km';
}
