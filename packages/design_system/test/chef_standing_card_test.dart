import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ChefStanding _standing({
  int rank = 1,
  String name = 'Amara Okonkwo',
  ChefTier tier = ChefTier.masterChef,
  double score = 21000,
  int recipes = 2,
  int likes = 4000,
  int saves = 1600,
  int views = 5000,
}) =>
    ChefStanding(
      chefRank: rank,
      id: 'c$rank',
      displayName: name,
      chefTier: tier,
      chefScore: score,
      publicRecipeCount: recipes,
      totalLikes: likes,
      totalSaves: saves,
      totalViews: views,
    );

Widget _host(
  ChefStanding standing, {
  VoidCallback? onTap,
  double width = 760,
  double textScale = 1.0,
  bool? dense,
}) =>
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 900),
            textScaler: TextScaler.linear(textScale),
          ),
          child: Center(
            child: SizedBox(
              width: width,
              child: ChefStandingCard(
                standing: standing,
                dense: dense,
                onTap: onTap ?? () {},
              ),
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('podium ranks get a medal, everyone else gets a numeral',
      (tester) async {
    await tester.pumpWidget(_host(_standing(rank: 1)));
    expect(find.byIcon(Icons.workspace_premium), findsOneWidget);
    expect(find.text('#1'), findsOneWidget);
    expect(find.text('rank'), findsNothing);

    await tester.pumpWidget(_host(_standing(rank: 3)));
    expect(find.byIcon(Icons.military_tech), findsOneWidget);
    expect(find.text('#3'), findsOneWidget);

    await tester.pumpWidget(_host(_standing(rank: 4)));
    expect(find.byIcon(Icons.workspace_premium), findsNothing);
    expect(find.byIcon(Icons.military_tech), findsNothing);
    expect(find.text('4'), findsOneWidget);
    expect(find.text('rank'), findsOneWidget);
  });

  testWidgets('shows grouped counts with labels, and the score', (tester) async {
    await tester.pumpWidget(_host(_standing(), dense: false));

    expect(find.text('21,000'), findsOneWidget);
    expect(find.text('4,000 likes'), findsOneWidget);
    expect(find.text('1,600 saves'), findsOneWidget);
    expect(find.text('5,000 views'), findsOneWidget);
    expect(find.text('2 recipes'), findsOneWidget);
  });

  testWidgets('dense drops the stat labels but keeps the numbers',
      (tester) async {
    await tester.pumpWidget(_host(_standing(), dense: true, width: 360));

    expect(find.text('4,000 likes'), findsNothing);
    expect(find.text('4,000'), findsOneWidget);
    expect(find.text('1,600'), findsOneWidget);
  });

  testWidgets('reports progress to the next tier, and stops at the top',
      (tester) async {
    // Head Chef at 10,189: 5,189 into a 15,000-point band -> 34%.
    await tester.pumpWidget(
      _host(_standing(rank: 2, tier: ChefTier.headChef, score: 10189)),
    );
    expect(find.text('34% to Master'), findsOneWidget);
    expect(find.text('top tier reached'), findsNothing);

    await tester.pumpWidget(_host(_standing(score: 21000)));
    expect(find.text('top tier reached'), findsOneWidget);
  });

  testWidgets('the whole row is one tap target', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_host(_standing(), onTap: () => taps++));

    await tester.tap(find.text('Amara Okonkwo'));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('draws a tier-coloured spine on the leading edge', (tester) async {
    await tester.pumpWidget(_host(_standing(tier: ChefTier.sousChef)));

    final spine = tester.widget<ColoredBox>(
      find.descendant(
        of: find.byType(ChefStandingCard),
        matching: find.byType(ColoredBox),
      ),
    );
    expect(
      spine.color,
      TierChip.colorFor(ChefTier.sousChef, Brightness.light),
    );
  });

  // The same envelope the old leaderboard row was pinned at: narrowest phone,
  // 2.0x accessibility scaling, longest tier label, a long display name, and
  // six-figure counts. Two real overflows (B016-shaped) were found here before.
  final stress = _standing(
    rank: 12,
    name: 'Bartholomew Featherstonehaugh-Wentworth',
    tier: ChefTier.masterChef,
    score: 987654.5,
    recipes: 128,
    likes: 240000,
    saves: 180000,
    views: 990000,
  );

  for (final width in <double>[320, 360, 600, 760]) {
    for (final scale in <double>[1.0, 2.0]) {
      testWidgets('fits at ${width}px, textScale $scale', (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          _host(stress, width: width, textScale: scale, dense: width < 600),
        );
        await tester.pumpAndSettle();

        expect(
          tester.takeException(),
          isNull,
          reason: 'overflow at ${width}px @ ${scale}x',
        );
      });
    }
  }

  group('board variant', () {
    Widget board(
      ChefStanding standing, {
      double width = ChefsPanelWidth.value,
      double textScale = 1.0,
      VoidCallback? onTap,
    }) =>
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 900),
                textScaler: TextScaler.linear(textScale),
              ),
              child: Center(
                child: SizedBox(
                  width: width,
                  child: ChefStandingCard(
                    standing: standing,
                    variant: ChefCardVariant.board,
                    onTap: onTap ?? () {},
                  ),
                ),
              ),
            ),
          ),
        );

    testWidgets('trades the medal for a rank pill and the chips for a bar',
        (tester) async {
      await tester.pumpWidget(board(_standing(rank: 1)));

      // No medal, no "#1", no stat chips — all of that is on the spotlight
      // cards beside the panel or in the expanded card a tap away.
      expect(find.byIcon(Icons.workspace_premium), findsNothing);
      expect(find.text('#1'), findsNothing);
      expect(find.text('4,000 likes'), findsNothing);

      expect(find.text('1'), findsOneWidget); // the rank pill
      expect(find.text('2 recipes'), findsOneWidget);
      expect(find.text('21,000'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('the bar tracks progress through the current tier',
        (tester) async {
      // Head Chef at 10,189: 5,189 into a 15,000-point band.
      await tester.pumpWidget(
        board(_standing(rank: 2, tier: ChefTier.headChef, score: 10189)),
      );
      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, closeTo(5189 / 15000, 0.001));
    });

    testWidgets('a single recipe is not "1 recipes" (B031)', (tester) async {
      await tester.pumpWidget(board(_standing(recipes: 1)));
      expect(find.text('1 recipe'), findsOneWidget);
      expect(find.text('1 recipes'), findsNothing);
    });

    testWidgets('the whole row is one tap target', (tester) async {
      var taps = 0;
      await tester.pumpWidget(board(_standing(), onTap: () => taps++));
      await tester.tap(find.text('Amara Okonkwo'));
      await tester.pumpAndSettle();
      expect(taps, 1);
    });

    // The panel is a fixed 404px column, so this row has no width to spare and
    // never gets any — the page does not reflow it.
    for (final scale in <double>[1.0, 1.5, 2.0]) {
      testWidgets('fits the 404px panel at textScale $scale', (tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          board(
            _standing(
              rank: 128,
              name: 'Bartholomew Featherstonehaugh-Wentworth',
              tier: ChefTier.masterChef,
              score: 987654.5,
              recipes: 128,
            ),
            textScale: scale,
          ),
        );
        await tester.pumpAndSettle();

        expect(
          tester.takeException(),
          isNull,
          reason: 'board row overflowed at ${scale}x',
        );
      });
    }
  });
}

/// The chefs page's panel width, restated here so the row's envelope test pins
/// the width the row is actually given. `ChefsScreen.panelWidth` lives in the
/// app package, which `design_system` cannot import.
abstract final class ChefsPanelWidth {
  static const double value = 404;
}
