import 'package:flutter/material.dart';

import '../../core/formatting.dart';
import '../../models/trip_brief.dart';
import '../../models/trip_models.dart';
import '../../models/yatri_question.dart';
import '../../state/yatri_controller.dart';
import '../common.dart';
import 'answer_view.dart';
import 'brief_summary.dart';
import 'chat_bubbles.dart';
import '../../agents/runtime/agent_kind.dart';
import '../taskgraph/task_graph_card.dart';
import 'option_card.dart';
import 'route_map_card.dart';

/// Renders one row of the Yatri conversation.
class ChatEntryView extends StatelessWidget {
  const ChatEntryView({
    required this.entry,
    required this.controller,
    required this.onOpenForm,
    required this.onReview,
    required this.onExample,
    required this.onViewTrip,
    this.mapTileLayer,
    super.key,
  });

  final ChatEntry entry;
  final YatriController controller;
  final VoidCallback onOpenForm;
  final ValueChanged<TripBrief> onReview;
  final ValueChanged<String> onExample;
  final ValueChanged<TripPlan> onViewTrip;

  /// Replaces the OpenStreetMap tiles in the route map (tests only).
  final Widget? mapTileLayer;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    switch (e) {
      case UserText():
        return UserBubble(text: e.text);
      case AgentText():
        return AgentBubble(text: e.text);
      case QuestionEntry():
        final q = e.question;
        final planner = _plannerFor(q);
        return AgentBubble(
          text: q.displayText,
          agent: planner,
          why: q.why,
          child: e.isActive
              ? AnswerCard(
                  question: q,
                  // Planner questions arrive while the plan is busy; that is
                  // exactly when they must be answerable.
                  disabled: controller.busy && !q.id.startsWith('plan.'),
                  onSubmit: (a) => controller.answer(q, a),
                  entryId: e.id,
                )
              : null,
        );
      case WelcomeEntry():
        return _WelcomeCard(onExample: onExample, onOpenForm: onOpenForm);
      case NoKeyEntry():
        return _NoKeyCard(rejected: e.rejected, onOpenForm: onOpenForm);
      case ErrorEntry():
        return _ErrorCard(
          entry: e,
          onRetry: () => controller.retry(e),
          onOpenForm: onOpenForm,
        );
      case ReviewReadyEntry():
        final latest = controller.entries.whereType<ReviewReadyEntry>().last == e;
        return _ReviewReadyCard(
          brief: e.brief,
          enabled: latest && controller.phase == YatriPhase.review && !controller.busy,
          onReview: () => onReview(controller.brief),
        );
      case PlanningEntry():
        return const _PlanningCard();
      case TaskGraphEntry():
        return TaskGraphCard(graph: e.graph, clock: e.clock);
      case RouteMapEntry():
        if (!e.ready) return const _MapLoadingCard();
        return Padding(
          padding: const EdgeInsets.only(left: 38),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: RouteMapCard(
              origin: e.originPoint!,
              destination: e.destinationPoint!,
              originName: e.origin,
              destinationName: e.destination,
              modes: e.modes,
              shown: e.shown,
              onShow: (m) => controller.showMode(e, m),
              tileLayer: mapTileLayer,
            ),
          ),
        );
      case PlanEntry():
        return Padding(
          padding: const EdgeInsets.only(left: 38),
          child: TripPreviewCard(
            trip: e.plan,
            saved: e.saved,
            onSave: () => controller.saveTrip(e),
            onView: () => onViewTrip(e.plan),
          ),
        );
    }
  }
}

/// The planner agent behind a question (by name), if it is one.
AgentKind? _plannerFor(YatriQuestion q) {
  final name = q.agent;
  if (name == null) return null;
  for (final a in AgentKind.values) {
    if (a.name == name) return a;
  }
  return null;
}

/// The card that holds an active question's answer widget.
class AnswerCard extends StatelessWidget {
  const AnswerCard({
    required this.question,
    required this.onSubmit,
    required this.entryId,
    this.disabled = false,
    super.key,
  });

  final YatriQuestion question;
  final ValueChanged<YatriAnswer> onSubmit;
  final int entryId;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final showHint =
        question.hint != null &&
        (question.reason != IssueKind.unconfirmed || question.attempt > 0);

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 150),
      opacity: disabled ? 0.55 : 1,
      child: AbsorbPointer(
        absorbing: disabled,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showHint)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: scheme.error.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline_rounded, size: 18, color: scheme.error),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          question.hint!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              buildAnswerView(
                question,
                key: ValueKey('answer-$entryId'),
                onSubmit: onSubmit,
              ),
              if (const {'destination', 'origin', 'travellers'}.contains(question.id))
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    'Or type your answer in the message box below.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.child, this.tint});

  final Widget child;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = tint ?? scheme.primary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            base.withValues(alpha: 0.16),
            (tint ?? scheme.tertiary).withValues(alpha: 0.07),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: base.withValues(alpha: 0.35)),
      ),
      child: child,
    );
  }
}

