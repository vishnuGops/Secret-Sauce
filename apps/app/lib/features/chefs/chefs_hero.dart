import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app/features/chefs/chefs_providers.dart';

/// Explains a control that is deliberately inert, and gets out of the way of
/// one that is not.
///
/// The conditional matters: `Tooltip` with an empty message still opens an
/// empty box on hover, so wrapping every segment unconditionally would put a
/// blank tooltip under the two thirds of these controls that work.
Widget notYetTooltip({
  required bool enabled,
  required String message,
  required Widget child,
}) =>
    enabled ? child : Tooltip(message: message, child: child);

/// The banner across the top of `/chefs`: how many chefs there are, how they
/// are ranked, and how they are spread across the five tiers.
///
/// **Always dark, in both themes.** The gradient is a brand surface rather than
/// a scheme colour, so its foreground colours are literals and the tier accents
/// are resolved at [Brightness.dark] — the light-mode tier shades are unreadable
/// on it.
///
/// Web/expanded only. The compact board keeps its plain app bar; there is no
/// room on a phone for five tiles and a filter without turning the page into a
/// header.
class ChefsHero extends ConsumerWidget {
  const ChefsHero({super.key});

  /// The draft's `linear-gradient(104deg, …)`.
  static const _gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF241A17), Color(0xFF3B2823), Color(0xFF5C3B2D)],
    stops: [0, 0.52, 1],
  );

  static const _onHero = Colors.white;
  static const _onHeroDim = Color(0xB3FFFFFF); // white @ 70%
  static const _onHeroFaint = Color(0x94FFFFFF); // white @ 58%

  /// Width the three-part row needs at 1.0× text scale: an identity block wide
  /// enough for the strapline, five tier tiles, and the filter.
  static const double _rowWidth = 900;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final total = ref.watch(chefCountProvider).valueOrNull;
    final counts = ref.watch(chefTierCountsProvider).valueOrNull;

    final identity = _Identity(total: total);
    final tiles = _TierTiles(counts: counts);
    final filter = _WindowFilter(
      selected: ref.watch(chefsWindowProvider),
      onSelected: (w) =>
          ref.read(chefsWindowProvider.notifier).state = w,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: _gradient,
        borderRadius: BorderRadius.circular(26),
        boxShadow: const [
          BoxShadow(
            color: Color(0x42231917),
            blurRadius: 34,
            offset: Offset(0, 14),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
          // TODO(fonts): a mono face in the draft; approximated with letter
          // spacing until the app-wide type decision lands.
          style: theme.textTheme.labelSmall?.copyWith(
            color: ChefsHero._onHeroFaint,
            letterSpacing: 1.6,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'Chefs',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              // TODO(fonts): the display face in the draft.
              style: theme.textTheme.displaySmall?.copyWith(
                color: ChefsHero._onHero,
                fontWeight: FontWeight.w600,
                height: 1,
              ),
            ),
            if (total != null) _RankedPill(total: total!),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Text(
            'Ranked on what public recipes earn — likes, saves and views, '
            'nothing else.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: ChefsHero._onHeroDim, height: 1.4),
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

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.groups, size: 14, color: ChefsHero._onHeroDim),
          const SizedBox(width: AppSpacing.xs),
          // Flexible: the pill is a `Wrap` child, so it is handed the identity
          // column's width rather than its own intrinsic one.
          Flexible(
            child: Text(
              '${groupedCount(total)} ranked',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: ChefsHero._onHeroDim,
                fontWeight: FontWeight.w700,
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

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = AppSpacing.sm;
        // Aim for five across, but never narrower than a tile that can hold
        // "MASTER CHEF" at 1.0x.
        final ideal = (constraints.maxWidth - gap * 4) / 5;
        final width = ideal < 96 ? (constraints.maxWidth - gap * 2) / 3 : ideal;

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Always the dark-brightness accent: the hero is dark in both themes.
    final color = TierChip.colorFor(tier, Brightness.dark);
    final top = tier == ChefTier.masterChef;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: top ? 0.10 : 0.07),
        borderRadius: BorderRadius.circular(14),
        border: top
            ? Border.all(color: color.withValues(alpha: 0.45))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 22,
            height: 3,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 5),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              // "—" while the counts are in flight: the tile keeps its size, so
              // the hero does not jump when they land.
              count == null ? '—' : groupedCount(count!),
              maxLines: 1,
              style: theme.textTheme.titleMedium?.copyWith(
                color: ChefsHero._onHero,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            tier.label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: ChefsHero._onHeroFaint,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

/// All time / Month / Week. Two of the three are disabled — see [ChefsWindow].
class _WindowFilter extends StatelessWidget {
  const _WindowFilter({required this.selected, required this.onSelected});

  final ChefsWindow selected;
  final ValueChanged<ChefsWindow> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final window in ChefsWindow.values)
            notYetTooltip(
              enabled: window.enabled,
              message: 'Needs dated engagement data — not wired up yet',
              child: InkWell(
                onTap: window.enabled ? () => onSelected(window) : null,
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: window == selected ? Colors.white : null,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    window.label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: window == selected
                          ? const Color(0xFF2C1F1B)
                          : window.enabled
                              ? ChefsHero._onHeroDim
                              : ChefsHero._onHeroFaint,
                      fontWeight:
                          window == selected ? FontWeight.w800 : FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
