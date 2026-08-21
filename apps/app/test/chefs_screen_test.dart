import 'dart:async';

// Overrides `chefRepositoryProvider` (core) rather than the screen's own
// provider, so the FutureProvider wiring in chefs_providers.dart is exercised
// too instead of being stubbed out.
import 'package:app/features/chefs/chef_detail_sheet.dart';
import 'package:app/features/chefs/chefs_hero.dart';
import 'package:app/features/chefs/chefs_providers.dart';
import 'package:app/features/chefs/chefs_screen.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stand-in for the RPCs. `ChefRepository` is an abstract interface precisely
/// so it can be swapped like this — no Supabase client is constructed.
class _FakeChefRepository implements ChefRepository {
  _FakeChefRepository(this._result, {this.recipes = const []});

  /// A `List<ChefStanding>` to return, an `Exception` to throw, or null to
  /// hang forever (so the loading state can be observed).
  final Object? _result;

  /// What `chef_top_recipes` returns. An `Exception` here stands for a database
  /// that has not had the RPC applied yet.
  final Object recipes;

  /// Fixed: the header renders "Rank 2 of 148" from this.
  static const count = 148;

  /// Every `leaderboard` call, so the paging test can prove the limit grew.
  final List<int> limits = [];

  @override
  Future<List<ChefStanding>> leaderboard({int limit = 50, int offset = 0}) {
    limits.add(limit);
    if (_result == null) return Completer<List<ChefStanding>>().future;
    if (_result is Exception) return Future.error(_result);
    // Honour the limit the way the RPC does — the board asks for a wider first
    // page rather than a second one, so `Show all` has to change this.
    final all = _result as List<ChefStanding>;
    return Future.value(all.take(limit).toList());
  }

  @override
  Future<List<Recipe>> topRecipes(String chefId, {int limit = 3}) {
    if (recipes is Exception) return Future.error(recipes as Exception);
    return Future.value(recipes as List<Recipe>);
  }

  // No `chefCount()` any more (OPT-P10) — the board's denominator is the sum of
  // the tier counts below, which is why they add up to [count] (148).
  @override
  Future<Map<ChefTier, int>> tierCounts() async => const {
        ChefTier.homeCook: 61,
        ChefTier.lineCook: 44,
        ChefTier.sousChef: 28,
        ChefTier.headChef: 14,
        ChefTier.masterChef: 1,
      };
}

class _FakeProfileRepository implements ProfileRepository {
  @override
  Future<Profile?> getById(String id) async => Profile(
        id: id,
        displayName: 'Secret Sauce Kitchen',
        createdAt: DateTime(2025, 3, 14),
      );

  @override
  Future<Profile?> findByEmailOrName(String query) async => null;

  @override
  Future<Profile> updateMine(Profile profile) async => profile;
}

const _board = [
  ChefStanding(
    chefRank: 1,
    id: 'd1',
    displayName: 'Amara Okonkwo',
    chefTier: ChefTier.masterChef,
    chefScore: 21000,
    publicRecipeCount: 2,
    totalLikes: 4000,
    totalSaves: 1600,
    totalViews: 5000,
  ),
  // Tied pair — dense_rank gives both rank 4, which must render as two "4"s.
  ChefStanding(
    chefRank: 4,
    id: 'd3',
    displayName: 'Chen Wei',
    chefTier: ChefTier.sousChef,
    chefScore: 1200,
    publicRecipeCount: 1,
  ),
  ChefStanding(
    chefRank: 4,
    id: 'd7',
    displayName: 'Greta Lindqvist',
    chefTier: ChefTier.sousChef,
    chefScore: 1200,
    publicRecipeCount: 1,
  ),
];

const _kitchen = ChefStanding(
  chefRank: 2,
  id: 'ssk',
  displayName: 'Secret Sauce Kitchen',
  chefTier: ChefTier.headChef,
  chefScore: 10189,
  publicRecipeCount: 14,
  totalLikes: 1980,
  totalSaves: 780,
  totalViews: 1745,
);

const _topRecipe = Recipe(
  id: 'r1',
  ownerId: 'ssk',
  title: 'Chicken Tikka Masala',
  likeCount: 820,
  saveCount: 310,
  viewCount: 400,
  ratingAvg: 4.3,
  ratingCount: 12,
);

/// Sizes the test window, since the screen now renders three different layouts.
/// 400 is the phone board, 1440 the two-column page.
void _size(WidgetTester tester, double width, [double height = 1000]) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

