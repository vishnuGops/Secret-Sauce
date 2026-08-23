import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app/features/discover/discover_masthead.dart';
import 'package:app/features/discover/discover_providers.dart';
import 'package:app/features/discover/discover_shelf.dart';
import 'package:app/widgets/recipe_async_grid.dart';

/// Public discovery: a masthead, three numbered shelves, then everything else.
///
/// **The tabs are gone.** Discover was Popular / Trending / Recent — one corpus
/// ranked three ways, three times, and a visitor with no opinion about ranking
/// had nothing to open. The shelves answer a different question ("what am I in
/// the mood for": half an hour, a whole Saturday, or the recipe everyone else
/// keeps rewriting), and each one is ranked by the signal that actually suits
/// it — see the shelf RPCs in `supabase/migrations/0001_init.sql`. The old three
/// survive underneath as a **sort** on one browse grid, which is what they
/// always were.
///
/// One scroll, so the page is a `CustomScrollView` and the browse grid goes in
/// as a sliver ([RecipeAsyncSliverGrid]). Nesting the box `RecipeAsyncGrid`
/// inside a page-level list would put a scrollable inside a scrollable.
///
/// It also drops the screen's own `AppBar`: on the web that was a second bar
/// under `TopNavBar`, and the masthead is the page title now (the Phase 21
/// deferred item, for this screen).
///
/// Signed-out safe, like `/chefs` — every read behind it is `anon`-callable.
class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key});

  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final query = ref.watch(searchQueryProvider);
    final searching = query.trim().isNotEmpty;
    final wide = !context.isCompact;
    final side = wide ? AppSpacing.xl : AppSpacing.md;
    final gutter = EdgeInsets.symmetric(horizontal: side);
    // The grid gets the page's margin, not its own default (B059) — the cards
    // have to start on the same left edge as the numerals and the masthead rule
    // above them.
    final gridPadding = EdgeInsets.fromLTRB(
      side,
      AppSpacing.md,
      side,
      AppSpacing.md,
    );

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(side, AppSpacing.lg, side, 0),
              sliver: SliverToBoxAdapter(
                child: DiscoverMasthead(
                  publicCount: ref.watch(publicRecipeCountProvider).valueOrNull,
                  search: SearchBar(
                    controller: _searchController,
                    hintText: 'Search recipes, ingredients, tags…',
                    leading: const Icon(Icons.search),
                    trailing: [
                      if (searching)
                        IconButton(
                          icon: const Icon(Icons.clear),
                          tooltip: 'Clear search',
                          onPressed: () {
                            _searchController.clear();
                            ref.read(searchQueryProvider.notifier).state = '';
                          },
                        ),
                    ],
                    onChanged:
                        (v) => ref.read(searchQueryProvider.notifier).state = v,
                  ),
                ),
              ),
            ),

            // Searching replaces the whole page below the masthead. A shelf of
            // quick dinners under a list of search results is noise: the reader
            // has already said what they want.
            if (searching)
              RecipeAsyncSliverGrid(
                provider: searchResultsProvider,
                padding: gridPadding,
                empty: _empty('No matches'),
              )
            else ...[
              for (final shelf in _shelves(scheme))
                SliverPadding(
                  padding: gutter.copyWith(top: AppSpacing.xl),
                  sliver: SliverToBoxAdapter(child: shelf),
                ),
              SliverPadding(
                padding: gutter.copyWith(top: AppSpacing.xxl),
                sliver: const SliverToBoxAdapter(child: _BrowseHeader()),
              ),
              _BrowseGrid(
                sort: ref.watch(browseSortProvider),
                padding: gridPadding,
              ),
            ],

            // Clearance for the compact chrome: the shell puts an extended FAB
            // and a NavigationBar over the bottom of this scroll, and the last
            // thing in it is a `Load more` button.
            SliverToBoxAdapter(
              child: SizedBox(height: wide ? AppSpacing.xl : 96),
            ),
          ],
        ),
      ),
    );
  }

  /// The three shelves, in order. Accents come from the scheme rather than
  /// literals so both themes get them for free — and they are three *different*
  /// scheme roles because the numeral and its rule are the only thing telling
  /// one shelf from the next at a glance.
  List<Widget> _shelves(ColorScheme scheme) => [
    DiscoverShelf(
      index: '01',
      title: 'Under 30',
      subtitle: 'Knife down to plate in half an hour, best-rated first.',
      kicker: 'RANKED BY RATING',
      accent: scheme.primary,
      provider: quickShelfProvider,
      emptyReason:
          'Nothing here yet — no public recipe records a total time of '
          '30 minutes or less.',
    ),
    DiscoverShelf(
      index: '02',
      title: 'Weekend projects',
      subtitle:
          'Two hours or harder. Ranked by saves — what people file away for '
          'a free Saturday.',
      kicker: 'RANKED BY SAVES',
      accent: scheme.tertiary,
      provider: projectsShelfProvider,
      emptyReason:
          'Nothing here yet — no public recipe runs to two hours or carries '
          'the hard difficulty.',
    ),
    DiscoverShelf(
      index: '03',
      title: 'Most forked',
      subtitle: 'Recipes other kitchens took and rewrote as their own.',
      kicker: 'RANKED BY FORKS',
      accent: scheme.secondary,
      provider: mostForkedShelfProvider,
      emptyReason:
          'Nothing here yet — no public recipe has been forked. Open one and '
          'press Fork to start a lineage.',
    ),
  ];
}

