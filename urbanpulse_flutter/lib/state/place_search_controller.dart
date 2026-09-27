import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/saved_place.dart';
import '../services/place_suggestions.dart';

/// Type-ahead for a place: waits for a pause in typing, asks once, and ignores
/// answers that arrive after the person has typed something newer.
class PlaceSearchController extends ChangeNotifier {
  PlaceSearchController(this._suggestions, {this.delay = const Duration(milliseconds: 400), this.nearLat, this.nearLon});

  final PlaceSuggestions _suggestions;
  final Duration delay;
  double? nearLat;
  double? nearLon;

  String query = '';
  List<PlaceSuggestion> suggestions = const [];
  bool searching = false;

  /// Set when a search finished with nothing to show.
  bool noMatches = false;

  Timer? _timer;
  int _token = 0;
  bool _disposed = false;

  void changed(String text) {
    query = text;
    _timer?.cancel();
    final q = text.trim();
    final token = ++_token;
    if (q.length < 2) {
      suggestions = const [];
      searching = false;
      noMatches = false;
      _notify();
      return;
    }
    searching = true;
    noMatches = false;
    _notify();
    _timer = Timer(delay, () => _run(q, token));
  }

  Future<void> _run(String q, int token) async {
    final found = await _suggestions.suggest(q, nearLat: nearLat, nearLon: nearLon);
    if (_disposed || token != _token) return;
    suggestions = found;
    searching = false;
    noMatches = found.isEmpty;
    _notify();
  }

  void clear() {
    _timer?.cancel();
    _token++;
    query = '';
    suggestions = const [];
    searching = false;
    noMatches = false;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
