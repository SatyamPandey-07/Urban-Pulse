import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/app_theme.dart';
import 'core/config.dart';
import 'core/routes.dart';
import 'state/app_scope.dart';
import 'widgets/sos_overlay.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // `UrbanPulseApplication.onCreate` eagerly initialised the preference-backed
  // managers; doing it here keeps every controller synchronous at call sites.
  final prefs = await SharedPreferences.getInstance();
  await AppConfig.loadOverrides(prefs);
  // Real accounts and cloud storage when the project is configured; the
  // Supabase client keeps the session across launches.
  SupabaseClient? supabase;
  if (AppConfig.hasSupabase) {
    try {
      supabase = (await Supabase.initialize(url: AppConfig.supabaseUrl, publishableKey: AppConfig.supabaseKey)).client;
    } catch (_) {
      supabase = null; // the app still runs, on the device only
    }
  }
  final services = AppServices(prefs, supabase: supabase);
  // Before sign-in resumes: restores an SOS from before a restart and takes a
  // power-button SOS that started the app.
  unawaited(services.sos.init());
  runApp(UrbanPulseApp(services: services));
  // A kept session: bring the traveller's data up to date in the background.
  unawaited(services.auth.resume());
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
            navigatorKey: services.navigatorKey,
            initialRoute: Routes.splash,
            routes: Routes.table,
            onGenerateRoute: Routes.onGenerateRoute,
            // Your active SOS, and alerts from people nearby, on every screen.
            builder: (context, child) => SosOverlay(child: child ?? const SizedBox.shrink()),
          );
        },
      ),
    );
  }
}
