import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../agents/twin/social_signals.dart';
import '../agents/twin/twin_calibration.dart';
import '../agents/twin/twin_controller.dart';
import '../agents/twin/twin_demo.dart';
import '../agents/twin/weather_twin.dart';
import '../agents/travel_risk/nugen_travel_risk.dart';
import '../agents/travel_risk/travel_risk.dart';
import '../core/app_colors.dart';
import '../core/config.dart';
import '../core/formatting.dart';
import '../models/itinerary/itinerary.dart';
import '../state/app_scope.dart';
import '../widgets/common.dart';

/// The weather digital twin of a trip: the live forecast and what people are
/// reporting, a map of the places, stay and legs, and interactive what-ifs
/// (rain, heat, wind, alerts, a flooded area) showing how the weather
/// propagates: places close or move, walks become cabs, days run out of time,
/// demand shifts across attractions, cabs, restaurants and hotels. Nothing here
/// changes the saved trip.
class WeatherTwinScreen extends StatefulWidget {
  const WeatherTwinScreen({this.itinerary, this.tileLayer, super.key});

  /// The trip to mirror; null opens the newest saved itinerary, or a sample.
  final Itinerary? itinerary;

  /// Replaces the OpenStreetMap tiles (tests only).
  final Widget? tileLayer;

  @override
  State<WeatherTwinScreen> createState() => _WeatherTwinScreenState();
}

class _WeatherTwinScreenState extends State<WeatherTwinScreen> {
  TwinController? _c;
  bool _sample = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c != null) return;
    final services = AppScope.of(context);
    var it = widget.itinerary;
    if (it == null) {
      it = services.itineraries.all().firstOrNull;
      if (it == null) {
        it = TwinDemo.jaipur();
        _sample = true;
      }
    }
    final tk = services.agentToolkit;
    _c = TwinController(
      itinerary: it,
      risk: tk.travelRisk,
      forecast: tk.forecast,
      calibration: TwinCalibration(services.prefs),
      feed: SocialSignalFeed(client: tk.client, webSearch: tk.tavily, geocoder: tk.geocoder),
    )..addListener(_changed);
    unawaited(_c!.start());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _c?.removeListener(_changed);
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c!;
    final it = c.itinerary;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Weather twin · ${it.destination}', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            Text(
              '${dateRangeLabel(it.start, it.end)}${_sample ? ' · sample trip' : ''}',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh live weather and reports',
            onPressed: c.loadingLive
                ? null
                : () {
                    unawaited(c.refreshLive());
                    unawaited(c.refreshSignals());
                  },
            icon: c.loadingLive ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 32),
          children: [
            _Status(c: c),
            const SizedBox(height: 10),
            _ScenarioPanel(c: c),
            const SizedBox(height: 10),
            _TwinMap(c: c, tileLayer: widget.tileLayer),
            const SizedBox(height: 10),
            if (c.state == null)
              const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
            else ...[
              _Summary(c: c),
              const SizedBox(height: 10),
              _Chain(state: c.state!),
              const SizedBox(height: 10),
              for (final d in c.state!.days) ...[_DayCard(c: c, day: d), const SizedBox(height: 10)],
              _Ecosystem(state: c.state!),
              const SizedBox(height: 10),
            ],
            _Signals(c: c),
            const SizedBox(height: 10),
            _Learning(c: c),
            const SizedBox(height: 10),
            _Timeline(c: c),
          ],
        ),
      ),
    );
  }
}

// --- colours -------------------------------------------------------------------------

Color _stateColor(VisitState s) => switch (s) {
  VisitState.ok => const Color(0xFF2E7D32),
  VisitState.shifted => const Color(0xFFF9A825),
  VisitState.atRisk => const Color(0xFFEF6C00),
  VisitState.closed => const Color(0xFFC62828),
  VisitState.dropped => const Color(0xFF757575),
};

const _floodColor = Color(0xFF1565C0);
const _signalColor = Color(0xFF7B1FA2);

String _pct(double p) => '${(p * 100).round()}%';

String _signed(num v, {String unit = '', String prefix = ''}) => '${v >= 0 ? '+' : '−'}$prefix${v.abs().round()}$unit';

