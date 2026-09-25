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
    this.window,
    this.windowLabel,
    this.note,
  });

  final ChefStanding standing;

  /// What this chef earned inside the board's time window (Phase 33's
  /// `Momentum` sort). When set, the score column shows the **gain** — `+312`
  /// over [windowLabel] — instead of the all-time score, and the podium's stat
  /// chips count the window rather than the lifetime totals, so every number on
  /// the row measures the same span. The tier, the chip and the progress bar
  /// stay all-time: a tier is earned over a career, not a week.
  final ChefWindowStats? window;

  /// The span [window] covers, under the gain — `last 7 days`. Ignored without
  /// a [window].
  final String? windowLabel;

  /// One extra muted fact, appended to the row's wrapping detail line — the
  /// board's `New` sort passes `joined Sep 2026`. A `Wrap` child, so a long
  /// note costs the row a line rather than overflowing it.
  final String? note;

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

  /// The podium row's gap between rank, avatar, text and score at full width
  /// (compact uses [AppSpacing.smPlus]).
  static const double _gapWide = 14;

  /// Avatar radius on the full-width podium row, and on the compact podium and
  /// the board row.
  static const double _avatarRadius = 22;
  static const double _avatarRadiusCompact = 18;

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
      return _BoardRow(
        standing: standing,
        onTap: onTap,
        color: tier,
        window: window,
        windowLabel: windowLabel,
        note: note,
      );
    }

    final compact = dense ?? context.isCompact;
    final gap = compact ? AppSpacing.smPlus : _gapWide;

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
                (compact ? AppSpacing.smPlus : AppSpacing.md) + spineWidth,
                AppSpacing.smPlus,
                compact ? AppSpacing.smPlus : AppSpacing.md,
                AppSpacing.smPlus,
              ),
              child: Row(
                children: [
                  _RankBlock(standing: standing, color: tier, compact: compact),
                  SizedBox(width: gap),
                  ChefAvatar(
                    name: standing.displayName,
                    avatarUrl: standing.avatarUrl,
                    radius: compact ? _avatarRadiusCompact : _avatarRadius,
                    backgroundColor: Color.alphaBlend(
                      tier.withValues(alpha: AppAlpha.tintStrong),
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
                        _Stats(
                          standing: standing,
                          compact: compact,
                          window: window,
                          note: note,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: compact ? AppSpacing.sm : gap),
                  _ScoreBlock(
                    standing: standing,
                    color: tier,
                    compact: compact,
                    window: window,
                    windowLabel: windowLabel,
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
    this.window,
    this.windowLabel,
    this.note,
  });

  final ChefStanding standing;
  final VoidCallback onTap;
  final Color color;
  final ChefWindowStats? window;
  final String? windowLabel;
  final String? note;

  /// The row's vertical inset.
  static const double _verticalInset = 9;

  /// The tier bar across the bottom edge.
  static const double _barHeight = 3;

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
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.smPlus,
                vertical: _verticalInset,
              ),
              child: Row(
                children: [
                  _RankPill(rank: standing.chefRank, color: color),
                  const SizedBox(width: AppSpacing.md),
                  ChefAvatar(
                    name: standing.displayName,
                    avatarUrl: standing.avatarUrl,
                    radius: ChefStandingCard._avatarRadiusCompact,
                    tier: standing.chefTier,
                    surfaceColor: scheme.surface,
                    backgroundColor: Color.alphaBlend(
                      color.withValues(alpha: AppAlpha.tintStrong),
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
                          style: theme.textTheme.titleSmall,
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        // Wrap, not Row: at 2.0x text scale the chip alone is
                        // most of a 404px panel's text column.
                        Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.xxs,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            TierChip(tier: standing.chefTier, dense: true),
                            Text(
                              countOf(standing.publicRecipeCount, 'recipes'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.tabular
                                  .copyWith(color: scheme.onSurfaceVariant),
                            ),
                            if (note != null)
                              Text(
                                note!,
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
                  _ScoreBlock(
                    standing: standing,
                    color: color,
                    compact: true,
                    window: window,
                    windowLabel: windowLabel,
                  ),
                ],
              ),
            ),
            SizedBox(
              height: _barHeight,
              child: LinearProgressIndicator(
                value: standing.tierProgress,
                minHeight: _barHeight,
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

  /// The disc's diameter, and the side padding that keeps a numeral off its
  /// curve.
  static const double _size = 28;
  static const double _padding = 3;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: _size,
      height: _size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: AppAlpha.tint),
      ),
      // Ranks past two digits would otherwise clip the disc, as would 2.0x
      // text scale on a two-digit rank.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: _padding),
          child: Text(
            '$rank',
            maxLines: 1,
            style: theme.textTheme.titleSmall?.tabular.copyWith(color: color),
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

  /// Column width and medal glyph size, full and compact.
  static const double _width = 46;
  static const double _widthCompact = 38;
  static const double _medalSize = 26;
  static const double _medalSizeCompact = 22;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final medal = ChefStandingCard.medalFor(standing.chefRank);
    final width = compact ? _widthCompact : _width;

    return SizedBox(
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (medal != null)
            Icon(
              medal,
              size: compact ? _medalSizeCompact : _medalSize,
              color: color,
            )
          else
            FittedBox(
              child: Text(
                '${standing.chefRank}',
                style: context.appText.statLarge.copyWith(
                  color: color,
                  height: 1.1,
                ),
              ),
            ),
          FittedBox(
            child: Text(
              medal != null ? '#${standing.chefRank}' : 'rank',
              style: theme.textTheme.labelSmall?.tabular.copyWith(
                color:
                    medal != null ? color : theme.colorScheme.onSurfaceVariant,
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
      style: compact ? theme.textTheme.titleSmall : theme.textTheme.titleMedium,
    );
    final chip = TierChip(tier: standing.chefTier, dense: true);

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [name, const SizedBox(height: AppSpacing.xxs), chip],
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
///
/// With a [window] the chips count the window instead — new recipes, likes,
/// saves and views (distinct signed-in viewers per recipe, summed — the
/// all-time `views` rule) — so they add up to the gain in the score column
/// rather than to a lifetime total printed beside it.
class _Stats extends StatelessWidget {
  const _Stats({
    required this.standing,
    required this.compact,
    this.window,
    this.note,
  });

  final ChefStanding standing;
  final bool compact;
  final ChefWindowStats? window;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget stat(IconData icon, int value, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: AppIconSize.xs, color: scheme.onSurfaceVariant),
        const SizedBox(width: AppSpacing.xs),
        Flexible(
          child: Text(
            // `countOf` drops the plural's "s" at one — "1 recipes" was on
            // the board's first render (B031).
            compact ? groupedCount(value) : countOf(value, label),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.tabular.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );

    final w = window;
    return Wrap(
      spacing: compact ? AppSpacing.smPlus : AppSpacing.md,
      runSpacing: AppSpacing.xs,
      children: [
        if (w == null) ...[
          stat(Icons.menu_book_outlined, standing.publicRecipeCount, 'recipes'),
          stat(Icons.favorite_outline, standing.totalLikes, 'likes'),
          stat(Icons.bookmark_outline, standing.totalSaves, 'saves'),
          stat(Icons.visibility_outlined, standing.totalViews, 'views'),
        ] else ...[
          stat(Icons.menu_book_outlined, w.newRecipes, 'new recipes'),
          stat(Icons.favorite_outline, w.likes, 'likes'),
          stat(Icons.bookmark_outline, w.saves, 'saves'),
          stat(Icons.visibility_outlined, w.viewers, 'views'),
        ],
        if (note != null)
          Text(
            note!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

/// Score, then how far to the next tier. The score is a [FittedBox] rather than
/// an ellipsis: a truncated number is worse than a smaller one, and a
/// six-figure score at 2.0× text scale does not fit any sane column width.
///
/// With a window the same two lines read `+312` over `last 7 days`: the gain is
/// what the Momentum board is sorted by, so it sits where the eye expects the
/// ranking key.
class _ScoreBlock extends StatelessWidget {
  const _ScoreBlock({
    required this.standing,
    required this.color,
    required this.compact,
    this.window,
    this.windowLabel,
  });

  final ChefStanding standing;
  final Color color;
  final bool compact;
  final ChefWindowStats? window;
  final String? windowLabel;

  /// The column's width cap, full and compact.
  static const double _maxWidth = 116;
  static const double _maxWidthCompact = 92;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final w = window;
    final maxWidth = compact ? _maxWidthCompact : _maxWidth;
    if (w != null) {
      return ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                w.gainLabel,
                maxLines: 1,
                style: context.appText.statLarge.copyWith(
                  height: 1.1,
                  color: w.moved ? scheme.primary : null,
                ),
              ),
            ),
            Text(
              windowLabel ?? 'in window',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }
    final next = standing.nextTierLabel;
    final atTop = next == null;

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
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
              style: context.appText.statLarge.copyWith(
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
            ),
          ),
        ],
      ),
    );
  }
}
