// OPT-P8: Discover's search field writes `searchQueryProvider` on every
// keystroke, which invalidates `searchResultsProvider`. Without a debounce,
// typing "chicken" fired seven `recipes_search` RPCs and used one.
//
// `recipes_search` is the most expensive read in the app even after OPT-P1, and
// it is reachable signed-out, so per-keystroke calls are both slow and free to
// anyone. These tests drive the provider directly through a ProviderContainer —
// no widget needed, and `async` timers advance under `fakeAsync` via
// `FakeAsync`-backed `pump`-less control.
import 'package:app/features/discover/discover_masthead.dart';
import 'package:app/features/discover/discover_providers.dart';
import 'package:app/features/discover/discover_screen.dart';
import 'package:app/features/explore/explore_screen.dart';
import 'package:app/routing/app_router.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _RecordingDiscoverRepository implements DiscoverRepository {
  final List<String> searches = [];

  @override
  Future<List<Recipe>> search(
    String query, {
    int limit = kRecipePageSize,
    int offset = 0,
  }) async {
    searches.add(query);
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}

ProviderContainer _container(_RecordingDiscoverRepository repo) {
  final c = ProviderContainer(
    overrides: [discoverRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('an empty query never reaches the repository', () async {
    final repo = _RecordingDiscoverRepository();
    final c = _container(repo);

    c.listen(searchResultsProvider, (_, __) {});
    await Future<void>.delayed(kSearchDebounce * 2);

    expect(repo.searches, isEmpty);
  });

  test('one settled query issues exactly one search', () async {
    final repo = _RecordingDiscoverRepository();
    final c = _container(repo);

    c.read(searchQueryProvider.notifier).state = 'chicken';
    c.listen(searchResultsProvider, (_, __) {});
    await Future<void>.delayed(kSearchDebounce * 2);

    expect(repo.searches, ['chicken']);
  });

  test('typing does not search until the pause (the P8 fix)', () async {
    final repo = _RecordingDiscoverRepository();
    final c = _container(repo);
    c.listen(searchResultsProvider, (_, __) {});

    // Seven keystrokes in quick succession, each well inside the debounce.
    for (final q in ['c', 'ch', 'chi', 'chic', 'chick', 'chicke', 'chicken']) {
      c.read(searchQueryProvider.notifier).state = q;
      c.listen(searchResultsProvider, (_, __) {});
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    // Nothing should have gone out yet.
    expect(
      repo.searches,
      isEmpty,
      reason: 'a search fired mid-typing — the debounce is not holding',
    );

    await Future<void>.delayed(kSearchDebounce * 2);
    expect(repo.searches, [
      'chicken',
    ], reason: 'only the settled query should reach the server');
  });

  test('a superseded query is dropped, not sent late', () async {
    final repo = _RecordingDiscoverRepository();
    final c = _container(repo);

    c.read(searchQueryProvider.notifier).state = 'lamb';
    c.listen(searchResultsProvider, (_, __) {});
    await Future<void>.delayed(const Duration(milliseconds: 50));

    c.read(searchQueryProvider.notifier).state = 'lamb tagine';
    c.listen(searchResultsProvider, (_, __) {});
    await Future<void>.delayed(kSearchDebounce * 2);

    expect(repo.searches, ['lamb tagine']);
  });

  group('search in the URL (UX-022)', () {
    testWidgets('/discover?q=soup pre-fills the field and shows results', (
      tester,
    ) async {
      final repo = _RoutedDiscover();
      await _pumpAt(tester, '/discover?q=soup', repo);

      expect(_fieldText(tester), 'soup');
      expect(repo.searches, ['soup']);
      expect(find.text('Soup hit'), findsOneWidget);
      expect(find.text('UNDER 30'), findsNothing);
      // The seed frame renders a spinner, not the unsearched page — so a deep
      // link does not cost the three shelves and the browse grid their reads.
      expect(repo.calls, isNot(contains('popular')));
      expect(repo.calls, isNot(contains('quick')));
    });

    testWidgets('typing writes ?q= to the location, once, after the pause', (
      tester,
    ) async {
      final repo = _RoutedDiscover();
      final router = await _pumpAt(tester, Routes.discover, repo);

      await tester.enterText(find.byType(SearchBar), 'soup');
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        _uri(router).queryParameters['q'],
        isNull,
        reason: 'the URL moved mid-typing',
      );
      await tester.pump(kSearchDebounce * 2);
      await tester.pumpAndSettle();

      expect(_uri(router).path, Routes.discover);
      expect(_uri(router).queryParameters['q'], 'soup');
      expect(repo.searches, ['soup']);
      expect(find.text('Soup hit'), findsOneWidget);
    });

    testWidgets('the URL echo never rewrites what the reader typed', (
      tester,
    ) async {
      final repo = _RoutedDiscover();
      final router = await _pumpAt(tester, Routes.discover, repo);

      // A trailing space: the URL carries the trimmed query, and the rebuild
      // it causes must not "correct" the field to match it.
      await tester.enterText(find.byType(SearchBar), 'soup ');
      await tester.pump(kSearchDebounce * 2);
      await tester.pumpAndSettle();

      expect(_uri(router).queryParameters['q'], 'soup');
      expect(_fieldText(tester), 'soup ');
    });

    testWidgets('a q that changes under the page (Back, a link) is adopted', (
      tester,
    ) async {
      final repo = _RoutedDiscover();
      final router = await _pumpAt(tester, '/discover?q=soup', repo);

      router.go('/discover?q=stew');
      await tester.pumpAndSettle();
      expect(_fieldText(tester), 'stew');
      expect(repo.searches.last, 'stew');
      expect(find.text('Stew hit'), findsOneWidget);

      // The Discover tab carries no q: the search is over.
      router.go(Routes.discover);
      await tester.pumpAndSettle();
      expect(_fieldText(tester), isEmpty);
      expect(find.text('UNDER 30'), findsOneWidget);
    });

    testWidgets('typing under a tile keeps the tile in the URL', (
      tester,
    ) async {
      final repo = _RoutedDiscover();
      final router = await _pumpAt(
        tester,
        Routes.discoverCategory('mains'),
        repo,
      );

      await tester.enterText(find.byType(SearchBar), 'soup');
      await tester.pump(kSearchDebounce * 2);
      await tester.pumpAndSettle();

      expect(_uri(router).queryParameters, {'q': 'soup', 'category': 'mains'});
    });

    testWidgets('q + category: search wins; clearing restores the tile grid', (
      tester,
    ) async {
      final repo = _RoutedDiscover();
      final router = await _pumpAt(
        tester,
        Routes.discoverSearch('soup', category: 'mains'),
        repo,
      );

      expect(find.text('Soup hit'), findsOneWidget);
      expect(find.text('Main pick'), findsNothing);
      expect(find.text('BROWSE BY CATEGORY'), findsNothing);

      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();

      expect(_uri(router).queryParameters, {'category': 'mains'});
      expect(_fieldText(tester), isEmpty);
      expect(find.text('MAINS'), findsOneWidget);
      expect(find.text('Main pick'), findsOneWidget);
      expect(find.text('Soup hit'), findsNothing);
    });
  });

  group('the search miss (UX-022 / UX-021)', () {
    testWidgets('names the query, and Clear search clears field and URL', (
      tester,
    ) async {
      final repo = _RoutedDiscover();
      final router = await _pumpAt(tester, '/discover?q=zzz', repo);

      expect(find.byKey(kDiscoverSearchMissKey), findsOneWidget);
      expect(find.text('No recipes match “zzz”'), findsOneWidget);
      // The old copy promised arrivals to a reader who had searched.
      expect(find.text('Public recipes will appear here.'), findsNothing);

      await tester.tap(find.text('Clear search'));
      await tester.pumpAndSettle();

      expect(_fieldText(tester), isEmpty);
      expect(_uri(router).queryParameters, isEmpty);
      expect(find.byKey(kDiscoverSearchMissKey), findsNothing);
      expect(find.text('UNDER 30'), findsOneWidget);
    });

    testWidgets('offers the web collection, and it opens /explore', (
      tester,
    ) async {
      final repo = _RoutedDiscover();
      final router = await _pumpAt(tester, '/discover?q=zzz', repo);

      await tester.tap(find.text('Browse the web collection'));
      await tester.pumpAndSettle();

      expect(router.state.matchedLocation, Routes.explore);
      expect(find.byType(ExploreScreen), findsOneWidget);
    });
  });

  // UX-021: the only door to the corpus sat under an infinite grid and was
  // hidden while searching.
  testWidgets('the masthead links to /explore, even mid-search', (
    tester,
  ) async {
    final repo = _RoutedDiscover();
    final router = await _pumpAt(tester, '/discover?q=soup', repo);

    expect(find.byKey(DiscoverMasthead.exploreLinkKey), findsOneWidget);
    await tester.tap(find.byKey(DiscoverMasthead.exploreLinkKey));
    await tester.pumpAndSettle();

    expect(router.state.matchedLocation, Routes.explore);
  });

  // The miss state and the masthead link are new furniture: the page's
  // widths × the contract scales (Gotchas 13, 22, 26).
  group('envelope', () {
    for (final width in [390.0, 600.0, 1000.0, 1440.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('the miss and the masthead link hold at ${width}px × '
            '$scale', (tester) async {
          await _pumpAt(
            tester,
            Routes.discoverSearch(
              'a very long query nobody wrote a recipe for, ever',
            ),
            _RoutedDiscover(),
            width: width,
            height: 2400,
            textScale: scale,
          );

          expect(
            tester.takeException(),
            isNull,
            reason: 'overflow at ${width}px / ${scale}x',
          );
          // Not vacuous: both rendered.
          expect(find.byKey(kDiscoverSearchMissKey), findsOneWidget);
          expect(find.text('Browse the web collection'), findsOneWidget);
          expect(find.byKey(DiscoverMasthead.exploreLinkKey), findsOneWidget);
        });
      }
    }
  });
}

Recipe _recipe(String id, String title) =>
    Recipe(id: id, ownerId: 'u1', title: title, prepMinutes: 10);

class _SignedOut implements AuthRepository {
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

/// Discover behind the real router. `search` answers `soup` and `stew` with
/// one card each and everything else with nothing — the miss.
class _RoutedDiscover implements DiscoverRepository {
  final List<String> calls = [];
  final List<String> searches = [];

  @override
  Future<List<Recipe>> search(
    String query, {
    int limit = kRecipePageSize,
    int offset = 0,
  }) async {
    searches.add(query);
    return switch (query) {
      'soup' => [_recipe('s1', 'Soup hit')],
      'stew' => [_recipe('s2', 'Stew hit')],
      _ => const [],
    };
  }

  @override
  Future<List<Recipe>> byCategories(
    List<String> categories, {
    int limit = kRecipePageSize,
    int offset = 0,
  }) async {
    calls.add('byCategories');
    return [_recipe('c1', '${categories.first} pick')];
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
  Future<List<Recipe>> quick({
    int limit = kRecipePageSize,
    int offset = 0,
  }) async {
    calls.add('quick');
    return const [];
  }

  @override
  Future<List<Recipe>> projects({
    int limit = kRecipePageSize,
    int offset = 0,
  }) async => const [];

  @override
  Future<List<Recipe>> mostForked({
    int limit = kRecipePageSize,
    int offset = 0,
  }) async => const [];

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
  _RoutedDiscover repo, {
  double width = 1400,
  double height = 3000,
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(_SignedOut()),
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

String _fieldText(WidgetTester tester) =>
    tester.widget<SearchBar>(find.byType(SearchBar)).controller!.text;
