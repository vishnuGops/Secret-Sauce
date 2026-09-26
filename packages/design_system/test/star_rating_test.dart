import 'dart:ui' show Tristate;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) {
    return tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: Center(child: child)),
      ),
    );
  }

  testWidgets('StarRating draws half stars and the numeric average', (
    tester,
  ) async {
    await pump(tester, const StarRating(rating: 4.5, count: 12));

    expect(find.byIcon(Icons.star_rounded), findsNWidgets(4));
    expect(find.byIcon(Icons.star_half_rounded), findsOneWidget);
    expect(find.byIcon(Icons.star_outline_rounded), findsNothing);
    expect(find.text('4.5'), findsOneWidget);
    expect(find.text('(12)'), findsOneWidget);
  });

  testWidgets('StarRating shows an unrated state', (tester) async {
    await pump(tester, const StarRating(rating: 0, count: 0));

    expect(find.byIcon(Icons.star_outline_rounded), findsNWidgets(5));
    expect(find.text('No ratings'), findsOneWidget);
  });

  testWidgets('StarRatingInput snaps taps to half stars', (tester) async {
    final changes = <double>[];
    const size = 40.0;

    await pump(
      tester,
      StarRatingInput(
        value: null,
        size: size,
        onChanged: (_) {},
        onChangeEnd: changes.add,
      ),
    );

    final topLeft = tester.getTopLeft(find.byType(StarRatingInput));
    // Left half of the 3rd star -> 2.5; right half of the 4th star -> 4.0.
    await tester.tapAt(topLeft + const Offset(size * 2 + 5, size / 2));
    await tester.pump();
    await tester.tapAt(topLeft + const Offset(size * 3 + size - 5, size / 2));
    await tester.pump();

    expect(changes, [2.5, 4.0]);
  });

  // Regression: press-then-scroll cancels the tap, so onChangeEnd never fires.
  // The preview must be dropped, or the stars keep showing an unsaved rating
  // that didUpdateWidget cannot clear (value never changed).
  testWidgets(
    'StarRatingInput drops the preview when the gesture is cancelled',
    (tester) async {
      final settled = <double>[];
      const size = 40.0;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: ListView(
              children: [
                const SizedBox(height: 400),
                Center(
                  child: StarRatingInput(
                    value: null,
                    size: size,
                    onChanged: (_) {},
                    onChangeEnd: settled.add,
                  ),
                ),
                const SizedBox(height: 800),
              ],
            ),
          ),
        ),
      );

      final topLeft = tester.getTopLeft(find.byType(StarRatingInput));
      final gesture = await tester.startGesture(
        topLeft + const Offset(size * 3 + 5, size / 2),
      );
      // Hold past the tap deadline so onTapDown fires and sets the preview.
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byIcon(Icons.star_rounded), findsNWidgets(3));

      // Scroll away: the ListView claims the gesture and the tap is cancelled.
      await gesture.moveBy(const Offset(0, -80));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(settled, isEmpty, reason: 'nothing was persisted');
      expect(find.byIcon(Icons.star_rounded), findsNothing);
      expect(find.byIcon(Icons.star_half_rounded), findsNothing);
      expect(find.byIcon(Icons.star_outline_rounded), findsNWidgets(5));
    },
  );

  testWidgets('StarRatingInput clamps to the 0.5 .. 5.0 range', (tester) async {
    final changes = <double>[];
    const size = 40.0;

    await pump(
      tester,
      StarRatingInput(
        value: 3,
        size: size,
        onChanged: (_) {},
        onChangeEnd: changes.add,
      ),
    );

    final topLeft = tester.getTopLeft(find.byType(StarRatingInput));
    await tester.tapAt(topLeft + const Offset(0.5, size / 2));
    await tester.pump();
    await tester.tapAt(topLeft + const Offset(size * 5 - 0.5, size / 2));
    await tester.pump();

    expect(changes, [0.5, 5.0]);
  });

  // UX-046: the count is pluralised, so one rating is not `1 ratings`.
  testWidgets('StarRating reads a single rating as singular', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, const StarRating(rating: 4, count: 1));
    expect(
      find.bySemanticsLabel('4.0 out of 5 stars, 1 rating'),
      findsOneWidget,
    );

    await pump(tester, const StarRating(rating: 4, count: 12));
    expect(
      find.bySemanticsLabel('4.0 out of 5 stars, 12 ratings'),
      findsOneWidget,
    );
    handle.dispose();
  });

  // B126 / UX-003 (WCAG 2.1.1): the input must be operable without a pointer.
  group('StarRatingInput keyboard + screen reader', () {
    SemanticsData semanticsOf(WidgetTester tester) =>
        tester.getSemantics(find.byType(StarRatingInput)).getSemanticsData();

    Future<void> perform(WidgetTester tester, SemanticsAction action) async {
      final node = tester.getSemantics(find.byType(StarRatingInput));
      node.owner!.performAction(node.id, action);
      await tester.pump();
    }

    DecoratedBox ring(WidgetTester tester) => tester.widget<DecoratedBox>(
      find.descendant(
        of: find.byType(StarRatingInput),
        matching: find.byWidgetPredicate(
          (w) =>
              w is DecoratedBox && w.position == DecorationPosition.foreground,
        ),
      ),
    );

    testWidgets('exposes a slider with increase/decrease actions', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pump(tester, StarRatingInput(value: 3, onChanged: (_) {}));

      final data = semanticsOf(tester);
      expect(data.label, 'Rate this recipe');
      expect(data.value, '3.0 stars');
      expect(data.increasedValue, '3.5 stars');
      expect(data.decreasedValue, '2.5 stars');
      expect(data.hasAction(SemanticsAction.increase), isTrue);
      expect(data.hasAction(SemanticsAction.decrease), isTrue);
      expect(data.flagsCollection.isSlider, isTrue);
      expect(data.flagsCollection.isFocused, isNot(Tristate.none));
      handle.dispose();
    });

    testWidgets('semantics actions step, settle, and stop at the ends', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final changed = <double>[];
      final settled = <double>[];
      await pump(
        tester,
        StarRatingInput(
          value: 4.5,
          onChanged: changed.add,
          onChangeEnd: settled.add,
        ),
      );

      await perform(tester, SemanticsAction.increase);
      expect(changed, [5.0]);
      expect(settled, [5.0]);
      expect(find.byIcon(Icons.star_rounded), findsNWidgets(5));

      // At the maximum there is nowhere up to go, so none is advertised.
      final atMax = semanticsOf(tester);
      expect(atMax.hasAction(SemanticsAction.increase), isFalse);
      expect(atMax.decreasedValue, '4.5 stars');

      await perform(tester, SemanticsAction.decrease);
      expect(changed, [5.0, 4.5]);
      expect(settled, [5.0, 4.5]);
      handle.dispose();
    });

    testWidgets('unrated offers only an increase, to the minimum', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pump(tester, StarRatingInput(value: null, onChanged: (_) {}));

      final data = semanticsOf(tester);
      expect(data.value, 'Not rated');
      expect(data.increasedValue, '0.5 stars');
      expect(data.hasAction(SemanticsAction.increase), isTrue);
      expect(data.hasAction(SemanticsAction.decrease), isFalse);
      handle.dispose();
    });

    testWidgets('arrows, Home and End move the rating by keyboard', (
      tester,
    ) async {
      final changed = <double>[];
      final settled = <double>[];
      await pump(
        tester,
        StarRatingInput(
          value: null,
          onChanged: changed.add,
          onChangeEnd: settled.add,
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(settled, [0.5, 1.0]);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(settled, [0.5, 1.0, 0.5]);

      // Already at the minimum: nothing to report.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(settled, [0.5, 1.0, 0.5]);

      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pump();
      expect(settled.last, 5.0);
      expect(find.byIcon(Icons.star_rounded), findsNWidgets(5));

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(settled.last, 5.0, reason: 'already at the maximum');
      expect(settled, hasLength(4));

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pump();
      expect(settled.sublist(4), [4.5, 0.5]);

      // A key press is a settled gesture: every change was also an end.
      expect(changed, settled);
    });

    testWidgets('keyboard focus draws a ring without changing the size', (
      tester,
    ) async {
      await pump(tester, StarRatingInput(value: 2, onChanged: (_) {}));
      final before = tester.getSize(find.byType(StarRatingInput));
      expect((ring(tester).decoration as BoxDecoration).border, isNull);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();

      final border = (ring(tester).decoration as BoxDecoration).border;
      expect(border, isA<Border>());
      final side = (border! as Border).top;
      final theme = Theme.of(tester.element(find.byType(StarRatingInput)));
      expect(side.color, theme.colorScheme.primary);
      expect(side.width, StarRatingInput.focusRingWidth);
      expect(tester.getSize(find.byType(StarRatingInput)), before);
    });

    testWidgets('disabled is not focusable and offers no actions', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final changed = <double>[];
      await pump(
        tester,
        StarRatingInput(value: 3, onChanged: changed.add, enabled: false),
      );

      final data = semanticsOf(tester);
      expect(data.hasAction(SemanticsAction.increase), isFalse);
      expect(data.hasAction(SemanticsAction.decrease), isFalse);
      expect(data.flagsCollection.isFocused, Tristate.none);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(changed, isEmpty);
      handle.dispose();
    });

    testWidgets('focused input holds its envelope', (tester) async {
      for (final width in [390.0, 1440.0]) {
        for (final scale in [1.0, 2.0]) {
          tester.view.physicalSize = Size(width, 800);
          tester.view.devicePixelRatio = 1;
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.light(),
              home: MediaQuery(
                data: MediaQueryData(
                  size: Size(width, 800),
                  textScaler: TextScaler.linear(scale),
                ),
                child: Scaffold(
                  body: Center(
                    child: StarRatingInput(
                      value: 3.5,
                      size: StarRatingInput.defaultSize,
                      onChanged: (_) {},
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
          expect(tester.takeException(), isNull, reason: '$width x $scale');
          expect(
            tester.getSize(find.byType(StarRatingInput)),
            const Size(
              StarRatingInput.defaultSize * 5,
              StarRatingInput.defaultSize,
            ),
          );
        }
      }
      tester.view.reset();
    });
  });
}
