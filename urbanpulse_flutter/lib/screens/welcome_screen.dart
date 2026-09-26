import 'package:flutter/material.dart';

import '../core/routes.dart';
import '../state/app_scope.dart';
import '../state/auth_controller.dart';
import '../widgets/common.dart';
import '../widgets/urbanpulse_logo.dart';

/// Port of `WelcomeActivity` / `activity_welcome.xml`.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  Future<void> _enterDemo(BuildContext context) async {
    final auth = AppScope.of(context).auth;
    final navigator = Navigator.of(context);
    final result = await auth.signIn(email: AuthController.demoEmail, password: AuthController.demoPassword);
    if (!context.mounted) return;
    if (result is AuthFailed) {
      showToast(context, result.message);
      return;
    }
    showToast(context, 'Welcome! Logged in as Demo Explorer.');
    navigator.pushNamedAndRemoveUntil(Routes.home, (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const UrbanPulseLogo(size: 140),
                const SizedBox(height: 32),
                Text(
                  'UrbanPulse',
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Smart Sustainable & Accessible Travel Platform',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 40),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton(
                    onPressed: () =>
                        Navigator.of(context).pushNamed(Routes.signup),
                    child: const Text('Get Started'),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton.tonal(
                    onPressed: () =>
                        Navigator.of(context).pushNamed(Routes.login),
                    child: const Text('Sign In'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: TextButton.icon(
                    onPressed: () => _enterDemo(context),
                    icon: const Icon(Icons.celebration),
                    label: const Text('1-Tap Demo / Judge Access'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
