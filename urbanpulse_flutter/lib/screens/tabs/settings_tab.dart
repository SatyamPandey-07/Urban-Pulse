import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../../core/config.dart';
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
        services.location,
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
            title: 'API Key & Provider Overrides',
            subtitle: AppConfig.hasAnyOverride
                ? 'Custom key overrides active'
                : 'Using embedded build keys (Groq, Tavily, TomTom)',
            icon: Icons.key_rounded,
            iconBg: const Color(0xFFCCFBF1),
            onTap: _showApiKeyOverridesSheet,
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

  Future<void> _showApiKeyOverridesSheet() async {
    final updated = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _ApiKeyOverridesSheet(),
    );
    if (updated == true && mounted) {
      setState(() {});
      showToast(context, 'API key overrides updated successfully');
    }
  }

  static String _accentLabel(AccentColor accent) =>
      '${accent.key[0].toUpperCase()}${accent.key.substring(1)}';
}

class _ApiKeyOverridesSheet extends StatefulWidget {
  const _ApiKeyOverridesSheet();

  @override
  State<_ApiKeyOverridesSheet> createState() => _ApiKeyOverridesSheetState();
}

class _ApiKeyOverridesSheetState extends State<_ApiKeyOverridesSheet> {
  late final TextEditingController _groqCtrl;
  late final TextEditingController _tavilyCtrl;
  late final TextEditingController _tomtomCtrl;
  late final TextEditingController _geoapifyCtrl;
  late final TextEditingController _xoteloCtrl;
  late final TextEditingController _centralRegistryCtrl;

  bool _obscureGroq = true;
  bool _obscureTavily = true;
  bool _obscureTomTom = true;
  bool _obscureGeoapify = true;
  bool _obscureXotelo = true;

  @override
  void initState() {
    super.initState();
    _groqCtrl = TextEditingController(
      text: AppConfig.getOverride(AppConfig.keyOverrideGroq) ?? '',
    );
    _tavilyCtrl = TextEditingController(
      text: AppConfig.getOverride(AppConfig.keyOverrideTavily) ?? '',
    );
    _tomtomCtrl = TextEditingController(
      text: AppConfig.getOverride(AppConfig.keyOverrideTomTom) ?? '',
    );
    _geoapifyCtrl = TextEditingController(
      text: AppConfig.getOverride(AppConfig.keyOverrideGeoapify) ?? '',
    );
    _xoteloCtrl = TextEditingController(
      text: AppConfig.getOverride(AppConfig.keyOverrideXotelo) ?? '',
    );
    _centralRegistryCtrl = TextEditingController(
      text: AppConfig.getOverride(AppConfig.keyOverrideCentralRegistry) ?? '',
    );
  }

  @override
  void dispose() {
    _groqCtrl.dispose();
    _tavilyCtrl.dispose();
    _tomtomCtrl.dispose();
    _geoapifyCtrl.dispose();
    _xoteloCtrl.dispose();
    _centralRegistryCtrl.dispose();
    super.dispose();
  }

  static String _mask(String? key) {
    if (key == null || key.isEmpty) return 'None (Not configured)';
    if (key.length <= 8) return '••••••••';
    return '${key.substring(0, 4)}••••••••${key.substring(key.length - 4)}';
  }

