import 'package:app/routing/app_router.dart';
import 'package:app/widgets/recipe_grid.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const _recipes = <Recipe>[
  Recipe(id: '1', ownerId: 'u1', title: 'Chicken Tikka Masala'),
  Recipe(id: '2', ownerId: 'u1', title: 'Spaghetti Aglio e Olio'),
  Recipe(id: '3', ownerId: 'u1', title: 'Suya-Spiced Lamb Skewers'),
  Recipe(id: '4', ownerId: 'u1', title: 'Charcoal Jollof Rice'),
  Recipe(id: '5', ownerId: 'u1', title: 'Classic Margherita Pizza'),
  Recipe(id: '6', ownerId: 'u1', title: 'Cacio e Pepe'),
  Recipe(id: '7', ownerId: 'u1', title: 'Fresh Guacamole'),
  Recipe(id: '8', ownerId: 'u1', title: "Grandma's Sunday Sauce"),
];

Widget _grid(double width) => MaterialApp(
  theme: AppTheme.light(),
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: width,
        height: 900,
        child: const RecipeGrid(recipes: _recipes),
      ),
    ),
  ),
);

/// The cards sharing the topmost row, left to right.
List<Rect> _firstRow(WidgetTester tester) {
  final finder = find.byType(RecipeCard);
  final rects = <Rect>[
    for (var i = 0; i < finder.evaluate().length; i++)
      tester.getRect(finder.at(i)),
  ];
  final top = rects.first.top;
  return rects.where((r) => r.top == top).toList();
}

