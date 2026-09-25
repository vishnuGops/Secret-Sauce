import 'package:core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How many chefs one page of the leaderboard holds — the panel's `TOP 25`, and
/// the unit `Load more` advances the offset by.
const kLeaderboardPageSize = 25;

/// How many chefs each rail shows.
const kChefRailLength = 10;

/// The window `/chef/:id`'s momentum line covers.
const kChefMomentumDays = 30;

/// How many chefs sit on each tier — the five tiles across the hero.
///
/// Kept separate from the board rather than tallied from its rows: the board is
/// one page of the ranking, so counting tiers from it would describe the top 25
/// while claiming to describe all 148.
final chefTierCountsProvider = FutureProvider.autoDispose<Map<ChefTier, int>>((
  ref,
) {
  return ref.watch(chefRepositoryProvider).tierCounts();
});

/// The board's three orderings (Phase 33 enabled all three).
///
/// Three different queries, not one list re-sorted in memory — the board is
/// paged, so a client-side sort would only reorder the rows already fetched:
///  * `score` — `chefs_leaderboard`, all-time `chef_score`.
///  * `momentum` — `chefs_leaderboard_windowed` over the hero's Month / Week:
///    points earned inside the window, counted from the dated logs.
///  * `newest` — `chefs_leaderboard` re-ordered by join date, newest first.
enum BoardSort {
  score('Score'),
  momentum('Momentum'),
  newest('New');

  const BoardSort(this.label);

  final String label;
}

/// The hero's time filter — the span the Momentum board measures.
enum ChefsWindow {
  allTime('All time', null),
  month('Month', 30),
  week('Week', 7);

  const ChefsWindow(this.label, this.days);

  final String label;

  /// `p_days` for the windowed RPCs. Null is "no window" — the all-time board.
  final int? days;

  /// The span as a reader says it, under a gain: `last 7 days`.
  String get span => days == null ? 'all time' : 'last $days days';
}

/// What the board is showing: an ordering, and the window it is measured over.
///
/// One state rather than two independent selections, because the two controls
/// are not independent. "Momentum over all time" means nothing (it is the Score
/// board), and "Score this week" is exactly Momentum this week — so
/// [BoardViewNotifier] keeps them coupled: a window other than All time **is**
/// the Momentum board, and every other sort is all-time. The hero's pill
/// therefore always tells the truth about the numbers under it.
@immutable
class BoardView {
  const BoardView({
    this.sort = BoardSort.score,
    this.window = ChefsWindow.allTime,
  });

  final BoardSort sort;
  final ChefsWindow window;

  /// The window the board's query takes, or null for an all-time query. Falls
  /// back to a month for a hand-built momentum view with no window, so the
  /// query never receives "momentum over nothing".
  int? get days =>
      sort == BoardSort.momentum
          ? (window.days ?? ChefsWindow.month.days)
          : null;

  @override
  bool operator ==(Object other) =>
      other is BoardView && other.sort == sort && other.window == window;

  @override
  int get hashCode => Object.hash(sort, window);

  @override
  String toString() => 'BoardView(${sort.name}, ${window.name})';
}

/// Owns [BoardView] and the coupling between its two halves.
class BoardViewNotifier extends AutoDisposeNotifier<BoardView> {
  @override
  BoardView build() => const BoardView();

  /// Value equality, not identity: re-tapping the tab that is already selected
  /// builds an equal [BoardView], and notifying on it would rebuild the board
  /// from page 1 — dropping every loaded page for a tap that changed nothing.
  @override
  bool updateShouldNotify(BoardView previous, BoardView next) =>
      previous != next;

  /// A board tab. Momentum keeps the window the hero already shows, or takes a
  /// month when the hero was on All time; the other two are all-time boards.
  void selectSort(BoardSort sort) {
    state = switch (sort) {
      BoardSort.momentum => BoardView(
        sort: sort,
        window:
            state.window == ChefsWindow.allTime
                ? ChefsWindow.month
                : state.window,
      ),
      _ => BoardView(sort: sort),
    };
  }