/// The rule and the sort control that open the browse grid.
///
/// Set apart from the shelves on purpose: a heavier rule, no numeral, and the
/// controls on the same line. The shelves are an edit; this is the archive.
class _BrowseHeader extends ConsumerWidget {
  const _BrowseHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sort = ref.watch(browseSortProvider);

    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'EVERYTHING ELSE',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: 1.4,
          ),
        ),
        Text(
          'The whole public vault, one page at a time.',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );

    final control = Wrap(
      spacing: AppSpacing.lg,
      runSpacing: AppSpacing.sm,
      children: [
        for (final option in BrowseSort.values)
          _SortLink(
            label: option.label,
            selected: option == sort,
            onTap: () => ref.read(browseSortProvider.notifier).state = option,
          ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(height: 2, color: scheme.outlineVariant),
        const SizedBox(height: AppSpacing.md),
        LayoutBuilder(
          builder:
              (context, constraints) =>
                  constraints.maxWidth >= 560 * context.textScale
                      ? Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(child: heading),
                          const SizedBox(width: AppSpacing.md),
                          control,
                        ],
                      )
                      : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          heading,
                          const SizedBox(height: AppSpacing.md),
                          control,
                        ],
                      ),
        ),
      ],
    );
  }
}

/// One sort option: a label that gains an accent underline when it is the
/// active one.
///
/// Deliberately not the pill the chefs board uses. Two pages, two jobs — the
/// board's control switches a ranking *within* a leaderboard, this one reorders
/// an archive, and copying the pill here would leave the two pages looking like
/// one page with different data in it.
class _SortLink extends StatelessWidget {
  const _SortLink({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.button),
      // The underline is a **border on the box that holds the text**, not a
      // `Container` under it in a `Column` (B060). A box with no child and no
      // width takes `constraints.biggest` when it is bounded and
      // `constraints.smallest` when it is not — so the same widget rendered a
      // full-width rule that forced each link onto its own line in the stacked
      // layout, and a zero-width, invisible one in the row layout, where the
      // `Wrap` is a non-flex child laid out unbounded. Selected state was
      // therefore undrawn at exactly the width most people use.
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              width: 2,
              // Drawn in both states so selecting one does not move the row.
              color: selected ? scheme.primary : Colors.transparent,
            ),
          ),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// The browse grid, as a sliver, for whichever sort is selected.
///
/// A `switch` rather than one parameterised widget because Riverpod provider
/// types are invariant: each of the three has its own notifier type, and there
/// is no common supertype a single provider parameter could accept (the same
/// reason [RecipeAsyncGrid] is generic).
class _BrowseGrid extends StatelessWidget {
  const _BrowseGrid({required this.sort, required this.padding});

  final BrowseSort sort;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return switch (sort) {
      BrowseSort.topRated => RecipeAsyncSliverGrid(
        provider: popularRecipesProvider,
        padding: padding,
        empty: _empty('No public recipes yet'),
      ),
      BrowseSort.trending => RecipeAsyncSliverGrid(
        provider: trendingRecipesProvider,
        padding: padding,
        empty: _empty('Nothing trending yet'),
      ),
      BrowseSort.newest => RecipeAsyncSliverGrid(
        provider: recentRecipesProvider,
        padding: padding,
        empty: _empty('No recipes yet'),
      ),
    };
  }
}

EmptyView _empty(String title) => EmptyView(
  title: title,
  icon: Icons.local_dining_outlined,
  message: 'Public recipes will appear here.',
);
