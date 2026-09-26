import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../../core/formatting.dart';
import '../../core/routes.dart';
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
            icon: Icons.accessible,
            iconBg: const Color(0xFFD3E3FD),
            onTap: _showAccessibilityDialog,
          ),
          _SettingItem(
            title: 'Green Travel Passport',
            subtitle:
                '${fixed(co2Kg)} kg CO2 saved • '
                'Level ${services.gamification.level} Explorer',
            icon: Icons.card_travel,
            iconBg: const Color(0xFFC3E7A1),
            onTap: () => Navigator.of(context).pushNamed(Routes.carbonWallet),
          ),
          _SettingItem(
            title: 'Sustainable & Inclusive Stays',
            subtitle: 'Verified solar hotels, zero-waste resorts & accessibility audits',
            icon: Icons.hotel_outlined,
            iconBg: const Color(0xFFA7F3D0),
            onTap: () => Navigator.of(context).pushNamed(Routes.hospitality),
          ),
          _SettingItem(
            title: 'Multimodal Green Route Planner',
            subtitle: 'Tradeoff optimizer for Metro, EV Cab, and bus emissions',
            icon: Icons.alt_route,
            iconBg: const Color(0xFFFDE293),
            onTap: () =>
                Navigator.of(context).pushNamed(Routes.greenRoutePlanner),
          ),
          _SettingItem(
            title: 'AI Eco & Inclusive Itinerary',
            subtitle: 'Personalized step-free & low-carbon day itineraries',
            icon: Icons.celebration_outlined,
            iconBg: const Color(0xFFFED7AA),
            onTap: () => Navigator.of(context).pushNamed(Routes.itinerary),
          ),
          _SettingItem(
            title: 'Hotel Resource & Waste Hub',
            subtitle: 'B2B Energy, Water, food surplus & ESG compliance',
            icon: Icons.insights_outlined,
            iconBg: const Color(0xFFFBCFE8),
            onTap: () => Navigator.of(context).pushNamed(Routes.hotelOptimizer),
          ),
          _SettingItem(
            title: 'Appearance & Accent',
            subtitle:
                'Accent: ${_accentLabel(services.theme.accent)} • '
                'Theme follows the system',
            icon: Icons.light_mode_outlined,
            iconBg: const Color(0xFFFDE293),
            onTap: _showAccentDialog,
          ),
          _SettingItem(
            title: 'Default City Hub',
            subtitle: 'Mumbai, Maharashtra, India',
            icon: Icons.location_on_outlined,
            iconBg: const Color(0xFFD3E3FD),
            onTap: null,
          ),
          _SettingItem(
            title: 'Measurement Units',
            subtitle: 'Metric (°C, km/h, kg CO2e)',
            icon: Icons.straighten,
            iconBg: const Color(0xFFF8D7DA),
            onTap: null,
          ),
          _SettingItem(
            title: 'Language',
            subtitle: 'English',
            icon: Icons.translate,
            iconBg: const Color(0xFFE9D5FF),
            onTap: null,
          ),
          _SettingItem(
            title: 'Sign Out',
            subtitle: services.auth.userEmail.isEmpty
                ? 'End this session'
                : 'Signed in as ${services.auth.userEmail}',
            icon: Icons.logout,
            iconBg: const Color(0xFFFECACA),
            onTap: _signOut,
          ),
        ];

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          itemCount: items.length + 1,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            if (index == 0) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Settings',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
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
