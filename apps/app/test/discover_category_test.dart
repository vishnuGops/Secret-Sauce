// Phase 36c (the owner's Q6) — Discover's category tiles filter the browse
// grid, and the selection is URL state (`/discover?category=mains`).
//
// Driven through the REAL `appRouterProvider`, not a test router, because half
// the contract is the route builder parsing the slug: a test router that
// restated that line would pass while the real one ignored the parameter.
// Every grid assertion ties the rows to the repository call behind them — a
// grid of cards looks the same whichever query produced it.
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:app/features/discover/discover_categories.dart';
import 'package:app/features/discover/discover_screen.dart';
import 'package:app/routing/app_router.dart';

Recipe _recipe(String id, String title, [String? category]) => Recipe(
  id: id,
  ownerId: 'u1',
  title: title,
  prepMinutes: 10,
  category: category,
);

class _FakeAuth implements AuthRepository {
  @override
  String? get currentUserId => null;

  @override
  Future<String?> currentProfileId() async => null;

  @override
  Stream<AuthState> authStateChanges() => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}

/// Records every call. `byCategories` answers with one card named after the
/// group's first raw value, or nothing when [emptyCategories] is set.
class _FakeDiscover implements DiscoverRepository {
  _FakeDiscover({this.emptyCategories = false});

  final bool emptyCategories;
  final List<String> calls = [];

  @override
  Future<List<Recipe>> byCategories(
    List<String> categories, {
    int limit = kRecipePageSize,
    int offset = 0,
  }) async {
    calls.add('byCategories:${categories.join('|')}');
    if (emptyCategories) return const [];
    return [_recipe('c1', '${categories.first} pick', categories.first)];
  }

  @override
  Future<List<Recipe>> popular({
    int limit = kRecipePageSize,
    int offset = 0,
  }) async {
    calls.add('popular');
    return [_recipe('p1', 'Popular pick')];
  }

  @override
  Future<List<Recipe>> trending({
    int limit = kRecipePageSize,
    int offset = 0,
  }) async => const [];

  @override
  Future<List<Recipe>> recent({
    int limit = kRecipePageSize,
    int offset = 0,
  }) async => const [];

  @override
  Future<List<Recipe>> search(
    String query, {
    int limit = kRecipePageSize,
    int offset = 0,
  }) async {
    calls.add('search:$query');
    return [_recipe('s1', 'Search hit')];
  }

  @override
  Future<List<Recipe>> quick({
    int limit = kRecipePageSize,
    int offset = 0,
  }) async => [_recipe('q1', 'Aglio e olio')];

  @override
  Future<List<Recipe>> projects({
    int limit = kRecipePageSize,
    int offset = 0,
  }) async => const [];

  @override
  Future<List<Recipe>> mostForked({
    int limit = kRecipePageSize,
    int offset = 0,
  }) async => [
    _recipe('f1', 'The house sauce'),
    _recipe('f2', 'The second sauce'),
  ];

  @override
  Future<List<Recipe>> corpus({
    int limit = kRecipePageSize,
    int offset = 0,
    String? cuisine,
  }) async => const [];

  @override
  Future<int> corpusCount() async => 0;

  @override
  Future<int> publicCount() async => 14;
}

