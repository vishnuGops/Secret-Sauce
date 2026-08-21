import 'package:core/core.dart';
import 'package:flutter/material.dart';

import 'package:design_system/src/theme/app_theme.dart';

/// One line of the expanded chef card's "Why this score" panel:
/// `1,980 likes × 3` on the left, `5,940` on the right, and a bar showing this
/// input's share of the total.
///
/// The multipliers are printed deliberately — the panel exists to answer "why
/// am I here", and a bar with no weights answers only "which is biggest".
class ScoreContributionBar extends StatelessWidget {
  const ScoreContributionBar({
    super.key,
    required this.contribution,
    required this.total,
    required this.color,
  });

  final ScoreContribution contribution;

  /// The chef's whole score, the denominator for the bar's share.
  final double total;

  /// Tier accent for the fill.
  final Color color;

  /// `× 3`, `× 0.2` — the weight without a pointless trailing zero.
  static String weightLabel(double weight) =>
      weight == weight.roundToDouble()
          ? weight.toStringAsFixed(0)
          : weight.toString();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final share =
        total <= 0 ? 0.0 : (contribution.points / total).clamp(0, 1).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${groupedCount(contribution.count)} ${contribution.label} '
                '× ${weightLabel(contribution.weight)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              groupedScore(contribution.points),
              maxLines: 1,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: share,
            minHeight: 8,
            backgroundColor: scheme.surfaceContainerHigh,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}