  /// A hero window. Month or Week turns the board to Momentum over that span;
  /// All time turns Momentum back into Score and leaves `New` alone.
  void selectWindow(ChefsWindow window) {
    state =
        window == ChefsWindow.allTime
            ? BoardView(
              sort:
                  state.sort == BoardSort.momentum
                      ? BoardSort.score
                      : state.sort,
            )
            : BoardView(sort: BoardSort.momentum, window: window);
  }
}

final boardViewProvider =
    NotifierProvider.autoDispose<BoardViewNotifier, BoardView>(
      BoardViewNotifier.new,
    );

/// One board row: the chef, and — on the Momentum board — what they earned in
/// the window.
@immutable
class ChefBoardRow {
  const ChefBoardRow(this.standing, [this.window]);

  final ChefStanding standing;
  final ChefWindowStats? window;
}

/// The board so far: every page loaded, whether the server looks like it has
/// more, and whether the next page is in flight — [RecipePage]'s shape, for
/// chefs. `loadingMore` lives in the data so the rows on screen stay there.
@immutable
class ChefBoardPage {
  const ChefBoardPage({
    this.rows = const [],
    this.hasMore = false,
    this.loadingMore = false,
    this.since,
  });

  final List<ChefBoardRow> rows;
  final bool hasMore;
  final bool loadingMore;

  /// The Momentum board's pinned boundary — page 1's `window_start` — sent as
  /// `p_since` on every page after it. Null on an all-time board, and on a
  /// Momentum board whose first page came back empty (there is no page 2).
  final DateTime? since;

  ChefBoardPage copyWith({bool? loadingMore}) => ChefBoardPage(
    rows: rows,
    hasMore: hasMore,
    loadingMore: loadingMore ?? this.loadingMore,
    since: since,
  );
}

/// The leaderboard, paged (Phase 33 — it used to be one `limit: 25 × n` read
/// that `Show all` widened).
///
/// Each page is one `limit`/`offset` request, which is only sound because every
/// query behind it has a **total** order ending in the profile id (Gotcha 24).
/// The Momentum board adds the second half of that rule: a window measured
/// from `now()` moves between two requests, so page 1 is sent **without**
/// `p_since`, the server's own boundary is read back off its first row
/// (`window_start`), and that is sent on every page after it. The server's
/// clock, not the device's: the rails beside the board send no boundary at
/// all, so a device clock hours off would otherwise put two different windows
/// under one "last 7 days" label — and a clock far ahead would ask for a
/// future boundary and show a false "Nothing moved". A browser `DateTime`
/// keeps milliseconds only, so the echoed boundary can come back up to a
/// millisecond early; page 2 then measures a window under a millisecond
/// wider, which no count can see.
///
/// **A page from a previous ordering never lands on this one.** A re-sort
/// rebuilds the same notifier instance, so `_generation` is bumped per build
/// and a [loadMore] that started under the old ordering drops its result
/// rather than writing Score rows under the `New` tab — and then paging the
/// new ordering from the old one's offset (Gotcha 24).
///
/// **The Momentum board lists only chefs who moved.** The windowed RPC returns
/// every ranked chef, quiet ones last (they tie at zero), and a board of zeros
/// under a `Momentum` tab is the all-time board wearing the wrong name. So the
/// first zero-score row ends the list: it and everything after it are dropped
/// and `hasMore` goes false. A window where nobody moved is therefore an
/// **empty page**, which the screen renders as an empty state — a stale sim
/// anchor produces exactly that, and it is old data, not a failure.
class ChefBoardNotifier extends AutoDisposeAsyncNotifier<ChefBoardPage> {
  BoardView _view = const BoardView();
  DateTime? _since;
  bool _disposed = false;
  int _generation = 0;

  int get pageSize => kLeaderboardPageSize;

  @override
  Future<ChefBoardPage> build() async {
    // Re-armed per build: `onDispose` also fires on a rebuild (a new sort), and
    // the notifier instance survives it.
    _disposed = false;
    _generation++;
    ref.onDispose(() => _disposed = true);

    // Synchronous, before any await: this is what makes a new sort or window a
    // new build starting at offset 0, never an offset carried across orderings.
    _view = ref.watch(boardViewProvider);
    // Pinned from page 1's reply in [_fetch], never from the device clock.
    _since = null;

    final (rows, more) = await _fetch(0);
    return ChefBoardPage(rows: rows, hasMore: more, since: _since);
  }

