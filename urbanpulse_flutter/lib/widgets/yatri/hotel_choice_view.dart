import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../core/safe_launch.dart';
import '../../agents/runtime/agent_kind.dart';
import '../../agents/yatri/planner_orchestrator.dart';
import '../../core/app_colors.dart';
import '../../core/formatting.dart';
import '../../models/itinerary/itinerary_parts.dart';
import '../../models/trip_brief.dart';
import '../../models/yatri_question.dart';
import 'choice_answers.dart';
import 'claims_view.dart';
import 'khoji_badge.dart';
import 'option_card.dart';

/// Colour for how well a hotel supports a need. Green means a source says so,
/// amber partly, red no, grey nobody could say.
Color supportColor(BuildContext context, SupportLevel level) => switch (level) {
  SupportLevel.yes => AppColors.primaryGreenDark,
  SupportLevel.partial => AppColors.solidWarning,
  SupportLevel.no => Theme.of(context).colorScheme.error,
  SupportLevel.unknown => Theme.of(context).colorScheme.outline,
};

IconData _supportIcon(SupportLevel level) => switch (level) {
  SupportLevel.yes => Icons.check_circle_rounded,
  SupportLevel.partial => Icons.adjust_rounded,
  SupportLevel.no => Icons.cancel_rounded,
  SupportLevel.unknown => Icons.help_outline_rounded,
};

/// A short label for a need on a hotel card.
String needShortLabel(AccessibilityNeed n) => switch (n) {
  AccessibilityNeed.wheelchair => 'Wheelchair',
  AccessibilityNeed.limitedMobility => 'Step-free',
  AccessibilityNeed.visual => 'Visual',
  AccessibilityNeed.hearing => 'Hearing',
  AccessibilityNeed.elderlyCare => 'Elderly',
  AccessibilityNeed.serviceAnimal => 'Service animal',
  AccessibilityNeed.cognitiveSensory => 'Sensory',
  AccessibilityNeed.otherSpecial => 'Special needs',
  AccessibilityNeed.none => 'Access',
};

/// Lets the traveller choose a stay: the shortlisted hotels on a map and as
/// cards showing price (live or estimated, and from where), rating, distance
/// and per-need access with the evidence behind it.
class HotelChoiceView extends StatefulWidget {
  const HotelChoiceView({required this.question, required this.onSubmit, this.tileLayer, super.key});

  final YatriQuestion question;
  final AnswerSubmit onSubmit;

  /// Replaces the OpenStreetMap tiles (tests pass an empty layer).
  final Widget? tileLayer;

  @override
  State<HotelChoiceView> createState() => _HotelChoiceViewState();
}

class _HotelChoiceViewState extends State<HotelChoiceView> {
  String? _selected;
  final Set<String> _open = {};

  List<HotelOption> get _hotels => widget.question.hotels;

  @override
  void initState() {
    super.initState();
    _selected = _hotels.firstOrNull?.id;
  }

  void _toggleOpen(String id) => setState(() => _open.contains(id) ? _open.remove(id) : _open.add(id));

  @override
  Widget build(BuildContext context) {
    final hotels = _hotels;
    final located = [for (var i = 0; i < hotels.length; i++) if (hotels[i].location != null) i];
    HotelOption? chosen;
    for (final h in hotels) {
      if (h.id == _selected) chosen = h;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (located.isNotEmpty) ...[
          _HotelMap(
            hotels: hotels,
            selected: _selected,
            onSelect: (id) => setState(() => _selected = id),
            tileLayer: widget.tileLayer,
          ),
          const SizedBox(height: 10),
        ],
        OptionGrid(
          children: [
            for (var i = 0; i < hotels.length; i++)
              _HotelCard(
                index: i + 1,
                hotel: hotels[i],
                needs: widget.question.hotelNeeds,
                selected: _selected == hotels[i].id,
                open: _open.contains(hotels[i].id),
                onTap: () => setState(() => _selected = hotels[i].id),
                onToggle: () => _toggleOpen(hotels[i].id),
              ),
          ],
        ),
        const SizedBox(height: 12),
        CtaButton(
          label: chosen == null ? 'Choose a stay' : 'Choose ${chosen.name}',
          icon: Icons.check_rounded,
          onPressed: chosen == null ? null : () => widget.onSubmit(ChoiceAnswer(chosen!.id, chosen.name)),
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => widget.onSubmit(const ChoiceAnswer(PlannerOrchestrator.autoPick, 'Let Yatri choose')),
            child: const Text('Let Yatri choose'),
          ),
        ),
      ],
    );
  }
}

