import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:app/features/chefs/chefs_providers.dart';
import 'package:app/routing/app_router.dart';

/// The three shelves beside the board (web/medium only).
///
/// **Popular** is the top of the all-time board. **Trending** and **Best of the
/// month** are the top of `chefs_leaderboard_windowed` over 7 and 30 days
/// (Phase 33 — they were placeholder cards until the windowed SQL existed), and
/// they list only chefs who actually gained points in the window. A window in
/// which nobody moved is a real, loaded, *empty* shelf — the stale-sim-anchor
/// case — and it says so in words rather than holding placeholders, which read
/// as "still loading" forever.
class ChefsRails extends ConsumerWidget {
  const ChefsRails({super.key, required this.height, this.shrinkWrap = false});

  final double height;
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(popularChefsProvider);
    final total = ref.watch(chefCountProvider).valueOrNull;

    final popular = async.valueOrNull ?? const <ChefStanding>[];
    // Three states, not two. A board that has loaded and is genuinely empty
    // must not render a shelf of placeholders — that reads as "loading
    // forever" and claims a population the empty state right beside it denies.
    final loading = async.isLoading && popular.isEmpty;

    return ListView(
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      padding: EdgeInsets.zero,
      children: [
        if (async.hasError)
          ErrorView(
            message: friendlyError(async.error),
            onRetry: () => ref.invalidate(popularChefsProvider),
          )
        else if (popular.isNotEmpty || loading)
          CardRail(
            icon: Icons.favorite,
            title: 'Popular chefs',
            subtitle: 'Most decorated kitchens, all time',
            height: height,
            cardWidth: kSpotlightCardWidth,
            // Placeholders while the board is still loading, so the shelf keeps
            // its height instead of collapsing and shoving the rails below it.
            itemCount:
                loading
                    ? kChefRailLength
                    : popular.length.clamp(1, kChefRailLength),
            itemBuilder:
                (context, i) =>
                    loading
                        ? SpotlightCardPlaceholder(
                          tier: ChefTier.values[i % ChefTier.values.length],
                        )
                        : ChefSpotlightCard(
                          standing: popular[i],
                          totalChefs: total,
                          onTap: () => context.push(Routes.chef(popular[i].id)),
                        ),
          ),
        const SizedBox(height: AppSpacing.lg),
        _WindowRail(
          window: ChefsWindow.week,
          icon: Icons.trending_up,
          title: 'Trending chefs',
          height: height,
        ),
        const SizedBox(height: AppSpacing.lg),
        _WindowRail(
          window: ChefsWindow.month,
          icon: Icons.calendar_month,
          title: 'Best chefs of the month',
          height: height,
        ),
      ],
    );
  }
}

/// One windowed shelf: loading placeholders, an error, a quiet window, or the
/// chefs who moved, ranked by the points they earned in it.
class _WindowRail extends ConsumerWidget {
  const _WindowRail({
    required this.window,
    required this.icon,
    required this.title,
    required this.height,
  });

  final ChefsWindow window;
  final IconData icon;
  final String title;
  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(windowRailProvider(window));
    final subtitle = 'Most points earned in the ${window.span}';

    if (async.hasError && !async.isLoading) {
      return ErrorView(
        message: friendlyError(async.error),
        onRetry: () => ref.invalidate(windowRailProvider(window)),
      );
    }

    final chefs = async.valueOrNull;
    if (chefs == null) {
      return CardRail(
        icon: icon,
        title: title,
        subtitle: subtitle,
        height: height,
        cardWidth: kSpotlightCardWidth,
        itemCount: 6,
        itemBuilder:
            (context, i) => SpotlightCardPlaceholder(
              tier: ChefTier.values[i % ChefTier.values.length],
            ),
      );
    }

    return CardRail(
      icon: icon,
      title: title,
      subtitle: subtitle,
      height: height,
      cardWidth: kSpotlightCardWidth,
      // One quiet tile rather than zero items: the shelf keeps its title and
      // its height, and one item is below a page, so no arrows are drawn.
      itemCount: chefs.isEmpty ? 1 : chefs.length,
      itemBuilder:
          (context, i) =>
              chefs.isEmpty
                  ? QuietShelfCard(window: window, height: height)
                  : ChefSpotlightCard(
                    standing: chefs[i].standing,
                    window: chefs[i].window,
                    windowLabel: window.span,
                    // No denominator: the rank here is the rank *in the
                    // window*, and "4 / 148" would read as the all-time board.
                    onTap: () => context.push(Routes.chef(chefs[i].id)),
                  ),
    );
  }
}

/// A windowed shelf with nobody on it, at the size of one spotlight card.
///
/// Not a placeholder: the query ran and answered "nobody moved". On a real
/// deployment that is a quiet week; on a simulated one whose `sim.epoch_end()`
/// anchor has gone stale it is every week — old data, not a broken query, which
/// is why this names the window rather than apologising for an error.
class QuietShelfCard extends StatelessWidget {
  const QuietShelfCard({super.key, required this.window, required this.height});

  final ChefsWindow window;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return SizedBox(
      width: kSpotlightCardWidth,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.hourglass_empty, color: scheme.onSurfaceVariant),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Nothing moved in the ${window.span}',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Flexible(
                child: Text(
                  'No public recipe earned a like, save or view in that time, '
                  'so there is nobody to rank here yet.',
                  overflow: TextOverflow.fade,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
