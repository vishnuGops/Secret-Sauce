import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app/features/chefs/chef_detail_sheet.dart';
import 'package:app/features/chefs/chefs_hero.dart';
import 'package:app/features/chefs/chefs_providers.dart';

/// Chefs leaderboard — ranked by chef score over each chef's public recipes.
///
/// Two layouts, one screen. On a phone this is the board and nothing else, the
/// way it has always been. From [Breakpoints.compact] up it is the page from the
/// redraw: a hero stating the population and the ranking rule, the board demoted
/// to a panel on the left, and rails of spotlight cards on the right.
///
/// Signed-out safe, like Discover: every read behind it is `anon`-callable, so
/// this route is deliberately absent from the router's `needsAuth` list.
class ChefsScreen extends ConsumerWidget {
  const ChefsScreen({super.key});

  /// Width of the leaderboard panel beside the rails, from the draft.
  static const double panelWidth = 404;

  /// Above this text scale the two-column layout stops being a layout.
  ///
  /// The columns are fixed-height — a 404px panel beside the rails, under a
  /// hero that does not scroll — so all three have to fit the viewport at once.
  /// At 2.0× the hero alone is taller than a 1200px window, which is the
  /// overflow this bound exists to prevent. Past it the page becomes one
  /// scroll, which has no such constraint.
  static const double maxTwoColumnTextScale = 1.3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (context.isCompact) return const _CompactBoard();

    final wide =
        context.isExpanded && context.textScale <= maxTwoColumnTextScale;
    final railHeight = spotlightCardHeight(context);

    return Scaffold(
      body: Padding(
        padding: EdgeInsets.fromLTRB(
          wide ? AppSpacing.xl : AppSpacing.md,
          AppSpacing.lg,
          wide ? AppSpacing.xl : AppSpacing.md,
          wide ? AppSpacing.xl : AppSpacing.md,
        ),
        child: wide
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const ChefsHero(),
                  const SizedBox(height: AppSpacing.lg),
                  // Two independently scrolling columns under a fixed hero.
                  // The draft scrolls the page and pins the panel with
                  // `position: sticky`; the panel already owns a scroll
                  // container there, so this renders the same thing without a
                  // nested-scroll arrangement to get wrong.
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(
                          width: panelWidth,
                          child: _BoardPanel(scrollable: true),
                        ),
                        const SizedBox(width: AppSpacing.lg),
                        Expanded(child: _Rails(height: railHeight)),
                      ],
                    ),
                  ),
                ],
              )
            // Below 1000px — or above the text scale the columns can hold —
            // the page becomes one scroll, rails first: they are the part of
            // this redraw a narrow window can still show properly.
            : ListView(
                children: [
                  const ChefsHero(),
                  const SizedBox(height: AppSpacing.lg),
                  _Rails(height: railHeight, shrinkWrap: true),
                  const SizedBox(height: AppSpacing.lg),
                  const _BoardPanel(scrollable: false),
                ],
              ),
      ),
    );
  }
}

/// The phone board: unchanged by the page redraw.
class _CompactBoard extends ConsumerWidget {
  const _CompactBoard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(chefsLeaderboardProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Chefs')),
      body: async.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          message: e.toString(),
          onRetry: () => ref.invalidate(chefsLeaderboardProvider),
        ),
        data: (chefs) => chefs.isEmpty
            ? const EmptyView(
                title: 'No chefs yet',
                message: 'Publish a recipe and you will show up here.',
                icon: Icons.emoji_events_outlined,
              )
            : RefreshIndicator(
                onRefresh: () async => ref.invalidate(chefsLeaderboardProvider),
                child: ListView.separated(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  itemCount: chefs.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, i) => ChefStandingCard(
                    standing: chefs[i],
                    onTap: () => showChefDetail(context, chefs[i]),
                  ),
                ),
              ),
      ),
    );
  }
}

/// The ranked board, as a panel: header, ordering tabs, rows, and a footer that
/// widens the page.
class _BoardPanel extends ConsumerWidget {
  const _BoardPanel({required this.scrollable});

  /// True when the panel owns its own scroll (the two-column layout); false
  /// when it sits inside the page's scroll and must size to its content.
  final bool scrollable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final async = ref.watch(chefsLeaderboardProvider);
    final total = ref.watch(chefCountProvider).valueOrNull;
    final sort = ref.watch(boardSortProvider);

