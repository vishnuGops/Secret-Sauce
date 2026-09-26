// Regression cover for B035: the editor used to model a step as its text and
// nothing else, so `temperature`, `duration_minutes`, `tip` and `image_url`
// (and an ingredient's `note` / `is_optional`) were unreachable when creating a
// recipe *and* silently erased when editing one that had them — `update()`
// deletes the groups and re-inserts whatever `toModel()` produces.
//
// The round-trip group is the load-bearing half: it fails if any field is
// dropped between the core model and the editor's mutable draft types. The
// widget group covers the envelope the new inputs have to survive (Gotcha 13).
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:app/features/recipe_editor/edit_models.dart';
import 'package:app/features/recipe_editor/ingredients_editor.dart';
import 'package:app/features/recipe_editor/recipe_editor_providers.dart';
import 'package:app/features/recipe_editor/recipe_editor_screen.dart';
import 'package:app/features/recipe_editor/steps_editor.dart';
import 'package:app/routing/app_router.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// A real 1x1 PNG. `Image.memory` decodes whatever the picker handed it, so the
/// photo tests cannot get away with dummy bytes — an undecodable buffer is
/// reported as a framework error and fails the pump that follows.
final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
  '+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);

/// A step that uses every column the schema gives it.
const _fullStep = RecipeStep(
  id: 's1',
  groupId: 'g1',
  stepOrder: 3,
  text: 'Bake until the edges are set but the centre still looks underdone.',
  imageUrl: 'https://example.test/step.jpg',
  durationMinutes: 12,
  temperature: '180°C fan',
  tip: 'Rotate the tray halfway through.',
  sortOrder: 3,
);

const _fullIngredient = Ingredient(
  id: 'i1',
  groupId: 'g1',
  quantity: 1.25,
  unit: 'cups',
  name: 'plain flour',
  note: 'sifted',
  isOptional: true,
  sortOrder: 2,
  foodId: 'all-purpose-flour',
);

