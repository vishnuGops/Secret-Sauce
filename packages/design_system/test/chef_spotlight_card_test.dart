import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ChefStanding _standing({
  int rank = 2,
  String name = 'Secret Sauce Kitchen',
  ChefTier tier = ChefTier.headChef,
  double score = 10189,
  int recipes = 14,
  int likes = 1980,
  int saves = 780,
  int views = 1745,
}) => ChefStanding(
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
  Widget card, {
  double textScale = 1.0,
  Brightness brightness = Brightness.light,
}) => MaterialApp(
  theme: brightness == Brightness.light ? AppTheme.light() : AppTheme.dark(),
  home: Scaffold(
    body: MediaQuery(
      data: MediaQueryData(
        size: const Size(1440, 900),
        textScaler: TextScaler.linear(textScale),
      ),
      // Unbounded height on purpose: the card is a fixed-size tile and must
      // size itself, exactly as it does inside a horizontal rail.
      child: Align(alignment: Alignment.topLeft, child: card),
    ),
  ),
);

void main() {
  testWidgets('carries score, rank, serial, tier and the four totals', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        ChefSpotlightCard(standing: _standing(), totalChefs: 148, onTap: () {}),
      ),
    );

    expect(find.text('10,189'), findsOneWidget);
    expect(find.text('PTS'), findsOneWidget);
    expect(find.text('RANK 2'), findsOneWidget);
    // Zero-padded rank over the population — the draft's "S1 · 002/148" minus
    // the season, which this build has no model for.
    expect(find.text('002 / 148'), findsOneWidget);
    expect(find.textContaining('S1'), findsNothing);

    expect(find.text('HEAD CHEF'), findsOneWidget);
    expect(find.text('14 recipes'), findsOneWidget);

    expect(find.text('1,980'), findsOneWidget); // likes
    expect(find.text('780'), findsOneWidget); // saves
    expect(find.text('1,745'), findsOneWidget); // views
    expect(find.text('rec'), findsOneWidget);

    expect(find.text('HEAD → MASTER'), findsOneWidget);
    expect(find.text('9,811 to go'), findsOneWidget);
  });

  testWidgets('the driver row names the input doing the most work', (
    tester,
  ) async {
    // 1,980 likes x 3 = 5,940 beats 780 saves x 5 = 3,900.
    await tester.pumpWidget(
      _host(ChefSpotlightCard(standing: _standing(), onTap: () {})),
    );
    expect(find.text('Driven by likes'), findsOneWidget);
    expect(find.text('1,980 likes × 3'), findsOneWidget);
    expect(find.text('5,940'), findsOneWidget);

    // Flip the weights' favour: 400 likes x 3 = 1,200 against 900 saves x 5.
    await tester.pumpWidget(
      _host(
        ChefSpotlightCard(
          standing: _standing(likes: 400, saves: 900, views: 0),
          onTap: () {},
        ),
      ),
    );
    expect(find.text('Driven by saves'), findsOneWidget);
    expect(find.text('900 saves × 5'), findsOneWidget);
  });

  testWidgets('the serial drops the denominator until the count lands', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(ChefSpotlightCard(standing: _standing(rank: 7), onTap: () {})),
    );
    expect(find.text('007'), findsOneWidget);
  });

  testWidgets('a single recipe is not "1 recipes" (B031)', (tester) async {
    await tester.pumpWidget(
      _host(ChefSpotlightCard(standing: _standing(recipes: 1), onTap: () {})),
    );
    expect(find.text('1 recipe'), findsOneWidget);
    expect(find.text('1 recipes'), findsNothing);
  });

  testWidgets('the top tier says so instead of promising a next one', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        ChefSpotlightCard(
          standing: _standing(tier: ChefTier.masterChef, score: 21000),
          onTap: () {},
        ),
      ),
    );
    expect(find.text('TOP TIER REACHED'), findsOneWidget);
    expect(find.text('max'), findsOneWidget);
    expect(find.textContaining('to go'), findsNothing);
  });

  testWidgets('foil intensity rises with tier', (tester) async {
    expect(
      ChefSpotlightCard.foilFor(ChefTier.homeCook),
      lessThan(ChefSpotlightCard.foilFor(ChefTier.lineCook)),
    );
    expect(
      ChefSpotlightCard.foilFor(ChefTier.headChef),
      lessThan(ChefSpotlightCard.foilFor(ChefTier.masterChef)),
    );
  });

  testWidgets('the whole card is one tap target', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _host(ChefSpotlightCard(standing: _standing(), onTap: () => taps++)),
    );
    await tester.tap(find.byType(ChefSpotlightCard));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('a chef with no avatar falls back to the monogram', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(ChefSpotlightCard(standing: _standing(), onTap: () {})),
    );
    // The portrait window has no asset behind it yet, so it draws the same
    // initials circle the rest of the app uses.
    expect(find.byType(ChefAvatar), findsOneWidget);
    expect(find.text('SK'), findsOneWidget);
  });

  group('placeholder', () {
    testWidgets('matches the real card geometry', (tester) async {
      await tester.pumpWidget(_host(const SpotlightCardPlaceholder()));
      final box = tester.getSize(find.byType(SpotlightCardPlaceholder));
      expect(box.width, kSpotlightCardWidth);
      expect(box.height, kSpotlightCardHeight);
    });

    testWidgets('says nothing a real card would say', (tester) async {
      await tester.pumpWidget(_host(const SpotlightCardPlaceholder()));
      expect(find.text('PTS'), findsNothing);
      expect(find.textContaining('RANK'), findsNothing);
    });
  });

  testWidgets('the name gets the width the score does not use', (tester) async {
    await tester.pumpWidget(
      _host(
        ChefSpotlightCard(
          standing: _standing(name: 'Secret Sauce Kitchen', score: 10189),
          onTap: () {},
        ),
      ),
    );

    // The header was an `Expanded` name beside a `Flexible` score, which splits
    // the row 50/50 whatever the content — the name truncated at half the card
    // while a shorter score left dead space beside it. The score is capped and
    // intrinsic now, so the name takes the remainder.
    //
    // Asserted as a ratio, not a pixel count: `flutter test` renders in a
    // fixed-width font far wider than Roboto, so any absolute width here would
    // be measuring the test harness rather than the layout.
    final nameWidth = tester.getSize(find.text('Secret Sauce Kitchen')).width;
    final scoreWidth = tester.getSize(find.text('10,189')).width;
    expect(nameWidth, greaterThan(scoreWidth));
  });

  // The card is a fixed-size tile, so text growth has nowhere to go except the
  // portrait — and the intrinsic bands alone exceed the 1.0x height well before
  // 2.0x. `spotlightCardHeight` is what keeps that from overflowing; these
  // pin it. Same failure mode as B001 / B002 / B016.
  //
  // 3.0 is past the growth clamp on purpose: above 2.5x the tile stops growing
  // and the portrait absorbs the difference, which is the last line of defence.
  for (final scale in <double>[1.0, 1.3, 1.6, 2.0, 3.0]) {
    testWidgets('fits its own tile at textScale $scale', (tester) async {
      await tester.pumpWidget(
        _host(
          ChefSpotlightCard(
            standing: _standing(
              name: 'Bartholomew Featherstonehaugh-Wentworth',
              score: 987654.5,
              recipes: 128,
              likes: 240000,
              saves: 180000,
              views: 990000,
            ),
            totalChefs: 148000,
            onTap: () {},
          ),
          textScale: scale,
        ),
      );
      expect(
        tester.takeException(),
        isNull,
        reason: 'spotlight card overflowed at ${scale}x',
      );
    });
  }

  testWidgets('renders on a dark theme without exploding', (tester) async {
    await tester.pumpWidget(
      _host(
        ChefSpotlightCard(standing: _standing(), onTap: () {}),
        brightness: Brightness.dark,
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('10,189'), findsOneWidget);
  });
}
