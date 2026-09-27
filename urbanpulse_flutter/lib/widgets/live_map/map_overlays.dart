import 'package:flutter/material.dart';

import '../../core/formatting.dart';
import '../../models/live_city_data.dart';
import '../../models/map_category.dart';
import '../../services/live_location.dart';
import '../../state/live_map_controller.dart';

/// The search box, the category chips and the results under them.
class MapSearchOverlay extends StatefulWidget {
  const MapSearchOverlay({required this.controller, super.key});

  final LiveMapController controller;

  @override
  State<MapSearchOverlay> createState() => _MapSearchOverlayState();
}

class _MapSearchOverlayState extends State<MapSearchOverlay> {
  final _text = TextEditingController();
  final _focus = FocusNode();

  LiveMapController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.addListener(_sync);
  }

  @override
  void dispose() {
    c.removeListener(_sync);
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _sync() {
    // Choosing a category empties the box; clearing everything does too.
    if (c.category != null && _text.text.isNotEmpty) _text.clear();
    if (c.query.isEmpty && c.category == null && c.selected == null && _text.text.isNotEmpty && !_focus.hasFocus) _text.clear();
  }

  void _choose(LivePoiResult p) {
    _focus.unfocus();
    _text.text = p.name;
    c.select(p);
  }

  bool get _showList => c.selected == null && c.category == null && c.query.trim().isNotEmpty && (c.results.isNotEmpty || c.searchMessage != null);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final scheme = Theme.of(context).colorScheme;
        final active = c.selected != null || c.results.isNotEmpty || c.category != null || _text.text.isNotEmpty;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Material(
              elevation: 4,
              shadowColor: Colors.black45,
              color: scheme.surface,
              borderRadius: BorderRadius.circular(28),
              child: SizedBox(
                height: 52,
                child: Row(
                  children: [
                    IconButton(
                      tooltip: active ? 'Back' : 'Search',
                      onPressed: active
                          ? () {
                              _focus.unfocus();
                              _text.clear();
                              c.clearSelection();
                              c.clearResults();
                            }
                          : () => _focus.requestFocus(),
                      icon: Icon(active ? Icons.arrow_back_rounded : Icons.search_rounded),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _text,
                        focusNode: _focus,
                        textInputAction: TextInputAction.search,
                        onChanged: (v) {
                          if (c.selected != null) c.clearSelection();
                          c.queryChanged(v);
                        },
                        onSubmitted: (v) => c.search(v),
                        style: const TextStyle(fontSize: 15),
                        decoration: const InputDecoration(hintText: 'Search places or addresses', border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none, filled: false, isDense: true, contentPadding: EdgeInsets.zero),
                      ),
                    ),
                    if (c.searching)
                      const Padding(padding: EdgeInsets.symmetric(horizontal: 14), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                    else if (_text.text.isNotEmpty)
                      IconButton(
                        tooltip: 'Clear',
                        onPressed: () {
                          _text.clear();
                          c.clearSelection();
                          c.clearResults();
                          _focus.requestFocus();
                        },
                        icon: const Icon(Icons.close_rounded, size: 20),
                      )
                    else
                      const SizedBox(width: 8),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: MapCategory.values.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final cat = MapCategory.values[i];
                  final on = c.category == cat;
                  return Material(
                    elevation: 2,
                    shadowColor: Colors.black38,
                    color: on ? cat.color : scheme.surface,
                    borderRadius: BorderRadius.circular(20),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () {
                        _focus.unfocus();
                        c.toggleCategory(cat);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(cat.icon, size: 18, color: on ? Colors.white : cat.color),
                            const SizedBox(width: 6),
                            Text(cat.label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: on ? Colors.white : scheme.onSurface)),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (c.searchAreaOffered) ...[
              const SizedBox(height: 8),
              Center(
                child: ActionChip(
                  avatar: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Search this area'),
                  backgroundColor: scheme.surface,
                  elevation: 3,
                  onPressed: c.searchThisArea,
                ),
              ),
            ],
            if (_showList) ...[
              const SizedBox(height: 8),
              Material(
                elevation: 4,
                shadowColor: Colors.black45,
                color: scheme.surface,
                borderRadius: BorderRadius.circular(20),
                clipBehavior: Clip.antiAlias,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 300),
                  child: c.results.isEmpty
                      ? Padding(padding: const EdgeInsets.all(16), child: Text(c.searchMessage ?? '', style: Theme.of(context).textTheme.bodyMedium))
                      : ListView.separated(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          itemCount: c.results.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, i) => _ResultTile(place: c.results[i], number: i + 1, onTap: () => _choose(c.results[i])),
                        ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.place, required this.number, required this.onTap});

  final LivePoiResult place;
  final int number;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      onTap: onTap,
      leading: CircleAvatar(radius: 14, backgroundColor: scheme.primary, child: Text('$number', style: TextStyle(color: scheme.onPrimary, fontSize: 12, fontWeight: FontWeight.w800))),
      title: Text(place.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: place.address.isEmpty ? null : Text(place.address, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Text(distanceLabel(place.distanceMeters), style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w700, fontSize: 12)),
    );
  }
}

/// Layers, zoom and "my location", down the right-hand side of the map.
class MapControls extends StatelessWidget {
  const MapControls({required this.controller, required this.onZoom, required this.onLayers, super.key});

  final LiveMapController controller;
  final void Function(double delta) onZoom;
  final VoidCallback onLayers;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        final located = c.hasFix;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _RoundButton(icon: Icons.layers_rounded, tooltip: 'Map layers', onTap: onLayers),
            const SizedBox(height: 10),
            _RoundButton(icon: Icons.add_rounded, tooltip: 'Zoom in', onTap: () => onZoom(1)),
            const SizedBox(height: 2),
            _RoundButton(icon: Icons.remove_rounded, tooltip: 'Zoom out', onTap: () => onZoom(-1)),
            const SizedBox(height: 10),
            _RoundButton(
              icon: located ? Icons.my_location_rounded : Icons.location_searching_rounded,
              tooltip: located ? 'My location' : 'Find my location',
              busy: c.locating,
              highlight: c.navigating && !c.following,
              onTap: c.recenter,
            ),
          ],
        );
      },
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.tooltip, required this.onTap, this.busy = false, this.highlight = false});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool busy;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: Material(
          elevation: 3,
          shadowColor: Colors.black45,
          color: highlight ? scheme.primary : scheme.surface,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 44,
              height: 44,
              child: busy ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2.5)) : Icon(icon, size: 22, color: highlight ? scheme.onPrimary : scheme.onSurface),
            ),
          ),
        ),
      ),
    );
  }
}