    final rows = async.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: LoadingView(),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: ErrorView(
          message: e.toString(),
          onRetry: () => ref.invalidate(chefsLeaderboardProvider),
        ),
      ),
      data: (chefs) => chefs.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: EmptyView(
                title: 'No chefs yet',
                message: 'Publish a recipe and you will show up here.',
                icon: Icons.emoji_events_outlined,
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.sm),
              shrinkWrap: !scrollable,
              physics: scrollable ? null : const NeverScrollableScrollPhysics(),
              itemCount: chefs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (context, i) => ChefStandingCard(
                standing: chefs[i],
                variant: ChefCardVariant.board,
                onTap: () => showChefDetail(context, chefs[i]),
              ),
            ),
    );

    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              14,
              AppSpacing.md,
              10,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(Icons.leaderboard, size: 20, color: scheme.primary),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'Leaderboard',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      _shownLabel(async.valueOrNull?.length, total),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                _SortTabs(
                  selected: sort,
                  onSelected: (s) =>
                      ref.read(boardSortProvider.notifier).state = s,
                ),
              ],
            ),
          ),
          Divider(height: 1, color: scheme.outlineVariant),
          if (scrollable) Expanded(child: rows) else rows,
          Divider(height: 1, color: scheme.outlineVariant),
          _PanelFooter(loaded: async.valueOrNull?.length, total: total),
        ],
      ),
    );
  }

  /// `TOP 25 / 148` — or just the total until the rows land.
  static String _shownLabel(int? loaded, int? total) {
    if (loaded == null) return total == null ? '' : groupedCount(total);
    if (total == null) return 'TOP ${groupedCount(loaded)}';
    return 'TOP ${groupedCount(loaded)} / ${groupedCount(total)}';
  }
}

class _PanelFooter extends ConsumerWidget {
  const _PanelFooter({required this.loaded, required this.total});

  final int? loaded;
  final int? total;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final more = loaded != null && total != null && loaded! < total!;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, AppSpacing.sm, AppSpacing.sm, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Ties share a rank.',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          if (more)
            TextButton(
              // One more page is one wider read — see `leaderboardPagesProvider`.
              onPressed: () =>
                  ref.read(leaderboardPagesProvider.notifier).state++,
              child: Text('Show all ${groupedCount(total!)}'),
            ),
        ],
      ),
    );
  }
}

/// Score / Momentum / New. Two of the three are disabled — see [BoardSort].
class _SortTabs extends StatelessWidget {
  const _SortTabs({required this.selected, required this.onSelected});

  final BoardSort selected;
  final ValueChanged<BoardSort> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          for (final sort in BoardSort.values)
            Expanded(
              child: notYetTooltip(
                enabled: sort.enabled,
                message: 'Needs a score history — not wired up yet',
                child: InkWell(
                  onTap: sort.enabled ? () => onSelected(sort) : null,
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    decoration: BoxDecoration(
                      color: sort == selected
                          ? scheme.surfaceContainerLowest
                          : null,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      sort.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight:
                            sort == selected ? FontWeight.w800 : FontWeight.w700,
                        color: sort == selected
                            ? scheme.onSurface
                            : scheme.onSurfaceVariant
                                .withValues(alpha: sort.enabled ? 1 : 0.5),
                      ),
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

/// The three shelves beside the board.
///
/// Only the first has data. Trending and "best of the month" rank on engagement
/// earned inside a time window, which is derivable from the `created_at` /
/// `viewed_at` columns on the like, save and view tables — but the seed writes
/// the counters straight onto `recipes` and leaves those logs almost empty, so
/// today they would render three empty shelves.
// TODO(rails): swap the placeholders for real cards once there is dated
// engagement to rank and the windowed RPC exists (EXECUTION-PLAN Phase 23).
class _Rails extends ConsumerWidget {
  const _Rails({required this.height, this.shrinkWrap = false});

  final double height;
  final bool shrinkWrap;

  static const _placeholderNote =
      'Placeholder cards — this shelf needs dated likes and saves to rank, '
      'and the seeded data carries totals only.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(chefsLeaderboardProvider);
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
            message: async.error.toString(),
            onRetry: () => ref.invalidate(chefsLeaderboardProvider),
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
            itemCount: loading
                ? kChefRailLength
                : popular.length.clamp(1, kChefRailLength),
            itemBuilder: (context, i) => loading
                ? SpotlightCardPlaceholder(
                    tier: ChefTier.values[i % ChefTier.values.length],
                  )
                : ChefSpotlightCard(
                    standing: popular[i],
                    totalChefs: total,
                    onTap: () => showChefDetail(context, popular[i]),
                  ),
          ),
        const SizedBox(height: AppSpacing.lg),
        CardRail(
          icon: Icons.trending_up,
          title: 'Trending chefs',
          subtitle: 'Fastest score gain in the last 7 days',
          height: height,
          cardWidth: kSpotlightCardWidth,
          itemCount: 6,
          footnote: _placeholderNote,
          itemBuilder: (context, i) => SpotlightCardPlaceholder(
            tier: ChefTier.values[i % ChefTier.values.length],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        CardRail(
          icon: Icons.calendar_month,
          title: 'Best chefs of the month',
          subtitle: 'Ranked on saves earned this month',
          height: height,
          cardWidth: kSpotlightCardWidth,
          itemCount: 6,
          footnote: _placeholderNote,
          itemBuilder: (context, i) => SpotlightCardPlaceholder(
            tier: ChefTier.values[(i + 2) % ChefTier.values.length],
          ),
        ),
      ],
    );
  }
}
