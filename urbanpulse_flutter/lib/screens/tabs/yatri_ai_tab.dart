import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../core/routes.dart';
import '../../models/trip_models.dart';
import '../../state/activity_tracker.dart';
import '../../state/app_scope.dart';
import '../../state/yatri_ai_controller.dart';
import '../../widgets/chat_bubble.dart';
import '../../widgets/common.dart';
import '../dialogs/add_experience_dialog.dart';
import '../dialogs/provider_dashboard_dialog.dart';

/// Port of `YatriAiFragment` / `fragment_yatri_ai.xml` — the conversation view.
/// All reasoning lives in [YatriAiController]; this widget is the chat list, the
/// suggestion-chip rail and the composer (which flips between mic and send just
/// as the original `FloatingActionButton` did).
class YatriAiTab extends StatefulWidget {
  const YatriAiTab({super.key});

  @override
  State<YatriAiTab> createState() => _YatriAiTabState();
}

class _YatriAiTabState extends State<YatriAiTab> {
  YatriAiController? _controller;
  final _input = TextEditingController();
  final _scrollController = ScrollController();
  final _speech = SpeechToText();
  bool _isListening = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller ??= YatriAiController(AppScope.of(context))
      ..addListener(_onMessagesChanged);
  }

  @override
  void dispose() {
    _controller?.removeListener(_onMessagesChanged);
    _controller?.dispose();
    _input.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onMessagesChanged() {
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  void _send(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    _input.clear();
    _controller?.send(trimmed);
  }

  /// Replaces `RecognizerIntent.ACTION_RECOGNIZE_SPEECH`: tapping the mic starts
  /// dictation, and the recognised phrase is sent as a message.
  Future<void> _startVoiceInput() async {
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

  Future<void> _openAddExperienceDialog() async {
    final services = AppScope.of(context);
    final published = await AddExperienceDialog.show(
      context,
      services.experiences,
      detectedCity: services.location.city,
    );
    if (!mounted) return;
    if (published == null) {
      showToast(context, 'Failed to publish experience');
      return;
    }
    showToast(context, 'Experience published successfully!');
    _controller?.announcePublishedExperience(published);
  }

  Future<void> _openProviderDashboard() async {
    final services = AppScope.of(context);
    await ProviderDashboardDialog.show(
      context,
      repository: services.experiences,
      onAddNew: _openAddExperienceDialog,
    );
  }

  Future<void> _saveTrip(TripPlan trip) async {
    final services = AppScope.of(context);
    await services.trips.addTrip(trip);
    await services.activity.increment(TrackedAction.tripsSaved);
    if (!mounted) return;
    showToast(context, '✅ Saved "${trip.title}" to My Trips!');
  }

  void _viewTrip(TripPlan trip) =>
      Navigator.of(context).pushNamed(Routes.tripDetail, arguments: trip);

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) return const SizedBox.shrink();
    final messages = controller.messages;

    return Column(
      children: [
        _header(context, controller),
        _suggestionChips(context),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            itemCount: messages.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) => ChatBubble(
              message: messages[index],
              onMcqOptionSelected: _send,
              onSaveTrip: _saveTrip,
              onViewTrip: _viewTrip,
            ),
          ),
        ),
        _composer(context),
      ],
    );
  }

  Widget _header(BuildContext context, YatriAiController controller) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Yatri AI',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Active • Smart Mobility Assistant',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: controller.clearChat,
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  Widget _suggestionChips(BuildContext context) {
    // Same twelve shortcuts as the Kotlin chip group, in the same order.
    final chips = <(String, VoidCallback)>[
      (
        '2-Hour Micro Experiences',
        () => _send(
          'Find local micro-experiences within 2 hours near my location',
        ),
      ),
      (
        'Adapt Plan (Rain / Delay)',
        () => _send(
          'Adapt my plan: It started raining and I only have 90 minutes',
        ),
      ),
      (
        'Family & Child-Friendly',
        () => _send(
          'Find family and child-friendly cultural experiences near me',
        ),
      ),
      ('+ List Experience', _openAddExperienceDialog),
      ('Provider Hub (My Listings)', _openProviderDashboard),
      ('Plan Trip to Lonavala 🌲', () => _send('Plan a trip to Kedarnath')),
      ('Nearest Hospitals', () => _send('Suggest some hospital near me')),
      (
        'Live Traffic',
        () => _send('What is the traffic status around my current area?'),
      ),
      (
        'AQI & Weather',
        () =>
            _send('What is the air quality index and weather at my location?'),
      ),
      (
        'Eco Routes',
        () => _send(
          'Find nearby solar eco-resorts with wheelchair accessibility',
        ),
      ),
      (
        'Report Hazard',
        () => _send('Report a road obstruction at my GPS coordinates'),
      ),
      ('Emergency SOS', () => _send('Emergency assistance at my location')),
    ];

    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final (label, onTap) = chips[index];
          return Center(
            child: ActionChip(label: Text(label), onPressed: onTap),
          );
        },
      ),
    );
  }

  Widget _composer(BuildContext context) {
    final hasText = _input.text.trim().isNotEmpty;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onChanged: (_) => setState(() {}),
                onSubmitted: _send,
                decoration: const InputDecoration(
                  hintText: 'Ask Yatri AI...',
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FloatingActionButton(
              heroTag: 'yatri-send',
              tooltip: hasText ? 'Send' : 'Speak to Yatri AI',
              onPressed: hasText ? () => _send(_input.text) : _startVoiceInput,
              child: Icon(
                hasText
                    ? Icons.send
                    : _isListening
                    ? Icons.stop
                    : Icons.mic,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
