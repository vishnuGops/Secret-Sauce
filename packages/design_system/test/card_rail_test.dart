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

/// The numbered variant (Phase 26) — Discover's shelves. Same machinery, a
/// different header, so these tests cover only what the header does.
Widget _numbered({
  int itemCount = 10,
  double width = 900,
  double textScale = 1.0,
  String? kicker = 'RANKED BY SAVES',
}) => MaterialApp(
  theme: AppTheme.light(),
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
    child: Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          child: CardRail(
            variant: CardRailVariant.numbered,
            index: '02',
            title: 'Weekend projects',
            subtitle: 'Two hours or harder.',
            kicker: kicker,
            height: 120,
            cardWidth: _cardWidth,
            gap: _gap,
            itemCount: itemCount,
            itemBuilder:
                (context, i) =>
                    SizedBox(width: _cardWidth, child: Text('card $i')),
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

  group('numbered variant', () {
    testWidgets('sets the numeral, the title in caps, and the rule', (
      tester,
    ) async {
      await tester.pumpWidget(_numbered());

      expect(find.text('02'), findsOneWidget);
      // Upper-cased by the header, not by the caller: a shelf's title is also
      // its accessible name, and 'Weekend projects' is what it is called.
      expect(find.text('WEEKEND PROJECTS'), findsOneWidget);
      expect(find.text('Two hours or harder.'), findsOneWidget);
      expect(find.text('RANKED BY SAVES'), findsOneWidget);
      expect(find.text('1–3 / 10'), findsOneWidget);
    });

    testWidgets('drops the kicker, then the label, then the arrows as the '
        'header narrows', (tester) async {
      // Each control has a width it is worth less than: the title is the one
      // thing that must survive, and a phone rail is scrolled by drag anyway.
      await tester.pumpWidget(_numbered(width: 660));
      expect(find.text('RANKED BY SAVES'), findsNothing);
      expect(find.text('1–3 / 10'), findsOneWidget);
      expect(_arrows, findsNWidgets(2));

      await tester.pumpWidget(_numbered(width: 500));
      expect(find.text('1–3 / 10'), findsNothing);
      expect(_arrows, findsNWidgets(2));

      await tester.pumpWidget(_numbered(width: 380));
      expect(_arrows, findsNothing);
      expect(find.text('WEEKEND PROJECTS'), findsOneWidget);
    });

    testWidgets('a shelf that fits still has no controls', (tester) async {
      await tester.pumpWidget(_numbered(itemCount: 2));
      expect(_arrows, findsNothing);
      expect(find.textContaining('/ 2'), findsNothing);
    });

    testWidgets('an over-long kicker ellipsizes instead of overflowing (B057)', (
      tester,
    ) async {
      // The width gate only decides whether the kicker is drawn — it says
      // nothing about how long the caller's string is, and a non-flex child of
      // a Row is laid out unbounded (B039).
      for (final scale in [1.0, 2.0]) {
        await tester.pumpWidget(
          _numbered(
            width: 1400,
            textScale: scale,
            kicker:
                'RANKED BY SAVES EARNED IN THE LAST THIRTY DAYS BY '
                'SIGNED-IN COOKS, EXCLUDING THE OWNER',
          ),
        );
        expect(
          tester.takeException(),
          isNull,
          reason: 'the kicker overflowed the header at ${scale}x',
        );
        expect(find.text('WEEKEND PROJECTS'), findsOneWidget);
      }
    });

    testWidgets('the header holds together at 320px and 2.0x text scale', (
      tester,
    ) async {
      // The envelope the card is contracted to (Gotcha 13). The chefs rails
      // never rendered below 600px — Discover's do, on every phone.
      for (final width in [320.0, 390.0, 700.0, 1200.0]) {
        for (final scale in [1.0, 2.0]) {
          await tester.pumpWidget(_numbered(width: width, textScale: scale));
          expect(
            tester.takeException(),
            isNull,
            reason: 'overflow at ${width}px / ${scale}x',
          );
        }
      }
    });
  });
}
