import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../agents/live/live_mode_engine.dart';
import '../../core/formatting.dart';
import '../../models/itinerary/itinerary.dart';
import '../../screens/itinerary_map_link.dart';
import '../../services/live_location.dart';
import '../../services/live_map_data.dart';
import '../../services/voice/voice_service.dart';
import '../../state/app_scope.dart';
import '../../state/live_mode_controller.dart';
import '../../state/live_map_controller.dart' show distanceWords;

/// Live Mode beside the chat: while a trip is under way, switch on hands-free
/// and hear what is coming up through your earbuds or car, so the phone can stay
/// in your pocket.
class LiveModeView extends StatefulWidget {
  const LiveModeView({super.key});

  @override
  State<LiveModeView> createState() => _LiveModeViewState();
}

class _LiveModeViewState extends State<LiveModeView> {
  LiveModeController? _c;
  VoiceService? _voice;
  List<Itinerary> _trips = const [];
  Itinerary? _trip;
  int _dayNumber = 1;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c != null) return;
    final s = AppScope.of(context);
    _voice = s.voice..addListener(_onVoice);
    final data = ServiceLiveMapData();
    _c = LiveModeController(
      location: const DeviceLocation(),
      say: s.voice.say,
      describe: (p) => data.describe(p),
      onNavigate: (day, ref) {
        if (mounted) showDayOnLiveMap(context, day, navigateToRefId: ref);
      },
      keepAwake: (on) {
        try {
          on ? WakelockPlus.enable() : WakelockPlus.disable();
        } catch (_) {}
      },
    )..addListener(_onChange);
    _loadTrips();
  }

  void _loadTrips() {
    final trips = AppScope.of(context).itineraries.all().where((t) => t.days.isNotEmpty).toList();
    final now = DateTime.now();
    Itinerary? pick;
    for (final t in trips) {
      if (LiveModeController.dayForToday(t, now) != null) {
        pick = t;
        break;
      }
    }
    pick ??= trips.firstOrNull;
    setState(() {
      _trips = trips;
      _trip = pick;
      _dayNumber = pick == null ? 1 : (LiveModeController.dayForToday(pick, now)?.number ?? pick.days.first.number);
      _loaded = true;
    });
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  void _onVoice() {
    if (!mounted) return;
    setState(() {});
    final e = _voice?.error;
    if (e != null) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(e)));
  }

  @override
  void dispose() {
    _voice?.removeListener(_onVoice);
    _c?.removeListener(_onChange);
    _c?.dispose();
    super.dispose();
  }

  ItineraryDay? get _day => _trip?.days.where((d) => d.number == _dayNumber).firstOrNull;

  Future<void> _toggle() async {
    final c = _c!;
    if (c.active) {
      await c.stop();
      return;
    }
    final t = _trip, d = _day;
    if (t == null || d == null) return;
    await c.start(t, d);
  }

  Future<void> _speakQuestion() async {
    final v = _voice, c = _c;
    if (v == null || c == null) return;
    await v.toggle((words) => c.ask(words));
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (c == null || !_loaded) return const Center(child: CircularProgressIndicator());
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final day = _day;
    final onToday = _trip != null && LiveModeController.dayForToday(_trip!, DateTime.now()) != null;

    if (_trips.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.headset_mic_rounded, size: 56, color: scheme.primary),
              const SizedBox(height: 12),
              Text('Live Mode is for a trip under way', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800), textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text('Plan a trip with Yatri and save it. Then switch on hands-free here and hear what is next through your earbuds, with the phone in your pocket.', textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      );
    }

    final next = c.nextSlot;
    final metres = c.metresToNext;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        // --- the switch ---------------------------------------------------------------
        Card(
          color: c.active ? scheme.primaryContainer : null,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(c.active ? Icons.hearing_rounded : Icons.headset_mic_rounded, color: scheme.primary, size: 30),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(c.active ? 'Hands-free is on' : 'Hands-free', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                          Text(
                            c.active ? 'Listening to the clock and your position. Updates play through your earbuds or speaker.' : 'Hear what is coming up through your earbuds or car, so the phone can stay in your pocket.',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (!c.active) ...[
                  DropdownButtonFormField<String>(
                    initialValue: _trip?.id,
                    decoration: const InputDecoration(labelText: 'Trip', isDense: true),
                    items: [for (final t in _trips) DropdownMenuItem(value: t.id, child: Text('${t.destination} · ${dateRangeLabel(t.start, t.end)}', overflow: TextOverflow.ellipsis))],
                    onChanged: (id) => setState(() {
                      _trip = _trips.firstWhere((t) => t.id == id);
                      _dayNumber = LiveModeController.dayForToday(_trip!, DateTime.now())?.number ?? _trip!.days.first.number;
                    }),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final d in _trip?.days ?? const <ItineraryDay>[]) ChoiceChip(label: Text('Day ${d.number}'), selected: d.number == _dayNumber, onSelected: (_) => setState(() => _dayNumber = d.number)),
                    ],
                  ),
                  if (_trip != null && !onToday)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('This trip is not on today. Live Mode will follow the times of the day you pick, so you can try it out.', style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                    ),
                  const SizedBox(height: 12),
                ],
                SizedBox(
                  width: double.infinity,
                  child: c.active
                      ? FilledButton.icon(style: FilledButton.styleFrom(backgroundColor: scheme.error, foregroundColor: scheme.onError), onPressed: _toggle, icon: const Icon(Icons.stop_circle_rounded), label: const Text('Stop hands-free'))
                      : FilledButton.icon(onPressed: day == null || c.starting ? null : _toggle, icon: const Icon(Icons.play_circle_rounded), label: Text(c.starting ? 'Starting…' : 'Start hands-free')),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    ActionChip(avatar: const Icon(Icons.volume_up_rounded, size: 18), label: const Text('Test my earbuds'), onPressed: () => _voice?.say('This is Live Mode. If you can hear this, updates will reach you here.')),
                  ],
                ),
              ],
            ),
          ),
        ),

        if (c.active) ...[
          const SizedBox(height: 12),
          // --- what is next ---------------------------------------------------------------
          Card(
            child: ListTile(
              leading: Icon(Icons.flag_rounded, color: scheme.primary),
              title: Text(next == null ? 'Nothing left in the plan for today' : next.title, style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: next == null ? null : Text('${clock12(next.start)}${metres == null ? '' : ' · ${distanceWords(metres)} from you'}${c.locationStatus != LocationStatus.ok && metres == null ? ' · location not available' : ''}'),
              trailing: next?.location == null ? null : IconButton(tooltip: 'Navigate there', icon: const Icon(Icons.navigation_rounded), onPressed: () => c.ask('take me there')),
            ),
          ),
          const SizedBox(height: 12),
          Text('Ask', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (label, words) in const [("What's next", "what's next"), ('How far', 'how far'), ('Where am I', 'where am i'), ('Weather', 'weather'), ('Take me there', 'take me there'), ('Repeat', 'repeat')]) ActionChip(label: Text(label), onPressed: () => c.ask(words)),
              ActionChip(avatar: Icon(c.quiet ? Icons.volume_up_rounded : Icons.volume_off_rounded, size: 18), label: Text(c.quiet ? 'Resume updates' : 'Quiet for 30 min'), onPressed: () => c.ask(c.quiet ? 'resume' : 'quiet')),
            ],
          ),
          if (_voice != null && _voice!.canTranscribe) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: _voice!.state == VoiceState.transcribing ? null : _speakQuestion,
                icon: _voice!.state == VoiceState.transcribing ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(_voice!.recording ? Icons.stop_rounded : Icons.mic_rounded, color: _voice!.recording ? scheme.error : null),
                label: Text(_voice!.recording ? 'Tap to send' : 'Tap and ask out loud'),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Text('What I have said', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          if (c.log.isEmpty) Text('Nothing yet.', style: theme.textTheme.bodySmall),
          for (final u in c.log.reversed.take(12))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(padding: const EdgeInsets.only(top: 2, right: 8), child: Icon(_icon(u.kind), size: 16, color: scheme.primary)),
                  Expanded(child: Text(u.text, style: theme.textTheme.bodySmall)),
                ],
              ),
            ),
        ],
        const SizedBox(height: 16),
        Text(
          'Live Mode works while the app is open on your phone. Updates are read through the phone\'s audio, so they reach any connected Bluetooth earbuds or car. Times and places come from your plan; travel times are estimates.',
          style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }

  static IconData _icon(UpdateKind k) => switch (k) {
    UpdateKind.briefing => Icons.play_circle_outline_rounded,
    UpdateKind.arrived => Icons.place_rounded,
    UpdateKind.leaveNow => Icons.directions_walk_rounded,
    UpdateKind.late => Icons.schedule_rounded,
    UpdateKind.upcoming => Icons.upcoming_rounded,
    UpdateKind.meal => Icons.restaurant_rounded,
    UpdateKind.dayDone => Icons.flag_rounded,
    UpdateKind.info => Icons.chat_bubble_outline_rounded,
  };
}