// --- status -----------------------------------------------------------------------------

class _Status extends StatelessWidget {
  const _Status({required this.c});

  final TwinController c;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final risk = c.risk;
    final updated = c.liveUpdatedAt;
    final model = risk is NugenTravelRisk ? risk : null;
    return SectionCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.hub_outlined, color: AppColors.primaryGreen),
              const SizedBox(width: 8),
              Expanded(
                child: Text('A live model of your trip that re-simulates as the weather changes', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _Badge(
                icon: Icons.cloud_outlined,
                text: c.loadingLive
                    ? 'Loading live weather…'
                    : c.liveError ?? 'Open-Meteo · updated ${updated == null ? '-' : _hm(updated)}',
                color: c.liveError == null ? const Color(0xFF0277BD) : theme.colorScheme.error,
              ),
              _Badge(
                icon: Icons.psychology_alt_outlined,
                text: risk.isAligned ? '${risk.label}${model?.medianLatencyMs == null ? '' : ' · ${(model!.medianLatencyMs! / 1000).toStringAsFixed(1)} s'}' : 'Offline rules (Nugen model not configured)',
                color: risk.isAligned ? AppColors.primaryGreen : theme.colorScheme.onSurfaceVariant,
              ),
              _Badge(icon: Icons.forum_outlined, text: c.loadingSignals ? 'Reading reports…' : '${c.signals.length} live report${c.signals.length == 1 ? '' : 's'}', color: _signalColor),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Simulation only: your saved trip is never changed.${risk.isAligned && AppConfig.nugenModelId.isNotEmpty ? ' Model ${AppConfig.nugenModelId}.' : ''}',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

String _hm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.text, required this.color});

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withValues(alpha: 0.35))),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Flexible(child: Text(text, style: TextStyle(fontSize: 11.5, color: color, fontWeight: FontWeight.w600))),
      ],
    ),
  );
}

// --- scenario ---------------------------------------------------------------------------

class _ScenarioPanel extends StatelessWidget {
  const _ScenarioPanel({required this.c});

  final TwinController c;

  TwinScenario get s => c.scenario;

