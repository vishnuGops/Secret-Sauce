// Phase 26 — Discover's shelves.
//
// Overrides `discoverRepositoryProvider` (core) rather than the screen's own
// providers, so the wiring in discover_providers.dart is exercised instead of
// being stubbed out — the same argument as chefs_screen_test.dart.
//
// The thing these tests are really guarding is that each shelf reaches its own
// query. Three rows of recipe cards look right whichever repository call
// produced them, so "01 renders" proves nothing on its own: every assertion
// below ties a shelf to the call behind it.
import 'dart:async';

import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:go_router/go_router.dart';

import 'package:app/features/discover/discover_masthead.dart';
import 'package:app/features/discover/discover_providers.dart';
import 'package:app/features/discover/discover_screen.dart';
import 'package:app/routing/app_router.dart';

Recipe _recipe(String id, String title) =>
    Recipe(id: id, ownerId: 'u1', title: title, prepMinutes: 10);

/// Answers each shelf with one recognisable card, and records every call so a
/// test can prove which query a row came from.
class _FakeDiscover implements DiscoverRepository {
  // Phase 35c: the corpus surface. Empty in every fixture here — these tests are
  // about Discover and the ranked shelves, which exclude imported content by
  // construction.
  @override
  Future<List<Recipe>> corpus({
    int limit = kRecipePageSize,
    int offset = 0,
    String? cuisine,
  }) async => const [];

  @override
  Future<int> corpusCount() async => 0;

  _FakeDiscover({
    this.quickRows = const [],
    this.projectRows = const [],
    this.forkedRows = const [],
    this.hangingShelf,
    this.failingShelf,
  });

  final List<Recipe> quickRows;
  final List<Recipe> projectRows;
  final List<Recipe> forkedRows;

  /// A shelf name whose call never completes, so the loading state is visible.
  final String? hangingShelf;

  /// A shelf name whose call throws.
  final String? failingShelf;

  final List<String> calls = [];

  Future<List<Recipe>> _shelf(String name, List<Recipe> rows) {
    calls.add(name);
    if (name == hangingShelf) return Completer<List<Recipe>>().future;
    if (name == failingShelf) {
      return Future.error(Exception('shelf $name is unavailable'));
    }
    return Future.value(rows);
  }

  @override
  Future<List<Recipe>> quick({int limit = kRecipePageSize, int offset = 0}) =>
      _shelf('quick', quickRows);

  @override
  Future<List<Recipe>> projects({
    int limit = kRecipePageSize,
    int offset = 0,
  }) => _shelf('projects', projectRows);

  @override
  Future<List<Recipe>> mostForked({
    int limit = kRecipePageSize,
    int offset = 0,
  }) => _shelf('mostForked', forkedRows);

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
  }) async {
    calls.add('trending');
    return [_recipe('t1', 'Trending pick')];
  }

  @override
  Future<List<Recipe>> recent({
    int limit = kRecipePageSize,
    int offset = 0,
  }) async {
    calls.add('recent');
    return [_recipe('n1', 'Newest pick')];
  }

  @override
  Future<List<Recipe>> byCategories(
    List<String> categories, {
    int limit = kRecipePageSize,
    int offset = 0,
  }) async {
    calls.add('byCategories:${categories.join('|')}');
    return [_recipe('c1', 'Category pick')];
  }

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
  Future<int> publicCount() async => 1684;
}

