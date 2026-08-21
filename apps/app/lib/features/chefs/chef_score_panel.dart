import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

import 'package:app/features/chefs/chef_detail_common.dart';

/// The left half of the expanded chef card: what the score is made of and how
/// far the next tier is. Split out of `chef_detail_sheet.dart` (OPT-A8).
///
/// The arithmetic it renders is `ChefScoring` in core, which mirrors the SQL —
/// see Gotcha 19 before changing a weight or a threshold on either side.

/// "Why this score" + the tier ladder.
class ChefScorePanel extends StatelessWidget {
  const ChefScorePanel({
    super.key,required this.standing, required this.color});

  final ChefStanding standing;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final breakdown = ChefScoring.breakdown(
      likes: standing.totalLikes,
      saves: standing.totalSaves,
      views: standing.totalViews,
    );
    final gap = standing.pointsToNextLabel;
    final next = standing.nextTier;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const ChefKicker(text: 'Why this score'),
        const SizedBox(height: AppSpacing.xs),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(
                standing.scoreLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800, color: color),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              'points',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        for (final row in breakdown) ...[
          ScoreContributionBar(
            contribution: row,
            total: standing.chefScore,
            color: color,
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Public recipes only. Private recipes never count toward score or '
          'rank.',
          style:
              theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const Divider(height: AppSpacing.xl),
        const ChefKicker(text: 'Tier ladder'),
        const SizedBox(height: AppSpacing.md),
        TierLadder(score: standing.chefScore),
        const SizedBox(height: AppSpacing.md),
        if (gap == null || next == null)
          Text(
            'Master Chef is the top tier — there is nothing above this.',
            style: theme.textTheme.bodySmall,
          )
        else
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$gap points to ${next.label}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(text: ' — about ${_closingLine(standing)}.'),
              ],
            ),
            style: theme.textTheme.bodySmall,
          ),
      ],
    );
  }

  /// "1,962 more saves, or 3,270 more likes" — the gap expressed in the two
  /// inputs a chef can actually influence. Views are left out: they are not
  /// something a chef adds on purpose.
  static String _closingLine(ChefStanding standing) {
    final saves = ChefScoring.unitsToNext(standing.chefScore, ChefScoring.saveWeight);
    final likes = ChefScoring.unitsToNext(standing.chefScore, ChefScoring.likeWeight);
    return '${groupedCount(saves ?? 0)} more saves, '
        'or ${groupedCount(likes ?? 0)} more likes';
  }
}