  Future<(List<ChefBoardRow>, bool)> _fetch(int offset) async {
    final chefs = ref.read(chefRepositoryProvider);
    switch (_view.sort) {
      case BoardSort.score:
        final rows = await chefs.leaderboard(limit: pageSize, offset: offset);
        return (
          [for (final r in rows) ChefBoardRow(r)],
          rows.length == pageSize,
        );
      case BoardSort.newest:
        final rows = await chefs.newest(limit: pageSize, offset: offset);
        return (
          [for (final r in rows) ChefBoardRow(r)],
          rows.length == pageSize,
        );
      case BoardSort.momentum:
        final rows = await chefs.windowedLeaderboard(
          days: _view.days!,
          limit: pageSize,
          offset: offset,
          since: _since,
        );
        // The server's boundary, pinned the first time a page carries one.
        if (_since == null && rows.isNotEmpty) {
          _since = rows.first.window.windowStart;
        }
        final moved = [
          for (final r in rows)
            if (r.window.moved) ChefBoardRow(r.standing, r.window),
        ];
        // Ordered by window score first, so the first quiet row means every
        // row behind it is quiet too.
        return (moved, rows.length == pageSize && rows.last.window.moved);
    }
  }

  /// Append the next page; a no-op while one is in flight or when there is
  /// nothing more. On failure the rows already loaded stay and the error is
  /// rethrown for the caller to surface — [PagedRecipesNotifier.loadMore]'s
  /// contract.
  Future<void> loadMore() async {
    // Mid re-sort the state still carries the previous ordering's page as its
    // value; paging from it would append the new ordering to the old one.
    if (state.isLoading) return;
    final current = state.valueOrNull;
    if (current == null || !current.hasMore || current.loadingMore) return;
    final generation = _generation;

    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final (rows, more) = await _fetch(current.rows.length);
      if (_disposed || generation != _generation) return;
      // A chef who publishes their first public recipe between two pages
      // shifts the window by one; drop a row already on screen rather than
      // show it twice.
      final seen = {for (final r in current.rows) r.standing.id};
      state = AsyncData(
        ChefBoardPage(
          rows: [
            ...current.rows,
            for (final r in rows)
              if (seen.add(r.standing.id)) r,
          ],
          hasMore: more,
          since: current.since,
        ),
      );
    } catch (_) {
      if (!_disposed && generation == _generation) {
        state = AsyncData(current.copyWith(loadingMore: false));
      }
      rethrow;
    }
  }
}

/// The board. Signed-out safe: every RPC behind it is granted to `anon`.
final chefBoardProvider =
    AsyncNotifierProvider.autoDispose<ChefBoardNotifier, ChefBoardPage>(
      ChefBoardNotifier.new,
    );

/// The Popular rail — the top of the all-time board, one short read of its own.
///
/// Its own request rather than the board's first page, because the board is now
/// re-sortable and paged: reading the rail off it would reshuffle the Popular
/// shelf every time someone picked `New`.
final popularChefsProvider = FutureProvider.autoDispose<List<ChefStanding>>(
  (ref) =>
      ref.watch(chefRepositoryProvider).leaderboard(limit: kChefRailLength),
);

/// A windowed rail — Trending (a week) and Best of the month (30 days): the top
/// of `chefs_leaderboard_windowed`, **movers only**, for the reason given on
/// [ChefBoardNotifier]. Empty is a real answer (nobody moved), not a failure.
///
/// No `p_since`: a rail is one page, so there is no second request for the
/// boundary to move under.
final windowRailProvider = FutureProvider.autoDispose
    .family<List<ChefWindowStanding>, ChefsWindow>((ref, window) async {
      final rows = await ref
          .watch(chefRepositoryProvider)
          .windowedLeaderboard(
            days: window.days ?? ChefsWindow.month.days!,
            limit: kChefRailLength,
          );
      return [
        for (final r in rows)
          if (r.window.moved) r,
      ];
    });

