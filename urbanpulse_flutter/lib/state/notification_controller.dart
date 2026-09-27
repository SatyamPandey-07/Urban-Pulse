import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_notification.dart';
import '../models/gamification.dart';

/// The in-app notification feed: trips planned, itineraries ready, trips
/// saved, Trip-pool requests and their answers, SOS alerts nearby, badges
/// unlocked. Kept on the device, newest first, capped at [_max] entries, and
/// cleared when the signed-in account changes (so a shared or reused phone
/// never shows one traveller's activity to the next).
class NotificationController extends ChangeNotifier {
  NotificationController(this._prefs) {
    _load();
  }

  static const _key = 'notifications.feed.v1';
  static const _keySeenBadges = 'notifications.seen_badges.v1';
  static const _max = 200;

  final SharedPreferences _prefs;
  final List<AppNotification> _items = [];
  final StreamController<AppNotification> _stream = StreamController<AppNotification>.broadcast();

  List<AppNotification> get items => List.unmodifiable(_items);
  int get unreadCount => _items.where((n) => !n.read).length;
  bool get hasUnread => unreadCount > 0;

  /// Broadcast stream fired in real-time whenever an in-app notification is added.
  Stream<AppNotification> get onNotification => _stream.stream;

  void _load() {
    final raw = _prefs.getString(_key);
    if (raw == null) return;
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      _items.addAll([for (final e in list) if (AppNotification.fromJson(e) case final n?) n]);
    } catch (_) {
      // a damaged store just starts empty
    }
  }

  Future<void> _save() async {
    await _prefs.setString(_key, jsonEncode([for (final n in _items) n.toJson()]));
  }

  /// Adds one entry to the top of the feed and emits to live in-app listeners.
  Future<void> add({
    required NotificationKind kind,
    required String title,
    required String body,
    NotificationTarget target = const NotificationTarget.none(),
  }) async {
    final notif = AppNotification(
      id: '${DateTime.now().microsecondsSinceEpoch}',
      kind: kind,
      title: title,
      body: body,
      at: DateTime.now(),
      target: target,
    );
    _items.insert(0, notif);
    if (_items.length > _max) _items.removeRange(_max, _items.length);
    await _save();
    _stream.add(notif);
    notifyListeners();
  }

  Future<void> markRead(String id) async {
    final n = _items.where((n) => n.id == id).firstOrNull;
    if (n == null || n.read) return;
    n.read = true;
    await _save();
    notifyListeners();
  }

  Future<void> markAllRead() async {
    if (!hasUnread) return;
    for (final n in _items) {
      n.read = true;
    }
    await _save();
    notifyListeners();
  }

  Future<void> remove(String id) async {
    _items.removeWhere((n) => n.id == id);
    await _save();
    notifyListeners();
  }

  Future<void> clear() async {
    _items.clear();
    await _prefs.remove(_key);
    await _prefs.remove(_keySeenBadges);
    notifyListeners();
  }

  /// Compares [badges] against what has already been notified about, and adds
  /// one entry per newly unlocked badge. Safe to call on every gamification
  /// change: a badge already seen is never repeated.
  Future<void> checkNewBadges(List<AchievementBadge> badges) async {
    final seen = (_prefs.getStringList(_keySeenBadges) ?? const []).toSet();
    final unlocked = {for (final b in badges) if (b.isUnlocked) b.id};
    final justUnlocked = unlocked.difference(seen);
    if (justUnlocked.isEmpty) {
      // Still persist the first time, so pre-existing unlocks are not all
      // announced at once the first time this ever runs.
      if (seen.isEmpty && unlocked.isNotEmpty) await _prefs.setStringList(_keySeenBadges, unlocked.toList());
      return;
    }
    if (seen.isEmpty) {
      // First run: record every currently-unlocked badge as already known,
      // rather than flooding the feed with everything unlocked historically.
      await _prefs.setStringList(_keySeenBadges, unlocked.toList());
      return;
    }
    for (final id in justUnlocked) {
      final badge = badges.firstWhere((b) => b.id == id);
      await add(
        kind: NotificationKind.badge,
        title: 'New badge: ${badge.title}',
        body: badge.description,
        target: const NotificationTarget.route('/achievements'),
      );
    }
    await _prefs.setStringList(_keySeenBadges, unlocked.toList());
  }

  @override
  void dispose() {
    _stream.close();
    super.dispose();
  }
}
