import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child, {double? width, double scale = 1.0, Brightness? b}) {
  return MaterialApp(
    theme: b == Brightness.dark ? AppTheme.dark() : AppTheme.light(),
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: Scaffold(
        body: Center(
          child: width == null ? child : SizedBox(width: width, child: child),
        ),
      ),
    ),
  );
}

void main() {
  group('TierChip', () {
    testWidgets('renders the label for every tier', (tester) async {
      for (final tier in ChefTier.values) {
        await tester.pumpWidget(_wrap(TierChip(tier: tier)));
        expect(find.text(tier.label), findsOneWidget);
      }
    });

    test('labels and rungs match the SQL enum order', () {
      expect(ChefTier.values.map((t) => t.label), [
        'Home Cook',
        'Line Cook',
        'Sous Chef',
        'Head Chef',
        'Master Chef',
      ]);
      // chef_tier_for() returns these in ascending score order; the rung index
      // is used for styling ramps, so a reorder here is a silent visual bug.
      expect(ChefTier.values.map((t) => t.rank), [0, 1, 2, 3, 4]);
    });

    testWidgets('picks a different accent per brightness', (tester) async {
      for (final tier in ChefTier.values) {
        expect(
          TierChip.colorFor(tier, Brightness.light),
          isNot(TierChip.colorFor(tier, Brightness.dark)),
          reason: '${tier.name} must not reuse one color across themes',
        );
      }
    });

    testWidgets('dense variant drops the icon', (tester) async {
      await tester.pumpWidget(_wrap(const TierChip(tier: ChefTier.headChef)));
      expect(find.byIcon(TierChip.iconFor(ChefTier.headChef)), findsOneWidget);

      await tester.pumpWidget(
        _wrap(const TierChip(tier: ChefTier.headChef, dense: true)),
      );
      expect(find.byIcon(TierChip.iconFor(ChefTier.headChef)), findsNothing);
      expect(find.text('Head Chef'), findsOneWidget);
    });
  });

  group('ChefBadge', () {
    testWidgets('shows the name with the tier underneath it', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ChefBadge(name: 'Amara Okonkwo', tier: ChefTier.masterChef),
          width: 320,
        ),
      );

      expect(find.text('Amara Okonkwo'), findsOneWidget);
      expect(find.text('Master Chef'), findsOneWidget);

      // The requirement is specifically "tier under the name", not beside it.
      // Compare the chip's own box, not its label — the label sits 25px inside
      // the chip (padding + icon + gap), so a text-to-text comparison would
      // fail a correctly-aligned layout.
      final name = tester.getRect(find.text('Amara Okonkwo'));
      final chip = tester.getRect(find.byType(TierChip));
      expect(
        chip.top,
        greaterThanOrEqualTo(name.bottom - 1),
        reason: 'tier must sit below the name, not beside it',
      );
      expect(
        (chip.left - name.left).abs(),
        lessThan(2),
        reason: 'tier must be left-aligned with the name',
      );
    });

    testWidgets('falls back to initials without an avatar url', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ChefBadge(name: 'Greta Lindqvist', tier: ChefTier.sousChef),
          width: 320,
        ),
      );
      expect(find.text('GL'), findsOneWidget);
    });

    testWidgets('survives an empty display name', (tester) async {
      await tester.pumpWidget(
        _wrap(const ChefBadge(name: '', tier: ChefTier.homeCook), width: 320),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Unnamed chef'), findsOneWidget);
      expect(find.text('?'), findsOneWidget);
    });

    testWidgets('fromProfile carries tier and avatar across', (tester) async {
      const profile = Profile(
        id: 'd1',
        displayName: 'Bruno Castellani',
        chefTier: ChefTier.headChef,
      );
      await tester.pumpWidget(
        _wrap(ChefBadge.fromProfile(profile), width: 320),
      );
      expect(find.text('Bruno Castellani'), findsOneWidget);
      expect(find.text('Head Chef'), findsOneWidget);
    });
  });

  group('RecipeCard chef overlay', () {
    // The owner badge is an overlay on the cover Stack, never a new row in the
    // footer column — the tile is fixed-height and cannot grow
    // (B001/B002/B016). Worst realistic envelope: `kRecipeCardMinWidth` (the
    // narrowest column the grid packs to), the longest tier label, the longest
    // time label, a 4-digit rating count, and 2.0x accessibility text scale.
    const worstCase = Recipe(
      id: '1',
      ownerId: 'd1',
      title: 'Slow-Braised Short Rib Ragu',
      description: 'Long enough to ellipsize over two lines.',
      difficulty: Difficulty.medium,
      prepMinutes: 90,
      cookMinutes: 675, // "12h 45m"
      ratingAvg: 4.5,
      ratingCount: 1250,
      owner: Profile(
        id: 'd1',
        displayName: 'Bartholomew Featherstonehaugh',
        chefTier: ChefTier.masterChef, // longest label
      ),
    );

    for (final (width, scale) in <(double, double)>[
      (kRecipeCardMinWidth, 1.0),
      (kRecipeCardMaxWidth, 1.0),
      (kRecipeCardMinWidth, 2.0),
      (kRecipeCardMaxWidth, 2.0),
    ]) {
      testWidgets('fits at ${width}px, textScale $scale', (tester) async {
        await tester.pumpWidget(
          _wrap(
            const RecipeCard(recipe: worstCase),
            width: width,
            scale: scale,
          ),
        );
        expect(
          tester.takeException(),
          isNull,
          reason: 'overflow at ${width}px @ ${scale}x',
        );
      });
    }

    testWidgets('renders the badge only when an owner is embedded',
        (tester) async {
      const noOwner = Recipe(id: '1', ownerId: 'd1', title: 'No embed');
      await tester.pumpWidget(
        _wrap(const RecipeCard(recipe: noOwner), width: 320),
      );
      expect(find.byType(ChefBadge), findsNothing);

      await tester.pumpWidget(
        _wrap(const RecipeCard(recipe: worstCase), width: 320),
      );
      expect(find.byType(ChefBadge), findsOneWidget);
    });

    testWidgets('showChef: false suppresses the badge', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const RecipeCard(recipe: worstCase, showChef: false),
          width: 320,
        ),
      );
      expect(find.byType(ChefBadge), findsNothing);
    });

    testWidgets('badge and visibility pill coexist without overflow',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          const RecipeCard(recipe: worstCase, showVisibility: true),
          width: kRecipeCardMinWidth,
          scale: 2.0,
        ),
      );
      expect(tester.takeException(), isNull);
      // v2 puts the visibility chip in the title banner, icon-only.
      expect(find.byTooltip('Private'), findsOneWidget);
    });

    // v2 moved the overlay to the bottom-right of the cover, inset by
    // AppSpacing.sm. Asserted, not just "it renders somewhere" — the position
    // is the contract the design pins down.
    testWidgets('overlay sits bottom-right of the cover', (tester) async {
      await tester.pumpWidget(
        _wrap(const RecipeCard(recipe: worstCase), width: kRecipeCardMinWidth),
      );

      final card = tester.getRect(find.byType(RecipeCard));
      final badge = tester.getRect(find.byType(ChefBadge));

      // Right-aligned against the card's right edge (scrim padding + inset).
      expect(card.right - badge.right, lessThan(24));
      // In the lower half of the card, above the footer.
      expect(badge.center.dy, greaterThan(card.center.dy));
    });
  });
}