void _size(WidgetTester tester, double width, [double height = 2400]) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _app(_FakeDiscover repo, {double textScale = 1.0}) => ProviderScope(
  overrides: [discoverRepositoryProvider.overrideWithValue(repo)],
  child: MaterialApp(
    theme: AppTheme.light(),
    builder:
        (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
    home: const DiscoverScreen(),
  ),
);

_FakeDiscover _stocked() => _FakeDiscover(
  quickRows: [_recipe('q1', 'Aglio e olio')],
  projectRows: [_recipe('w1', 'Overnight brisket')],
  forkedRows: [_recipe('f1', 'The house sauce')],
);

/// A shelf row with its owner embedded, so the card draws a chef badge.
const _owned = Recipe(
  id: 'q1',
  ownerId: 'd1',
  title: 'Aglio e olio',
  owner: Profile(
    id: 'd1',
    displayName: 'Amara Okonkwo',
    chefTier: ChefTier.masterChef,
  ),
);

/// Discover behind a real router, with probes for the two destinations a shelf
/// card can reach. `_app` above hangs the screen off `MaterialApp.home`, which
/// is enough for everything that never navigates — `context.push` throws
/// without a router.
Widget _routedApp(_FakeDiscover repo) => ProviderScope(
  overrides: [discoverRepositoryProvider.overrideWithValue(repo)],
  child: MaterialApp.router(
    theme: AppTheme.light(),
    routerConfig: GoRouter(
      initialLocation: Routes.discover,
      routes: [
        GoRoute(
          path: Routes.discover,
          builder: (context, state) => const DiscoverScreen(),
        ),
        GoRoute(
          path: Routes.recipePattern,
          builder:
              (context, state) => Scaffold(
                body: Text('RECIPE PAGE ${state.pathParameters['id']}'),
              ),
        ),
        GoRoute(
          path: Routes.chefPattern,
          builder:
              (context, state) => Scaffold(
                body: Text('CHEF PAGE ${state.pathParameters['id']}'),
              ),
        ),
      ],
    ),
  ),
);

/// How far the UX-048 check scrolls between evaluations: two thirds of its
/// 900px viewport, so consecutive windows overlap.
const double _guidelineStep = 600;

void main() {
  testWidgets('the masthead states the corpus, not a page title', (
    tester,
  ) async {
    _size(tester, 1400);
    await tester.pumpWidget(_app(_stocked()));
    await tester.pumpAndSettle();

    expect(find.byType(DiscoverMasthead), findsOneWidget);
    expect(find.text('Discover'), findsOneWidget);
    expect(find.text('THE PASS'), findsOneWidget);
    expect(find.text('1,684 PUBLIC RECIPES'), findsOneWidget);
    // The screen's own AppBar is gone — on web it was a second bar under the
    // top nav (the Phase 21 deferred item, for this screen).
    expect(find.byType(AppBar), findsNothing);
  });

  testWidgets('the masthead is a full-bleed cream band with a pill search', (
    tester,
  ) async {
    // Reference 2 (36c). The band runs edge to edge while its content keeps
    // the page margin, and the field is a pill — asserted on the widgets
    // because neither overflows or throws when it is wrong.
    _size(tester, 1440);
    await tester.pumpWidget(_app(_stocked()));
    await tester.pumpAndSettle();

    final band = find.descendant(
      of: find.byType(DiscoverMasthead),
      matching: find.byType(ColoredBox),
    );
    expect(
      tester.widget<ColoredBox>(band.first).color,
      AppPalette.light.surfaceWarm,
    );
    expect(tester.getRect(band.first).left, 0);
    expect(tester.getRect(band.first).width, 1440);
    expect(tester.getTopLeft(find.text('THE PASS')).dx, greaterThan(24));

    final bar = tester.widget<SearchBar>(find.byType(SearchBar));
    expect(bar.shape?.resolve({}), isA<StadiumBorder>());
    expect(tester.getSize(find.byType(SearchBar)).height, greaterThan(47));
  });

  testWidgets('three numbered shelves, each fed by its own query', (
    tester,
  ) async {
    _size(tester, 1400);
    final repo = _stocked();
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();

    expect(find.text('01'), findsOneWidget);
    expect(find.text('02'), findsOneWidget);
    expect(find.text('03'), findsOneWidget);
    expect(find.text('UNDER 30'), findsOneWidget);
    expect(find.text('WEEKEND PROJECTS'), findsOneWidget);
    expect(find.text('MOST FORKED'), findsOneWidget);

    // Each shelf shows the row its own repository call returned.
    expect(find.text('Aglio e olio'), findsOneWidget);
    expect(find.text('Overnight brisket'), findsOneWidget);
    expect(find.text('The house sauce'), findsOneWidget);
    expect(repo.calls, containsAll(['quick', 'projects', 'mostForked']));

    // Each one prints the rule it ranks by — a shelf that will not say why
    // these twelve recipes is a row of pictures.
    expect(find.text('RANKED BY RATING'), findsOneWidget);
    expect(find.text('RANKED BY SAVES'), findsOneWidget);
    expect(find.text('RANKED BY FORKS'), findsOneWidget);
  });

  testWidgets('a loading shelf holds its height with placeholders', (
    tester,
  ) async {
    _size(tester, 1400);
    await tester.pumpWidget(
      _app(
        _FakeDiscover(
          quickRows: [_recipe('q1', 'Aglio e olio')],
          hangingShelf: 'mostForked',
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(RecipeCardPlaceholder), findsWidgets);
  });

  testWidgets('an empty shelf gives the reason, not placeholders', (
    tester,
  ) async {
    _size(tester, 1400);
    // The seed-only case: nothing has been forked, so shelf 03 is genuinely
    // empty and must say so rather than spin forever.
    await tester.pumpWidget(
      _app(_FakeDiscover(quickRows: [_recipe('q', 'x')])),
    );
    await tester.pumpAndSettle();

    expect(find.byType(RecipeCardPlaceholder), findsNothing);
    expect(
      find.textContaining('no public recipe has been forked'),
      findsOneWidget,
    );
    // The shelf keeps its identity even with nothing on it.
    expect(find.text('MOST FORKED'), findsOneWidget);
  });

  testWidgets('a failed shelf offers a retry and leaves the others alone', (
    tester,
  ) async {
    _size(tester, 1400);
    final repo = _FakeDiscover(
      quickRows: [_recipe('q1', 'Aglio e olio')],
      failingShelf: 'projects',
    );
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();

    expect(find.byType(ErrorView), findsOneWidget);
    expect(find.text('Aglio e olio'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(
      repo.calls.where((c) => c == 'projects').length,
      2,
      reason: 'retry must re-issue that shelf’s query, not reload the page',
    );
  });

  testWidgets('the browse sort reorders the grid under the shelves', (
    tester,
  ) async {
    _size(tester, 1400);
    final repo = _stocked();
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();

    // Top rated is the default, and it is Discover's old Popular tab.
    expect(find.text('EVERYTHING ELSE'), findsOneWidget);
    expect(find.text('Popular pick'), findsOneWidget);
    expect(repo.calls, contains('popular'));

    await tester.tap(find.text('Newest'));
    await tester.pumpAndSettle();

    expect(find.text('Newest pick'), findsOneWidget);
    expect(find.text('Popular pick'), findsNothing);
    expect(repo.calls, contains('recent'));
  });

  testWidgets('searching replaces the shelves, and clearing restores them', (
    tester,
  ) async {
    _size(tester, 1400);
    final repo = _stocked();
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(SearchBar), 'sauce');
    // Past the debounce in discover_providers.dart.
    await tester.pump(kSearchDebounce * 2);
    await tester.pumpAndSettle();

    expect(find.text('Search hit'), findsOneWidget);
    expect(find.text('UNDER 30'), findsNothing);
    expect(find.text('EVERYTHING ELSE'), findsNothing);

    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();

    expect(find.text('UNDER 30'), findsOneWidget);
    expect(find.text('Search hit'), findsNothing);
  });

  testWidgets('the archive grid starts on the page margin, not its own (B059)', (
    tester,
  ) async {
    // Found by screenshot: the grid was inset 16 while the masthead, the
    // shelves and their numerals were inset 32, so the cards under
    // EVERYTHING ELSE started half a gutter left of everything above them.
    // Nothing overflows, so no envelope test sees it — this one measures.
    _size(tester, 1400);
    await tester.pumpWidget(_app(_stocked()));
    await tester.pumpAndSettle();

    final numeral = tester.getTopLeft(find.text('01')).dx;
    // Targeted by its title, not `byType(RecipeCard).last`: the shelf cards
    // sit on the page margin too, so an index that drifted onto one of them
    // would pass this test while the bug was back.
    final card =
        tester
            .getTopLeft(
              find.ancestor(
                of: find.text('Popular pick'),
                matching: find.byType(RecipeCard),
              ),
            )
            .dx;
    expect(
      (card - numeral).abs(),
      lessThan(8),
      reason:
          'the archive card starts at $card and the shelf numeral at $numeral '
          '— the grid is not using the page margin',
    );
  });

  testWidgets('the selected sort is drawn at every width (B060)', (
    tester,
  ) async {
    // B060: the old sort links' underline was a width-less box that took
    // `constraints.biggest` when bounded (full-width links, one per line) and
    // `smallest` when not (zero-width, invisible, in the row layout). The
    // sort is the `SegmentedTabs` pill since UX-032; this keeps both halves of
    // the guard on it — each segment is the width of its own label, and the
    // selected one is the one actually filled — in both header layouts.
    final pill = find.byType(SegmentedTabs<BrowseSort>);
    Finder chip(String label) => find.ancestor(
      of: find.text(label),
      matching: find.descendant(
        of: pill,
        matching: find.byType(AnimatedContainer),
      ),
    );
    Color? fillOf(String label) =>
        (tester.widget<AnimatedContainer>(chip(label)).decoration
                as BoxDecoration?)
            ?.color;

    for (final width in [1400.0, 390.0]) {
      _size(tester, width);
      await tester.pumpWidget(_app(_stocked()));
      await tester.pumpAndSettle();

      expect(pill, findsOneWidget);
      for (final label in ['Top rated', 'Trending', 'Newest']) {
        // Measured in `flutter test`'s fixed-width font, much wider than the
        // real one; 200 is "its label", not "the row".
        final w = tester.getRect(chip(label)).width;
        expect(w, lessThan(200), reason: '$label stretched to $w at $width');
        expect(w, greaterThan(0), reason: '$label is undrawn at $width');
      }

      expect(
        fillOf('Top rated'),
        isNotNull,
        reason: 'the selected sort is not filled at ${width}px',
      );
      for (final label in ['Trending', 'Newest']) {
        expect(
          fillOf(label),
          isNull,
          reason: 'an unselected sort is filled at ${width}px',
        );
      }
    }
  });

  // UX-014: the fill and colour are all a screen reader never sees. The
  // selected sort has to say so in the semantics tree, and move with a tap.
  testWidgets('the sort links announce which one is selected', (tester) async {
    final handle = tester.ensureSemantics();
    _size(tester, 1400);
    await tester.pumpWidget(_app(_stocked()));
    await tester.pumpAndSettle();

    expect(
      tester.getSemantics(find.text('Top rated')),
      isSemantics(isButton: true, isSelected: true),
    );
    expect(
      tester.getSemantics(find.text('Newest')),
      isSemantics(isButton: true, isSelected: false),
    );

    await tester.tap(find.text('Newest'));
    await tester.pumpAndSettle();

    expect(
      tester.getSemantics(find.text('Newest')),
      isSemantics(isSelected: true),
    );
    expect(
      tester.getSemantics(find.text('Top rated')),
      isSemantics(isSelected: false),
    );
    handle.dispose();
  });

  // UX-048: every control on the page is at least 48 × 48 (WCAG 2.5.8 via
  // Flutter's Android guideline, the stricter of the two it ships). The
  // shelf rows carry no owner, so no card draws the compact chef badge — the
  // one accepted secondary target inside a larger tappable tile.
  //
  // The search pill is the other one. `SearchBar`'s whole 56px pill is an
  // `InkWell` that focuses the field, but the text field's own semantics node
  // is the 24px line inside it, and `SearchBar` exposes nothing that grows it
  // without moving the text. So the pill and the Explore link are measured
  // directly, and the guideline runs from just past the pill to the end of
  // the page — every category tile, shelf, sort and card still in front of
  // it.
  testWidgets('every tap target meets the 48dp guideline', (tester) async {
    final handle = tester.ensureSemantics();
    for (final width in [390.0, 1440.0]) {
      _size(tester, width, 900);
      await tester.pumpWidget(const SizedBox()); // a fresh scroll position
      await tester.pumpWidget(_app(_stocked()));
      await tester.pumpAndSettle();

      expect(
        tester.getSize(find.byType(SearchBar)).height,
        greaterThanOrEqualTo(kMinInteractiveDimension),
      );
      expect(
        tester.getSize(find.byKey(DiscoverMasthead.exploreLinkKey)).height,
        greaterThanOrEqualTo(kMinInteractiveDimension),
      );

      final position =
          tester.state<ScrollableState>(find.byType(Scrollable).first).position;
      // Viewport-sized steps that overlap by a third, from just past the pill
      // to the end: every control below the masthead is wholly on screen in
      // at least one of them (a node touching an edge is skipped).
      final start = tester.getRect(find.byType(SearchBar)).bottom + 1;
      for (var offset = start; ; offset += _guidelineStep) {
        position.jumpTo(offset.clamp(0, position.maxScrollExtent));
        await tester.pumpAndSettle();
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        if (offset >= position.maxScrollExtent) break;
      }
    }
    handle.dispose();
  });

  testWidgets('the page holds together from a phone to a wide window', (
    tester,
  ) async {
    // The same envelope the card and the nav bar are contracted to: 2.0x text
    // scale at the narrowest width anything renders at (Gotcha 13).
    for (final width in [320.0, 390.0, 600.0, 700.0, 1000.0, 1440.0]) {
      for (final scale in [1.0, 2.0]) {
        _size(tester, width, 3000);
        await tester.pumpWidget(_app(_stocked(), textScale: scale));
        await tester.pumpAndSettle();

        expect(
          tester.takeException(),
          isNull,
          reason: 'overflow at ${width}px / ${scale}x',
        );
        // Not a vacuous pass: a page that rendered nothing also throws
        // nothing. At 320 x 2.0 the shelf header has dropped its kicker, its
        // position label and its arrows — the numeral and the title are the
        // part that must survive every envelope.
        expect(
          find.text('01'),
          findsOneWidget,
          reason: 'shelf 01 vanished at ${width}px / ${scale}x',
        );
        expect(find.text('UNDER 30'), findsOneWidget);
      }
    }
  });

  // Phase 30's carried-over item, Discover's half. The browse grid and the
  // search results get the link from `SliverRecipeGrid`; the shelves build
  // their cards directly, so they wire the same destination themselves and a
  // test has to say so — the two must not disagree.
  //
  // Asserted on the rendered probe rather than the router's uri: an imperative
  // `push` nests a match list instead of replacing the outer one, so
  // `currentConfiguration.uri` still reads `/discover` on top of a pushed page.
  group('a shelf card links to its chef', () {
    testWidgets('the badge opens the chef, the card opens the recipe', (
      tester,
    ) async {
      _size(tester, 1400);
      await tester.pumpWidget(_routedApp(_FakeDiscover(quickRows: [_owned])));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(ChefBadge));
      await tester.pumpAndSettle();
      expect(find.text('CHEF PAGE d1'), findsOneWidget);
      expect(find.text('RECIPE PAGE q1'), findsNothing);
    });

    testWidgets('the rest of the shelf card still opens the recipe', (
      tester,
    ) async {
      _size(tester, 1400);
      await tester.pumpWidget(_routedApp(_FakeDiscover(quickRows: [_owned])));
      await tester.pumpAndSettle();

      // The title banner, well clear of the cover overlay.
      await tester.tap(find.text('Aglio e olio'));
      await tester.pumpAndSettle();
      expect(find.text('RECIPE PAGE q1'), findsOneWidget);
      expect(find.text('CHEF PAGE d1'), findsNothing);
    });

    // The shelves render placeholders while a query is in flight, and a
    // placeholder has no recipe behind it — reading `recipes[i]` on that branch
    // is a range error, not a missing badge.
    testWidgets('a loading shelf renders placeholders, not a crash', (
      tester,
    ) async {
      _size(tester, 1400);
      await tester.pumpWidget(_routedApp(_FakeDiscover(hangingShelf: 'quick')));
      await tester.pump();

      expect(find.byType(RecipeCardPlaceholder), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });
}
