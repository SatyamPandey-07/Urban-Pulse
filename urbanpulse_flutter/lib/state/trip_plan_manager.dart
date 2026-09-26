import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SelectedStay {
  const SelectedStay({
    required this.id,
    required this.name,
    required this.carbonKgPerNight,
    required this.priceRupees,
  });

  final String id;
  final String name;
  final double carbonKgPerNight;
  final int priceRupees;
}

class SelectedMobility {
  const SelectedMobility({
    required this.modeLabel,
    required this.carbonGrams,
    required this.fareRupees,
    required this.distanceKm,
  });

  final String modeLabel;
  final double carbonGrams;
  final int fareRupees;
  final double distanceKm;
}

class SelectedExperiences {
  const SelectedExperiences({
    required this.names,
    required this.totalCarbonKg,
    required this.totalPriceRupees,
  });

  final List<String> names;
  final double totalCarbonKg;
  final int totalPriceRupees;
}

/// Remembers the traveler's current stay + transport + activity choices across
/// screens so a combined trip-level summary can be computed, instead of
/// Hospitality, Green Route Planner and Itinerary staying three independent,
/// unconnected optimizers.
///
/// Port of `trip/TripPlanManager.kt`.
class TripPlanManager extends ChangeNotifier {
  TripPlanManager(this._prefs);

  static const _prefix = 'urbanpulse_trip_plan';

  final SharedPreferences _prefs;

  Future<void> setSelectedStay(SelectedStay stay) async {
    await _prefs.setString('$_prefix.stay_id', stay.id);
    await _prefs.setString('$_prefix.stay_name', stay.name);
    await _prefs.setDouble('$_prefix.stay_carbon_kg', stay.carbonKgPerNight);
    await _prefs.setInt('$_prefix.stay_price', stay.priceRupees);
    notifyListeners();
  }

  SelectedStay? get selectedStay {
    final id = _prefs.getString('$_prefix.stay_id');
    if (id == null) return null;
    return SelectedStay(
      id: id,
      name: _prefs.getString('$_prefix.stay_name') ?? '',
      carbonKgPerNight: _prefs.getDouble('$_prefix.stay_carbon_kg') ?? 0,
      priceRupees: _prefs.getInt('$_prefix.stay_price') ?? 0,
    );
  }

  Future<void> setSelectedMobility(SelectedMobility mobility) async {
    await _prefs.setString('$_prefix.mobility_label', mobility.modeLabel);
    await _prefs.setDouble(
      '$_prefix.mobility_carbon_grams',
      mobility.carbonGrams,
    );
    await _prefs.setInt('$_prefix.mobility_fare', mobility.fareRupees);
    await _prefs.setDouble(
      '$_prefix.mobility_distance_km',
      mobility.distanceKm,
    );
    notifyListeners();
  }

  SelectedMobility? get selectedMobility {
    final label = _prefs.getString('$_prefix.mobility_label');
    if (label == null) return null;
    return SelectedMobility(
      modeLabel: label,
      carbonGrams: _prefs.getDouble('$_prefix.mobility_carbon_grams') ?? 0,
      fareRupees: _prefs.getInt('$_prefix.mobility_fare') ?? 0,
      distanceKm: _prefs.getDouble('$_prefix.mobility_distance_km') ?? 0,
    );
  }

  Future<void> setSelectedExperiences(SelectedExperiences experiences) async {
    await _prefs.setString(
      '$_prefix.experience_names',
      experiences.names.join('|'),
    );
    await _prefs.setDouble(
      '$_prefix.experience_total_carbon_kg',
      experiences.totalCarbonKg,
    );
    await _prefs.setInt(
      '$_prefix.experience_total_price',
      experiences.totalPriceRupees,
    );
    notifyListeners();
  }

  SelectedExperiences? get selectedExperiences {
    final namesJoined = _prefs.getString('$_prefix.experience_names');
    if (namesJoined == null) return null;
    return SelectedExperiences(
      names: namesJoined.split('|'),
      totalCarbonKg:
          _prefs.getDouble('$_prefix.experience_total_carbon_kg') ?? 0,
      totalPriceRupees: _prefs.getInt('$_prefix.experience_total_price') ?? 0,
    );
  }
}
