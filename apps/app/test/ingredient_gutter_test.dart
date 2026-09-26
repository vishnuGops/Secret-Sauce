// UX-030, client half: the quantity gutter never collides with the name.
//
// Imported recipes carry long, non-canonical units. The import canonicalises
// the spellings it knows (`tablespoon` -> `tbsp`), but an unknown one
// (`handfuls`, `sprigs`, `quarts`) passes through, and a label that fills the
// fixed gutter used to run flush into the name. Both surfaces that draw the
// gutter are pinned here: the reading rail (through `RailPanel`, the host both
// detail layouts place) and cook mode's "For this step" panel.
//
// The assertions are relational (the quantity's box ends a gap before the
// name's begins; every laid-out line sits inside the paragraph that sits inside
// the gutter), never pixel widths: `flutter test`'s font is far wider than the
// real one.
import 'package:app/features/recipe_detail/cook_mode_model.dart';
import 'package:app/features/recipe_detail/cook_step_view.dart';
import 'package:app/features/recipe_detail/detail_layout.dart';
import 'package:app/features/recipe_detail/rail_panel.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The gap both surfaces leave between the gutter and the name.
const double _kGap = AppSpacing.sm;

/// Layout rounding slack for the relational checks.
const double _kEpsilon = 0.01;

const _ingredients = [
  Ingredient(
    id: 'i1',
    groupId: 'ig1',
    quantity: 3,
    unit: 'tablespoons',
    name: 'olive oil',
  ),
  Ingredient(
    id: 'i2',
    groupId: 'ig1',
    quantity: 2,
    unit: 'handfuls',
    name: 'basil',
  ),
  Ingredient(
    id: 'i3',
    groupId: 'ig1',
    quantity: 12,
    unit: 'ounces',
    name: 'spaghetti',
  ),
  // One word wider than the gutter at every scale: it has to break inside the
  // gutter rather than paint across into the name.
  Ingredient(
    id: 'i4',
    groupId: 'ig1',
    quantity: 1,
    unit: 'supercalifragilistic',
    name: 'flour',
  ),
];

const _recipe = Recipe(
  id: 'r1',
  ownerId: 'o',
  title: 'Imported pasta',
  servings: 4,
  ingredientGroups: [
    IngredientGroup(
      id: 'ig1',
      recipeId: 'r1',
      name: 'Pasta',
      ingredients: _ingredients,
    ),
  ],
  stepGroups: [
    StepGroup(
      id: 'sg1',
      recipeId: 'r1',
      name: '',
      steps: [
        // Names every ingredient, so cook mode's panel lists all four.
        RecipeStep(
          id: 's1',
          groupId: 'sg1',
          text:
              'Warm the olive oil, add the spaghetti, tear in the basil and '
              'dust with flour.',
        ),
        RecipeStep(id: 's2', groupId: 'sg1', text: 'Serve.'),
      ],
    ),
  ],
);

