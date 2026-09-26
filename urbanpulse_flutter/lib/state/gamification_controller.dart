import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/gamification.dart';
import '../services/cloud/cloud_store.dart';
import 'activity_tracker.dart';

/// XP / PULSE credits / login streak / lifetime CO2, persisted exactly as
/// `GamificationManager.kt` did. Notifies listeners so the Carbon Wallet and
/// Achievements screens refresh without manual `onResume` plumbing.
class GamificationController extends ChangeNotifier {
  GamificationController(this._prefs, this._activity, {this.cloud}) {
    _activity.addListener(notifyListeners);
    _checkDailyLogin();
  }

  static const _prefix = 'urbanpulse_game_prefs';
  static const _keyXp = '$_prefix.user_xp';
  static const _keyPulse = '$_prefix.user_pulse';
  static const _keyLastLogin = '$_prefix.last_login_day';
  static const _keyStreak = '$_prefix.current_streak';
  static const _keyCo2 = '$_prefix.co2_saved';

  final SharedPreferences _prefs;
  final ActivityTracker _activity;
  final CloudStore? cloud;

  /// XP, PULSE, streak and CO2 as the account stores them (`user_progress`).
  Map<String, Object?> snapshot() => {
    'xp': xp,
    'pulse': pulse,
    'streak': streak,
    'last_login_day': _prefs.getInt(_keyLastLogin),
    'co2_saved_kg': co2SavedGrams / 1000,
  };

  Future<void> _sync() async => cloud?.saveProgress(snapshot());

  /// The device values become the account's.
  Future<void> applyCloud(Map<String, dynamic> row) async {
    int asInt(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    await _prefs.setInt(_keyXp, asInt(row['xp']));
    await _prefs.setInt(_keyPulse, asInt(row['pulse']));
    await _prefs.setInt(_keyStreak, asInt(row['streak']));
    final day = row['last_login_day'];
    if (day is num) await _prefs.setInt(_keyLastLogin, day.toInt());
    final kg = row['co2_saved_kg'];
    await _prefs.setDouble(_keyCo2, (kg is num ? kg.toDouble() : double.tryParse('$kg') ?? 0) * 1000);
    notifyListeners();
  }

  Future<void> clear() async {
    for (final k in [_keyXp, _keyPulse, _keyStreak, _keyLastLogin, _keyCo2]) {
      await _prefs.remove(k);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _activity.removeListener(notifyListeners);
    super.dispose();
  }

  // --- Progression ---

  int get xp => _prefs.getInt(_keyXp) ?? 0;

  int get pulse => _prefs.getInt(_keyPulse) ?? 0;

  int get level {
    final current = xp;
    if (current < 1000) return 1;
    return (math.pow(current / 1000.0, 1.0 / 1.5) + 1).toInt();
  }

  int get nextLevelXp => (1000 * math.pow(level, 1.5)).toInt();

  Future<void> addXp(int amount) async {
    await _prefs.setInt(_keyXp, xp + amount);
    notifyListeners();
    await _sync();
  }

  Future<void> addPulse(int amount) async {
    await _prefs.setInt(_keyPulse, pulse + amount);
    notifyListeners();
    await _sync();
  }

  Future<bool> spendPulse(int amount) async {
    if (pulse < amount) return false;
    await _prefs.setInt(_keyPulse, pulse - amount);
    notifyListeners();
    await _sync();
    return true;
  }

  // --- Streak ---

  int get streak => _prefs.getInt(_keyStreak) ?? 0;

  Future<void> _checkDailyLogin() async {
    final lastLoginDay = _prefs.getInt(_keyLastLogin) ?? -1;
    final now = DateTime.now();
    final currentDay =
        now.difference(DateTime(now.year)).inDays + 1; // day of year

    if (lastLoginDay == -1) {
      await _prefs.setInt(_keyLastLogin, currentDay);
      await _prefs.setInt(_keyStreak, 1);
    } else if (currentDay == lastLoginDay + 1) {
      await _prefs.setInt(_keyLastLogin, currentDay);
      await _prefs.setInt(_keyStreak, streak + 1);
      await addXp(50);
    } else if (currentDay > lastLoginDay + 1) {
      await _prefs.setInt(_keyLastLogin, currentDay);
      await _prefs.setInt(_keyStreak, 1);
    }
    notifyListeners();
    await _sync();
  }

  // --- CO2 ---

  double get co2SavedGrams => _prefs.getDouble(_keyCo2) ?? 0;

  Future<void> addCo2Saved(double grams) async {
    await _prefs.setDouble(_keyCo2, co2SavedGrams + grams);
    notifyListeners();
    await _sync();
  }

  // --- Challenges & badges ---
  //
  // Progress is read from the real counters in [ActivityTracker] and the real
  // lifetime CO2 total, so these bars actually move as the app is used. The
  // Kotlin originals returned fixed `progress` values that never changed.

  List<Challenge> get activeChallenges => [
    Challenge(
      id: 'ch_plan_trip',
      title: 'Plan a low-carbon trip with Yatri AI',
      type: 'Daily',
      target: 1,
      progress: _activity.count(TrackedAction.tripsPlanned),
      xpReward: 100,
      pulseReward: 10,
    ),
    Challenge(
      id: 'ch_confirm_journeys',
      title: 'Confirm 3 green journeys',
      type: 'Weekly',
      target: 3,
      progress: _activity.count(TrackedAction.greenJourneysConfirmed),
      xpReward: 500,
      pulseReward: 50,
    ),
    Challenge(
      id: 'ch_accessibility_reports',
      title: 'File 2 accessibility reports',
      type: 'Weekly',
      target: 2,
      progress: _activity.count(TrackedAction.accessibilityReportsFiled),
      xpReward: 300,
      pulseReward: 30,
    ),
  ];

  List<AchievementBadge> get allBadges => [
    AchievementBadge(
      id: 'b_eco_pioneer',
      title: 'Eco Pioneer',
      description: 'Save 10 kg of CO2',
      icon: Icons.local_fire_department,
      // Tracked in grams; the badge is expressed in whole kilograms.
      progress: (co2SavedGrams / 1000).floor(),
      target: 10,
    ),
    AchievementBadge(
      id: 'b_green_commuter',
      title: 'Green Commuter',
      description: 'Confirm 5 low-carbon journeys',
      icon: Icons.directions_transit,
      progress: _activity.count(TrackedAction.greenJourneysConfirmed),
      target: 5,
    ),
    AchievementBadge(
      id: 'b_ai_navigator',
      title: 'AI Navigator',
      description: 'Ask Yatri AI 10 questions',
      icon: Icons.auto_awesome,
      progress: _activity.count(TrackedAction.aiQuestionsAsked),
      target: 10,
    ),
    AchievementBadge(
      id: 'b_trip_curator',
      title: 'Trip Curator',
      description: 'Save 3 trips to your passport',
      icon: Icons.luggage,
      progress: _activity.count(TrackedAction.tripsSaved),
      target: 3,
    ),
    AchievementBadge(
      id: 'b_access_advocate',
      title: 'Access Advocate',
      description: 'File 5 accessibility reports',
      icon: Icons.accessible_forward,
      progress: _activity.count(TrackedAction.accessibilityReportsFiled),
      target: 5,
    ),
    AchievementBadge(
      id: 'b_local_host',
      title: 'Local Host',
      description: 'Publish an experience to the registry',
      icon: Icons.storefront,
      progress: _activity.count(TrackedAction.experiencesPublished),
      target: 1,
    ),
  ];
}
