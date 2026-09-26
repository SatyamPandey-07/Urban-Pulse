import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/gamification.dart';

/// XP / PULSE credits / login streak / lifetime CO2, persisted exactly as
/// `GamificationManager.kt` did. Notifies listeners so the Carbon Wallet and
/// Achievements screens refresh without manual `onResume` plumbing.
class GamificationController extends ChangeNotifier {
  GamificationController(this._prefs) {
    _checkDailyLogin();
  }

  static const _prefix = 'urbanpulse_game_prefs';
  static const _keyXp = '$_prefix.user_xp';
  static const _keyPulse = '$_prefix.user_pulse';
  static const _keyLastLogin = '$_prefix.last_login_day';
  static const _keyStreak = '$_prefix.current_streak';
  static const _keyCo2 = '$_prefix.co2_saved';

  final SharedPreferences _prefs;

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
  }

  Future<void> addPulse(int amount) async {
    await _prefs.setInt(_keyPulse, pulse + amount);
    notifyListeners();
  }

  Future<bool> spendPulse(int amount) async {
    if (pulse < amount) return false;
    await _prefs.setInt(_keyPulse, pulse - amount);
    notifyListeners();
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
  }

  // --- CO2 ---

  double get co2SavedGrams => _prefs.getDouble(_keyCo2) ?? 0;

  Future<void> addCo2Saved(double grams) async {
    await _prefs.setDouble(_keyCo2, co2SavedGrams + grams);
    notifyListeners();
  }

  // --- Challenges & badges ---

  List<Challenge> get activeChallenges => const [
    Challenge(
      id: 'ch1',
      title: 'Walk 2,000 steps',
      type: 'Daily',
      target: 2000,
      progress: 0,
      xpReward: 100,
      pulseReward: 10,
    ),
    Challenge(
      id: 'ch2',
      title: 'Report 3 hazards',
      type: 'Weekly',
      target: 3,
      progress: 0,
      xpReward: 500,
      pulseReward: 50,
    ),
  ];

  List<AchievementBadge> get allBadges => const [
    AchievementBadge(
      id: 'b1',
      title: 'Eco Pioneer',
      description: 'Save 10kg of CO2',
      icon: Icons.local_fire_department,
      progress: 5,
      target: 10,
    ),
    AchievementBadge(
      id: 'b2',
      title: 'Urban Scout',
      description: 'Report 5 incidents',
      icon: Icons.location_on,
      progress: 3,
      target: 5,
    ),
    AchievementBadge(
      id: 'b3',
      title: 'Daily Walker',
      description: 'Reach 10,000 steps',
      icon: Icons.dashboard,
      progress: 10000,
      target: 10000,
    ),
    AchievementBadge(
      id: 'b4',
      title: 'Night Owl',
      description: 'Report a safe path at night',
      icon: Icons.map,
      progress: 1,
      target: 1,
    ),
    AchievementBadge(
      id: 'b5',
      title: 'AI Navigator',
      description: 'Ask Yatri AI 10 questions',
      icon: Icons.auto_awesome,
      progress: 4,
      target: 10,
    ),
    AchievementBadge(
      id: 'b6',
      title: 'Community Hero',
      description: 'Get 50 upvotes',
      icon: Icons.celebration,
      progress: 12,
      target: 50,
    ),
  ];
}
