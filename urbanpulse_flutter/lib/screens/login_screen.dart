import 'package:flutter/material.dart';

import '../core/routes.dart';
import '../state/app_scope.dart';
import '../state/auth_controller.dart';
import '../widgets/common.dart';
import '../widgets/urbanpulse_logo.dart';

/// Port of `LoginActivity` / `activity_login.xml`.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscurePassword = true;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _performLogin(String email, String password) async {
    if (_busy) return;
    final auth = AppScope.of(context).auth;
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    final result = await auth.signIn(email: email, password: password);
    if (!mounted) return;
    setState(() => _busy = false);
    switch (result) {
      case AuthOk():
        showToast(context, auth.usesAccounts ? 'Signed in as $email' : 'Logged in as $email (on this device only)');
        navigator.pushNamedAndRemoveUntil(Routes.home, (route) => false);
      case AuthNeedsConfirmation():
        showToast(context, 'Please confirm your email first: check your inbox for the link.');
      case AuthFailed(:final message):
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Login Failed'),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
    }
  }

  Future<void> _onSignInPressed() async {
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || password.isEmpty) {
      showToast(context, 'Please enter email and password');
      return;
    }
    await _performLogin(email, password);
  }

  Future<void> _onDemoLoginPressed() async {
    _email.text = AuthController.demoEmail;
    _password.text = AuthController.demoPassword;
    await _performLogin(AuthController.demoEmail, AuthController.demoPassword);
  }

  Future<void> _onForgotPassword() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      showToast(context, 'Enter your email above, then tap Forgot password');
      return;
    }
    final result = await AppScope.of(context).auth.resetPassword(email);
    if (!mounted) return;
    showToast(context, switch (result) {
      AuthFailed(:final message) => message,
      _ => 'If $email has an account, a reset link is on its way.',
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 24),
              const UrbanPulseLogo(size: 96),
              const SizedBox(height: 20),
              Text(
                'Welcome Back',
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Sign in to continue your green journey',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 28),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _password,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _onSignInPressed(),
                decoration: InputDecoration(
                  labelText: 'Password',
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                    ),
                    tooltip: _obscurePassword
                        ? 'Show password'
                        : 'Hide password',
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  onPressed: _busy ? null : _onSignInPressed,
                  child: _busy
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                      : const Text('Sign In'),
                ),
              ),
              if (AppScope.of(context).auth.usesAccounts)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(onPressed: _busy ? null : _onForgotPassword, child: const Text('Forgot password?')),
                ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton.tonalIcon(
                  onPressed: _busy ? null : _onDemoLoginPressed,
                  icon: const Icon(Icons.celebration),
                  label: const Text('1-Tap Demo Login (Judge / Guest Mode)'),
                ),
              ),
              const SizedBox(height: 20),
              TextButton(
                onPressed: () =>
                    Navigator.of(context).pushReplacementNamed(Routes.signup),
                child: const Text("Don't have an account? Sign Up"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
