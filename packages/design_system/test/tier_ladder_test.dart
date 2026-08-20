import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(double score, {double width = 420, double textScale = 1.0}) =>
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Center(
            child: SizedBox(width: width, child: TierLadder(score: score)),
          ),
        ),
      ),
    );

void main() {
  group('positionFor', () {
    // The four thresholds are the anchors, evenly spaced. This is the widget's
    // whole contract: a linear points axis would squash Line Cook and Sous Chef
    // into the first 5% of the bar.
    test('lands each threshold on its anchor', () {
      expect(TierLadder.positionFor(100), 0);
      expect(TierLadder.positionFor(1000), closeTo(1 / 3, 1e-9));
      expect(TierLadder.positionFor(5000), closeTo(2 / 3, 1e-9));
      expect(TierLadder.positionFor(20000), 1);
    });

    test('interpolates within a band', () {
      // Half way through the Sous band (1,000..5,000) is half way between the
      // second and third anchors.
      expect(TierLadder.positionFor(3000), closeTo(0.5, 1e-9));
    });

    test('clamps outside the ladder', () {
      expect(TierLadder.positionFor(0), 0);
      expect(TierLadder.positionFor(50), 0);
      expect(TierLadder.positionFor(100000), 1);
    });
  });

  testWidgets('prints the thresholds and the rung words', (tester) async {
    await tester.pumpWidget(_host(10189));

    expect(find.text('100'), findsOneWidget);
    expect(find.text('1,000'), findsOneWidget);
    expect(find.text('5,000'), findsOneWidget);
    expect(find.text('20,000'), findsOneWidget);
    expect(find.text('Line'), findsOneWidget);
    expect(find.text('Sous'), findsOneWidget);
    expect(find.text('Head'), findsOneWidget);
    expect(find.text('Master'), findsOneWidget);
  });

  testWidgets('fills to the score and tints with the current tier',
      (tester) async {
    await tester.pumpWidget(_host(10189));

    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, closeTo(TierLadder.positionFor(10189), 1e-9));
    expect(
      bar.valueColor?.value,
      TierChip.colorFor(ChefTier.headChef, Brightness.light),
    );
  });

  for (final width in <double>[280, 420]) {
    testWidgets('fits at ${width}px, textScale 2.0', (tester) async {
      tester.view.physicalSize = Size(width, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_host(10189, width: width, textScale: 2.0));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: 'overflow at ${width}px');
    });
  }
}
