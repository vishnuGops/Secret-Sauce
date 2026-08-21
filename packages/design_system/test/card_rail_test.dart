import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const double _cardWidth = 200;
const double _gap = 16;

Widget _host({
  int itemCount = 10,
  int page = 3,
  String? footnote,
  double width = 700,
}) => MaterialApp(
  theme: AppTheme.light(),
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: width,
        child: CardRail(
          icon: Icons.trending_up,
          title: 'Trending chefs',
          subtitle: 'Fastest score gain in the last 7 days',
          height: 120,
          cardWidth: _cardWidth,
          gap: _gap,
          page: page,
          footnote: footnote,
          itemCount: itemCount,
          itemBuilder:
              (context, i) => SizedBox(
                width: _cardWidth,
                child: ColoredBox(
                  color: Colors.grey,
                  child: Center(child: Text('card $i')),
                ),
              ),
        ),
      ),
    ),
  ),
);

/// The rail's back/forward buttons, in order.
Finder get _arrows => find.byType(IconButton);

bool _enabled(WidgetTester tester, int index) =>
    tester.widgetList<IconButton>(_arrows).elementAt(index).onPressed != null;

void main() {
  testWidgets('shows the title, subtitle and window position', (tester) async {
    await tester.pumpWidget(_host());
    expect(find.text('Trending chefs'), findsOneWidget);
    expect(find.text('Fastest score gain in the last 7 days'), findsOneWidget);
    expect(find.text('1–3 / 10'), findsOneWidget);
  });

  testWidgets('the back arrow starts disabled and the forward one does not', (
    tester,
  ) async {
    await tester.pumpWidget(_host());
    expect(_enabled(tester, 0), isFalse);
    expect(_enabled(tester, 1), isTrue);
  });

  testWidgets('an arrow press moves exactly one page', (tester) async {
    await tester.pumpWidget(_host());

    await tester.tap(_arrows.last);
    await tester.pumpAndSettle();

    expect(find.text('4–6 / 10'), findsOneWidget);
    expect(_enabled(tester, 0), isTrue);

    await tester.tap(_arrows.first);
    await tester.pumpAndSettle();
    expect(find.text('1–3 / 10'), findsOneWidget);
  });

  testWidgets('the forward arrow disables at the end and the label clamps', (
    tester,
  ) async {
    await tester.pumpWidget(_host());

    // 10 items, 3 per page: the last window starts at index 7, so three
    // presses land on the end and the fourth cannot happen.
    for (var i = 0; i < 3; i++) {
      await tester.tap(_arrows.last);
      await tester.pumpAndSettle();
    }

    expect(find.text('8–10 / 10'), findsOneWidget);
    expect(_enabled(tester, 1), isFalse);
    expect(_enabled(tester, 0), isTrue);
  });

  testWidgets('a rail that fits has no controls to get wrong', (tester) async {
    await tester.pumpWidget(_host(itemCount: 2));
    expect(_arrows, findsNothing);
    expect(find.textContaining('/ 2'), findsNothing);
  });

  testWidgets('the footnote renders under the shelf when given', (
    tester,
  ) async {
    await tester.pumpWidget(_host(footnote: 'Placeholder cards for now.'));
    expect(find.text('Placeholder cards for now.'), findsOneWidget);

    await tester.pumpWidget(_host());
    expect(find.text('Placeholder cards for now.'), findsNothing);
  });
}
