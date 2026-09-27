import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/app_colors.dart';
import '../core/routes.dart';
import '../models/app_notification.dart';
import '../state/app_scope.dart';
import 'home_screen.dart';

/// The Notification Center for all in-app events: trips planned, itineraries ready,
/// trip-pool requests & approvals, badges unlocked, eco-points, and emergency alerts.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

enum _FilterCategory {
  all('All'),
  trips('Trips & Plans'),
  pool('Trip-Pool'),
  rewards('Rewards'),
  alerts('Alerts');

  const _FilterCategory(this.label);
  final String label;
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  _FilterCategory _filter = _FilterCategory.all;

  bool _matchesFilter(AppNotification n) {
    return switch (_filter) {
      _FilterCategory.all => true,
      _FilterCategory.trips => n.kind == NotificationKind.itinerary ||
          n.kind == NotificationKind.tripSaved ||
          n.kind == NotificationKind.tripUpdated,
      _FilterCategory.pool => n.kind == NotificationKind.poolRequest ||
          n.kind == NotificationKind.poolApproved ||
          n.kind == NotificationKind.poolDeclined,
      _FilterCategory.rewards => n.kind == NotificationKind.badge || n.kind == NotificationKind.ecoPoints,
      _FilterCategory.alerts => n.kind == NotificationKind.sos,
    };
  }

