import 'package:flutter/material.dart';

/// What an [AppNotification] is about — decides its icon, colour and, in the
/// notifications screen, where tapping it goes.
enum NotificationKind {
  itinerary('itinerary'),
  tripSaved('trip_saved'),
  tripUpdated('trip_updated'),
  poolRequest('pool_request'),
  poolApproved('pool_approved'),
  poolDeclined('pool_declined'),
  ecoPoints('eco_points'),
  sos('sos'),
  badge('badge'),
  general('general');

  const NotificationKind(this.wire);

  final String wire;

  static NotificationKind parse(Object? v) => NotificationKind.values.firstWhere((k) => k.wire == v, orElse: () => NotificationKind.general);

  IconData get icon => switch (this) {
    NotificationKind.itinerary => Icons.auto_awesome_rounded,
    NotificationKind.tripSaved => Icons.bookmark_added_rounded,
    NotificationKind.tripUpdated => Icons.edit_calendar_rounded,
    NotificationKind.poolRequest => Icons.directions_car_filled_rounded,
    NotificationKind.poolApproved => Icons.check_circle_rounded,
    NotificationKind.poolDeclined => Icons.cancel_rounded,
    NotificationKind.ecoPoints => Icons.eco_rounded,
    NotificationKind.sos => Icons.sos_rounded,
    NotificationKind.badge => Icons.military_tech_rounded,
    NotificationKind.general => Icons.notifications_rounded,
  };

  Color get color => switch (this) {
    NotificationKind.itinerary => const Color(0xFF10B981),
    NotificationKind.tripSaved => const Color(0xFF059669),
    NotificationKind.tripUpdated => const Color(0xFF0D9488),
    NotificationKind.poolRequest => const Color(0xFFF59E0B),
    NotificationKind.poolApproved => const Color(0xFF16A34A),
    NotificationKind.poolDeclined => const Color(0xFF64748B),
    NotificationKind.ecoPoints => const Color(0xFF10B981),
    NotificationKind.sos => const Color(0xFFDC2626),
    NotificationKind.badge => const Color(0xFFEAB308),
    NotificationKind.general => const Color(0xFF64748B),
  };
}

/// Where tapping a notification goes: one of the home tabs, or a pushed route.
class NotificationTarget {
  const NotificationTarget.tab(this.tabIndex) : route = null;
  const NotificationTarget.route(String this.route) : tabIndex = null;
  const NotificationTarget.none() : tabIndex = null, route = null;

  final int? tabIndex;
  final String? route;

  Map<String, Object?> toJson() => {'tab': tabIndex, 'route': route};

  static NotificationTarget fromJson(Object? j) {
    if (j is! Map) return const NotificationTarget.none();
    final tab = j['tab'];
    if (tab is num) return NotificationTarget.tab(tab.toInt());
    final route = j['route'];
    if (route is String && route.isNotEmpty) return NotificationTarget.route(route);
    return const NotificationTarget.none();
  }
}

/// One entry in the in-app notification feed: a trip planned, an itinerary
/// ready, a Trip-pool request, an SOS nearby, a badge unlocked, and so on.
/// Kept on the device (`NotificationController`), newest first.
class AppNotification {
  AppNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.at,
    this.target = const NotificationTarget.none(),
    this.read = false,
  });

  final String id;
  final NotificationKind kind;
  final String title;
  final String body;
  final DateTime at;
  final NotificationTarget target;
  bool read;

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.wire,
    'title': title,
    'body': body,
    'at': at.toIso8601String(),
    'target': target.toJson(),
    'read': read,
  };

  static AppNotification? fromJson(Object? j) {
    if (j is! Map<String, dynamic>) return null;
    final id = j['id'];
    final at = DateTime.tryParse('${j['at']}');
    if (id is! String || at == null) return null;
    return AppNotification(
      id: id,
      kind: NotificationKind.parse(j['kind']),
      title: '${j['title'] ?? ''}',
      body: '${j['body'] ?? ''}',
      at: at,
      target: NotificationTarget.fromJson(j['target']),
      read: j['read'] == true,
    );
  }
}