  /// A weather edit starts a custom what-if covering at least one day.
  void _edit(TwinScenario next) => c.setScenario(next.durationDays == 0 ? next.copyWith(durationDays: 1) : next, log: false);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final days = math.max(1, c.itinerary.days.length);
    final live = c.live[s.startDay];
    final rain = s.rainMm ?? live?.rainMm ?? 0;
    final temp = s.tempMaxC ?? live?.tempMaxC ?? 30;
    final wind = s.windKmh ?? live?.windKmh ?? 12;
    final preview = WeatherDay(tempMaxC: temp, rainMm: rain, windKmh: wind);
    return SectionCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('What if…', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final p in c.presets)
                ChoiceChip(
                  label: Text(p.name),
                  selected: s.id == p.id,
                  onSelected: (_) => c.setScenario(p),
                ),
            ],
          ),
          Theme(
            data: theme.copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: Text(s.isLive ? 'Adjust the weather yourself' : 'Scenario: ${s.name}', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
              subtitle: Text(
                s.isLive
                    ? 'Rain, heat, wind, alerts, duration and a flooded area'
                    : 'Days ${s.startDay}–${math.min(days, s.startDay + math.max(1, s.durationDays) - 1)} · ${preview.summary}${s.hasFlood ? ' · flood ${s.floodRadiusKm.toStringAsFixed(1)} km' : ''}',
                style: theme.textTheme.bodySmall,
              ),
              children: [
                _SliderRow(
                  label: 'Rain',
                  value: rain.clamp(0, 250).toDouble(),
                  max: 250,
                  divisions: 50,
                  text: '${rain.round()} mm · ${preview.rainClass}',
                  onChanged: (v) => _edit(s.copyWith(rainMm: v)),
                ),
                _SliderRow(
                  label: 'Max temp',
                  value: temp.clamp(15, 50).toDouble(),
                  min: 15,
                  max: 50,
                  divisions: 35,
                  text: '${temp.round()}°C · ${preview.heatClass}',
                  onChanged: (v) => _edit(s.copyWith(tempMaxC: v)),
                ),
                _SliderRow(
                  label: 'Wind',
                  value: wind.clamp(0, 130).toDouble(),
                  max: 130,
                  divisions: 26,
                  text: '${wind.round()} km/h',
                  onChanged: (v) => _edit(s.copyWith(windKmh: v)),
                ),
                if (days > 1)
                  _SliderRow(
                    label: 'From day',
                    value: s.startDay.toDouble().clamp(1, days.toDouble()),
                    min: 1,
                    max: days.toDouble(),
                    divisions: days - 1,
                    text: 'Day ${s.startDay}',
                    onChanged: (v) => _edit(s.copyWith(startDay: v.round())),
                  ),
                if (days > 1)
                  _SliderRow(
                    label: 'Lasting',
                    value: math.max(1, s.durationDays).toDouble().clamp(1, days.toDouble()),
                    min: 1,
                    max: days.toDouble(),
                    divisions: days - 1,
                    text: '${math.max(1, s.durationDays)} day${math.max(1, s.durationDays) == 1 ? '' : 's'}',
                    onChanged: (v) => _edit(s.copyWith(durationDays: v.round())),
                  ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const SizedBox(width: 84, child: Text('Alert', style: TextStyle(fontWeight: FontWeight.w600))),
                    Expanded(
                      child: Wrap(
                        spacing: 4,
                        children: [
                          for (final a in WeatherAlert.values)
                            ChoiceChip(
                              visualDensity: VisualDensity.compact,
                              label: Text(a.name),
                              selected: (s.alert ?? WeatherAlert.none) == a,
                              onSelected: (_) => _edit(
                                s.copyWith(
                                  alert: a,
                                  alertFor: s.alertFor.isNotEmpty
                                      ? s.alertFor
                                      : temp >= 40 && rain < 15
                                      ? 'heat'
                                      : wind >= 60
                                      ? 'cyclone'
                                      : 'heavy rain',
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                if ((s.alert ?? WeatherAlert.none) != WeatherAlert.none)
                  Row(
                    children: [
                      const SizedBox(width: 84, child: Text('For', style: TextStyle(fontWeight: FontWeight.w600))),
                      Expanded(
                        child: Wrap(
                          spacing: 4,
                          children: [
                            for (final f in const ['heavy rain', 'thunderstorm', 'heat', 'cyclone'])
                              ChoiceChip(visualDensity: VisualDensity.compact, label: Text(f), selected: s.alertFor == f, onSelected: (_) => _edit(s.copyWith(alertFor: f))),
                          ],
                        ),
                      ),
                    ],
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Flooded area'),
                  subtitle: Text(s.hasFlood ? 'Tap the map to move it' : 'Mark part of the city as under water'),
                  value: s.hasFlood,
                  onChanged: (on) => c.setScenario(
                    on
                        ? s.copyWith(floodCenter: c.itinerary.hotel?.location ?? c.tripCenter, durationDays: math.max(1, s.durationDays))
                        : s.copyWith(clearFlood: true),
                    log: false,
                  ),
                ),
                if (s.hasFlood)
                  _SliderRow(
                    label: 'Radius',
                    value: s.floodRadiusKm.clamp(0.3, 6),
                    min: 0.3,
                    max: 6,
                    divisions: 57,
                    text: '${s.floodRadiusKm.toStringAsFixed(1)} km',
                    onChanged: (v) => c.setScenario(s.copyWith(floodRadiusKm: v), log: false),
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Include live reports'),
                  subtitle: const Text('Closures and waterlogging people are posting'),
                  value: s.useSocial,
                  onChanged: (on) => c.setScenario(s.copyWith(useSocial: on, durationDays: s.durationDays), log: false),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({required this.label, required this.value, required this.text, required this.onChanged, this.min = 0, required this.max, this.divisions});

  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String text;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(width: 84, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
      Expanded(child: Slider(value: value, min: min, max: max, divisions: divisions, onChanged: onChanged)),
      SizedBox(width: 118, child: Text(text, style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.end)),
    ],
  );
}

// --- map ----------------------------------------------------------------------------------

class _TwinMap extends StatelessWidget {
  const _TwinMap({required this.c, this.tileLayer});

  final TwinController c;
  final Widget? tileLayer;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final st = c.state;
    final hotel = c.itinerary.hotel?.location;
    final visits = st?.visits.where((v) => v.location != null).toList() ?? const <TwinVisit>[];
    final points = <LatLng>[?hotel, for (final v in visits) v.location!];
    if (points.isEmpty) {
      points.addAll([for (final d in c.itinerary.days) for (final s in d.slots) if (s.location != null) s.location!]);
    }
    if (points.isEmpty) return const SizedBox.shrink();
    final s = c.scenario;
    final options = MapOptions(
      initialCameraFit: points.length == 1 ? null : CameraFit.coordinates(coordinates: points, padding: const EdgeInsets.all(40), maxZoom: 14),
      initialCenter: points.first,
      initialZoom: 12,
      onTap: s.hasFlood ? (_, p) => c.setScenario(s.copyWith(floodCenter: p), log: false) : null,
    );
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: SizedBox(
            height: 320,
            child: DecoratedBox(
              decoration: BoxDecoration(border: Border.all(color: scheme.outlineVariant), borderRadius: BorderRadius.circular(18)),
              child: FlutterMap(
                options: options,
                children: [
                  tileLayer ?? TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.urbanpulse.app'),
                  if (s.hasFlood)
                    CircleLayer(
                      circles: [
                        CircleMarker(
                          point: s.floodCenter!,
                          radius: s.floodRadiusKm * 1000,
                          useRadiusInMeter: true,
                          color: _floodColor.withValues(alpha: 0.22),
                          borderColor: _floodColor,
                          borderStrokeWidth: 2,
                        ),
                      ],
                    ),
                  if (st != null)
                    PolylineLayer(
                      polylines: [
                        for (final l in st.legs)
                          if (l.path.length == 2)
                            Polyline(
                              points: l.path,
                              strokeWidth: l.changed ? 4.5 : 3,
                              color: l.blocked
                                  ? const Color(0xFFC62828)
                                  : l.extraMin >= 10 || l.becameCab
                                  ? const Color(0xFFEF6C00)
                                  : l.extraMin > 0
                                  ? const Color(0xFFF9A825)
                                  : const Color(0xFF546E7A).withValues(alpha: 0.7),
                              pattern: l.walking ? StrokePattern.dotted() : const StrokePattern.solid(),
                            ),
                      ],
                    ),
                  MarkerLayer(
                    markers: [
                      if (hotel != null)
                        Marker(
                          point: hotel,
                          width: 38,
                          height: 38,
                          child: _Pin(
                            color: st?.hotelAtRisk == true ? const Color(0xFFC62828) : const Color(0xFF00897B),
                            ring: st?.hotelAtRisk == true,
                            child: const Icon(Icons.hotel_rounded, color: Colors.white, size: 18),
                          ),
                        ),
                      for (final v in visits)
                        Marker(
                          point: v.location!,
                          width: 34,
                          height: 34,
                          child: Tooltip(
                            message: '${v.name}: ${v.state.label}',
                            child: _Pin(
                              color: _stateColor(v.state),
                              child: Icon(
                                switch (v.state) {
                                  VisitState.closed => Icons.block_rounded,
                                  VisitState.dropped => Icons.remove_rounded,
                                  VisitState.atRisk => Icons.warning_amber_rounded,
                                  VisitState.shifted => Icons.schedule_rounded,
                                  VisitState.ok => Icons.place_rounded,
                                },
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                          ),
                        ),
                      for (final sig in c.signals)
                        if (sig.location != null)
                          Marker(
                            point: sig.location!,
                            width: 30,
                            height: 30,
                            child: Tooltip(
                              message: '${sig.event.label}: ${sig.post.text}',
                              child: const _Pin(color: _signalColor, child: Icon(Icons.campaign_rounded, color: Colors.white, size: 15)),
                            ),
                          ),
                    ],
                  ),
                  const Align(
                    alignment: Alignment.bottomRight,
                    child: Padding(padding: EdgeInsets.all(4), child: Text('© OpenStreetMap', style: TextStyle(fontSize: 9, color: Color(0xFF444444)))),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 10,
          runSpacing: 4,
          children: [
            for (final v in VisitState.values) _Legend(color: _stateColor(v), text: v.label),
            const _Legend(color: _signalColor, text: 'Live report'),
            const _Legend(color: _floodColor, text: 'Flooded area'),
            const _Legend(color: Color(0xFFEF6C00), text: 'Slower leg', line: true),
          ],
        ),
      ],
    );
  }
}

class _Pin extends StatelessWidget {
  const _Pin({required this.color, required this.child, this.ring = false});

  final Color color;
  final Widget child;
  final bool ring;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: ring ? 3 : 2),
      boxShadow: [BoxShadow(color: color.withValues(alpha: ring ? 0.8 : 0.4), blurRadius: ring ? 12 : 6)],
    ),
    alignment: Alignment.center,
    child: child,
  );
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.text, this.line = false});

  final Color color;
  final String text;
  final bool line;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: line ? 16 : 10, height: line ? 4 : 10, decoration: BoxDecoration(color: color, shape: line ? BoxShape.rectangle : BoxShape.circle)),
      const SizedBox(width: 4),
      Text(text, style: const TextStyle(fontSize: 11)),
    ],
  );
}

// --- summary ------------------------------------------------------------------------------

class _Summary extends StatelessWidget {
  const _Summary({required this.c});

  final TwinController c;

  @override
  Widget build(BuildContext context) {
    final st = c.state!;
    final o = c.outlook;
    final base = c.baseline;
    final theme = Theme.of(context);
    String range((int, int, int)? r, {String prefix = '', String unit = ''}) => r == null ? '' : '80% range $prefix${r.$1}–$prefix${r.$3}$unit';
    final tiles = <Widget>[
      StatTile(
        label: 'Visits kept',
        value: '${st.visitsKept}/${st.visitsTotal}',
        caption: o == null ? null : range(o.visitsKept),
        icon: Icons.place_outlined,
        valueColor: st.visitsKept < st.visitsTotal ? const Color(0xFFC62828) : const Color(0xFF2E7D32),
      ),
      StatTile(
        label: 'Extra travel',
        value: _signed(st.extraTravelMin, unit: ' min'),
        caption: o == null ? null : range(o.extraMin, unit: ' min'),
        icon: Icons.timer_outlined,
      ),
      StatTile(
        label: 'Extra cost',
        value: _signed(st.extraCostInr, prefix: '₹'),
        caption: o == null ? null : range(o.extraCostInr, prefix: '₹'),
        icon: Icons.currency_rupee_rounded,
      ),
      StatTile(
        label: 'Extra CO₂',
        value: '${st.extraCo2Kg >= 0 ? '+' : ''}${st.extraCo2Kg.toStringAsFixed(1)} kg',
        caption: o == null ? null : 'median ${o.co2KgP50.toStringAsFixed(1)} kg',
        icon: Icons.eco_outlined,
      ),
    ];
    return SectionCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(st.scenario.isLive ? 'Your trip under the live forecast' : 'Your trip under “${st.scenario.name}”', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
              if (c.simulating) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 2.1,
            children: tiles,
          ),
          if (o != null) ...[
            const SizedBox(height: 8),
            Text(
              'Chance something on the trip is disrupted: ${_pct(o.pAnyDisruption)}. '
              'Ranges from ${o.runs} simulated weather draws around this scenario${st.source == RiskSource.aligned ? '; place-by-place impact from the Nugen model' : ''}.',
              style: theme.textTheme.bodySmall,
            ),
          ],
          if (!st.scenario.isLive && base != null) ...[
            const SizedBox(height: 6),
            Text(
              'Compared with the live forecast: ${base.visitsKept}/${base.visitsTotal} visits kept, ${_signed(base.extraTravelMin, unit: ' min')} travel.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
          if (st.hotelNote != null) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.hotel_rounded, size: 16, color: Color(0xFFC62828)),
                const SizedBox(width: 6),
                Expanded(child: Text(st.hotelNote!, style: theme.textTheme.bodySmall)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// --- propagation chain ---------------------------------------------------------------------

class _Chain extends StatelessWidget {
  const _Chain({required this.state});

  final TwinState state;

  static const _titles = {1: 'Direct effects on places', 2: 'Travel and the stay', 3: 'Knock-on effects'};

  static IconData _icon(String kind) => switch (kind) {
    'weather' => Icons.thunderstorm_outlined,
    'visit' => Icons.place_outlined,
    'leg' => Icons.alt_route_rounded,
    'hotel' => Icons.hotel_outlined,
    'crowd' => Icons.groups_outlined,
    'time' => Icons.hourglass_bottom_rounded,
    'social' => Icons.campaign_outlined,
    _ => Icons.currency_rupee_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (state.effects.isEmpty) {
      return SectionCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Color(0xFF2E7D32)),
            const SizedBox(width: 8),
            Expanded(child: Text('No weather effects on this trip under this scenario.', style: theme.textTheme.bodyMedium)),
          ],
        ),
      );
    }
    return SectionCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('How the weather propagates', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          for (final order in const [1, 2, 3])
            if (state.effects.any((e) => e.order == order)) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  CircleAvatar(radius: 10, backgroundColor: AppColors.primaryGreen, child: Text('$order', style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w800))),
                  const SizedBox(width: 8),
                  Text(_titles[order]!, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 4),
              for (final e in state.effects.where((e) => e.order == order).take(8))
                Padding(
                  padding: const EdgeInsets.only(left: 28, top: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(_icon(e.kind), size: 15, color: e.kind == 'social' ? _signalColor : theme.colorScheme.onSurfaceVariant),
                      const SizedBox(width: 6),
                      Expanded(child: Text(e.text, style: theme.textTheme.bodySmall)),
                    ],
                  ),
                ),
            ],
        ],
      ),
    );
  }
}