Future<GoRouter> _pumpAt(
  WidgetTester tester,
  String location,
  _FakeDiscover repo, {
  double width = 1400,
  double height = 4000,
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(_FakeAuth()),
      discoverRepositoryProvider.overrideWithValue(repo),
    ],
  );
  addTearDown(container.dispose);

  final router = container.read(appRouterProvider);
  router.go(location);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: AppTheme.light(),
        routerConfig: router,
        builder:
            (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

Uri _uri(GoRouter router) => router.routerDelegate.currentConfiguration.uri;

Finder _tile(DiscoverCategory c) =>
    find.byKey(DiscoverCategoryTiles.tileKey(c));

void main() {
  testWidgets('six tiles, headed BROWSE BY CATEGORY, none selected', (
    tester,
  ) async {
    final repo = _FakeDiscover();
    await _pumpAt(tester, Routes.discover, repo);

    expect(find.text('BROWSE BY CATEGORY'), findsOneWidget);
    for (final c in DiscoverCategory.values) {
      expect(_tile(c), findsOneWidget);
      expect(tester.widget<CategoryTile>(_tile(c)).selected, isFalse);
    }
    // Unfiltered: the sorted grid, the sort links, no clear chip.
    expect(find.text('EVERYTHING ELSE'), findsOneWidget);
    expect(find.text('Popular pick'), findsOneWidget);
    expect(find.byKey(kDiscoverClearCategoryKey), findsNothing);
    expect(repo.calls.where((c) => c.startsWith('byCategories')), isEmpty);
  });

  testWidgets('a tile routes to ?category= and filters the grid by its group', (
    tester,
  ) async {
    final repo = _FakeDiscover();
    final router = await _pumpAt(tester, Routes.discover, repo);

    await tester.tap(_tile(DiscoverCategory.mains));
    await tester.pumpAndSettle();

    expect(_uri(router).path, Routes.discover);
    expect(_uri(router).queryParameters['category'], 'mains');
    // The whole group, as one request — a tile is not one raw value.
    expect(
      repo.calls,
      contains('byCategories:Main|Main Course|Mains|Dinner|Lunch|Entree'),
    );
    expect(find.text('Main pick'), findsOneWidget);
    expect(find.text('Popular pick'), findsNothing);

    // The heading names the tile, the sort links give way to the clear chip,
    // and the shelves stay above.
    expect(find.text('MAINS'), findsOneWidget);
    expect(find.text('EVERYTHING ELSE'), findsNothing);
    expect(find.text('Top rated'), findsNothing);
    expect(find.byKey(kDiscoverClearCategoryKey), findsOneWidget);
    expect(find.text('UNDER 30'), findsOneWidget);
    expect(
      tester.widget<CategoryTile>(_tile(DiscoverCategory.mains)).selected,
      isTrue,
    );
  });

  // 36c review: on a phone the tiles sit a screen above the grid they
  // filter, so a tap scrolls the browse header into view — without it a tap
  // changes nothing the reader can see.
  testWidgets('a tile tap scrolls the filtered grid into view (390×800)', (
    tester,
  ) async {
    final repo = _FakeDiscover();
    await _pumpAt(tester, Routes.discover, repo, width: 390, height: 800);

    final position =
        tester.state<ScrollableState>(find.byType(Scrollable).first).position;
    expect(position.pixels, 0);
    expect(find.text('MAINS'), findsNothing);

    await tester.tap(_tile(DiscoverCategory.mains));
    await tester.pumpAndSettle();

    expect(position.pixels, greaterThan(0));
    final heading = tester.getRect(find.text('MAINS'));
    expect(heading.top, greaterThanOrEqualTo(0));
    expect(heading.bottom, lessThanOrEqualTo(800));
  });

  testWidgets('the clear chip goes back to /discover, unfiltered', (
    tester,
  ) async {
    final repo = _FakeDiscover();
    final router = await _pumpAt(
      tester,
      Routes.discoverCategory('mains'),
      repo,
    );

    await tester.tap(find.byKey(kDiscoverClearCategoryKey));
    await tester.pumpAndSettle();

    expect(_uri(router).queryParameters, isEmpty);
    expect(find.text('EVERYTHING ELSE'), findsOneWidget);
    expect(find.text('Popular pick'), findsOneWidget);
    expect(find.text('Main pick'), findsNothing);
  });

  testWidgets('pressing the selected tile again clears it', (tester) async {
    final repo = _FakeDiscover();
    final router = await _pumpAt(
      tester,
      Routes.discoverCategory('salads'),
      repo,
    );

    await tester.ensureVisible(_tile(DiscoverCategory.salads));
    await tester.tap(_tile(DiscoverCategory.salads));
    await tester.pumpAndSettle();

    expect(_uri(router).queryParameters, isEmpty);
    expect(find.text('EVERYTHING ELSE'), findsOneWidget);
  });

  testWidgets('moving from one tile to another re-filters, no clear between', (
    tester,
  ) async {
    // The override in the screen's own ProviderScope changes value under a
    // grid that is already watching — the case a fresh build does not cover.
    final repo = _FakeDiscover();
    final router = await _pumpAt(
      tester,
      Routes.discoverCategory('mains'),
      repo,
    );
    expect(find.text('Main pick'), findsOneWidget);

    await tester.ensureVisible(_tile(DiscoverCategory.desserts));
    await tester.tap(_tile(DiscoverCategory.desserts));
    await tester.pumpAndSettle();

    expect(_uri(router).queryParameters['category'], 'desserts');
    expect(repo.calls.last, 'byCategories:Dessert|Desserts|Baking|Sweet');
    expect(find.text('Dessert pick'), findsOneWidget);
    expect(find.text('Main pick'), findsNothing);
    expect(find.text('DESSERTS'), findsOneWidget);
  });

  testWidgets('a deep link opens filtered', (tester) async {
    final repo = _FakeDiscover();
    await _pumpAt(tester, '/discover?category=desserts', repo);

    expect(repo.calls, contains('byCategories:Dessert|Desserts|Baking|Sweet'));
    expect(find.text('DESSERTS'), findsOneWidget);
    expect(find.text('Dessert pick'), findsOneWidget);
    expect(repo.calls, isNot(contains('popular')));
  });

  testWidgets('an unknown slug is ignored — Discover opens unfiltered', (
    tester,
  ) async {
    final repo = _FakeDiscover();
    await _pumpAt(tester, '/discover?category=pudding', repo);

    expect(find.byType(DiscoverScreen), findsOneWidget);
    expect(find.text('EVERYTHING ELSE'), findsOneWidget);
    expect(find.text('Popular pick'), findsOneWidget);
    expect(repo.calls.where((c) => c.startsWith('byCategories')), isEmpty);
  });

  testWidgets('an empty category explains itself and offers the way back', (
    tester,
  ) async {
    final repo = _FakeDiscover(emptyCategories: true);
    final router = await _pumpAt(
      tester,
      Routes.discoverCategory('drinks'),
      repo,
    );

    expect(find.text('No public drinks yet'), findsOneWidget);
    await tester.tap(find.text('Show everything'));
    await tester.pumpAndSettle();
    expect(_uri(router).queryParameters, isEmpty);
  });

  testWidgets('search still wins over a selected category', (tester) async {
    final repo = _FakeDiscover();
    await _pumpAt(tester, Routes.discoverCategory('mains'), repo);

    await tester.enterText(find.byType(SearchBar), 'sauce');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    expect(find.text('Search hit'), findsOneWidget);
    expect(find.text('Main pick'), findsNothing);
    expect(find.text('BROWSE BY CATEGORY'), findsNothing);
  });

  testWidgets('03 MOST FORKED wears rank ribbons; the other shelves do not', (
    tester,
  ) async {
    await _pumpAt(tester, Routes.discover, _FakeDiscover());

    expect(find.text('1st'), findsOneWidget);
    expect(find.text('2nd'), findsOneWidget);
    // Shelf 01 has a card too, and it is not ranked.
    final quick = tester.widget<RecipeCard>(
      find.ancestor(
        of: find.text('Aglio e olio'),
        matching: find.byType(RecipeCard),
      ),
    );
    expect(quick.rank, isNull);
  });

  // Six across or three by two on a wide window — never a ragged 4 + 2 — and
  // one sideways-scrolling row on a phone.
  Set<double> rowsOf(WidgetTester tester) => {
    for (final c in DiscoverCategory.values)
      if (_tile(c).evaluate().isNotEmpty) tester.getTopLeft(_tile(c)).dy,
  };

  testWidgets('1440px: the six tiles share one row', (tester) async {
    await _pumpAt(tester, Routes.discover, _FakeDiscover(), width: 1440);
    expect(rowsOf(tester), hasLength(1));
  });

  testWidgets('1000px at 2.0x: three by two', (tester) async {
    await _pumpAt(
      tester,
      Routes.discover,
      _FakeDiscover(),
      width: 1000,
      textScale: 2.0,
    );
    expect(rowsOf(tester), hasLength(2));
  });

  testWidgets('390px: one row that scrolls sideways', (tester) async {
    await _pumpAt(tester, Routes.discover, _FakeDiscover(), width: 390);
    expect(rowsOf(tester), hasLength(1));
    expect(
      find.ancestor(
        of: _tile(DiscoverCategory.mains),
        matching: find.byWidgetPredicate(
          (w) => w is ListView && w.scrollDirection == Axis.horizontal,
        ),
      ),
      findsOneWidget,
    );
  });

  // The tile row's envelope (Gotchas 13, 22, 26): the widths the app renders
  // at × the contract scales, compact (a scrolling row) and wide (full rows).
  for (final width in [390.0, 600.0, 1000.0, 1440.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('the tiles hold at ${width}px × $scale', (tester) async {
        await _pumpAt(
          tester,
          Routes.discoverCategory('mains'),
          _FakeDiscover(),
          width: width,
          textScale: scale,
        );

        expect(
          tester.takeException(),
          isNull,
          reason: 'overflow at ${width}px / ${scale}x',
        );
        // Not vacuous: the section rendered, and the selected tile with it.
        expect(find.text('BROWSE BY CATEGORY'), findsOneWidget);
        // The first tile — on a phone the row scrolls, so a later one may be
        // (correctly) not built yet.
        expect(_tile(DiscoverCategory.mains), findsOneWidget);
        expect(find.text('Mains'), findsWidgets);
      });
    }
  }
}
