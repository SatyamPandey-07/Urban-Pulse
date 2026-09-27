import 'dart:async';

import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../agents/planner/trip_plan_handoff_agent.dart';
import '../../agents/core/llm_gateway.dart';
import '../../agents/receptionist/receptionist_agent.dart';
import '../../core/config.dart';
import '../../core/routes.dart';
import '../../models/trip_brief.dart';
import '../../models/trip_models.dart';
import '../../services/place_geocoder.dart';
import '../../services/voice/voice_service.dart';
import '../../state/activity_tracker.dart';
import '../../state/app_scope.dart';
import '../../state/yatri_controller.dart';
import '../../widgets/common.dart';
import '../../widgets/live/live_mode_view.dart';
import '../../widgets/yatri/brief_progress.dart';
import '../../widgets/yatri/chat_bubbles.dart';
import '../../widgets/yatri/chat_entry_view.dart';
import '../../widgets/yatri/yatri_composer.dart';
import '../dialogs/add_experience_dialog.dart';
import '../dialogs/provider_dashboard_dialog.dart';
import '../plan_itinerary_screen.dart';
import '../trip_brief_form_screen.dart';

/// Yatri AI — the receptionist that collects a trip brief by chat, then hands
/// it to the planner. All logic lives in [YatriController]; this widget is the
/// responsive shell: a single chat column on phones, a centred column on
/// tablets, and chat plus a live "Trip brief" panel on wide screens.
class YatriAiTab extends StatefulWidget {
  const YatriAiTab({super.key});

  @override
  State<YatriAiTab> createState() => _YatriAiTabState();
}

enum _YatriMode { chat, live }

class _YatriAiTabState extends State<YatriAiTab> {
  _YatriMode _mode = _YatriMode.chat;
  static const _wideBreakpoint = 900.0;
  static const _chatMaxWidth = 720.0;