void _sizeView(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Widget _app(Widget child, {required double textScale, ThemeData? theme}) {
  return ProviderScope(
    child: MaterialApp(
      theme: theme ?? AppTheme.light(),
      builder:
          (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
      home: child,
    ),
  );
}

/// The width the real layouts hand the rail: compact's content box (the
/// window less its side gutters), or expanded's rail column, which grows with
/// the type up to [kDetailRailMaxScale].
double _railWidth(double window, double textScale) =>
    window >= 1000
        ? kDetailRailWidth * textScale.clamp(1.0, kDetailRailMaxScale)
        : window - 2 * AppSpacing.md;

/// Checks one row: [qty] is the quantity `Text`, [name] the name's.
///
/// Returns whether the quantity filled its gutter — the case the gap exists
/// for, so the caller can prove the fixture actually reached it.
bool _expectRowClear(
  WidgetTester tester,
  Finder qty,
  Finder name, {
  required String label,
}) {
  expect(qty, findsOneWidget, reason: 'quantity "$label"');
  expect(name, findsOneWidget, reason: 'name beside "$label"');

  final gutter = find.ancestor(of: qty, matching: find.byType(SizedBox)).first;
  // The quantity `Text` carries a `semanticsLabel`, so its first render object
  // is a semantics wrapper; the paragraph is the `RichText` inside it.
  final qtyParagraph = find.descendant(
    of: qty,
    matching: find.byType(RichText),
  );
  final gutterRect = tester.getRect(gutter);
  final qtyRect = tester.getRect(qtyParagraph);
  final nameRect = tester.getRect(name);
  final paragraph = tester.renderObject<RenderParagraph>(qtyParagraph);

  // Never clipped: the label wraps inside the gutter instead.
  expect(paragraph.didExceedMaxLines, isFalse, reason: label);

  // The paragraph sits inside the gutter it was given...
  expect(
    qtyRect.width,
    lessThanOrEqualTo(gutterRect.width + _kEpsilon),
    reason: '"$label" is wider than its gutter',
  );
  expect(qtyRect.left, greaterThanOrEqualTo(gutterRect.left - _kEpsilon));
  expect(qtyRect.right, lessThanOrEqualTo(gutterRect.right + _kEpsilon));

  // ...and every line it laid out sits inside the paragraph, so a word wider
  // than the gutter broke inside it rather than painting past its edge.
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: label.length),
  );
  var inkRight = 0.0;
  for (final box in boxes) {
    expect(
      box.right,
      lessThanOrEqualTo(paragraph.size.width + _kEpsilon),
      reason: 'a line of "$label" paints past its paragraph',
    );
    if (box.right > inkRight) inkRight = box.right;
  }

  // The collision itself. The gutter box (a `Text` in a fixed-width
  // `SizedBox` always spans it) ends a gap before the name begins — the
  // layout guarantee — and so does the widest line actually painted.
  expect(
    qtyRect.right + _kGap,
    lessThanOrEqualTo(nameRect.left + _kEpsilon),
    reason: '"$label" runs into its name',
  );
  expect(
    qtyRect.left + inkRight + _kGap,
    lessThanOrEqualTo(nameRect.left + _kEpsilon),
    reason: 'the ink of "$label" runs into its name',
  );

  // "Filled" is decided by the TEXT: on one line it would not fit the gutter,
  // so it wrapped and its ink reaches the gutter's far side.
  return paragraph.getMaxIntrinsicWidth(double.infinity) >
      paragraph.size.width + _kEpsilon;
}

void main() {
  for (final width in const [390.0, 1440.0]) {
    for (final scale in const [1.0, 2.0]) {
      testWidgets('reading rail: long units stay in the gutter at '
          '${width.toInt()} x $scale', (tester) async {
        _sizeView(tester, Size(width, 2400));
        await tester.pumpWidget(
          _app(
            Scaffold(
              body: SingleChildScrollView(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: _railWidth(width, scale),
                    child: const RailPanel(recipe: _recipe),
                  ),
                ),
              ),
            ),
            textScale: scale,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        var anyFilled = false;
        for (final ing in _ingredients) {
          final label = ingredientQuantityLabel(ing);
          anyFilled |= _expectRowClear(
            tester,
            find.text(label),
            find.text(sentenceCase(ing.name), findRichText: true),
            label: label,
          );
        }
        // The fixture has to fill the gutter somewhere, or the gap check
        // above proves nothing.
        expect(anyFilled, isTrue);
      });
    }
  }

  // Cook mode's gutter panel is the wide layout's rail — at <1000 the step's
  // ingredients are a strip of one-line chips with no gutter at all — so its
  // envelope is the two widths that draw it: 1000 (rail stacked under the
  // step) and 1440 (beside it at 1.0×, stacked at 2.0×).
  for (final width in const [1000.0, 1440.0]) {
    for (final scale in const [1.0, 2.0]) {
      testWidgets('cook mode "For this step": long units stay in the gutter at '
          '${width.toInt()} x $scale', (tester) async {
        _sizeView(tester, Size(width, 3000));
        await tester.pumpWidget(
          _app(
            Scaffold(
              body: CookStepView(
                recipe: _recipe,
                steps: flattenCookSteps(_recipe),
                index: 0,
                onClose: () {},
              ),
            ),
            textScale: scale,
            theme: AppTheme.dark(),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('For this step'), findsOneWidget);

        var anyFilled = false;
        for (final ing in _ingredients) {
          final label = ingredientQuantityLabel(ing);
          anyFilled |= _expectRowClear(
            tester,
            find.text(label),
            find.text(sentenceCase(ing.name)),
            label: label,
          );
        }
        expect(anyFilled, isTrue);
      });
    }
  }

  testWidgets('cook mode at 390 draws the ingredients as chips, not a gutter', (
    tester,
  ) async {
    _sizeView(tester, const Size(390, 844));
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: CookStepView(
            recipe: _recipe,
            steps: flattenCookSteps(_recipe),
            index: 0,
            onClose: () {},
          ),
        ),
        textScale: 2.0,
        theme: AppTheme.dark(),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('For this step'), findsNothing);
  });
}
