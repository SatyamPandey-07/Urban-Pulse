import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/app_theme.dart';
import 'core/routes.dart';
import 'state/app_scope.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // `UrbanPulseApplication.onCreate` eagerly initialised the preference-backed
  // managers; doing it here keeps every controller synchronous at call sites.
  final prefs = await SharedPreferences.getInstance();
  runApp(UrbanPulseApp(services: AppServices(prefs)));
}

class UrbanPulseApp extends StatelessWidget {
  const UrbanPulseApp({required this.services, super.key});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      services: services,
      child: AnimatedBuilder(
        animation: services.theme,
        builder: (context, _) {
          final accent = services.theme.accent;
          return MaterialApp(
            title: 'UrbanPulse',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(accent),
            darkTheme: AppTheme.dark(accent),
            // `Theme.Material3.DayNight` — follow the device setting.
            themeMode: ThemeMode.system,
            initialRoute: Routes.splash,
            routes: Routes.table,
            onGenerateRoute: Routes.onGenerateRoute,
          );
        },
      ),
    );
  }
}
