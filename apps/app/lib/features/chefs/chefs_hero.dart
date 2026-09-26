import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app/features/chefs/chefs_providers.dart';

/// The banner across the top of `/chefs`: how many chefs there are, how they
/// are ranked, and how they are spread across the five tiers.
///
/// **Always dark, in both themes.** The gradient is a brand surface rather than
/// a scheme colour, so its colours are the palette's `hero*` fields (identical
/// in light and dark) and the tier accents are resolved at [Brightness.dark] —
/// the light-mode tier shades are unreadable on it.
///
/// Web/expanded only. The compact board keeps its plain app bar; there is no
/// room on a phone for five tiles and a filter without turning the page into a
/// header.
class ChefsHero extends ConsumerWidget {
  const ChefsHero({super.key});

  /// Width the three-part row needs at 1.0× text scale: an identity block wide
  /// enough for the strapline, five tier tiles, and the filter.
  static const double _rowWidth = 900;

  /// The hero's drop-shadow geometry (its colour is `palette.heroShadow`).
  static const double _shadowBlur = 34;
  static const Offset _shadowOffset = Offset(0, 14);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final total = ref.watch(chefCountProvider).valueOrNull;
    final counts = ref.watch(chefTierCountsProvider).valueOrNull;

    final identity = _Identity(total: total);
    final tiles = _TierTiles(counts: counts);
    final palette = context.palette;
    final filter = _WindowFilter(
      selected: ref.watch(boardViewProvider).window,
      onSelected: ref.read(boardViewProvider.notifier).selectWindow,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: palette.heroGradient,
        // Transparent in light; in dark the band's own colour is within a
        // hair of the page's, so this is its edge (UX-054).
        border: Border.all(color: palette.heroOutline),
        borderRadius: BorderRadius.circular(AppRadii.hero),
        boxShadow: [
          BoxShadow(
            color: palette.heroShadow,
            blurRadius: _shadowBlur,
            offset: _shadowOffset,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.md,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // The row needs its width to grow with the text in it. Squeezing
            // three blocks into a fixed 900px at 2.0× is what drove the
            // strapline to seven lines and made the hero taller than the page
            // it sits on — so above a point the parts stack instead.
            final row = constraints.maxWidth >= _rowWidth * context.textScale;

            return row
                ? Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Flexible(child: identity),
                    const SizedBox(width: AppSpacing.xl),
                    Expanded(flex: 2, child: tiles),
                    const SizedBox(width: AppSpacing.md),
                    filter,
                  ],
                )
                : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    identity,
                    const SizedBox(height: AppSpacing.md),
                    tiles,
                    const SizedBox(height: AppSpacing.md),
                    Align(alignment: Alignment.centerLeft, child: filter),
                  ],
                );
          },
        ),
      ),
    );
  }
}

class _Identity extends StatelessWidget {
  const _Identity({required this.total});

  final int? total;

  /// Measure of the one-sentence ranking rule under the title.
  static const double _ruleMaxWidth = 320;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          // The draft reads "RECOMPUTED 4H AGO", which is wrong about this
          // build for the same reason draft 1c's "recomputes nightly" was:
          // `on_recipe_stats_change` fires on every like, save, view and
          // visibility flip. There is no job to be behind.
          'LIVE · UPDATES ON EVERY LIKE, SAVE AND VIEW',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          // The kicker role stands in for the draft's mono line. onHeroMuted,
          // not the old 58% "faint" step: that measured 3.7:1 on the
          // gradient's light end (B133).
          style: context.appText.kicker.copyWith(color: palette.onHeroMuted),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            // The page title from compact up, where there is no AppBar to
            // carry one — so it is the heading assistive tech lands on
            // (UX-014).
            Semantics(
              container: true,
              header: true,
              child: Text(
                'Chefs',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.displaySmall?.copyWith(
                  color: palette.onHero,
                  height: 1,
                ),
              ),
            ),
            if (total != null) _RankedPill(total: total!),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _ruleMaxWidth),
          child: Text(
            'Ranked on what public recipes earn — likes, saves and views, '
            'nothing else.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: palette.onHeroMuted,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

class _RankedPill extends StatelessWidget {
  const _RankedPill({required this.total});

  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;

    return Container(
      padding: AppInsets.pill,
      decoration: BoxDecoration(
        color: palette.heroFill,
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.groups, size: AppIconSize.xs, color: palette.onHeroMuted),
          const SizedBox(width: AppSpacing.xs),
          // Flexible: the pill is a `Wrap` child, so it is handed the identity
          // column's width rather than its own intrinsic one.
          Flexible(
            child: Text(
              '${groupedCount(total)} ranked',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.tabular.copyWith(
                color: palette.onHeroMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One tile per tier, lowest to highest, each with the tier's accent bar.
///
/// A `Wrap` rather than a `Row` of five `Expanded`s: at 2.0× text scale five
/// tiles across a 1440px hero is about 190px each, which is not enough for
/// `MASTER CHEF` on one line. Wrapping to two rows costs the hero some height;
/// squeezing costs the labels.
class _TierTiles extends StatelessWidget {
  const _TierTiles({required this.counts});

  final Map<ChefTier, int>? counts;

  /// Narrowest tile that holds `MASTER CHEF` at 1.0×; below it, three across.
  static const double _minTileWidth = 96;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = AppSpacing.sm;
        // Aim for five across, but never narrower than a tile that can hold
        // "MASTER CHEF" at 1.0x.
        final ideal = (constraints.maxWidth - gap * 4) / 5;
        final width =
            ideal < _minTileWidth
                ? (constraints.maxWidth - gap * 2) / 3
                : ideal;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final tier in ChefTier.values)
              SizedBox(
                width: width,
                child: _TierTile(tier: tier, count: counts?[tier]),
              ),
          ],
        );
      },
    );
  }
}

