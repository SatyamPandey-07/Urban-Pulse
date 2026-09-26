import 'package:flutter/material.dart';

import '../core/formatting.dart';
import '../models/chat_message.dart';
import '../models/trip_models.dart';
import 'common.dart';

/// Renders one Yatri AI conversation entry — the Flutter form of `ChatAdapter`
/// and `item_chat_message.xml` / `item_typing_indicator.xml`: a right-aligned
/// user bubble, or a left-aligned assistant bubble that can carry a row of
/// quick-reply chips and a generated-trip preview card.
class ChatBubble extends StatelessWidget {
  const ChatBubble({
    required this.message,
    required this.onMcqOptionSelected,
    required this.onSaveTrip,
    required this.onViewTrip,
    super.key,
  });

  final ChatMessage message;
  final ValueChanged<String> onMcqOptionSelected;
  final ValueChanged<TripPlan> onSaveTrip;
  final ValueChanged<TripPlan> onViewTrip;

  @override
  Widget build(BuildContext context) {
    if (message.isLoading) return const _TypingIndicator();
    if (message.isUser) return _UserBubble(text: message.message);

    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.86,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(20),
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                ),
              ),
              child: InlineBoldText(
                message.message,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ),
          if (message.mcqQuestion case final mcq? when mcq.options.isNotEmpty)
            _McqChips(options: mcq.options, onSelected: onMcqOptionSelected),
          if (message.generatedTrip case final trip?)
            _TripPreviewCard(
              trip: trip,
              onSave: () => onSaveTrip(trip),
              onView: () => onViewTrip(trip),
            ),
        ],
      ),
    );
  }
}

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.82,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(4),
              bottomLeft: Radius.circular(20),
              bottomRight: Radius.circular(20),
            ),
          ),
          child: Text(
            text,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

class _McqChips extends StatelessWidget {
  const _McqChips({required this.options, required this.onSelected});

  final List<String> options;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final option in options)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ActionChip(
                label: Text(option),
                onPressed: () => onSelected(option),
              ),
            ),
        ],
      ),
    ),
  );
}

class _TripPreviewCard extends StatelessWidget {
  const _TripPreviewCard({
    required this.trip,
    required this.onSave,
    required this.onView,
  });

  final TripPlan trip;
  final VoidCallback onSave;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.9,
        ),
        child: SectionCard(
          padding: const EdgeInsets.all(16),
          borderWidth: 1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      trip.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Text(
                    '-${trip.co2SavedKg} kg CO2',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '🚆 ${trip.travelMode} • 🏨 ${trip.hotelName} • '
                '💰 ${rupees(trip.totalBudgetInr)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonal(
                      onPressed: onSave,
                      child: const Text('Save Trip'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: onView,
                      child: const Text('View Itinerary'),
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
}

/// Three-dot "assistant is thinking" row.
class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(20),
        ),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (i) {
              // Each dot peaks a third of a cycle after the previous one.
              final phase = (_controller.value - i * 0.2) % 1.0;
              final scale =
                  0.6 + 0.4 * (phase < 0.5 ? phase * 2 : (1 - phase) * 2);
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Transform.scale(
                  scale: scale,
                  child: CircleAvatar(
                    radius: 4,
                    backgroundColor: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