class _HotelCard extends StatelessWidget {
  const _HotelCard({
    required this.index,
    required this.hotel,
    required this.needs,
    required this.selected,
    required this.open,
    required this.onTap,
    required this.onToggle,
  });

  final int index;
  final HotelOption hotel;
  final Set<AccessibilityNeed> needs;
  final bool selected;
  final bool open;
  final VoidCallback onTap;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final atithi = AgentKind.atithi.color;
    final shownNeeds = needs.toList();

    return Material(
      color: selected ? scheme.primary.withValues(alpha: 0.08) : scheme.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: selected ? scheme.primary : scheme.outlineVariant, width: selected ? 1.6 : 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _NumberDot(index: index, color: atithi),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(hotel.name, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Wrap(
                          spacing: 8,
                          runSpacing: 2,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(hotel.type, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                            if (hotel.rating != null)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.star_rounded, size: 15, color: AppColors.solidWarning),
                                  const SizedBox(width: 2),
                                  Text(
                                    hotel.rating!.toStringAsFixed(1) +
                                        (hotel.reviewCount == null ? '' : ' (${grouped(hotel.reviewCount!)})'),
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            if (hotel.distanceToCenterKm != null)
                              Text(
                                '${hotel.distanceToCenterKm} km from centre',
                                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  SelectionMark(selected: selected, multi: false),
                ],
              ),
              const SizedBox(height: 10),
              _PriceRow(hotel: hotel),
              if (shownNeeds.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final n in shownNeeds) NeedChip(need: n, support: hotel.access[n]),
                  ],
                ),
              ],
              if (hotel.claims.isNotEmpty) ...[
                const SizedBox(height: 8),
                KhojiBadge(claims: hotel.claims),
              ],
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: onToggle,
                  icon: Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 18),
                  label: Text(open ? 'Hide details' : 'Details and sources'),
                ),
              ),
              if (open) _Details(hotel: hotel, needs: shownNeeds),
            ],
          ),
        ),
      ),
    );
  }
}

class _NumberDot extends StatelessWidget {
  const _NumberDot({required this.index, required this.color});

  final int index;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 26,
    height: 26,
    alignment: Alignment.center,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    child: Text(
      '$index',
      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800),
    ),
  );
}

class _PriceRow extends StatelessWidget {
  const _PriceRow({required this.hotel});

  final HotelOption hotel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final price = hotel.nightlyInr;
    final live = !hotel.priceIsEstimated;
    final note = live
        ? 'live price${hotel.cheapestOta == null ? '' : ' via ${hotel.cheapestOta}'}'
        : 'estimated price';

