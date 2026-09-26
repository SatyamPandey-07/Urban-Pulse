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
      icon: Icon(Icons.home_outlined),
      selectedIcon: Icon(Icons.home_rounded),
      label: 'Home',
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
          borderRadius: BorderRadius.circular(16),
          onTap: () => location.resolve(force: true),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.primaryGreen,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryGreen.withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.location_on_rounded,
                  size: 20,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 10),
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
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        const SizedBox(width: 2),
                        Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 18,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        if (location.isResolving)
                          const Padding(
                            padding: EdgeInsets.only(left: 6),
                            child: SizedBox.square(
                              dimension: 12,
                              child: CircularProgressIndicator(strokeWidth: 2),
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
                        fontSize: 11,
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
        Stack(
          alignment: Alignment.center,
          children: [
            IconButton(
              icon: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLow,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant,
                    width: 1,
                  ),
                ),
                child: Icon(
                  Icons.notifications_none_rounded,
                  size: 20,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              tooltip: 'Notifications & Achievements',
              onPressed: () => Navigator.of(context).pushNamed(Routes.achievements),
            ),
            Positioned(
              top: 16,
              right: 14,
              child: Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppColors.solidError,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(right: 14),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => Navigator.of(context).pushNamed(Routes.carbonWallet),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.primaryGreen.withValues(alpha: 0.5),
                  width: 1.5,
                ),
                image: const DecorationImage(
                  image: NetworkImage('https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=100&fit=crop&q=80'),
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
