import 'package:flutter/material.dart';

import '../../models/yatri_question.dart';

/// The custom selection mark used by every Yatri answer: a rounded square for
/// multi-select (a checkbox) or a circle for single choice (a radio). Built
/// from the colour scheme so it follows the user's accent and light/dark mode.
class SelectionMark extends StatelessWidget {
  const SelectionMark({required this.selected, required this.multi, super.key});

  final bool selected;
  final bool multi;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(multi ? 7 : 12);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: selected ? scheme.primary : Colors.transparent,
        borderRadius: radius,
        border: Border.all(
          color: selected ? scheme.primary : scheme.outline,
          width: 1.6,
        ),
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 140),
        transitionBuilder: (child, anim) =>
            ScaleTransition(scale: anim, child: child),
        child: selected
            ? Icon(
                multi ? Icons.check_rounded : Icons.circle,
                key: const ValueKey('on'),
                size: multi ? 16 : 8,
                color: scheme.onPrimary,
              )
            : const SizedBox.shrink(key: ValueKey('off')),
      ),
    );
  }
}

IconData _iconForOption(QuestionOption option) {
  if (option.icon != null) return option.icon!;
  final id = option.id.toLowerCase();
  return switch (id) {
    'train' => Icons.train_outlined,
    'metrolocal' || 'metro' => Icons.subway_outlined,
    'ebus' => Icons.electric_bolt_outlined,
    'bus' => Icons.directions_bus_outlined,
    'sharedev' => Icons.local_taxi_outlined,
    'selfdriveev' => Icons.electric_car_outlined,
    'cartaxi' || 'taxi' || 'cab' => Icons.directions_car_outlined,
    'flight' => Icons.flight_takeoff_outlined,
    'wheelchair' => Icons.accessible_outlined,
    'limitedmobility' => Icons.directions_walk_outlined,
    'visual' => Icons.visibility_outlined,
    'hearing' => Icons.hearing_outlined,
    'elderlycare' => Icons.elderly_outlined,
    'serviceanimal' => Icons.pets_outlined,
    'womenonlytransport' => Icons.shield_outlined,
    'verifiedstays' => Icons.verified_outlined,
    'avoidlatenighttransit' => Icons.nights_stay_outlined,
    'sharedlivelocation' => Icons.share_location_outlined,
    'leisure' => Icons.beach_access_outlined,
    'family' => Icons.family_restroom_outlined,
    'pilgrimage' => Icons.temple_hindu_outlined,
    'adventure' => Icons.hiking_outlined,
    'heritage' => Icons.museum_outlined,
    'nature' => Icons.forest_outlined,
    'workation' => Icons.laptop_mac_outlined,
    'relaxed' => Icons.hourglass_bottom_outlined,
    'balanced' => Icons.balance_outlined,
    'packed' => Icons.bolt_outlined,
    'ecostay' => Icons.eco_outlined,
    'homestay' => Icons.home_outlined,
    'hotel' => Icons.hotel_outlined,
    'hostel' => Icons.bed_outlined,
    'resort' => Icons.spa_outlined,
    'veg' || 'vegan' || 'jain' || 'halal' || 'nopreference' => Icons.restaurant_outlined,
    'budget' => Icons.savings_outlined,
    'comfort' => Icons.hotel_outlined,
    'premium' => Icons.auto_awesome_outlined,
    'luxury' => Icons.diamond_outlined,
    'custom' => Icons.tune_outlined,
    '1' => Icons.person_outline,
    'manual' => Icons.accessible_outlined,
    'electric' => Icons.electric_wheelchair_outlined,
    'walking_aid' => Icons.nordic_walking_outlined,
    'audio' => Icons.volume_up_outlined,
    'screen_reader' => Icons.phone_android_outlined,
    'guide' => Icons.record_voice_over_outlined,
    'high_contrast' => Icons.contrast_outlined,
    'tactile' => Icons.touch_app_outlined,
    'visual_alerts' => Icons.chat_bubble_outline,
    'sign_language' => Icons.sign_language_outlined,
    'hearing_loop' => Icons.hearing_outlined,
    'captions' => Icons.closed_caption_outlined,
    'ground_floor' => Icons.stairs_outlined,
    'medical' => Icons.local_hospital_outlined,
    'slow_pace' => Icons.directions_walk_outlined,
    'porter' => Icons.luggage_outlined,
    'guide_dog' || 'hearing_dog' || 'mobility_dog' || 'other' => Icons.pets_outlined,
    'lt100' || '100_500' || '500_1000' || 'gt1000' => Icons.directions_walk_outlined,
    'rest_stops' || 'seating' => Icons.chair_outlined,
    'avoid_stairs' => Icons.elevator_outlined,
    'step_free' => Icons.door_front_door_outlined,
    'lift' => Icons.elevator_outlined,
    'toilet' => Icons.wc_outlined,
    'roll_in' => Icons.shower_outlined,
    'ramps' => Icons.accessible_forward_outlined,
    'greenest' => Icons.eco_outlined,
    'convenience' => Icons.luggage_outlined,
    'none' => Icons.check_circle_outline,
    'pick' => Icons.date_range_outlined,
    _ when int.tryParse(id) != null => Icons.group_outlined,
    _ => Icons.place_outlined,
  };
}

