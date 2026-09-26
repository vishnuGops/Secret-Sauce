import 'dart:async';

import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:app/features/discover/discover_categories.dart';
import 'package:app/features/discover/discover_masthead.dart';
import 'package:app/features/discover/discover_providers.dart';
import 'package:app/features/discover/discover_shelf.dart';
import 'package:app/routing/app_router.dart';
import 'package:app/widgets/recipe_async_grid.dart';

/// Bottom clearance on compact for the shell's extended FAB and NavigationBar.
const double _kCompactChromeClearance = 96;

/// Browse-header width (× text scale) below which the sort drops under the
/// heading.
const double _kBrowseHeaderRowWidth = 560;

/// The heavier rule that opens the browse grid.
const double _kBrowseRule = 2;

/// The sort link's underline stroke.
const double _kSortUnderline = 2;

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
/// **Category tiles (Phase 36c, the owner's Q6)** sit between the masthead and
/// the shelves. A tile filters the browse grid — the shelves stay, because they
/// are an edit, not a list — and the selection is URL state: [category] comes
/// from `/discover?category=…` via the router, and a tap is a `context.go`, so
/// a deep link, the back button and a tap all take the same road. Search still
/// wins over a category while the query is non-empty.
///
/// **The search is URL state too (UX-022)** — `/discover?q=soup` — but typed
/// rather than tapped, so the two directions are wired differently. Typing
/// writes [searchQueryProvider] on every keystroke (its debounce is what keeps
/// the server quiet) and, after the same pause, *replaces* the address with
/// `?q=` via `Router.neglect`, so a search is linkable without a history entry
/// per word. A `q` that arrives from outside — a deep link, the back button —
/// is copied into the field and the provider after the frame, because a
/// provider cannot be written from a widget lifecycle method.
///
/// Signed-out safe, like `/chefs` — every read behind it is `anon`-callable.
class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key, this.category, this.query = ''});

  /// The category tile the URL selects, or null for the unfiltered page. An
  /// unknown slug has already become null in the router.
  final DiscoverCategory? category;

  /// The search the URL carries (`?q=`, trimmed), or empty for none.
  final String query;

  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen> {
  final _searchController = TextEditingController();

  /// The browse header — scrolled to when a tile is picked, because the
  /// filtered grid is under three shelves and a tap that changes nothing on
  /// screen reads as a tap that did nothing.
  final _browseKey = GlobalKey();

  /// Debounces the address-bar update behind the typing.
  Timer? _urlSync;

  /// The last `q` this screen put in the URL (or received from it). A route
  /// rebuild carrying this value is our own echo and must not touch the
  /// field: by the time it lands the reader may have typed on.
  late String _lastUrlQuery = widget.query;

  /// A URL query on its way into [searchQueryProvider], which cannot be
  /// written until the frame is done. Non-null for exactly that one frame;
  /// the build reads it in place of the provider so the page does not flash
  /// the unsearched shelves first.
  String? _seed;

  @override
  void initState() {
    super.initState();
    if (widget.query.isNotEmpty) _adoptUrlQuery(widget.query);
  }

  /// Takes a query that arrived from the URL: into the field now, into the
  /// provider after the frame.
  void _adoptUrlQuery(String query) {
    _urlSync?.cancel();
    _lastUrlQuery = query;
    _searchController.text = query;
    _seed = query;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _seed != query) return;
      ref.read(searchQueryProvider.notifier).state = query;
      setState(() => _seed = null);
    });
  }

  void _onSearchChanged(String value) {
    ref.read(searchQueryProvider.notifier).state = value;
    _urlSync?.cancel();
    _urlSync = Timer(kSearchDebounce, () => _writeUrlQuery(value.trim()));
  }

  /// Puts [query] in the address bar, keeping the selected tile. `neglect`
  /// replaces the current history entry instead of pushing one, so Back
  /// leaves the search rather than un-typing it a word at a time. A host
  /// without a router (a bare widget test) simply has no URL to keep.
  void _writeUrlQuery(String query) {
    if (!mounted || query == _lastUrlQuery) return;
    _lastUrlQuery = query;
    final router = GoRouter.maybeOf(context);
    if (router == null) return;
    Router.neglect(
      context,
      () => router.go(
        Routes.discoverSearch(query, category: widget.category?.slug),
      ),
    );
  }

  /// The clear button, and the miss state's **Clear search** (UX-022): an
  /// empty field, no `q`, and back to whatever the URL's tile selects.
  void _clearSearch() {
    _urlSync?.cancel();
    _searchController.clear();
    ref.read(searchQueryProvider.notifier).state = '';
    setState(() => _seed = null);
    _writeUrlQuery('');
  }

  @override
  void didUpdateWidget(DiscoverScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A `q` that changed under us — the back button, a link, the Discover tab
    // (no `q`) — as opposed to the echo of our own debounced write.
    if (widget.query != oldWidget.query && widget.query != _lastUrlQuery) {
      _adoptUrlQuery(widget.query);
    }
    // Only on a change *to* a tile made while the page is open. A deep link
    // opens at the top, where the tiles show which one is selected; clearing
    // leaves the reader where they are.
    if (widget.category != null && widget.category != oldWidget.category) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final target = _browseKey.currentContext;
        if (!mounted || target == null) return;
        Scrollable.ensureVisible(
          target,
          duration: AppMotion.of(context, AppMotion.slow),
          curve: AppMotion.emphasized,
        );
      });
    }
  }

  @override
  void dispose() {
    _urlSync?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  /// A tile press: select it, or clear it when it is already the selected one.
  void _onTile(DiscoverCategory category) => context.go(
    category == widget.category
        ? Routes.discover
        : Routes.discoverCategory(category.slug),
  );

  void _clearCategory() => context.go(Routes.discover);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final category = widget.category;
    // Watched unconditionally, so the seed frame still subscribes.
    final live = ref.watch(searchQueryProvider);
    final query = _seed ?? live;
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

    // The selection is overridden into a scope of this screen's own, so
    // `categoryRecipesProvider` (which declares it as a dependency) is built
    // here, against the URL's value — see `selectedCategoryProvider`.
    return ProviderScope(
      overrides: [selectedCategoryProvider.overrideWithValue(category)],
      child: Scaffold(
        body: SafeArea(
          child: CustomScrollView(
            slivers: [
              // Full bleed: the cream band runs edge to edge and carries the
              // page margin inside it, so its content still starts on the same
              // left edge as the tiles and the shelves' numerals.
              SliverToBoxAdapter(
                child: DiscoverMasthead(
                  gutter: side,
                  publicCount: ref.watch(publicRecipeCountProvider).valueOrNull,
                  // UX-021: the corpus is reachable from the top of the page,
                  // searching or not — the link under the grid is a screen of
                  // infinite scroll away, and hidden while a search is up.
                  onExplore: () => context.push(Routes.explore),
                  search: DiscoverSearchField(
                    controller: _searchController,
                    trailing: [
                      if (searching)
                        IconButton(
                          icon: const Icon(Icons.clear),
                          tooltip: 'Clear search',
                          onPressed: _clearSearch,
                        ),
                    ],
                    onChanged: _onSearchChanged,
                  ),
                ),
              ),

              // Searching replaces the whole page below the masthead. A shelf of
              // quick dinners under a list of search results is noise: the reader
              // has already said what they want.
              if (searching && _seed != null)
                // The one frame before a URL query reaches the provider: the
                // grid would read the old query and could flash a miss.
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: EdgeInsets.all(AppSpacing.xl),
                    child: LoadingView(),
                  ),
                )
              else if (searching)
                RecipeAsyncSliverGrid(
                  provider: searchResultsProvider,
                  padding: gridPadding,
                  empty: _SearchMiss(
                    key: kDiscoverSearchMissKey,
                    query: query.trim(),
                    onClear: _clearSearch,
                  ),
                )
              else ...[
                SliverPadding(
                  padding: gutter.copyWith(top: AppSpacing.xl),
                  sliver: SliverToBoxAdapter(
                    child: DiscoverCategoryTiles(
                      selected: category,
                      onSelect: _onTile,
                    ),
                  ),
                ),
                for (final shelf in _shelves(scheme))
                  SliverPadding(
                    padding: gutter.copyWith(top: AppSpacing.xl),
                    sliver: SliverToBoxAdapter(child: shelf),
                  ),
                SliverPadding(
                  padding: gutter.copyWith(top: AppSpacing.xxl),
                  sliver: SliverToBoxAdapter(
                    child: _BrowseHeader(
                      key: _browseKey,
                      category: category,
                      onClear: _clearCategory,
                    ),
                  ),
                ),
                if (category != null)
                  RecipeAsyncSliverGrid(
                    provider: categoryRecipesProvider,
                    padding: gridPadding,
                    empty: _categoryEmpty(category, onClear: _clearCategory),
                  )
                else
                  _BrowseGrid(
                    sort: ref.watch(browseSortProvider),
                    padding: gridPadding,
                  ),
                // The way into the corpus (Phase 35c). A link rather than a
                // fourth sort above, and below the grid rather than above it,
                // because the recipes people here wrote come first — this page
                // is the front door to Secret-Sauce, not to the web.
                SliverPadding(
                  padding: gutter.copyWith(top: AppSpacing.xl),
                  sliver: const SliverToBoxAdapter(child: _ExploreLink()),
                ),
              ],

              // Clearance for the compact chrome: the shell puts an extended FAB
              // and a NavigationBar over the bottom of this scroll, and the last
              // thing in it is a `Load more` button.
              SliverToBoxAdapter(
                child: SizedBox(
                  height: wide ? AppSpacing.xl : _kCompactChromeClearance,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The three shelves, in order. One accent for all three since 36c — the
  /// index line is reference 5's coloured kicker, and what tells one shelf from
  /// the next is its numeral, not a colour (three scheme roles used to do that
  /// job, and read as three unrelated sections).
  List<Widget> _shelves(ColorScheme scheme) => [
    DiscoverShelf(
      index: '01',
      title: 'Under 30',
      subtitle: 'Knife down to plate in half an hour, best-rated first.',
      kicker: 'RANKED BY RATING',
      accent: scheme.tertiary,
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
      accent: scheme.tertiary,
      provider: mostForkedShelfProvider,
      ranked: true,
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
///
/// While a category tile is selected the heading names it (`MAINS`) and the
/// sort links give way to a clear chip: the filtered grid has one order,
/// newest first, so offering three would be offering two that do nothing.
class _BrowseHeader extends ConsumerWidget {
  const _BrowseHeader({
    super.key,
    required this.category,
    required this.onClear,
  });

  final DiscoverCategory? category;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sort = ref.watch(browseSortProvider);
    final category = this.category;

    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          category == null ? 'EVERYTHING ELSE' : category.label.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          // The index line at section level (UX-031/UX-032 kicker
          // consolidation) — the shelves' heading role, in their accent.
          style: context.appText.kickerLarge.copyWith(color: scheme.tertiary),
        ),
        Text(
          category == null
              ? 'The whole public vault, one page at a time.'
              : 'Every public recipe filed under '
                  '${category.label.toLowerCase()}, newest first.',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );

    final Widget control =
        category != null
            ? ActionChip(
              key: kDiscoverClearCategoryKey,
              avatar: const Icon(Icons.close),
              label: Text(category.label),
              tooltip: 'Clear the category filter',
              onPressed: onClear,
            )
            : Wrap(
              spacing: AppSpacing.lg,
              runSpacing: AppSpacing.sm,
              children: [
                for (final option in BrowseSort.values)
                  _SortLink(
                    label: option.label,
                    selected: option == sort,
                    onTap:
                        () =>
                            ref.read(browseSortProvider.notifier).state =
                                option,
                  ),
              ],
            );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(height: _kBrowseRule, color: scheme.outlineVariant),
        const SizedBox(height: AppSpacing.md),
        LayoutBuilder(
          builder:
              (context, constraints) =>
                  constraints.maxWidth >=
                          _kBrowseHeaderRowWidth * context.textScale
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

    // UX-014: the underline and the colour say which sort is on; this says
    // it to a screen reader, which sees neither.
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.md),
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
            vertical: AppSpacing.xsPlus,
          ),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                width: _kSortUnderline,
                // Drawn in both states so selecting one does not move the row.
                color: selected ? scheme.primary : Colors.transparent,
              ),
            ),
          ),
          child: Text(
            label,
            // One weight in both states (UX-049): a heavier selected label
            // widened itself and pushed its neighbours along. Selection is the
            // colour and the underline.
            // The selected one in the brand colour, matching its underline —
            // the link colour everywhere since 36c.
            style: theme.textTheme.labelLarge?.copyWith(
              color: selected ? scheme.primary : scheme.onSurfaceVariant,
            ),
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

/// The clear chip over a filtered grid — keyed for tests.
const kDiscoverClearCategoryKey = Key('discover-clear-category');

/// An empty category says which tile and why, and offers the way back — the
/// shelves' rule that an empty state explains itself (AUDIT Preserve).
EmptyView _categoryEmpty(
  DiscoverCategory category, {
  required VoidCallback onClear,
}) {
  final name = category.label.toLowerCase();
  return EmptyView(
    title: 'No public $name yet',
    icon: Icons.local_dining_outlined,
    message:
        'Nothing public is filed under $name yet — a recipe shows here once '
        'its owner makes it public with a category on this tile.',
    action: TextButton(
      onPressed: onClear,
      child: const Text('Show everything'),
    ),
  );
}

EmptyView _empty(String title) => EmptyView(
  title: title,
  icon: Icons.local_dining_outlined,
  message: 'Public recipes will appear here.',
);

/// The miss state's key — for tests.
const kDiscoverSearchMissKey = Key('discover-search-miss');

/// Longest slice of the query the miss state's title repeats back. A pasted
/// paragraph would otherwise become the heading.
const int _kMissQueryMaxChars = 40;

/// A search that found nothing (UX-022 / UX-021).
///
/// It used to borrow the browse grid's "No matches / Public recipes will
/// appear here" — wrong (the reader searched; nothing is on its way) and a
/// dead end. It now repeats the query and offers the two ways on: clear the
/// search, or the web collection on `/explore`, which this search does not
/// reach.
class _SearchMiss extends StatelessWidget {
  const _SearchMiss({super.key, required this.query, required this.onClear});

  final String query;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final shown =
        query.length > _kMissQueryMaxChars
            ? '${query.substring(0, _kMissQueryMaxChars)}…'
            : query;
    return EmptyView(
      title: 'No recipes match “$shown”',
      icon: Icons.search_off,
      message:
          'Nothing public in the vault matches that. Try fewer or different '
          'words — or browse recipes published elsewhere on the web, kept '
          'with their credit and a link back.',
      // Wrap, so the two buttons stack rather than overflow on a phone at
      // 2.0× text.
      action: Wrap(
        alignment: WrapAlignment.center,
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [
          OutlinedButton.icon(
            onPressed: onClear,
            icon: const Icon(Icons.clear),
            label: const Text('Clear search'),
          ),
          TextButton.icon(
            onPressed: () => context.push(Routes.explore),
            icon: const Icon(Icons.travel_explore_outlined),
            label: const Text('Browse the web collection'),
          ),
        ],
      ),
    );
  }
}

/// The link to `/explore` (Phase 35c).
///
/// It names what is on the other side rather than saying "see more": the
/// difference between a recipe somebody here wrote and one captured from
/// somewhere else is the whole point of keeping them on separate pages, and a
/// link that hides the distinction undoes that in one tap.
class _ExploreLink extends StatelessWidget {
  const _ExploreLink();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(AppRadii.card),
      child: InkWell(
        onTap: () => context.push(Routes.explore),
        borderRadius: BorderRadius.circular(AppRadii.card),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Icon(
                Icons.travel_explore_outlined,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.md),
              // The icons are the non-flex children; the text takes what is
              // left (Gotcha 21).
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'From around the web',
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Recipes published elsewhere, kept with their credit and '
                      'a link back.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
