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
      label: 'Dashboard',
    ),
    NavigationDestination(icon: Icon(Icons.map_outlined), label: 'Live Map'),
    NavigationDestination(icon: Icon(Icons.route_outlined), label: 'Trips'),
    NavigationDestination(
      icon: Icon(Icons.auto_awesome_outlined),
      label: 'Yatri AI',
    ),
    NavigationDestination(
      icon: Icon(Icons.settings_outlined),
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
              Icon(
                Icons.navigation,
                size: 20,
                color: theme.colorScheme.onSurface,
              ),
              const SizedBox(width: 8),
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
                            style: theme.textTheme.titleLarge?.copyWith(
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
                          const Icon(Icons.refresh, size: 18),
                      ],
                    ),
                    Text(
                      location.displaySubtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
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
          icon: const Icon(Icons.celebration),
          tooltip: 'Achievements',
          onPressed: () => Navigator.of(context).pushNamed(Routes.achievements),
        ),
        IconButton(
          icon: const Icon(Icons.sos, color: AppColors.sosRed),
          tooltip: 'SOS',
          onPressed: () => Navigator.of(context).pushNamed(Routes.sos),
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}