    return Wrap(
      spacing: 10,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          price == null ? 'Price unknown' : '${live ? '' : '≈ '}${rupees(price)} / night',
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: (live ? AppColors.primaryGreenDark : AppColors.solidWarning).withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            note,
            style: theme.textTheme.labelSmall?.copyWith(
              color: live ? AppColors.primaryGreenDark : scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (hotel.totalStayInr != null && live)
          Text('${rupees(hotel.totalStayInr!)} total', style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        if (hotel.priceBand == 'high')
          Text('busy dates', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.solidWarning, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class NeedChip extends StatelessWidget {
  const NeedChip({required this.need, required this.support, super.key});

  final AccessibilityNeed need;
  final NeedSupport? support;

  @override
  Widget build(BuildContext context) {
    final level = support?.level ?? SupportLevel.unknown;
    final color = supportColor(context, level);
    final theme = Theme.of(context);
    return Semantics(
      label: '${needShortLabel(need)}: ${level.label}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_supportIcon(level), size: 14, color: color),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                '${needShortLabel(need)}: ${level.label}',
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurface, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({required this.hotel, required this.needs});

  final HotelOption hotel;
  final List<AccessibilityNeed> needs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final url = hotel.tripAdvisorUrl ?? hotel.bookingUrl;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final n in needs)
          if (hotel.access[n] case final s?)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(needShortLabel(n), style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
                  Text(
                    s.detail.isEmpty ? 'No information found' : s.detail,
                    style: theme.textTheme.bodySmall,
                  ),
                  Text(
                    s.provenance.isEstimated ? 'AI-estimated, not verified' : 'Source: ${s.provenance.source}',
                    style: muted?.copyWith(fontStyle: s.provenance.isEstimated ? FontStyle.italic : null),
                  ),
                ],
              ),
            ),
        if (hotel.amenities.isNotEmpty)
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final a in hotel.amenities)
                Chip(
                  label: Text(a, style: theme.textTheme.labelSmall),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
            ],
          ),
        if (hotel.claims.isNotEmpty) ...[
          const SizedBox(height: 8),
          ClaimsView(claims: hotel.claims),
        ],
        if (hotel.priceIsEstimated) ...[
          const SizedBox(height: 6),
          Text(
            'This price is an estimate (${hotel.provenance.isEstimated ? 'AI or regional average' : 'TripAdvisor price range'}). Check the live rate before booking.',
            style: muted,
          ),
        ],
        if (url != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4), minimumSize: const Size(0, 32)),
              onPressed: () => openWebLink(url),
              icon: const Icon(Icons.open_in_new_rounded, size: 16),
              label: const Text('Open listing'),
            ),
          ),
      ],
    );
  }
}

/// The shortlisted hotels as numbered pins. Tapping a pin selects the hotel.
class _HotelMap extends StatelessWidget {
  const _HotelMap({required this.hotels, required this.selected, required this.onSelect, this.tileLayer});

  final List<HotelOption> hotels;
  final String? selected;
  final ValueChanged<String> onSelect;
  final Widget? tileLayer;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final points = [for (final h in hotels) if (h.location != null) h.location!];
    final options = points.length == 1
        ? MapOptions(initialCenter: points.first, initialZoom: 14, interactionOptions: const InteractionOptions(flags: InteractiveFlag.none))
        : MapOptions(
            initialCameraFit: CameraFit.coordinates(coordinates: points, padding: const EdgeInsets.all(34), maxZoom: 15),
            interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
          );

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: 190,
        decoration: BoxDecoration(border: Border.all(color: scheme.outlineVariant), borderRadius: BorderRadius.circular(18)),
        child: FlutterMap(
          options: options,
          children: [
            tileLayer ??
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.urbanpulse.app',
                ),
            MarkerLayer(
              markers: [
                for (var i = 0; i < hotels.length; i++)
                  if (hotels[i].location != null)
                    Marker(
                      point: hotels[i].location!,
                      width: 34,
                      height: 34,
                      child: GestureDetector(
                        onTap: () => onSelect(hotels[i].id),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AgentKind.atithi.color,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: selected == hotels[i].id ? 3 : 1.5),
                            boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 4)],
                          ),
                          child: Text(
                            '${i + 1}',
                            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    ),
              ],
            ),
            const Align(
              alignment: Alignment.bottomRight,
              child: Padding(
                padding: EdgeInsets.all(4),
                child: Text('© OpenStreetMap', style: TextStyle(fontSize: 9, color: Color(0xFF444444))),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
