import 'dart:async';

import 'package:flutter/material.dart';

import '../core/routes.dart';
import '../state/app_scope.dart';
import '../widgets/urbanpulse_logo.dart';

/// Logo hold, then straight on to Welcome — the 1200ms delay from
/// `SplashActivity`. A session that is already signed in skips to Home.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      final isLoggedIn = AppScope.of(context).auth.isLoggedIn;
      Navigator.of(context)
          .pushReplacementNamed(isLoggedIn ? Routes.home : Routes.welcome);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const UrbanPulseLogo(size: 140),
              const SizedBox(height: 24),
              Text(
                'UrbanPulse',
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
