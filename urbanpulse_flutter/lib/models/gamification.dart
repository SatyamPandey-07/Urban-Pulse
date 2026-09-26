import 'package:flutter/material.dart';

/// Port of the `Challenge` / `AchievementBadge` data classes in `GamificationManager.kt`
/// and the `Achievement` class in `AchievementsActivity.kt`. Icons are Material
/// icons standing in for the vector drawables the Android layouts referenced.
class Challenge {
  const Challenge({
    required this.id,
    required this.title,
    required this.type,
    required this.target,
    required this.progress,
    required this.xpReward,
    required this.pulseReward,
  });

  final String id;
  final String title;
  final String type;
  final int target;
  final int progress;
  final int xpReward;
  final int pulseReward;
}

class AchievementBadge {
  const AchievementBadge({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.progress,
    required this.target,
  });

  final String id;
  final String title;
  final String description;
  final IconData icon;
  final int progress;
  final int target;

  bool get isUnlocked => progress >= target;
}

class Achievement {
  Achievement({
    required this.title,
    required this.description,
    required this.icon,
    required this.isUnlocked,
  });

  final String title;
  final String description;
  final IconData icon;
  bool isUnlocked;
}
