// Regression cover for B035: the editor used to model a step as its text and
// nothing else, so `temperature`, `duration_minutes`, `tip` and `image_url`
// (and an ingredient's `note` / `is_optional`) were unreachable when creating a
// recipe *and* silently erased when editing one that had them — `update()`
// deletes the groups and re-inserts whatever `toModel()` produces.
//
// The round-trip group is the load-bearing half: it fails if any field is
// dropped between the core model and the editor's mutable draft types. The
// widget group covers the envelope the new inputs have to survive (Gotcha 13).
import 'package:app/features/recipe_editor/edit_models.dart';
import 'package:app/features/recipe_editor/ingredients_editor.dart';
import 'package:app/features/recipe_editor/recipe_editor_screen.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
    // The form is a plain `ListView(children: …)`, so anything below the fold
    // is never built and no finder can reach it. Give the tests a viewport tall
    // enough to build the whole form instead of scripting scrolls.
    void sizeView(WidgetTester tester, double width) {
      tester.view.physicalSize = Size(width, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    testWidgets('step details reveal time, temperature and tip', (
      tester,
    ) async {
      sizeView(tester, 800);
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();

      expect(find.text('Temperature'), findsNothing);

      await tester.tap(find.byTooltip('Time, temperature & tip'));
      await tester.pumpAndSettle();

      expect(find.text('Time (min)'), findsOneWidget);
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

    // Phase 28. The panel is collapsed on a new recipe — eleven empty boxes
    // between Attribution and Ingredients would push the parts of the form
    // everyone uses off the first screen.
    testWidgets('nutrition starts collapsed and opens on Add', (tester) async {
      sizeView(tester, 800);
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();

      expect(find.text('Nutrition facts'), findsOneWidget);
      expect(find.text('Cholesterol'), findsNothing);

      await tester.tap(find.widgetWithText(TextButton, 'Add'));
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
          reason: 'nutrition panel overflows at ${width}px @ 2.0x',
        );

        await tester.tap(find.byTooltip('Note & optional'));
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: 'ingredient note row overflows at ${width}px @ 2.0x',
        );

        await tester.tap(find.byTooltip('Time, temperature & tip'));
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
            home: Scaffold(
              body: SingleChildScrollView(
                child: StatefulBuilder(
                  builder:
                      (context, setState) => IngredientsEditor(
                        groups: groups,
                        onChanged: () => setState(() {}),
                      ),
                ),
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

  // B052 / OPT-S4. `_load()` was try/finally with no catch: a failed getById
  // escaped as an unhandled future and the form rendered its empty defaults over
  // a recipe that still exists. Because `update()` replaces content wholesale,
  // one Save then deleted every ingredient and step group it had.
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
}

/// The editor in edit mode (`recipeId` non-null) over a stub repository.
Widget _editApp(RecipeRepository repo) => ProviderScope(
  overrides: [recipeRepositoryProvider.overrideWithValue(repo)],
  child: MaterialApp(
    theme: AppTheme.light(),
    home: const RecipeEditorScreen(recipeId: 'r1'),
  ),
);

/// Registry stub for the typeahead: two flours for a `flo…` query, nothing for
/// anything else — enough to cover pick, free-text, and empty-result paths.
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
