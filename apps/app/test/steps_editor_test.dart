// The steps half of the recipe editor, pumped on its own (Phase 38):
//
// - UX-035: the step timer was hidden behind a `tune` icon, and
//   `int.tryParse` silently saved no timer for `1h`. The Time field is now on
//   every step and reads hours and minutes; anything else fails the form.
// - UX-035: steps could not be reordered. Now by drag handle, and by a
//   Move up / Move down menu a keyboard can reach.
// - UX-052: removing a whole section took its steps with it in one tap.
//
// `StepsEditor` is a StatelessWidget over a mutable draft, so the harness owns
// the rebuild (a `StatefulBuilder`) the way the editor screen does.
import 'package:app/features/recipe_editor/edit_models.dart';
import 'package:app/features/recipe_editor/ingredients_editor.dart';
import 'package:app/features/recipe_editor/steps_editor.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(
  List<EditStepGroup> groups, {
  GlobalKey<FormState>? formKey,
  double textScale = 1.0,
}) => MaterialApp(
  theme: AppTheme.light(),
  builder:
      (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
  home: Scaffold(
    body: Form(
      key: formKey,
      child: StatefulBuilder(
        builder:
            // A sliver, hosted the way the screen hosts it.
            (context, setState) => CustomScrollView(
              slivers: [
                SliverPadding(
                  // The editor's own page padding.
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
  ),
);

void _size(WidgetTester tester, double width, {double height = 2400}) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

List<EditStepGroup> _groups(List<List<String>> sections) => [
  for (final steps in sections)
    EditStepGroup(steps: [for (final text in steps) EditStep(text: text)]),
];

void _disposeLater(List<EditStepGroup> groups) {
  addTearDown(() {
    for (final g in groups) {
      g.dispose();
    }
  });
}

Finder _timeField() => find.widgetWithText(TextFormField, 'Time');

List<String> _savedTexts(EditStepGroup group) => [
  for (final s in group.toModel().steps) s.text,
];

/// The step fields top to bottom, as the cook sees them.
List<String> _shownTexts(WidgetTester tester) => [
  for (final f in tester.widgetList<TextField>(
    find.widgetWithText(TextField, 'Step'),
  ))
    f.controller!.text,
];

/// The number bubbles top to bottom.
List<String?> _numbers(WidgetTester tester) => [
  for (final t in tester.widgetList<Text>(
    find.descendant(of: find.byType(CircleAvatar), matching: find.byType(Text)),
  ))
    t.data,
];

Future<void> _move(WidgetTester tester, int row, String label) async {
  await tester.tap(find.byTooltip('Move step').at(row));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  group('step timer (UX-035)', () {
    testWidgets('the Time field is on every step without a tap', (
      tester,
    ) async {
      _size(tester, 800);
      final groups = _groups([
        ['Mix.', 'Chill.'],
      ]);
      _disposeLater(groups);
      await tester.pumpWidget(_app(groups));
      await tester.pumpAndSettle();

      expect(_timeField(), findsNWidgets(2));
      expect(find.text('e.g. 1h 30m'), findsNWidgets(2));
      // Temperature and tip are still behind the disclosure.
      expect(find.text('Temperature'), findsNothing);
      await tester.tap(find.byTooltip('Temperature & tip').first);
      await tester.pumpAndSettle();
      expect(find.text('Temperature'), findsOneWidget);
      expect(find.text('Tip'), findsOneWidget);
    });

    testWidgets('a loaded step with a temperature or tip opens showing it '
        '(B035)', (tester) async {
      _size(tester, 800);
      final groups = [
        EditStepGroup(
          steps: [
            EditStep.fromModel(
              const RecipeStep(
                id: 's1',
                groupId: 'g1',
                text: 'Bake.',
                temperature: '180°C',
                durationMinutes: 90,
              ),
            ),
          ],
        ),
      ];
      _disposeLater(groups);
      await tester.pumpWidget(_app(groups));
      await tester.pumpAndSettle();

      expect(find.text('Temperature'), findsOneWidget);
      expect(find.text('180°C'), findsOneWidget);
      expect(find.text('1 h 30 min'), findsOneWidget);
      // Untouched, it saves back what it loaded.
      expect(groups[0].toModel().steps.single.durationMinutes, 90);
    });

    testWidgets('1h 30m saves as a 90-minute timer', (tester) async {
      _size(tester, 800);
      final formKey = GlobalKey<FormState>();
      final groups = _groups([
        ['Simmer the stock.'],
      ]);
      _disposeLater(groups);
      await tester.pumpWidget(_app(groups, formKey: formKey));
      await tester.pumpAndSettle();

      await tester.enterText(_timeField(), '1h 30m');
      await tester.pump();

      expect(formKey.currentState!.validate(), isTrue);
      expect(groups[0].toModel().steps.single.durationMinutes, 90);
    });

    testWidgets('an unreadable time fails the form and says what works', (
      tester,
    ) async {
      _size(tester, 800);
      final formKey = GlobalKey<FormState>();
      final groups = _groups([
        ['Simmer the stock.'],
      ]);
      _disposeLater(groups);
      await tester.pumpWidget(_app(groups, formKey: formKey));
      await tester.pumpAndSettle();

      await tester.enterText(_timeField(), 'soon');
      await tester.pump();

      expect(formKey.currentState!.validate(), isFalse);
      await tester.pump();
      expect(find.text('Try 90, 1h or 1h 30m'), findsOneWidget);
    });
  });

  group('reorder (UX-035)', () {
    testWidgets('Move down / Move up reorder the section and what it saves', (
      tester,
    ) async {
      _size(tester, 800);
      final groups = _groups([
        ['Alpha', 'Bravo', 'Charlie'],
      ]);
      _disposeLater(groups);
      await tester.pumpWidget(_app(groups));
      await tester.pumpAndSettle();

      await _move(tester, 0, 'Move down');
      expect(_savedTexts(groups[0]), ['Bravo', 'Alpha', 'Charlie']);
      // Ascending by the new list position (B022).
      expect(
        [for (final s in groups[0].toModel().steps) s.stepOrder],
        [0, 1, 2],
      );
      expect(
        [for (final s in groups[0].toModel().steps) s.sortOrder],
        [0, 1, 2],
      );
      // The fields and the numbers re-flow with the rows.
      expect(_shownTexts(tester), ['Bravo', 'Alpha', 'Charlie']);
      expect(_numbers(tester), ['1', '2', '3']);

      await _move(tester, 2, 'Move up');
      expect(_savedTexts(groups[0]), ['Bravo', 'Charlie', 'Alpha']);
      expect(_shownTexts(tester), ['Bravo', 'Charlie', 'Alpha']);
    });

    testWidgets('the ends cannot move past themselves', (tester) async {
      _size(tester, 800);
      final groups = _groups([
        ['Alpha', 'Bravo'],
      ]);
      _disposeLater(groups);
      await tester.pumpWidget(_app(groups));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Move step').first);
      await tester.pumpAndSettle();
      final up = tester.widget<PopupMenuItem<Object?>>(
        find.ancestor(
          of: find.text('Move up'),
          matching: find.byWidgetPredicate((w) => w is PopupMenuItem),
        ),
      );
      expect(up.enabled, isFalse);
      await tester.tap(find.text('Move up'));
      await tester.pumpAndSettle();
      expect(_savedTexts(groups[0]), ['Alpha', 'Bravo']);
    });

    testWidgets('each step has a drag handle, and dragging it reorders', (
      tester,
    ) async {
      _size(tester, 800);
      final groups = _groups([
        ['Alpha', 'Bravo', 'Charlie'],
      ]);
      _disposeLater(groups);
      await tester.pumpWidget(_app(groups));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.drag_indicator), findsNWidgets(3));
      expect(find.byType(EditorDragHandle), findsNWidgets(3));

      // Drag Alpha's grip below Charlie.
      final start = tester.getCenter(find.byIcon(Icons.drag_indicator).first);
      final below = tester.getBottomLeft(find.text('Charlie')).dy + 40;
      final gesture = await tester.startGesture(start);
      for (var i = 1; i <= 10; i++) {
        await gesture.moveTo(
          Offset(start.dx, start.dy + (below - start.dy) * i / 10),
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();

      expect(_savedTexts(groups[0]), ['Bravo', 'Charlie', 'Alpha']);
    });

    // B156 (Phase 39 review): the rows share the page's viewport, whose edge
    // auto-scroller cannot carry an item taller than itself — it asserted in
    // debug and, in release, scrolled to the end and dropped the step last.
    testWidgets('a step taller than the window does not start a drag', (
      tester,
    ) async {
      _size(tester, 390, height: 700);
      final groups = _groups([
        ['Alpha ${'stir and taste as you go, ' * 60}', 'Bravo', 'Charlie'],
      ]);
      _disposeLater(groups);
      await tester.pumpWidget(_app(groups));
      await tester.pumpAndSettle();

      final grip = find.byIcon(Icons.drag_indicator).first;
      // The row `editorRow` keys by its draft.
      final row = find.ancestor(
        of: grip,
        matching: find.byWidgetPredicate(
          (w) => w is KeyedSubtree && w.key is GlobalObjectKey,
        ),
      );
      expect(row, findsOneWidget);
      expect(
        tester.getSize(row).height,
        greaterThan(700),
        reason: 'the fixture step has to be taller than the window',
      );
      final page = tester.state<ScrollableState>(find.byType(Scrollable).first);
      final before = page.position.pixels;

      final start = tester.getCenter(grip);
      final gesture = await tester.startGesture(start);
      for (var i = 1; i <= 20; i++) {
        await gesture.moveTo(start + Offset(0, 2.0 * i));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(tester.takeException(), isNull);
      expect(page.position.pixels, before, reason: 'the page ran away');
      await gesture.up();
      await tester.pumpAndSettle();

      expect(_savedTexts(groups[0]).skip(1), ['Bravo', 'Charlie']);
      expect(_savedTexts(groups[0]).first, startsWith('Alpha'));
    });
  });

  group('removing a section (UX-052)', () {
    testWidgets('a section with steps asks first; Keep keeps it', (
      tester,
    ) async {
      _size(tester, 800);
      final groups = _groups([
        ['Make the dough.', 'Rest it.'],
        ['Bake.'],
      ]);
      _disposeLater(groups);
      await tester.pumpWidget(_app(groups));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Remove section').first);
      await tester.pumpAndSettle();
      expect(find.text('Remove this section?'), findsOneWidget);
      expect(find.text('Its 2 steps will be removed too.'), findsOneWidget);

      await tester.tap(find.text('Keep'));
      await tester.pumpAndSettle();
      expect(groups, hasLength(2));
      expect(find.text('Make the dough.'), findsOneWidget);
    });

    testWidgets('Remove removes it', (tester) async {
      _size(tester, 800);
      final groups = _groups([
        ['Bake.'],
        ['Cool.'],
      ]);
      // The removed group is disposed by the editor itself, post-frame.
      final survivor = groups[1];
      addTearDown(survivor.dispose);
      await tester.pumpWidget(_app(groups));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Remove section').first);
      await tester.pumpAndSettle();
      expect(find.text('Its 1 step will be removed too.'), findsOneWidget);
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      expect(groups, [survivor]);
      expect(find.text('Bake.'), findsNothing);
    });

    testWidgets('an empty section goes at once', (tester) async {
      _size(tester, 800);
      final groups = _groups([
        ['   '],
        ['Cool.'],
      ]);
      final survivor = groups[1];
      addTearDown(survivor.dispose);
      await tester.pumpWidget(_app(groups));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Remove section').first);
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(groups, [survivor]);
    });
  });

  group('envelope', () {
    for (final width in [390.0, 600.0, 1000.0, 1440.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('no overflow at ${width.toInt()}px @ ${scale}x', (
          tester,
        ) async {
          _size(tester, width, height: 4000);
          final formKey = GlobalKey<FormState>();
          final groups = [
            EditStepGroup(
              name: 'Prepare the dough',
              steps: [
                EditStep(
                  text:
                      'Rub the butter into the flour until it looks like '
                      'coarse breadcrumbs.',
                  duration: 'soon',
                  temperature: '220°C / 425°F fan',
                  tip: 'Keep everything cold.',
                ),
                EditStep(text: 'Chill.', duration: '1h 30m'),
              ],
            ),
            EditStepGroup(steps: [EditStep(text: 'Bake.')]),
          ];
          _disposeLater(groups);
          await tester.pumpWidget(
            _app(groups, formKey: formKey, textScale: scale),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'rows');

          // The error line under Time.
          formKey.currentState!.validate();
          await tester.pumpAndSettle();
          expect(find.text('Try 90, 1h or 1h 30m'), findsOneWidget);
          expect(tester.takeException(), isNull, reason: 'time error');

          await tester.tap(find.byTooltip('Move step').first);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'move menu');
          await tester.tapAt(Offset.zero);
          await tester.pumpAndSettle();

          await tester.tap(find.byTooltip('Remove section').first);
          await tester.pumpAndSettle();
          expect(find.text('Remove this section?'), findsOneWidget);
          expect(tester.takeException(), isNull, reason: 'confirm dialog');
          await tester.tap(find.text('Keep'));
          await tester.pumpAndSettle();
        });
      }
    }
  });
}
