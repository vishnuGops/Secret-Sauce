import 'package:app/features/my_recipes/my_recipes_providers.dart';
import 'package:app/features/my_recipes/my_recipes_screen.dart';
import 'package:app/routing/app_router.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// My Recipes' **Saved** tab (UX-020): the bookmark on a recipe wrote a
/// `recipe_saves` row that no screen ever listed.
///
/// The other two tabs are stubbed at the notifier seam the way
/// `my_recipes_header_test.dart` does it; the Saved tab goes through the real
/// `SavedRecipesNotifier` over a fake repository, so the test sees the actual
/// `listSaved` calls — which is what the paging assertion is about.
class _EmptyMine extends MyRecipesNotifier {
  @override
  Future<List<Recipe>> fetchPage({required int limit, required int offset}) =>
      Future.value(const []);
}

class _EmptyShared extends SharedWithMeNotifier {
  @override
  Future<List<Recipe>> fetchPage({required int limit, required int offset}) =>
      Future.value(const []);
}

/// Someone else's recipe, with its owner embedded so the chef badge has a
/// name to render.
Recipe _saved(int i) => Recipe(
  id: 'saved-$i',
  ownerId: 'chef-$i',
  title: 'Saved Recipe $i',
  visibility: RecipeVisibility.public,
  owner: Profile(
    id: 'chef-$i',
    displayName: 'Chef Number $i',
    chefTier: ChefTier.homeCook,
  ),
);

class _SavedRepo implements RecipeRepository {
  _SavedRepo({this.total = 0, this.fail = false});

  /// How many saved recipes the "server" holds.
  final int total;
  final bool fail;

  final List<({int limit, int offset})> calls = [];

