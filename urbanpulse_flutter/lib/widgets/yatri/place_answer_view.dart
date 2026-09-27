import 'package:flutter/material.dart';

import '../../models/saved_place.dart';
import '../../models/yatri_question.dart';
import '../../state/app_scope.dart';
import '../../state/place_search_controller.dart';
import 'choice_answers.dart';

/// Where the trip starts, answered the way delivery apps ask for an address:
/// your current location, one of your saved addresses, or type it and pick from
/// the completions. Answers with the city, so the rest of the flow is unchanged.
class PlaceAnswerView extends StatefulWidget {
  const PlaceAnswerView({required this.question, required this.onSubmit, this.embedded = false, this.onChanged, super.key});

  final YatriQuestion question;
  final AnswerSubmit onSubmit;
  final bool embedded;
  final AnswerChanged? onChanged;

  @override
  State<PlaceAnswerView> createState() => _PlaceAnswerViewState();
}

class _PlaceAnswerViewState extends State<PlaceAnswerView> {
  final _text = TextEditingController();
  PlaceSearchController? _search;
  AppServices? _services;
  bool _resolving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_search != null) return;
    // Without the app's services (a bare preview) only typing works.
    _services = context.getInheritedWidgetOfExactType<AppScope>()?.services;
    final s = _services;
    if (s != null) _search = PlaceSearchController(s.placeSuggestions, nearLat: s.location.gpsLatitude, nearLon: s.location.gpsLongitude);
  }

  @override
  void dispose() {
    _search?.dispose();
    _text.dispose();
    super.dispose();
  }

  void _answer(String city, String label) {
    final a = ChoiceAnswer(city, label);
    if (widget.embedded) {
      widget.onChanged?.call(a);
    } else {
      widget.onSubmit(a);
    }
  }

  Future<void> _pick(PlaceSuggestion sug) async {
    final s = _services;
    if (s == null || _resolving) return;
    setState(() => _resolving = true);
    final city = await s.placeSuggestions.cityOf(sug.lat, sug.lon) ?? sug.title;
    if (!mounted) return;
    setState(() => _resolving = false);
    _answer(city, sug.subtitle.isEmpty ? city : '${sug.title}, $city');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = _services;
    final detected = [for (final o in widget.question.options) if (o.recommended) o].firstOrNull;
    final saved = s?.savedPlaces.places ?? const <SavedPlace>[];
    final search = _search;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (detected != null) ActionChip(avatar: const Icon(Icons.my_location_rounded, size: 18), label: Text('Current location: ${detected.id}'), onPressed: () => _answer(detected.id, detected.id)),
            for (final p in saved.where((p) => p.city.isNotEmpty))
              ActionChip(
                avatar: Icon(switch (p.kind) { PlaceKind.home => Icons.home_rounded, PlaceKind.work => Icons.work_rounded, PlaceKind.other => Icons.place_rounded }, size: 18),
                label: Text('${p.label} · ${p.city}'),
                onPressed: () => _answer(p.city, '${p.label} (${p.city})'),
              ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _text,
          textInputAction: TextInputAction.done,
          onChanged: (v) {
            search?.changed(v);
            setState(() {});
          },
          onSubmitted: (v) {
            final t = v.trim();
            if (t.length >= 2) _answer(t, t);
          },
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search_rounded),
            hintText: 'Type your city, area or address',
            isDense: true,
            suffixIcon: _resolving || (search?.searching ?? false) ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))) : null,
          ),
        ),
        if (search != null)
          ListenableBuilder(
            listenable: search,
            builder: (context, _) {
              final typed = _text.text.trim();
              if (typed.length < 2) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final sug in search.suggestions.take(5))
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.location_on_outlined, color: scheme.primary),
                      title: Text(sug.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: sug.subtitle.isEmpty ? null : Text(sug.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () => _pick(sug),
                    ),
                  if (search.noMatches) Padding(padding: const EdgeInsets.only(top: 6), child: Text('No matches. You can still use what you typed.', style: theme.textTheme.bodySmall)),
                ],
              );
            },
          ),
        if (_text.text.trim().length >= 2)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(onPressed: () => _answer(_text.text.trim(), _text.text.trim()), icon: const Icon(Icons.check_rounded, size: 18), label: Text('Use “${_text.text.trim()}”')),
          ),
      ],
    );
  }
}
