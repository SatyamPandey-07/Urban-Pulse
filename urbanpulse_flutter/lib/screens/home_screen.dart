import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../core/routes.dart';
import '../state/app_scope.dart';
import 'tabs/dashboard_tab.dart';
import 'tabs/live_map_tab.dart';
import 'tabs/settings_tab.dart';
import 'tabs/trips_tab.dart';
import 'tabs/yatri_ai_tab.dart';

/// Lets a tab switch the shell to a sibling tab, replacing
/// `(activity as? MainActivity)?.switchToTab(n)`.
class HomeTabController extends InheritedWidget {
  const HomeTabController({
    required this.switchToTab,
    required super.child,
    super.key,
  });

  final void Function(int index) switchToTab;

  static HomeTabController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HomeTabController>();

  @override
  bool updateShouldNotify(HomeTabController oldWidget) => false;
}

/// Port of `MainActivity` / `activity_main.xml`: a location header with the
/// Achievements and SOS actions, five tabs in a bottom navigation bar, and the
/// pages kept alive between switches (the original disabled ViewPager2 swiping,
/// so an [IndexedStack] is the faithful equivalent).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  static const _pages = <Widget>[
    DashboardTab(),
    LiveMapTab(),
    TripsTab(),
    YatriAiTab(),
    SettingsTab(),
  ];

  static const _destinations = <NavigationDestination>[
    NavigationDestination(
      icon: Icon(Icons.dashboard_outlined),
      selectedIcon: Icon(Icons.dashboard_rounded),
      label: 'Dashboard',
    ),
    NavigationDestination(
      icon: Icon(Icons.map_outlined),
      selectedIcon: Icon(Icons.map_rounded),
      label: 'Live Map',
    ),
    NavigationDestination(
      icon: Icon(Icons.alt_route_outlined),
      selectedIcon: Icon(Icons.alt_route_rounded),
      label: 'Trips',
    ),
    NavigationDestination(
      icon: Icon(Icons.auto_awesome_outlined),
      selectedIcon: Icon(Icons.auto_awesome_rounded),
      label: 'Yatri AI',
    ),
    NavigationDestination(
      icon: Icon(Icons.settings_outlined),
      selectedIcon: Icon(Icons.settings_rounded),
      label: 'Settings',
    ),
  ];

  void _switchToTab(int index) {
    if (index < 0 || index >= _pages.length) return;
    setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    return HomeTabController(
      switchToTab: _switchToTab,
      child: Scaffold(
        appBar: const _LocationAppBar(),
        body: SafeArea(
          top: false,
          child: IndexedStack(index: _index, children: _pages),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: _switchToTab,
          destinations: _destinations,
        ),
      ),
    );
  }
}

/// Shows where the traveler actually is. The Kotlin `MainActivity` wrote
/// "Mumbai" / "Maharashtra, India" into the header unconditionally; this reads
/// the resolved GPS place and shows an honest status while it is pending or
/// unavailable. Tapping it re-resolves.
class _LocationAppBar extends StatefulWidget implements PreferredSizeWidget {
  const _LocationAppBar();

  @override
  Size get preferredSize => const Size.fromHeight(72);

  @override
  State<_LocationAppBar> createState() => _LocationAppBarState();
}

class _LocationAppBarState extends State<_LocationAppBar> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => AppScope.of(context).location.resolve(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final location = AppScope.of(context).location;
    return AppBar(
      toolbarHeight: 72,
      titleSpacing: 16,
      title: AnimatedBuilder(
        animation: location,
        builder: (context, _) => InkWell(
          onTap: () => location.resolve(force: true),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.near_me_rounded,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            location.displayTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (location.isResolving)
                          const Padding(
                            padding: EdgeInsets.only(left: 8),
                            child: SizedBox.square(
                              dimension: 12,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        else
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Icon(
                              Icons.sync_rounded,
                              size: 15,
                              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                            ),
                          ),
                      ],
                    ),
                    Text(
                      location.displaySubtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        IconButton(
          icon: Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.military_tech_outlined,
              size: 18,
              color: theme.colorScheme.primary,
            ),
          ),
          tooltip: 'Achievements',
          onPressed: () => Navigator.of(context).pushNamed(Routes.achievements),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 4, right: 12),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => Navigator.of(context).pushNamed(Routes.sos),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.sosRed, AppColors.sosDeepRed],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.sosRed.withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.emergency_outlined, size: 15, color: Colors.white),
                    SizedBox(width: 4),
                    Text(
                      'SOS',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