  @override
  Future<List<Recipe>> listSaved({
    int limit = kRecipePageSize,
    int offset = 0,
  }) async {
    calls.add((limit: limit, offset: offset));
    if (fail) throw Exception('network down');
    final end = (offset + limit).clamp(0, total);
    return [for (var i = offset; i < end; i++) _saved(i)];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}

Future<void> _pump(
  WidgetTester tester, {
  required double width,
  required _SavedRepo repo,
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        myRecipesProvider.overrideWith(_EmptyMine.new),
        sharedWithMeProvider.overrideWith(_EmptyShared.new),
        recipeRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp.router(
        theme: AppTheme.light(),
        builder:
            (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
        routerConfig: GoRouter(
          initialLocation: Routes.myRecipes,
          routes: [
            GoRoute(
              path: Routes.myRecipes,
              builder: (context, state) => const MyRecipesScreen(),
            ),
            GoRoute(
              path: Routes.discover,
              builder:
                  (context, state) =>
                      const Scaffold(body: Text('DISCOVER PAGE')),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openSaved(WidgetTester tester) async {
  // The web strip scrolls, and at 600px x 2.0 `Saved` starts past its edge.
  await tester.ensureVisible(find.text('Saved'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Saved'));
  await tester.pumpAndSettle();
}

void main() {
  for (final width in [390.0, 1440.0]) {
    testWidgets('three tabs at ${width}px, Saved last', (tester) async {
      await _pump(tester, width: width, repo: _SavedRepo());

      final tabBar = tester.widget<TabBar>(find.byType(TabBar));
      expect(
        [for (final t in tabBar.tabs) (t as Tab).text],
        ['My Recipes', 'Shared with me', 'Saved'],
      );
    });
  }

  testWidgets('Saved lists the saved recipes with their chef badges', (
    tester,
  ) async {
    final repo = _SavedRepo(total: 2);
    await _pump(tester, width: 1440, repo: repo);
    await _openSaved(tester);

    expect(find.text('Saved Recipe 0'), findsOneWidget);
    expect(find.text('Saved Recipe 1'), findsOneWidget);
    // Other people's recipes: who made each one is the point.
    expect(find.byType(ChefBadge), findsNWidgets(2));
    expect(find.text('Chef Number 0'), findsOneWidget);
    // Visibility is the owner's setting, not the saver's — no pill.
    expect(find.byTooltip('Public'), findsNothing);
    expect(repo.calls, [(limit: kRecipePageSize, offset: 0)]);
  });

  testWidgets('empty Saved explains the bookmark and links to Discover', (
    tester,
  ) async {
    await _pump(tester, width: 390, repo: _SavedRepo());
    await _openSaved(tester);

    expect(find.text('Nothing saved yet'), findsOneWidget);
    expect(find.byIcon(Icons.bookmark_border), findsOneWidget);

    await tester.tap(find.text('Browse recipes'));
    await tester.pumpAndSettle();
    expect(find.text('DISCOVER PAGE'), findsOneWidget);
  });

  testWidgets('Load more asks listSaved for the next page', (tester) async {
    final repo = _SavedRepo(total: kRecipePageSize + 3);
    await _pump(tester, width: 1440, repo: repo);
    await _openSaved(tester);

    final loadMore = find.text('Load more');
    await tester.scrollUntilVisible(
      loadMore,
      400,
      scrollable: find.descendant(
        of: find.byType(CustomScrollView),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(loadMore);
    await tester.pumpAndSettle();

    expect(repo.calls, [
      (limit: kRecipePageSize, offset: 0),
      (limit: kRecipePageSize, offset: kRecipePageSize),
    ]);
  });

  testWidgets('a failed Saved read shows the error view', (tester) async {
    await _pump(tester, width: 1440, repo: _SavedRepo(fail: true));
    await _openSaved(tester);

    expect(find.byType(ErrorView), findsOneWidget);
    expect(find.text('Nothing saved yet'), findsNothing);
  });

  // UX-055: an empty vault on web showed the header's `New recipe` and the
  // empty state's, one card apart. Web keeps the header's; compact, whose
  // AppBar has only an icon, keeps the empty state's labelled one.
  group('one labelled New recipe when My Recipes is empty', () {
    testWidgets('web: the header button only', (tester) async {
      await _pump(tester, width: 1440, repo: _SavedRepo());

      expect(find.text('No recipes yet'), findsOneWidget);
      expect(find.text('New recipe'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(MyRecipesScreen.newRecipeButtonKey),
          matching: find.text('New recipe'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('compact: the empty state keeps its labelled button', (
      tester,
    ) async {
      await _pump(tester, width: 390, repo: _SavedRepo());

      expect(find.byKey(MyRecipesScreen.newRecipeButtonKey), findsNothing);
      expect(find.text('New recipe'), findsOneWidget);
      expect(find.byTooltip('New recipe'), findsOneWidget);
    });
  });

  // The strip now holds three labels, and at 390px and 2.0x `Shared with me`
  // alone is wider than a third of the phone. A fixed `TabBar` does not
  // overflow there — `Tab` fades its label — so `takeException()` cannot see
  // it; the label's laid-out width against its intrinsic width can.
  testWidgets('compact: no tab label is cut at 390px, textScale 2.0', (
    tester,
  ) async {
    await _pump(tester, width: 390, textScale: 2.0, repo: _SavedRepo());

    for (final label in ['My Recipes', 'Shared with me', 'Saved']) {
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: find.byType(Tab), matching: find.text(label)),
      );
      expect(
        paragraph.size.width,
        greaterThanOrEqualTo(
          paragraph.getMaxIntrinsicWidth(double.infinity) - 0.5,
        ),
        reason: '"$label" is clipped',
      );
    }
  });

  // The whole screen, both tabs that matter here, across the envelope.
  for (final width in [390.0, 600.0, 1000.0, 1440.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('three tabs fit at ${width}px, textScale $scale', (
        tester,
      ) async {
        await _pump(
          tester,
          width: width,
          textScale: scale,
          repo: _SavedRepo(total: 2),
        );
        expect(tester.takeException(), isNull, reason: 'My Recipes tab');

        await _openSaved(tester);
        expect(find.text('Saved Recipe 0'), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'Saved tab');
      });
    }
  }
}