  Future<void> _saveAll() async {
    await AppConfig.setOverride(AppConfig.keyOverrideGroq, _groqCtrl.text);
    await AppConfig.setOverride(AppConfig.keyOverrideTavily, _tavilyCtrl.text);
    await AppConfig.setOverride(AppConfig.keyOverrideTomTom, _tomtomCtrl.text);
    await AppConfig.setOverride(
      AppConfig.keyOverrideGeoapify,
      _geoapifyCtrl.text,
    );
    await AppConfig.setOverride(AppConfig.keyOverrideXotelo, _xoteloCtrl.text);
    await AppConfig.setOverride(
      AppConfig.keyOverrideCentralRegistry,
      _centralRegistryCtrl.text,
    );

    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _resetAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset All Overrides?'),
        content: const Text(
          'This will clear all custom keys and immediately revert all services to their embedded build-time defaults.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.solidError,
            ),
            child: const Text('Reset All'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    await AppConfig.clearAllOverrides();
    setState(() {
      _groqCtrl.clear();
      _tavilyCtrl.clear();
      _tomtomCtrl.clear();
      _geoapifyCtrl.clear();
      _xoteloCtrl.clear();
      _centralRegistryCtrl.clear();
    });

    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  Widget _buildKeyField({
    required String title,
    required String subtitle,
    required TextEditingController controller,
    required String embeddedValue,
    required IconData icon,
    bool obscure = false,
    VoidCallback? onToggleObscure,
    String? hintText,
  }) {
    final theme = Theme.of(context);
    final hasCustom = controller.text.trim().isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasCustom
              ? AppColors.primaryGreen.withValues(alpha: 0.5)
              : AppColors.surfaceBorder,
          width: hasCustom ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color:
                      (hasCustom
                              ? AppColors.primaryGreen
                              : AppColors.primaryBlue)
                          .withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  size: 18,
                  color:
                      hasCustom
                          ? AppColors.primaryGreen
                          : AppColors.primaryBlue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color:
                      hasCustom
                          ? AppColors.primaryGreen.withValues(alpha: 0.2)
                          : Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  hasCustom ? 'OVERRIDE' : 'EMBEDDED',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color:
                        hasCustom
                            ? AppColors.primaryGreen
                            : AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Text(
                'Default build key: ',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textTertiary,
                ),
              ),
              Expanded(
                child: Text(
                  _mask(embeddedValue),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            obscureText: obscure,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(
              fontSize: 13,
              fontFamily: 'monospace',
              color: AppColors.textPrimary,
            ),
            decoration: InputDecoration(
              isDense: true,
              hintText: hintText ?? 'Paste override key or leave blank',
              hintStyle: const TextStyle(
                fontSize: 12,
                fontFamily: 'sans-serif',
                color: AppColors.textTertiary,
              ),
              filled: true,
              fillColor: AppColors.surfaceElevated,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.surfaceBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color:
                      hasCustom
                          ? AppColors.primaryGreen.withValues(alpha: 0.4)
                          : AppColors.surfaceBorder,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: AppColors.primaryGreen,
                  width: 1.5,
                ),
              ),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (controller.text.isNotEmpty)
                    IconButton(
                      icon: const Icon(
                        Icons.clear,
                        size: 16,
                        color: AppColors.textTertiary,
                      ),
                      tooltip: 'Clear override (revert to embedded)',
                      onPressed: () {
                        controller.clear();
                        setState(() {});
                      },
                    ),
                  if (onToggleObscure != null)
                    IconButton(
                      icon: Icon(
                        obscure
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                        size: 18,
                        color: AppColors.textSecondary,
                      ),
                      tooltip: obscure ? 'Show key' : 'Hide key',
                      onPressed: onToggleObscure,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    return Container(
      constraints: BoxConstraints(
        maxHeight: mediaQuery.size.height * 0.88,
      ),
      padding: EdgeInsets.only(
        bottom: mediaQuery.viewInsets.bottom,
      ),
      decoration: const BoxDecoration(
        color: AppColors.bgDark,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.surfaceBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primaryGreen.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.key_rounded,
                    color: AppColors.primaryGreen,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'API Key & Provider Overrides',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Active overrides replace embedded keys immediately without rebuilding.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.close_rounded,
                    color: AppColors.textSecondary,
                  ),
                  onPressed: () => Navigator.of(context).pop(false),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.surfaceBorder),
          // Scrollable Fields List
          Flexible(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              children: [
                _buildKeyField(
                  title: 'Groq Cloud API Key',
                  subtitle: 'Yatri AI autonomous planner & multi-model LLMs',
                  controller: _groqCtrl,
                  embeddedValue: AppConfig.embeddedGroqApiKey,
                  icon: Icons.psychology_rounded,
                  obscure: _obscureGroq,
                  onToggleObscure:
                      () => setState(() => _obscureGroq = !_obscureGroq),
                  hintText: 'gsk_...',
                ),
                _buildKeyField(
                  title: 'Tavily Search API Key',
                  subtitle:
                      'Live hotel intelligence, web search & current events',
                  controller: _tavilyCtrl,
                  embeddedValue: AppConfig.embeddedTavilyApiKey,
                  icon: Icons.travel_explore_rounded,
                  obscure: _obscureTavily,
                  onToggleObscure:
                      () => setState(() => _obscureTavily = !_obscureTavily),
                  hintText: 'tvly-...',
                ),
                _buildKeyField(
                  title: 'TomTom Map API Key',
                  subtitle: 'Real-time traffic, geocoding & step-free routing',
                  controller: _tomtomCtrl,
                  embeddedValue: AppConfig.embeddedTomTomApiKey,
                  icon: Icons.map_rounded,
                  obscure: _obscureTomTom,
                  onToggleObscure:
                      () => setState(() => _obscureTomTom = !_obscureTomTom),
                ),
                _buildKeyField(
                  title: 'Geoapify API Key',
                  subtitle: 'Places discovery, transit POIs & isochrones',
                  controller: _geoapifyCtrl,
                  embeddedValue: AppConfig.embeddedGeoapifyApiKey,
                  icon: Icons.explore_rounded,
                  obscure: _obscureGeoapify,
                  onToggleObscure:
                      () => setState(() => _obscureGeoapify = !_obscureGeoapify),
                ),
                _buildKeyField(
                  title: 'Xotelo / RapidAPI Key',
                  subtitle: 'Hotel real-time price comparison & availability',
                  controller: _xoteloCtrl,
                  embeddedValue: AppConfig.embeddedXoteloRapidApiKey,
                  icon: Icons.hotel_rounded,
                  obscure: _obscureXotelo,
                  onToggleObscure:
                      () => setState(() => _obscureXotelo = !_obscureXotelo),
                ),
                _buildKeyField(
                  title: 'Central Registry Base URL',
                  subtitle: 'Edge sync and multi-agent mesh coordination',
                  controller: _centralRegistryCtrl,
                  embeddedValue: AppConfig.embeddedCentralRegistryBaseUrl,
                  icon: Icons.dns_rounded,
                  obscure: false,
                  hintText: 'http://10.0.2.2:3001 or https://...',
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.surfaceBorder),
          // Action Buttons Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
            child: Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _resetAll,
                  icon: const Icon(Icons.restore_rounded, size: 18),
                  label: const Text('Reset All'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.solidError,
                    side: BorderSide(
                      color: AppColors.solidError.withValues(alpha: 0.5),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _saveAll,
                    icon: const Icon(Icons.check_circle_rounded, size: 18),
                    label: const Text(
                      'Save & Apply Overrides',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primaryGreen,
                      foregroundColor: const Color(0xFF0B1015),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
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
