import 'package:flutter/material.dart';

import '../../services/live_location.dart';
import '../../services/live_map_data.dart';
import '../../state/app_scope.dart';
import '../../state/live_map_controller.dart';
import '../../state/map_requests.dart';
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

  @override
  void initState() {
    super.initState();
    _owns = widget.controller == null;
    // The app's voice reads directions aloud (absent in a bare preview).
    final voice = context.getInheritedWidgetOfExactType<AppScope>()?.services.voice;
    _c = widget.controller ?? LiveMapController(data: ServiceLiveMapData(), location: const DeviceLocation(), speak: voice == null ? null : (t) => voice.say(t));
    if (_owns) WidgetsBinding.instance.addPostFrameCallback((_) => _c.start());
    _requests = context.getInheritedWidgetOfExactType<AppScope>()?.services.mapRequests;
    _requests?.addListener(_onRequest);
    if (_requests?.pending != null) WidgetsBinding.instance.addPostFrameCallback((_) => _onRequest());
  }

  MapRequests? _requests;

  /// A day of the trip to show, sent from the itinerary screen.
  void _onRequest() {
    final r = _requests?.take();
    if (r != null && mounted) _c.showTrip(r);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Start on the dark map in a dark app, once.
    if (!_styled && _owns) {
      _styled = true;
      if (Theme.of(context).brightness == Brightness.dark) _c.setStyle(MapStyle.dark);
    }
  }

  @override
  void dispose() {
    _requests?.removeListener(_onRequest);
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
