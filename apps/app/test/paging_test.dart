// OPT-P9: Discover and My Recipes fetch one page at a time and grow by a tap
// on `Load more`. Before this, Discover was capped at 20/30 rows and the two My
// Recipes tabs were unbounded reads.
//
// The mechanics that can go wrong are all in `PagedRecipesNotifier` (core):
// where the next offset comes from, what happens when a row moves between two
// pages, and what a failed second page does to the rows already on screen.
import 'dart:async';

import 'package:app/features/discover/discover_providers.dart';
import 'package:app/widgets/recipe_async_grid.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

List<Recipe> _page(int from, int count) => [
  for (var i = from; i < from + count; i++)
    Recipe(id: 'r$i', ownerId: 'u1', title: 'Recipe $i'),
];

/// Records every `(limit, offset)` it is asked for and serves from a fixed
/// corpus, exactly as `recipes_popular(p_limit, p_offset)` does.
class _PagingDiscoverRepository implements DiscoverRepository {
  _PagingDiscoverRepository({this.total = 45});

  final int total;
  final List<(int, int)> calls = [];
  Object? failNext;

  @override
  Future<List<Recipe>> popular({
    int limit = kRecipePageSize,
    int offset = 0,
  }) async {
    calls.add((limit, offset));
    final err = failNext;
    if (err != null) {
      failNext = null;
      throw err;
    }
    if (offset >= total) return const [];
    return _page(offset, offset + limit > total ? total - offset : limit);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}

/// A paged list keyed by [_keyProvider] — the shape of Discover's category
/// and search grids, where a new key rebuilds the **same** notifier instance.
/// A page whose `'<key>@<offset>'` has a gate waits on it.
final _keyProvider = StateProvider<String>((ref) => 'a');
final _gates = <String, Completer<List<Recipe>>>{};

class _KeyedNotifier extends PagedRecipesNotifier {
  late String _key;

  @override
  Future<RecipePage> build() {
    _key = ref.watch(_keyProvider);
    return super.build();
  }

