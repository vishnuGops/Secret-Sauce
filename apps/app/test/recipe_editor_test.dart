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
);

Widget _app({double textScale = 1.0}) => ProviderScope(
      child: MaterialApp(
        theme: AppTheme.light(),
        // `builder`, not a MediaQuery around `home` — same reason as the chefs
        // tests: overlays sit above the Navigator.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
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

    test('EditIngredient preserves note and isOptional', () {
      final draft = EditIngredient.fromModel(_fullIngredient);
      final out = draft.toModel(2);

      expect(out.quantity, 1.25);
      expect(out.unit, 'cups');
      expect(out.name, 'plain flour');
      expect(out.note, 'sifted');
      expect(out.isOptional, isTrue);
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

    testWidgets('step details reveal time, temperature and tip',
        (tester) async {
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

    testWidgets('ingredient details reveal note and the optional toggle',
        (tester) async {
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
      expect(
        tester.widget<Checkbox>(find.byType(Checkbox)).value,
        isTrue,
      );
    });

    // Both new blocks are Rows with intrinsic siblings, the shape behind
    // B001/B002/B016/B023. Check them at the narrowest phone and 2.0x.
    for (final width in <double>[320, 360, 600]) {
      testWidgets('expanded detail rows fit at ${width}px, textScale 2.0',
          (tester) async {
        sizeView(tester, width);

        await tester.pumpWidget(_app(textScale: 2.0));
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: 'collapsed form overflows at ${width}px @ 2.0x',
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
}