/// Map style and the traffic overlay.
Future<void> showMapLayersSheet(BuildContext context, LiveMapController c) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (context) => ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final scheme = Theme.of(context).colorScheme;
        Widget style(MapStyle s, String label, IconData icon) {
          final on = c.style == s;
          return Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => c.setStyle(s),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: on ? scheme.primary : scheme.outlineVariant, width: on ? 2 : 1), color: on ? scheme.primaryContainer.withValues(alpha: 0.4) : null),
                child: Column(children: [Icon(icon, color: on ? scheme.primary : scheme.onSurfaceVariant), const SizedBox(height: 6), Text(label, style: TextStyle(fontWeight: on ? FontWeight.w800 : FontWeight.w600))]),
              ),
            ),
          );
        }

        final hasTraffic = c.data.trafficTiles != null;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Map type', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                Row(children: [style(MapStyle.standard, 'Standard', Icons.map_rounded), const SizedBox(width: 10), style(MapStyle.dark, 'Dark', Icons.dark_mode_rounded), const SizedBox(width: 10), style(MapStyle.satellite, 'Satellite', Icons.satellite_alt_rounded)]),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Live traffic', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(hasTraffic ? 'Green is free-flowing, red is slow.' : 'Needs a TomTom key in the app settings.'),
                  value: c.traffic,
                  onChanged: hasTraffic ? c.setTraffic : null,
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

/// Shown when the map does not know where you are, and why.
class LocationBanner extends StatelessWidget {
  const LocationBanner({required this.controller, super.key});

  final LiveMapController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        if (c.hasFix || c.locating || c.locationStatus == LocationStatus.unknown || c.locationStatus == LocationStatus.ok) return const SizedBox.shrink();
        final (text, action) = switch (c.locationStatus) {
          LocationStatus.serviceOff => ('Location is switched off, so the map cannot show where you are.', 'Turn on'),
          LocationStatus.denied => ('Allow location to see where you are and to get directions.', 'Allow'),
          LocationStatus.deniedForever => ('Location is blocked for this app. Allow it in settings to see where you are.', 'Settings'),
          _ => ('Your position is not available yet.', 'Try again'),
        };
        final scheme = Theme.of(context).colorScheme;
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Material(
            elevation: 4,
            color: scheme.surface,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
              child: Row(
                children: [
                  Icon(Icons.location_off_rounded, color: scheme.error),
                  const SizedBox(width: 10),
                  Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
                  TextButton(
                    onPressed: () => c.locationStatus == LocationStatus.denied || c.locationStatus == LocationStatus.unavailable ? c.locate() : c.openLocationSettings(),
                    child: Text(action),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
