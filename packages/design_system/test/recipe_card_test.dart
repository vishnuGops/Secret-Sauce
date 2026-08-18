import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('RecipeCard shows title, description, time and difficulty',
      (tester) async {
    const recipe = Recipe(
      id: '1',
      ownerId: 'u1',
      title: 'Grandma Sauce',
      description: 'Slow-cooked Sunday sauce',
      difficulty: Difficulty.medium,
      prepMinutes: 15,
      cookMinutes: 45,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: Center(
            child: SizedBox(width: 320, child: RecipeCard(recipe: recipe)),
          ),
        ),
      ),
    );

    expect(find.text('Grandma Sauce'), findsOneWidget);
    expect(find.text('Slow-cooked Sunday sauce'), findsOneWidget);
    expect(find.text('1h'), findsOneWidget); // 60 minutes total
    expect(find.text('Medium'), findsOneWidget);
    expect(find.byType(RatingPill), findsNothing); // unrated -> no pill
  });

  testWidgets('RecipeCard shows the rating pill once a recipe is rated',
      (tester) async {
    const recipe = Recipe(
      id: '1',
      ownerId: 'u1',
      title: 'Grandma Sauce',
      ratingAvg: 4.5,
      ratingCount: 12,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: Center(
            child: SizedBox(width: 320, child: RecipeCard(recipe: recipe)),
          ),
        ),
      ),
    );

    expect(find.text('4.5'), findsOneWidget);
    expect(find.text(' (12)'), findsOneWidget);
  });

  // Regression: the rating pill pushed the metadata row past the card width on
  // a rated recipe with a long time label. 276px is the narrowest card the grid
  // produces (2 columns at the 600px medium breakpoint). The 2.0 text scale
  // case is the real-world trigger — at default scale the margin is thin but
  // positive, and accessibility scaling eats it.
  const longMeta = Recipe(
    id: '1',
    ownerId: 'u1',
    title: 'Slow-Braised Short Rib Ragu',
    description: 'Long enough to ellipsize over two lines.',
    difficulty: Difficulty.medium,
    prepMinutes: 90,
    cookMinutes: 675, // "12h 45m"
    ratingAvg: 4.5,
    ratingCount: 1250,
  );

  for (final (width, scale) in <(double, double)>[
    (276, 1.0),
    (320, 1.0),
    (276, 2.0),
    (320, 2.0),
  ]) {
    testWidgets(
        'RecipeCard metadata row fits at ${width}px, textScale $scale',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              body: Center(
                child: SizedBox(
                  width: width,
                  child: const RecipeCard(recipe: longMeta),
                ),
              ),
            ),
          ),
        ),
      );

      expect(
        tester.takeException(),
        isNull,
        reason: 'overflow at ${width}px @ ${scale}x',
      );
    });
  }

  testWidgets('RecipeCard badges visibility when asked', (tester) async {
    const recipe = Recipe(id: '1', ownerId: 'u1', title: 'Secret Sauce');

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: RecipeCard(recipe: recipe, showVisibility: true),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Private'), findsOneWidget);
  });
}
