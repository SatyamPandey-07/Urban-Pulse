import 'package:flutter/material.dart';

import '../../agents/runtime/agent_kind.dart';
import '../common.dart';
import '../taskgraph/task_graph_view.dart';

/// The small round mark next to every assistant message.
class AgentAvatar extends StatelessWidget {
  const AgentAvatar({this.size = 30, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [scheme.primary, scheme.tertiary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.35),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Icon(Icons.auto_awesome, size: size * 0.55, color: scheme.onPrimary),
    );
  }
}

/// A left-aligned assistant message. [child] slots content (e.g. an answer
/// card) under the bubble, indented to line up with the text. When [agent] is
/// set (a planner agent speaking) its name is shown in its colour above the
/// bubble, and a “?” beside the text explains [why] it is being said.
class AgentBubble extends StatelessWidget {
  const AgentBubble({
    required this.text,
    this.child,
    this.maxWidth,
    this.agent,
    this.why,
    super.key,
  });

  final String text;
  final Widget? child;
  final double? maxWidth;
  final AgentKind? agent;
  final String? why;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = agent;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (a == null)
          const AgentAvatar()
        else
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(shape: BoxShape.circle, color: a.color.withValues(alpha: 0.18)),
            child: Icon(a.icon, size: 17, color: agentTextColor(context, a)),
          ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (a != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3, left: 4),
                  child: Text(
                    '${a.displayName} · ${a.role}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: agentTextColor(context, a),
                    ),
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  constraints: BoxConstraints(maxWidth: maxWidth ?? 560),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHigh,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(4),
                      topRight: Radius.circular(20),
                      bottomLeft: Radius.circular(20),
                      bottomRight: Radius.circular(20),
                    ),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
                      width: 1,
                    ),
                  ),
                  child: why == null
                      ? InlineBoldText(text, style: theme.textTheme.bodyMedium)
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(child: InlineBoldText(text, style: theme.textTheme.bodyMedium)),
                            const SizedBox(width: 6),
                            WhyButton(agent: a ?? AgentKind.yatri, title: text, why: why!),
                          ],
                        ),
                ),
              ),
              if (child != null) ...[const SizedBox(height: 10), child!],
            ],
          ),
        ),
      ],
    );
  }
}

class UserBubble extends StatelessWidget {
  const UserBubble({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(4),
            bottomLeft: Radius.circular(20),
            bottomRight: Radius.circular(20),
          ),
          boxShadow: [
            BoxShadow(
              color: theme.colorScheme.primary.withValues(alpha: 0.25),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          text,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// Three-dot "assistant is thinking" row.
class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key});

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
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
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        const AgentAvatar(),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(20),
          ),
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) {
                final phase = (_controller.value - i * 0.2) % 1.0;
                final scale =
                    0.6 + 0.4 * (phase < 0.5 ? phase * 2 : (1 - phase) * 2);
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Transform.scale(
                    scale: scale,
                    child: CircleAvatar(
                      radius: 4,
                      backgroundColor: scheme.onSurfaceVariant,
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ],
    );
  }
}
