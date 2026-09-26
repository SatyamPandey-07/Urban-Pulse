import 'package:latlong2/latlong.dart';

import '../../services/data/forecast_client.dart';
import 'itinerary_parts.dart';

/// One change the traveller asked for after the plan was made.
class EditRecord {
  const EditRecord({required this.at, required this.request, required this.summary});

  final DateTime at;

  /// What the traveller asked, in their own words (capped).
  final String request;

  /// What Yatri did about it, in one line.
  final String summary;

  Map<String, dynamic> toJson() => {'at': at.toIso8601String(), 'request': request, 'summary': summary};

  static EditRecord fromJson(Map<String, dynamic> j) => EditRecord(
    at: DateTime.tryParse(j['at'] as String? ?? '') ?? DateTime.now(),
    request: j['request'] as String? ?? '',
    summary: j['summary'] as String? ?? '',
  );
}

/// What a finished itinerary must remember so it can be re-planned later:
/// every place the planner ranked (not only the ones on the days), the weather,
/// where things are, and the edits the traveller has already made (rest days,
/// locked stops). Kept small: the pool is capped and trimmed.
class PlanSnapshot {
  const PlanSnapshot({
    this.pool = const [],
    this.weather = const {},
    this.center,
    this.origin,
    this.bannedOutdoor = const {},
    this.droppedIds = const {},
    this.pins = const {},
    this.dayWindows = const {},
    this.dayStopCaps = const {},
  });

  /// Every ranked place: those on the days and the spares.
  final List<Hotspot> pool;

  /// ISO date -> weather for the trip's dates.
  final Map<String, DayForecast> weather;
  final LatLng? center;
  final LatLng? origin;

  /// Dates with no outdoor plans (the traveller asked).
  final Set<String> bannedOutdoor;

  /// Places the plan must not use again.
  final Set<String> droppedIds;

  /// Places the traveller locked: they stay on their day.
  final Set<String> pins;

  /// Shorter days (1-based day to start/end minutes), e.g. a rest day.
  final Map<int, (int, int)> dayWindows;

  /// The most places on a given day (1-based day).
  final Map<int, int> dayStopCaps;

  static const maxPool = 60;

  PlanSnapshot copyWith({
    List<Hotspot>? pool,
    Map<String, DayForecast>? weather,
    Set<String>? bannedOutdoor,
    Set<String>? droppedIds,
    Set<String>? pins,
    Map<int, (int, int)>? dayWindows,
    Map<int, int>? dayStopCaps,
  }) => PlanSnapshot(
    pool: pool ?? this.pool,
    weather: weather ?? this.weather,
    center: center,
    origin: origin,
    bannedOutdoor: bannedOutdoor ?? this.bannedOutdoor,
    droppedIds: droppedIds ?? this.droppedIds,
    pins: pins ?? this.pins,
    dayWindows: dayWindows ?? this.dayWindows,
    dayStopCaps: dayStopCaps ?? this.dayStopCaps,
  );

  Map<String, dynamic> toJson() => {
    'pool': [for (final h in pool.take(maxPool)) h.toJson()],
    'weather': {for (final e in weather.entries) e.key: e.value.toJson()},
    'center': latLngToJson(center),
    'origin': latLngToJson(origin),
    'bannedOutdoor': bannedOutdoor.toList(),
    'droppedIds': droppedIds.toList(),
    'pins': pins.toList(),
    'dayWindows': {for (final e in dayWindows.entries) '${e.key}': [e.value.$1, e.value.$2]},
    'dayStopCaps': {for (final e in dayStopCaps.entries) '${e.key}': e.value},
  };

  static PlanSnapshot fromJson(Map<String, dynamic> j) {
    Set<String> strings(String k) => {for (final v in (j[k] as List<dynamic>? ?? const [])) '$v'};
    final windows = <int, (int, int)>{};
    final w = j['dayWindows'];
    if (w is Map<String, dynamic>) {
      for (final e in w.entries) {
        final day = int.tryParse(e.key);
        final v = e.value;
        if (day != null && v is List && v.length == 2 && v[0] is num && v[1] is num) {
          windows[day] = ((v[0] as num).toInt(), (v[1] as num).toInt());
        }
      }
    }
    final caps = <int, int>{};
    final c = j['dayStopCaps'];
    if (c is Map<String, dynamic>) {
      for (final e in c.entries) {
        final day = int.tryParse(e.key);
        if (day != null && e.value is num) caps[day] = (e.value as num).toInt();
      }
    }
    return PlanSnapshot(
      pool: [
        for (final h in (j['pool'] as List<dynamic>? ?? const []))
          if (h is Map<String, dynamic>) Hotspot.fromJson(h),
      ],
      weather: {
        if (j['weather'] is Map<String, dynamic>)
          for (final e in (j['weather'] as Map<String, dynamic>).entries)
            if (e.value is Map<String, dynamic>) e.key: DayForecast.fromJson(e.value as Map<String, dynamic>),
      },
      center: latLngFromJson(j['center']),
      origin: latLngFromJson(j['origin']),
      bannedOutdoor: strings('bannedOutdoor'),
      droppedIds: strings('droppedIds'),
      pins: strings('pins'),
      dayWindows: windows,
      dayStopCaps: caps,
    );
  }
}
