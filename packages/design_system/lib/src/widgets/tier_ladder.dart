import 'package:core/core.dart';
import 'package:flutter/material.dart';

import 'package:design_system/src/theme/app_theme.dart';
import 'package:design_system/src/widgets/tier_chip.dart';

/// The four-rung tier ladder from the expanded chef card: a progress bar with
/// the thresholds printed beneath it and the chef's current rung highlighted.
///
/// **The scale is per-rung, not linear in points.** The four thresholds
/// (100 / 1,000 / 5,000 / 20,000) sit at 0 / ⅓ / ⅔ / 1 of the track and the
/// fill interpolates between them, so each tier is an equal stretch of bar. A
/// linear axis would squash Line Cook and Sous Chef into the first 5% and make
/// the ladder useless for exactly the chefs who need to read it.
class TierLadder extends StatelessWidget {
  const TierLadder({super.key, required this.score, this.height = 8});

  /// The chef's score, in points.
  final double score;

  final double height;

  /// Where [score] sits on the track, 0..1. Public for the test that pins the
  /// anchors — the mapping is the whole contract of this widget.
  static double positionFor(double score) {
    const rungs = ChefScoring.ladder;
    final anchors = <double>[
      for (final tier in rungs) ChefScoring.thresholds[tier]!,
    ];
    // The track starts *at* Line Cook, so a Home Cook reads as an empty bar.
    // That is the honest picture: they have not reached the first rung.
    if (score <= anchors.first) return 0;
    final segment = 1 / (anchors.length - 1);
    for (var i = 0; i < anchors.length - 1; i++) {
      final lo = anchors[i];
      final hi = anchors[i + 1];
      if (score < hi) {
        return (i + (score - lo) / (hi - lo)) * segment;
      }
    }
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final current = ChefScoring.tierFor(score);
    final color = TierChip.colorFor(current, theme.brightness);
    const rungs = ChefScoring.ladder;

    Widget row(List<Widget> children) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < children.length; i++)
          Expanded(
            child: Align(
              // First tick sits at the track's start, last at its end, the
              // rest centred — the labels have to land on the anchors.
              alignment: switch (i) {
                0 => Alignment.centerLeft,
                _ when i == children.length - 1 => Alignment.centerRight,
                _ => Alignment.center,
              },
              child: children[i],
            ),
          ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: positionFor(score),
            minHeight: height,
            backgroundColor: scheme.surfaceContainerHigh,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        row([
          for (final tier in rungs)
            Text(
              groupedCount(ChefScoring.thresholds[tier]!.round()),
              maxLines: 1,
              style: theme.textTheme.labelSmall?.copyWith(
                color: tier == current ? color : scheme.onSurfaceVariant,
                fontWeight: tier == current ? FontWeight.w800 : null,
              ),
            ),
        ]),
        row([
          for (final tier in rungs)
            Text(
              // Rung word only — "Master Chef" under a 4-way split does not fit
              // at any useful width, let alone at 2.0x text scale.
              tier.label.split(' ').first,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: tier == current ? color : scheme.onSurfaceVariant,
                fontWeight: tier == current ? FontWeight.w800 : null,
              ),
            ),
        ]),
      ],
    );
  }
}
