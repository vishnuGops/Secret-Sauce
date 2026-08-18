import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
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

  testWidgets('StarRating draws half stars and the numeric average',
      (tester) async {
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
  testWidgets('StarRatingInput drops the preview when the gesture is cancelled',
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
    final gesture = await tester
        .startGesture(topLeft + const Offset(size * 3 + 5, size / 2));
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
  });

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
}
