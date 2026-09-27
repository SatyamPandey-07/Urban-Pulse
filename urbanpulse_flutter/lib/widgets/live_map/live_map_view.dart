import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/live_city_data.dart';
import '../../models/map_category.dart';
import '../../models/map_route.dart';
import '../../services/live_location.dart';
import '../../state/live_map_controller.dart';

/// The map itself: tiles, routes, your position, and the places on it. It draws
/// what [LiveMapController] holds and reports taps, long presses and camera
/// moves back to it.
class LiveMapView extends StatefulWidget {
  const LiveMapView({required this.controller, this.tileLayer, this.trafficLayer, this.fitPadding = const EdgeInsets.fromLTRB(40, 150, 40, 60), super.key});

  final LiveMapController controller;

  /// Replaces the network tiles (used in tests).
  final Widget? tileLayer;
  final Widget? trafficLayer;

  /// Space kept clear around the shape when the camera fits places or a route.
  final EdgeInsets fitPadding;

  @override
  State<LiveMapView> createState() => LiveMapViewState();
}

class LiveMapViewState extends State<LiveMapView> with SingleTickerProviderStateMixin {
  final MapController _map = MapController();
  late final AnimationController _anim;
  StreamSubscription<CameraRequest>? _sub;
  bool _ready = false;
  CameraRequest? _early;

