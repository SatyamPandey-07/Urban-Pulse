import 'package:flutter/material.dart';

import '../models/saved_place.dart';
import '../state/app_scope.dart';
import '../state/place_search_controller.dart';
import '../widgets/common.dart';

/// Where the app works from: the device's position, or one of the saved
/// addresses (Home, Work, others), or a new place found by searching.
class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const LocationPickerScreen()));

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  final _text = TextEditingController();
  PlaceSearchController? _search;

  /// Set when the person tapped "Add Home" or "Add Work".
  PlaceKind? _adding;

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

  Future<void> _useCurrent() async {
    final s = AppScope.of(context);
    await s.location.useCurrentLocation();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _useSaved(SavedPlace p) async {
    await AppScope.of(context).location.useSavedPlace(p);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _pick(PlaceSuggestion sug) async {
    final choice = await showModalBottomSheet<_SaveChoice>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _SaveSheet(suggestion: sug, initial: _adding ?? PlaceKind.other),
    );
    if (choice == null || !mounted) return;
    final s = AppScope.of(context);
    final city = await s.placeSuggestions.cityOf(sug.lat, sug.lon) ?? sug.title;
    final saved = await s.savedPlaces.save(kind: choice.kind, label: choice.label, address: sug.line, city: city, lat: sug.lat, lon: sug.lon);
    if (!mounted) return;
    if (saved == null) {
      showToast(context, 'You can keep up to ${12} addresses. Remove one first.');
      return;
    }
    await s.location.useSavedPlace(saved);
    if (mounted) Navigator.of(context).pop();
  }

  void _startAdding(PlaceKind kind) {
    setState(() => _adding = kind);
    _text.clear();
    _search!.clear();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(_adding == null ? 'Select location' : 'Add ${_adding == PlaceKind.home ? 'Home' : 'Work'} address')),
      body: ListenableBuilder(
        listenable: Listenable.merge([_search!, s.savedPlaces, s.location]),
        builder: (context, _) {
          final search = _search!;
          final searching = search.query.trim().length >= 2;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              TextField(
                controller: _text,
                onChanged: search.changed,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded),
                  hintText: 'Search for an area, street or landmark',
                  suffixIcon: search.searching
                      ? const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                      : (_text.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear',
                                icon: const Icon(Icons.close_rounded),
                                onPressed: () {
                                  _text.clear();
                                  search.clear();
                                },
                              )),
                ),
              ),
              const SizedBox(height: 8),
              if (searching) ...[
                if (search.noMatches) Padding(padding: const EdgeInsets.all(16), child: Text('No places matched. Try a nearby landmark or the area name.', style: theme.textTheme.bodyMedium)),
                for (final sug in search.suggestions)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.location_on_outlined),
                    title: Text(sug.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: sug.subtitle.isEmpty ? null : Text(sug.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
                    onTap: () => _pick(sug),
                  ),
              ] else ...[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.my_location_rounded, color: theme.colorScheme.primary),
                  title: Text('Use my current location', style: TextStyle(fontWeight: FontWeight.w800, color: theme.colorScheme.primary)),
                  subtitle: Text(s.location.gpsCity == null ? (s.location.isResolving ? 'Locating…' : 'Tap to find where you are') : s.location.gpsCity!),
                  trailing: s.location.usingSavedPlace ? null : Icon(Icons.check_circle_rounded, color: theme.colorScheme.primary),
                  onTap: _useCurrent,
                ),
                const Divider(),
                Padding(padding: const EdgeInsets.only(top: 8, bottom: 4), child: Text('Saved addresses', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
                _slot(context, PlaceKind.home, s.savedPlaces.home, s),
                _slot(context, PlaceKind.work, s.savedPlaces.work, s),
                for (final p in s.savedPlaces.others) _tile(context, p, s),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.add_location_alt_outlined),
                  title: const Text('Add a new address', style: TextStyle(fontWeight: FontWeight.w700)),
                  onTap: () => _startAdding(PlaceKind.other),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _slot(BuildContext context, PlaceKind kind, SavedPlace? place, AppServices s) {
    if (place != null) return _tile(context, place, s);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(kind == PlaceKind.home ? Icons.home_outlined : Icons.work_outline_rounded),
      title: Text('Add ${kind.label}', style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: const Text('Search and save it once'),
      onTap: () => _startAdding(kind),
    );
  }

  Widget _tile(BuildContext context, SavedPlace p, AppServices s) {
    final active = s.savedPlaces.active?.id == p.id;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(switch (p.kind) { PlaceKind.home => Icons.home_rounded, PlaceKind.work => Icons.work_rounded, PlaceKind.other => Icons.place_rounded }),
      title: Text(p.label, style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text(p.address.isEmpty ? p.city : p.address, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (active) Icon(Icons.check_circle_rounded, color: Theme.of(context).colorScheme.primary),
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (v) async {
              if (v == 'delete') {
                await s.savedPlaces.remove(p.id);
              } else if (v == 'change') {
                _startAdding(p.kind);
              }
            },
            itemBuilder: (_) => [
              if (p.kind != PlaceKind.other) const PopupMenuItem(value: 'change', child: Text('Change address')),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
      onTap: () => _useSaved(p),
    );
  }
}

class _SaveChoice {
  const _SaveChoice(this.kind, this.label);

  final PlaceKind kind;
  final String label;
}

/// "Save this address as": Home, Work, or a name of your own.
class _SaveSheet extends StatefulWidget {
  const _SaveSheet({required this.suggestion, required this.initial});

  final PlaceSuggestion suggestion;
  final PlaceKind initial;

  @override
  State<_SaveSheet> createState() => _SaveSheetState();
}

class _SaveSheetState extends State<_SaveSheet> {
  late PlaceKind _kind = widget.initial;
  late final _name = TextEditingController(text: widget.initial == PlaceKind.other ? '' : '');

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.suggestion.title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          if (widget.suggestion.subtitle.isNotEmpty) Text(widget.suggestion.subtitle, style: theme.textTheme.bodySmall),
          const SizedBox(height: 14),
          Text('Save as', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final k in PlaceKind.values)
                ChoiceChip(
                  label: Text(k.label),
                  avatar: Icon(switch (k) { PlaceKind.home => Icons.home_rounded, PlaceKind.work => Icons.work_rounded, PlaceKind.other => Icons.place_rounded }, size: 18),
                  selected: _kind == k,
                  onSelected: (_) => setState(() => _kind = k),
                ),
            ],
          ),
          if (_kind == PlaceKind.other) ...[
            const SizedBox(height: 12),
            TextField(controller: _name, maxLength: 24, decoration: const InputDecoration(labelText: 'Name (for example Mom\'s flat)', counterText: '')),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton(onPressed: () => Navigator.of(context).pop(_SaveChoice(_kind, _name.text)), child: const Text('Save and use this address')),
          ),
        ],
      ),
    );
  }
}
