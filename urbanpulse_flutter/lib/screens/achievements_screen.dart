import 'package:flutter/material.dart';

import '../models/gamification.dart';
import '../state/app_scope.dart';
import '../widgets/common.dart';

/// Port of `AchievementsActivity` + `ChallengesFragment` / `BadgesFragment`
/// (`activity_achievements.xml`, `fragment_challenges.xml`, `fragment_badges.xml`)
/// — progression, active challenges and the badge grid in one tabbed screen.
///
/// The Kotlin screen also had a "Connect Web3 Wallet" button that generated a
/// random hex string and unlocked a badge locally. It was not backed by any
/// wallet, chain or signature, so it is not reproduced here; see the migration
/// notes in README.md.
class AchievementsScreen extends StatelessWidget {
  const AchievementsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Achievements'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Challenges'),
              Tab(text: 'Badges'),
            ],
          ),
        ),
        body: AnimatedBuilder(
          animation: services.gamification,
          builder: (context, _) => Column(
            children: [
              _progressHeader(context),
              Expanded(
                child: TabBarView(
                  children: [
                    _ChallengesList(
                      challenges: services.gamification.activeChallenges,
                    ),
                    _BadgesGrid(badges: services.gamification.allBadges),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _progressHeader(BuildContext context) {
    final gamification = AppScope.of(context).gamification;
    final theme = Theme.of(context);
    final nextLevelXp = gamification.nextLevelXp;
    final progress = nextLevelXp > 0
        ? (gamification.xp / nextLevelXp).clamp(0.0, 1.0)
        : 0.0;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: StatTile(
                    label: 'LEVEL',
                    value: '${gamification.level}',
                    caption: '${gamification.xp} / $nextLevelXp XP',
                  ),
                ),
                Expanded(
                  child: StatTile(
                    label: 'PULSE',
                    value: '${gamification.pulse}',
                    valueColor: theme.colorScheme.primary,
                  ),
                ),
                Expanded(
                  child: StatTile(
                    label: 'STREAK',
                    value: '${gamification.streak} days',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(value: progress, minHeight: 8),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChallengesList extends StatelessWidget {
  const _ChallengesList({required this.challenges});

  final List<Challenge> challenges;

  @override
  Widget build(BuildContext context) {
    if (challenges.isEmpty) {
      return const EmptyState(
        message: 'No active challenges right now.',
        icon: Icons.flag_outlined,
      );
    }
    final theme = Theme.of(context);
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      itemCount: challenges.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final challenge = challenges[index];
        final progress = challenge.target > 0
            ? challenge.progress / challenge.target
            : 0.0;
        return SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                challenge.type.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                challenge.title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: progress.clamp(0.0, 1.0),
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '+${challenge.xpReward} XP • +${challenge.pulseReward} PULSE',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _BadgesGrid extends StatelessWidget {
  const _BadgesGrid({required this.badges});

  final List<AchievementBadge> badges;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.85,
      ),
      itemCount: badges.length,
      itemBuilder: (context, index) {
        final badge = badges[index];
        return Opacity(
          opacity: badge.isUnlocked ? 1.0 : 0.4,
          child: SectionCard(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(badge.icon, size: 30, color: theme.colorScheme.primary),
                const SizedBox(height: 8),
                Text(
                  badge.title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (!badge.isUnlocked) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${badge.progress}/${badge.target}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
