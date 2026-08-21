import 'package:core/core.dart';
import 'package:flutter/material.dart';

import 'package:design_system/src/layout/adaptive.dart';
import 'package:design_system/src/theme/app_theme.dart';
import 'package:design_system/src/widgets/chef_avatar.dart';
import 'package:design_system/src/widgets/tier_chip.dart';

/// Which shape a [ChefStandingCard] takes.
enum ChefCardVariant {
  /// The full-width "podium" row: medal, tier spine, four labelled stat chips.
  /// What `/chefs` shows on a phone and what the board was before the page grew
  /// a second column.
  podium,

  /// The dense row used inside the chefs page's 404px leaderboard panel: a rank
  /// pill instead of a medal, no stat chips, and the tier progress drawn as a
  /// 3px bar across the bottom edge. Everything dropped here is on the spotlight
  /// cards beside it or in the expanded card a tap away.
  board,
}

/// One row of the chefs leaderboard — the design's "podium" card.
///
/// Four things carry the ranking, in the order the eye reaches them: a tier
/// spine down the left edge, a medal glyph for the top three (a numeral for
/// everyone else), the tier-tinted avatar, and the score with its `27% to
/// Master` line. Tapping opens the expanded chef card.
///
/// Unlike [RecipeCard] this tile is **not** fixed-height: it is a list row and
/// may grow, so a long name or a large text scale costs vertical space rather
/// than overflowing. The stats row and the score column are still built to
/// degrade — both are the shape that overflowed in B016.
class ChefStandingCard extends StatelessWidget {
  const ChefStandingCard({
    super.key,
    required this.standing,
    required this.onTap,
    this.dense,
    this.variant = ChefCardVariant.podium,
  });

  final ChefStanding standing;

  /// Opens the expanded card. Required: a row with no destination was the
  /// complaint this design answers.
  final VoidCallback onTap;

  /// Drops the stat labels and tightens the metrics, the way the compact
  /// leaderboard has always rendered. Defaults to `context.isCompact`.
  /// Ignored by [ChefCardVariant.board], which is dense by construction.
  final bool? dense;

  /// Which of the two row shapes to draw. See [ChefCardVariant].
  final ChefCardVariant variant;

  /// Width of the tier spine on the card's leading edge.
  static const double spineWidth = 6;

  /// Medal glyph for a podium rank, or null below the top three.
  static IconData? medalFor(int rank) => switch (rank) {
    1 => Icons.workspace_premium,
    2 || 3 => Icons.military_tech,
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tier = TierChip.colorFor(standing.chefTier, theme.brightness);

    if (variant == ChefCardVariant.board) {
      return _BoardRow(standing: standing, onTap: onTap, color: tier);
    }

    final compact = dense ?? context.isCompact;
    final gap = compact ? 12.0 : 14.0;

    return Card(
      // The spine runs to the card's edge, so the child has to be clipped to
      // the same rounded rectangle.
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        // A `Stack` with a positioned spine, not a stretched `Row`: the card
        // sits in a `ListView`, so its height is unbounded during layout and
        // `CrossAxisAlignment.stretch` would hand the spine an infinite height.
        // The alternative, `IntrinsicHeight`, costs an extra layout pass on
        // every one of 50 rows.
        child: Stack(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                (compact ? 12 : AppSpacing.md) + spineWidth,
                12,
                compact ? 12 : AppSpacing.md,
                12,
              ),
              child: Row(
                children: [
                  _RankBlock(standing: standing, color: tier, compact: compact),
                  SizedBox(width: gap),
                  ChefAvatar(
                    name: standing.displayName,
                    avatarUrl: standing.avatarUrl,
                    radius: compact ? 18 : 22,
                    backgroundColor: Color.alphaBlend(
                      tier.withValues(alpha: 0.18),
                      scheme.surfaceContainerHigh,
                    ),
                    foregroundColor: tier,
                  ),
                  SizedBox(width: gap),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _NameLine(standing: standing, compact: compact),
                        const SizedBox(height: AppSpacing.xs),
                        _Stats(standing: standing, compact: compact),
                      ],
                    ),
                  ),
                  SizedBox(width: compact ? AppSpacing.sm : gap),
                  _ScoreBlock(
                    standing: standing,
                    color: tier,
                    compact: compact,
                  ),
                ],
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: spineWidth,
              child: ColoredBox(color: tier),
            ),
          ],
        ),
      ),
    );
  }
}

/// The dense row for the chefs page's leaderboard panel.
///
/// Reads left to right: rank pill, avatar wearing its tier dot, name over the
/// tier and recipe count, then the score and how far the next tier is. A 3px
/// tier bar across the bottom edge repeats that last number as a shape — the
/// panel is 404px wide, and a progress bar survives that better than a second
/// line of text does.
///
/// No medal: the panel sits beside three rails of spotlight cards that already
/// decorate the top of the board, and two ornaments competing at 404px was what
/// the draft's own row avoided.
class _BoardRow extends StatelessWidget {
  const _BoardRow({
    required this.standing,
    required this.onTap,
    required this.color,
  });