Widget _app({double textScale = 1.0}) => ProviderScope(
  overrides: [
    // The nutrition panel's Automatic mode reaches the registry (29c); the
    // stub keeps every test off the network.
    foodRepositoryProvider.overrideWithValue(_StubFoodRepository()),
  ],
  child: MaterialApp(
    theme: AppTheme.light(),
    // `builder`, not a MediaQuery around `home` — same reason as the chefs
    // tests: overlays sit above the Navigator.
    builder:
        (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
    home: const RecipeEditorScreen(),
  ),
);

void main() {
  group('draft round-trip', () {
    test('EditStep preserves every field of a step it loaded', () {
      final draft = EditStep.fromModel(_fullStep);
      final out = draft.toModel(3);

      expect(out.text, _fullStep.text);
      expect(out.durationMinutes, 12);
      expect(out.temperature, '180°C fan');
      expect(out.tip, _fullStep.tip);
      // No per-step image picker yet — the value still has to survive a save.
      expect(out.imageUrl, _fullStep.imageUrl);
    });

    test('EditIngredient preserves note, isOptional and the food link', () {
      final draft = EditIngredient.fromModel(_fullIngredient);
      final out = draft.toModel(2);

      expect(out.quantity, 1.25);
      expect(out.unit, 'cups');
      expect(out.name, 'plain flour');
      expect(out.note, 'sifted');
      expect(out.isOptional, isTrue);
      // Phase 29b: the invisible registry link survives the draft round-trip —
      // dropping it here is how an edit would silently unlink every ingredient
      // (the exact B035 failure, one field later).
      expect(out.foodId, 'all-purpose-flour');
    });

    test('clearing the chip clears the link on the next save', () {
      final draft = EditIngredient.fromModel(_fullIngredient);
      draft.foodId = null; // what the chip's delete does
      expect(draft.toModel(0).foodId, isNull);
    });

    test('a whole step group survives load -> save unchanged', () {
      const group = StepGroup(
        id: 'g1',
        recipeId: 'r1',
        name: 'Bake',
        steps: [_fullStep],
      );

      final out = EditStepGroup.fromModel(group).toModel();

      expect(out.steps, hasLength(1));
      expect(out.steps.single.temperature, _fullStep.temperature);
      expect(out.steps.single.durationMinutes, _fullStep.durationMinutes);
      expect(out.steps.single.tip, _fullStep.tip);
      expect(out.steps.single.imageUrl, _fullStep.imageUrl);
    });

    // The per-step picker (Phase 9 carry-over). `image_url` was carried through
    // verbatim because nothing could set it; now that the control exists, both
    // directions have to survive the same round-trip.
    test('a photo set on the draft reaches the saved step', () {
      final draft = EditStep.fromModel(_fullStep);
      expect(draft.hasImage, isTrue);

      // What the preview's corner button does.
      draft.clearImage();
      expect(draft.hasImage, isFalse);
      expect(draft.toModel(0).imageUrl, isNull);

      // What `_uploadStepImages` writes back once the upload has landed.
      draft.imageUrl = 'https://cdn.test/me/step_1.jpg';
      expect(draft.hasImage, isTrue);
      expect(draft.toModel(0).imageUrl, 'https://cdn.test/me/step_1.jpg');
    });

    test('a pending pick shows as an image but stores nothing on its own', () {
      final draft = EditStep()..pendingImageBytes = _png;

      expect(draft.hasImage, isTrue);
      // Bytes are not a URL: the save uploads first, and a `toModel()` taken
      // before that must not invent a link.
      expect(draft.toModel(0).imageUrl, isNull);
    });

    test('empty detail fields round-trip to null, not empty strings', () {
      final out = EditStep().toModel(0);

      expect(out.durationMinutes, isNull);
      expect(out.temperature, isNull);
      expect(out.tip, isNull);
      expect(out.imageUrl, isNull);
    });

    // Phase 28. Same obligation as the two above: `save_recipe` writes the
    // whole `nutrition` object, so a field the draft drops is a field the next
    // save deletes.
    test('EditNutrition preserves all 11 fields', () {
      const full = RecipeNutrition(
        calories: 240,
        totalFatG: 10,
        saturatedFatG: 4.5,
        transFatG: 0,
        cholesterolMg: 30,
        sodiumMg: 600,
        totalCarbsG: 33,
        dietaryFiberG: 7,
        totalSugarsG: 12,
        addedSugarsG: 15,
        proteinG: 25,
      );

      final out = EditNutrition.fromModel(full).toModel();

      expect(out, full);
    });

    test('all-empty becomes null, never an empty object', () {
      expect(EditNutrition().toModel(), isNull);
      expect(EditNutrition.fromModel(null).toModel(), isNull);
      // The distinction that matters: `{}` would render a label with a
      // masthead and no rows; null renders the empty state.
      expect(
        EditNutrition.fromModel(const RecipeNutrition()).toModel(),
        isNull,
      );
    });

    test('one value is enough to produce a label', () {
      final draft = EditNutrition();
      draft.calories.text = '180';
      expect(draft.toModel(), const RecipeNutrition(calories: 180));
      expect(draft.hasValues, isTrue);
    });

    test('a numeric round-trip does not gain a decimal point', () {
      // Postgres hands back `10.0`; the box the user typed `10` into must not
      // start saying `10.0`.
      final draft = EditNutrition.fromModel(
        const RecipeNutrition(calories: 10),
      );
      expect(draft.calories.text, '10');
      expect(
        EditNutrition.fromModel(
          const RecipeNutrition(saturatedFatG: 4.5),
        ).saturatedFat.text,
        '4.5',
      );
    });

    // Mirrors `_Field`'s validator. The screen reads this to decide whether a
    // blocked save was the nutrition panel's fault, so the two predicates
    // agreeing is the contract — not an implementation detail.
    test('hasInvalidEntry matches what the field validator rejects', () {
      final draft = EditNutrition();
      expect(draft.hasInvalidEntry, isFalse);

      draft.calories.text = '  '; // blank is not invalid, it is absent
      expect(draft.hasInvalidEntry, isFalse);

      draft.calories.text = '1/2'; // tryParse -> null
      expect(draft.hasInvalidEntry, isTrue);

      draft.calories.text = '-3';
      expect(draft.hasInvalidEntry, isTrue);

      draft.calories.text = '1.5';
      expect(draft.hasInvalidEntry, isFalse);
      // Zero is a legitimate label value (0 g trans fat is a printed row).
      draft.transFat.text = '0';
      expect(draft.hasInvalidEntry, isFalse);
    });

    test('load() refills the SAME controllers, so dispose stays wired', () {
      final draft = EditNutrition();
      final calories = draft.calories;
      draft.load(const RecipeNutrition(calories: 99));
      expect(identical(draft.calories, calories), isTrue);
      expect(calories.text, '99');
      // And loading null clears rather than leaving the previous recipe's
      // numbers behind.
      draft.load(null);
      expect(calories.text, '');
      expect(draft.hasValues, isFalse);
    });

    test('details start revealed when the loaded row already uses them', () {
      expect(EditStep.fromModel(_fullStep).showDetails, isTrue);
      expect(EditIngredient.fromModel(_fullIngredient).showDetails, isTrue);
      // A blank row stays collapsed so the common case is not noisier.
      expect(EditStep().showDetails, isFalse);
      expect(EditIngredient().showDetails, isFalse);
    });
  });

  group('editor inputs', () {
    // The form is one scroll view, so every field is built — but a tap still
    // needs its target on screen. A viewport tall enough to show the whole
    // form beats scripting scrolls.
    void sizeView(WidgetTester tester, double width) {
      tester.view.physicalSize = Size(width, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    // UX-035 put the step timer in plain sight; temperature and tip stay
    // behind the disclosure.
    testWidgets('step details reveal temperature and tip', (tester) async {
      sizeView(tester, 800);
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();

      expect(find.text('Time'), findsOneWidget);
      expect(find.text('Temperature'), findsNothing);

      await tester.tap(find.byTooltip('Temperature & tip'));
      await tester.pumpAndSettle();

      expect(find.text('Temperature'), findsOneWidget);
      expect(find.text('Tip'), findsOneWidget);
    });

    testWidgets('ingredient details reveal note and the optional toggle', (
      tester,
    ) async {
      sizeView(tester, 800);
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();

      expect(find.text('Optional'), findsNothing);

      await tester.tap(find.byTooltip('Note & optional'));
      await tester.pumpAndSettle();

      expect(find.text('Note'), findsOneWidget);
      expect(find.text('Optional'), findsOneWidget);

      // The toggle has to reach the draft, not just paint — this is the field
      // that used to be unreachable from the editor entirely.
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
    });

    // 32a2: `ingredients_quantity_positive` makes a zero or negative quantity
    // unstorable, so the field has to say so before the save does — a check
    // constraint surfaces as a generic failure, and B076 is the reason the value
    // matters: a negative quantity *subtracted* from an estimated label.
    testWidgets('a non-positive quantity blocks Save', (tester) async {
      sizeView(tester, 800);
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, 'Title'), 'X');
      await tester.enterText(find.widgetWithText(TextField, 'Qty'), '-2');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(find.text('Must be > 0'), findsOneWidget);

      // The remaining cases are asked of the rule directly rather than through
      // Save: the row's validator and the screen's "which collapsed rows must
      // open" both call `ingredientQuantityError`. Empty is the "to taste"
      // ingredient and stays valid — the SQL check allows NULL for the same
      // reason, and that is the half that would break real recipes if the
      // rule were written as "required".
      String? rule(String text) =>
          ingredientQuantityError(EditIngredient(quantity: text));
      expect(rule(''), isNull);
      expect(rule('  '), isNull);
      expect(rule('0'), 'Must be > 0');
      expect(rule('0/4'), 'Must be > 0');
      // UX-052: a fraction is a quantity now, and only the unreadable is not.
      expect(rule('1/2'), isNull);
      expect(rule('1 1/2'), isNull);
      expect(rule('½'), isNull);
      expect(rule('1,5'), isNull);
      expect(rule('1.5'), isNull);
      expect(rule('a pinch'), 'Try 1/2 or 0.5');
      expect(rule('1/0'), 'Try 1/2 or 0.5');
    });

    // Phase 28, reshaped by 29c: the panel is collapsed on a new recipe, and
    // opening it shows the three-way mode choice with None selected — the
    // eleven boxes appear only once the cook picks Manual.
    testWidgets('nutrition opens on Add; Manual reveals the fields', (
      tester,
    ) async {
      sizeView(tester, 800);
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();

      expect(find.text('Nutrition facts'), findsOneWidget);
      expect(find.text('Cholesterol'), findsNothing);
      expect(find.byType(ChoiceChip), findsNothing);

      await tester.tap(find.widgetWithText(TextButton, 'Add'));
      await tester.pumpAndSettle();

      // The choice, not the boxes: None is the default on a new recipe.
      expect(find.widgetWithText(ChoiceChip, 'Automatic'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Manual'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'None'), findsOneWidget);
      expect(find.text('Calories'), findsNothing);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Manual'));
      await tester.pumpAndSettle();

      expect(find.text('Calories'), findsOneWidget);
      expect(find.text('Cholesterol'), findsOneWidget);
      expect(find.text('Protein'), findsOneWidget);
    });

    testWidgets('a non-numeric entry blocks Save instead of being dropped', (
      tester,
    ) async {
      sizeView(tester, 800);
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Manual'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, 'Title'), 'X');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Calories'),
        '1/2',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      // `double.tryParse('1/2')` is null — without the validator this would be
      // saved as "no calories" with no word to the user (the B066 shape).
      expect(find.textContaining('Numbers only'), findsOneWidget);
    });

    // B072's actual mechanism, and the one the test above cannot reach: the
    // panel is COLLAPSED. A `TextFormField` that leaves the tree leaves
    // `Form.validate()` with it, so without `maintainState: true` the entry is
    // never validated and `tryParse` drops it in silence. Delete that flag and
    // the test above stays green; this one does not.
    testWidgets('an invalid entry still blocks Save while collapsed', (
      tester,
    ) async {
      sizeView(tester, 800);
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Manual'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, 'Title'), 'X');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Calories'),
        '1/2',
      );

      await tester.tap(find.widgetWithText(TextButton, 'Hide'));
      await tester.pumpAndSettle();
      expect(find.text('Cholesterol'), findsNothing);

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      // Blocked — and the panel is back open, so the error is reachable
      // instead of being a Save button that does nothing.
      expect(find.widgetWithText(TextButton, 'Hide'), findsOneWidget);
      expect(find.textContaining('Numbers only'), findsOneWidget);
    });

    // The other half of that rule: the force-expand is scoped to a *nutrition*
    // failure. A blank Title must not unfold eleven boxes that have nothing to
    // do with the error above them.
    testWidgets('a blank title does not unfold the nutrition panel', (
      tester,
    ) async {
      sizeView(tester, 800);
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();

      // Title left empty; nutrition never touched.
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.text('Required'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Add'), findsOneWidget);
      expect(find.text('Cholesterol'), findsNothing);
    });

    // Both new blocks are Rows with intrinsic siblings, the shape behind
    // B001/B002/B016/B023. Check them at the narrowest phone and 2.0x —
    // with the nutrition panel expanded too (Phase 28).
    for (final width in <double>[320, 360, 600]) {
      testWidgets('expanded detail rows fit at ${width}px, textScale 2.0', (
        tester,
      ) async {
        sizeView(tester, width);

        await tester.pumpWidget(_app(textScale: 2.0));
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: 'collapsed form overflows at ${width}px @ 2.0x',
        );

        await tester.tap(find.widgetWithText(TextButton, 'Add'));
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: 'nutrition mode chips overflow at ${width}px @ 2.0x',
        );

        await tester.tap(find.widgetWithText(ChoiceChip, 'Manual'));
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: 'nutrition panel overflows at ${width}px @ 2.0x',
        );

        await tester.tap(find.byTooltip('Note & optional'));
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: 'ingredient note row overflows at ${width}px @ 2.0x',
        );

        await tester.tap(find.byTooltip('Temperature & tip'));
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: 'step detail rows overflow at ${width}px @ 2.0x',
        );
      });
    }
  });

  // Phase 29b: the name field's registry typeahead and the link chip. Pumped
  // as IngredientsEditor directly — the full screen adds nothing to these
  // behaviours and would drag the whole form into every pump.
  group('food link (Phase 29b)', () {
    Widget app(List<EditIngredientGroup> groups, {double textScale = 1.0}) =>
        ProviderScope(
          overrides: [
            foodRepositoryProvider.overrideWithValue(_StubFoodRepository()),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            builder:
                (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(textScale)),
                  child: child!,
                ),
            // The editor is a sliver: it goes in a `CustomScrollView`, the
            // way the screen hosts it.
            home: Scaffold(
              body: CustomScrollView(
                slivers: [
                  StatefulBuilder(
                    builder:
                        (context, setState) => IngredientsEditor(
                          groups: groups,
                          onChanged: () => setState(() {}),
                        ),
                  ),
                ],
              ),
            ),
          ),
        );

    testWidgets('picking a suggestion sets the name AND the link', (
      tester,
    ) async {
      final groups = [EditIngredientGroup()];
      await tester.pumpWidget(app(groups));

      await tester.enterText(find.widgetWithText(TextField, 'Name'), 'flou');
      await tester.pump(const Duration(milliseconds: 300)); // debounce
      await tester.pumpAndSettle();

      await tester.tap(find.text('All-purpose flour').last);
      await tester.pumpAndSettle();

      final ingredient = groups.single.ingredients.single;
      expect(ingredient.foodId, 'all-purpose-flour');
      expect(ingredient.name.text, 'All-purpose flour');
      expect(find.byType(InputChip), findsOneWidget);
    });

    testWidgets('typing past the dropdown stays free text, unlinked', (
      tester,
    ) async {
      final groups = [EditIngredientGroup()];
      await tester.pumpWidget(app(groups));

      await tester.enterText(
        find.widgetWithText(TextField, 'Name'),
        'grandma\'s secret blend',
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(groups.single.ingredients.single.foodId, isNull);
      expect(find.byType(InputChip), findsNothing);
    });

    testWidgets('renaming keeps the link; only the chip clears it', (
      tester,
    ) async {
      final groups = [
        EditIngredientGroup(
          ingredients: [
            EditIngredient(name: 'plain flour')
              ..foodId = 'all-purpose-flour'
              ..foodLabel = 'All-purpose flour',
          ],
        ),
      ];
      await tester.pumpWidget(app(groups));
      expect(find.byType(InputChip), findsOneWidget);

      // Renaming is the case the per-row FK exists for — the link survives.
      await tester.enterText(
        find.widgetWithText(TextField, 'Name'),
        'my best flour',
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(groups.single.ingredients.single.foodId, 'all-purpose-flour');

      await tester.tap(find.byTooltip('Remove link'));
      await tester.pumpAndSettle();
      expect(groups.single.ingredients.single.foodId, isNull);
      expect(find.byType(InputChip), findsNothing);
    });

    // The row's envelope, re-run with the chip present (Gotcha 26): a linked
    // row is a new caller of a row that was at its width budget already.
    for (final width in <double>[320, 360, 600]) {
      testWidgets('a linked row fits at ${width}px, textScale 2.0', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 2000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final groups = [
          EditIngredientGroup(
            ingredients: [
              EditIngredient(name: 'extra virgin olive oil')
                ..foodId = 'olive-oil'
                ..foodLabel = 'Olive oil, extra virgin, cold pressed',
            ],
          ),
        ];
        await tester.pumpWidget(app(groups, textScale: 2.0));
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: 'linked ingredient row overflows at ${width}px @ 2.0x',
        );
      });
    }
  });

  // Phase 29c: the three-way mode, its transitions, and the Auto pane's
  // honesty surfaces. The stub estimates like the server does (counted =
  // linked rows with a quantity, null label at zero), so these are the same
  // shapes the real RPC produces.
  group('nutrition modes (Phase 29c)', () {
    // The nutrition panel is the last thing on the page (UX-039). Tall
    // viewport instead of scripted scrolls.
    void sizeView(WidgetTester tester, double width) {
      tester.view.physicalSize = Size(width, 6000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    testWidgets(
      'a stored auto label reopens as Automatic with the honest pane',
      (tester) async {
        sizeView(tester, 800);
        await tester.pumpWidget(
          _editApp(_LoadedRecipeRepository(_autoRecipe())),
        );
        await tester.pumpAndSettle();

        // 1 linked of 2 named rows, straight from the loaded draft.
        expect(
          find.textContaining('Estimated from 1 of 2 ingredients'),
          findsOneWidget,
        );
        // The preview is the real label widget, marked as an estimate.
        expect(find.text('Nutrition Facts'), findsOneWidget);
        expect(
          find.textContaining('Estimated from ingredients'),
          findsOneWidget,
        );
        // The not-counted list names the row and the reason.
        expect(find.textContaining('onion'), findsWidgets);
        expect(find.textContaining('not linked to a food'), findsOneWidget);
      },
    );

    testWidgets('a suggestion chip links the row and recounts', (tester) async {
      sizeView(tester, 800);
      await tester.pumpWidget(_editApp(_LoadedRecipeRepository(_autoRecipe())));
      await tester.pumpAndSettle();

      // One link chip already (flour); onion offers a match_foods candidate.
      expect(find.byType(InputChip), findsOneWidget);
      await tester.tap(find.widgetWithText(ActionChip, 'All-purpose flour'));
      await tester.pumpAndSettle();

      // The confirmed link is a draft fact: the row grows its chip and the
      // re-estimate counts it.
      expect(find.byType(InputChip), findsNWidgets(2));
      expect(
        find.textContaining('Estimated from 2 of 2 ingredients'),
        findsOneWidget,
      );
      expect(find.textContaining('not linked to a food'), findsNothing);
    });

    // The stale-preview trap: the Auto pane tells the cook to link foods "in
    // the ingredient list", and that list is a different widget. Without the
    // debounced re-estimate the header and label keep describing the previous
    // draft until the refresh button is found.
    testWidgets('editing the ingredients below re-estimates', (tester) async {
      sizeView(tester, 800);
      await tester.pumpWidget(
        _editApp(_LoadedRecipeRepository(_autoRecipe(linked: false))),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Nothing to estimate from yet'),
        findsOneWidget,
      );

      // Link the free-text row through the ingredient list's own typeahead.
      await tester.enterText(
        find.widgetWithText(TextField, 'Name').first,
        'flou',
      );
      await tester.pump(
        const Duration(milliseconds: 300),
      ); // typeahead debounce
      await tester.pumpAndSettle();
      await tester.tap(find.text('All-purpose flour').last);
      await tester.pump(const Duration(milliseconds: 600)); // estimate debounce
      await tester.pumpAndSettle();

      expect(find.textContaining('Nothing to estimate from yet'), findsNothing);
      expect(find.text('Nutrition Facts'), findsOneWidget);
    });

    // Same trap on the other input the estimate depends on: servings is the
    // divisor, so a stale label would print per-4 rows under an "8 servings"
    // line.
    testWidgets('changing servings re-estimates', (tester) async {
      sizeView(tester, 800);
      final repo = _RecordingFoodRepository();
      await tester.pumpWidget(
        _editApp(_LoadedRecipeRepository(_autoRecipe()), food: repo),
      );
      await tester.pumpAndSettle();
      expect(repo.servingsSeen, [4]);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Servings'),
        '8',
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      expect(repo.servingsSeen, [4, 8]);
    });

    testWidgets('Automatic with nothing counted warns and saves no lie', (
      tester,
    ) async {
      sizeView(tester, 800);
      await tester.pumpWidget(
        _editApp(_LoadedRecipeRepository(_autoRecipe(linked: false))),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Nothing to estimate from yet'),
        findsOneWidget,
      );
      // No preview label to mislead with.
      expect(find.text('Nutrition Facts'), findsNothing);
    });

    testWidgets('Auto -> Manual seeds the fields with the computed values', (
      tester,
    ) async {
      sizeView(tester, 800);
      await tester.pumpWidget(_editApp(_LoadedRecipeRepository(_autoRecipe())));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ChoiceChip, 'Manual'));
      await tester.pumpAndSettle();

      // The estimate's values, not the stored 999 the recipe carried — the
      // cook edits the current estimate, and the seeded copy sheds `source`.
      expect(find.widgetWithText(TextFormField, '250'), findsOneWidget);
      expect(find.text('Calories'), findsOneWidget);
      expect(find.textContaining('Estimated from 1 of'), findsNothing);
    });

    testWidgets('Manual with values asks before switching to Automatic', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Manual'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Calories'),
        '100',
      );

      // Cancel keeps the typed values and the mode.
      await tester.tap(find.widgetWithText(ChoiceChip, 'Automatic'));
      await tester.pumpAndSettle();
      expect(find.text('Switch to automatic?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Keep manual'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextFormField, '100'), findsOneWidget);

      // Confirm switches — an empty draft estimates to the honest warning.
      await tester.tap(find.widgetWithText(ChoiceChip, 'Automatic'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Use automatic'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Nothing to estimate from yet'),
        findsOneWidget,
      );
    });

    testWidgets('None from Manual asks nothing and hides the boxes', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Manual'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'None'));
      await tester.pumpAndSettle();

      expect(find.text('Calories'), findsNothing);
      expect(find.textContaining('no nutrition panel'), findsOneWidget);
    });

    // The Auto pane's envelope (Gotcha 13/26): preview label + not-counted
    // list + suggestion chips, at the same matrix as every other editor row.
    for (final width in <double>[320, 360, 600]) {
      testWidgets('the Auto pane fits at ${width}px, textScale 2.0', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 6000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          _editApp(_LoadedRecipeRepository(_autoRecipe()), textScale: 2.0),
        );
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: 'Auto pane overflows at ${width}px @ 2.0x',
        );
      });
    }
  });

  // B052 / OPT-S4. `_load()` was try/finally with no catch: a failed getById
  // escaped as an unhandled future and the form rendered its empty defaults over
  // a recipe that still exists. Because `update()` replaces content wholesale,
  // one Save then deleted every ingredient and step group it had.
  // Phase 9 carry-over: the per-step photo picker. The upload deliberately
  // reuses the cover tile's shape — pick, hold the bytes on the draft, upload
  // inside `_save`, write the URL into the same `save_recipe` call — so these
  // tests assert that shape end to end with the platform channel and Storage
  // faked out. Neither can be exercised for real on this machine.
  group('step photo', () {
    void sizeView(WidgetTester tester, double width) {
      tester.view.physicalSize = Size(width, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    testWidgets('a pick is uploaded on save and its URL reaches the step', (
      tester,
    ) async {
      sizeView(tester, 800);
      final repo = _RecordingRecipeRepository();
      final storage = _FakeStorageService();
      await tester.pumpWidget(
        _routedNewApp(repo, pick: () async => _png, storage: storage),
      );
      await tester.pumpAndSettle();

      // Nothing to show, and nothing to remove, before a pick.
      expect(find.byTooltip('Remove photo'), findsNothing);

      await _fillRequired(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Step'),
        'Sear the lamb hard on one side.',
      );
      await tester.tap(find.byTooltip('Step photo'));
      await tester.pumpAndSettle();

      // The pick is visible immediately — from memory, before any upload.
      expect(find.byType(Image), findsWidgets);
      expect(find.byTooltip('Remove photo'), findsOneWidget);
      expect(storage.uploads, isEmpty, reason: 'upload belongs to the save');

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(storage.uploads, hasLength(1));
      expect(storage.uploads.single.$1, startsWith('step_'));
      expect(storage.uploads.single.$2, _png.length);

      // The round-trip that matters: one `save_recipe` call, carrying the URL.
      expect(repo.created, hasLength(1));
      final saved = repo.created.single.stepGroups.single.steps.single;
      expect(saved.text, 'Sear the lamb hard on one side.');
      expect(saved.imageUrl, 'https://cdn.test/${storage.uploads.single.$1}');
    });

    testWidgets('removing a stored photo clears image_url on the next save', (
      tester,
    ) async {
      sizeView(tester, 800);
      final repo = _RecordingRecipeRepository(loaded: _recipeWithStepPhoto);
      final storage = _FakeStorageService();
      await tester.pumpWidget(_routedEditApp(repo, storage: storage));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Remove photo'), findsOneWidget);
      await tester.tap(find.byTooltip('Remove photo'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Remove photo'), findsNothing);

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(storage.uploads, isEmpty, reason: 'nothing new was picked');
      expect(repo.updated, hasLength(1));
      expect(
        repo.updated.single.$1.stepGroups.single.steps.single.imageUrl,
        isNull,
      );
    });

    testWidgets('an untouched photo survives an edit that ignores it', (
      tester,
    ) async {
      sizeView(tester, 800);
      final repo = _RecordingRecipeRepository(loaded: _recipeWithStepPhoto);
      await tester.pumpWidget(_routedEditApp(repo));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(
        repo.updated.single.$1.stepGroups.single.steps.single.imageUrl,
        'https://cdn.test/me/stored.jpg',
      );
    });

    // The bucket refuses anything over `file_size_limit` (5 MB, 32a4) at the
    // API edge, and the picker cannot prevent it — so the editor checks the
    // byte count where the file was chosen. Without this the refusal surfaces
    // from inside the save as "Save failed", naming no size.
    testWidgets('an over-sized pick is refused before any upload', (
      tester,
    ) async {
      sizeView(tester, 800);
      final storage = _FakeStorageService();
      await tester.pumpWidget(
        _routedNewApp(
          _RecordingRecipeRepository(),
          pick: () async => Uint8List(kMaxUploadBytes + 1),
          storage: storage,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Step photo'));
      await tester.pumpAndSettle();

      expect(find.textContaining('over 5 MB'), findsOneWidget);
      expect(find.byTooltip('Remove photo'), findsNothing);
      expect(storage.uploads, isEmpty);
    });

    // A denied gallery permission is a platform-channel throw. It has to read
    // as a sentence, through `friendlyError` like every other error the editor
    // shows — never a raw exception in a snackbar.
    testWidgets('a refused pick says so in the mapper\'s words', (
      tester,
    ) async {
      sizeView(tester, 800);
      await tester.pumpWidget(
        _routedNewApp(
          _RecordingRecipeRepository(),
          pick: () async => throw Exception('MissingPluginException'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Step photo'));
      await tester.pumpAndSettle();

      expect(find.text(friendlyError(Exception('x'))), findsOneWidget);
      expect(find.textContaining('MissingPluginException'), findsNothing);
      expect(find.byTooltip('Remove photo'), findsNothing);
    });

    // Gotcha 13/26's envelope, re-run because the row gained a third icon
    // button and the step gained a preview under it. 390 is the phone the
    // control was designed against; 320 is the narrowest the suite carries.
    for (final width in <double>[320, 360, 390, 600]) {
      testWidgets('a step with a photo fits at ${width}px, textScale 2.0', (
        tester,
      ) async {
        sizeView(tester, width);
        final groups = [
          EditStepGroup(
            steps: [
              EditStep(text: 'Sear the lamb hard on one side.')
                ..pendingImageBytes = _png,
            ],
          ),
        ];
        addTearDown(() {
          for (final g in groups) {
            g.dispose();
          }
        });

        await tester.pumpWidget(_stepsApp(groups, textScale: 2.0));
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: 'step row + photo overflows at ${width}px @ 2.0x',
        );

        await tester.tap(find.byTooltip('Temperature & tip'));
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: 'photo above the detail rows overflows at ${width}px @ 2.0x',
        );
      });
    }
  });

  group('failed load (B052)', () {
    testWidgets('renders ErrorView instead of an empty form', (tester) async {
      await tester.pumpWidget(_editApp(_ThrowingRecipeRepository()));
      await tester.pumpAndSettle();

      expect(find.byType(ErrorView), findsOneWidget);
      expect(
        find.byType(TextFormField),
        findsNothing,
        reason: 'an empty draft over a real recipe is the data-loss path',
      );
    });

    testWidgets('offers no Save button on the error screen', (tester) async {
      await tester.pumpWidget(_editApp(_ThrowingRecipeRepository()));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(FilledButton, 'Save'), findsNothing);
    });

    testWidgets('retry recovers into the loaded form', (tester) async {
      final repo = _ThrowingRecipeRepository(failures: 1);
      await tester.pumpWidget(_editApp(repo));
      await tester.pumpAndSettle();
      expect(find.byType(ErrorView), findsOneWidget);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Retry'));
      await tester.pumpAndSettle();

      expect(find.byType(ErrorView), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Save'), findsOneWidget);
      // The recipe that came back, not the empty defaults.
      expect(find.text('Loaded Recipe'), findsOneWidget);
    });

    testWidgets('a successful load leaves Save enabled', (tester) async {
      await tester.pumpWidget(_editApp(_ThrowingRecipeRepository(failures: 0)));
      await tester.pumpAndSettle();

      final save = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Save'),
      );
      expect(save.onPressed, isNotNull);
    });
  });

  // 32e2. `_save` had never been driven: no test in this file called
  // `repo.create` or `repo.update`, so the success navigation, the change
  // summary an edit records, and the failure snackbar were all unpinned — on
  // the one path that writes a whole recipe.
  group('saving (32e2)', () {
    testWidgets('a new recipe goes through create and opens the recipe', (
      tester,
    ) async {
      final repo = _RecordingRecipeRepository();
      await tester.pumpWidget(_routedNewApp(repo));
      await tester.pumpAndSettle();

      await _fillRequired(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(repo.created, hasLength(1));
      expect(repo.created.single.title, 'Suya-Spiced Lamb');
      expect(repo.updated, isEmpty);
      expect(find.text('RECIPE PAGE'), findsOneWidget);
    });

    // F001: `category` was written by `save_recipe` and sent by the repository,
    // but the editor had no control for it — so `_save` built a Recipe with
    // `category: null` and every edit silently deleted the value. The draft
    // round-trip tests above could not catch it: the miss was on the top-level
    // Recipe, not on the edit_models types they cover. All 14 authored recipes
    // and all 108 corpus recipes carry a category, so this hit every save.
    testWidgets('an edit preserves a category the editor loaded', (
      tester,
    ) async {
      final repo = _RecordingRecipeRepository(
        loaded: const Recipe(
          id: 'r1',
          ownerId: 'me',
          title: 'Loaded Recipe',
          servings: 4,
          cuisine: 'Italian',
          category: 'Main course',
        ),
      );
      await tester.pumpWidget(_routedEditApp(repo));
      await tester.pumpAndSettle();

      // Change something unrelated, exactly as a user editing a typo would.
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Loaded Recipe'),
        'Loaded Recipe, revised',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(repo.updated, hasLength(1));
      expect(repo.updated.single.$1.category, 'Main course');
      expect(repo.updated.single.$1.cuisine, 'Italian');
    });

    testWidgets('an edit goes through update, with a change summary', (
      tester,
    ) async {
      final repo = _RecordingRecipeRepository();
      await tester.pumpWidget(_routedEditApp(repo));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Loaded Recipe'),
        'Loaded Recipe, hotter',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(repo.created, isEmpty);
      expect(repo.updated, hasLength(1));
      expect(repo.updated.single.$1.title, 'Loaded Recipe, hotter');
      expect(repo.updated.single.$1.id, 'r1');
      // Every edit appends a version, and the summary is what the history sheet
      // prints for it.
      expect(repo.updated.single.$2, isNotEmpty);
      expect(find.text('RECIPE PAGE'), findsOneWidget);
    });

    testWidgets('a blank title blocks the save before the repository', (
      tester,
    ) async {
      final repo = _RecordingRecipeRepository();
      await tester.pumpWidget(_routedNewApp(repo));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(repo.created, isEmpty);
      expect(find.text('Required'), findsOneWidget);
    });

    testWidgets('a refused save says so and stays in the editor', (
      tester,
    ) async {
      final repo = _RecordingRecipeRepository(fail: true);
      await tester.pumpWidget(_routedNewApp(repo));
      await tester.pumpAndSettle();

      await _fillRequired(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Save failed'), findsOneWidget);
      expect(find.text('RECIPE PAGE'), findsNothing);
      // Still editable — a failed save must not leave the button spinning.
      final save = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Save'),
      );
      expect(save.onPressed, isNotNull);
    });

    testWidgets('an unloaded edit draft offers no Save at all', (tester) async {
      // `_canSave`'s reason for existing (B052): the draft holds empty defaults
      // until the load lands, and `update()` replaces content wholesale — so a
      // save here would delete every group the recipe has.
      await tester.pumpWidget(_routedEditApp(_HangingRecipeRepository()));
      await tester.pump();

      expect(find.byType(LoadingView), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Save'), findsNothing);
    });
  });

  // 32c2 / B085. The discard confirm hung off the close button alone, so a
  // system back gesture dropped a half-written recipe without a word — and the
  // inverse: closing an untouched editor asked about changes that did not
  // exist. `handlePopRoute()` is the platform back button, routed through the
  // same `maybePop` an Android gesture uses.
  group('leaving the editor (32c2)', () {
    testWidgets('an untouched editor closes without asking', (tester) async {
      await tester.pumpWidget(_routedEditApp(_loadedRepo()));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Discard changes?'), findsNothing);
      expect(find.text('RECIPE PAGE'), findsOneWidget);
    });

    testWidgets('an untouched editor pops on a system back', (tester) async {
      await tester.pumpWidget(_routedEditApp(_loadedRepo()));
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('Discard changes?'), findsNothing);
    });

    testWidgets('an edited draft asks before a system back throws it away', (
      tester,
    ) async {
      await tester.pumpWidget(_routedEditApp(_loadedRepo()));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Loaded Recipe'),
        'Loaded Recipe with a new name',
      );
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);

      // Keeping the edits leaves the cook exactly where they were.
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsNothing);
      expect(find.text('RECIPE PAGE'), findsNothing);
      expect(find.text('Loaded Recipe with a new name'), findsOneWidget);
    });

    testWidgets('discarding leaves for the recipe', (tester) async {
      await tester.pumpWidget(_routedEditApp(_loadedRepo()));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Loaded Recipe'),
        'Half a thought',
      );
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();

      expect(find.text('RECIPE PAGE'), findsOneWidget);
    });

    testWidgets('touching a field without changing its text is not an edit', (
      tester,
    ) async {
      await tester.pumpWidget(_routedEditApp(_loadedRepo()));
      await tester.pumpAndSettle();

      // A `TextEditingController` notifies on **selection** changes too, so
      // focusing Title or re-entering the same string moves the caret and fires
      // every listener. If the flag trusted the notification rather than the
      // text, this would nag about changes nobody made — the half of B085 this
      // was supposed to remove.
      final title = find.widgetWithText(TextFormField, 'Loaded Recipe');
      await tester.tap(title);
      await tester.pumpAndSettle();
      await tester.enterText(title, 'Loaded Recipe');
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('Discard changes?'), findsNothing);
    });

    testWidgets('an edit anywhere in the draft counts, not just the fields', (
      tester,
    ) async {
      await tester.pumpWidget(_routedEditApp(_loadedRepo()));
      await tester.pumpAndSettle();

      // The ingredients editor reports through `onChanged`, which is the other
      // half of the dirty signal — a recipe can be changed without a keystroke
      // in any of the seven text fields. It is below the fold, hence the scroll
      // — built (B142) but off screen, so the finder has to look off stage.
      final add = find.widgetWithText(
        TextButton,
        'Add ingredient',
        skipOffstage: false,
      );
      await tester.ensureVisible(add);
      await tester.pumpAndSettle();
      await tester.tap(add);
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('Discard changes?'), findsOneWidget);
    });

    // B149: no draft field reported a keystroke, so changing an ingredient's
    // name or a step's text and backing out threw the edit away unasked.
    for (final label in ['Name', 'Step']) {
      testWidgets('typing in a draft $label field is an edit', (tester) async {
        await tester.pumpWidget(_routedEditApp(_loadedRepo()));
        await tester.pumpAndSettle();

        final field =
            find.widgetWithText(TextField, label, skipOffstage: false).first;
        await tester.ensureVisible(field);
        await tester.pumpAndSettle();
        await tester.enterText(field, 'changed');
        await tester.pumpAndSettle();

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.text('Discard changes?'), findsOneWidget);
      });
    }

    // Phase 38 review: showing a step's temperature and tip is not an edit
    // (the steps twin of B143).
    testWidgets('opening Temperature & tip is not an edit', (tester) async {
      await tester.pumpWidget(_routedEditApp(_loadedRepo()));
      await tester.pumpAndSettle();

      final toggle =
          find.byTooltip('Temperature & tip', skipOffstage: false).first;
      await tester.ensureVisible(toggle);
      await tester.pumpAndSettle();
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      await tester.tap(toggle);
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsNothing);
    });
  });

  // Phase 38 review: a stored duration the parser refuses (a negative — the
  // column has no check — or one past a week) saves back untouched instead of
  // blocking the save of a step the cook never touched.
  test('an untouched out-of-range step time saves back as it was', () {
    for (final stored in [-5, kMaxDurationMinutes + 60]) {
      final draft = EditStep.fromModel(
        RecipeStep(
          id: 's',
          groupId: 'g',
          text: 'Rest.',
          durationMinutes: stored,
        ),
      );
      expect(draft.hasInvalidDuration, isFalse, reason: '$stored');
      expect(draft.toModel(0).durationMinutes, stored);
      draft.duration.text = '1h 30m';
      expect(draft.toModel(0).durationMinutes, 90);
      draft.dispose();
    }
  });

  // Phase 38 (UX-035 / UX-039 / UX-052): the editor's order, its honest empty
  // defaults, fraction quantities, reordering, the group-delete confirm, the
  // compact one-line ingredient row, and the not-counted list.
  group('Phase 38 editor', () {
    void sizeView(WidgetTester tester, double width, [double height = 5000]) {
      tester.view.physicalSize = Size(width, height);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    Future<void> save(WidgetTester tester) async {
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
    }

    List<Ingredient> savedIngredients(_RecordingRecipeRepository repo) => [
      for (final g in repo.updated.single.$1.ingredientGroups) ...g.ingredients,
    ];

    testWidgets('the order is Ingredients, then Steps, then Nutrition', (
      tester,
    ) async {
      sizeView(tester, 800);
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();

      double top(String text) => tester.getTopLeft(find.text(text)).dy;
      expect(top('Ingredients'), lessThan(top('Instructions')));
      expect(top('Instructions'), lessThan(top('Nutrition facts')));
    });

    testWidgets('a new recipe opens with no invented numbers', (tester) async {
      sizeView(tester, 800);
      await tester.pumpWidget(_routedNewApp(_RecordingRecipeRepository()));
      await tester.pumpAndSettle();

      String text(String label) =>
          tester
              .widget<TextFormField>(
                find.ancestor(
                  of: find.text(label),
                  matching: find.byType(TextFormField),
                ),
              )
              .controller!
              .text;
      expect(text('Prep'), isEmpty);
      expect(text('Cook'), isEmpty);
      expect(text('Servings'), isEmpty);
      // No preselected difficulty — the hint stands in for it.
      expect(find.text('Choose…'), findsOneWidget);
      expect(find.text('Easy'), findsNothing);
    });

    testWidgets('servings and difficulty are required', (tester) async {
      sizeView(tester, 800);
      final repo = _RecordingRecipeRepository();
      await tester.pumpWidget(_routedNewApp(repo));
      await tester.pumpAndSettle();

      await tester.enterText(_titleField, 'Suya-Spiced Lamb');
      await save(tester);

      expect(repo.created, isEmpty);
      expect(find.text('How many does it serve?'), findsOneWidget);
      expect(find.text('Pick one'), findsOneWidget);
    });

    testWidgets('empty prep and cook save 0; the picks save as chosen', (
      tester,
    ) async {
      sizeView(tester, 800);
      final repo = _RecordingRecipeRepository();
      await tester.pumpWidget(_routedNewApp(repo));
      await tester.pumpAndSettle();

      await _fillRequired(tester, servings: '6');
      await save(tester);

      final saved = repo.created.single;
      expect(saved.prepMinutes, 0);
      expect(saved.cookMinutes, 0);
      expect(saved.servings, 6);
      expect(saved.difficulty, Difficulty.medium);
    });

    // Live pass (Phase 38): with Prep and Cook empty the labels sit inside
    // the field at full size, and `Prep (min)` ellipsised to `Prep (mi…` in a
    // third of a 390px phone.
    testWidgets('the empty Prep and Cook labels are laid out whole at 390', (
      tester,
    ) async {
      sizeView(tester, 390);
      await tester.pumpWidget(_routedNewApp(_RecordingRecipeRepository()));
      await tester.pumpAndSettle();
      // Not Servings: `flutter test`'s font is far wider than Manrope, and the
      // live capture shows it whole (Gotcha 27 — pin the change, not pixels).
      for (final label in ['Prep', 'Cook']) {
        final text = find.descendant(
          of: find.byType(InputDecorator),
          matching: find.text(label),
        );
        final paragraph = tester.renderObject<RenderParagraph>(text.first);
        expect(paragraph.didExceedMaxLines, isFalse, reason: label);
      }
    });

    // UX-035 in the header: `int.tryParse` saved a typed `1h` as no time.
    testWidgets('prep and cook read 1h 30m; unreadable is refused', (
      tester,
    ) async {
      sizeView(tester, 800);
      final repo = _RecordingRecipeRepository();
      await tester.pumpWidget(_routedNewApp(repo));
      await tester.pumpAndSettle();

      await _fillRequired(tester, servings: '4');
      final prep = find.widgetWithText(TextFormField, 'Prep');
      final cook = find.widgetWithText(TextFormField, 'Cook');
      await tester.enterText(prep, '1h 30m');
      await tester.enterText(cook, 'a while');
      await save(tester);
      expect(repo.created, isEmpty);
      expect(find.text('Try 45, 1h or 1h 30m'), findsOneWidget);

      await tester.enterText(cook, '45');
      await save(tester);
      expect(repo.created.single.prepMinutes, 90);
      expect(repo.created.single.cookMinutes, 45);
    });

    testWidgets('an untouched new recipe is not dirty', (tester) async {
      sizeView(tester, 800);
      await tester.pumpWidget(_routedNewApp(_RecordingRecipeRepository()));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Discard changes?'), findsNothing);
      expect(find.text('MY RECIPES'), findsOneWidget);
    });

    testWidgets('a stored 0 prep shows empty and saves 0 again', (
      tester,
    ) async {
      sizeView(tester, 800);
      final repo = _RecordingRecipeRepository(
        loaded: const Recipe(
          id: 'r1',
          ownerId: 'me',
          title: 'Loaded Recipe',
          servings: 4,
          cookMinutes: 25,
          difficulty: Difficulty.hard,
        ),
      );
      await tester.pumpWidget(_routedEditApp(repo));
      await tester.pumpAndSettle();

      final prep = tester.widget<TextFormField>(
        find.ancestor(
          of: find.text('Prep'),
          matching: find.byType(TextFormField),
        ),
      );
      expect(prep.controller!.text, isEmpty);
      expect(find.widgetWithText(TextFormField, '25'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '4'), findsOneWidget);
      await save(tester);

      final saved = repo.updated.single.$1;
      expect(saved.prepMinutes, 0);
      expect(saved.cookMinutes, 25);
      expect(saved.servings, 4);
      expect(saved.difficulty, Difficulty.hard);
    });

    // B035 (UX-052): the box shows a loaded quantity as a cook reads it, and
    // an untouched box saves the loaded number back exactly — `1⁄3` must not
    // become 0.3333… — while a typed fraction saves its decimal.
    test('a loaded 0.33 cup shows as 1⁄3 and saves back as 0.33', () {
      final draft = EditIngredient.fromModel(
        const Ingredient(
          id: 'i1',
          groupId: 'g1',
          quantity: 0.33,
          unit: 'cup',
          name: 'milk',
          isOptional: false,
          sortOrder: 0,
        ),
      );
      expect(draft.quantity.text, '1⁄3');
      expect(draft.toModel(0).quantity, 0.33);
      expect(ingredientQuantityError(draft), isNull);

      draft.quantity.text = '1/2';
      expect(draft.toModel(0).quantity, 0.5);
      draft.dispose();
    });

    testWidgets('a typed 1/2 saves 0.5; an untouched 1⁄3 saves 0.33', (
      tester,
    ) async {
      sizeView(tester, 800);
      final repo = _RecordingRecipeRepository(loaded: _twoIngredients());
      await tester.pumpWidget(_routedEditApp(repo));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextField, '1⁄3'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, '2'), '1/2');
      await save(tester);

      final saved = savedIngredients(repo);
      expect(saved.map((i) => i.name), ['milk', 'flour']);
      expect(saved[0].quantity, 0.33);
      expect(saved[1].quantity, 0.5);
    });

    testWidgets('an unreadable quantity blocks Save with a hint', (
      tester,
    ) async {
      sizeView(tester, 800);
      final repo = _RecordingRecipeRepository(loaded: _twoIngredients());
      await tester.pumpWidget(_routedEditApp(repo));
      await tester.pumpAndSettle();

      // A full keyboard: the numeric keypads have no `/`.
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, '2'))
            .keyboardType,
        TextInputType.text,
      );
      await tester.enterText(find.widgetWithText(TextField, '2'), 'a pinch');
      await save(tester);

      expect(repo.updated, isEmpty);
      expect(find.text('Try 1/2 or 0.5'), findsOneWidget);

      // The complaint clears as soon as the entry reads.
      await tester.enterText(find.widgetWithText(TextField, 'a pinch'), '½');
      await tester.pumpAndSettle();
      expect(find.text('Try 1/2 or 0.5'), findsNothing);
    });

    // UX-052: the message used to live inside the fixed 64px field, where it
    // clipped to a letter or two at 2.0×. It is a line of its own now; prove
    // the whole sentence is laid out, at the phone width it failed at.
    testWidgets('the quantity error is laid out whole at 390px, 2.0x', (
      tester,
    ) async {
      sizeView(tester, 390);
      await tester.pumpWidget(
        _routedNewApp(_RecordingRecipeRepository(), textScale: 2.0),
      );
      await tester.pumpAndSettle();

      final qty = find.widgetWithText(TextField, 'Qty');
      await tester.ensureVisible(qty);
      await tester.enterText(qty, 'abc');
      await save(tester);
      expect(tester.takeException(), isNull);

      final message = find.text('Try 1/2 or 0.5');
      expect(message, findsOneWidget);
      final paragraph = tester.renderObject<RenderParagraph>(message);
      expect(paragraph.didExceedMaxLines, isFalse);
      // …and it is not squeezed into the field's width.
      expect(
        tester.getSize(message).width,
        greaterThan(tester.getSize(qty).width),
      );
    });

    testWidgets('Move up / Move down reorder, and the save keeps it', (
      tester,
    ) async {
      sizeView(tester, 800);
      final repo = _RecordingRecipeRepository(loaded: _twoIngredients());
      await tester.pumpWidget(_routedEditApp(repo));
      await tester.pumpAndSettle();

      // The first row cannot move up.
      await tester.tap(find.byTooltip('Move ingredient').first);
      await tester.pumpAndSettle();
      final up = tester.widget<PopupMenuItem<int>>(
        find.widgetWithText(PopupMenuItem<int>, 'Move up'),
      );
      expect(up.enabled, isFalse);
      await tester.tapAt(Offset.zero); // dismiss
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Move ingredient').at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Move up'));
      await tester.pumpAndSettle();
      await save(tester);

      final saved = savedIngredients(repo);
      expect(saved.map((i) => i.name), ['flour', 'milk']);
      expect(saved.map((i) => i.sortOrder), [0, 1]);
      // The rows moved with their values, not just their names.
      expect(saved[0].quantity, 2);
      expect(saved[1].quantity, 0.33);
    });

    testWidgets('the drag handle reorders too', (tester) async {
      sizeView(tester, 800);
      final repo = _RecordingRecipeRepository(loaded: _twoIngredients());
      await tester.pumpWidget(_routedEditApp(repo));
      await tester.pumpAndSettle();

      final handle = find.byIcon(Icons.drag_indicator).at(1);
      final gesture = await tester.startGesture(tester.getCenter(handle));
      for (var i = 0; i < 10; i++) {
        await gesture.moveBy(const Offset(0, -12));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();
      await save(tester);

      expect(savedIngredients(repo).map((i) => i.name), ['flour', 'milk']);
    });

    testWidgets('removing a group with ingredients asks first', (tester) async {
      final groups = [
        EditIngredientGroup(
          name: 'Dough',
          ingredients: [
            EditIngredient(name: 'flour'),
            EditIngredient(name: 'water'),
            EditIngredient(), // blank rows are not counted
          ],
        ),
        EditIngredientGroup(ingredients: [EditIngredient(name: 'salt')]),
        EditIngredientGroup(),
      ];
      final all = [...groups];
      addTearDown(() {
        for (final g in all) {
          if (groups.contains(g)) g.dispose();
        }
      });
      sizeView(tester, 800);
      await tester.pumpWidget(_ingredientsApp(groups));
      await tester.pumpAndSettle();

      // An empty group goes at once.
      await tester.tap(find.byTooltip('Remove group').at(2));
      await tester.pumpAndSettle();
      expect(find.text('Remove this group?'), findsNothing);
      expect(groups, hasLength(2));

      await tester.tap(find.byTooltip('Remove group').first);
      await tester.pumpAndSettle();
      expect(find.text('Remove this group?'), findsOneWidget);
      expect(
        find.text('Its 2 ingredients will be removed too.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Keep'));
      await tester.pumpAndSettle();
      expect(groups, hasLength(2));

      await tester.tap(find.byTooltip('Remove group').last);
      await tester.pumpAndSettle();
      expect(
        find.text('Its 1 ingredient will be removed too.'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await tester.pumpAndSettle();
      expect(groups, hasLength(1));
      expect(groups.single.name.text, 'Dough');
      expect(tester.takeException(), isNull);
    });

    testWidgets('on a phone a saved row is one line that opens on tap', (
      tester,
    ) async {
      sizeView(tester, 390);
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(_routedEditApp(_loadedFlour()));
      await tester.pumpAndSettle();

      // The summary, through core's one chain: `1½ cup Wheat flour`.
      expect(find.widgetWithText(TextField, 'Qty'), findsNothing);
      expect(find.text('1½ cup Wheat flour'), findsOneWidget);
      expect(find.text('sifted · optional'), findsOneWidget);
      expect(find.byIcon(Icons.link), findsOneWidget);
      final summary = find.bySemanticsLabel(
        'Edit 1 and 1 half cup Wheat flour, sifted, optional, '
        'linked to a food',
      );
      expect(summary, findsOneWidget);

      await tester.tap(summary);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'Qty'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Done'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'Qty'), findsNothing);

      // Opening and closing a row is not an edit.
      await tester.tap(find.byTooltip('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsNothing);
      semantics.dispose();
    });

    testWidgets('a wide window always shows the fields; new rows open', (
      tester,
    ) async {
      sizeView(tester, 1000);
      await tester.pumpWidget(_routedEditApp(_loadedFlour()));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'Qty'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Done'), findsNothing);

      tester.view.physicalSize = const Size(390, 5000);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'Qty'), findsNothing);

      final add = find.widgetWithText(TextButton, 'Add ingredient');
      await tester.ensureVisible(add);
      await tester.tap(add);
      await tester.pumpAndSettle();
      // The new row is open; the saved one stays a summary.
      expect(find.widgetWithText(TextField, 'Qty'), findsOneWidget);
      expect(find.text('1½ cup Wheat flour'), findsOneWidget);
    });

    // A collapsed row hides its fields — it must not hide an unreadable
    // quantity from the save. Typed on a wide window, then the window
    // narrows: the row folds to its summary with the bad value inside it.
    testWidgets('a collapsed row with a bad quantity blocks Save and opens', (
      tester,
    ) async {
      sizeView(tester, 1000);
      final repo = _RecordingRecipeRepository(loaded: _loadedFlour().loaded);
      await tester.pumpWidget(_routedEditApp(repo));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, '1½'), 'lots');
      tester.view.physicalSize = const Size(390, 5000);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'Qty'), findsNothing);

      await save(tester);

      expect(repo.updated, isEmpty, reason: 'saved a null quantity silently');
      expect(find.widgetWithText(TextField, 'lots'), findsOneWidget);
      expect(find.text('Try 1/2 or 0.5'), findsOneWidget);
    });

    // UX-039: nutrition moved to the bottom of the page. A manual entry
    // there that is wrong has to (a) still be validated after the cook has
    // scrolled away from it, and (b) be scrolled back into view when it is
    // what refused the save — at a real phone's height, not a 5000px one.
    testWidgets('a bad nutrition entry far below is validated and revealed', (
      tester,
    ) async {
      sizeView(tester, 390, 844);
      final repo = _RecordingRecipeRepository();
      await tester.pumpWidget(_routedNewApp(repo));
      await tester.pumpAndSettle();

      // Off stage but built (B142) — hence `skipOffstage: false` to reach
      // what is below the fold.
      final add = find.widgetWithText(TextButton, 'Add', skipOffstage: false);
      await tester.ensureVisible(add);
      await tester.pumpAndSettle();
      await tester.tap(add);
      await tester.pumpAndSettle();
      final manual = find.widgetWithText(
        ChoiceChip,
        'Manual',
        skipOffstage: false,
      );
      await tester.ensureVisible(manual);
      await tester.pumpAndSettle();
      await tester.tap(manual);
      await tester.pumpAndSettle();
      final calories = find.widgetWithText(
        TextFormField,
        'Calories',
        skipOffstage: false,
      );
      await tester.ensureVisible(calories);
      await tester.pumpAndSettle();
      await tester.enterText(calories, '1/2');
      // Let the field's caret-into-view scroll finish first, or it lands after
      // the scroll below and carries the page back down to Calories.
      await tester.pumpAndSettle();

      // Back to the top; focus leaves the Calories box for Title.
      await tester.ensureVisible(_titleField);
      await tester.pumpAndSettle();
      await _fillRequired(tester);
      await tester.ensureVisible(_titleField);
      await tester.pumpAndSettle();

      await save(tester);

      expect(repo.created, isEmpty, reason: 'the bad entry was not validated');
      final error = find.textContaining('Numbers only');
      expect(error, findsOneWidget);
      final view = Offset.zero & const Size(390, 844);
      expect(
        view.contains(tester.getCenter(error)),
        isTrue,
        reason: 'the refused save left its reason off screen',
      );
    });

    // Phase 39: the page is slivers now (so a drag can scroll it), and slivers
    // build lazily. B142 needs every row built wherever the page is scrolled:
    // a quantity typed far down a long list, then scrolled away from, must
    // still refuse the save and be brought back into view.
    testWidgets('a bad quantity far down a long list is validated and '
        'revealed (B142)', (tester) async {
      sizeView(tester, 390, 844);
      final repo = _RecordingRecipeRepository(loaded: _manyIngredients(60));
      await tester.pumpWidget(_routedEditApp(repo));
      await tester.pumpAndSettle();

      // Built without a scroll: every row, the last one included, is in the
      // tree — though the last is far below the window, so a default
      // (on-stage) finder does not see it.
      final last = find.textContaining(_row(60), skipOffstage: false);
      expect(last, findsOneWidget);
      expect(find.textContaining(_row(60)), findsNothing);
      expect(
        find.byType(ReorderableDragStartListener, skipOffstage: false),
        findsAtLeastNWidgets(60),
      );

      // Scroll down to the last row the way a cook does, open it and type
      // something unreadable into it…
      await tester.scrollUntilVisible(
        find.textContaining(_row(60)),
        200,
        scrollable:
            find
                .descendant(
                  of: find.byType(CustomScrollView),
                  matching: find.byType(Scrollable),
                )
                .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining(_row(60)));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Qty'), 'lots');
      await tester.pumpAndSettle();

      // …then go back to the top and put the focus there, so nothing is
      // keeping the row alive but the page itself.
      final title = find.widgetWithText(
        TextFormField,
        'Loaded Recipe',
        skipOffstage: false,
      );
      await tester.ensureVisible(title);
      await tester.pumpAndSettle();
      await tester.enterText(title, 'Loaded Recipe');
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'lots'), findsNothing);
      expect(
        find.widgetWithText(TextField, 'lots', skipOffstage: false),
        findsOneWidget,
        reason: 'the row was thrown away once scrolled off',
      );

      await save(tester);

      expect(repo.updated, isEmpty, reason: 'saved a null quantity silently');
      final error = find.text('Try 1/2 or 0.5');
      expect(error, findsOneWidget);
      expect(
        (Offset.zero & const Size(390, 844)).contains(tester.getCenter(error)),
        isTrue,
        reason: 'the refused save left its reason off screen',
      );
    });

    // Phase 39: each group's rows used to be a shrink-wrapped
    // `ReorderableListView`, whose drag auto-scroller drove the list's own
    // zero-extent scrollable — so a row dragged to the window's edge never
    // scrolled the page, and a long list could only be reordered a screen at
    // a time. The rows are a `SliverReorderableList` in the page's viewport
    // now, and holding a drag at the bottom edge scrolls the page.
    testWidgets('dragging a row to the window edge scrolls the page', (
      tester,
    ) async {
      sizeView(tester, 390, 844);
      final repo = _RecordingRecipeRepository(loaded: _manyIngredients(30));
      await tester.pumpWidget(_routedEditApp(repo));
      await tester.pumpAndSettle();

      // The page's own scrollable: the outermost one, first in tree order
      // (every other — a text field's, an old nested list's — is inside it).
      final page = tester.state<ScrollableState>(find.byType(Scrollable).first);

      // The first row near the top of the window.
      final handle =
          find.byIcon(Icons.drag_indicator, skipOffstage: false).first;
      await tester.ensureVisible(handle);
      await tester.pumpAndSettle();
      page.position.jumpTo(
        page.position.pixels + tester.getTopLeft(handle).dy - 200,
      );
      await tester.pumpAndSettle();

      final before = page.position.pixels;
      // The last row whose top is inside the window — measured rather than
      // asked of an on-stage finder, so the same test runs against the old
      // shrink-wrapped layout (where every row counts as on stage).
      double top(int i) =>
          tester
              .getTopLeft(find.textContaining(_row(i), skipOffstage: false))
              .dy;
      final lastVisible =
          [
            for (var i = 1; i <= 30; i++)
              if (top(i) < 844) i,
          ].last;
      expect(lastVisible, lessThan(30), reason: 'the list must overflow');

      // Drag row 1 to the bottom edge of the window, and hold it there.
      final start = tester.getCenter(handle);
      final gesture = await tester.startGesture(start);
      const edge = 844.0 - AppSpacing.xs;
      for (var i = 1; i <= 10; i++) {
        await gesture.moveTo(
          Offset(start.dx, start.dy + (edge - start.dy) * i / 10),
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
      for (var i = 0; i < 90; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(
        page.position.pixels,
        greaterThan(before),
        reason: 'holding a drag at the edge did not scroll the page',
      );

      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await save(tester);

      // The order is the draft's, and it saves (B022: ascending by position).
      final names = [for (final i in savedIngredients(repo)) i.name];
      expect(names, hasLength(30));
      expect(
        names.indexOf('row 01'),
        greaterThan(lastVisible - 1),
        reason: 'row 01 did not travel past the rows visible when it started',
      );
      expect(savedIngredients(repo).map((i) => i.sortOrder), [
        for (var i = 0; i < 30; i++) i,
      ]);
    });

    testWidgets('Not counted lists a repeated ingredient once', (tester) async {
      sizeView(tester, 800);
      await tester.pumpWidget(
        _editApp(_LoadedRecipeRepository(_repeatedOnionRecipe())),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('not linked to a food'), findsOneWidget);
      // First spelling kept.
      expect(
        find.textContaining('onion — not linked to a food'),
        findsOneWidget,
      );

      // One confirmation links both rows.
      await tester.tap(find.widgetWithText(ActionChip, 'All-purpose flour'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Estimated from 3 of 3 ingredients'),
        findsOneWidget,
      );
    });

    // The Auto pane read the quantity box with `double.tryParse`, which the
    // fraction display (`1½`) fails — every fractional amount read as
    // "no quantity".
    testWidgets('a fractional quantity is not reported as missing', (
      tester,
    ) async {
      sizeView(tester, 800);
      await tester.pumpWidget(
        _editApp(
          _LoadedRecipeRepository(
            _autoRecipe(flourQuantity: 1.5, flourUnit: 'cup'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextField, '1½'), findsOneWidget);
      expect(find.textContaining('no quantity'), findsNothing);
    });

    // The envelope (Gotcha 13/22/26): the whole editor, collapsed rows and
    // open ones, with a quantity error showing, at four widths × two scales.
    for (final width in <double>[390, 600, 1000, 1440]) {
      for (final scale in <double>[1.0, 2.0]) {
        testWidgets('the editor fits at ${width}px, textScale $scale', (
          tester,
        ) async {
          sizeView(tester, width, 8000);
          final repo = _RecordingRecipeRepository(loaded: _envelopeRecipe);
          await tester.pumpWidget(_routedEditApp(repo, textScale: scale));
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: 'editor overflows at ${width}px @ ${scale}x',
          );

          if (width < 600) {
            // Collapsed first; open every row.
            expect(find.widgetWithText(TextField, 'Qty'), findsNothing);
            for (var i = 0; i < 3; i++) {
              final summary = find.byIcon(Icons.edit_outlined).first;
              await tester.ensureVisible(summary);
              await tester.tap(summary);
              await tester.pumpAndSettle();
            }
          }
          expect(find.widgetWithText(TextField, 'Qty'), findsNWidgets(3));
          expect(
            tester.takeException(),
            isNull,
            reason: 'open rows overflow at ${width}px @ ${scale}x',
          );

          await tester.enterText(
            find.widgetWithText(TextField, 'Qty').first,
            'lots',
          );
          await save(tester);
          expect(repo.updated, isEmpty);
          expect(
            tester.takeException(),
            isNull,
            reason: 'quantity error overflows at ${width}px @ ${scale}x',
          );
          final message = find.text('Try 1/2 or 0.5');
          expect(message, findsOneWidget);
          expect(
            tester.renderObject<RenderParagraph>(message).didExceedMaxLines,
            isFalse,
          );
        });
      }
    }
  });

  // UX-048: every control in the editor is at least 48 × 48 (WCAG 2.5.8 via
  // Flutter's Android guideline, the stricter of the two it ships) — a loaded
  // recipe with two ingredient rows, a detailed step and the Auto nutrition
  // pane, so every row control and group action is on screen.
  for (final width in [390.0, 1440.0]) {
    testWidgets('every tap target meets the 48dp guideline at ${width}px', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      tester.view.physicalSize = Size(width, 6000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final recipe = _autoRecipe().copyWith(
        description: 'A weeknight flatbread.',
        stepGroups: [
          StepGroup(
            id: 'g1',
            recipeId: 'r1',
            name: 'Method',
            steps: [
              // No photo: a network image never settles, and the photo
              // tile's buttons are covered by the step photo group.
              _fullStep.copyWith(imageUrl: null),
              const RecipeStep(
                id: 's2',
                groupId: 'g1',
                stepOrder: 4,
                text: 'Rest for five minutes.',
                sortOrder: 4,
              ),
            ],
          ),
        ],
      );
      await tester.pumpWidget(_editApp(_LoadedRecipeRepository(recipe)));
      await tester.pumpAndSettle();
      expect(find.text('Rest for five minutes.'), findsOneWidget);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      // The food chips are measured directly as well: the guideline skips a
      // node it judges to be at a scrollable's edge, and it judged the Auto
      // pane's suggestion chip to be at one while it sat mid-form at 40px.
      // (The link chip shows only on an open row — the wide layout's.)
      final suggestion = find.widgetWithText(ActionChip, 'All-purpose flour');
      expect(suggestion, findsOneWidget);
      for (final chip in [find.byType(InputChip), suggestion]) {
        for (final element in chip.evaluate()) {
          expect(
            tester.getSize(find.byWidget(element.widget)).height,
            greaterThanOrEqualTo(kMinInteractiveDimension),
          );
        }
      }
      handle.dispose();
    });
  }
}

/// The editor in edit mode (`recipeId` non-null) over stub repositories.
Widget _editApp(
  RecipeRepository repo, {
  double textScale = 1.0,
  FoodRepository? food,
}) => ProviderScope(
  overrides: [
    recipeRepositoryProvider.overrideWithValue(repo),
    foodRepositoryProvider.overrideWithValue(food ?? _StubFoodRepository()),
  ],
  child: MaterialApp(
    theme: AppTheme.light(),
    builder:
        (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
    home: const RecipeEditorScreen(recipeId: 'r1'),
  ),
);

/// Signed in, offline. `_save` reads `currentUserIdProvider` for the owner id,
/// which without this override reaches the real `SupabaseAuthRepository` and
/// asserts that `Supabase.instance` was initialised — an exception `_save`
/// catches, so the save "fails" for a reason that has nothing to do with the
/// repository under test. It cost two red tests to find (32e2).
class _FakeAuth implements AuthRepository {
  @override
  String? get currentUserId => 'me';

  // Phase 35b: `profiles.id` and the auth uid are the same value for a member,
  // which every fixture in this file is.
  @override
  Future<String?> currentProfileId() async => 'me';

  @override
  Stream<AuthState> authStateChanges() => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}

/// The Title field of an empty editor, found by its label rather than its value.
/// Off stage included: the page is slivers, so a header scrolled out of view is
/// built but not "on stage" to a default finder (B142 keeps it built).
final Finder _titleField = find.ancestor(
  of: find.text('Title', skipOffstage: false),
  matching: find.byType(TextFormField, skipOffstage: false),
);

/// The Servings field, by its label.
final Finder _servingsField = find.ancestor(
  of: find.text('Servings', skipOffstage: false),
  matching: find.byType(TextFormField, skipOffstage: false),
);

/// A new recipe's required fields (UX-039): a title, a serving count and a
/// difficulty — the last two have no default any more, so a save that skips
/// them is refused.
Future<void> _fillRequired(
  WidgetTester tester, {
  String title = 'Suya-Spiced Lamb',
  String servings = '4',
}) async {
  await tester.enterText(_titleField, title);
  await tester.enterText(_servingsField, servings);
  final difficulty = find.byType(DropdownButtonFormField<Difficulty>);
  await tester.ensureVisible(difficulty);
  await tester.pumpAndSettle();
  await tester.tap(difficulty);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Medium').last);
  await tester.pumpAndSettle();
}

/// Records what `_save` sent, and can refuse (32e2).
///
/// `getById` answers the same loaded recipe `_loadedRepo` uses, so one fake
/// covers both the create and the edit path.
class _RecordingRecipeRepository implements RecipeRepository {
  _RecordingRecipeRepository({this.fail = false, Recipe? loaded})
    : loaded = loaded ?? _plain;

  final bool fail;

  /// What the edit path loads. Overridable so one fake covers "the recipe
  /// already has a step photo" as well as the plain case.
  final Recipe loaded;

  final List<Recipe> created = [];
  final List<(Recipe, String)> updated = [];

  static const _plain = Recipe(
    id: 'r1',
    ownerId: 'me',
    title: 'Loaded Recipe',
    servings: 4,
  );

  @override
  Future<Recipe> getById(String id) async => loaded;

  @override
  Future<Recipe> create(Recipe recipe) async {
    if (fail) throw Exception('denied');
    created.add(recipe);
    return recipe.copyWith(id: 'r-new');
  }

  @override
  Future<Recipe> update(
    Recipe recipe, {
    String changeSummary = 'Updated',
  }) async {
    if (fail) throw Exception('denied');
    updated.add((recipe, changeSummary));
    return recipe;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}

/// A load that never lands — the only way to hold the editor in its loading
/// state long enough to assert what it does *not* offer there.
class _HangingRecipeRepository implements RecipeRepository {
  @override
  Future<Recipe> getById(String id) => Completer<Recipe>().future;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}

/// The editor in **create** mode behind a real router, so `_save`'s
/// `context.go(Routes.recipe(saved.id))` has somewhere to land.
Widget _routedNewApp(
  RecipeRepository repo, {
  ImagePickFn? pick,
  StorageService? storage,
  double textScale = 1.0,
}) => ProviderScope(
  overrides: [
    recipeRepositoryProvider.overrideWithValue(repo),
    authRepositoryProvider.overrideWithValue(_FakeAuth()),
    foodRepositoryProvider.overrideWithValue(_StubFoodRepository()),
    if (pick != null) imagePickerProvider.overrideWithValue(pick),
    if (storage != null) storageServiceProvider.overrideWithValue(storage),
  ],
  child: MaterialApp.router(
    theme: AppTheme.light(),
    builder: (context, child) => _scaled(context, child!, textScale),
    routerConfig: GoRouter(
      initialLocation: Routes.newRecipe,
      routes: [
        GoRoute(
          path: Routes.newRecipe,
          builder: (_, __) => const RecipeEditorScreen(),
        ),
        GoRoute(
          path: Routes.recipePattern,
          builder: (_, __) => const Scaffold(body: Text('RECIPE PAGE')),
        ),
        GoRoute(
          path: Routes.myRecipes,
          builder: (_, __) => const Scaffold(body: Text('MY RECIPES')),
        ),
      ],
    ),
  ),
);

/// One loaded recipe with nothing exotic in it — the leaving tests only need a
/// form with real content in its fields.
_LoadedRecipeRepository _loadedRepo() => _LoadedRecipeRepository(
  const Recipe(id: 'r1', ownerId: 'me', title: 'Loaded Recipe', servings: 4),
);

/// The editor behind a **real router**, which the leaving tests need twice
/// over: `_leave()` calls `context.canPop()` (a GoRouter extension, so a bare
/// `MaterialApp` throws), and "did it actually leave?" has to have somewhere to
/// land. Entered at the edit route with nothing under it, which is the deep-link
/// shape — so a discard `go`es to the recipe rather than popping.
Widget _routedEditApp(
  RecipeRepository repo, {
  ImagePickFn? pick,
  StorageService? storage,
  double textScale = 1.0,
}) => ProviderScope(
  overrides: [
    recipeRepositoryProvider.overrideWithValue(repo),
    authRepositoryProvider.overrideWithValue(_FakeAuth()),
    foodRepositoryProvider.overrideWithValue(_StubFoodRepository()),
    if (pick != null) imagePickerProvider.overrideWithValue(pick),
    if (storage != null) storageServiceProvider.overrideWithValue(storage),
  ],
  child: MaterialApp.router(
    theme: AppTheme.light(),
    builder: (context, child) => _scaled(context, child!, textScale),
    routerConfig: GoRouter(
      initialLocation: '/recipe/r1/edit',
      routes: [
        GoRoute(
          path: Routes.editRecipePattern,
          builder:
              (_, state) =>
                  RecipeEditorScreen(recipeId: state.pathParameters['id']),
        ),
        GoRoute(
          path: Routes.recipePattern,
          builder: (_, __) => const Scaffold(body: Text('RECIPE PAGE')),
        ),
        GoRoute(
          path: Routes.myRecipes,
          builder: (_, __) => const Scaffold(body: Text('MY RECIPES')),
        ),
      ],
    ),
  ),
);

/// [child] under a text scale — the routed apps' envelope knob.
Widget _scaled(BuildContext context, Widget child, double textScale) =>
    MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child,
    );

/// `IngredientsEditor` on its own, the way the food-link group pumps it.
Widget _ingredientsApp(
  List<EditIngredientGroup> groups, {
  double textScale = 1.0,
}) => ProviderScope(
  overrides: [foodRepositoryProvider.overrideWithValue(_StubFoodRepository())],
  child: MaterialApp(
    theme: AppTheme.light(),
    builder: (context, child) => _scaled(context, child!, textScale),
    home: Scaffold(
      body: CustomScrollView(
        slivers: [
          StatefulBuilder(
            builder:
                (context, setState) => IngredientsEditor(
                  groups: groups,
                  onChanged: () => setState(() {}),
                ),
          ),
        ],
      ),
    ),
  ),
);

/// Two rows in one group: a loaded `0.33 cup` (shown as `1⁄3`) and a plain
/// `2 cups` — for the reorder and fraction tests.
Recipe _twoIngredients() => const Recipe(
  id: 'r1',
  ownerId: 'me',
  title: 'Loaded Recipe',
  servings: 4,
  ingredientGroups: [
    IngredientGroup(
      id: 'g1',
      recipeId: 'r1',
      name: '',
      ingredients: [
        Ingredient(
          id: 'i1',
          groupId: 'g1',
          quantity: 0.33,
          unit: 'cup',
          name: 'milk',
          isOptional: false,
          sortOrder: 0,
        ),
        Ingredient(
          id: 'i2',
          groupId: 'g1',
          quantity: 2,
          unit: 'cups',
          name: 'flour',
          isOptional: false,
          sortOrder: 1,
        ),
      ],
    ),
  ],
);

/// A loaded recipe with one group of [count] plain rows, `row 01` … — for the
/// long-list tests (B142 at length, and the drag auto-scroll).
Recipe _manyIngredients(int count) => Recipe(
  id: 'r1',
  ownerId: 'me',
  title: 'Loaded Recipe',
  servings: 4,
  ingredientGroups: [
    IngredientGroup(
      id: 'g1',
      recipeId: 'r1',
      name: '',
      ingredients: [
        for (var i = 1; i <= count; i++)
          Ingredient(
            id: 'i$i',
            groupId: 'g1',
            quantity: 1,
            unit: 'cup',
            name: 'row ${i.toString().padLeft(2, '0')}',
            isOptional: false,
            sortOrder: i - 1,
          ),
      ],
    ),
  ],
);

/// Row [i] of [_manyIngredients], as a pattern over its one-line summary
/// (which capitalises the name).
Pattern _row(int i) =>
    RegExp('row ${i.toString().padLeft(2, '0')}\$', caseSensitive: false);

/// One linked, noted, optional `1.5 cup wheat flour` — the compact summary's
/// fixture (`1½ cup Wheat flour`).
_RecordingRecipeRepository _loadedFlour() => _RecordingRecipeRepository(
  loaded: const Recipe(
    id: 'r1',
    ownerId: 'me',
    title: 'Loaded Recipe',
    servings: 4,
    ingredientGroups: [
      IngredientGroup(
        id: 'g1',
        recipeId: 'r1',
        name: '',
        ingredients: [
          Ingredient(
            id: 'i1',
            groupId: 'g1',
            quantity: 1.5,
            unit: 'cup',
            name: 'wheat flour',
            note: 'sifted',
            isOptional: true,
            sortOrder: 0,
            foodId: 'all-purpose-flour',
          ),
        ],
      ),
    ],
  ),
);

/// Two groups and three rows with every marker a row can carry — the
/// envelope's fixture.
const Recipe _envelopeRecipe = Recipe(
  id: 'r1',
  ownerId: 'me',
  title: 'Slow-Roasted Pork Shoulder with Crackling and Apple Sauce',
  servings: 12,
  prepMinutes: 30,
  cookMinutes: 360,
  ingredientGroups: [
    IngredientGroup(
      id: 'g1',
      recipeId: 'r1',
      name: 'For the pork and its overnight dry brine',
      ingredients: [
        Ingredient(
          id: 'i1',
          groupId: 'g1',
          quantity: 2.75,
          unit: 'tablespoons',
          name: 'coarse flaky sea salt, preferably Maldon or Halen Môn',
          note: 'crushed between your fingers',
          isOptional: true,
          sortOrder: 0,
          foodId: 'salt',
        ),
        Ingredient(
          id: 'i2',
          groupId: 'g1',
          name: 'black pepper',
          note: 'to taste',
          isOptional: false,
          sortOrder: 1,
        ),
      ],
    ),
    IngredientGroup(
      id: 'g2',
      recipeId: 'r1',
      name: 'Apple sauce',
      ingredients: [
        Ingredient(
          id: 'i3',
          groupId: 'g2',
          quantity: 1.3333333333333333,
          unit: 'kg',
          name: 'Bramley apples',
          isOptional: false,
          sortOrder: 0,
        ),
      ],
    ),
  ],
);

/// [_autoRecipe] with the same free-text ingredient in both groups, spelled
/// two ways — the not-counted list must name it once.
Recipe _repeatedOnionRecipe() {
  final base = _autoRecipe();
  return base.copyWith(
    ingredientGroups: [
      ...base.ingredientGroups,
      const IngredientGroup(
        id: 'g2',
        recipeId: 'r1',
        name: 'Topping',
        ingredients: [
          Ingredient(
            id: 'i3',
            groupId: 'g2',
            quantity: 1,
            name: 'Onion',
            isOptional: false,
            sortOrder: 0,
          ),
        ],
      ),
    ],
  );
}

/// Registry stub for the typeahead: two flours for a `flo…` query, nothing for
/// anything else — enough to cover pick, free-text, and empty-result paths.
///
/// The 29c halves mimic the server's honesty contract instead of canning one
/// reply: `estimate` counts the rows that could contribute (linked, with a
/// quantity) and names the rest, returning a null label when nothing counted —
/// so the mode tests exercise the same shapes the real RPC produces.
class _StubFoodRepository implements FoodRepository {
  @override
  Future<List<FoodHit>> search(String query, {int limit = 10}) async =>
      query.startsWith('flo')
          ? const [
            FoodHit(id: 'all-purpose-flour', displayName: 'All-purpose flour'),
            FoodHit(id: 'bread-flour', displayName: 'Bread flour'),
          ]
          : const [];

  @override
  Future<Map<String, String>> displayNames(List<String> ids) async => const {};

  @override
  Future<NutritionEstimate> estimate({
    required List<IngredientGroup> ingredientGroups,
    required int servings,
  }) async {
    final rows = [for (final g in ingredientGroups) ...g.ingredients];
    final counted =
        rows.where((i) => i.foodId != null && i.quantity != null).length;
    return NutritionEstimate(
      label:
          counted == 0
              ? null
              : const RecipeNutrition(
                calories: 250,
                proteinG: 12,
                source: 'auto',
              ),
      counted: counted,
      total: rows.length,
      unmatched: [
        for (final i in rows)
          if (i.foodId == null || i.quantity == null) i.name,
      ],
    );
  }

  @override
  Future<Map<String, List<FoodHit>>> matchFoods(List<String> names) async => {
    for (final n in names)
      n: const [
        FoodHit(id: 'all-purpose-flour', displayName: 'All-purpose flour'),
      ],
  };
}

/// [_StubFoodRepository] that records the serving count each estimate was
/// asked for — the servings field is a divisor, so "did it re-estimate?" is
/// the only thing worth asserting about that input.
class _RecordingFoodRepository extends _StubFoodRepository {
  final List<int> servingsSeen = [];

  @override
  Future<NutritionEstimate> estimate({
    required List<IngredientGroup> ingredientGroups,
    required int servings,
  }) {
    servingsSeen.add(servings);
    return super.estimate(
      ingredientGroups: ingredientGroups,
      servings: servings,
    );
  }
}

/// A recipe whose stored label claims `source: 'auto'` (the stored 999 is
/// deliberately NOT what the stub estimates — the pane must show the fresh
/// estimate, and Auto -> Manual must seed the fresh values, never the stale
/// stored ones). One linked row with a quantity, one free-text row.
Recipe _autoRecipe({
  bool linked = true,
  double flourQuantity = 200,
  String flourUnit = 'g',
}) => Recipe(
  id: 'r1',
  ownerId: 'me',
  title: 'Auto Recipe',
  servings: 4,
  nutrition: const RecipeNutrition(calories: 999, source: 'auto'),
  ingredientGroups: [
    IngredientGroup(
      id: 'g1',
      recipeId: 'r1',
      name: 'Main',
      ingredients: [
        if (linked)
          Ingredient(
            id: 'i1',
            groupId: 'g1',
            quantity: flourQuantity,
            unit: flourUnit,
            name: 'flour',
            isOptional: false,
            sortOrder: 0,
            foodId: 'all-purpose-flour',
          ),
        const Ingredient(
          id: 'i2',
          groupId: 'g1',
          quantity: 1,
          name: 'onion',
          isOptional: false,
          sortOrder: 1,
        ),
      ],
    ),
  ],
);

/// Loads one fixed recipe — the 29c mode tests' edit-path entry.
class _LoadedRecipeRepository implements RecipeRepository {
  _LoadedRecipeRepository(this.recipe);

  final Recipe recipe;

  @override
  Future<Recipe> getById(String id) async => recipe;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}

/// Fails `getById` [failures] times, then succeeds — so one stub covers both the
/// permanent-failure and the retry-recovers cases.
class _ThrowingRecipeRepository implements RecipeRepository {
  _ThrowingRecipeRepository({this.failures = 1 << 30});

  int failures;

  @override
  Future<Recipe> getById(String id) async {
    if (failures > 0) {
      failures--;
      throw Exception('offline');
    }
    return const Recipe(
      id: 'r1',
      ownerId: 'me',
      title: 'Loaded Recipe',
      servings: 4,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}

/// `StepsEditor` on its own, the way the food-link group pumps
/// `IngredientsEditor`: the envelope belongs to the row, and dragging the whole
/// form (and its 16:9 cover tile) into every pump only adds noise.
Widget _stepsApp(List<EditStepGroup> groups, {double textScale = 1.0}) =>
    MaterialApp(
      theme: AppTheme.light(),
      builder:
          (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
      home: Scaffold(
        body: StatefulBuilder(
          builder:
              (context, setState) => CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    sliver: StepsEditor(
                      groups: groups,
                      onChanged: () => setState(() {}),
                      onPickImage: (_) {},
                    ),
                  ),
                ],
              ),
        ),
      ),
    );

/// A loaded recipe whose only step already carries a photo — the "edit
/// something that has one" half of the picker's cover.
const Recipe _recipeWithStepPhoto = Recipe(
  id: 'r1',
  ownerId: 'me',
  title: 'Loaded Recipe',
  servings: 4,
  stepGroups: [
    StepGroup(
      id: 'sg1',
      recipeId: 'r1',
      name: 'Method',
      steps: [
        RecipeStep(
          id: 's1',
          groupId: 'sg1',
          stepOrder: 0,
          sortOrder: 0,
          text: 'Sear the lamb hard on one side.',
          imageUrl: 'https://cdn.test/me/stored.jpg',
        ),
      ],
    ),
  ],
);

/// Records what the editor uploaded and hands back a public URL, the shape
/// `StorageService` really returns. Implemented rather than subclassed: the
/// real one needs a `SupabaseClient`, and its `_upload` is private, so the
/// public surface is the whole contract a caller can see.
class _FakeStorageService implements StorageService {
  /// (fileName, byte length) per upload.
  final List<(String, int)> uploads = [];

  @override
  Future<String> uploadRecipeImage({
    required String fileName,
    required List<int> bytes,
    String contentType = 'image/jpeg',
  }) async {
    uploads.add((fileName, bytes.length));
    return 'https://cdn.test/$fileName';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}
