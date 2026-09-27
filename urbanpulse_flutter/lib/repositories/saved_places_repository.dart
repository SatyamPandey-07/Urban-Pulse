import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/saved_place.dart';

/// The traveller's saved addresses (Home, Work and their own), and which one is
/// in use. Kept on the device.
class SavedPlacesRepository extends ChangeNotifier {
  SavedPlacesRepository(this._prefs) {
    _places = _read();
    _activeId = _prefs.getString(_keyActive);
  }

  static const _key = 'urbanpulse.saved_places';
  static const _keyActive = 'urbanpulse.active_place_id';
  static const maxPlaces = 12;

  final SharedPreferences _prefs;
  late List<SavedPlace> _places;
  String? _activeId;

  List<SavedPlace> get places => List.unmodifiable(_places);

  SavedPlace? get home => _first(PlaceKind.home);
  SavedPlace? get work => _first(PlaceKind.work);
  List<SavedPlace> get others => [for (final p in _places) if (p.kind == PlaceKind.other) p];

  /// The address the app currently works from, or null for "my current location".
  SavedPlace? get active {
    final id = _activeId;
    if (id == null) return null;
    for (final p in _places) {
      if (p.id == id) return p;
    }
    return null;
  }

  SavedPlace? _first(PlaceKind k) {
    for (final p in _places) {
      if (p.kind == k) return p;
    }
    return null;
  }

  List<SavedPlace> _read() {
    final raw = _prefs.getString(_key);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return [];
      return [for (final j in list) ?SavedPlace.fromJson(j)];
    } catch (_) {
      return [];
    }
  }

  Future<void> _write() async {
    await _prefs.setString(_key, jsonEncode([for (final p in _places) p.toJson()]));
    final id = _activeId;
    if (id == null) {
      await _prefs.remove(_keyActive);
    } else {
      await _prefs.setString(_keyActive, id);
    }
    notifyListeners();
  }

  /// Saves an address. There is one Home and one Work: saving another replaces
  /// it. Returns the saved place, or null if there is no room for another.
  Future<SavedPlace?> save({required PlaceKind kind, required String label, required String address, required String city, required double lat, required double lon}) async {
    final name = label.trim().isEmpty ? kind.label : label.trim();
    if (!lat.isFinite || !lon.isFinite) return null;
    final existing = kind == PlaceKind.other ? null : _first(kind);
    if (existing == null && _places.length >= maxPlaces) return null;
    final place = SavedPlace(
      id: existing?.id ?? 'p${DateTime.now().microsecondsSinceEpoch}',
      kind: kind,
      label: kind == PlaceKind.other ? name : kind.label,
      address: address.trim(),
      city: city.trim(),
      lat: lat,
      lon: lon,
    );
    _places = [for (final p in _places) if (p.id != place.id) p, place]..sort(_order);
    await _write();
    return place;
  }

  static int _order(SavedPlace a, SavedPlace b) => a.kind.index != b.kind.index ? a.kind.index.compareTo(b.kind.index) : a.label.compareTo(b.label);

  Future<void> remove(String id) async {
    _places = [for (final p in _places) if (p.id != id) p];
    if (_activeId == id) _activeId = null;
    await _write();
  }

  /// Works from [place] (or, with null, from the current location).
  Future<void> setActive(SavedPlace? place) async {
    _activeId = place?.id;
    await _write();
  }
}