  LiveMapController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 550));
    _sub = c.cameraRequests.listen(_onCamera);
  }

  @override
  void didUpdateWidget(LiveMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _sub?.cancel();
      _sub = c.cameraRequests.listen(_onCamera);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _anim.dispose();
    _map.dispose();
    super.dispose();
  }

  // --- camera -------------------------------------------------------------------

  void _onCamera(CameraRequest r) {
    if (!_ready) {
      _early = r; // the map is not built yet: do it as soon as it is
      return;
    }
    // A layout change (the bottom panel appearing) needs a frame before a fit is right.
    if (r is FitPlaces) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _apply(r);
      });
    } else {
      _apply(r);
    }
  }

  void _apply(CameraRequest r) {
    switch (r) {
      case CameraMove(:final center, :final zoom):
        _fly(center, zoom ?? _map.camera.zoom);
      case FitPlaces(:final points):
        if (points.isEmpty) return;
        if (points.length == 1) {
          _fly(points.first, math.max(_map.camera.zoom, 15));
          return;
        }
        try {
          final fitted = CameraFit.coordinates(coordinates: points, padding: widget.fitPadding, maxZoom: 17).fit(_map.camera);
          _fly(fitted.center, fitted.zoom);
        } catch (_) {
          _fly(points.first, 14);
        }
    }
  }

  void _fly(LatLng to, double zoom) {
    final from = _map.camera.center;
    final z0 = _map.camera.zoom;
    final z1 = zoom.clamp(3.0, 19.0);
    if (!to.latitude.isFinite || !to.longitude.isFinite) return;
    _anim.stop();
    // Short hops are smooth; very long ones jump the way real maps do.
    final far = const Distance().as(LengthUnit.Kilometer, from, to) > 400;
    if (far || (z0 - z1).abs() > 8) {
      _map.move(to, z1);
      return;
    }
    final curve = CurvedAnimation(parent: _anim, curve: Curves.easeInOutCubic);
    void tick() => _map.move(LatLng(from.latitude + (to.latitude - from.latitude) * curve.value, from.longitude + (to.longitude - from.longitude) * curve.value), z0 + (z1 - z0) * curve.value);
    curve.addListener(tick);
    _anim.forward(from: 0).whenCompleteOrCancel(() => curve.removeListener(tick));
  }

  void zoomBy(double delta) {
    final z = (_map.camera.zoom + delta).clamp(3.0, 19.0);
    _fly(_map.camera.center, z);
  }

  // --- build ----------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => FlutterMap(
        mapController: _map,
        options: MapOptions(
          initialCenter: c.viewCenter,
          initialZoom: c.viewZoom,
          minZoom: 3,
          maxZoom: 19,
          interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
          onMapReady: () {
            _ready = true;
            final early = _early;
            _early = null;
            if (early != null) WidgetsBinding.instance.addPostFrameCallback((_) => mounted ? _apply(early) : null);
          },
          onPointerDown: (_, _) => _anim.stop(),
          onPositionChanged: (camera, byGesture) => c.viewMoved(camera.center, camera.zoom, byUser: byGesture),
          onTap: (_, _) => c.clearSelection(),
          onLongPress: (_, at) => c.dropPin(at),
        ),
        children: [
          widget.tileLayer ?? _tiles(c.style),
          if (c.traffic) widget.trafficLayer ?? _trafficTiles(),
          ..._routeLayers(context),
          if (c.user?.accuracyM != null && (c.user!.accuracyM! > 8)) CircleLayer(circles: [CircleMarker(point: c.user!.point, radius: math.min(c.user!.accuracyM!, 400), useRadiusInMeter: true, color: const Color(0x223B82F6), borderColor: const Color(0x663B82F6), borderStrokeWidth: 1)]),
          MarkerLayer(markers: _placeMarkers(context)),
          if (c.selected != null) MarkerLayer(markers: [_selectedMarker(context, c.selected!)]),
          if (c.user != null) MarkerLayer(markers: [_userMarker(c.user!)]),
          _attribution(c.style),
        ],
      ),
    );
  }

  Widget _tiles(MapStyle s) {
    switch (s) {
      case MapStyle.standard:
        return TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.urbanpulse.app', maxNativeZoom: 19);
      case MapStyle.dark:
        return TileLayer(urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png', subdomains: const ['a', 'b', 'c', 'd'], userAgentPackageName: 'com.urbanpulse.app', maxNativeZoom: 19, retinaMode: RetinaMode.isHighDensity(context));
      case MapStyle.satellite:
        return TileLayer(urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}', userAgentPackageName: 'com.urbanpulse.app', maxNativeZoom: 18);
    }
  }

  Widget _trafficTiles() {
    final url = c.data.trafficTiles;
    if (url == null) return const SizedBox.shrink();
    return Opacity(opacity: 0.85, child: TileLayer(urlTemplate: url, userAgentPackageName: 'com.urbanpulse.app', maxNativeZoom: 18));
  }

  /// The credit the tile providers require, small enough for a phone.
  Widget _attribution(MapStyle s) => Align(
    alignment: Alignment.bottomLeft,
    child: Padding(
      padding: const EdgeInsets.all(4),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 220),
        child: DecoratedBox(
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.75), borderRadius: BorderRadius.circular(6)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Text(
              switch (s) { MapStyle.standard => '© OpenStreetMap contributors', MapStyle.dark => '© OpenStreetMap, CARTO', MapStyle.satellite => '© Esri, Maxar, Earthstar Geographics' },
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, color: Colors.black87),
            ),
          ),
        ),
      ),
    ),
  );

  // --- routes ---------------------------------------------------------------------

  List<Widget> _routeLayers(BuildContext context) {
    if (c.routes.isEmpty) return const [];
    final scheme = Theme.of(context).colorScheme;
    final chosen = c.selectedRoute;
    final others = [for (final r in c.routes) if (r.id != chosen?.id) r];
    final walking = chosen?.mode == NavMode.walk;
    return [
      PolylineLayer(
        polylines: [
          for (final r in others) Polyline(points: r.points, strokeWidth: 6, color: const Color(0xFF94A3B8).withValues(alpha: 0.85), borderStrokeWidth: 2, borderColor: Colors.white),
          if (chosen != null) ...[
            Polyline(points: chosen.points, strokeWidth: 9, color: Colors.white),
            Polyline(points: chosen.points, strokeWidth: 6, color: walking ? const Color(0xFF0EA5E9) : scheme.primary, pattern: walking ? StrokePattern.dotted(spacingFactor: 1.6) : const StrokePattern.solid()),
          ],
        ],
      ),
    ];
  }

  // --- markers ---------------------------------------------------------------------

  List<Marker> _placeMarkers(BuildContext context) {
    final sel = c.selected;
    final cat = c.category;
    final out = <Marker>[];
    var n = 0;
    for (final p in c.pins) {
      n++;
      if (n > 40) break;
      if (sel != null && sel.lat == p.lat && sel.lon == p.lon) continue; // drawn as the chosen pin
      out.add(Marker(point: LatLng(p.lat, p.lon), width: 40, height: 40, child: _PlacePin(place: p, number: cat == null ? n : null, category: cat, onTap: () => c.select(p))));
    }
    return out;
  }

  Marker _selectedMarker(BuildContext context, LivePoiResult p) {
    final scheme = Theme.of(context).colorScheme;
    return Marker(
      point: LatLng(p.lat, p.lon),
      width: 48,
      height: 56,
      alignment: Alignment.topCenter,
      child: Semantics(
        label: 'Chosen place: ${p.name}',
        child: Icon(Icons.location_on_rounded, size: 52, color: scheme.error, shadows: const [Shadow(color: Colors.black38, blurRadius: 6, offset: Offset(0, 2))]),
      ),
    );
  }

  Marker _userMarker(UserFix u) {
    return Marker(
      point: u.point,
      width: 44,
      height: 44,
      child: Semantics(
        label: 'Your position',
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (u.headingDeg != null)
              Transform.rotate(angle: u.headingDeg! * math.pi / 180, child: const Align(alignment: Alignment.topCenter, child: Icon(Icons.navigation_rounded, size: 18, color: Color(0xFF2563EB)))),
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(color: const Color(0xFF2563EB), shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3), boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 6)]),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlacePin extends StatelessWidget {
  const _PlacePin({required this.place, required this.onTap, this.number, this.category});

  final LivePoiResult place;
  final int? number;
  final MapCategory? category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = category?.color ?? Theme.of(context).colorScheme.primary;
    return Semantics(
      button: true,
      label: place.name,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2.5), boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 5, offset: Offset(0, 2))]),
            child: number != null ? Center(child: Text('$number', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800))) : Icon(category?.icon ?? Icons.place_rounded, size: 16, color: Colors.white),
          ),
        ),
      ),
    );
  }
}