/// One chef's last [kChefMomentumDays] days — the momentum line on `/chef/:id`.
///
/// The same `chef_window_stats` the board ranks, called with `p_chef`, so the
/// line and the board cannot disagree (the reason the SQL has one function that
/// computes and one that ranks). Null for a profile that holds no rank.
final chefMomentumProvider = FutureProvider.autoDispose
    .family<ChefWindowStats?, String>((ref, chefId) {
      return ref
          .watch(chefRepositoryProvider)
          .windowStats(chefId, days: kChefMomentumDays);
    });

/// Total chefs on the board — the denominator in "Rank 2 of 148".
///
/// Derived from [chefTierCountsProvider] rather than fetched (OPT-P10): the
/// tier counts cover exactly the same population — profiles with at least one
/// public recipe — so the total is their sum, and asking the server for it
/// again was a sixth round trip for a number the first five already contained.
/// Four call sites share the one request.
///
/// Read with `valueOrNull` at the call site: the header drops to "Rank 2"
/// rather than blocking the whole card on a count.
final chefCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final counts = await ref.watch(chefTierCountsProvider.future);
  return counts.values.fold<int>(0, (sum, n) => sum + n);
});

/// Everything `/chef/:id` needs about the chef themself: the profile row and
/// the leaderboard standing, fetched together (Phase 30).
///
/// The two are deliberately separate reads with different failure meanings. The
/// **profile** is the page — without it there is no chef and the route is a 404.
/// The **standing** is null for a real profile that simply holds no rank
/// (private-only, brand-new, no public recipe), which is a state the page
/// renders rather than an error.
class ChefPageData {
  const ChefPageData({
    required this.profile,
    this.standing,
    this.entities = const [],
  });

  final Profile profile;

  /// Null when this profile is not on the board — see [ChefRepository.standing].
  final ChefStanding? standing;

  /// The groups this chef is listed under (Phase 35b). Empty is the normal
  /// case: most profiles never join one, and the affiliation line is simply
  /// absent rather than showing "no affiliations".
  final List<Entity> entities;

  /// A chef page for somebody who has never signed up — a name the corpus
  /// credits, with no account behind it.
  ///
  /// Read off `kind` rather than inferred from a null standing: an imported
  /// chef is *also* unranked, but so is a brand-new member, and the two pages
  /// have to say different things.
  bool get isUnclaimed => profile.kind.isImported;
}

/// Profile + standing for one chef.
///
/// Both requests are started before either is awaited (the OPT-P10 shape) —
/// they are independent, so awaiting the profile first would cost the sum of two
/// round trips instead of the slower one.
///
/// Unlike the dialog this replaced, **neither read is swallowed**: the board
/// used to hand the card a `ChefStanding` it already had, so a failed fetch cost
/// one section; here the page has a uuid and nothing else, so a failure is a
/// failure and the screen shows a retry.
final chefPageProvider = FutureProvider.autoDispose.family<
  ChefPageData,
  String
>((ref, chefId) async {
  final profiles = ref.watch(profileRepositoryProvider);
  final chefs = ref.watch(chefRepositoryProvider);

  // `Future.wait`, not two sequential awaits over two started futures.
  // Starting both and awaiting them one after the other leaves the second
  // with **no handler attached** until the first completes, so a fast failure
  // there is delivered as an unhandled async error before anything can catch
  // it — the provider still reports it, and the app also logs a zone error
  // for the same exception. `Future.wait` subscribes to both up front and
  // rethrows the first failure, which keeps the parallelism without the
  // window.
  // The affiliation read joins the same pattern: three independent requests,
  // all started before any is awaited.
  final entities = ref.watch(entityRepositoryProvider);
  final results = await Future.wait<Object?>([
    profiles.getById(chefId),
    chefs.standing(chefId),
    entities.forProfile(chefId),
  ]);

  final profile = results[0] as Profile?;
  if (profile == null) {
    // The one genuine 404: a uuid with no profile behind it. A *null
    // standing* is not this — see [ChefPageData].
    throw StateError('No chef with id $chefId');
  }
  return ChefPageData(
    profile: profile,
    standing: results[1] as ChefStanding?,
    entities: results[2] as List<Entity>,
  );
});

