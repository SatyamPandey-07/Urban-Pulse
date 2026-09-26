import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../core/formatting.dart';
import '../state/app_scope.dart';
import '../widgets/common.dart';

/// Port of `SosActivity` / `activity_sos.xml` — hold the button for three
/// seconds to raise an alert.
///
/// The Kotlin version only showed a toast saying the location had been shared.
/// This version actually resolves the device fix first and reports honestly
/// whether it got one, so the confirmation isn't a claim the app can't back up.
/// Wiring the alert to real emergency contacts still needs a backend — see the
/// migration notes in README.md.
class SosScreen extends StatefulWidget {
  const SosScreen({super.key});

  @override
  State<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends State<SosScreen>
    with SingleTickerProviderStateMixin {
  static const _holdDuration = Duration(seconds: 3);

  late final AnimationController _holdController =
      AnimationController(vsync: this, duration: _holdDuration)
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed) _triggerSos();
        });

  bool _isSending = false;

  @override
  void dispose() {
    _holdController.dispose();
    super.dispose();
  }

  void _onPressStart() => _holdController.forward();

  void _onPressEnd() {
    final wasIncomplete = _holdController.value < 1.0;
    _holdController.reverse();
    if (wasIncomplete && !_isSending) {
      showToast(context, 'Hold for 3 seconds to send SOS');
    }
  }

  Future<void> _triggerSos() async {
    if (_isSending) return;
    setState(() => _isSending = true);

    final position = await AppScope.of(context).location.currentPosition();
    if (!mounted) return;

    setState(() => _isSending = false);
    _holdController.reset();

    showToast(
      context,
      position != null
          ? 'SOS raised at ${fixed(position.latitude, 4)}, '
                '${fixed(position.longitude, 4)}.'
          : 'SOS raised — but your location could not be read. Enable location services '
                'so responders can find you.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Are you in an emergency?',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Press the SOS button for 3 seconds to share your live location.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 48),
              Center(child: _sosButton(context)),
              const SizedBox(height: 16),
              Text(
                _isSending ? 'Raising alert…' : 'Press 3 sec for SOS',
                textAlign: TextAlign.center,
                style: theme.textTheme.labelLarge,
              ),
              const SizedBox(height: 48),
              Text(
                "What's your emergency?",
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _categoryCard(
                      context,
                      'Medical',
                      Icons.medical_services_outlined,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _categoryCard(
                      context,
                      'Fire',
                      Icons.local_fire_department_outlined,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _categoryCard(
                      context,
                      'Accident',
                      Icons.car_crash_outlined,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _categoryCard(
                      context,
                      'Violence',
                      Icons.shield_outlined,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sosButton(BuildContext context) => GestureDetector(
    onTapDown: (_) => _onPressStart(),
    onTapUp: (_) => _onPressEnd(),
    onTapCancel: _onPressEnd,
    child: AnimatedBuilder(
      animation: _holdController,
      builder: (context, child) => Container(
        width: 200,
        height: 200,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.sosRed.withValues(alpha: 0.12),
        ),
        padding: const EdgeInsets.all(20),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.sosRed.withValues(alpha: 0.25),
          ),
          padding: const EdgeInsets.all(20),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Fills as the 3-second hold progresses.
              SizedBox.expand(
                child: CircularProgressIndicator(
                  value: _holdController.value == 0
                      ? null
                      : _holdController.value,
                  strokeWidth: 6,
                  backgroundColor: Colors.transparent,
                  valueColor: const AlwaysStoppedAnimation(Colors.white),
                ),
              ),
              Transform.scale(
                scale: 1 - 0.1 * _holdController.value,
                child: Container(
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.sosRed, AppColors.sosDeepRed],
                    ),
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    'SOS',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _categoryCard(BuildContext context, String label, IconData icon) =>
      SectionCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        onTap: () => showToast(context, '$label emergency selected'),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.sosRed),
            const SizedBox(width: 12),
            Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      );
}
