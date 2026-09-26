import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// UX-032: the one rank widget that replaced the spotlight card's RANK pill,
/// the board row's disc and the podium row's rank column. UX-012 (the dark
/// RANK pill) and UX-049 (tabular ranks) ride along with it.
Widget _host(
  Widget badge, {
  double textScale = 1.0,
  double width = 390,
  Brightness brightness = Brightness.light,
}) => MaterialApp(
  theme: brightness == Brightness.light ? AppTheme.light() : AppTheme.dark(),
  home: Scaffold(
    body: MediaQuery(
      data: MediaQueryData(
        size: Size(width, 900),
        textScaler: TextScaler.linear(textScale),
      ),
      child: Center(child: badge),
    ),
  ),
);

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// Every [Text] a badge draws, whatever the variant.
Iterable<Text> _texts(WidgetTester tester) => tester.widgetList<Text>(
  find.descendant(of: find.byType(RankBadge), matching: find.byType(Text)),
);

void main() {
  final variants = <String, RankBadge Function(int rank)>{
    'pill': (r) => RankBadge.pill(rank: r, tier: ChefTier.headChef),
    'disc': (r) => RankBadge.disc(rank: r, tier: ChefTier.headChef),
    'podium': (r) => RankBadge.podium(rank: r, tier: ChefTier.headChef),
    'podium dense':
        (r) => RankBadge.podium(rank: r, tier: ChefTier.headChef, dense: true),
  };

  group('copy', () {
    testWidgets('pill reads RANK N', (tester) async {
      await tester.pumpWidget(_host(variants['pill']!(12)));
      expect(find.text('RANK 12'), findsOneWidget);
    });

    testWidgets('disc is the bare numeral', (tester) async {
      await tester.pumpWidget(_host(variants['disc']!(12)));
      expect(find.text('12'), findsOneWidget);
    });

    testWidgets('podium: a medal over #N for the top three, else N over rank', (
      tester,
    ) async {
      await tester.pumpWidget(_host(variants['podium']!(1)));
      expect(find.byIcon(Icons.workspace_premium), findsOneWidget);
      expect(find.text('#1'), findsOneWidget);
      expect(find.text('rank'), findsNothing);

      await tester.pumpWidget(_host(variants['podium']!(3)));
      expect(find.byIcon(Icons.military_tech), findsOneWidget);
      expect(find.text('#3'), findsOneWidget);

      await tester.pumpWidget(_host(variants['podium']!(12)));
      expect(find.byIcon(Icons.workspace_premium), findsNothing);
      expect(find.byIcon(Icons.military_tech), findsNothing);
      expect(find.text('12'), findsOneWidget);
      expect(find.text('rank'), findsOneWidget);
    });
  });

  for (final MapEntry(key: name, value: build) in variants.entries) {
    group(name, () {
      // UX-049: a proportional `1` is narrower than a `0`, so a re-rank moved
      // the row around the number.
      testWidgets('sets every figure tabular', (tester) async {
        for (final rank in [1, 12, 128]) {
          await tester.pumpWidget(_host(build(rank)));
          for (final text in _texts(tester)) {
            expect(
              text.style?.fontFeatures,
              contains(const FontFeature.tabularFigures()),
              reason: '"${text.data}" at rank $rank is proportional',
            );
          }
        }
      });

      testWidgets('is one semantics node reading "Rank 12"', (tester) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(_host(build(12)));

        expect(find.bySemanticsLabel('Rank 12'), findsOneWidget);
        // The visual text is excluded, so it is not read a second time.
        expect(find.bySemanticsLabel('RANK 12'), findsNothing);
        expect(find.bySemanticsLabel('12'), findsNothing);
        expect(find.bySemanticsLabel('rank'), findsNothing);
        handle.dispose();
      });

      for (final width in [390.0, 600.0, 1000.0, 1440.0]) {
        for (final scale in [1.0, 2.0]) {
          testWidgets('a 3-digit rank fits at ${width.toInt()} × ${scale}x', (
            tester,
          ) async {
            await tester.pumpWidget(
              _host(build(128), width: width, textScale: scale),
            );
            expect(tester.takeException(), isNull);
          });
        }
      }
    });
  }

  // The disc and the podium column are fixed-size: a 3-digit rank at 2.0×
  // scales down inside them rather than growing the row.
  testWidgets('disc and podium keep their size for a 3-digit rank at 2.0x', (
    tester,
  ) async {
    await tester.pumpWidget(_host(variants['disc']!(1)));
    final disc = tester.getSize(find.byType(RankBadge));
    await tester.pumpWidget(_host(variants['disc']!(128), textScale: 2));
    expect(tester.getSize(find.byType(RankBadge)), disc);

    await tester.pumpWidget(_host(variants['podium']!(4)));
    final podiumWidth = tester.getSize(find.byType(RankBadge)).width;
    await tester.pumpWidget(_host(variants['podium']!(128), textScale: 2));
    expect(tester.getSize(find.byType(RankBadge)).width, podiumWidth);
  });

  // UX-012: the pill is near-white in both themes. Its ink used to be the
  // page-brightness tier colour — a pastel in dark mode, ~1.5:1 on the pill.
  // Measured over the worst backdrop the portrait caption gives it: the cover
  // scrim over a black plate.
  group('pill ink contrast (UX-012)', () {
    for (final brightness in Brightness.values) {
      for (final tier in ChefTier.values) {
        testWidgets('${brightness.name} · ${tier.name} ≥ 4.5:1', (
          tester,
        ) async {
          await tester.pumpWidget(
            _host(RankBadge.pill(rank: 12, tier: tier), brightness: brightness),
          );
          final palette = AppPalette.of(brightness);
          final pill =
              tester
                      .widget<Container>(
                        find.descendant(
                          of: find.byType(RankBadge),
                          matching: find.byType(Container),
                        ),
                      )
                      .decoration!
                  as BoxDecoration;
          final backdrop = Color.alphaBlend(
            palette.scrim,
            const Color(0xFF000000),
          );
          final fill = Color.alphaBlend(pill.color!, backdrop);
          final ink = tester.widget<Text>(find.text('RANK 12')).style!.color!;

          final ratio = _contrast(ink, fill);
          expect(
            ratio,
            greaterThanOrEqualTo(4.5),
            reason: 'measured ${ratio.toStringAsFixed(2)}:1',
          );
        });
      }
    }
  });
}