  @override
  Future<List<Recipe>> fetchPage({required int limit, required int offset}) {
    final gate = _gates['$_key@$offset'];
    if (gate != null) return gate.future;
    return Future.value([
      for (var i = offset; i < offset + limit; i++)
        Recipe(id: '$_key$i', ownerId: 'u1', title: '$_key $i'),
    ]);
  }
}

final _keyedProvider =
    AsyncNotifierProvider.autoDispose<_KeyedNotifier, RecipePage>(
      _KeyedNotifier.new,
    );

ProviderContainer _container(DiscoverRepository repo) {
  final c = ProviderContainer(
    overrides: [discoverRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(c.dispose);
  // Something must listen or an autoDispose provider is torn down between
  // `read`s and every page starts over at offset 0.
  c.listen(popularRecipesProvider, (_, __) {});
  return c;
}

void main() {
  tearDown(_gates.clear);

  // 36c review (B121's class, in the base class this time): a `loadMore`
  // begun under one key must not land after a rebuild to another. The
  // notifier instance survives the rebuild, so only the generation guard can
  // tell the stale page apart.
  test('a loadMore begun before a rebuild is dropped, not appended', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.listen(_keyedProvider, (_, __) {});
    await c.read(_keyedProvider.future);

    final stale = Completer<List<Recipe>>();
    _gates['a@$kRecipePageSize'] = stale;
    final more = c.read(_keyedProvider.notifier).loadMore();

    c.read(_keyProvider.notifier).state = 'b';
    final fresh = await c.read(_keyedProvider.future);
    expect(fresh.recipes.first.id, 'b0');

    stale.complete([
      for (var i = kRecipePageSize; i < 2 * kRecipePageSize; i++)
        Recipe(id: 'a$i', ownerId: 'u1', title: 'a $i'),
    ]);
    await more;

    final after = c.read(_keyedProvider).valueOrNull!;
    expect(
      after.recipes.every((r) => r.id.startsWith('b')),
      isTrue,
      reason: 'a page from the previous key was appended under the new one',
    );
    expect(after.recipes, hasLength(kRecipePageSize));
    expect(after.loadingMore, isFalse);
  });

  group('PagedRecipesNotifier', () {
    test(
      'the first page is one page, and a full page means there is more',
      () async {
        final repo = _PagingDiscoverRepository();
        final c = _container(repo);

        final page = await c.read(popularRecipesProvider.future);

        expect(repo.calls, [(kRecipePageSize, 0)]);
        expect(page.recipes, hasLength(kRecipePageSize));
        expect(page.hasMore, isTrue);
      },
    );

    test('loadMore appends the next page at the right offset', () async {
      final repo = _PagingDiscoverRepository();
      final c = _container(repo);
      await c.read(popularRecipesProvider.future);

      await c.read(popularRecipesProvider.notifier).loadMore();

      expect(repo.calls, [
        (kRecipePageSize, 0),
        (kRecipePageSize, kRecipePageSize),
      ]);
      final page = c.read(popularRecipesProvider).requireValue;
      expect(page.recipes, hasLength(kRecipePageSize * 2));
      expect(page.recipes.map((r) => r.id).toSet(), hasLength(40));
      expect(page.loadingMore, isFalse);
    });

    test('a short page ends the list', () async {
      // 45 rows: pages of 20, 20, then 5.
      final repo = _PagingDiscoverRepository();
      final c = _container(repo);
      await c.read(popularRecipesProvider.future);
      await c.read(popularRecipesProvider.notifier).loadMore();
      await c.read(popularRecipesProvider.notifier).loadMore();

      final page = c.read(popularRecipesProvider).requireValue;
      expect(page.recipes, hasLength(45));
      expect(page.hasMore, isFalse);

      // Nothing more is requested once the server has run out.
      await c.read(popularRecipesProvider.notifier).loadMore();
      expect(repo.calls, hasLength(3));
    });

    test('a row that shifts between pages is shown once, not twice', () async {
      // A recipe deleted between page 1 and page 2 slides the window back, so
      // the server legitimately returns a row the client already has.
      final repo = _OverlappingRepository();
      final c = ProviderContainer(
        overrides: [discoverRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(c.dispose);
      c.listen(popularRecipesProvider, (_, __) {});

      await c.read(popularRecipesProvider.future);
      await c.read(popularRecipesProvider.notifier).loadMore();

      final ids =
          c
              .read(popularRecipesProvider)
              .requireValue
              .recipes
              .map((r) => r.id)
              .toList();
      expect(
        ids.toSet(),
        hasLength(ids.length),
        reason: 'a row was duplicated',
      );
      // The full page still counts as "there is more", even though five of its
      // rows were already on screen.
      expect(c.read(popularRecipesProvider).requireValue.hasMore, isTrue);
    });

    test('a second loadMore while one is in flight is ignored', () async {
      final repo = _PagingDiscoverRepository();
      final c = _container(repo);
      await c.read(popularRecipesProvider.future);

      final notifier = c.read(popularRecipesProvider.notifier);
      final first = notifier.loadMore();
      final second = notifier.loadMore();
      await Future.wait([first, second]);

      expect(repo.calls, hasLength(2), reason: 'the page was fetched twice');
    });

    test('a failed page keeps the rows already loaded and rethrows', () async {
      final repo = _PagingDiscoverRepository();
      final c = _container(repo);
      await c.read(popularRecipesProvider.future);

      repo.failNext = StateError('network gone');
      await expectLater(
        c.read(popularRecipesProvider.notifier).loadMore(),
        throwsA(isA<StateError>()),
      );

      final page = c.read(popularRecipesProvider).requireValue;
      expect(page.recipes, hasLength(kRecipePageSize));
      expect(page.loadingMore, isFalse, reason: 'the button would stay dead');
      expect(page.hasMore, isTrue, reason: 'the failure is retryable');
    });
  });

  group('RecipeAsyncGrid', () {
    testWidgets('offers Load more only while the server has more', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1000, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final repo = _PagingDiscoverRepository(total: 25);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [discoverRepositoryProvider.overrideWithValue(repo)],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: RecipeAsyncGrid(
                provider: popularRecipesProvider,
                empty: const EmptyView(title: 'none', icon: Icons.no_food),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The footer scrolls with the grid, so it is below the fold on a
      // 1000x1200 viewport — reaching it is part of what is being asserted.
      await tester.scrollUntilVisible(find.text('Load more'), 400);
      expect(find.text('Load more'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Load more'));
      await tester.pumpAndSettle();

      // 25 rows total: the second page is short, so the button is gone.
      expect(repo.calls, hasLength(2));
      expect(find.text('Load more'), findsNothing);
    });

    testWidgets('the footer survives the narrow envelope at 2.0x text scale', (
      tester,
    ) async {
      // The card's own envelope (CLAUDE.md #13): narrowest column the grid
      // packs to, largest accessibility scale. The footer is new furniture in
      // that space, so it gets checked at the same corner.
      tester.view.physicalSize = const Size(kRecipeCardMinWidth, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            discoverRepositoryProvider.overrideWithValue(
              _PagingDiscoverRepository(),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(kRecipeCardMinWidth, 1000),
                textScaler: TextScaler.linear(2),
              ),
              child: Scaffold(
                body: RecipeAsyncGrid(
                  provider: popularRecipesProvider,
                  empty: const EmptyView(title: 'none', icon: Icons.no_food),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Load more'), 400);

      expect(tester.takeException(), isNull);
      expect(find.text('Load more'), findsOneWidget);
    });
  });
}

/// Serves page 2 starting five rows earlier than the client asked — what a
/// deletion between two requests does to an offset.
class _OverlappingRepository implements DiscoverRepository {
  @override
  Future<List<Recipe>> popular({
    int limit = kRecipePageSize,
    int offset = 0,
  }) async {
    return offset == 0 ? _page(0, limit) : _page(offset - 5, limit);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}
