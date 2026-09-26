import 'package:core/core.dart';
import 'package:flutter/material.dart';

import 'package:design_system/src/theme/app_theme.dart';

/// Which of the three rank looks a [RankBadge] draws. See the named
/// constructors for where each one lives.
enum RankBadgeVariant { pill, disc, podium }

/// A chef's leaderboard rank — the one rank widget (UX-032).
///
/// Three looks, one contract. Every variant:
///  - sets its digits **tabular** (UX-049), so `9 → 10` on a re-rank does not
///    shift the row around it;
///  - is **one** semantics node reading `Rank N`, with the visual text (`RANK
///    12`, `#1`, the `rank` caption) excluded — a screen reader hears the rank
///    once, not `RANK 12` plus a medal glyph plus `#1`;
///  - takes the chef's [tier] rather than a colour, and resolves the ink itself,
///    so a caller cannot hand the pill the wrong brightness's tier colour
///    (UX-012).
///
/// Ties share a rank (`dense_rank`), so two badges can read the same number.
///
/// What this is **not**: the recipe card's `Ranked 1st` ribbon (a shelf
/// position, not a chef's standing, with its own palette pair) and the chefs
/// hero's `148 ranked` pill (a population count — reading it as `Rank 148`
/// would tell a screen reader something false).
class RankBadge extends StatelessWidget {
  /// The frosted `RANK 12` pill that sits on imagery — the spotlight card's
  /// portrait caption. Near-white in both themes, so its ink is the tier colour
  /// at **light** brightness whatever the page's is: the page-brightness tier
  /// colour is a pastel in dark mode and measured ~1.5:1 on it (UX-012).
  const RankBadge.pill({super.key, required this.rank, required this.tier})
    : variant = RankBadgeVariant.pill,
      dense = false;

  /// The 28px tier-tinted disc holding the bare numeral — the leaderboard
  /// panel's dense board row. Past two digits, or at 2.0× text scale, the
  /// numeral scales down inside the disc rather than clipping it.
  const RankBadge.disc({super.key, required this.rank, required this.tier})
    : variant = RankBadgeVariant.disc,
      dense = false;

  /// The podium row's rank column: a medal over `#1` for the top three, a
  /// large numeral over `rank` for everyone else. A fixed-width column, so the
  /// avatar beside it lines up down the whole board. [dense] is the phone's
  /// narrower column and smaller medal.
  const RankBadge.podium({
    super.key,
    required this.rank,
    required this.tier,
    this.dense = false,
  }) : variant = RankBadgeVariant.podium;

  final int rank;

  /// Drives the ink (and the disc's wash).
  final ChefTier tier;

  final RankBadgeVariant variant;

  /// Only [RankBadgeVariant.podium] reads it.
  final bool dense;

  /// What assistive tech hears, for every variant.
  static String semanticsLabelFor(int rank) => 'Rank $rank';

  /// Medal glyph for a podium rank, or null below the top three.
  static IconData? medalFor(int rank) => switch (rank) {
    1 => Icons.workspace_premium,
    2 || 3 => Icons.military_tech,
    _ => null,
  };

  /// The pill's inset — the draft's 7px sides on the 2px vertical step.
  static const EdgeInsets _pillPadding = EdgeInsets.symmetric(
    horizontal: 7,
    vertical: AppSpacing.xxs,
  );

  /// The disc's diameter, and the side padding that keeps a numeral off its
  /// curve.
  static const double _discSize = 28;
  static const double _discPadding = 3;

  /// The podium column's width and medal size, full and [dense].
  static const double _podiumWidth = 46;
  static const double _podiumWidthDense = 38;
  static const double _medalSize = 26;
  static const double _medalSizeDense = 22;

  /// The podium numeral's line height: statLarge's 28/22 leaves a gap above
  /// the caption that the column has no room for.
  static const double _podiumNumeralHeight = 1.1;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: semanticsLabelFor(rank),
      excludeSemantics: true,
      child: switch (variant) {
        RankBadgeVariant.pill => _pill(context),
        RankBadgeVariant.disc => _disc(context),
        RankBadgeVariant.podium => _podium(context),
      },
    );
  }

  Widget _pill(BuildContext context) {
    // Light brightness on purpose, not a brightness branch: the pill's fill is
    // the same near-white in both themes, so there is only one right ink.
    final ink = AppPalette.light.tier(tier);

    return Container(
      padding: _pillPadding,
      decoration: BoxDecoration(
        color: context.palette.onImage.withValues(alpha: AppAlpha.frosted),
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.workspace_premium, size: AppIconSize.xs, color: ink),
          const SizedBox(width: AppSpacing.xs),
          Text(
            'RANK $rank',
            maxLines: 1,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.tabular.copyWith(color: ink),
          ),
        ],
      ),
    );
  }

  Widget _disc(BuildContext context) {
    final color = context.palette.tier(tier);

    return Container(
      width: _discSize,
      height: _discSize,
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
          padding: const EdgeInsets.symmetric(horizontal: _discPadding),
          child: Text(
            '$rank',
            maxLines: 1,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.tabular.copyWith(color: color),
          ),
        ),
      ),
    );
  }

  Widget _podium(BuildContext context) {
    final theme = Theme.of(context);
    final color = context.palette.tier(tier);
    final medal = medalFor(rank);

    return SizedBox(
      width: dense ? _podiumWidthDense : _podiumWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (medal != null)
            Icon(
              medal,
              size: dense ? _medalSizeDense : _medalSize,
              color: color,
            )
          else
            // scaleDown, centred: a `4` and a `128` share one baseline and one
            // centre line, and only the one that does not fit shrinks (UX-049).
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '$rank',
                maxLines: 1,
                style: context.appText.statLarge.tabular.copyWith(
                  color: color,
                  height: _podiumNumeralHeight,
                ),
              ),
            ),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              medal != null ? '#$rank' : 'rank',
              maxLines: 1,
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
