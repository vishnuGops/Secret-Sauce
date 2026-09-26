import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // B134 / UX-028: every imported row carries the importer's default
  // difficulty, and the card printed "Medium" on each Explore card as fact.
  testWidgets('an imported recipe shows no difficulty badge', (tester) async {
    const recipe = Recipe(
      id: '1',
      ownerId: 'u1',
      title: 'Captured Soup',
      difficulty: Difficulty.medium,
      isImported: true,
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
    await tester.pump();
    expect(find.byType(DifficultyBadge), findsNothing);
    expect(find.text('Medium'), findsNothing);
  });

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
    // 60 minutes total, in the card's compact form — the one width exception
    // to UX-043's single format (the long form clipped at 288 × 1.0, Phase 37
    // review). Asked of core's formatter rather than spelled here.
    expect(find.text(formatMinutes(60, compact: true)), findsOneWidget);
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
  // here would pin the harness, not the layout (same reason as B038).
  // "Nothing truncates" now has its own group below (B080), which asks the
  // renderer instead of measuring pixels.
  const longMeta = Recipe(
    id: '1',
    ownerId: 'u1',
    title: 'Slow-Braised Short Rib Ragu',
    description: 'Long enough to ellipsize over two lines.',
    difficulty: Difficulty.medium,
    prepMinutes: 90,
    cookMinutes: 675, // 12 h 45 min in total
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
    // B049: past the 2.0x contract the card drops its description rather than
    // overflowing. 3.0x is where iOS accessibility sizes put it.
    (264, 3.0),
    (kRecipeCardMinWidth, 3.0),
    (kRecipeCardMaxWidth, 3.0),
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

  // B049. The envelope above uses `longMeta` bare; the real worst case at 3.0x
  // also carries every optional band — the visibility chip in the banner, the
  // chef overlay on the cover, a title that clamps at two lines — because each
  // one competes for the same fixed 352px.
  group('3.0x text scale (B049)', () {
    final everything = longMeta.copyWith(
      title: 'Slow-Braised Short Rib Ragu with Gremolata and Soft Polenta',
      owner: const Profile(
        id: 'u1',
        displayName: 'Amara Baptiste-Okonkwo',
        chefTier: ChefTier.masterChef,
      ),
    );

    Future<void> pump(WidgetTester tester, double width, double scale) =>
        tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: width,
                    child: RecipeCard(recipe: everything, showVisibility: true),
                  ),
                ),
              ),
            ),
          ),
        );

    for (final width in [264.0, kRecipeCardMinWidth, kRecipeCardMaxWidth]) {
      for (final scale in [2.5, 3.0]) {
        testWidgets('every band at ${width}px, textScale $scale fits', (
          tester,
        ) async {
          await pump(tester, width, scale);
          expect(
            tester.takeException(),
            isNull,
            reason: 'overflow at ${width}px @ ${scale}x',
          );
          expect(
            tester.getSize(find.byType(RecipeCard)).height,
            kRecipeCardHeight,
            reason: 'the fix degrades the card; it must not grow it',
          );
        });
      }
    }

    testWidgets('the description is what yields, and only past 2.0x', (
      tester,
    ) async {
      await pump(tester, kRecipeCardMinWidth, kRecipeCardDescriptionMaxScale);
      expect(find.text(everything.description), findsOneWidget);

      await pump(tester, kRecipeCardMinWidth, 3.0);
      expect(find.text(everything.description), findsNothing);
      // The parts a card is *for* stay.
      expect(find.text(everything.title), findsOneWidget);
      expect(find.text(everything.difficulty.label), findsOneWidget);
      expect(find.byType(RatingPill), findsOneWidget);
    });

    testWidgets('the cover keeps some height at 3.0x', (tester) async {
      await pump(tester, kRecipeCardMinWidth, 3.0);
      // Contract change (36c): a recipe with no photo gets the category
      // colour block, not a utensil glyph — measure the block. If the cover
      // band were starved to zero it would be laid out in no space at all.
      final cover = tester.getSize(find.byType(CategoryCover));
      expect(cover.height, greaterThan(40));
    });
  });

  // B080 — the half the envelope suite above cannot see. An ellipsis is not a
  // `RenderFlex` overflow, so `takeException()` stays null while the row quietly
  // prints `5…` instead of `5.0`. That shipped, and Phase 20's deferred
  // screenshot pass found it on a real grid, exactly where the roadmap predicted
  // a widget test could not look.
  //
  // A test *can* look — just not with a ruler. `RenderParagraph` already worked
  // out whether it had to clip, so ask it instead of measuring pixels.
  //
  // **What is and is not assertable here.** `flutter test` renders in a
  // fixed-width font far wider than Roboto, so "nothing is cut at 288" is
  // simply false in the harness and true on a device — asserting it would pin
  // the font, which is what the envelope suite above refuses to do for the same
  // reason. What survives the font swap is the *shape* of the degradation, and
  // that is what B080 actually broke:
  //
  // The shape is one law: **the rating value is the last thing to go.** The row
  // gives up the time label first, then the rating count, and only then the
  // number itself — because the number is the only part that cannot be inferred
  // from the rest of the card. Stated as an implication, so it holds at widths
  // where nothing is cut and at widths where everything is; only the specific
  // inversion is forbidden.
  //
  // That law was false before the fix at real widths — at 320px/Easy the value
  // was clipped while both the time and the count came through whole — and it is
  // font-robust, which the absolute "nothing is cut at 288" claim is not. That
  // one stays a screenshot check; see ROADMAP Phase 20 for the run that found
  // this.
  group('metadata row degrades in the right order (B080)', () {
    // The card that actually broke: `Medium` is a wider badge than `Easy` or
    // `Hard`, and that extra width was what starved the rating pill.
    const rated = Recipe(
      id: '1',
      ownerId: 'u1',
      title: 'Weeknight Curry Laksa',
      description: 'Noodles in a coconut curry broth.',
      difficulty: Difficulty.medium,
      cookMinutes: 65, // 1 h 5 min
      ratingAvg: 5,
      ratingCount: 1,
    );

    bool clipped(WidgetTester tester, Finder text) =>
        tester.renderObject<RenderParagraph>(text).didExceedMaxLines;

    Future<void> pump(WidgetTester tester, Recipe recipe, double width) =>
        tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: width,
                  child: RecipeCard(recipe: recipe),
                ),
              ),
            ),
          ),
        );

    // Every width the grid actually produces, plus one below the floor.
    const widths = [264.0, kRecipeCardMinWidth, 320.0, kRecipeCardMaxWidth];

    testWidgets('the rating value is the last thing the row gives up', (
      tester,
    ) async {
      // Swept rather than sampled: the inversion showed up at some widths and
      // not others (320/Easy yes, 288/Easy no, because both were already gone
      // there), so a single width is a coin flip.
      for (final width in widths) {
        for (final difficulty in Difficulty.values) {
          for (final recipe in [
            rated.copyWith(difficulty: difficulty),
            // The synthetic worst case too: "12h 45m" and a four-digit count.
            rated.copyWith(
              difficulty: difficulty,
              cookMinutes: 765,
              ratingCount: 1250,
            ),
          ]) {
            await pump(tester, recipe, width);

            final where =
                '${width}px / ${difficulty.label} / '
                '${recipe.totalMinutes}min / count ${recipe.ratingCount}';
            expect(find.text(difficulty.label), findsOneWidget);

            final valueCut = clipped(tester, find.text('5.0'));
            final countCut = clipped(
              tester,
              find.text(' (${recipe.ratingCount})'),
            );
            // The card prints core's one duration format (UX-043): 65 ->
            // "1 h 5 min", 765 -> "12 h 45 min" — longer than the compact form
            // it replaced, which is what makes this implication worth
            // re-running rather than assuming.
            final timeLabel = formatMinutes(recipe.totalMinutes, compact: true);
            final timeCut = clipped(tester, find.text(timeLabel));

            expect(
              valueCut && !countCut,
              isFalse,
              reason:
                  'at $where the rating VALUE was clipped while the count came '
                  'through whole — that is B080 exactly, and `5…` reads as any '
                  'rating from 5.0 down',
            );
            expect(
              valueCut && !timeCut,
              isFalse,
              reason:
                  'at $where the rating VALUE was clipped while the time label '
                  'came through whole — the time is the cheapest thing in the '
                  'row to lose, so it yields first',
            );
          }
        }
      }
    });
  });

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
      // Contract change (36c): the band sits **under** the cover, so the
      // title is measured from the band's own top rather than the card's
      // (the old comment about the `Card` insetting the `InkWell` is moot —
      // the tile has no `Card` since 36c).
      return (
        tester.getRect(find.byKey(const ValueKey('recipe-card-title-band'))),
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

  // 36c review: the title band sits under the cover, so a one-line
  // description beside a two-line one used to move the neighbour's cover and
  // title by a line. The footer reserves two description lines, always.
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'neighbouring titles line up whatever the description, $scale×',
      (tester) async {
        const short = Recipe(
          id: 'a',
          ownerId: 'o',
          title: 'Soup',
          description: 'Short.',
        );
        const long = Recipe(
          id: 'b',
          ownerId: 'o',
          title: 'Stew',
          description:
              'A long description that certainly wraps onto a second line at '
              'the narrowest card width, and then some more words besides.',
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: const Scaffold(
                body: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: kRecipeCardMinWidth,
                      child: RecipeCard(recipe: short),
                    ),
                    SizedBox(
                      width: kRecipeCardMinWidth,
                      child: RecipeCard(recipe: long),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        final bands = find.byKey(const ValueKey('recipe-card-title-band'));
        expect(bands, findsNWidgets(2));
        expect(
          tester.getTopLeft(bands.at(0)).dy,
          tester.getTopLeft(bands.at(1)).dy,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  // UX-013. The card's `InkWell` painted focus on the transparent Material
  // *under* the cover, so a keyboard user tabbing through a grid saw focus on
  // a footer strip at best (WCAG 2.4.7). `InteractiveTile` paints it over the
  // whole tile instead — without moving a pixel of the geometry the envelope
  // suites above pin, and without getting between the chef badge and a tap.
  group('interaction states over the cover (UX-013)', () {
    const owner = Profile(
      id: 'u1',
      displayName: 'Amara Baptiste-Okonkwo',
      chefTier: ChefTier.masterChef,
    );

    Future<void> pump(
      WidgetTester tester, {
      Recipe recipe = longMeta,
      VoidCallback? onTap,
      VoidCallback? onChefTap,
      double scale = 1.0,
    }) => tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: kRecipeCardMinWidth,
                child: RecipeCard(
                  recipe: recipe,
                  onTap: onTap ?? () {},
                  onChefTap: onChefTap,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    Future<void> tabToCard(WidgetTester tester) async {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }

    for (final scale in [1.0, 2.0]) {
      testWidgets('Tab shows a ring over the whole tile, ${scale}x', (
        tester,
      ) async {
        await pump(tester, scale: scale);
        final before = tester.getRect(find.byType(RecipeCard));
        expect(find.byKey(kTileFocusRingKey), findsNothing);

        await tabToCard(tester);

        final ring = find.byKey(kTileFocusRingKey);
        expect(ring, findsOneWidget, reason: 'keyboard focus is invisible');
        // Over the cover, not only the text under it: the ring spans the
        // tile and is painted after (above) the cover in the same Stack.
        expect(tester.getRect(ring), before);
        expect(
          tester.getRect(find.byType(CategoryCover)).top,
          tester.getRect(ring).top,
        );
        final border =
            (tester.widget<DecoratedBox>(ring).decoration as BoxDecoration)
                    .border!
                as Border;
        expect(border.top.color, AppTheme.light().colorScheme.primary);
        expect(border.top.width, kTileFocusRingWidth);
        // Geometry is untouched (Preserve: the fixed 352 tile).
        expect(tester.getRect(find.byType(RecipeCard)), before);
        expect(before.height, kRecipeCardHeight);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a focus that did not come from the keyboard shows no ring', (
      tester,
    ) async {
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTouch;
      addTearDown(
        () =>
            FocusManager.instance.highlightStrategy =
                FocusHighlightStrategy.automatic,
      );
      await pump(tester);
      Focus.of(tester.element(find.byType(CategoryCover))).requestFocus();
      await tester.pump();
      expect(find.byKey(kTileFocusRingKey), findsNothing);
    });

    testWidgets('hover washes the cover too, not just the text band', (
      tester,
    ) async {
      await pump(tester);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.byType(CategoryCover)));
      await tester.pump();

      final wash = find.byKey(kTileInkWashKey);
      expect(wash, findsOneWidget);
      expect(
        tester
            .getRect(wash)
            .contains(tester.getCenter(find.byType(CategoryCover))),
        isTrue,
      );
    });

    testWidgets('the chef badge still takes its own tap with the ring up', (
      tester,
    ) async {
      var cardTaps = 0;
      var chefTaps = 0;
      await pump(
        tester,
        recipe: longMeta.copyWith(owner: owner),
        onTap: () => cardTaps++,
        onChefTap: () => chefTaps++,
      );
      // Focus the card itself (the badge is a focus stop of its own, so Tab
      // order is not what this test is about), from the keyboard.
      await tester.sendKeyEvent(LogicalKeyboardKey.shiftLeft);
      Focus.of(tester.element(find.byType(CategoryCover))).requestFocus();
      await tester.pump();
      expect(find.byKey(kTileFocusRingKey), findsOneWidget);

      await tester.tap(find.byType(ChefBadge));
      await tester.pump();
      expect(chefTaps, 1, reason: 'the overlay swallowed the badge tap');
      expect(cardTaps, 0);

      // And the rest of the cover still opens the recipe.
      await tester.tapAt(
        tester.getRect(find.byType(CategoryCover)).topLeft +
            const Offset(40, 40),
      );
      await tester.pump();
      expect(cardTaps, 1);
    });
  });
}
