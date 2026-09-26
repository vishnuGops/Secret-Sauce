import 'dart:async';
import 'dart:ui' show Tristate;

// Overrides `chefRepositoryProvider` (core) rather than the screen's own
// providers, so the notifier and provider wiring in chefs_providers.dart is
// exercised too instead of being stubbed out.
import 'package:app/features/chefs/chefs_hero.dart';
import 'package:app/features/chefs/chefs_providers.dart';
import 'package:app/features/chefs/chefs_rails.dart';
import 'package:app/features/chefs/chefs_screen.dart';
import 'package:app/routing/app_router.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// One recorded page request: which query, and the window it asked for.
typedef _Call =
    ({String rpc, int limit, int offset, int? days, DateTime? since});

/// Stand-in for the RPCs. `ChefRepository` is an abstract interface precisely
/// so it can be swapped like this — no Supabase client is constructed.
class _FakeChefRepository implements ChefRepository {
  _FakeChefRepository(this._result, {this.windowed = const []});

  /// A `List<ChefStanding>` to return, an `Exception` to throw, or null to
  /// hang forever (so the loading state can be observed).
  final Object? _result;

  /// What `chefs_leaderboard_windowed` answers, in its own order: movers first,
  /// quiet chefs (score 0) last, the way the RPC orders them.
  final List<ChefWindowStanding> windowed;

  /// Fixed: the header renders "Rank 2 of 148" from this.
  static const count = 148;

  /// Every page request, board and rails alike. The board asks for
  /// [kLeaderboardPageSize] rows and the rails for [kChefRailLength], which is
  /// how the assertions below tell them apart.
  final List<_Call> calls = [];

  Iterable<_Call> boardCalls(String rpc) =>
      calls.where((c) => c.rpc == rpc && c.limit == kLeaderboardPageSize);

  List<ChefStanding> get _all => _result as List<ChefStanding>;

  @override
  Future<List<ChefStanding>> leaderboard({int limit = 50, int offset = 0}) {
    calls.add((
      rpc: 'leaderboard',
      limit: limit,
      offset: offset,
      days: null,
      since: null,
    ));
    if (_result == null) return Completer<List<ChefStanding>>().future;
    if (_result is Exception) return Future.error(_result);
    // Honour the window the way the RPC does: `limit` rows from `offset`.
    return Future.value(_all.skip(offset).take(limit).toList());
  }

  @override
  Future<List<ChefStanding>> newest({int limit = 50, int offset = 0}) {
    calls.add((
      rpc: 'newest',
      limit: limit,
      offset: offset,
      days: null,
      since: null,
    ));
    if (_result is! List<ChefStanding>) return Future.value(const []);
    final sorted = [..._all]..sort(
      (a, b) =>
          (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)),
    );
    return Future.value(sorted.skip(offset).take(limit).toList());
  }

  @override
  Future<List<ChefWindowStanding>> windowedLeaderboard({
    required int days,
    int limit = 50,
    int offset = 0,
    DateTime? since,
  }) {
    calls.add((
      rpc: 'windowed',
      limit: limit,
      offset: offset,
      days: days,
      since: since,
    ));
    return Future.value(windowed.skip(offset).take(limit).toList());
  }

  @override
  Future<ChefWindowStats?> windowStats(
    String chefId, {
    required int days,
    DateTime? since,
  }) async => null;

  // Nothing on this screen calls it since Phase 30 replaced the expanded card —
  // which listed top recipes — with `/chef/:id`, which lists all of them.
  @override
  Future<List<Recipe>> topRecipes(
    String chefId, {
    int limit = 3,
    int offset = 0,
  }) => throw UnimplementedError();

  @override
  Future<List<Recipe>> trendingRecipes(
    String chefId, {
    int limit = 20,
    int offset = 0,
  }) => throw UnimplementedError();

  @override
  Future<ChefStanding?> standing(String chefId) async {
    if (_result is! List<ChefStanding>) return null;
    for (final s in _all) {
      if (s.id == chefId) return s;
    }
    return null;
  }

  // No `chefCount()` any more (OPT-P10) — the board's denominator is the sum of
  // the tier counts below, which is why they add up to [count] (148).
  @override
  Future<Map<ChefTier, int>> tierCounts() async => const {
    ChefTier.homeCook: 61,
    ChefTier.lineCook: 44,
    ChefTier.sousChef: 28,
    ChefTier.headChef: 14,
    ChefTier.masterChef: 1,
  };
}

class _FakeProfileRepository implements ProfileRepository {
  @override
  Future<Profile?> getById(String id) async => Profile(
    id: id,
    displayName: 'Secret Sauce Kitchen',
    createdAt: DateTime(2025, 3, 14),
  );

  @override
  Future<List<Profile>> searchByName(String query, {int limit = 10}) async =>
      const [];

  @override
  Future<Profile> updateMine(Profile profile) async => profile;
}

