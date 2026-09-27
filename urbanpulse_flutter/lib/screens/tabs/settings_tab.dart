import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../../core/formatting.dart';
import '../../core/routes.dart';
import '../../services/watch_sync_service.dart';
import '../../state/app_scope.dart';
import '../../widgets/common.dart';

/// Port of `SettingsFragment` / `fragment_settings.xml` + `item_setting_option.xml`.
class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key});

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final theme = Theme.of(context);

    return AnimatedBuilder(
      animation: Listenable.merge([
        services.accessibility,
        services.gamification,
        services.theme,
        services.location,
        services.watch,
      ]),
      builder: (context, _) {
        final wheelchairStatus = services.accessibility.isWheelchairModeEnabled
            ? 'Active (Step-Free Rerouting)'
            : 'Disabled';
        final co2Kg = services.gamification.co2SavedGrams / 1000.0;

        final items = <_SettingItem>[
          _SettingItem(
            title: 'Inclusive Accessibility Profile',
            subtitle: 'Wheelchair: $wheelchairStatus, Visual & Hearing alerts',
            icon: Icons.accessible_forward_rounded,
            iconBg: const Color(0xFFE0E7FF),
            onTap: _showAccessibilityDialog,
          ),
          _SettingItem(
            title: 'Green Travel Passport',
            subtitle:
                '${fixed(co2Kg)} kg CO2 saved • '
                'Level ${services.gamification.level} Explorer',
            icon: Icons.eco_rounded,
            iconBg: const Color(0xFFD1FAE5),
            onTap: () => Navigator.of(context).pushNamed(Routes.carbonWallet),
          ),
          _SettingItem(
            title: 'Sustainable & Inclusive Stays',
            subtitle: 'Verified solar hotels & accessibility audits',
            icon: Icons.hotel_outlined,
            iconBg: const Color(0xFFE0F2FE),
            onTap: () => Navigator.of(context).pushNamed(Routes.hospitality),
          ),
          _SettingItem(
            title: 'Multimodal Green Route Planner',
            subtitle: 'Metro, EV cab, bus emissions tradeoff',
            icon: Icons.alt_route_rounded,
            iconBg: const Color(0xFFFEF3C7),
            onTap: () =>
                Navigator.of(context).pushNamed(Routes.greenRoutePlanner),
          ),
          _SettingItem(
            title: 'AI Eco & Inclusive Itinerary',
            subtitle: 'Personalized step-free & low-carbon plans',
            icon: Icons.auto_awesome_rounded,
            iconBg: const Color(0xFFFFE4E6),
            onTap: () => Navigator.of(context).pushNamed(Routes.itinerary),
          ),
          _SettingItem(
            title: 'Hotel Resource & Waste Hub',
            subtitle: 'Energy, water, food surplus & ESG compliance',
            icon: Icons.recycling_rounded,
            iconBg: const Color(0xFFF3E8FF),
            onTap: () => Navigator.of(context).pushNamed(Routes.hotelOptimizer),
          ),
          _SettingItem(
            title: 'Garmin Watch',
            subtitle: _watchSubtitle(services.watch),
            icon: Icons.watch_outlined,
            iconBg: const Color(0xFFDBEAFE),
            onTap: _showWatchDialog,
          ),
          _SettingItem(
            title: 'Appearance & Accent',
            subtitle:
                'Theme: ${_accentLabel(services.theme.accent)} • Follows system settings',
            icon: Icons.wb_sunny_rounded,
            iconBg: const Color(0xFFFEF9C3),
            onTap: _showAccentDialog,
          ),
          _SettingItem(
            title: 'Detected Location',
            subtitle: services.location.hasFix
                ? '${services.location.displayTitle} • ${services.location.displaySubtitle}'
                : 'Panvel • Maharashtra, India',
            icon: Icons.location_on_rounded,
            iconBg: const Color(0xFFF1F5F9),
            onTap: () => services.location.resolve(force: true),
          ),
          _SettingItem(
            title: 'Sign Out',
            subtitle: services.auth.userEmail.isEmpty
                ? 'demo.traveler@urbanpulse.ai'
                : services.auth.userEmail,
            icon: Icons.logout_rounded,
            iconBg: const Color(0xFFFEE2E2),
            onTap: _signOut,
          ),
        ];

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          itemCount: items.length + 1,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            if (index == 0) {
              return Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Settings',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Personalize your inclusive & sustainable travel experience',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              );
            }
            return _settingRow(context, items[index - 1]);
          },
        );
      },
    );
  }

  Widget _settingRow(BuildContext context, _SettingItem item) {
    final theme = Theme.of(context);
    return SectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      onTap:
          item.onTap ??
          () => showToast(context, '${item.title} configuration active'),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: item.iconBg,
              shape: BoxShape.circle,
            ),
            child: Icon(item.icon, size: 20, color: const Color(0xFF1C1B1F)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (item.subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    item.subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
        ],
      ),
    );
  }

  Future<void> _showAccessibilityDialog() async {
    final accessibility = AppScope.of(context).accessibility;
    // Edit a local copy, then commit on Save — matching the Kotlin dialog's
    // "Save Preferences" / "Cancel" pair.
    var wheelchair = accessibility.isWheelchairModeEnabled;
    var visual = accessibility.isVisualAssistanceEnabled;
    var hearing = accessibility.isHearingAssistanceEnabled;
    var serviceAnimal = accessibility.isServiceAnimalFriendlyOnly;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Inclusive Accessibility Preferences'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Wheelchair / Step-Free Preference'),
                value: wheelchair,
                onChanged: (v) => setDialogState(() => wheelchair = v ?? false),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('High-Contrast & Large Badges'),
                value: visual,
                onChanged: (v) => setDialogState(() => visual = v ?? false),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Hearing & Visual Flash Alerts'),
                value: hearing,
                onChanged: (v) => setDialogState(() => hearing = v ?? false),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Service Animal Friendly Only'),
                value: serviceAnimal,
                onChanged: (v) =>
                    setDialogState(() => serviceAnimal = v ?? false),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Save Preferences'),
            ),
          ],
        ),
      ),
    );

    if (saved != true || !mounted) return;
    await accessibility.setWheelchairMode(wheelchair);
    await accessibility.setVisualAssistance(visual);
    await accessibility.setHearingAssistance(hearing);
    await accessibility.setServiceAnimalFriendlyOnly(serviceAnimal);
    if (!mounted) return;
    showToast(
      context,
      'Accessibility preferences updated & synced with Yatri AI.',
    );
  }

  static String _watchSubtitle(WatchSyncService watch) {
    if (!watch.isEnabled) return 'Off • itineraries stay on the phone';
    final what = watch.lastSentSummary;
    if (watch.state == WatchSyncState.failed) {
      return watch.lastError ?? 'Last send failed';
    }
    return what == null
        ? 'Code ${watch.pairingCode} • no plan sent yet'
        : 'Code ${watch.pairingCode} • showing $what';
  }

  /// The pairing ceremony, in full: read the code here, type it into the watch
  /// app's settings in Garmin Connect once. Every itinerary the agents finish
  /// then lands on the watch on its own.
  Future<void> _showWatchDialog() async {
    final watch = AppScope.of(context).watch;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Garmin Watch'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Open Garmin Connect → Urban Pulse → Settings and enter this '
                'pairing code. Finished itineraries then appear on the watch by '
                'themselves.',
              ),
              const SizedBox(height: 16),
              Center(
                child: SelectableText(
                  watch.pairingCode,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 6,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Send plans to the watch'),
                value: watch.isEnabled,
                onChanged: (v) async {
                  await watch.setEnabled(v);
                  setDialogState(() {});
                },
              ),
              if (watch.lastSentSummary != null)
                Text(
                  'On the watch: ${watch.lastSentSummary}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              if (watch.lastError != null)
                Text(
                  watch.lastError!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await watch.unpublish();
                await watch.regenerateCode();
                setDialogState(() {});
              },
              child: const Text('New code'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _showAccentDialog() async {
    final themeController = AppScope.of(context).theme;
    final chosen = await showDialog<AccentColor>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Choose Accent Color'),
        children: [
          for (final accent in AccentColor.values)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(accent),
              child: Row(
                children: [
                  CircleAvatar(radius: 10, backgroundColor: accent.seed),
                  const SizedBox(width: 12),
                  Text(_accentLabel(accent)),
                  if (accent == themeController.accent) ...[
                    const Spacer(),
                    const Icon(Icons.check, size: 18),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
    if (chosen != null) await themeController.setAccent(chosen);
  }

  Future<void> _signOut() async {
    final services = AppScope.of(context);
    final navigator = Navigator.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text(
          'End this session and return to the welcome screen?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await services.auth.signOut();
    navigator.pushNamedAndRemoveUntil(Routes.welcome, (route) => false);
  }

  static String _accentLabel(AccentColor accent) =>
      '${accent.key[0].toUpperCase()}${accent.key.substring(1)}';
}

class _SettingItem {
  const _SettingItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconBg,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconBg;
  final VoidCallback? onTap;
}
