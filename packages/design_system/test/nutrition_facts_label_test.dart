// Phase 28. Three contracts, and the third is the one that has bitten twice:
//
//   * a row with no value renders nothing, so a label carrying only calories is
//     a short label rather than a column of dashes;
//   * the `% Daily Value` column states the FDA arithmetic (Gotcha 19's rule in
//     miniature — the widget explains a number, so the number needs a test);
//   * the ENVELOPE. The rails hand this widget 320 / 358 / 493 px, and Gotcha 26
//     says an envelope is only the widths a widget has actually been pumped at.
//     Every combination of those and {1.0, 2.0} text scale is asserted here
//     BEFORE either detail layout gets to reuse it.
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Chosen so all eight percentages are DISTINCT (13/20/10/26/12/25/30/50) —
/// two rows landing on the same `%` makes `findsOneWidget` fail for a reason
/// that has nothing to do with the widget.
const _full = RecipeNutrition(
  calories: 240,
  totalFatG: 10,
  saturatedFatG: 4,
  transFatG: 0,
  cholesterolMg: 30,
  sodiumMg: 600,
  totalCarbsG: 33,
  dietaryFiberG: 7,
  totalSugarsG: 12,
  addedSugarsG: 15,
  proteinG: 25,
);

Widget _host(
  Widget child, {
  double width = 358,
  double textScale = 1.0,
  Brightness brightness = Brightness.light,
}) => MaterialApp(
  theme: brightness == Brightness.light ? AppTheme.light() : AppTheme.dark(),
  home: Scaffold(
    body: MediaQuery(
      data: MediaQueryData(
        size: Size(width, 2400),
        textScaler: TextScaler.linear(textScale),
      ),
      // The rail is a fixed-width column inside a scroll view, so the label is
      // width-constrained and height-free — the same shape it gets in both
      // detail layouts.
      child: SingleChildScrollView(child: SizedBox(width: width, child: child)),
    ),
  ),
);

void main() {
  testWidgets('draws the label chrome', (tester) async {
    await tester.pumpWidget(
      _host(
        const NutritionFactsLabel(
          nutrition: _full,
          servings: 4,
          baseServings: 4,
        ),
      ),
    );

    expect(find.text('Nutrition Facts'), findsOneWidget);
    expect(find.text('Amount per serving'), findsOneWidget);
    expect(find.text('% Daily Value*'), findsOneWidget);
    expect(find.text('Calories'), findsOneWidget);
    expect(find.text('240'), findsOneWidget);
    expect(
      find.textContaining('based on a 2,000 calorie diet'),
      findsOneWidget,
    );
  });

  testWidgets('omits the rows with no value', (tester) async {
    await tester.pumpWidget(
      _host(
        const NutritionFactsLabel(
          nutrition: RecipeNutrition(calories: 180, proteinG: 6),
          servings: 2,
          baseServings: 2,
        ),
      ),
    );

    expect(find.textContaining('Protein'), findsOneWidget);
    // Not "Total Fat —", not "Total Fat 0 g". Absent.
    expect(find.textContaining('Total Fat'), findsNothing);
    expect(find.textContaining('Sodium'), findsNothing);
    expect(find.textContaining('Cholesterol'), findsNothing);
  });

  testWidgets('a zero IS a value and renders', (tester) async {
    await tester.pumpWidget(
      _host(
        const NutritionFactsLabel(
          nutrition: RecipeNutrition(transFatG: 0),
          servings: 1,
          baseServings: 1,
        ),
      ),
    );

    expect(find.textContaining('Trans Fat 0 g'), findsOneWidget);
  });

  testWidgets('%DV states the FDA arithmetic', (tester) async {
    await tester.pumpWidget(
      _host(
        const NutritionFactsLabel(
          nutrition: _full,
          servings: 4,
          baseServings: 4,
        ),
      ),
    );

    expect(find.text('13%'), findsOneWidget); // 10 g fat / 78 g
    expect(find.text('20%'), findsOneWidget); // 4 g sat / 20 g
    expect(find.text('10%'), findsOneWidget); // 30 mg cholesterol / 300 mg
    expect(find.text('26%'), findsOneWidget); // 600 mg sodium / 2,300 mg
    expect(find.text('12%'), findsOneWidget); // 33 g carbs / 275 g
    expect(find.text('25%'), findsOneWidget); // 7 g fibre / 28 g
    expect(find.text('30%'), findsOneWidget); // 15 g added sugars / 50 g
    expect(find.text('50%'), findsOneWidget); // 25 g protein / 50 g
    // Trans fat and total sugars carry values but no percentage — 11 fields,
    // 8 percentages.
    expect(find.textContaining('Trans Fat 0 g'), findsOneWidget);
    expect(find.textContaining('Total Sugars 12 g'), findsOneWidget);
  });

  testWidgets('the three nutrients with no daily value print no %', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const NutritionFactsLabel(
          nutrition: RecipeNutrition(calories: 100, transFatG: 2),
          servings: 1,
          baseServings: 1,
        ),
      ),
    );

    // Trans fat has no established DV, so its row carries a value and no
    // percentage; nothing on the label should read as a percentage at all.
    expect(find.textContaining('%'), findsOneWidget); // the column header only
    expect(find.text('% Daily Value*'), findsOneWidget);
  });

  testWidgets('the batch line is calories × the SCALED servings', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const NutritionFactsLabel(
          nutrition: _full,
          servings: 8,
          baseServings: 4,
        ),
      ),
    );

    // Per-serving values do NOT move — that is the whole decision.
    expect(find.text('240'), findsOneWidget);
    expect(
      find.textContaining('8 servings · 1,920 kcal total'),
      findsOneWidget,
    );
    // And the label says what basis it is written for once the two differ.
    expect(find.textContaining('this recipe is written for 4'), findsOneWidget);
  });

  testWidgets('says nothing about a basis when the servings match', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const NutritionFactsLabel(
          nutrition: _full,
          servings: 4,
          baseServings: 4,
        ),
      ),
    );

    expect(find.textContaining('this recipe is written for'), findsNothing);
  });

  testWidgets('uses theme ink, not a hard-coded black', (tester) async {
    await tester.pumpWidget(
      _host(
        const NutritionFactsLabel(
          nutrition: _full,
          servings: 4,
          baseServings: 4,
        ),
        brightness: Brightness.dark,
      ),
    );

    final scheme = AppTheme.dark().colorScheme;
    final title = tester.widget<Text>(find.text('Nutrition Facts'));
    expect(title.style?.color, scheme.onSurface);
    expect(title.style?.color, isNot(Colors.black));
  });

  // Gotcha 26 / Gotcha 13: the two-axis matrix, not one width and not one
  // scale. 320 is the narrowest rail a small phone produces, 358 is compact
  // v2's content box on a 390px phone, 493 is the column the expanded page
  // hands the rail.
  for (final width in [320.0, 358.0, 493.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('fits ${width.toInt()}px at ${scale}x', (tester) async {
        await tester.pumpWidget(
          _host(
            const NutritionFactsLabel(
              nutrition: _full,
              servings: 12,
              baseServings: 4,
            ),
            width: width,
            textScale: scale,
          ),
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
}
