import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/evidence_graph_service.dart';
import '../models/evidence.dart';
import '../models/experience_listing.dart';
import '../models/hospitality_stay.dart';

/// Owns the traveler's own step-free / visual / hearing / service-animal
/// accessibility preference flags, and is the entry point for evidence-tagged
/// accessibility claims about a listing (delegating to [EvidenceGraphService],
/// which holds the actual Verified/Reported/Inferred confidence-tagging logic) —
/// this is the one place both halves of "accessibility" in this app meet: what
/// the traveler needs, and what's actually been confirmed about a place.
///
/// Port of `AccessibilityManager.kt`.
class AccessibilityController extends ChangeNotifier {
  AccessibilityController(this._prefs);

  static const _prefix = 'AccessibilityPrefs';
  static const _keyWheelchair = '$_prefix.key_wheelchair_mode';
  static const _keyVisual = '$_prefix.key_visual_assist';
  static const _keyHearing = '$_prefix.key_hearing_assist';
  static const _keyServiceAnimal = '$_prefix.key_service_animal';

  final SharedPreferences _prefs;

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
  }

  /// Evidence-tagged accessibility/sustainability claims for an experience
  /// listing — real confidence tiers, not a plain "Accessible: Yes/No".
  List<EvidenceClaim> evidenceForExperience(ExperienceListing experience) =>
      EvidenceGraphService.buildEvidenceForExperience(experience);

  /// Same, for a hospitality stay.
  List<EvidenceClaim> evidenceForStay(HospitalityStay stay) =>
      EvidenceGraphService.buildEvidence(stay);
}