  YatriController? _controller;
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _speech = SpeechToText();
  final _geocoder = PlaceGeocoder();
  final Map<int, GlobalKey> _entryKeys = {};
  bool _isListening = false;
  VoiceService? _voice;
  int _spokenUpTo = -1;
  String? _shownVoiceError;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final services = AppScope.of(context);
    _voice = services.voice..addListener(_onVoice);
    _controller =
        YatriController(
            receptionist: ReceptionistAgent(const GroqLlmGateway()),
            handoff: TripPlanHandoffAgent(),
            briefs: services.tripBriefs,
            trips: services.trips,
            hasKey: () => AppConfig.hasGroqKey,
            detectedCity: () => services.location.originCity,
            settingsNeeds: () => _settingsNeeds(services),
            onTripPlanned: () => services.activity.increment(TrackedAction.tripsPlanned),
            onTripSaved: () => services.activity.increment(TrackedAction.tripsSaved),
            geocode: _geocoder.lookup,
            toolkit: services.agentToolkit,
            itineraries: services.itineraries,
            cloud: services.cloud,
            tripPool: services.tripPool,
          )
          ..addListener(_onChanged)
          ..start();
    _inbox = services.yatriInbox..addListener(_takeFromInbox);
    // A trip handed in before this tab was first built.
    WidgetsBinding.instance.addPostFrameCallback((_) => _takeFromInbox());
  }

  ValueNotifier<TripBrief?>? _inbox;

  /// A trip handed to Yatri (Surprise Me): open it for review and planning.
  void _takeFromInbox() {
    if (!mounted || _inbox?.value == null) return;
    // After this frame: the screen that handed the trip over may still be
    // closing, and the form must open on top of the home screen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final inbox = _inbox;
      final b = inbox?.value;
      final c = _controller;
      if (!mounted || b == null || c == null) return;
      inbox!.value = null;
      // Starts a fresh conversation, stopping anything in progress.
      c.loadBrief(b, note: 'Here’s the surprise trip I picked for you. Check the brief, change anything you like, and confirm: my team will plan it.');
      unawaited(_openForm());
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  void dispose() {
    _inbox?.removeListener(_takeFromInbox);
    _voice?.removeListener(_onVoice);
    _voice?.cancel();
    _controller?.removeListener(_onChanged);
    _controller?.dispose();
    _input.dispose();
    _scroll.dispose();
    _speech.cancel();
    super.dispose();
  }

  static Set<AccessibilityNeed> _settingsNeeds(AppServices s) => {
    if (s.accessibility.isWheelchairModeEnabled) AccessibilityNeed.wheelchair,
    if (s.accessibility.isVisualAssistanceEnabled) AccessibilityNeed.visual,
    if (s.accessibility.isHearingAssistanceEnabled) AccessibilityNeed.hearing,
    if (s.accessibility.isServiceAnimalFriendlyOnly) AccessibilityNeed.serviceAnimal,
  };

  void _onChanged() {
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToLatest());
    _speakNewReplies();
  }

  /// Reads new agent messages and questions aloud when that is switched on.
  void _speakNewReplies() {
    final v = _voice;
    final c = _controller;
    if (v == null || c == null || c.entries.isEmpty) return;
    if (_spokenUpTo < 0) {
      // Whatever is already there when the chat opens is not read out.
      _spokenUpTo = c.entries.last.id;
      return;
    }
    for (final e in c.entries) {
      if (e.id <= _spokenUpTo) continue;
      _spokenUpTo = e.id;
      final text = switch (e) {
        AgentText(:final text) => text,
        QuestionEntry(:final question) => question.displayText,
        _ => null,
      };
      if (text != null) v.sayReply(text);
    }
  }

  void _onVoice() {
    if (!mounted) return;
    setState(() {});
    final err = _voice?.error;
    if (err != null && err != _shownVoiceError) {
      _shownVoiceError = err;
      showToast(context, err);
    } else if (err == null) {
      _shownVoiceError = null;
    }
  }

  /// A new question is scrolled to its top so the wording and the start of the
  /// card are both visible; anything else follows the bottom.
  void _scrollToLatest() {
    final c = _controller;
    if (c == null || !mounted || !_scroll.hasClients || c.entries.isEmpty) return;
    final last = c.entries.last;
    final ctx = _entryKeys[last.id]?.currentContext;
    if (last is QuestionEntry && last.isActive && ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        alignment: 0,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    _scroll.animateTo(
      _scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
    );
  }

  void _send(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    _input.clear();
    _controller?.sendText(trimmed);
  }

  Future<void> _toggleVoice() async {
    final v = _voice;
    // With a Groq key the words are transcribed by Groq (Whisper), which copes
    // with accents and mixed languages far better than the phone's recogniser.
    if (v != null && v.canTranscribe) {
      await v.toggle(_send);
      return;
    }
    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
      return;
    }
    final available = await _speech.initialize();
    if (!mounted) return;
    if (!available) {
      showToast(context, 'Voice input not available on device');
      return;
    }
    setState(() => _isListening = true);
    await _speech.listen(
      onResult: (result) {
        if (!result.finalResult) {
          _input.text = result.recognizedWords;
          return;
        }
        setState(() => _isListening = false);
        _send(result.recognizedWords);
      },
    );
  }

  Future<void> _openForm([TripBrief? _]) async {
    final c = _controller;
    if (c == null || c.busy) return;
    if (c.phase == YatriPhase.done) c.start();
    final services = AppScope.of(context);
    final result = await TripBriefFormScreen.open(
      context,
      initial: c.brief,
      now: c.now,
      detectedCity: services.location.originCity,
      settingsNeeds: _settingsNeeds(services),
      poolMatches: services.tripPool.available ? services.tripPool.matches : null,
    );
    if (result != null) await c.confirmBrief(result);
  }

  Future<void> _openAddExperienceDialog() async {
    final services = AppScope.of(context);
    final published = await AddExperienceDialog.show(
      context,
      services.experiences,
      detectedCity: services.location.city,
    );
    if (!mounted) return;
    showToast(
      context,
      published == null
          ? 'Failed to publish experience'
          : 'Experience published successfully!',
    );
  }

  Future<void> _openProviderDashboard() async {
    final services = AppScope.of(context);
    await ProviderDashboardDialog.show(
      context,
      repository: services.experiences,
      onAddNew: _openAddExperienceDialog,
    );
  }

  void _viewTrip(TripPlan trip) =>
      Navigator.of(context).pushNamed(Routes.tripDetail, arguments: trip);

  void _openItinerary(ItineraryEntry entry) {
    final c = _controller;
    if (c == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlanItineraryScreen(
          itinerary: entry.itinerary,
          saved: entry.saved,
          onSave: () => c.saveItinerary(entry),
          toolkit: AppScope.of(context).agentToolkit,
          onChanged: (updated) => c.updateItinerary(entry, updated),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (c == null) return const SizedBox.shrink();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: SegmentedButton<_YatriMode>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: _YatriMode.chat, icon: Icon(Icons.chat_bubble_outline_rounded), label: Text('Chat')),
              ButtonSegment(value: _YatriMode.live, icon: Icon(Icons.headset_mic_rounded), label: Text('Live mode')),
            ],
            selected: {_mode},
            onSelectionChanged: (m) => setState(() => _mode = m.first),
          ),
        ),
        // Both stay built, so Live Mode keeps running while the chat is open.
        Expanded(child: IndexedStack(index: _mode.index, children: [_chatView(c), const LiveModeView()])),
      ],
    );
  }

  Widget _chatView(YatriController c) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= _wideBreakpoint;
        final chat = _chatColumn(context, c, showStrip: !wide);
        final centered = Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _chatMaxWidth),
            child: chat,
          ),
        );
        if (!wide) return centered;

        final report = c.report;
        return Row(
          children: [
            Expanded(child: centered),
            SizedBox(
              width: 340,
              child: BriefPanel(
                items: c.progress,
                done: report.satisfied,
                total: report.required,
                onEdit: c.editQuestion,
                onOpenForm: _openForm,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _chatColumn(
    BuildContext context,
    YatriController c, {
    required bool showStrip,
  }) {
    final report = c.report;
    return Column(
      children: [
        _header(context, c, report.satisfied, report.required),
        if (showStrip) ...[
          BriefProgressStrip(items: c.progress, onEdit: c.editQuestion),
          const SizedBox(height: 8),
        ],
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final entry in c.entries)
                  Padding(
                    key: _entryKeys.putIfAbsent(entry.id, GlobalKey.new),
                    padding: const EdgeInsets.only(bottom: 14),
                    child: ChatEntryView(
                      entry: entry,
                      controller: c,
                      onOpenForm: _openForm,
                      onReview: _openForm,
                      onExample: _send,
                      onViewTrip: _viewTrip,
                      onOpenItinerary: _openItinerary,
                    ),
                  ),
                if (c.busy && c.phase != YatriPhase.planning)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 14),
                    child: TypingIndicator(),
                  ),
              ],
            ),
          ),
        ),
        YatriComposer(
          controller: _input,
          enabled: c.canType,
          hint: c.activeQuestion == null
              ? 'Tell me about your trip…'
              : 'Or type your answer…',
          isListening: _isListening || (_voice?.recording ?? false),
          transcribing: _voice?.state == VoiceState.transcribing,
          onSend: _send,
          onMic: _toggleVoice,
        ),
      ],
    );
  }

  Widget _header(BuildContext context, YatriController c, int done, int total) {
    final theme = Theme.of(context);
    final status = switch (c.phase) {
      YatriPhase.intake => 'Receptionist · collecting your trip details',
      YatriPhase.review => 'Ready for your review',
      YatriPhase.planning => 'Planner · building your itinerary',
      YatriPhase.done => 'Trip planned',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Yatri AI',
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                Text(
                  status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
          ProgressRing(done: done, total: total),
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (v) {
              switch (v) {
                case 'form':
                  _openForm();
                case 'reset':
                  c.start();
                case 'list':
                  _openAddExperienceDialog();
                case 'provider':
                  _openProviderDashboard();
                case 'speak':
                  _voice?.setSpeakReplies(!(_voice?.speakReplies ?? false));
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'form', child: Text('Open trip form')),
              const PopupMenuItem(value: 'reset', child: Text('Start over')),
              PopupMenuItem(
                value: 'speak',
                child: Row(children: [Icon((_voice?.speakReplies ?? false) ? Icons.volume_up_rounded : Icons.volume_off_rounded, size: 20), const SizedBox(width: 10), Text((_voice?.speakReplies ?? false) ? 'Reading replies aloud: on' : 'Read replies aloud: off')]),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'list', child: Text('List an experience')),
              const PopupMenuItem(value: 'provider', child: Text('Provider dashboard')),
            ],
          ),
        ],
      ),
    );
  }
}
