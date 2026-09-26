/// A forgiving reader for OpenStreetMap-style `opening_hours` text
/// (`Mo-Sa 09:00-17:00; Su off`, `24/7`, `09:00-13:00,14:00-18:00`).
///
/// It understands the common shapes and nothing else. Anything it cannot read
/// (`sunrise-sunset`, public-holiday rules, month ranges) yields "unknown",
/// which callers treat as "may be open": unreadable hours must never cause a
/// place to be dropped.
class OpeningHours {
  const OpeningHours._(this._byDay, {this.alwaysOpen = false, this.readable = true});

  /// Weekday (1 = Monday … 7 = Sunday) -> open ranges in minutes since midnight.
  final Map<int, List<(int, int)>> _byDay;
  final bool alwaysOpen;
  final bool readable;

  static const unknown = OpeningHours._({}, readable: false);
  static const open24h = OpeningHours._({}, alwaysOpen: true);

  static const _days = {'mo': 1, 'tu': 2, 'we': 3, 'th': 4, 'fr': 5, 'sa': 6, 'su': 7};

  /// Parses [text]; returns [unknown] when it cannot be understood.
  static OpeningHours parse(String? text) {
    final raw = text?.trim();
    if (raw == null || raw.isEmpty) return unknown;
    final lower = raw.toLowerCase();
    if (lower == '24/7') return open24h;

    final byDay = <int, List<(int, int)>>{};
    var understood = false;
    for (final ruleRaw in lower.split(';')) {
      final rule = ruleRaw.trim();
      if (rule.isEmpty) continue;
      final parsed = _parseRule(rule);
      if (parsed == null) return unknown;
      understood = true;
      final (days, ranges) = parsed;
      for (final d in days) {
        // A later rule for the same day replaces an earlier one (OSM semantics).
        byDay[d] = ranges;
      }
    }
    if (!understood) return unknown;
    return OpeningHours._(byDay);
  }

  static (List<int>, List<(int, int)>)? _parseRule(String rule) {
    // Split "<days> <times>" where days may be absent (applies to every day).
    final m = RegExp(r'^([a-z ,\-]+?)?\s*((?:\d{1,2}:\d{2}\s*-\s*\d{1,2}:\d{2}\s*,?\s*)+|off|closed|24/7)$').firstMatch(rule);
    if (m == null) return null;
    final dayPart = (m.group(1) ?? '').trim();
    final timePart = m.group(2)!.trim();

    final days = dayPart.isEmpty ? [1, 2, 3, 4, 5, 6, 7] : _parseDays(dayPart);
    if (days == null) return null;

    if (timePart == 'off' || timePart == 'closed') return (days, const []);
    if (timePart == '24/7') return (days, const [(0, 1440)]);

    final ranges = <(int, int)>[];
    for (final r in timePart.split(',')) {
      final t = RegExp(r'(\d{1,2}):(\d{2})\s*-\s*(\d{1,2}):(\d{2})').firstMatch(r.trim());
      if (t == null) continue;
      final a = int.parse(t.group(1)!) * 60 + int.parse(t.group(2)!);
      var b = int.parse(t.group(3)!) * 60 + int.parse(t.group(4)!);
      if (b <= a) b += 1440; // past midnight
      ranges.add((a, b.clamp(0, 2880)));
    }
    if (ranges.isEmpty) return null;
    return (days, ranges);
  }

  static List<int>? _parseDays(String part) {
    final out = <int>{};
    for (final piece in part.split(',')) {
      final p = piece.trim();
      if (p.isEmpty) continue;
      if (p.contains('-')) {
        final ends = p.split('-').map((s) => _days[s.trim()]).toList();
        if (ends.length != 2 || ends[0] == null || ends[1] == null) return null;
        var d = ends[0]!;
        for (var i = 0; i < 7; i++) {
          out.add(d);
          if (d == ends[1]) break;
          d = d % 7 + 1;
        }
      } else {
        final d = _days[p];
        if (d == null) return null;
        out.add(d);
      }
    }
    if (out.isEmpty) return null;
    return out.toList()..sort();
  }

  /// Open ranges (minutes since midnight) on [weekday], or null if unknown.
  List<(int, int)>? rangesOn(int weekday) {
    if (!readable) return null;
    if (alwaysOpen) return const [(0, 1440)];
    // OSM semantics: a day the text does not mention is a closed day.
    return _byDay[weekday] ?? const [];
  }

  /// Whether the place is open for the whole of [startMin, startMin+durationMin]
  /// on [weekday]. Null means unknown.
  bool? isOpenFor(int weekday, int startMin, int durationMin) {
    final r = rangesOn(weekday);
    if (r == null) return null;
    final end = startMin + durationMin;
    for (final (a, b) in r) {
      if (startMin >= a && end <= b) return true;
    }
    return false;
  }

  /// The earliest time (minutes) at or after [fromMin] that a visit of
  /// [durationMin] fits, on [weekday]; null if it never fits that day.
  int? nextSlot(int weekday, int fromMin, int durationMin) {
    final r = rangesOn(weekday);
    if (r == null) return fromMin; // unknown: any time
    for (final (a, b) in r) {
      final start = fromMin > a ? fromMin : a;
      if (start + durationMin <= b) return start;
    }
    return null;
  }

  /// Whether it is closed all day on [weekday].
  bool closedAllDay(int weekday) {
    final r = rangesOn(weekday);
    return r != null && r.isEmpty;
  }
}
