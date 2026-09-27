import '../../models/trip_brief.dart';
import 'edit_ops.dart';

/// A stop reference that could mean several stops: the traveller is asked.
class Ambiguity {
  const Ambiguity({required this.ref, required this.candidates, required this.build});

  final String ref;
  final List<IndexedStop> candidates;

  /// Makes the operation once the traveller has picked the stop.
  final EditOp Function(String placeId) build;
}

/// What a request turned into, before anything is changed.
class ParsedEdit {
  const ParsedEdit({this.ops = const [], this.problems = const [], this.ambiguities = const [], this.say, this.clarify});

  final List<EditOp> ops;

  /// Things that could not be understood or found, in plain words.
  final List<String> problems;
  final List<Ambiguity> ambiguities;

  /// The model's friendly one-liner.
  final String? say;

  /// A question for the traveller when the request is unclear.
  final String? clarify;

  bool get isEmpty => ops.isEmpty && ambiguities.isEmpty;
}

/// Turns the model's JSON (or a rule-parsed request) into validated
/// [EditOp]s. Strict on purpose: unknown operations, out-of-range days, unknown
/// stops and over-long text are dropped with a note rather than trusted, and at
/// most [maxOps] operations are taken from one request.
abstract final class EditParser {
  static const maxOps = 5;
  static const maxText = 200;

  static ParsedEdit fromModel(Object? json, PlanIndex index) {
    final root = json is Map<String, dynamic> ? json : null;
    if (root == null) return const ParsedEdit(problems: ['The reply could not be read.']);
    final rawOps = root['ops'];
    final ops = <EditOp>[];
    final problems = <String>[];
    final ambiguities = <Ambiguity>[];

    if (rawOps is List) {
      for (final raw in rawOps.take(maxOps)) {
        if (raw is! Map<String, dynamic>) continue;
        _one(raw, index, ops, problems, ambiguities);
      }
      if (rawOps.length > maxOps) problems.add('Only the first $maxOps changes were taken; ask for the rest next.');
    }
    return ParsedEdit(
      ops: ops,
      problems: problems,
      ambiguities: ambiguities,
      say: _text(root['say']),
      clarify: _text(root['clarify']),
    );
  }