void main() {
  // The grid derives its columns from the width it is handed, so these are
  // widths a window is actually dragged through, not breakpoint samples.
  // 16px padding each side, 16px gaps, cards 288–340 wide.
  for (final (width, expectedColumns) in <(double, int)>[
    (390, 1), // phone
    (700, 2), // split-screen web
    (1000, 3),
    (1440, 4), // four real cards, not three stretched ones
    (2000, 6), // ultrawide
    // B049: capped at `kRecipeGridMaxColumns`. Uncapped, 2560 was 8 columns
    // and 3840 was 12 — more than this fixture's eight cards.
    (2560, kRecipeGridMaxColumns),
    (3840, kRecipeGridMaxColumns),
  ]) {
    testWidgets('$width px lays out $expectedColumns columns', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_grid(width));
      expect(tester.takeException(), isNull);

      final row = _firstRow(tester);
      expect(row.length, expectedColumns);
      for (final card in row) {
        expect(
          card.width,
          lessThanOrEqualTo(kRecipeCardMaxWidth),
          reason: 'card stretched past its max width at $width',
        );
        expect(
          card.width,
          greaterThanOrEqualTo(kRecipeCardMinWidth),
          reason: 'card squeezed under its min width at $width',
        );
        expect(card.height, kRecipeCardHeight);
      }
    });
  }

  testWidgets('a row of maximum-width cards stays centred', (tester) async {
    tester.view.physicalSize = const Size(2000, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // 800 - 32 padding = 768, which fits two cards with 376 each — over the
    // cap, so they hold at 340 and the leftover becomes gutters.
    await tester.pumpWidget(_grid(800));

    final grid = tester.getRect(find.byType(RecipeGrid));
    final row = _firstRow(tester);
    expect(row.length, 2);
    expect(row.first.width, kRecipeCardMaxWidth);
    expect(
      row.first.left - grid.left,
      closeTo(grid.right - row.last.right, 0.001),
      reason: 'leftover width must be split evenly, not dumped on one side',
    );
    expect(
      row.first.left - grid.left,
      greaterThan(AppSpacing.md),
      reason: 'a capped row should actually be inset beyond the padding',
    );
  });

  // B049: past the column cap, extra width is a right-hand margin, so the
  // first card keeps the page's left edge (B059) instead of drifting 860px in.
  testWidgets('a 4K window left-aligns a capped block of six', (tester) async {
    tester.view.physicalSize = const Size(3840, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_grid(3840));

    final grid = tester.getRect(find.byType(RecipeGrid));
    final row = _firstRow(tester);
    expect(row.length, kRecipeGridMaxColumns);
    expect(row.first.width, kRecipeCardMaxWidth);
    final left = row.first.left - grid.left;
    final right = grid.right - row.last.right;
    expect(left, closeTo(AppSpacing.md, 0.001));
    // 3840 - 6 x 340 - 5 x 16 = 1720 of margin, all of it trailing.
    expect(right, closeTo(1720 - AppSpacing.md, 0.001));
    // And the metrics a header aligns with say the same thing.
    expect(
      AppSpacing.md + recipeGridMetrics(3840).gutter,
      closeTo(left, 0.001),
    );
  });

  // Resizing must reflow, not just re-measure: the same grid, dragged wider,
  // gains a column without anything above it changing.
  testWidgets('reflows when the window is resized', (tester) async {
    tester.view.physicalSize = const Size(2000, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_grid(400));
    expect(_firstRow(tester).length, 1);

    await tester.pumpWidget(_grid(1000));
    expect(_firstRow(tester).length, 3);

    await tester.pumpWidget(_grid(640));
    expect(_firstRow(tester).length, 2);
    expect(tester.takeException(), isNull);
  });

  // Phase 30's carried-over item: a reader on any browsing surface can get from
  // a recipe to the chef who wrote it. The grid is the one place every one of
  // those surfaces goes through, so wiring it here is what gives Discover's
  // browse grid, its search results, My Recipes and the chef page the link at
  // once — none of those files says anything about chefs.
  //
  // Asserted on the rendered probe, not on `currentConfiguration.uri`: an
  // imperative `push` nests a match list rather than replacing the outer one,
  // so the router's own uri still reads `/` on top of a pushed page. Same
  // reason `chefs_screen_test.dart` reads its destination off the screen.
  group('chef badge link', () {
    testWidgets('a card chef badge opens that chef', (tester) async {
      _phone(tester);
      await _pumpGrid(tester);

      // The badge takes its own hit area only: it sits deeper in the hit-test
      // path than the card's own `InkWell`, so its recognizer enters the
      // gesture arena first and wins the sweep.
      await tester.tap(find.byType(ChefBadge));
      await tester.pumpAndSettle();

      expect(find.text('CHEF PAGE d1'), findsOneWidget);
      expect(find.text('RECIPE PAGE r1'), findsNothing);
    });

    testWidgets('the rest of the card still opens the recipe', (tester) async {
      _phone(tester);
      await _pumpGrid(tester);

      // The title banner: on the card, nowhere near the cover overlay.
      await tester.tap(find.text('Aglio e olio'));
      await tester.pumpAndSettle();

      expect(find.text('RECIPE PAGE r1'), findsOneWidget);
      expect(find.text('CHEF PAGE d1'), findsNothing);
    });

    testWidgets('a caller can redirect the tap somewhere else', (tester) async {
      _phone(tester);
      final taken = <String>[];
      await _pumpGrid(tester, onChefTap: (chef) => taken.add(chef.id));

      await tester.tap(find.byType(ChefBadge));
      await tester.pumpAndSettle();

      expect(taken, ['d1']);
      expect(
        find.text('CHEF PAGE d1'),
        findsNothing,
        reason: 'an override replaces the push, it does not run beside it',
      );
    });

    testWidgets('a card with no embedded owner has no badge to tap', (
      tester,
    ) async {
      _phone(tester);
      await _pumpGrid(tester, recipes: _recipes.take(1).toList());

      expect(find.byType(ChefBadge), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}

/// One owned recipe, so the cover carries a chef badge at all.
const _owned = <Recipe>[
  Recipe(
    id: 'r1',
    ownerId: 'd1',
    title: 'Aglio e olio',
    owner: Profile(
      id: 'd1',
      displayName: 'Amara Okonkwo',
      chefTier: ChefTier.masterChef,
    ),
  ),
];

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// The grid at `/`, with probes for the two destinations a card can reach.
Future<void> _pumpGrid(
  WidgetTester tester, {
  List<Recipe> recipes = _owned,
  ValueChanged<Profile>? onChefTap,
}) async {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder:
            (context, state) => Scaffold(
              body: RecipeGrid(recipes: recipes, onChefTap: onChefTap),
            ),
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
            (context, state) =>
                Scaffold(body: Text('CHEF PAGE ${state.pathParameters['id']}')),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
  );
  await tester.pumpAndSettle();
}