_FakeChefRepository? _lastRepo;

Widget _app(
  Object? result, {
  Object recipes = const <Recipe>[],
  double textScale = 1.0,
}) {
  final repo = _FakeChefRepository(result, recipes: recipes);
  _lastRepo = repo;
  return ProviderScope(
    overrides: [
      chefRepositoryProvider.overrideWithValue(repo),
      profileRepositoryProvider.overrideWithValue(_FakeProfileRepository()),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      // `builder`, not a MediaQuery around `home`: dialogs and sheets are
      // pushed above the Navigator, so anything wrapped inside `home` never
      // reaches them and the text-scale envelope would silently test 1.0x.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: const ChefsScreen(),
    ),
  );
}

void main() {
  // OPT-P10 removed `chefCount()`; `chefCountProvider` now sums the tier counts
  // instead, which is only correct because both cover the same population —
  // profiles with at least one public recipe. `chefs_tier_counts()` enforces
  // that server-side; this pins it for the fake, so every "of 148" assertion
  // below keeps meaning what it says.
  test('the fake tier counts sum to the board total', () async {
    final counts = await _FakeChefRepository(const []).tierCounts();
    expect(
      counts.values.fold<int>(0, (sum, n) => sum + n),
      _FakeChefRepository.count,
    );
  });

  group('compact board', () {
    testWidgets('renders a ranked board with tiers and grouped scores',
        (tester) async {
      _size(tester, 400);
      await tester.pumpWidget(_app(_board));
      await tester.pumpAndSettle();

      expect(find.text('Amara Okonkwo'), findsOneWidget);
      expect(find.text('Master Chef'), findsOneWidget);
      expect(find.text('21,000'), findsOneWidget);
      expect(find.byType(ChefStandingCard), findsNWidgets(3));

      // Rank 1 is a podium row: medal + "#1", no numeral.
      expect(find.byIcon(Icons.workspace_premium), findsOneWidget);
      expect(find.text('#1'), findsOneWidget);

      // Tied chefs share a rank: two rows both showing "4", both below the
      // podium so both render the numeral.
      expect(find.text('4'), findsNWidgets(2));
      expect(find.text('Sous Chef'), findsNWidgets(2));

      // The page chrome is web-only.
      expect(find.byType(ChefsHero), findsNothing);
      expect(find.byType(CardRail), findsNothing);
    });

    testWidgets('shows the empty state when nobody qualifies', (tester) async {
      _size(tester, 400);
      await tester.pumpWidget(_app(<ChefStanding>[]));
      await tester.pumpAndSettle();

      expect(find.byType(EmptyView), findsOneWidget);
      expect(find.text('No chefs yet'), findsOneWidget);
      expect(find.byType(ChefStandingCard), findsNothing);
    });

    testWidgets('shows a retryable error state', (tester) async {
      _size(tester, 400);
      await tester.pumpWidget(_app(Exception('rpc down')));
      await tester.pumpAndSettle();

      expect(find.byType(ErrorView), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('shows the loading state while the RPC is in flight',
        (tester) async {
      _size(tester, 400);
      await tester.pumpWidget(_app(null)); // never resolves
      await tester.pump();
      expect(find.byType(LoadingView), findsOneWidget);
      expect(find.byType(ChefStandingCard), findsNothing);
    });
  });

  group('the page', () {
    testWidgets('draws the hero, the board panel and three rails',
        (tester) async {
      // Tall enough that the rails column builds all three: a `ListView` only
      // builds what is on screen, so a 1000px window would legitimately show
      // two and this would be testing the viewport, not the page.
      _size(tester, 1440, 2200);
      await tester.pumpWidget(_app(_board));
      await tester.pumpAndSettle();

      // Hero: population, ranking rule, and the five tier tiles.
      expect(find.byType(ChefsHero), findsOneWidget);
      expect(find.text('148 ranked'), findsOneWidget);
      expect(find.text('61'), findsOneWidget); // Home Cook tile
      expect(find.text('HOME COOK'), findsOneWidget);
      expect(find.text('MASTER CHEF'), findsWidgets);

      // The draft's "recomputed 4h ago" is wrong about this build.
      expect(find.textContaining('RECOMPUTED'), findsNothing);
      expect(find.textContaining('LIVE ·'), findsOneWidget);

      // Board panel, in its dense variant.
      expect(find.text('Leaderboard'), findsOneWidget);
      expect(find.text('TOP 3 / 148'), findsOneWidget);
      expect(find.text('Ties share a rank.'), findsOneWidget);
      expect(
        tester
            .widgetList<ChefStandingCard>(find.byType(ChefStandingCard))
            .every((c) => c.variant == ChefCardVariant.board),
        isTrue,
      );

      // Three rails, the first of them real cards.
      expect(find.byType(CardRail), findsNWidgets(3));
      expect(find.text('Popular chefs'), findsOneWidget);
      expect(find.text('Trending chefs'), findsOneWidget);
      expect(find.text('Best chefs of the month'), findsOneWidget);
      expect(find.byType(ChefSpotlightCard), findsWidgets);
    });

    testWidgets('the windowed rails are honest placeholders', (tester) async {
      _size(tester, 1440, 2200);
      await tester.pumpWidget(_app(_board));
      await tester.pumpAndSettle();

      expect(find.byType(SpotlightCardPlaceholder), findsWidgets);
      expect(
        find.textContaining('needs dated likes and saves'),
        findsNWidgets(2),
      );
    });

    testWidgets('an empty board shows no Popular shelf at all', (tester) async {
      _size(tester, 1440, 2200);
      await tester.pumpWidget(_app(<ChefStanding>[]));
      await tester.pumpAndSettle();

      // A loaded-and-empty board must not render placeholder cards: that reads
      // as "still loading" and claims chefs the panel's empty state denies.
      expect(find.text('Popular chefs'), findsNothing);
      expect(find.byType(EmptyView), findsOneWidget);
      // The two windowed shelves are placeholders by design and stay.
      expect(find.byType(CardRail), findsNWidgets(2));
    });

    testWidgets('the disabled orderings and windows are inert, not hidden',
        (tester) async {
      _size(tester, 1440);
      await tester.pumpWidget(_app(_board));
      await tester.pumpAndSettle();

      for (final label in ['Score', 'Momentum', 'New']) {
        expect(find.text(label), findsOneWidget);
      }
      for (final label in ['All time', 'Month', 'Week']) {
        expect(find.text(label), findsOneWidget);
      }

      // Tapping a disabled tab changes nothing.
      await tester.tap(find.text('Momentum'));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ChefsScreen)),
      );
      expect(container.read(boardSortProvider), BoardSort.score);
    });

    testWidgets('`Show all` asks the RPC for a wider page', (tester) async {
      _size(tester, 1440);
      final many = [
        for (var i = 0; i < 30; i++)
          ChefStanding(
            chefRank: i + 1,
            id: 'c$i',
            displayName: 'Chef $i',
            chefScore: (3000 - i * 100).toDouble(),
            publicRecipeCount: 1,
          ),
      ];

      await tester.pumpWidget(_app(many));
      await tester.pumpAndSettle();

      expect(_lastRepo!.limits.first, kLeaderboardPageSize);
      expect(find.text('TOP 25 / 148'), findsOneWidget);

      await tester.tap(find.text('Show all 148'));
      await tester.pumpAndSettle();

      expect(_lastRepo!.limits.last, kLeaderboardPageSize * 2);
      expect(find.text('TOP 30 / 148'), findsOneWidget);
    });

    testWidgets('a spotlight card carries the score and its top driver',
        (tester) async {
      _size(tester, 1440);
      await tester.pumpWidget(_app(const [_kitchen], recipes: [_topRecipe]));
      await tester.pumpAndSettle();

      // 780 saves x 5 = 3,900 beats 1,980 likes x 3 = 5,940? No — likes lead,
      // which is exactly what the card must say.
      expect(find.text('Driven by likes'), findsOneWidget);
      expect(find.text('1,980 likes × 3'), findsOneWidget);
      expect(find.text('RANK 2'), findsOneWidget);
      expect(find.text('002 / 148'), findsOneWidget);
      expect(find.text('14 recipes'), findsWidgets);
      expect(find.text('HEAD → MASTER'), findsOneWidget);
      expect(find.text('9,811 to go'), findsOneWidget);
    });

    testWidgets('a spotlight card opens the expanded chef card',
        (tester) async {
      _size(tester, 1440);
      await tester.pumpWidget(_app(const [_kitchen], recipes: [_topRecipe]));
      await tester.pumpAndSettle();

      expect(find.byType(ChefDetailView), findsNothing);
      await tester.tap(find.byType(ChefSpotlightCard).first);
      await tester.pumpAndSettle();

      expect(find.byType(ChefDetailView), findsOneWidget);
    });
  });

  group('expanded chef card', () {
    testWidgets('a row tap opens it with the score explained', (tester) async {
      _size(tester, 1200, 900);

      await tester.pumpWidget(_app(const [_kitchen], recipes: [_topRecipe]));
      await tester.pumpAndSettle();

      expect(find.byType(ChefDetailView), findsNothing);
      // The name is on the panel row and again on the rail card; the panel row
      // comes first in the tree.
      await tester.tap(find.text('Secret Sauce Kitchen').first);
      await tester.pumpAndSettle();

      expect(find.byType(ChefDetailView), findsOneWidget);

      // The multipliers are the reason the card exists.
      expect(find.text('1,980 likes × 3'), findsWidgets);
      expect(find.text('780 saves × 5'), findsOneWidget);
      expect(find.text('1,745 views × 0.2'), findsOneWidget);
      // Twice: the dialog's breakdown, and the spotlight card behind it, which
      // names the same top contribution.
      expect(find.text('5,940'), findsWidgets);

      // Rank line uses the count RPC; joined date comes from the profile.
      expect(find.textContaining('Rank 2 of 148'), findsOneWidget);
      expect(find.textContaining('joined Mar 2025'), findsOneWidget);

      // Ladder + gap to the next tier.
      expect(find.byType(TierLadder), findsOneWidget);
      expect(find.textContaining('9,811 points to Master Chef'), findsOneWidget);

      // Top recipes, ordered by contribution, with what each contributed.
      expect(find.text('Chicken Tikka Masala'), findsOneWidget);
      expect(find.text('4,090'), findsOneWidget); // 820*3 + 310*5 + 400*0.2

      // Nothing that does not exist in the build.
      expect(find.text('Follow'), findsNothing);
      expect(find.textContaining('View all'), findsNothing);
      expect(find.textContaining('nightly'), findsOneWidget); // "no nightly job"
    });

    testWidgets('opens as a bottom sheet on a phone', (tester) async {
      _size(tester, 400, 900);

      await tester.pumpWidget(_app(const [_kitchen], recipes: [_topRecipe]));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Secret Sauce Kitchen'));
      await tester.pumpAndSettle();

      expect(find.byType(ChefDetailView), findsOneWidget);
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets('survives a database without the chef_top_recipes RPC',
        (tester) async {
      _size(tester, 1200, 900);

      await tester.pumpWidget(
        _app(const [_kitchen], recipes: Exception('function does not exist')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Secret Sauce Kitchen').first);
      await tester.pumpAndSettle();

      // One section degrades; the score explanation still renders.
      expect(find.text('Top recipes are unavailable right now.'), findsOneWidget);
      expect(find.text('1,980 likes × 3'), findsWidgets);
    });
  });

  // Worst realistic envelope for a leaderboard row: the narrowest phone, 2.0x
  // accessibility scaling, the longest tier label, a long display name, and
  // six-figure counts. Two real overflows were found here before the score
  // column was bounded and the stat labels made Flexible.
  const stress = [
    ChefStanding(
      chefRank: 1,
      id: 'x',
      displayName: 'Bartholomew Featherstonehaugh-Wentworth',
      chefTier: ChefTier.masterChef,
      chefScore: 987654.5,
      publicRecipeCount: 128,
      totalLikes: 240000,
      totalSaves: 180000,
      totalViews: 990000,
    ),
  ];

  // 320/360 are the phone board; 600 is the stacked page and 1000/1440 the
  // two-column one, so this sweeps all three layouts at the accessibility
  // envelope.
  for (final width in <double>[320, 360, 600, 1000, 1440]) {
    testWidgets('the chefs page fits at ${width}px, textScale 2.0',
        (tester) async {
      _size(tester, width, 1200);

      await tester.pumpWidget(_app(stress, textScale: 2.0));
      await tester.pumpAndSettle();

      expect(
        tester.takeException(),
        isNull,
        reason: 'overflow at ${width}px @ 2.0x',
      );
    });
  }

  testWidgets('the expanded card fits a 360px phone at 2.0x text scale',
      (tester) async {
    _size(tester, 360, 900);

    await tester.pumpWidget(
      _app(const [_kitchen], recipes: [_topRecipe], textScale: 2.0),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Secret Sauce Kitchen'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull, reason: 'overflow in the sheet');
  });
}
