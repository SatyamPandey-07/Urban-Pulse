import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../models/saved_place.dart';
import '../state/app_scope.dart';
import '../state/place_search_controller.dart';

/// A place chosen for a tool to work on: what to call it, the city (what the
/// tools search by), and where it is.
class ToolPlace {
  const ToolPlace({required this.label, required this.city, required this.point});

  final String label;
  final String city;
  final LatLng point;
}

/// Asks where a tool should work: your current location, one of your saved
/// addresses, or a place you type (with completions). Used only for that tool;
/// it does not change where the rest of the app works from.
Future<ToolPlace?> chooseToolPlace(BuildContext context, {String title = 'Where should I look?'}) {
  return showModalBottomSheet<ToolPlace>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) => _ToolPlaceSheet(title: title),
  );
}

class _ToolPlaceSheet extends StatefulWidget {
  const _ToolPlaceSheet({required this.title});

  final String title;

  @override
  State<_ToolPlaceSheet> createState() => _ToolPlaceSheetState();
}

class _ToolPlaceSheetState extends State<_ToolPlaceSheet> {
  final _text = TextEditingController();
  PlaceSearchController? _search;
  bool _working = false;
  String? _message;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_search != null) return;
    final s = AppScope.of(context);
    _search = PlaceSearchController(s.placeSuggestions, nearLat: s.location.gpsLatitude, nearLon: s.location.gpsLongitude);
  }

  @override
  void dispose() {
    _search?.dispose();
    _text.dispose();
    super.dispose();
  }

  Future<void> _current() async {
    final s = AppScope.of(context);
    setState(() {
      _working = true;
      _message = null;
    });
    if (s.location.gpsLatitude == null) await s.location.resolve(force: true);
    if (!mounted) return;
    final lat = s.location.gpsLatitude, lon = s.location.gpsLongitude;
    if (lat == null || lon == null) {
      setState(() {
        _working = false;
        _message = 'I cannot see your location. Turn on location, or choose a place below.';
      });
      return;
    }
    final city = s.location.gpsCity ?? await s.placeSuggestions.cityOf(lat, lon) ?? 'Your location';
    if (mounted) Navigator.of(context).pop(ToolPlace(label: 'Current location · $city', city: city, point: LatLng(lat, lon)));
  }

  void _saved(SavedPlace p) => Navigator.of(context).pop(ToolPlace(label: '${p.label} · ${p.city}', city: p.city.isEmpty ? p.label : p.city, point: LatLng(p.lat, p.lon)));

  Future<void> _suggestion(PlaceSuggestion sug) async {
    final s = AppScope.of(context);
    setState(() => _working = true);
    final city = await s.placeSuggestions.cityOf(sug.lat, sug.lon) ?? sug.title;
    if (mounted) Navigator.of(context).pop(ToolPlace(label: sug.title, city: city, point: LatLng(sug.lat, sug.lon)));
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: ListenableBuilder(
        listenable: _search!,
        builder: (context, _) {
          final search = _search!;
          final typing = search.query.trim().length >= 2;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              TextField(
                controller: _text,
                onChanged: search.changed,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded),
                  hintText: 'Search for a city, area or landmark',
                  isDense: true,
                  suffixIcon: search.searching || _working ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))) : null,
                ),
              ),
              if (_message != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_message!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error))),
              const SizedBox(height: 6),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    if (typing) ...[
                      if (search.noMatches) const Padding(padding: EdgeInsets.all(12), child: Text('No places matched. Try the city name.')),
                      for (final sug in search.suggestions)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.location_on_outlined),
                          title: Text(sug.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: sug.subtitle.isEmpty ? null : Text(sug.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                          onTap: _working ? null : () => _suggestion(sug),
                        ),
                    ] else ...[
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.my_location_rounded, color: theme.colorScheme.primary),
                        title: Text('Current location', style: TextStyle(fontWeight: FontWeight.w800, color: theme.colorScheme.primary)),
                        subtitle: Text(s.location.gpsCity ?? 'Use where I am now'),
                        onTap: _working ? null : _current,
                      ),
                      for (final p in s.savedPlaces.places)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(switch (p.kind) { PlaceKind.home => Icons.home_rounded, PlaceKind.work => Icons.work_rounded, PlaceKind.other => Icons.place_rounded }),
                          title: Text(p.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(p.address.isEmpty ? p.city : p.address, maxLines: 1, overflow: TextOverflow.ellipsis),
                          onTap: () => _saved(p),
                        ),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