class _TierTile extends StatelessWidget {
  const _TierTile({required this.tier, required this.count});

  final ChefTier tier;
  final int? count;

  // Tile geometry from the draft: its inset and corner, the accent bar, and
  // the gap between the bar, the count and the label.
  static const EdgeInsets _padding = EdgeInsets.symmetric(
    horizontal: AppSpacing.smPlus,
    vertical: 10,
  );
  static const double _radius = 14;
  static const Size _accentBar = Size(22, 3);
  static const double _gap = 5;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    // Always the dark-brightness accent: the hero is dark in both themes.
    final color = TierChip.colorFor(tier, Brightness.dark);
    final top = tier == ChefTier.masterChef;

    return Container(
      padding: _padding,
      decoration: BoxDecoration(
        color: top ? palette.heroFill : palette.heroFillSubtle,
        borderRadius: BorderRadius.circular(_radius),
        border:
            top
                ? Border.all(color: color.withValues(alpha: AppAlpha.emphasis))
                : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: _accentBar.width,
            height: _accentBar.height,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(AppRadii.pill),
            ),
          ),
          const SizedBox(height: _gap),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              // "—" while the counts are in flight: the tile keeps its size, so
              // the hero does not jump when they land.
              count == null ? '—' : groupedCount(count!),
              maxLines: 1,
              style: context.appText.stat.copyWith(
                color: palette.onHero,
                height: 1,
              ),
            ),
          ),
          const SizedBox(height: _gap),
          Text(
            tier.label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            // onHeroMuted retires the 58% "faint" step (B133: 3.7:1 on the
            // Master Chef tile).
            style: context.appText.overline.copyWith(
              color: palette.onHeroMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// All time / Month / Week — the span the board beside the hero measures.
///
/// Month or Week turns the board to **Momentum** over that span, and All time
/// turns it back (see [BoardViewNotifier]), so the pill never claims a window
/// the numbers under it are not measured over. The tier tiles beside it stay
/// all-time on purpose: a tier is a career, and five tiles re-counting who is
/// a Master Chef *this week* would be a different product.
///
/// The design system's [SegmentedTabs] on its `onHero` tone (UX-032): the
/// same `heroFill` track, `onHero` fill and `heroSelectedInk` label it always
/// drew, now with a 48px target per segment (UX-048) and a keyboard focus ring.
/// Sized to its labels — a non-flex child of the hero's row layout, which only
/// appears once the row has room for it.
class _WindowFilter extends StatelessWidget {
  const _WindowFilter({required this.selected, required this.onSelected});

  final ChefsWindow selected;
  final ValueChanged<ChefsWindow> onSelected;

  @override
  Widget build(BuildContext context) => SegmentedTabs<ChefsWindow>(
    values: ChefsWindow.values,
    selected: selected,
    onSelected: onSelected,
    labelOf: (window) => window.label,
    tone: SegmentedTabsTone.onHero,
    semanticLabel: 'Ranking window',
  );
}
