import 'package:flutter/material.dart';

import '../../core/app_colors.dart';

/// The nine agents of the planner. Yatri is the only decision-maker; the rest
/// are specialist workers with tools.
enum AgentKind {
  yatri(
    'Yatri',
    'Planner',
    'Plans the trip, allocates tasks to the other agents and makes every decision.',
    AppColors.primaryGreen,
    Icons.auto_awesome_rounded,
    keySlot: 0,
  ),
  atithi(
    'Atithi',
    'Hotels',
    'Finds stays that fit the budget, the dates and the group’s access needs.',
    AppColors.primaryBlue,
    Icons.hotel_rounded,
    keySlot: 1,
  ),
  bhatkanti(
    'Bhatkanti',
    'Hotspots',
    'Finds the places worth visiting for the time you have.',
    AppColors.primaryOrange,
    Icons.explore_rounded,
    keySlot: 2,
  ),
  hisab(
    'Hisab',
    'Budget',
    'Keeps the plan inside your budget with exact costs.',
    AppColors.primaryPurple,
    Icons.calculate_rounded,
    keySlot: 0,
  ),
  khoji(
    'Khoji',
    'Verifier',
    'Checks claims against reviews and other sources, and shows where it looked.',
    AppColors.primaryPink,
    Icons.fact_check_rounded,
    keySlot: 3,
  ),
  saksham(
    'Saksham',
    'Accessibility',
    'Audits every step of the journey for each access need in the group.',
    AppColors.primaryTeal,
    Icons.accessible_forward_rounded,
    keySlot: 2,
  ),
  raah(
    'Raah',
    'Route',
    'Orders the places into practical days using distance, opening hours and weather.',
    AppColors.primaryIndigo,
    Icons.alt_route_rounded,
    keySlot: 1,
  ),
  safar(
    'Safar',
    'Transport',
    'Plans how you get there and between places, with cost, time and emissions.',
    AppColors.solidWarning,
    Icons.directions_transit_rounded,
    keySlot: 1,
  ),
  hariyali(
    'Hariyali',
    'Sustainability',
    'Scores the carbon and eco impact of every choice and suggests greener ones.',
    Color(0xFF84CC16),
    Icons.eco_rounded,
    keySlot: 3,
  );

  const AgentKind(
    this.displayName,
    this.role,
    this.description,
    this.color,
    this.icon, {
    required this.keySlot,
  });

  final String displayName;

  /// One word for the graph node, e.g. "Hotels".
  final String role;
  final String description;
  final Color color;
  final IconData icon;

  /// Which Groq key this agent uses by default. Agents that share a slot
  /// share a key (2-3 per key); with fewer keys than slots the slot wraps.
  final int keySlot;
}