final _board = [
  ChefStanding(
    chefRank: 1,
    id: 'd1',
    displayName: 'Amara Okonkwo',
    chefTier: ChefTier.masterChef,
    chefScore: 21000,
    publicRecipeCount: 2,
    totalLikes: 4000,
    totalSaves: 1600,
    totalViews: 5000,
    createdAt: DateTime.utc(2024, 1, 5),
  ),
  // Tied pair — dense_rank gives both rank 4, which must render as two "4"s.
  ChefStanding(
    chefRank: 4,
    id: 'd3',
    displayName: 'Chen Wei',
    chefTier: ChefTier.sousChef,
    chefScore: 1200,
    publicRecipeCount: 1,
    createdAt: DateTime.utc(2026, 9, 20),
  ),
  ChefStanding(
    chefRank: 4,
    id: 'd7',
    displayName: 'Greta Lindqvist',
    chefTier: ChefTier.sousChef,
    chefScore: 1200,
    publicRecipeCount: 1,
    createdAt: DateTime.utc(2025, 6, 1),
  ),
];

const _kitchen = ChefStanding(
  chefRank: 2,
  id: 'ssk',
  displayName: 'Secret Sauce Kitchen',
  chefTier: ChefTier.headChef,
  chefScore: 10189,
  publicRecipeCount: 14,
  totalLikes: 1980,
  totalSaves: 780,
  totalViews: 1745,
);

/// A windowed row: [standing] with what it earned, ranked [rank] in the window.
ChefWindowStanding _moved(
  ChefStanding standing, {
  required int rank,
  int likes = 0,
  int saves = 0,
  int viewers = 0,
}) => ChefWindowStanding(
  standing: standing.copyWith(chefRank: rank),
  window: ChefWindowStats(
    id: standing.id,
    windowStart: DateTime.utc(2026, 8, 25),
    likes: likes,
    saves: saves,
    viewers: viewers,
    // What `chef_score()` would say — computed here from the same formula the
    // Dart mirror pins (Gotcha 19), never used by the widgets for arithmetic.
    score: ChefScoring.score(likes: likes, saves: saves, views: viewers),
  ),
);

/// Chen moved most this window, Amara a little, Greta not at all — so the
/// Momentum order is not the Score order, and one row is quiet.
final _window = [
  _moved(_board[1], rank: 1, likes: 40, saves: 12, viewers: 60),
  _moved(_board[0], rank: 2, likes: 2),
  _moved(_board[2], rank: 3),
];

/// Sizes the test window, since the screen renders three different layouts.
/// 400 is the phone board, 1440 the two-column page.
void _size(WidgetTester tester, double width, [double height = 1000]) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

_FakeChefRepository? _lastRepo;

Widget _app(
  Object? result, {
  double textScale = 1.0,
  List<ChefWindowStanding> windowed = const [],
}) {
  final repo = _FakeChefRepository(result, windowed: windowed);
  _lastRepo = repo;
  return ProviderScope(
    overrides: [
      chefRepositoryProvider.overrideWithValue(repo),
      profileRepositoryProvider.overrideWithValue(_FakeProfileRepository()),
    ],
    child: MaterialApp.router(
      theme: AppTheme.light(),
      // `builder`, not a MediaQuery around the page: route pages are pushed
      // above this Navigator, so anything wrapped inside one never reaches them
      // and the text-scale envelope would silently test 1.0x.
      builder:
          (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
      routerConfig: _router(),
    ),
  );
}

/// The board **navigates** instead of opening a dialog, so these tests need a
/// real router: `context.push` throws without one.
///
/// `/chef/:id` lands on a probe rather than the real `ChefPage` — this suite is
/// about the board sending you to the right chef, and the page's own content is
/// covered by `chef_page_test.dart` with its own fakes.
GoRouter _router() => GoRouter(
  initialLocation: Routes.chefs,
  routes: [
    GoRoute(
      path: Routes.chefs,
      builder: (context, state) => const ChefsScreen(),
    ),
    GoRoute(
      path: Routes.chefPattern,
      builder:
          (context, state) =>
              Scaffold(body: Text('CHEF PAGE ${state.pathParameters['id']}')),
    ),
  ],
);

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(ChefsScreen)));

List<ChefStanding> _many(int n) => [
  for (var i = 0; i < n; i++)
    ChefStanding(
      chefRank: i + 1,
      id: 'c$i',
      displayName: 'Chef $i',
      chefScore: (9000 - i * 100).toDouble(),
      publicRecipeCount: 1,
      createdAt: DateTime.utc(2026, 1, 1).add(Duration(days: i)),
    ),
];

SemanticsData _a11y(WidgetTester tester, Finder finder) =>
    tester.getSemantics(finder).getSemanticsData();