/// A selectable card: icon, title, optional subtitle / CO2 badge, and a
/// selection mark. Used for the richer choices (transport, accessibility…).
class OptionCard extends StatelessWidget {
  const OptionCard({
    required this.option,
    required this.selected,
    required this.onTap,
    this.multi = false,
    super.key,
  });

  final QuestionOption option;
  final bool selected;
  final bool multi;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: selected
            ? scheme.primary.withValues(alpha: 0.12)
            : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected ? scheme.primary : scheme.outlineVariant,
          width: selected ? 1.6 : 1,
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected
                        ? scheme.primary.withValues(alpha: 0.18)
                        : scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _iconForOption(option),
                    size: 20,
                    color: selected ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 6,
                        runSpacing: 2,
                        children: [
                          Text(
                            option.label,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (option.recommended)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: scheme.primary.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.eco_outlined, size: 12, color: scheme.primary),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Greener',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: scheme.primary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      if (option.subtitle != null || option.badge != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            option.subtitle ?? option.badge!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                SelectionMark(selected: selected, multi: multi),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A compact pill for short one-word choices (cities, group sizes).
class OptionPill extends StatelessWidget {
  const OptionPill({
    required this.option,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final QuestionOption option;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      decoration: BoxDecoration(
        color: selected ? scheme.primary : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected
              ? scheme.primary
              : option.recommended
              ? scheme.primary.withValues(alpha: 0.6)
              : scheme.outlineVariant,
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _iconForOption(option),
                  size: 16,
                  color: selected ? scheme.onPrimary : scheme.primary,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    option.label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: selected ? scheme.onPrimary : scheme.onSurface,
                    ),
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

/// Lays option cards out in one column on phones and two on wider layouts,
/// keeping every card the same width whatever its height.
class OptionGrid extends StatelessWidget {
  const OptionGrid({required this.children, this.spacing = 8, super.key});

  final List<Widget> children;
  final double spacing;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final cols = constraints.maxWidth >= 520 ? 2 : 1;
      final width = (constraints.maxWidth - spacing * (cols - 1)) / cols;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [for (final c in children) SizedBox(width: width, child: c)],
      );
    },
  );
}

/// A full-width pill button for a primary call to action inside a card.
class CtaButton extends StatelessWidget {
  const CtaButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.tonal = false,
    super.key,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool tonal;

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 8)],
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
      ],
    );
    final style = FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(48),
      textStyle: const TextStyle(fontWeight: FontWeight.w700),
    );
    return tonal
        ? FilledButton.tonal(onPressed: onPressed, style: style, child: child)
        : FilledButton(onPressed: onPressed, style: style, child: child);
  }
}
