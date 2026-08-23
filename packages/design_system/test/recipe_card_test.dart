import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('RecipeCard shows title, description, time and difficulty', (
    tester,
  ) async {
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

  testWidgets('RecipeCard shows the rating pill once a recipe is rated', (
    tester,
  ) async {
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
  // a rated recipe with a long time label. 288px (`kRecipeCardMinWidth`) is the
  // narrowest card the grid produces — it packs columns down to that width
  // before wrapping. The 2.0 text scale case is the real-world trigger — at
  // default scale the margin is thin but positive, and accessibility scaling
  // eats it. 264 is below the minimum on purpose: a container narrower than one
  // column (a 300px-wide window) still gets one card, which must degrade rather
  // than overflow.
  //
  // These assert *no overflow*, never "nothing truncates" — `flutter test`
  // renders in a fixed-width font far wider than Roboto, so a width assertion
  // here would pin the harness, not the layout (same reason as B038). That the
  // metadata row fits uncut at 288 is a screenshot check.
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
    (264, 1.0), // below the minimum — degrades, never overflows
    (kRecipeCardMinWidth, 1.0),
    (kRecipeCardMaxWidth, 1.0),
    (264, 2.0),
    (kRecipeCardMinWidth, 2.0),
    (kRecipeCardMaxWidth, 2.0),
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
      },
    );
  }

  // The banner is a fixed band, not an intrinsic one: a one-line name and a
  // two-line name must give the same height, or neighbouring cards in a row
  // start their covers at different y. Asserted through the title's centre —
  // it sits at half the band whatever the line count — plus the line count
  // itself, so a title that grew to three lines fails here rather than silently
  // eating the cover.
  group('title banner', () {
    const short = Recipe(id: '1', ownerId: 'u1', title: 'Sauce');
    const twoLine = Recipe(
      id: '2',
      ownerId: 'u1',
      title: 'Slow-Braised Short Rib Ragu',
    );
    const overLong = Recipe(
      id: '3',
      ownerId: 'u1',
      title: 'Slow-Braised Short Rib Ragu With Soft Herb Polenta And Gremolata',
    );

    // Measured from the `InkWell`, not the `RecipeCard`: `Card` insets its
    // content by a 4px margin, so the widget's own rect is not where the banner
    // starts.
    Future<(Rect content, Rect title)> pump(
      WidgetTester tester,
      Recipe recipe, {
      double scale = 1.0,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              body: Center(
                child: SizedBox(
                  width: kRecipeCardMinWidth,
                  child: RecipeCard(recipe: recipe),
                ),
              ),
            ),
          ),
        ),
      );
      return (
        tester.getRect(find.byType(InkWell)),
        tester.getRect(find.text(recipe.title)),
      );
    }

    testWidgets('is the same height for a one-line and a two-line title', (
      tester,
    ) async {
      final (content1, title1) = await pump(tester, short);
      final oneLine = title1.height;
      expect(
        title1.center.dy - content1.top,
        closeTo(kRecipeCardBannerHeight / 2, 0.01),
        reason: 'a one-line title is not centred in the fixed band',
      );

      final (content2, title2) = await pump(tester, twoLine);
      expect(
        title2.height,
        closeTo(oneLine * 2, 0.01),
        reason: 'expected the two-line fixture to wrap to exactly two lines',
      );
      expect(
        title2.center.dy - content2.top,
        closeTo(kRecipeCardBannerHeight / 2, 0.01),
        reason: 'a two-line title moved the band it shares with one-line cards',
      );
    });

    testWidgets('clamps a longer title to two lines', (tester) async {
      final (_, oneLine) = await pump(tester, short);
      final (content, title) = await pump(tester, overLong);

      expect(
        title.height,
        closeTo(oneLine.height * 2, 0.01),
        reason: 'a long title must ellipsize at two lines, not add a third',
      );
      expect(
        title.center.dy - content.top,
        closeTo(kRecipeCardBannerHeight / 2, 0.01),
      );
    });

    // The band scales with text, because a fixed 65px would clip two lines of
    // 2.0x type. What must hold at every scale is that the two cases match.
    testWidgets('stays consistent at 2.0x text scale', (tester) async {
      final (content1, title1) = await pump(tester, short, scale: 2);
      final one = title1.center.dy - content1.top;
      final (content2, title2) = await pump(tester, twoLine, scale: 2);
      final two = title2.center.dy - content2.top;
      expect(
        one,
        closeTo(two, 0.01),
        reason: 'the band stopped matching between line counts at 2.0x',
      );
      expect(tester.takeException(), isNull);
    });
  });

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

    // v2: the chip is icon-only in the title banner; the label is the tooltip.
    expect(find.byTooltip('Private'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
  });

  // v2 is a fixed-height tile (the grid passes kRecipeCardHeight as
  // mainAxisExtent). The card owns that height itself so an unbounded-height
  // parent — a Center, a Column — cannot leave the cover's Expanded unbounded
  // (B001).
  testWidgets('RecipeCard is kRecipeCardHeight tall in an unbounded parent', (
    tester,
  ) async {
    const recipe = Recipe(id: '1', ownerId: 'u1', title: 'Secret Sauce');

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: Center(
            child: SizedBox(
              width: kRecipeCardMinWidth,
              child: RecipeCard(recipe: recipe),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(RecipeCard)).height, kRecipeCardHeight);
  });

  // The placeholder's whole job is to be exactly the size of the card it
  // stands in for: a shelf that changes height when its rows arrive drags
  // every shelf below it up the page (Phase 26).
  testWidgets('RecipeCardPlaceholder matches the card at every scale', (
    tester,
  ) async {
    for (final scale in [1.0, 1.5, 2.0, 3.0]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: const Scaffold(
              body: Center(
                child: SizedBox(
                  width: kRecipeCardMinWidth,
                  child: RecipeCardPlaceholder(),
                ),
              ),
            ),
          ),
        ),
      );

      expect(
        tester.takeException(),
        isNull,
        reason: 'placeholder overflowed at ${scale}x',
      );
      expect(
        tester.getSize(find.byType(RecipeCardPlaceholder)).height,
        kRecipeCardHeight,
      );
    }
  });
}