// --- days -----------------------------------------------------------------------------------

class _DayCard extends StatelessWidget {
  const _DayCard({required this.c, required this.day});

  final TwinController c;
  final TwinDay day;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final o = c.outlook;
    return SectionCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Day ${day.number}', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(width: 8),
              Text(shortDate(day.date), style: theme.textTheme.bodySmall),
              const Spacer(),
              if (day.overflowMinutes > 0) _Badge(icon: Icons.hourglass_bottom_rounded, text: '${day.overflowMinutes} min over', color: const Color(0xFFC62828)),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _Badge(icon: Icons.cloud_outlined, text: '${day.forecastIsReal ? 'Forecast' : 'Typical'}: ${day.live.summary}', color: const Color(0xFF0277BD)),
              if (day.simulated)
                _Badge(
                  icon: Icons.science_outlined,
                  text: 'What-if: ${day.weather.summary}${day.weather.alert == WeatherAlert.none ? '' : ' · ${day.weather.alert.name} alert'}',
                  color: const Color(0xFF6A1B9A),
                ),
            ],
          ),
          const SizedBox(height: 8),
          for (final v in day.visits) _VisitRow(c: c, v: v, p: o?.pDisrupted[v.key]),
          if (day.legs.any((l) => l.changed)) ...[
            const SizedBox(height: 6),
            for (final l in day.legs.where((l) => l.changed))
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(l.becameCab ? Icons.local_taxi_rounded : Icons.alt_route_rounded, size: 15, color: const Color(0xFFEF6C00)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${l.from} → ${l.to}: ${l.baseMin}→${l.simMin} min${l.simCostInr != l.baseCostInr ? ', ₹${l.baseCostInr}→₹${l.simCostInr}' : ''}${l.note == null ? '' : ' · ${l.note}'}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _VisitRow extends StatelessWidget {
  const _VisitRow({required this.c, required this.v, this.p});

  final TwinController c;
  final TwinVisit v;
  final double? p;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _stateColor(v.state);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
            child: Text(v.state.label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_hm(v.start)} ${v.name}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    decoration: v.state == VisitState.closed || v.state == VisitState.dropped ? TextDecoration.lineThrough : null,
                  ),
                ),
                if (v.why.isNotEmpty) Text(v.why, style: theme.textTheme.bodySmall),
                Text(
                  [
                    v.category.replaceAll('_', ' '),
                    if (v.impact.level != ImpactLevel.none) '${v.impact.level.name} impact',
                    if (v.impact.sensitiveTo.isNotEmpty) 'sensitive to ${v.impact.sensitiveTo.join(', ')}',
                    if (p != null && p! > 0) '${_pct(p!)} chance disrupted',
                    if (v.queueExtraMin > 0) '+${v.queueExtraMin} min queue',
                    v.impact.source == RiskSource.aligned ? 'Nugen' : 'rules',
                  ].join(' · '),
                  style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                if (v.state == VisitState.atRisk || v.state == VisitState.closed)
                  Row(
                    children: [
                      Text('Did it happen?', style: theme.textTheme.labelSmall),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Yes, it was disrupted',
                        onPressed: () => c.feedback(v, disrupted: true),
                        icon: const Icon(Icons.thumb_up_alt_outlined, size: 16),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: 'No, it was fine',
                        onPressed: () => c.feedback(v, disrupted: false),
                        icon: const Icon(Icons.thumb_down_alt_outlined, size: 16),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --- ecosystem ------------------------------------------------------------------------------

class _Ecosystem extends StatelessWidget {
  const _Ecosystem({required this.state});

  final TwinState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The day the weather hits hardest.
    final day = state.days.isEmpty
        ? null
        : state.days.reduce((a, b) {
            int score(TwinDay d) => d.weather.rainLevel * 3 + d.weather.heatLevel * 3 + d.weather.windLevel * 2 + d.weather.alert.index;
            return score(b) > score(a) ? b : a;
          });
    if (day == null) return const SizedBox.shrink();
    final e = day.ecosystem;
    final rows = <(String, IconData, double, String)>[
      ('Outdoor attractions', Icons.fort_outlined, e.outdoorDemandPct, 'visitors'),
      ('Indoor attractions', Icons.museum_outlined, e.indoorDemandPct, 'visitors'),
      ('Cab demand', Icons.local_taxi_outlined, (e.cabSurge - 1) * 100, 'surge ×${e.cabSurge.toStringAsFixed(2)}'),
      ('Restaurant dine-in', Icons.restaurant_outlined, e.dineInPct, 'covers'),
      ('Food delivery', Icons.delivery_dining_outlined, e.deliveryPct, 'orders'),
      ('Hotel stay extensions', Icons.hotel_outlined, e.hotelExtensionsPct, 'late check-outs'),
      ('Hotel arrival cancellations', Icons.event_busy_outlined, e.arrivalCancellationsPct, 'bookings'),
      ('Hotel cooling load', Icons.ac_unit_rounded, e.coolingLoadPct, 'energy'),
      ('Hospitality staff available', Icons.badge_outlined, e.staffAvailabilityPct, 'commutes'),
    ];
    return SectionCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Across the destination (day ${day.number})', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(
            'How ${day.weather.summary} shifts demand and capacity for attractions, cabs, restaurants and hotels, against a normal day. Power-cut risk: ${e.powerRisk}.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          for (final r in rows) _Bar(label: r.$1, icon: r.$2, pct: r.$3, note: r.$4),
          const SizedBox(height: 4),
          Text('Estimated elasticities, scaled by what the twin has learned.', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.label, required this.icon, required this.pct, required this.note});

  final String label;
  final IconData icon;
  final double pct;
  final String note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final up = pct >= 0;
    final color = pct.abs() < 1
        ? theme.colorScheme.outline
        : up
        ? const Color(0xFF2E7D32)
        : const Color(0xFFC62828);
    final frac = (pct.abs() / 100).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          SizedBox(width: 150, child: Text(label, style: theme.textTheme.bodySmall)),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                final half = box.maxWidth / 2;
                return Stack(
                  children: [
                    Container(height: 10, decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(5))),
                    Positioned(left: half - 0.5, top: 0, bottom: 0, child: Container(width: 1, height: 10, color: theme.colorScheme.outline)),
                    Positioned(
                      left: up ? half : half - half * frac,
                      width: half * frac,
                      child: Container(height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(5))),
                    ),
                  ],
                );
              },
            ),
          ),
          SizedBox(width: 56, child: Text('${up ? '+' : '−'}${pct.abs().round()}%', textAlign: TextAlign.end, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: color))),
        ],
      ),
    );
  }
}