  void _onTap(AppNotification n) {
    final services = AppScope.of(context);
    services.notifications.markRead(n.id);

    final target = n.target;
    if (target.tabIndex != null) {
      Navigator.of(context).popUntil((r) => r.isFirst || r.settings.name == Routes.home);
      HomeScreen.selectTab(target.tabIndex!);
    } else if (target.route != null) {
      Navigator.of(context).pushNamed(target.route!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final controller = AppScope.of(context).notifications;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'Notifications',
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w800,
            fontSize: 20,
          ),
        ),
        actions: [
          AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              if (!controller.hasUnread) return const SizedBox.shrink();
              return TextButton.icon(
                onPressed: () => controller.markAllRead(),
                icon: const Icon(Icons.done_all_rounded, size: 18, color: AppColors.primaryGreen),
                label: Text(
                  'Mark all read',
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: AppColors.primaryGreen,
                  ),
                ),
              );
            },
          ),
          AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              if (controller.items.isEmpty) return const SizedBox.shrink();
              return PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded),
                onSelected: (val) {
                  if (val == 'clear') {
                    _confirmClearAll(context, controller);
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'clear',
                    child: Row(
                      children: [
                        Icon(Icons.delete_sweep_rounded, size: 20, color: AppColors.solidError),
                        SizedBox(width: 10),
                        Text('Clear all notifications', style: TextStyle(color: AppColors.solidError)),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final allItems = controller.items;
          final filteredItems = allItems.where(_matchesFilter).toList();

          return Column(
            children: [
              // Filter chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    for (final cat in _FilterCategory.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          selected: _filter == cat,
                          label: Text(
                            cat == _FilterCategory.all
                                ? 'All (${allItems.length})'
                                : cat.label,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              fontWeight: _filter == cat ? FontWeight.w700 : FontWeight.w500,
                            ),
                          ),
                          onSelected: (_) => setState(() => _filter = cat),
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),

              // Content list or empty state
              Expanded(
                child: filteredItems.isEmpty
                    ? _EmptyNotificationsView(filter: _filter)
                    : _NotificationList(
                        items: filteredItems,
                        onTap: _onTap,
                        onDismiss: (id) => controller.remove(id),
                        isDark: isDark,
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _confirmClearAll(BuildContext context, dynamic controller) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear all notifications?'),
        content: const Text('This will delete all past notifications from this device.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.solidError),
            onPressed: () {
              controller.clear();
              Navigator.of(ctx).pop();
            },
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
  }
}

class _NotificationList extends StatelessWidget {
  const _NotificationList({
    required this.items,
    required this.onTap,
    required this.onDismiss,
    required this.isDark,
  });

  final List<AppNotification> items;
  final ValueChanged<AppNotification> onTap;
  final ValueChanged<String> onDismiss;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    // Group items into Today, Yesterday, and Earlier
    final now = DateTime.now();
    final today = <AppNotification>[];
    final yesterday = <AppNotification>[];
    final earlier = <AppNotification>[];

    for (final item in items) {
      final diffDays = _daysBetween(item.at, now);
      if (diffDays == 0) {
        today.add(item);
      } else if (diffDays == 1) {
        yesterday.add(item);
      } else {
        earlier.add(item);
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        if (today.isNotEmpty) ...[
          _SectionHeader(title: 'Today', count: today.length),
          for (final n in today) _NotificationCard(notification: n, onTap: () => onTap(n), onDismiss: () => onDismiss(n.id), isDark: isDark),
        ],
        if (yesterday.isNotEmpty) ...[
          _SectionHeader(title: 'Yesterday', count: yesterday.length),
          for (final n in yesterday) _NotificationCard(notification: n, onTap: () => onTap(n), onDismiss: () => onDismiss(n.id), isDark: isDark),
        ],
        if (earlier.isNotEmpty) ...[
          _SectionHeader(title: 'Earlier', count: earlier.length),
          for (final n in earlier) _NotificationCard(notification: n, onTap: () => onTap(n), onDismiss: () => onDismiss(n.id), isDark: isDark),
        ],
      ],
    );
  }

  static int _daysBetween(DateTime from, DateTime to) {
    final fromDate = DateTime(from.year, from.month, from.day);
    final toDate = DateTime(to.year, to.month, to.day);
    return (toDate.difference(fromDate).inHours / 24).round();
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.count});
  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 8, left: 4, right: 4),
      child: Row(
        children: [
          Text(
            title,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.notification,
    required this.onTap,
    required this.onDismiss,
    required this.isDark,
  });

  final AppNotification notification;
  final VoidCallback onTap;
  final VoidCallback onDismiss;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final kind = notification.kind;
    final isUnread = !notification.read;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Dismissible(
        key: ValueKey('notif_${notification.id}'),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          decoration: BoxDecoration(
            color: AppColors.solidError.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
        ),
        onDismissed: (_) => onDismiss(),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isUnread
                    ? (isDark ? const Color(0xFF1E293B) : const Color(0xFFF0FDF4))
                    : (isDark ? const Color(0xFF16202C) : Colors.white),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isUnread
                      ? AppColors.primaryGreen.withValues(alpha: 0.35)
                      : (isDark ? const Color(0xFF243242) : const Color(0xFFE2E8F0)),
                  width: isUnread ? 1.4 : 1.0,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: kind.color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(kind.icon, size: 20, color: kind.color),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                notification.title,
                                style: GoogleFonts.plusJakartaSans(
                                  fontWeight: isUnread ? FontWeight.w800 : FontWeight.w600,
                                  fontSize: 14,
                                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _timeAgo(notification.at),
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 11,
                                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          notification.body,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12.5,
                            color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
                            height: 1.35,
                          ),
                        ),
                        if (notification.target.tabIndex != null || notification.target.route != null) ...[
                          const SizedBox(height: 8),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _actionLabel(notification),
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primaryGreen,
                                ),
                              ),
                              const SizedBox(width: 3),
                              const Icon(Icons.arrow_forward_rounded, size: 14, color: AppColors.primaryGreen),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (isUnread) ...[
                    const SizedBox(width: 8),
                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.only(top: 6),
                      decoration: const BoxDecoration(
                        color: AppColors.primaryGreen,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _actionLabel(AppNotification n) {
    if (n.kind == NotificationKind.itinerary) return 'View Itinerary';
    if (n.kind == NotificationKind.tripSaved || n.kind == NotificationKind.tripUpdated) return 'Open My Trips';
    if (n.kind == NotificationKind.poolRequest ||
        n.kind == NotificationKind.poolApproved ||
        n.kind == NotificationKind.poolDeclined) {
      return 'Open Trip-Pool';
    }
    if (n.kind == NotificationKind.badge) return 'View Badge';
    if (n.kind == NotificationKind.sos) return 'Open SOS Alert';
    return 'View Details';
  }

  static String _timeAgo(DateTime at) {
    final diff = DateTime.now().difference(at);
    if (diff.inSeconds < 45) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${at.day}/${at.month}/${at.year}';
  }
}

class _EmptyNotificationsView extends StatelessWidget {
  const _EmptyNotificationsView({required this.filter});
  final _FilterCategory filter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                shape: BoxShape.circle,
                border: Border.all(
                  color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                ),
              ),
              child: Icon(
                Icons.notifications_none_rounded,
                size: 36,
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              filter == _FilterCategory.all
                  ? 'All caught up'
                  : 'No ${filter.label.toLowerCase()} yet',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              filter == _FilterCategory.all
                  ? 'When trips are planned, itineraries are generated, or badges are unlocked, they will show up here.'
                  : 'Relevant updates for ${filter.label.toLowerCase()} will appear here when available.',
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
