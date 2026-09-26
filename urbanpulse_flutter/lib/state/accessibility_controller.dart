import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/evidence_graph_service.dart';
import '../models/evidence.dart';
import '../models/experience_listing.dart';
import '../models/hospitality_stay.dart';
import '../services/cloud/cloud_store.dart';

/// Owns the traveler's own step-free / visual / hearing / service-animal
/// accessibility preference flags, and is the entry point for evidence-tagged
/// accessibility claims about a listing (delegating to [EvidenceGraphService],
/// which holds the actual Verified/Reported/Inferred confidence-tagging logic) —
/// this is the one place both halves of "accessibility" in this app meet: what
/// the traveler needs, and what's actually been confirmed about a place.
///
/// Port of `AccessibilityManager.kt`.
class AccessibilityController extends ChangeNotifier {
  AccessibilityController(this._prefs, {this.cloud});

  static const _prefix = 'AccessibilityPrefs';
  static const _keyWheelchair = '$_prefix.key_wheelchair_mode';
  static const _keyVisual = '$_prefix.key_visual_assist';
  static const _keyHearing = '$_prefix.key_hearing_assist';
  static const _keyServiceAnimal = '$_prefix.key_service_animal';

  final SharedPreferences _prefs;
  final CloudStore? cloud;

  /// The account's column for each flag (`user_settings`).
  static const _columns = {
    _keyWheelchair: 'wheelchair_mode',
    _keyVisual: 'visual_assist',
    _keyHearing: 'hearing_assist',
    _keyServiceAnimal: 'service_animal_only',
  };

  bool get isWheelchairModeEnabled => _prefs.getBool(_keyWheelchair) ?? false;

  bool get isVisualAssistanceEnabled => _prefs.getBool(_keyVisual) ?? false;

  bool get isHearingAssistanceEnabled => _prefs.getBool(_keyHearing) ?? false;

  bool get isServiceAnimalFriendlyOnly =>
      _prefs.getBool(_keyServiceAnimal) ?? false;

  Future<void> setWheelchairMode(bool value) => _set(_keyWheelchair, value);

  Future<void> setVisualAssistance(bool value) => _set(_keyVisual, value);

  Future<void> setHearingAssistance(bool value) => _set(_keyHearing, value);

  Future<void> setServiceAnimalFriendlyOnly(bool value) =>
      _set(_keyServiceAnimal, value);

  Future<void> _set(String key, bool value) async {
    await _prefs.setBool(key, value);
    notifyListeners();
    await cloud?.saveSettings({_columns[key]!: value});
  }

  /// The flags as the account stores them.
  Map<String, Object?> snapshot() => {for (final e in _columns.entries) e.value: _prefs.getBool(e.key) ?? false};

  /// The device flags become the account's.
  Future<void> applyCloud(Map<String, dynamic> row) async {
    for (final e in _columns.entries) {
      await _prefs.setBool(e.key, row[e.value] == true);
    }
    notifyListeners();
  }

  Future<void> clear() async {
    for (final k in _columns.keys) {
      await _prefs.remove(k);
    }
    notifyListeners();
  }

  /// Evidence-tagged accessibility/sustainability claims for an experience
  /// listing — real confidence tiers, not a plain "Accessible: Yes/No".
  List<EvidenceClaim> evidenceForExperience(ExperienceListing experience) =>
      EvidenceGraphService.buildEvidenceForExperience(experience);

  /// Same, for a hospitality stay.
  List<EvidenceClaim> evidenceForStay(HospitalityStay stay) =>
      EvidenceGraphService.buildEvidence(stay);
}