// --- social signals -------------------------------------------------------------------------

class _Signals extends StatefulWidget {
  const _Signals({required this.c});

  final TwinController c;

  @override
  State<_Signals> createState() => _SignalsState();
}

class _SignalsState extends State<_Signals> {
  final _text = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final t = _text.text.trim();
    if (t.isEmpty || _busy) return;
    setState(() => _busy = true);
    final sig = await widget.c.addReport(t);
    if (!mounted) return;
    setState(() => _busy = false);
    _text.clear();
    if (sig != null) {
      showToast(context, sig.event.isEvent ? 'Read as ${sig.event.label} (${sig.event.severity.name}) by ${sig.event.source.label}' : 'Not read as a travel disruption');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final theme = Theme.of(context);
    return SectionCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('What people are reporting', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
              if (c.loadingSignals) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
          Text(
            'Google News, Reddit${c.feed?.webSearch != null ? ' and the web' : ''}, read by ${c.risk.label}. Reports are applied to day ${c.state == null ? 1 : WeatherTwin(itinerary: c.itinerary, live: c.live).socialDay(c.scenario, DateTime.now())} as they would affect it.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          if (c.signals.isEmpty && !c.loadingSignals)
            Text('No weather disruptions reported right now.', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          for (final s in c.signals.take(10))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.campaign_outlined, size: 16, color: _signalColor),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.post.text, maxLines: 3, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
                        Text(
                          '${s.post.source}${s.post.at == null ? '' : ' · ${shortDate(s.post.at!.toLocal())}'} · ${s.event.label}, ${s.event.severity.name}'
                          '${s.event.place == null ? '' : ' · ${s.event.place}'}${s.location == null ? '' : ' · on map'} · ${s.event.source == RiskSource.aligned ? 'Nugen' : 'rules'}',
                          style: theme.textTheme.labelSmall?.copyWith(color: _signalColor),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _text,
                  minLines: 1,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    hintText: 'Add a report, e.g. “Amber Fort closed due to heavy rain”',
                  ),
                  onSubmitted: (_) => _send(),
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filled(
                onPressed: _busy ? null : _send,
                icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// --- learning and timeline --------------------------------------------------------------------

class _Learning extends StatelessWidget {
  const _Learning({required this.c});

  final TwinController c;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cal = c.calibration;
    final cats = <String>{for (final v in c.state?.visits ?? const <TwinVisit>[]) v.category}.toList()..sort();
    return SectionCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('What the twin has learned', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(
            '${cal.observations} observation${cal.observations == 1 ? '' : 's'} from travellers and reports. For each kind of place: how often a high-impact day really disrupts a visit (starts at ${_pct(TwinCalibration.priorHigh)}).',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final cat in cats)
                () {
                  final p = cal.pDisrupt(cat, ImpactLevel.high);
                  final (a, b) = cal.betaFor(cat);
                  final n = (a + b - TwinCalibration.priorA - TwinCalibration.priorB).round();
                  return _Badge(icon: Icons.insights_outlined, text: '${cat.replaceAll('_', ' ')} ${_pct(p)}${n > 0 ? ' ($n seen)' : ''}', color: n > 0 ? AppColors.primaryGreen : theme.colorScheme.onSurfaceVariant);
                }(),
            ],
          ),
        ],
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.c});

  final TwinController c;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SectionCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Twin updates', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text('Live weather every 15 min, reports every 20 min; every change re-simulates the trip.', style: theme.textTheme.bodySmall),
          const SizedBox(height: 6),
          if (c.timeline.isEmpty) Text('Starting…', style: theme.textTheme.bodySmall),
          for (final e in c.timeline.take(12))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 42, child: Text(_hm(e.at), style: theme.textTheme.labelSmall)),
                  Icon(
                    switch (e.kind) {
                      'live' => Icons.cloud_sync_outlined,
                      'social' => Icons.campaign_outlined,
                      'learn' => Icons.school_outlined,
                      _ => Icons.science_outlined,
                    },
                    size: 14,
                  ),
                  const SizedBox(width: 6),
                  Expanded(child: Text(e.text, style: theme.textTheme.bodySmall)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