  static String? _text(Object? v) {
    if (v is! String) return null;
    final t = v.replaceAll(RegExp(r'[\u0000-\u001F\u007F]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.isEmpty) return null;
    return t.length <= 300 ? t : '${t.substring(0, 299)}…';
  }

  static int? _day(Object? v, PlanIndex index) {
    final d = v is num ? v.toInt() : int.tryParse('$v');
    if (d == null || d < 1 || d > index.dayCount) return null;
    return d;
  }

  static void _one(Map<String, dynamic> raw, PlanIndex index, List<EditOp> ops, List<String> problems, List<Ambiguity> amb) {
    final op = '${raw['op']}';

    /// Resolves a stop reference to one id, or records why not.
    String? stop(Object? ref, EditOp Function(String id) make, {int? dayHint}) {
      final r = _text(ref);
      if (r == null) {
        problems.add('A change did not say which stop.');
        return null;
      }
      final found = index.resolve(r, dayHint: dayHint);
      if (found.isEmpty) {
        problems.add('“${r.length > 40 ? '${r.substring(0, 40)}…' : r}” is not in your plan.');
        return null;
      }
      if (found.length > 1 && index.byId(r) == null) {
        final best = found.first;
        final second = found[1];
        final clear = index.resolve(r).length == 1 || (best.name.toLowerCase() == r.toLowerCase() && second.name.toLowerCase() != r.toLowerCase());
        if (!clear) {
          amb.add(Ambiguity(ref: r, candidates: found.take(4).toList(), build: make));
          return null;
        }
      }
      return found.first.id;
    }

    switch (op) {
      case 'restDay':
        final day = _day(raw['day'], index);
        if (day == null) {
          problems.add('That day is not in the trip.');
          return;
        }
        ops.add(RestDayOp(day, '${raw['level']}' == 'free' ? RestLevel.free : RestLevel.light));
      case 'moveStop':
        final to = _day(raw['toDay'], index);
        if (to == null) {
          problems.add('That day is not in the trip.');
          return;
        }
        final id = stop(raw['place'], (id) => MoveStopOp(id, to));
        if (id != null) ops.add(MoveStopOp(id, to));
      case 'swapStop':
        final withRef = _text(raw['with']);
        final wish = _text(raw['wish']);
        final id = stop(raw['place'], (id) => SwapStopOp(id, withName: withRef, wish: wish));
        if (id != null) {
          // A replacement named in the plan's pool (by id) is used as is; a name is looked up.
          ops.add(SwapStopOp(id, withPlaceId: withRef != null && RegExp(r'^[\w:/.\-]+$').hasMatch(withRef) && !withRef.contains(' ') ? withRef : null, withName: withRef, wish: wish));
        }
      case 'removeStop':
        final id = stop(raw['place'], (id) => RemoveStopOp(id));
        if (id != null) ops.add(RemoveStopOp(id));
      case 'addStop':
        final name = _text(raw['name']);
        if (name == null) {
          problems.add('A change did not say which place to add.');
          return;
        }
        final day = raw['day'] == null ? null : _day(raw['day'], index);
        ops.add(AddStopOp(name: name, day: day));
      case 'lockStop':
        final lock = raw['lock'] != false;
        final id = stop(raw['place'], (id) => LockStopOp(id, lock: lock));
        if (id != null) ops.add(LockStopOp(id, lock: lock));
      case 'changeHotel':
        final max = raw['maxNightlyInr'] is num ? (raw['maxNightlyInr'] as num).round() : null;
        ops.add(
          ChangeHotelOp(
            hotelId: _text(raw['hotel']) != null && index.itinerary.hotelAlternatives.any((h) => h.id == _text(raw['hotel'])) ? _text(raw['hotel']) : null,
            name: _text(raw['hotel']),
            maxNightlyInr: max != null && max > 0 && max < 5000000 ? max : null,
            needs: _needs(raw['needs']),
            wish: _text(raw['wish']),
          ),
        );
      case 'changeTransport':
        final mode = _mode(raw['mode']);
        if (mode == null) {
          problems.add('That way of travelling is not one I know.');
          return;
        }
        ops.add(ChangeTransportOp(mode));
      case 'changeDates':
        final delta = raw['deltaDays'] is num ? (raw['deltaDays'] as num).toInt() : null;
        if (delta != null) {
          final target = index.dayCount + delta;
          if (delta == 0 || target < 1 || target > 21) {
            problems.add('A trip can be between 1 and 21 days.');
            return;
          }
          ops.add(ChangeDatesOp(deltaDays: delta));
        } else {
          final s = DateTime.tryParse('${raw['start']}');
          final e = DateTime.tryParse('${raw['end']}');
          if (s == null || e == null || e.isBefore(s) || e.difference(s).inDays > 21) {
            problems.add('Those dates cannot be used.');
            return;
          }
          ops.add(ChangeDatesOp(start: s, end: e));
        }
      case 'setPreferences':
        final budget = raw['budgetMaxInr'] is num ? (raw['budgetMaxInr'] as num).round() : null;
        final factor = raw['budgetFactor'] is num ? (raw['budgetFactor'] as num).toDouble() : null;
        ops.add(
          SetPreferencesOp(
            pace: _enum(TripPace.values, raw['pace']),
            style: _enum(TripStyle.values, raw['style']),
            sustainability: _enum(SustainabilityPriority.values, raw['sustainability']),
            budgetMaxInr: budget != null && budget > 0 && budget < 500000000 ? budget : null,
            budgetFactor: factor != null && factor > 0.2 && factor < 3 ? factor : null,
            addNeeds: _needs(raw['addNeeds']),
            removeNeeds: _needs(raw['removeNeeds']),
          ),
        );
      case 'explain':
        final r = _text(raw['place']);
        final id = r == null ? null : (index.resolve(r).firstOrNull?.id);
        ops.add(ExplainOp(placeId: id, day: _day(raw['day'], index)));
      default:
        problems.add('I do not know how to “${op.length > 20 ? op.substring(0, 20) : op}”.');
    }
  }

  static Set<AccessibilityNeed> _needs(Object? v) => {
    if (v is List)
      for (final e in v)
        for (final n in AccessibilityNeed.values)
          if (n.name == '$e' && n != AccessibilityNeed.none) n,
  };

  static T? _enum<T extends Enum>(List<T> values, Object? v) {
    for (final e in values) {
      if (e.name == '$v') return e;
    }
    return null;
  }

  static TripTransportMode? _mode(Object? v) {
    final s = '$v'.toLowerCase().trim();
    for (final m in TripTransportMode.values) {
      if (m.name.toLowerCase() == s || m.label.toLowerCase() == s) return m;
    }
    return switch (s) {
      'plane' || 'air' || 'flight' => TripTransportMode.flight,
      'cab' || 'taxi' || 'car' => TripTransportMode.carTaxi,
      'rail' || 'train' => TripTransportMode.train,
      'metro' => TripTransportMode.metroLocal,
      _ => null,
    };
  }
}

/// The fallback when no model can be reached: a small set of phrases and the
/// quick-action chips, read with patterns. It understands far less than the
/// model, and says so when it cannot tell what was meant.
abstract final class EditRules {
  static ParsedEdit parse(String text, PlanIndex index) {
    final t = text.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.isEmpty) return const ParsedEdit();
    final ops = <EditOp>[];
    final problems = <String>[];
    final ambiguities = <Ambiguity>[];

    int? dayIn(String s) {
      // "day 6" or "day 6th", and "6th day".
      final m = RegExp(r'\bday\s*(\d{1,2})(?:st|nd|rd|th)?\b').firstMatch(s) ?? RegExp(r'\b(\d{1,2})(?:st|nd|rd|th)\s+day\b').firstMatch(s);
      if (m == null) return null;
      final d = int.parse(m.group(1)!);
      return d >= 1 && d <= index.dayCount ? d : null;
    }

    // A pure pace phrase ("a more relaxed trip") shouldn't be mistaken for a
    // broken rest-day request when it names no day.
    final pacePhrase = RegExp(r'\b(more relaxed|relaxed pace|slower|slow down|fewer places|less packed|less rushed)\b').hasMatch(t);

    // Rest
    if (RegExp(r'\b(rest(ed|ful)?|relax(ed|ing)?|lighter|light day|take it easy|slow(er)? day|free day|day off|nothing planned)\b').hasMatch(t)) {
      final d = dayIn(t);
      if (d != null) {
        ops.add(RestDayOp(d, RegExp(r'\b(free day|day off|nothing planned|no plans)\b').hasMatch(t) ? RestLevel.free : RestLevel.light));
      } else if (!pacePhrase) {
        problems.add('Which day should be lighter?');
      }
    }
    // Stops by name: remove / add / move / replace
    String? afterVerb(RegExp verb) => verb.firstMatch(t)?.group(1)?.trim();
    void stopOp(String? ref, EditOp Function(String) make, {int? day}) {
      if (ref == null || ref.isEmpty) return;
      final found = index.resolve(ref.replaceAll(RegExp(r'^(the|a|an)\s+'), ''), dayHint: day);
      if (found.isEmpty) {
        problems.add('“$ref” is not in your plan.');
      } else if (found.length > 1 && found[1].name != found.first.name && found.first.name.toLowerCase() != ref) {
        ambiguities.add(Ambiguity(ref: ref, candidates: found.take(4).toList(), build: make));
      } else {
        ops.add(make(found.first.id));
      }
    }

    final remove = afterVerb(RegExp(r'\b(?:remove|drop|skip|delete|cancel)\s+(.+?)(?:\s+(?:from|on)\s+day\s*\d+)?$'));
    if (remove != null && ops.isEmpty) stopOp(remove, RemoveStopOp.new, day: dayIn(t));

    final move = RegExp(r'\bmove\s+(.+?)\s+to\s+day\s*(\d{1,2})\b').firstMatch(t);
    if (move != null) {
      final to = int.parse(move.group(2)!);
      if (to >= 1 && to <= index.dayCount) {
        stopOp(move.group(1), (id) => MoveStopOp(id, to));
      } else {
        problems.add('That day is not in the trip.');
      }
    }

    final replace = RegExp(r'\b(?:replace|swap|change)\s+(.+?)\s+(?:with|for|by)\s+(.+)$').firstMatch(t);
    if (replace != null && !t.contains('hotel')) {
      final what = replace.group(2)!.trim();
      stopOp(replace.group(1), (id) => SwapStopOp(id, withName: what, wish: what));
    } else {
      final wish = RegExp(r'\breplace\s+(.+?)\s+with something\s*(.*)$').firstMatch(t);
      if (wish != null) stopOp(wish.group(1), (id) => SwapStopOp(id, wish: 'something ${wish.group(2)}'.trim()));
    }

    final add = RegExp(r'\badd\s+(?!(?:a|an|one|two|another|1|2)\s+(?:more\s+)?days?\b)(.+?)(?:\s+(?:to|on)\s+day\s*(\d{1,2}))?$').firstMatch(t);
    if (add != null && !RegExp(r'\b(hotel|stay|days?)\b').hasMatch(add.group(1)!)) {
      final name = add.group(1)!.trim();
      final day = add.group(2) == null ? null : int.tryParse(add.group(2)!);
      if (name.isNotEmpty) ops.add(AddStopOp(name: name, day: day != null && day >= 1 && day <= index.dayCount ? day : null));
    }

    // Days
    final more = RegExp(r'\b(?:add|extend|one more|another)\b.*\bday').hasMatch(t) || RegExp(r'\bextra day\b').hasMatch(t);
    if (more && !ops.any((o) => o is AddStopOp)) {
      final n = RegExp(r'\b(two|2)\b').hasMatch(t) ? 2 : 1;
      ops.add(ChangeDatesOp(deltaDays: index.dayCount + n <= 21 ? n : null));
    }
    if (RegExp(r'\b(shorten|one day less|remove a day|drop a day|cut a day)\b').hasMatch(t) && index.dayCount > 1) ops.add(const ChangeDatesOp(deltaDays: -1));

    // Hotel
    if (RegExp(r'\b(hotel|stay|accommodation)\b').hasMatch(t) && RegExp(r'\b(change|different|another|new|cheaper|find|switch|better|accessible|wheelchair|under|below|budget)\b').hasMatch(t)) {
      final cap = RegExp(r'(?:under|below|less than|max|at most|within)\s*(?:rs\.?|₹|inr)?\s*(\d[\d,]{2,7})').firstMatch(t);
      ops.add(
        ChangeHotelOp(
          maxNightlyInr: cap == null ? null : int.tryParse(cap.group(1)!.replaceAll(',', '')),
          needs: {if (RegExp(r'wheelchair|accessible|step[- ]free').hasMatch(t)) AccessibilityNeed.wheelchair},
          wish: t.contains('cheaper') ? 'cheaper' : null,
        ),
      );
    }

    // Transport
    final mode = RegExp(r'\b(?:by|via|take the|use the|switch to|change to)\s+(train|flight|plane|bus|cab|taxi|car|metro|electric bus|e-bus|shared ev)\b').firstMatch(t);
    if (mode != null) {
      final m = EditParser.fromModel({'ops': [{'op': 'changeTransport', 'mode': mode.group(1)!.replaceAll('electric bus', 'eBus').replaceAll('e-bus', 'eBus').replaceAll('shared ev', 'sharedEv')}]}, index);
      ops.addAll(m.ops);
    }

    // Preferences
    TripPace? pace;
    if (RegExp(r'\b(more relaxed|relaxed pace|slower|slow down|fewer places|less packed|less rushed)\b').hasMatch(t)) pace = TripPace.relaxed;
    if (RegExp(r'\b(faster|packed|more places|see more|busier|more to do)\b').hasMatch(t)) pace = TripPace.packed;
    // "day 6 should be more relaxed" is about that one day, not the whole trip's pace.
    if (pace == TripPace.relaxed && ops.any((o) => o is RestDayOp)) pace = null;
    final greener = RegExp(r'\b(greener|eco[- ]friendly|more sustainable|lower carbon|less carbon|reduce (?:my )?(?:carbon|co2))\b').hasMatch(t);
    final cheaper = RegExp(r'\b(cheaper|reduce (?:the )?budget|save money|less expensive|lower (?:the )?cost)\b').hasMatch(t) && !t.contains('hotel');
    final budget = RegExp(r'\bbudget\s*(?:of|to|is|=)?\s*(?:rs\.?|₹|inr)?\s*(\d[\d,]{3,8})\b').firstMatch(t);
    if (pace != null || greener || cheaper || budget != null) {
      ops.add(
        SetPreferencesOp(
          pace: pace,
          sustainability: greener ? SustainabilityPriority.greenest : null,
          budgetFactor: cheaper && budget == null ? 0.85 : null,
          budgetMaxInr: budget == null ? null : int.tryParse(budget.group(1)!.replaceAll(',', '')),
        ),
      );
    }

    // Lock / why
    final lock = afterVerb(RegExp(r'\b(?:lock|pin|keep)\s+(.+?)\s+(?:where it is|in place|on day\s*\d+)$'));
    if (lock != null) stopOp(lock, (id) => LockStopOp(id));
    final why = RegExp(r'\bwhy\b.*\b(?:is|are|do we|did you)\b.*').hasMatch(t);
    if (why && ops.isEmpty && ambiguities.isEmpty) {
      final d = dayIn(t);
      final named = index.stops.where((s) => t.contains(s.name.toLowerCase())).firstOrNull;
      ops.add(ExplainOp(placeId: named?.id, day: d));
    }

    if (ops.isEmpty && ambiguities.isEmpty && problems.isEmpty) {
      problems.add('I can move stops between days, add, replace or remove places, lighten a day, change the hotel or the way you travel, add or remove a day, or make the trip greener or cheaper.');
    }
    return ParsedEdit(ops: ops.take(EditParser.maxOps).toList(), problems: problems, ambiguities: ambiguities);
  }
}
