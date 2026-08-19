import 'dart:async';

// Overrides `chefRepositoryProvider` (core) rather than the screen's own
// provider, so the FutureProvider wiring in chefs_providers.dart is exercised
// too instead of being stubbed out.
import 'package:app/features/chefs/chefs_screen.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stand-in for the RPC. `ChefRepository` is an abstract interface precisely so
/// it can be swapped like this — no Supabase client is constructed.
class _FakeChefRepository implements ChefRepository {
  _FakeChefRepository(this._result);

  /// A `List<ChefStanding>` to return, an `Exception` to throw, or null to
  /// hang forever (so the loading state can be observed).
  final Object? _result;

  @override
  Future<List<ChefStanding>> leaderboard({int limit = 50, int offset = 0}) {
    if (_result == null) return Completer<List<ChefStanding>>().future;
    if (_result is Exception) return Future.error(_result);
    return Future.value(_result as List<ChefStanding>);
  }
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

Widget _app(Object? result) => ProviderScope(
      overrides: [
        chefRepositoryProvider
            .overrideWithValue(_FakeChefRepository(result)),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: const ChefsScreen()),
    );

void main() {
  testWidgets('renders a ranked board with badges and tiers', (tester) async {
    await tester.pumpWidget(_app(_board));
    await tester.pumpAndSettle();

    expect(find.text('Amara Okonkwo'), findsOneWidget);
    expect(find.text('Master Chef'), findsOneWidget);
    expect(find.text('21000'), findsOneWidget); // no trailing .0
    expect(find.byType(ChefBadge), findsNWidgets(3));

    // Tied chefs share a rank: two rows both showing "4".
    expect(find.text('4'), findsNWidgets(2));
    expect(find.text('Sous Chef'), findsNWidgets(2));
  });

  testWidgets('shows the empty state when nobody qualifies', (tester) async {
    await tester.pumpWidget(_app(<ChefStanding>[]));
    await tester.pumpAndSettle();

    expect(find.byType(EmptyView), findsOneWidget);
    expect(find.text('No chefs yet'), findsOneWidget);
    expect(find.byType(ChefBadge), findsNothing);
  });

  testWidgets('shows a retryable error state', (tester) async {
    await tester.pumpWidget(_app(Exception('rpc down')));
    await tester.pumpAndSettle();

    expect(find.byType(ErrorView), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('shows the loading state while the RPC is in flight',
      (tester) async {
    await tester.pumpWidget(_app(null)); // never resolves
    await tester.pump();
    expect(find.byType(LoadingView), findsOneWidget);
    expect(find.byType(ChefBadge), findsNothing);
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

  for (final width in <double>[320, 360, 600]) {
    testWidgets('leaderboard row fits at ${width}px, textScale 2.0',
        (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chefRepositoryProvider
                .overrideWithValue(_FakeChefRepository(stress)),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(2.0)),
              child: ChefsScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester.takeException(),
        isNull,
        reason: 'overflow at ${width}px @ 2.0x',
      );
    });
  }
}
