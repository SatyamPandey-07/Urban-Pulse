import 'package:flutter/material.dart';

import '../core/routes.dart';
import '../state/app_scope.dart';
import '../widgets/common.dart';
import '../widgets/urbanpulse_logo.dart';

/// Port of `SignUpActivity` / `activity_signup.xml`.
class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();

  /// Equivalent of `android.util.Patterns.EMAIL_ADDRESS`.
  static final _emailPattern = RegExp(r"^[\w.+\-']+@[\w\-]+(\.[\w\-]+)+$");

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _onSignUpPressed() async {
    final firstName = _firstName.text.trim();
    final lastName = _lastName.text.trim();
    final email = _email.text.trim();
    final password = _password.text;
    final confirmPassword = _confirmPassword.text;

    if (firstName.isEmpty || email.isEmpty || password.isEmpty) {
      showToast(context, 'Please fill in all required fields');
      return;
    }
    if (!_emailPattern.hasMatch(email)) {
      showToast(context, 'Please enter a valid email address');
      return;
    }
    if (password.length < 6) {
      showToast(context, 'Password must be at least 6 characters');
      return;
    }
    if (password != confirmPassword) {
      showToast(context, 'Passwords do not match');
      return;
    }

    final fullName = lastName.isNotEmpty ? '$firstName $lastName' : firstName;
    final navigator = Navigator.of(context);
    await AppScope.of(context).auth.signUp(fullName: fullName, email: email);

    if (!mounted) return;
    showToast(context, 'Account created successfully! Welcome, $firstName');
    navigator.pushNamedAndRemoveUntil(Routes.home, (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            children: [
              const SizedBox(height: 16),
              const UrbanPulseLogo(size: 96),
              const SizedBox(height: 20),
              Text(
                'Create Account',
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Join the green & accessible travel network',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _firstName,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'First Name',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _lastName,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Last Name'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _password,
                obscureText: true,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Password'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _confirmPassword,
                obscureText: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _onSignUpPressed(),
                decoration: const InputDecoration(
                  labelText: 'Confirm Password',
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  onPressed: _onSignUpPressed,
                  child: const Text('Sign Up'),
                ),
              ),
              const SizedBox(height: 20),
              TextButton(
                onPressed: () =>
                    Navigator.of(context).pushReplacementNamed(Routes.login),
                child: const Text('Already have an account? Sign In'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
