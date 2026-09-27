import 'package:flutter/material.dart';

import 'routes.dart';

/// Material 3 window size classes: phones, tablets (and small laptop
/// windows), and desktops.
enum WindowSize {
  compact,
  medium,
  expanded;

  static WindowSize of(BuildContext context) => fromWidth(MediaQuery.sizeOf(context).width);

  static WindowSize fromWidth(double width) => width >= 1200
      ? expanded
      : width >= 600
      ? medium
      : compact;

  bool get isCompact => this == compact;
  bool get isExpanded => this == expanded;
}

/// Keeps [child] at a readable width on wide windows, centred, and gives it
/// the full width on phones. For scrolling pages, the scrollable keeps the
/// full window (so the wheel scrolls anywhere) and only its content narrows.
class ResponsiveCenter extends StatelessWidget {
  const ResponsiveCenter({required this.child, this.maxWidth = 1120, super.key});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width <= maxWidth) return child;
    // Narrow the content through the MediaQuery padding would move app bars;
    // insetting the page is simpler and keeps every child's layout as on a
    // tablet of the same width.
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child),
    );
  }
}

/// Every pushed screen on a wide window: centred at a comfortable width over a
/// quiet backdrop, instead of stretched edge to edge. Phones and narrow
/// windows see the page exactly as before. The home shell and the splash lay
/// themselves out.
class WidePageTransitionsBuilder extends PageTransitionsBuilder {
  const WidePageTransitionsBuilder(this.inner);

  final PageTransitionsBuilder inner;

  /// Pages that handle their own wide layout.
  static const fullWidth = {Routes.splash, Routes.home, Routes.weatherTwin};

  /// Short forms (sign in, sign up) read best as a narrow card.
  static const narrow = {Routes.welcome, Routes.login, Routes.signup, Routes.sos};

  /// The theme's page transitions with the wide-window frame added.
  static PageTransitionsTheme theme() {
    const base = PageTransitionsTheme();
    return PageTransitionsTheme(
      builders: {
        for (final p in TargetPlatform.values) p: WidePageTransitionsBuilder(base.builders[p] ?? const ZoomPageTransitionsBuilder()),
      },
    );
  }

  @override
  DelegatedTransitionBuilder? get delegatedTransition => inner.delegatedTransition;

  @override
  Duration get transitionDuration => inner.transitionDuration;

  @override
  Duration get reverseTransitionDuration => inner.reverseTransitionDuration;

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) =>
      inner.buildTransitions(route, context, animation, secondaryAnimation, _WidePage(name: route.settings.name, child: child));
}

class _WidePage extends StatelessWidget {
  const _WidePage({required this.name, required this.child});

  final String? name;
  final Widget child;

  static const _threshold = 900.0;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < _threshold || WidePageTransitionsBuilder.fullWidth.contains(name)) return child;
    final maxWidth = WidePageTransitionsBuilder.narrow.contains(name) ? 560.0 : 1120.0;
    if (width <= maxWidth + 48) return child;
    final scheme = Theme.of(context).colorScheme;
    final backdrop = Color.alphaBlend(scheme.onSurface.withValues(alpha: 0.035), scheme.surface);
    return ColoredBox(
      color: backdrop,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              border: Border.symmetric(vertical: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6))),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
