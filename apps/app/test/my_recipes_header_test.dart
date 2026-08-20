import 'package:app/features/my_recipes/my_recipes_providers.dart';
import 'package:app/features/my_recipes/my_recipes_screen.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// `New recipe` moved off the web top navigation and onto this header, which is
/// a **fixed-height** `AppBar` toolbar — the shape that produced B001/B002/B016
/// elsewhere. A labelled `FilledButton` carries 28px of vertical padding on top
/// of its line height, so at 2.0x text scale it wants ~68px inside a 56px
/// toolbar. Measured rather than assumed: the toolbar **clamps** it, with no
/// `RenderFlex` overflow, so the label stays at every scale — and that is what
/// the envelope below is here to keep true.
Future<void> _pump(
  WidgetTester tester, {
  required double width,
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // Empty lists: this is a chrome test, and the grid has its own suite.
        myRecipesProvider.overrideWith((ref) async => const <Recipe>[]),
        sharedWithMeProvider.overrideWith((ref) async => const <Recipe>[]),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 900),
            textScaler: TextScaler.linear(textScale),
          ),
          child: const MyRecipesScreen(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Header only — the empty state under it has its own labelled `New recipe`
/// button, so an unscoped finder matches either one.
final _headerLabel = find.descendant(
  of: find.byType(AppBar),
  matching: find.text('New recipe'),
);

void main() {
  testWidgets('web header carries the labelled New recipe button',
      (tester) async {
    await _pump(tester, width: 1400);

    expect(_headerLabel, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact keeps the icon — the FAB is the labelled action there',
      (tester) async {
    await _pump(tester, width: 390);

    expect(_headerLabel, findsNothing);
    expect(find.byTooltip('New recipe'), findsOneWidget);
  });

  testWidgets('2.0x text scale keeps the label and does not overflow',
      (tester) async {
    await _pump(tester, width: 1400, textScale: 2.0);

    expect(_headerLabel, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final (width, scale) in <(double, double)>[
    (600, 1.0),
    (700, 1.3),
    (1000, 2.0),
    (1400, 2.0),
  ]) {
    testWidgets('header fits at ${width}px, textScale $scale', (tester) async {
      await _pump(tester, width: width, textScale: scale);
      expect(
        tester.takeException(),
        isNull,
        reason: 'overflow at ${width}px @ ${scale}x',
      );
    });
  }
}
