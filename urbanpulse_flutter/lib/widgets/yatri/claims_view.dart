import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../agents/runtime/agent_kind.dart';
import '../../core/app_colors.dart';
import '../../models/itinerary/itinerary_parts.dart';

Color verdictColor(BuildContext context, Verdict v) => switch (v) {
  Verdict.confirmed => AppColors.primaryGreenDark,
  Verdict.mixed => AppColors.solidWarning,
  Verdict.contradicted => Theme.of(context).colorScheme.error,
  Verdict.unverified => Theme.of(context).colorScheme.outline,
};

String verdictLabel(Verdict v) => switch (v) {
  Verdict.confirmed => 'Confirmed',
  Verdict.mixed => 'Mixed',
  Verdict.contradicted => 'Contradicted',
  Verdict.unverified => 'Unverified',
};

IconData verdictIcon(Verdict v) => switch (v) {
  Verdict.confirmed => Icons.verified_rounded,
  Verdict.mixed => Icons.rule_rounded,
  Verdict.contradicted => Icons.report_gmailerrorred_rounded,
  Verdict.unverified => Icons.help_outline_rounded,
};

Future<void> _open(String url) async {
  final uri = Uri.tryParse(url);
  if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// What Khoji found about a place: each claim with its verdict and source, and
/// the guest reviews (usually the lower-rated ones) with the pages they came
/// from. Nothing here is shown without a link to where it was found.
class ClaimsView extends StatelessWidget {
  const ClaimsView({required this.claims, this.title = 'Checked by Khoji', super.key});

  final List<Claim> claims;
  final String title;

  @override
  Widget build(BuildContext context) {
    final facts = [for (final c in claims) if (!c.isReviews) c];
    final reviews = claims.where((c) => c.isReviews).firstOrNull;
    if (facts.isEmpty && reviews == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final khoji = AgentKind.khoji.color;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(AgentKind.khoji.icon, size: 15, color: khoji),
            const SizedBox(width: 6),
            Text(title, style: theme.textTheme.labelMedium?.copyWith(color: khoji, fontWeight: FontWeight.w800)),
          ],
        ),
        const SizedBox(height: 6),
        for (final c in facts) _ClaimRow(claim: c),
        if (reviews != null) _Reviews(claim: reviews),
      ],
    );
  }
}

class _ClaimRow extends StatelessWidget {
  const _ClaimRow({required this.claim});

  final Claim claim;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = verdictColor(context, claim.verdict);
    final source = claim.sources.firstOrNull;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(20)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(verdictIcon(claim.verdict), size: 12, color: color),
                const SizedBox(width: 3),
                Text(verdictLabel(claim.verdict), style: theme.textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(claim.text, style: theme.textTheme.bodySmall),
                if (source != null)
                  InkWell(
                    onTap: () => _open(source.url),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '${source.snippet == null || source.snippet!.isEmpty ? '' : '“${source.snippet}” · '}${source.source.isEmpty ? source.title : source.source}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Reviews extends StatelessWidget {
  const _Reviews({required this.claim});

  final Claim claim;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(Claim.reviewsLabel, style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
        Text('Usually the lower-rated reviews, since they show the problems.', style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 4),
        for (var i = 0; i < claim.reviewQuotes.length; i++)
          Container(
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(12),
              border: Border(left: BorderSide(color: AgentKind.khoji.color, width: 3)),
            ),
            child: InkWell(
              onTap: i < claim.sources.length ? () => _open(claim.sources[i].url) : null,
              child: Text(claim.reviewQuotes[i], style: theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
            ),
          ),
      ],
    );
  }
}