void main() {
  // OPT-P10 removed `chefCount()`; `chefCountProvider` now sums the tier counts
  // instead, which is only correct because both cover the same population.
  test('the fake tier counts sum to the board total', () async {
    final counts = await _FakeChefRepository(const []).tierCounts();
    expect(
      counts.values.fold<int>(0, (sum, n) => sum + n),
      _FakeChefRepository.count,
    );
  });

  // The coupling between the hero's window and the board's tabs is the one
  // piece of logic here with no widget in it — so it is pinned without one.
  group('BoardView coupling', () {
    BoardViewNotifier notifier(ProviderContainer c) =>
        c.read(boardViewProvider.notifier);

    test('starts on Score, all time', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.listen(boardViewProvider, (_, __) {});
      expect(c.read(boardViewProvider), const BoardView());
      expect(c.read(boardViewProvider).days, isNull);
    });

    test('Momentum from All time takes a month', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.listen(boardViewProvider, (_, __) {});
      notifier(c).selectSort(BoardSort.momentum);
      expect(
        c.read(boardViewProvider),
        const BoardView(sort: BoardSort.momentum, window: ChefsWindow.month),
      );
      expect(c.read(boardViewProvider).days, 30);
    });

    test('a window turns the board to Momentum; All time turns it back', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.listen(boardViewProvider, (_, __) {});
      notifier(c).selectWindow(ChefsWindow.week);
      expect(c.read(boardViewProvider).sort, BoardSort.momentum);
      expect(c.read(boardViewProvider).days, 7);

      notifier(c).selectWindow(ChefsWindow.allTime);
      expect(c.read(boardViewProvider), const BoardView());
    });

    test('Score and New are all-time boards', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.listen(boardViewProvider, (_, __) {});
      notifier(c).selectWindow(ChefsWindow.week);
      notifier(c).selectSort(BoardSort.newest);
      expect(
        c.read(boardViewProvider),
        const BoardView(sort: BoardSort.newest),
      );
      // All time leaves New alone rather than resetting it to Score.
      notifier(c).selectWindow(ChefsWindow.allTime);
      expect(c.read(boardViewProvider).sort, BoardSort.newest);
    });
  });

  group('compact board', () {
    testWidgets('renders a ranked board with tiers and grouped scores', (
      tester,
    ) async {
      _size(tester, 400);
      await tester.pumpWidget(_app(_board));
      await tester.pumpAndSettle();

      expect(find.text('Amara Okonkwo'), findsOneWidget);
      expect(find.text('Master Chef'), findsOneWidget);
      expect(find.text('21,000'), findsOneWidget);
      expect(find.byType(ChefStandingCard), findsNWidgets(3));

      // Rank 1 is a podium row: medal + "#1", no numeral.
      expect(find.byIcon(Icons.workspace_premium), findsOneWidget);
      expect(find.text('#1'), findsOneWidget);

      // Tied chefs share a rank: two rows both showing "4".
      expect(find.text('4'), findsNWidgets(2));
      expect(find.text('Sous Chef'), findsNWidgets(2));

      // The page chrome is web-only.
      expect(find.byType(ChefsHero), findsNothing);
      expect(find.byType(CardRail), findsNothing);
    });

    testWidgets('carries the three orderings the hero-less layout needs', (
      tester,
    ) async {
      _size(tester, 400);
      await tester.pumpWidget(_app(_board, windowed: _window));
      await tester.pumpAndSettle();

      for (final label in ['Score', 'Momentum', 'New']) {
        expect(find.text(label), findsOneWidget);
      }
      // No window pill until Momentum asks for one.
      expect(find.text('Week'), findsNothing);

      await tester.tap(find.text('Momentum'));
      await tester.pumpAndSettle();
      expect(find.text('Month'), findsOneWidget);
      expect(_lastRepo!.boardCalls('windowed').last.days, 30);

      await tester.tap(find.text('Week'));
      await tester.pumpAndSettle();
      expect(_lastRepo!.boardCalls('windowed').last.days, 7);
      // All time is the Score tab, not a Momentum window.
      expect(find.text('All time'), findsNothing);
    });

    testWidgets('shows the empty state when nobody qualifies', (tester) async {
      _size(tester, 400);
      await tester.pumpWidget(_app(<ChefStanding>[]));
      await tester.pumpAndSettle();

      expect(find.byType(EmptyView), findsOneWidget);
      expect(find.text('No chefs yet'), findsOneWidget);
      expect(find.byType(ChefStandingCard), findsNothing);
    });

    testWidgets('shows a retryable error state', (tester) async {
      _size(tester, 400);
      await tester.pumpWidget(_app(Exception('rpc down')));
      await tester.pumpAndSettle();

      expect(find.byType(ErrorView), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('shows the loading state while the RPC is in flight', (
      tester,
    ) async {
      _size(tester, 400);
      await tester.pumpWidget(_app(null)); // never resolves
      await tester.pump();
      expect(find.byType(LoadingView), findsOneWidget);
      expect(find.byType(ChefStandingCard), findsNothing);
    });

    testWidgets('pages with Load more at the end of the list', (tester) async {
      _size(tester, 400, 900);
      await tester.pumpWidget(_app(_many(30)));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('Load more'), 400);
      await tester.tap(find.text('Load more'));
      await tester.pumpAndSettle();

      final pages = _lastRepo!.boardCalls('leaderboard').toList();
      expect(pages.map((c) => c.offset), [0, kLeaderboardPageSize]);
      await tester.scrollUntilVisible(find.text('Chef 29'), 400);
      expect(find.text('Chef 29'), findsOneWidget);
      // A short second page is the end: no button promising a third.
      expect(find.text('Load more'), findsNothing);
    });
  });

  // The Phase 21 carry-over: the web shell draws `TopNavBar` above every shell
  // screen, so the screen's own `AppBar` was a second bar stacked under it.
  // Compact has no top bar, so the phone board keeps its title bar.
  group('app bar', () {
    AppBar? screenAppBar(WidgetTester tester) {
      final bars = find.descendant(
        of: find.byType(ChefsScreen),
        matching: find.byType(AppBar),
      );
      return bars.evaluate().isEmpty ? null : tester.widget<AppBar>(bars);
    }

    testWidgets('the phone board has its own', (tester) async {
      _size(tester, 400);
      await tester.pumpWidget(_app(_board));
      await tester.pumpAndSettle();

      expect(screenAppBar(tester), isNotNull);
    });

    for (final width in <double>[600, 1000, 1440]) {
      testWidgets('none at ${width}px, where the web top bar is', (
        tester,
      ) async {
        _size(tester, width, 1200);
        await tester.pumpWidget(_app(_board));
        await tester.pumpAndSettle();

        expect(screenAppBar(tester), isNull);
        // The hero's display title is the page title instead.
        expect(find.byType(ChefsHero), findsOneWidget);
      });
    }
  });

  group('the page', () {
    testWidgets('draws the hero, the board panel and three rails', (
      tester,
    ) async {
      // Tall enough that the rails column builds all three: a `ListView` only
      // builds what is on screen.
      _size(tester, 1440, 2200);
      await tester.pumpWidget(_app(_board));
      await tester.pumpAndSettle();

      expect(find.byType(ChefsHero), findsOneWidget);
      expect(find.text('148 ranked'), findsOneWidget);
      expect(find.text('61'), findsOneWidget); // Home Cook tile
      expect(find.text('HOME COOK'), findsOneWidget);
      expect(find.text('MASTER CHEF'), findsWidgets);

      // The draft's "recomputed 4h ago" is wrong about this build.
      expect(find.textContaining('RECOMPUTED'), findsNothing);
      expect(find.textContaining('LIVE ·'), findsOneWidget);

      expect(find.text('Leaderboard'), findsOneWidget);
      expect(find.text('TOP 3 / 148'), findsOneWidget);
      expect(find.text('Ties share a rank.'), findsOneWidget);
      expect(
        tester
            .widgetList<ChefStandingCard>(find.byType(ChefStandingCard))
            .every((c) => c.variant == ChefCardVariant.board),
        isTrue,
      );

      expect(find.byType(CardRail), findsNWidgets(3));
      expect(find.text('Popular chefs'), findsOneWidget);
      expect(find.text('Trending chefs'), findsOneWidget);
      expect(find.text('Best chefs of the month'), findsOneWidget);
      expect(find.byType(ChefSpotlightCard), findsWidgets);
    });

    testWidgets('every control is live — nothing is drawn and disabled', (
      tester,
    ) async {
      _size(tester, 1440);
      await tester.pumpWidget(_app(_board));
      await tester.pumpAndSettle();

      for (final label in ['Score', 'Momentum', 'New']) {
        expect(find.text(label), findsOneWidget);
      }
      for (final label in ['All time', 'Month', 'Week']) {
        expect(find.text(label), findsOneWidget);
      }
      // The Phase 23 "not wired up yet" tooltips are gone with the reason.
      expect(find.textContaining('not wired up'), findsNothing);
      expect(find.textContaining('Placeholder cards'), findsNothing);
    });

    testWidgets('an empty board keeps the Popular heading and says why', (
      tester,
    ) async {
      _size(tester, 1440, 2200);
      await tester.pumpWidget(_app(<ChefStanding>[]));
      await tester.pumpAndSettle();

      // A loaded-and-empty board must not render placeholder cards: that reads
      // as "still loading" and claims chefs the panel's empty state denies.
      expect(find.byType(SpotlightCardPlaceholder), findsNothing);
      expect(find.byType(ChefSpotlightCard), findsNothing);
      expect(find.text('No chefs yet'), findsOneWidget);
      // UX-045: all three shelves keep their heading, each with its reason.
      expect(find.byType(CardRail), findsNWidgets(3));
      expect(find.text('Popular chefs'), findsOneWidget);
      expect(find.text(ChefsRails.popularEmptyReason), findsOneWidget);
      expect(
        find.text(ChefsRails.windowEmptyReason(ChefsWindow.week)),
        findsOneWidget,
      );
      expect(
        find.text(ChefsRails.windowEmptyReason(ChefsWindow.month)),
        findsOneWidget,
      );
    });

    testWidgets('a spotlight card carries the score and its top driver', (
      tester,
    ) async {
      _size(tester, 1440);
      await tester.pumpWidget(_app(const [_kitchen]));
      await tester.pumpAndSettle();

      expect(find.text('Driven by likes'), findsOneWidget);
      expect(find.text('1,980 likes × 3'), findsOneWidget);
      expect(find.text('RANK 2'), findsOneWidget);
      expect(find.text('002 / 148'), findsOneWidget);
      expect(find.text('14 recipes'), findsWidgets);
      expect(find.text('HEAD → MASTER'), findsOneWidget);
      expect(find.text('9,811 to go'), findsOneWidget);
    });

    testWidgets("a spotlight card opens that chef's page", (tester) async {
      _size(tester, 1440);
      await tester.pumpWidget(_app(const [_kitchen]));
      await tester.pumpAndSettle();

      expect(find.text('CHEF PAGE ssk'), findsNothing);
      await tester.tap(find.byType(ChefSpotlightCard).first);
      await tester.pumpAndSettle();

      expect(find.text('CHEF PAGE ssk'), findsOneWidget);
    });
  });

  // Phase 22's carry-over: the board was one `limit: 25 × n` read that
  // `Show all` widened. It is a real `limit`/`offset` pager now.
  group('paging', () {
    testWidgets('Load more asks for the next offset, not a wider page', (
      tester,
    ) async {
      _size(tester, 1440);
      await tester.pumpWidget(_app(_many(30)));
      await tester.pumpAndSettle();

      expect(find.text('TOP 25 / 148'), findsOneWidget);
      expect(find.textContaining('Show all'), findsNothing);

      await tester.tap(find.text('Load more'));
      await tester.pumpAndSettle();

      final pages = _lastRepo!.boardCalls('leaderboard').toList();
      expect(pages.map((c) => (c.limit, c.offset)), [
        (kLeaderboardPageSize, 0),
        (kLeaderboardPageSize, kLeaderboardPageSize),
      ]);
      expect(find.text('TOP 30 / 148'), findsOneWidget);
      // A short page means the end.
      expect(find.text('Load more'), findsNothing);
    });

    testWidgets('a re-sort starts again at offset 0', (tester) async {
      // Gotcha 24 one level in: carrying an offset across a re-sort pages one
      // ordering's window against another ordering's rows.
      _size(tester, 1440);
      await tester.pumpWidget(_app(_many(30)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Load more'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('New'));
      await tester.pumpAndSettle();

      expect(_lastRepo!.boardCalls('newest').single.offset, 0);
      expect(find.text('NEWEST 25 / 148'), findsOneWidget);
    });
  });

  group('Momentum', () {
    testWidgets('ranks by the window and says so on every row', (tester) async {
      _size(tester, 1440);
      await tester.pumpWidget(_app(_board, windowed: _window));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Momentum'));
      await tester.pumpAndSettle();

      final call = _lastRepo!.boardCalls('windowed').single;
      expect(call.days, 30);
      // The hero's pill followed the tab: Momentum over All time is meaningless.
      expect(
        _container(tester).read(boardViewProvider).window,
        ChefsWindow.month,
      );

      // Chen moved most: 40 × 3 + 12 × 5 + 60 × 0.2 = 192.
      expect(find.text('+192'), findsOneWidget);
      expect(find.text('+6'), findsOneWidget); // Amara, 2 likes
      expect(find.text('last 30 days'), findsNWidgets(2));
      expect(find.text('Points earned in the last 30 days.'), findsOneWidget);
      // Momentum has no denominator — it lists movers, not the population.
      expect(find.text('TOP 2'), findsOneWidget);
    });

    testWidgets('lists only chefs who moved', (tester) async {
      // Greta's window is all zeros. The RPC returns her (last), and listing
      // her would be the all-time board wearing the Momentum tab's name.
      _size(tester, 1440);
      await tester.pumpWidget(_app(_board, windowed: _window));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Momentum'));
      await tester.pumpAndSettle();

      final names =
          tester
              .widgetList<ChefStandingCard>(find.byType(ChefStandingCard))
              .map((c) => c.standing.displayName)
              .toList();
      expect(names, ['Chen Wei', 'Amara Okonkwo']);
    });

    testWidgets('the hero window drives the board', (tester) async {
      _size(tester, 1440);
      await tester.pumpWidget(_app(_board, windowed: _window));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Week'));
      await tester.pumpAndSettle();
      expect(
        _container(tester).read(boardViewProvider).sort,
        BoardSort.momentum,
      );
      expect(_lastRepo!.boardCalls('windowed').last.days, 7);
      expect(find.text('last 7 days'), findsWidgets);

      await tester.tap(find.text('All time'));
      await tester.pumpAndSettle();
      expect(_container(tester).read(boardViewProvider), const BoardView());
      expect(find.text('TOP 3 / 148'), findsOneWidget);
    });

    testWidgets('pins page 1 window_start and sends it on page 2', (
      tester,
    ) async {
      // The second half of Gotcha 24: a window measured from `now()` moves
      // between two requests, so `offset` lies even over a total order unless
      // every page sends the same boundary.
      final movers = [
        for (final (i, s) in _many(30).indexed)
          _moved(s, rank: i + 1, likes: 100 - i),
      ];
      _size(tester, 1440);
      await tester.pumpWidget(_app(_many(30), windowed: movers));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Week'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Load more'));
      await tester.pumpAndSettle();

      final pages = _lastRepo!.boardCalls('windowed').toList();
      expect(pages.map((c) => c.offset), [0, kLeaderboardPageSize]);
      // Page 1 lets the server pick the boundary (its clock, the same one the
      // rails use); page 2 echoes it back rather than trusting the device.
      expect(pages.first.since, isNull);
      expect(pages.last.since, movers.first.window.windowStart);
      expect(find.text('TOP 30'), findsOneWidget);
    });

    testWidgets('re-tapping the selected tab keeps the loaded pages', (
      tester,
    ) async {
      _size(tester, 1440);
      await tester.pumpWidget(_app(_many(30)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Load more'));
      await tester.pumpAndSettle();
      final before = _lastRepo!.boardCalls('leaderboard').length;

      await tester.tap(find.text('Score'));
      await tester.pumpAndSettle();

      expect(_lastRepo!.boardCalls('leaderboard').length, before);
      expect(find.text('TOP 30 / 148'), findsOneWidget);
    });

    testWidgets('stops paging at the first quiet chef', (tester) async {
      // A full page whose last row is quiet means every row behind it is quiet
      // too (the RPC orders by window score first), so there is no next page
      // worth asking for.
      final page = [
        for (final (i, s) in _many(25).indexed)
          _moved(s, rank: i + 1, likes: i < 20 ? 50 - i : 0),
      ];
      _size(tester, 1440);
      await tester.pumpWidget(_app(_many(25), windowed: page));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Momentum'));
      await tester.pumpAndSettle();

      expect(find.text('TOP 20'), findsOneWidget);
      expect(find.text('Load more'), findsNothing);
    });

    // The Phase 33 empty state. A simulated database whose `sim.epoch_end()`
    // anchor has gone stale returns every chef with a zero window — correctly.
    // That is old data, and it must read as a statement, never a spinner.
    testWidgets('a window where nobody moved is a real empty state', (
      tester,
    ) async {
      final quiet = [for (final s in _board) _moved(s, rank: 1)];
      _size(tester, 1440);
      await tester.pumpWidget(_app(_board, windowed: quiet));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Week'));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(EmptyView),
          matching: find.text('Nothing moved in the last 7 days'),
        ),
        findsOneWidget,
      );
      expect(find.byType(LoadingView), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(ChefStandingCard), findsNothing);

      await tester.tap(find.text('Show all-time scores'));
      await tester.pumpAndSettle();
      expect(_container(tester).read(boardViewProvider), const BoardView());
      expect(find.byType(ChefStandingCard), findsNWidgets(3));
    });

    testWidgets('the phone board has the same empty state', (tester) async {
      final quiet = [for (final s in _board) _moved(s, rank: 1)];
      _size(tester, 400);
      await tester.pumpWidget(_app(_board, windowed: quiet));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Momentum'));
      await tester.pumpAndSettle();

      expect(find.text('Nothing moved in the last 30 days'), findsOneWidget);
      // The tabs that lead back out of it are still on screen.
      expect(find.text('Score'), findsOneWidget);
    });
  });

  group('New', () {
    testWidgets('orders by join date and says when each chef joined', (
      tester,
    ) async {
      _size(tester, 1440);
      await tester.pumpWidget(_app(_board));
      await tester.pumpAndSettle();

      await tester.tap(find.text('New'));
      await tester.pumpAndSettle();

      final names =
          tester
              .widgetList<ChefStandingCard>(find.byType(ChefStandingCard))
              .map((c) => c.standing.displayName)
              .toList();
      expect(names, ['Chen Wei', 'Greta Lindqvist', 'Amara Okonkwo']);
      expect(find.text('joined Sep 2026'), findsOneWidget);
      // The rank pill is still the all-time rank, which the footer says.
      expect(find.text('Newest first. Ranks are all-time.'), findsOneWidget);
      expect(find.text('NEWEST 3 / 148'), findsOneWidget);
    });
  });

  group('the windowed rails', () {
    testWidgets('show the movers with what they earned', (tester) async {
      _size(tester, 1440, 2200);
      await tester.pumpWidget(_app(_board, windowed: _window));
      await tester.pumpAndSettle();

      final rails =
          _lastRepo!.calls.where((c) => c.limit == kChefRailLength).toList();
      expect(
        rails.where((c) => c.rpc == 'windowed').map((c) => c.days),
        unorderedEquals([7, 30]),
      );
      // Two movers on each windowed rail (Greta is quiet), plus the three
      // Popular cards.
      expect(find.byType(ChefSpotlightCard), findsNWidgets(3 + 2 + 2));
      expect(find.text('+192 · last 7 days'), findsOneWidget);
      expect(find.text('+192 · last 30 days'), findsOneWidget);
      expect(
        find.text(ChefsRails.windowEmptyReason(ChefsWindow.week)),
        findsNothing,
      );
      expect(find.byType(SpotlightCardPlaceholder), findsNothing);
    });

    testWidgets('a quiet window says why, not placeholders', (tester) async {
      _size(tester, 1440, 2200);
      await tester.pumpWidget(_app(_board));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'No chef earned a like, save or view in the last 7 days yet.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'No chef earned a like, save or view in the last 30 days yet.',
        ),
        findsOneWidget,
      );
      expect(find.byType(SpotlightCardPlaceholder), findsNothing);
    });

    // UX-045: the quiet shelf used to be a spotlight-card-sized bordered tile
    // with its sentence centred in it — in the fixed-height column the
    // sentence sat below the fold, and what showed was an empty frame.
    testWidgets('an empty shelf is a heading and a sentence, not a box', (
      tester,
    ) async {
      _size(tester, 1440, 1000);
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_app(const [_kitchen]));
      await tester.pumpAndSettle();

      final reason = find.text(ChefsRails.windowEmptyReason(ChefsWindow.week));
      expect(reason, findsOneWidget);
      // The heading is still a heading.
      expect(
        _a11y(tester, find.text('Trending chefs')).flagsCollection.isHeader,
        isTrue,
      );
      // No frame around the sentence.
      final framed = find.ancestor(
        of: reason,
        matching: find.byWidgetPredicate(
          (w) =>
              w is DecoratedBox &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).border != null,
        ),
      );
      expect(framed, findsNothing);
      // And on screen in a 1000px window, right under its heading — not a
      // card's height below it.
      final heading = tester.getRect(find.text('Trending chefs'));
      final sentence = tester.getRect(reason);
      expect(sentence.bottom, lessThanOrEqualTo(1000));
      expect(sentence.top - heading.bottom, lessThan(80));
      handle.dispose();
    });

    // UX-045's other half. The rails column is not capped — it takes every
    // pixel beside the 404px board panel — so a mostly-blank 1440 page was a
    // one-chef shelf, not a layout that stopped short. A short shelf now says
    // so in the space a next card would take.
    testWidgets('the rails take the full width beside the board panel', (
      tester,
    ) async {
      _size(tester, 1440, 1000);
      await tester.pumpWidget(_app(const [_kitchen]));
      await tester.pumpAndSettle();

      final panel = tester.getRect(find.text('Leaderboard'));
      final rails = tester.getRect(find.byType(ChefsRails));
      // Page padding is 32 each side on the wide layout.
      expect(rails.right, 1440 - 32);
      expect(rails.left, greaterThan(panel.right));
      expect(
        rails.width,
        1440 - 2 * 32 - ChefsScreen.panelWidth - AppSpacing.lg,
      );
    });

    testWidgets('a one-chef shelf says that is everyone', (tester) async {
      _size(tester, 1440, 1000);
      await tester.pumpWidget(
        _app(const [_kitchen], windowed: [_moved(_kitchen, rank: 1, likes: 3)]),
      );
      await tester.pumpAndSettle();

      final note = find.text(ChefsRails.popularEndNote);
      expect(note, findsOneWidget);
      // Beside the card, in the row's otherwise blank space.
      final card = tester.getRect(find.byType(ChefSpotlightCard).first);
      expect(tester.getRect(note).left, greaterThan(card.right));
      expect(tester.getRect(note).top, lessThan(card.bottom));
      // No arrows and no `1–2 / 2` label: the note is never counted as a chef.
      expect(find.byTooltip('Next'), findsNothing);
      expect(
        find.text(ChefsRails.windowEndNote(ChefsWindow.week)),
        findsOneWidget,
      );
    });

    testWidgets('a full shelf carries no end note', (tester) async {
      _size(tester, 1440, 1000);
      await tester.pumpWidget(_app(_many(10)));
      await tester.pumpAndSettle();

      expect(find.text(ChefsRails.popularEndNote), findsNothing);
      // The pager still counts chefs only.
      expect(find.text('1–3 / 10'), findsOneWidget);
    });
  });

  // Phase 30 replaced the expanded dialog with `/chef/:id`.
  group('opening a chef', () {
    testWidgets('a board row navigates to that chef', (tester) async {
      _size(tester, 1200, 900);

      await tester.pumpWidget(_app(const [_kitchen]));
      await tester.pumpAndSettle();

      expect(find.text('CHEF PAGE ssk'), findsNothing);
      // The name is on the panel row and again on the rail card; the panel row
      // comes first in the tree.
      await tester.tap(find.text('Secret Sauce Kitchen').first);
      await tester.pumpAndSettle();

      expect(find.text('CHEF PAGE ssk'), findsOneWidget);
    });

    testWidgets('a Momentum row navigates too', (tester) async {
      _size(tester, 1440);
      await tester.pumpWidget(_app(_board, windowed: _window));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Momentum'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Chen Wei').first);
      await tester.pumpAndSettle();
      expect(find.text('CHEF PAGE d3'), findsOneWidget);
    });

    testWidgets('a phone board navigates too — no sheet, no dialog', (
      tester,
    ) async {
      _size(tester, 400, 900);

      await tester.pumpWidget(_app(const [_kitchen]));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Secret Sauce Kitchen'));
      await tester.pumpAndSettle();

      expect(find.text('CHEF PAGE ssk'), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets('the tapped row decides the chef, not the first one', (
      tester,
    ) async {
      _size(tester, 400, 900);

      await tester.pumpWidget(_app(_board));
      await tester.pumpAndSettle();

      // Third row — a tied-rank chef, so an implementation keying off rank
      // rather than id would land on the wrong one.
      await tester.tap(find.text('Greta Lindqvist'));
      await tester.pumpAndSettle();

      expect(find.text('CHEF PAGE d7'), findsOneWidget);
    });
  });

  // Worst realistic envelope for a leaderboard row: the narrowest phone, 2.0x
  // accessibility scaling, the longest tier label, a long display name, and
  // six-figure counts.
  final stress = ChefStanding(
    chefRank: 1,
    id: 'x',
    displayName: 'Bartholomew Featherstonehaugh-Wentworth',
    chefTier: ChefTier.masterChef,
    chefScore: 987654.5,
    publicRecipeCount: 128,
    totalLikes: 240000,
    totalSaves: 180000,
    totalViews: 990000,
    createdAt: DateTime.utc(2026, 9, 1),
  );
  final stressWindow = [
    ChefWindowStanding(
      standing: stress.copyWith(chefRank: 1),
      window: ChefWindowStats(
        id: 'x',
        windowStart: DateTime.utc(2026, 8, 25),
        likes: 240000,
        saves: 180000,
        viewers: 990000,
        ratings: 1200,
        newRecipes: 128,
        score: 1818000,
      ),
    ),
  ];

  // 320/360/390 are the phone board; 600 is the stacked page and 1000/1440 the
  // two-column one, so this sweeps all three layouts — and, with the windowed
  // rows, the Momentum and New variants of every row and card — at both ends
  // of the text-scale envelope.
  for (final sort in BoardSort.values) {
    for (final width in <double>[320, 360, 390, 600, 1000, 1440]) {
      for (final scale in <double>[1.0, 2.0]) {
        // Two heights: 1200 is the real window the two-column layout has to
        // fit (Gotcha 22); 4000 builds everything a lazy list would otherwise
        // leave unbuilt below the fold — at 600px the panel sits under three
        // rails, and a test that never builds a row cannot see it overflow.
        for (final height in <double>[1200, 4000]) {
          testWidgets('the chefs page fits at ${width}x${height.toInt()}, '
              'textScale $scale, ${sort.label}', (tester) async {
            _size(tester, width, height);

            await tester.pumpWidget(
              _app([stress], textScale: scale, windowed: stressWindow),
            );
            await tester.pumpAndSettle();
            _container(
              tester,
            ).read(boardViewProvider.notifier).selectSort(sort);
            await tester.pumpAndSettle();

            // The tall run must actually have built a row to prove anything.
            if (height > 1200) {
              expect(find.byType(ChefStandingCard), findsWidgets);
            }
            expect(
              tester.takeException(),
              isNull,
              reason: 'overflow at ${width}px @ ${scale}x on ${sort.label}',
            );
          });
        }
      }
    }
  }

  // Gotcha 18's envelope for a pill of labels: 600px at 2.0x. The board pill
  // sits in the stacked page's panel there; ellipsis is allowed, overflow and
  // lost segments are not.
  testWidgets('the ordering pill keeps three segments at 600px, 2.0x', (
    tester,
  ) async {
    // Tall: at 600px the panel sits below the rails in one lazy scroll.
    _size(tester, 600, 4000);
    await tester.pumpWidget(_app(_board, textScale: 2.0));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    for (final label in ['Score', 'Momentum', 'New']) {
      expect(find.text(label), findsOneWidget);
    }
  });

  // The empty Momentum state is a new region with a title that grows with the
  // span; at 1440 x 1.0 it sits in the 404px panel.
  for (final width in <double>[320, 390, 600, 1000, 1440]) {
    for (final scale in <double>[1.0, 2.0]) {
      testWidgets('an empty Momentum week fits at ${width}px, ${scale}x', (
        tester,
      ) async {
        _size(tester, width, 4000);
        await tester.pumpWidget(
          _app(
            _board,
            textScale: scale,
            windowed: [for (final s in _board) _moved(s, rank: 1)],
          ),
        );
        await tester.pumpAndSettle();
        _container(
          tester,
        ).read(boardViewProvider.notifier).selectWindow(ChefsWindow.week);
        await tester.pumpAndSettle();

        expect(find.text('Show all-time scores'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  // UX-045's two new states — every shelf empty, and short shelves with their
  // end note — across the page's envelope. 1200 is the window the two-column
  // layout must fit (Gotcha 22); 4000 builds everything below the fold.
  for (final width in <double>[390, 1000, 1440]) {
    for (final scale in <double>[1.0, 2.0]) {
      for (final (label, board, moved) in [
        ('empty shelves', <ChefStanding>[], <ChefWindowStanding>[]),
        (
          'short shelves',
          const [_kitchen],
          [_moved(_kitchen, rank: 1, likes: 3)],
        ),
      ]) {
        for (final height in <double>[1200, 4000]) {
          testWidgets('$label fit at ${width}x${height.toInt()}, ${scale}x', (
            tester,
          ) async {
            _size(tester, width, height);
            await tester.pumpWidget(
              _app(board, textScale: scale, windowed: moved),
            );
            await tester.pumpAndSettle();

            expect(
              tester.takeException(),
              isNull,
              reason: '$label at ${width}px @ ${scale}x',
            );
          });
        }
      }
    }
  }

  // Phase 37 wave C (UX-014): the page's two headings on the web layout.
  testWidgets('the hero title and the board panel are headings', (
    tester,
  ) async {
    _size(tester, 1440, 1200);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_app(_board));
    await tester.pumpAndSettle();

    final title = find.descendant(
      of: find.byType(ChefsHero),
      matching: find.text('Chefs'),
    );
    expect(_a11y(tester, title).flagsCollection.isHeader, isTrue);
    expect(
      _a11y(tester, find.text('Leaderboard')).flagsCollection.isHeader,
      isTrue,
    );
    // The board rows under it are not.
    expect(
      _a11y(tester, find.text('Ties share a rank.')).flagsCollection.isHeader,
      isFalse,
    );
    handle.dispose();
  });

  testWidgets('the board pill says which ordering is selected', (tester) async {
    _size(tester, 1440, 1200);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_app(_board));
    await tester.pumpAndSettle();

    Tristate selected(String label) =>
        _a11y(tester, find.bySemanticsLabel(label)).flagsCollection.isSelected;
    expect(selected(BoardSort.score.label), Tristate.isTrue);
    expect(selected(BoardSort.newest.label), Tristate.isFalse);
    handle.dispose();
  });

  // UX-048: every control on the page is at least 48 × 48 (WCAG 2.5.8 via
  // Flutter's Android guideline, the stricter of the two it ships) — the
  // phone board, and both web layouts, where the hero's window filter is a
  // row of `SegmentedTabs` segments.
  for (final width in [390.0, 1000.0, 1440.0]) {
    testWidgets('every tap target meets the 48dp guideline at ${width}px', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      _size(tester, width, 2200);
      await tester.pumpWidget(_app(_board, windowed: _window));
      await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      handle.dispose();
    });
  }
}
