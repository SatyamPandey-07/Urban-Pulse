import 'package:flutter/material.dart';

import '../../services/live_location.dart';
import '../../services/live_map_data.dart';
import '../../services/watch/live_map_watch_bridge.dart';
import '../../state/app_scope.dart';
import '../../state/live_map_controller.dart';
import '../../widgets/live_map/live_map_view.dart';
import '../../widgets/live_map/map_overlays.dart';
import '../../widgets/live_map/map_panels.dart';

/// The Live Map: a native map with search, places by category, dropped pins,
/// real routes to a place (drive or walk), and turn-by-turn guidance that
/// follows you. Everything shown was measured or found by a service: with no
/// position or no route it says so instead of guessing.
///
/// A [controller] can be given (tests do); otherwise the tab makes its own from
/// the real services.
class LiveMapTab extends StatefulWidget {
  const LiveMapTab({this.controller, this.tileLayer, this.trafficLayer, super.key});

  final LiveMapController? controller;

  /// Replaces the network tiles (used in tests).
  final Widget? tileLayer;
  final Widget? trafficLayer;

  @override
  State<LiveMapTab> createState() => _LiveMapTabState();
}

class _LiveMapTabState extends State<LiveMapTab> {
  late final LiveMapController _c;
  late final bool _owns;
  final _view = GlobalKey<LiveMapViewState>();
  bool _styled = false;

  /// Mirrors navigation to a Garmin watch, when one is linked. Built in
  /// [didChangeDependencies] because it needs the AppScope.
  LiveMapWatchBridge? _watchBridge;

  @override
  void initState() {
    super.initState();
    _owns = widget.controller == null;
    _c = widget.controller ?? LiveMapController(data: ServiceLiveMapData(), location: const DeviceLocation());
    if (_owns) WidgetsBinding.instance.addPostFrameCallback((_) => _c.start());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Start on the dark map in a dark app, once.
    if (!_styled && _owns) {
      _styled = true;
      if (Theme.of(context).brightness == Brightness.dark) _c.setStyle(MapStyle.dark);
    }
    // The bridge is cheap and does nothing while the mirror is off or no watch is
    // linked, so it is safe to attach whenever this tab is on screen.
    if (_watchBridge == null && _owns) {
      final services = AppScope.of(context);
      _watchBridge = LiveMapWatchBridge(controller: _c, mirror: services.watch.mirror);
    }
  }

  @override
  void dispose() {
    _watchBridge?.dispose();
    if (_owns) _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.of(context).viewInsets.bottom > 0;
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) => Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(child: LiveMapView(key: _view, controller: _c, tileLayer: widget.tileLayer, trafficLayer: widget.trafficLayer)),
                Positioned(
                  top: 12,
                  left: 12,
                  right: 12,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: _c.navigating ? NavigationBanner(controller: _c) : MapSearchOverlay(controller: _c),
                    ),
                  ),
                ),
                if (!keyboard)
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: MapControls(controller: _c, onZoom: (d) => _view.currentState?.zoomBy(d), onLayers: () => showMapLayersSheet(context, _c)),
                  ),
              ],
            ),
          ),
          if (!_c.navigating && _c.selected == null && _c.category == null) LocationBanner(controller: _c),
          MapBottomPanel(controller: _c),
        ],
      ),
    );
  }
}