/// Which chef `/chef/:id` is showing — the argument [ChefRecipesNotifier] pages
/// against. **Meant to be overridden**, never read at its default.
///
/// Not a `.family` on the notifier: a family notifier has to extend
/// `AutoDisposeFamilyAsyncNotifier`, which is not a [PagedRecipesNotifier], so
/// it could not use the shared `RecipeAsyncSliverGrid` ladder at all — and
/// re-implementing that ladder is what OPT-A7 consolidated away.
///
/// `ChefPage` supplies it by wrapping its subtree in a `ProviderScope` that
/// overrides this **and** [chefRecipesProvider], so each page gets its own
/// notifier bound to its own chef. The alternative — writing a `StateProvider`
/// from `initState` — throws `Tried to modify a provider while the widget tree
/// was building`, which is how this arrived at the scoped form.
///
/// The default is empty so a stray read fetches nothing rather than paging some
/// arbitrary chef, exactly as an empty search query does.
final viewedChefIdProvider = Provider<String>((ref) => '');

/// How `/chef/:id`'s recipe grid is ordered (Phase 31).
///
/// A **sort**, not a filter: all three show the same set — every public recipe
/// this chef owns — in three orders. For a chef with fewer than one page of
/// recipes the tabs only rearrange the same cards, which is exactly what
/// Discover's [BrowseSort] does to the browse grid and is why the copy says
/// nothing about narrowing anything down.
///
/// Like [BoardSort], every option here has data behind it.
enum ChefSort {
  /// Newest first — the chef's catalogue, straight off the table.
  all('All'),

  /// `chef_score()` per recipe: the same function the score panel above the
  /// grid explains, so the list cannot disagree with the number (Gotcha 19).
  popular('Popular'),

  /// `likes × 2 + distinct viewers` earned in the last seven days.
  trending('Trending');

  const ChefSort(this.label);

  final String label;
}

/// The selected sort. **Overridden per page** alongside [viewedChefIdProvider]
/// so two stacked chef pages cannot share one selection.
final chefSortProvider = StateProvider.autoDispose<ChefSort>(
  (ref) => ChefSort.all,
);

/// One chef's public recipes, paged — the grid on `/chef/:id`.
class ChefRecipesNotifier extends PagedRecipesNotifier {
  /// The chef this build is serving. Captured once, so `Load more` cannot page
  /// one chef's offsets against another chef's results.
  String _chefId = '';

  /// Likewise the sort: paging one ordering's offsets against another
  /// ordering's results is the same defect one level down (Gotcha 24).
  ChefSort _sort = ChefSort.all;

  @override
  Future<RecipePage> firstPage() {
    // Synchronous, before any `await`: this is the build phase, and it is what
    // makes a new chef — or a new sort — a new build.
    _chefId = ref.watch(viewedChefIdProvider);
    _sort = ref.watch(chefSortProvider);
    if (_chefId.isEmpty) return Future.value(const RecipePage());
    return super.firstPage();
  }

  @override
  Future<List<Recipe>> fetchPage({required int limit, required int offset}) {
    // Two repositories on purpose. `all` is a plain table read that PostgREST
    // can express, so it costs no RPC; the other two rank by an expression it
    // cannot order by, which is what those RPCs exist for.
    return switch (_sort) {
      ChefSort.all => ref
          .read(recipeRepositoryProvider)
          .listByChef(_chefId, limit: limit, offset: offset),
      ChefSort.popular => ref
          .read(chefRepositoryProvider)
          .topRecipes(_chefId, limit: limit, offset: offset),
      ChefSort.trending => ref
          .read(chefRepositoryProvider)
          .trendingRecipes(_chefId, limit: limit, offset: offset),
    };
  }
}

final chefRecipesProvider =
    AsyncNotifierProvider.autoDispose<ChefRecipesNotifier, RecipePage>(
      ChefRecipesNotifier.new,
    );
