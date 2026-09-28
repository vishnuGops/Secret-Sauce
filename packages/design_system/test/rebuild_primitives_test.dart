import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Phase 36c primitives: the no-photo colour block, tag pills, the
/// nutrition summary and the category tile — each at the widths its callers
/// hand it × 1.0 / 2.0 text scale (Gotchas 13, 22, 26), plus the contracts a
/// screen relies on.
void main() {
  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    double width = 358,
    double scale = 1.0,
    Brightness brightness = Brightness.light,
  }) => tester.pumpWidget(
    MaterialApp(
      theme:
          brightness == Brightness.light ? AppTheme.light() : AppTheme.dark(),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Scaffold(
          body: Center(child: SizedBox(width: width, child: child)),
        ),
      ),
    ),
  );

  group('CategoryCover', () {
    for (final height in [40.0, 120.0, 240.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('fits at ${height}px tall, ${scale}x', (tester) async {
          await pump(
            tester,
            SizedBox(
              height: height,
              child: const CategoryCover(category: 'Dessert'),
            ),
            width: 288,
            scale: scale,
          );
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('names the category, never the dish (no duplicate title)', (
      tester,
    ) async {
      await pump(
        tester,
        const SizedBox(height: 200, child: CategoryCover(category: 'Dessert')),
      );
      expect(find.text('DESSERT'), findsOneWidget);
    });

    testWidgets('is colour alone when there is no room for the label', (
      tester,
    ) async {
      await pump(
        tester,
        const SizedBox(height: 40, child: CategoryCover(category: 'Dessert')),
        scale: 2.0,
      );
      expect(find.text('DESSERT'), findsNothing);
    });

    testWidgets('a recipe card with no photo draws the block', (tester) async {
      const recipe = Recipe(
        id: 'r',
        ownerId: 'o',
        title: 'Lemon Tart',
        category: 'Dessert',
      );
      await pump(
        tester,
        const RecipeCard(recipe: recipe),
        width: kRecipeCardMinWidth,
      );
      expect(find.byType(CategoryCover), findsOneWidget);
      expect(find.text('Lemon Tart'), findsOneWidget);
    });
  });

  group('RecipeCard rank ribbon', () {
    const recipe = Recipe(id: 'r', ownerId: 'o', title: 'Ragu');
    for (final entry
        in {1: '1st', 2: '2nd', 3: '3rd', 4: '4th', 11: '11th'}.entries) {
      testWidgets('rank ${entry.key} reads ${entry.value}', (tester) async {
        await pump(
          tester,
          RecipeCard(recipe: recipe, rank: entry.key),
          width: kRecipeCardMinWidth,
          scale: 2.0,
        );
        expect(find.text(entry.value), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('an unranked card draws no ribbon', (tester) async {
      await pump(tester, const RecipeCard(recipe: recipe), width: 288);
      expect(find.text('1st'), findsNothing);
    });
  });

  group('TagPill', () {
    for (final width in [120.0, 358.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('ellipsizes, never overflows, at $width × $scale', (
          tester,
        ) async {
          await pump(
            tester,
            const Align(
              alignment: Alignment.centerLeft,
              child: TagPill(label: 'Middle Eastern', icon: Icons.public),
            ),
            width: width,
            scale: scale,
          );
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  group('NutritionSummary', () {
    const full = RecipeNutrition(
      calories: 1618,
      totalFatG: 34.8,
      totalCarbsG: 120.5,
      proteinG: 36.3,
    );

    for (final width in [320.0, 358.0, 493.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('wraps without overflow at $width × $scale', (
          tester,
        ) async {
          await pump(
            tester,
            const NutritionSummary(nutrition: full),
            width: width,
            scale: scale,
          );
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('prints no %DV for calories and a %DV for the rest', (
      tester,
    ) async {
      await pump(tester, const NutritionSummary(nutrition: full));
      expect(find.text('Calories'), findsOneWidget);
      expect(find.text('1618'), findsOneWidget);
      // 34.8 / 78 = 45%, 120.5 / 275 = 44%, 36.3 / 50 = 73%.
      expect(find.text('45%'), findsOneWidget);
      expect(find.text('44%'), findsOneWidget);
      expect(find.text('73%'), findsOneWidget);
    });

    testWidgets('a figure the label lacks is skipped; none at all is empty', (
      tester,
    ) async {
      await pump(
        tester,
        const NutritionSummary(nutrition: RecipeNutrition(calories: 400)),
      );
      expect(find.text('Protein'), findsNothing);
      await pump(tester, const NutritionSummary(nutrition: RecipeNutrition()));
      expect(find.text('Calories'), findsNothing);
    });
  });

  group('CategoryTile', () {
    for (final width in [140.0, 288.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('fits at $width × $scale', (tester) async {
          await pump(
            tester,
            const CategoryTile(category: 'Breakfast', selected: true),
            width: width,
            scale: scale,
          );
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('carries button + selected semantics and fires onTap', (
      tester,
    ) async {
      var taps = 0;
      await pump(
        tester,
        CategoryTile(category: 'Main', selected: true, onTap: () => taps++),
      );
      final handle = tester.ensureSemantics();
      expect(
        tester.getSemantics(find.byType(CategoryTile)),
        matchesSemantics(
          label: 'Main',
          isButton: true,
          isSelected: true,
          hasSelectedState: true,
          hasTapAction: true,
        ),
      );
      handle.dispose();
      await tester.tap(find.byType(CategoryTile));
      expect(taps, 1);
    });

    testWidgets('a label names the tile; the category only picks the colour', (
      tester,
    ) async {
      // Discover's `Starters` tile stands for Appetizer / Snack / Side Dish …
      // and takes Appetizer's block — the palette has no `starters` key.
      await pump(
        tester,
        const CategoryTile(category: 'Appetizer', label: 'Starters'),
      );
      expect(find.text('Starters'), findsOneWidget);
      expect(find.text('Appetizer'), findsNothing);
      final handle = tester.ensureSemantics();
      expect(tester.getSemantics(find.byType(CategoryTile)).label, 'Starters');
      handle.dispose();
      final material = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(CategoryTile),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(material.color, AppPalette.light.category('Appetizer').background);
    });

    group('with a photo', () {
      final photo = MemoryImage(Uint8List.fromList(_kTransparentPng));

      for (final width in [140.0, 288.0]) {
        for (final scale in [1.0, 2.0]) {
          testWidgets('fits at $width × $scale', (tester) async {
            await pump(
              tester,
              CategoryTile(category: 'Breakfast', image: photo, selected: true),
              width: width,
              scale: scale,
            );
            expect(tester.takeException(), isNull);
          });
        }
      }

      testWidgets('the photo is decorative and does not swallow the tap', (
        tester,
      ) async {
        var taps = 0;
        await pump(
          tester,
          CategoryTile(category: 'Main', image: photo, onTap: () => taps++),
        );
        final handle = tester.ensureSemantics();
        expect(
          tester.getSemantics(find.byType(CategoryTile)),
          matchesSemantics(
            label: 'Main',
            isButton: true,
            hasSelectedState: true,
            hasTapAction: true,
          ),
        );
        handle.dispose();
        // The ink layer sits above the photo and the scrim, so a tap on the
        // photo's side of the tile still lands.
        await tester.tapAt(
          tester.getTopRight(find.byType(CategoryTile)) + const Offset(-8, 8),
        );
        expect(taps, 1);
      });

      testWidgets('the block colour stays underneath the photo', (
        tester,
      ) async {
        await pump(tester, CategoryTile(category: 'Salad', image: photo));
        final material = tester.widget<Material>(
          find
              .descendant(
                of: find.byType(CategoryTile),
                matching: find.byType(Material),
              )
              .first,
        );
        expect(material.color, AppPalette.light.category('Salad').background);
        expect(find.byType(Image), findsOneWidget);
      });
    });
  });
}

/// A 1×1 transparent PNG — enough for an [Image] to lay out in a test.
const List<int> _kTransparentPng = [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];
