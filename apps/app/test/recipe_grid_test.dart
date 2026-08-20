import 'package:app/widgets/recipe_grid.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
