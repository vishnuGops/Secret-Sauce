// Phase 35c. `/explore` — the corpus.
//
// The property worth more than the layout is the **preamble**. These are other
// people's recipes, and a grid that looks exactly like Discover's has misled
// the reader whatever the individual cards say. If the introduction is ever
// dropped for space, this file is what notices.
import 'dart:async';

import 'package:app/features/explore/explore_screen.dart';
import 'package:app/routing/app_router.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

Recipe _recipe(String id, String title) => Recipe(
  id: id,
  ownerId: 'imported-1',
  title: title,
  servings: 4,
  visibility: RecipeVisibility.public,
  isImported: true,
  sourceName: 'Jo Cooks',
  sourceUrl: 'https://example.test/jo/$id',
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

class _FakeDiscover implements DiscoverRepository {
  _FakeDiscover({this.rows = const [], this.count = 0, this.fail = false});

  final List<Recipe> rows;
  final int count;
  final bool fail;

  /// Every (limit, offset) the page asked for.
  final List<(int, int)> calls = [];

  @override
  Future<List<Recipe>> corpus({
    int limit = kRecipePageSize,
    int offset = 0,
    String? cuisine,
  }) async {
    if (fail) throw Exception('boom');
    calls.add((limit, offset));
    return offset == 0 ? rows : const [];
  }

  @override
  Future<int> corpusCount() async => count;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}

void _size(WidgetTester tester, double width, [double height = 1600]) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<GoRouter> _pump(
  WidgetTester tester, {
  required _FakeDiscover discover,
  double textScale = 1.0,
}) async {
  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(_FakeAuth()),
      discoverRepositoryProvider.overrideWithValue(discover),
    ],
  );
  addTearDown(container.dispose);

  final router = container.read(appRouterProvider);
  router.go(Routes.explore);

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

void main() {
  testWidgets('opens signed out — no redirect to /auth', (tester) async {
    _size(tester, 1000);
    final router = await _pump(tester, discover: _FakeDiscover());

    expect(router.state.matchedLocation, Routes.explore);
    expect(find.byType(ExploreScreen), findsOneWidget);
  });

  testWidgets('says what this collection is before the first card', (
    tester,
  ) async {
    _size(tester, 1000);
    await _pump(
      tester,
      discover: _FakeDiscover(rows: [_recipe('r1', 'Lemon Garlic Scallops')]),
    );

    expect(
      find.textContaining('Every recipe here was published somewhere else'),
      findsOneWidget,
    );
    expect(
      find.textContaining('do not copy their photographs'),
      findsOneWidget,
      reason: 'the image position is the one the Rights page leads with',
    );
  });

  testWidgets('states the size of the collection', (tester) async {
    _size(tester, 1000);
    await _pump(tester, discover: _FakeDiscover(count: 21334));

    // Grouped, not abbreviated. "21k" reads as vagueness about how much of
    // other people's work this holds.
    expect(find.textContaining('21,334 recipes'), findsOneWidget);
  });

  testWidgets('links to the Rights page', (tester) async {
    _size(tester, 1000);
    final router = await _pump(tester, discover: _FakeDiscover());

    await tester.tap(find.text('How we credit these'));
    await tester.pumpAndSettle();

    expect(router.state.matchedLocation, Routes.legal('rights'));
  });

  testWidgets('asks for one page at a time', (tester) async {
    _size(tester, 1000);
    final discover = _FakeDiscover(
      rows: [_recipe('r1', 'Lemon Garlic Scallops')],
    );
    await _pump(tester, discover: discover);

    expect(discover.calls.first, (kRecipePageSize, 0));
  });

  testWidgets('renders the cards it is given', (tester) async {
    _size(tester, 1000);
    await _pump(
      tester,
      discover: _FakeDiscover(rows: [_recipe('r1', 'Lemon Garlic Scallops')]),
    );

    expect(find.text('Lemon Garlic Scallops'), findsOneWidget);
  });

  testWidgets('an empty corpus is a state, not an error', (tester) async {
    _size(tester, 1000);
    await _pump(tester, discover: _FakeDiscover());

    expect(find.text('Nothing imported yet'), findsOneWidget);
    expect(find.byType(ErrorView), findsNothing);
  });

  testWidgets('a failed read offers a retry', (tester) async {
    _size(tester, 1000);
    await _pump(tester, discover: _FakeDiscover(fail: true));

    expect(find.byType(ErrorView), findsOneWidget);
  });

  group('envelope', () {
    for (final width in <double>[390, 600, 1000, 1440]) {
      for (final scale in <double>[1.0, 2.0]) {
        testWidgets('fits at ${width}px @ ${scale}x', (tester) async {
          _size(tester, width, 2400);
          await _pump(
            tester,
            textScale: scale,
            discover: _FakeDiscover(
              count: 21334,
              rows: [
                _recipe('r1', 'Slow-Braised Short Rib with Salsa Verde'),
                _recipe(
                  'r2',
                  'Gluten-Free Potato, Bacon & Egg Breakfast Burritos',
                ),
              ],
            ),
          );

          expect(
            tester.takeException(),
            isNull,
            reason: 'overflow at ${width}px @ ${scale}x',
          );
        });
      }
    }
  });
}