  final ChefStanding standing;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
              child: Row(
                children: [
                  _RankPill(rank: standing.chefRank, color: color),
                  const SizedBox(width: AppSpacing.md),
                  ChefAvatar(
                    name: standing.displayName,
                    avatarUrl: standing.avatarUrl,
                    radius: 18,
                    tier: standing.chefTier,
                    surfaceColor: scheme.surface,
                    backgroundColor: Color.alphaBlend(
                      color.withValues(alpha: 0.16),
                      scheme.surfaceContainerHigh,
                    ),
                    foregroundColor: color,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          standing.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        // Wrap, not Row: at 2.0x text scale the chip alone is
                        // most of a 404px panel's text column.
                        Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: 2,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            TierChip(tier: standing.chefTier, dense: true),
                            Text(
                              countOf(standing.publicRecipeCount, 'recipes'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  _ScoreBlock(standing: standing, color: color, compact: true),
                ],
              ),
            ),
            SizedBox(
              height: 3,
              child: LinearProgressIndicator(
                value: standing.tierProgress,
                minHeight: 3,
                backgroundColor: scheme.surfaceContainerHigh,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The rank as a tinted disc. Ties share a rank, so two discs can read `4`.
class _RankPill extends StatelessWidget {
  const _RankPill({required this.rank, required this.color});

  final int rank;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.14),
      ),
      // Ranks past two digits would otherwise clip the disc, as would 2.0x
      // text scale on a two-digit rank.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Text(
            '$rank',
            maxLines: 1,
            style: theme.textTheme.labelLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

/// Medal + `#1` for the podium, numeral + `rank` for everyone below it. Ties
/// share a rank (`dense_rank`), so two rows can both read `4` — and two rows
/// can both wear the same medal.
class _RankBlock extends StatelessWidget {
  const _RankBlock({
    required this.standing,
    required this.color,
    required this.compact,
  });

  final ChefStanding standing;
  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final medal = ChefStandingCard.medalFor(standing.chefRank);
    final width = compact ? 38.0 : 46.0;

    return SizedBox(
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (medal != null)
            Icon(medal, size: compact ? 22 : 26, color: color)
          else
            FittedBox(
              child: Text(
                '${standing.chefRank}',
                style: theme.textTheme.titleLarge?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
            ),
          FittedBox(
            child: Text(
              medal != null ? '#${standing.chefRank}' : 'rank',
              style: theme.textTheme.labelSmall?.copyWith(
                color:
                    medal != null ? color : theme.colorScheme.onSurfaceVariant,
                fontWeight: medal != null ? FontWeight.w800 : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Name plus dense tier chip — side by side with room, **stacked** without.
///
/// Sharing a line is what the design draws, but on a phone the chip takes
/// roughly a third of the text column and the name ellipsises to "Amara…" for
/// nearly every chef. Stacking costs a line and keeps the name, which is the
/// one thing a leaderboard row must not lose.
class _NameLine extends StatelessWidget {
  const _NameLine({required this.standing, required this.compact});

  final ChefStanding standing;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final name = Text(
      standing.displayName,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: (compact
              ? theme.textTheme.titleSmall
              : theme.textTheme.titleMedium)
          ?.copyWith(fontWeight: FontWeight.w700),
    );
    final chip = TierChip(tier: standing.chefTier, dense: true);

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [name, const SizedBox(height: 2), chip],
      );
    }

    return Row(
      children: [
        Flexible(child: name),
        const SizedBox(width: AppSpacing.sm),
        Flexible(child: chip),
      ],
    );
  }
}

/// The four engagement chips. Labels drop when [compact]; a `Wrap` because at
/// 2.0× text scale on a narrow phone these cannot share one line (B016).
class _Stats extends StatelessWidget {
  const _Stats({required this.standing, required this.compact});

  final ChefStanding standing;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget stat(IconData icon, int value, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: scheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            // `countOf` drops the plural's "s" at one — "1 recipes" was on
            // the board's first render (B031).
            compact ? groupedCount(value) : countOf(value, label),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );

    return Wrap(
      spacing: compact ? 12 : AppSpacing.md,
      runSpacing: AppSpacing.xs,
      children: [
        stat(Icons.menu_book_outlined, standing.publicRecipeCount, 'recipes'),
        stat(Icons.favorite_outline, standing.totalLikes, 'likes'),
        stat(Icons.bookmark_outline, standing.totalSaves, 'saves'),
        stat(Icons.visibility_outlined, standing.totalViews, 'views'),
      ],
    );
  }
}

/// Score, then how far to the next tier. The score is a [FittedBox] rather than
/// an ellipsis: a truncated number is worse than a smaller one, and a
/// six-figure score at 2.0× text scale does not fit any sane column width.
class _ScoreBlock extends StatelessWidget {
  const _ScoreBlock({
    required this.standing,
    required this.color,
    required this.compact,
  });

  final ChefStanding standing;
  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final next = standing.nextTierLabel;
    final atTop = next == null;

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: compact ? 92 : 116),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              standing.scoreLabel,
              maxLines: 1,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                height: 1.1,
                color: atTop ? color : null,
              ),
            ),
          ),
          Text(
            atTop ? 'top tier reached' : next,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: theme.textTheme.labelSmall?.copyWith(
              color: atTop ? color : scheme.onSurfaceVariant,
              fontWeight: atTop ? FontWeight.w700 : null,
            ),
          ),
        ],
      ),
    );
  }
}
