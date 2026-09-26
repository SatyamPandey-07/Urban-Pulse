import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../travel_risk/travel_risk.dart';

/// One thing the twin learned from.
class CalibrationObservation {
  const CalibrationObservation({required this.category, required this.disrupted, required this.source, required this.at});

  final String category;
  final bool disrupted;

  /// "traveller" (feedback in the app) or "social" (a report confirmed it).
  final String source;
  final DateTime at;

  Map<String, Object?> toJson() => {'category': category, 'disrupted': disrupted, 'source': source, 'at': at.toIso8601String()};

  static CalibrationObservation? fromJson(Object? j) {
    if (j is! Map<String, dynamic>) return null;
    return CalibrationObservation(
      category: '${j['category']}',
      disrupted: j['disrupted'] == true,
      source: '${j['source'] ?? 'traveller'}',
      at: DateTime.tryParse('${j['at']}') ?? DateTime.now(),
    );
  }
}

/// What the twin has learned about how weather really plays out: for each
/// kind of place, how often a "high impact" day actually disrupts a visit
/// (a Beta distribution per category, starting from a prior of 60%), and how
/// strongly demand reacts. Every confirmation from a traveller or a matching
/// social report updates it, and it is kept on the device between sessions.
class TwinCalibration {
  TwinCalibration(this._prefs) {
    _load();
  }

  /// Not persisted (tests, previews).
  TwinCalibration.memory() : _prefs = null;

  static const _key = 'twin.calibration.v1';
  static const priorA = 6.0;
  static const priorB = 4.0;

  final SharedPreferences? _prefs;
  final Map<String, (double, double)> _beta = {};
  final List<CalibrationObservation> history = [];

  /// Multiplies the demand and queue effects; nudged by observations.
  double demandScale = 1;

  /// Multiplies cab surge.
  double surgeScale = 1;

  int get observations => history.length;

  (double, double) betaFor(String category) => _beta[category] ?? (priorA, priorB);

  /// Chance a visit to [category] is really disrupted at [level].
  double pDisrupt(String category, ImpactLevel level) {
    final (a, b) = betaFor(category);
    final mean = a / (a + b);
    return switch (level) {
      ImpactLevel.closed => 0.97,
      ImpactLevel.high => mean,
      ImpactLevel.moderate => mean * 0.35,
      ImpactLevel.low => mean * 0.1,
      ImpactLevel.none => 0.01,
    };
  }

  /// The prior's chance at "high", for comparison in the UI.
  static double get priorHigh => priorA / (priorA + priorB);

  Future<void> record(String category, {required bool disrupted, String source = 'traveller'}) async {
    final (a, b) = betaFor(category);
    _beta[category] = disrupted ? (a + 1, b) : (a, b + 1);
    // Demand reacts a little more (or less) strongly than assumed.
    demandScale = (demandScale + (disrupted ? 0.02 : -0.02)).clamp(0.6, 1.6);
    history.insert(0, CalibrationObservation(category: category, disrupted: disrupted, source: source, at: DateTime.now()));
    if (history.length > 50) history.removeLast();
    await _save();
  }

  Future<void> reset() async {
    _beta.clear();
    history.clear();
    demandScale = 1;
    surgeScale = 1;
    await _save();
  }

  void _load() {
    final raw = _prefs?.getString(_key);
    if (raw == null) return;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final beta = j['beta'];
      if (beta is Map<String, dynamic>) {
        for (final e in beta.entries) {
          final v = e.value;
          if (v is List && v.length == 2 && v[0] is num && v[1] is num) _beta[e.key] = ((v[0] as num).toDouble(), (v[1] as num).toDouble());
        }
      }
      demandScale = (j['demandScale'] as num?)?.toDouble() ?? 1;
      surgeScale = (j['surgeScale'] as num?)?.toDouble() ?? 1;
      for (final h in (j['history'] as List<dynamic>? ?? const [])) {
        final o = CalibrationObservation.fromJson(h);
        if (o != null) history.add(o);
      }
    } catch (_) {
      // a damaged store starts from the prior
    }
  }

  Future<void> _save() async {
    final p = _prefs;
    if (p == null) return;
    await p.setString(
      _key,
      jsonEncode({
        'beta': {for (final e in _beta.entries) e.key: [e.value.$1, e.value.$2]},
        'demandScale': demandScale,
        'surgeScale': surgeScale,
        'history': [for (final h in history) h.toJson()],
      }),
    );
  }
}
