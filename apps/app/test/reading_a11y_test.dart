// The reading surfaces as a screen reader meets them (UX-014), plus the two
// formatting rules the rail and the method list print through (UX-023 fractions,
// UX-043 durations) and the nutrition empty state's copy (UX-046).
//
// `RailPanel` and `MethodColumn` are pumped on their own rather than through the
// whole detail screen: everything they read is a plain `StateProvider`, so no
// repository fake is needed, and the semantics tree stays small enough that a
// node found by `getSemantics` is unambiguously the row under test.
import 'package:app/features/recipe_detail/method_column.dart';
import 'package:app/features/recipe_detail/rail_panel.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _kLongTemperature = '220°C / 425°F fan';

const _recipe = Recipe(
  id: 'r1',
  ownerId: 'o',
  title: 'Slow-roast shoulder',
  servings: 4,
  ingredientGroups: [
    IngredientGroup(
      id: 'ig1',
      recipeId: 'r1',
      name: 'Rub',
      ingredients: [
        Ingredient(
          id: 'i1',
          groupId: 'ig1',
          quantity: 0.5,
          unit: 'cup',
          name: 'brown sugar',
        ),
        Ingredient(
          id: 'i2',
          groupId: 'ig1',
          quantity: 0.333,
          unit: 'cup',
          name: 'smoked paprika',
        ),
      ],
    ),
    IngredientGroup(
      id: 'ig2',
      recipeId: 'r1',
      name: 'Roast',
      ingredients: [
        Ingredient(
          id: 'i3',
          groupId: 'ig2',
          quantity: 1.5,
          unit: 'kg',
          name: 'pork shoulder',
        ),
      ],
    ),
  ],
  stepGroups: [
    StepGroup(
      id: 'sg1',
      recipeId: 'r1',
      name: 'Roast',
      steps: [
        RecipeStep(
          id: 's1',
          groupId: 'sg1',
          text: 'Roast the shoulder, covered, until it pulls apart.',
          durationMinutes: 90,
          temperature: _kLongTemperature,
        ),
        RecipeStep(id: 's2', groupId: 'sg1', text: 'Rest it under foil.'),
      ],
    ),
  ],
);

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(1000, 2000),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('ingredients rail', () {
    testWidgets('the kicker and group names are headings', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, const RailPanel(recipe: _recipe));

      expect(
        tester.getSemantics(find.text('INGREDIENTS')),
        isSemantics(isHeader: true),
      );
      expect(
        tester.getSemantics(find.text('RUB')),
        isSemantics(isHeader: true),
      );
      handle.dispose();
    });

    testWidgets('a row is one checkable node that says when it is ticked', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, const RailPanel(recipe: _recipe));

      final row = find.text('Brown sugar');
      expect(
        tester.getSemantics(row),
        isSemantics(hasCheckedState: true, isChecked: false),
      );
      // Quantity and name are one announcement, not two stops.
      // Contract change (Phase 38): the quantity is heard in words — a
      // reader said `1 1⁄3` as "fraction slash" — through core's
      // `spokenQuantity`, a transform of the same printed label.
      expect(tester.getSemantics(row).label, contains('1 half cup'));
      expect(tester.getSemantics(row).label, contains('Brown sugar'));

      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(row),
        isSemantics(hasCheckedState: true, isChecked: true),
      );
      handle.dispose();
    });

    testWidgets('the tab chips say which pane is showing', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, const RailPanel(recipe: _recipe));

      expect(
        tester.getSemantics(find.text('Ingredients')),
        isSemantics(isSelected: true),
      );
      expect(
        tester.getSemantics(find.text('Nutrition')),
        isSemantics(isSelected: false),
      );

      await tester.tap(find.text('Nutrition'));
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(find.text('Nutrition')),
        isSemantics(isSelected: true),
      );
      // The kicker follows the tab, and is still a heading.
      expect(
        tester.getSemantics(find.text('NUTRITION')),
        isSemantics(isHeader: true),
      );
      handle.dispose();
    });

    // UX-023: a cook reads ½ and ⅓, not 0.5 and 0.33 — and metric stays
    // decimal. Through the one chain both rails use (B066).
    testWidgets('the gutter prints fractions for cups, decimals for kg', (
      tester,
    ) async {
      await _pump(tester, const RailPanel(recipe: _recipe));

      expect(find.text('½ cup'), findsOneWidget);
      expect(find.text('1⁄3 cup'), findsOneWidget);
      expect(find.text('1.5 kg'), findsOneWidget);
      expect(find.text('0.5 cup'), findsNothing);
      expect(find.text('0.33 cup'), findsNothing);
    });

    // UX-046: the copy said auto-calculation was not built; Phase 29c built it.
    testWidgets('the nutrition empty state names both ways to add a label', (
      tester,
    ) async {
      await _pump(tester, const RailPanel(recipe: _recipe));
      await tester.tap(find.text('Nutrition'));
      await tester.pumpAndSettle();

      expect(find.text('No nutrition info available'), findsOneWidget);
      expect(find.textContaining('Automatic'), findsOneWidget);
      expect(find.textContaining('entered by whoever'), findsNothing);
    });
  });

  group('method column', () {
    testWidgets('the kicker and step-group names are headings', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, const MethodColumn(recipe: _recipe));

      expect(
        tester.getSemantics(find.text('METHOD')),
        isSemantics(isHeader: true),
      );
      expect(
        tester.getSemantics(find.text('ROAST')),
        isSemantics(isHeader: true),
      );
      handle.dispose();
    });

    testWidgets('a step is one checkable node labelled with its number', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, const MethodColumn(recipe: _recipe));

      final step = find.text('Rest it under foil.');
      final node = tester.getSemantics(step);
      expect(node, isSemantics(hasCheckedState: true, isChecked: false));
      expect(node.label, contains('Step 2'));
      expect(node.label, contains('Rest it under foil.'));

      await tester.tap(step);
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(step),
        isSemantics(hasCheckedState: true, isChecked: true),
      );
      handle.dispose();
    });

    // UX-043 + UX-024's other half: the reading page keeps its small chips,
    // and its durations read the one way.
    testWidgets('step chips stay small and say 1 h 30 min', (tester) async {
      await _pump(tester, const MethodColumn(recipe: _recipe));

      expect(find.text('90 min'), findsNothing);
      final duration = tester.widget<Text>(find.text('1 h 30 min')).style;
      final temperature =
          tester.widget<Text>(find.text(_kLongTemperature)).style;
      expect(duration?.fontSize, lessThan(16));
      expect(temperature?.fontSize, lessThan(16));
    });

    testWidgets('a done step keeps its duration in the same format', (
      tester,
    ) async {
      await _pump(tester, const MethodColumn(recipe: _recipe));
      await tester.tap(find.text(_recipe.stepGroups.first.steps.first.text));
      await tester.pumpAndSettle();
      expect(find.text('1 h 30 min'), findsOneWidget);
    });
  });

  // The two panels this file changed (Semantics wrappers around the rows),
  // pumped across the widths they are placed at and both text scales.
  group('envelope', () {
    for (final width in [390.0, 600.0, 1000.0, 1440.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('no overflow at ${width}px, textScale $scale', (
          tester,
        ) async {
          tester.view.physicalSize = Size(width, 3000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            ProviderScope(
              child: MaterialApp(
                theme: AppTheme.light(),
                builder:
                    (context, child) => MediaQuery(
                      data: MediaQuery.of(
                        context,
                      ).copyWith(textScaler: TextScaler.linear(scale)),
                      child: child!,
                    ),
                home: const Scaffold(
                  body: SingleChildScrollView(
                    child: Column(
                      children: [
                        RailPanel(recipe: _recipe),
                        MethodColumn(recipe: _recipe),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}