class _WelcomeCard extends StatelessWidget {
  const _WelcomeCard({required this.onExample, required this.onOpenForm});

  final ValueChanged<String> onExample;
  final VoidCallback onOpenForm;

  static const _examples = [
    'Munnar with my family of 4 next weekend',
    'Solo eco trip to Rishikesh, step-free routes only',
    'Weekend in Coorg for 2, budget ₹20,000',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return _HeroCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const AgentAvatar(size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Plan a greener, more accessible trip',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Tell me about your trip in your own words — destination, who’s '
            'coming, dates, budget. I’ll ask for whatever’s missing, one '
            'question at a time.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final ex in _examples)
                OptionPill(
                  option: QuestionOption(id: ex, label: ex, icon: Icons.chat_bubble_outline),
                  selected: false,
                  onTap: () => onExample(ex),
                ),
            ],
          ),
          const SizedBox(height: 14),
          CtaButton(
            tonal: true,
            icon: Icons.edit_note_rounded,
            label: 'Prefer a form? Fill it in instead',
            onPressed: onOpenForm,
          ),
        ],
      ),
    );
  }
}

class _NoKeyCard extends StatelessWidget {
  const _NoKeyCard({required this.rejected, required this.onOpenForm});

  final bool rejected;
  final VoidCallback onOpenForm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return _HeroCard(
      tint: scheme.error,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.key_off_rounded, color: scheme.error),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  rejected ? 'Groq rejected the API key' : 'Yatri chat needs a Groq API key',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            rejected
                ? 'The configured GROQ_API_KEY was not accepted. Put a valid key in '
                    'urbanpulse_flutter/config.json and relaunch with ./run.sh.'
                : 'Add GROQ_API_KEY to urbanpulse_flutter/config.json and relaunch '
                    'with ./run.sh. The trip form works without it.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          CtaButton(
            icon: Icons.edit_note_rounded,
            label: 'Use the form instead',
            onPressed: onOpenForm,
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({
    required this.entry,
    required this.onRetry,
    required this.onOpenForm,
  });

  final ErrorEntry entry;
  final VoidCallback onRetry;
  final VoidCallback onOpenForm;

  @override
  Widget build(BuildContext context) {
    return AgentBubble(
      text: '${entry.message} Want to try again?',
      child: Row(
        children: [
          Expanded(
            child: CtaButton(
              icon: Icons.refresh_rounded,
              label: 'Retry',
              onPressed: onRetry,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: CtaButton(
              tonal: true,
              icon: Icons.edit_note_rounded,
              label: 'Open form',
              onPressed: onOpenForm,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewReadyCard extends StatelessWidget {
  const _ReviewReadyCard({
    required this.brief,
    required this.enabled,
    required this.onReview,
  });

  final TripBrief brief;
  final bool enabled;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final rows = briefSummaryRows(brief);
    return Padding(
      padding: const EdgeInsets.only(left: 38),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: scheme.primary.withValues(alpha: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.fact_check_rounded, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Your trip brief',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (final (label, value) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 96,
                      child: Text(
                        label,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        value,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            CtaButton(
              icon: Icons.tune_rounded,
              label: 'Review & confirm',
              onPressed: enabled ? onReview : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanningCard extends StatelessWidget {
  const _PlanningCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    Widget step(String label, {required bool done}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          done
              ? Icon(Icons.check_circle_rounded, size: 20, color: scheme.primary)
              : const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
          const SizedBox(width: 10),
          Text(label, style: theme.textTheme.bodyMedium),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(left: 38),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            step('Receptionist · trip brief saved', done: true),
            step('Planner · building your sustainable itinerary…', done: false),
          ],
        ),
      ),
    );
  }
}

/// Shown for the moment it takes to look the two places up.
class _MapLoadingCard extends StatelessWidget {
  const _MapLoadingCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 38),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
            const SizedBox(width: 12),
            Text('Plotting your route…', style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

/// The generated plan with Save / View actions.
class TripPreviewCard extends StatelessWidget {
  const TripPreviewCard({
    required this.trip,
    required this.onSave,
    required this.onView,
    this.saved = false,
    super.key,
  });

  final TripPlan trip;
  final bool saved;
  final VoidCallback onSave;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
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
            const SizedBox(height: 4),
            Text(
              trip.travelDates,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.directions_subway_outlined, size: 14, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(trip.travelMode, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.hotel_outlined, size: 14, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(trip.hotelName, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.account_balance_wallet_outlined, size: 14, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(rupees(trip.totalBudgetInr), style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: saved ? null : onSave,
                    child: saved
                        ? const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.check_rounded, size: 16),
                              SizedBox(width: 6),
                              Text('Saved'),
                            ],
                          )
                        : const Text('Save Trip'),
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
    );
  }
}
