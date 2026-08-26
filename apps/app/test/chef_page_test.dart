import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:app/features/chefs/chef_page.dart';
import 'package:app/routing/app_router.dart';

/// `/chef/:id` — the page that replaced the expanded chef dialog (Phase 30).
///
/// The content assertions here are the dialog suite's, moved: the multipliers,
/// the rank line, the joined date, the ladder and the gap to the next tier are
/// what the card existed to show, so they have to keep being asserted
/// somewhere. What is new is the shape the dialog never had to handle — a page
/// that starts from a uuid, so the profile can be missing and the standing can
/// legitimately be null.

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

Recipe _recipe(String id, String title) =>
    Recipe(id: id, ownerId: 'ssk', title: title);

class _FakeChefRepository implements ChefRepository {
  _FakeChefRepository({this.result = _kitchen, this.fail = false});

  /// The standing to answer with. Null models a real profile that holds no
  /// board row — the private-only case, not an error.
  final ChefStanding? result;
  final bool fail;

  @override
  Future<ChefStanding?> standing(String chefId) {
    if (fail) return Future.error(Exception('boom'));
    return Future.value(result);
  }

  @override
  Future<List<ChefStanding>> leaderboard({int limit = 50, int offset = 0}) =>
      throw UnimplementedError();

  @override
  Future<List<Recipe>> topRecipes(String chefId, {int limit = 3}) =>
      throw UnimplementedError();

  @override
  Future<Map<ChefTier, int>> tierCounts() => throw UnimplementedError();
}

class _FakeProfileRepository implements ProfileRepository {
  _FakeProfileRepository({this.profile});

  /// Null models a uuid with no profile behind it — a bad link, which is the
  /// one case that is genuinely an error rather than a state.
  final Profile? profile;

  @override
  Future<Profile?> getById(String id) async => profile;

  @override
  Future<List<Profile>> searchByName(String query, {int limit = 10}) async =>
      const [];

  @override
  Future<Profile> updateMine(Profile profile) async => profile;
}

class _FakeRecipeRepository implements RecipeRepository {
  _FakeRecipeRepository({this.pages = const []});

  /// Successive pages handed to `listByChef`, in order.
  final List<List<Recipe>> pages;

  /// Every (chefId, limit, offset) the page asked for.
  final List<(String, int, int)> calls = [];

  @override
  Future<List<Recipe>> listByChef(
    String chefId, {
    int limit = kRecipePageSize,
    int offset = 0,
  }) async {
    calls.add((chefId, limit, offset));
    final index = offset ~/ limit;
    return index < pages.length ? pages[index] : const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Widget _app({
  ChefStanding? standing = _kitchen,
  bool standingFails = false,
  Profile? profile,

  /// Explicit, because `profile: null` cannot be told from "not supplied" by a
  /// `??` default — and "the profile is missing" is one of the cases under test.
  bool noProfile = false,
  List<List<Recipe>> pages = const [],
  _FakeRecipeRepository? recipes,
  double textScale = 1.0,
  String chefId = 'ssk',
}) {
  return ProviderScope(
    overrides: [
      chefRepositoryProvider.overrideWithValue(
        _FakeChefRepository(result: standing, fail: standingFails),
      ),
      profileRepositoryProvider.overrideWithValue(
        _FakeProfileRepository(
          profile:
              noProfile
                  ? null
                  : profile ??
                      Profile(
                        id: 'ssk',
                        displayName: 'Secret Sauce Kitchen',
                        createdAt: DateTime(2025, 3, 14),
                        chefTier: ChefTier.headChef,
                        publicRecipeCount: 14,
                      ),
        ),
      ),
      recipeRepositoryProvider.overrideWithValue(
        recipes ?? _FakeRecipeRepository(pages: pages),
      ),
    ],
    child: MaterialApp.router(
      theme: AppTheme.light(),
      builder:
          (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
      routerConfig: GoRouter(
        initialLocation: Routes.chef(chefId),
        routes: [
          GoRoute(
            path: Routes.chefPattern,
            builder:
                (context, state) =>
                    ChefPage(chefId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: Routes.chefs,
            builder: (context, state) => const Scaffold(body: Text('BOARD')),
          ),
        ],
      ),
    ),
  );
}

void _size(WidgetTester tester, double width, [double height = 1200]) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  group('a ranked chef', () {
    testWidgets('explains the score the way the dialog did', (tester) async {
      _size(tester, 1000);
      await tester.pumpWidget(
        _app(
          pages: [
            [_recipe('r1', 'Chicken Tikka Masala')],
          ],
        ),
      );
      await tester.pumpAndSettle();

      // The multipliers are the reason this surface exists at all (Phase 22).
      expect(find.text('1,980 likes × 3'), findsOneWidget);
      expect(find.text('780 saves × 5'), findsOneWidget);
      expect(find.text('1,745 views × 0.2'), findsOneWidget);

      // Rank comes from the standing; the joined date from the profile.
      expect(find.textContaining('Rank 2'), findsOneWidget);
      expect(find.textContaining('joined Mar 2025'), findsOneWidget);

      expect(find.byType(TierLadder), findsOneWidget);
      expect(
        find.textContaining('9,811 points to Master Chef'),
        findsOneWidget,
      );

      // Phase 22's deliberate correction of the mockup. It lived in the panel
      // that was deleted with the dialog, so this pins that it survived.
      expect(find.textContaining('no nightly job'), findsOneWidget);
    });

    testWidgets('lists the public recipes, singularising the count', (
      tester,
    ) async {
      _size(tester, 1000);
      await tester.pumpWidget(
        _app(
          standing: _kitchen.copyWith(publicRecipeCount: 1),
          profile: Profile(
            id: 'ssk',
            displayName: 'Secret Sauce Kitchen',
            createdAt: DateTime(2025, 3, 14),
            publicRecipeCount: 1,
          ),
          pages: [
            [_recipe('r1', 'Chicken Tikka Masala')],
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Chicken Tikka Masala'), findsOneWidget);
      // B031: `1 public recipes` is the bug this repo has shipped once already.
      expect(find.text('1 PUBLIC RECIPE'), findsOneWidget);
    });

    testWidgets('asks the repository for this chef, newest first, paged', (
      tester,
    ) async {
      _size(tester, 1000);
      final repo = _FakeRecipeRepository(
        pages: [
          [for (var i = 0; i < kRecipePageSize; i++) _recipe('r$i', 'R$i')],
          [_recipe('last', 'Last One')],
        ],
      );
      await tester.pumpWidget(_app(recipes: repo));
      await tester.pumpAndSettle();

      expect(repo.calls.first, ('ssk', kRecipePageSize, 0));

      // A full first page is the only evidence more rows exist, so Load more
      // is offered — and it must page *this* chef's offsets. It sits under 20
      // cards in a lazy sliver, so it has to be scrolled into existence first.
      await tester.scrollUntilVisible(find.text('Load more'), 600);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Load more'));
      await tester.pumpAndSettle();

      expect(repo.calls.last, ('ssk', kRecipePageSize, kRecipePageSize));
      expect(find.text('Last One'), findsOneWidget);
    });

    testWidgets('does not repeat the chef badge on every card', (tester) async {
      _size(tester, 1000);
      await tester.pumpWidget(
        _app(
          pages: [
            [_recipe('r1', 'Chicken Tikka Masala')],
          ],
        ),
      );
      await tester.pumpAndSettle();

      // You are on their page; naming them on each of their own cards is noise.
      expect(find.byType(ChefBadge), findsNothing);
    });
  });

  group('a chef with no rank', () {
    testWidgets('is a page, not an error', (tester) async {
      _size(tester, 1000);
      await tester.pumpWidget(
        _app(
          standing: null,
          profile: Profile(
            id: 'd6',
            displayName: 'Farid Haddad',
            createdAt: DateTime(2025, 6, 1),
          ),
          chefId: 'd6',
        ),
      );
      await tester.pumpAndSettle();

      // The seed's private-only chef: a real profile that holds no board row.
      expect(find.text('Farid Haddad'), findsOneWidget);
      expect(find.textContaining('Not ranked yet'), findsOneWidget);
      expect(find.textContaining('do not hold'), findsOneWidget);

      // No score panel — there is no score to explain, and rendering one full
      // of zeroes would be a worse lie than omitting it.
      expect(find.byType(TierLadder), findsNothing);
      expect(find.byType(ErrorView), findsNothing);

      expect(find.text('No public recipes'), findsOneWidget);
    });
  });

  group('failures', () {
    testWidgets('a missing profile is an error with a retry', (tester) async {
      _size(tester, 1000);
      await tester.pumpWidget(_app(noProfile: true));
      await tester.pumpAndSettle();

      expect(find.byType(ErrorView), findsOneWidget);
    });

    testWidgets('a failed standing fails the page rather than half of it', (
      tester,
    ) async {
      _size(tester, 1000);
      await tester.pumpWidget(_app(standingFails: true));
      await tester.pumpAndSettle();

      // Unlike the dialog, the page has no board-supplied standing to fall back
      // on, so a swallowed failure would render a chef with no rank and no
      // score as though that were the truth.
      expect(find.byType(ErrorView), findsOneWidget);
    });
  });

  // Fixed-height header over a grid is the Gotcha 22 shape, and the header's
  // fact line is the Wrap the dialog needed for exactly this reason.
  for (final width in <double>[320, 390, 600, 1000, 1440]) {
    for (final scale in <double>[1.0, 2.0]) {
      testWidgets('fits at ${width}px, textScale $scale', (tester) async {
        _size(tester, width, 1400);
        await tester.pumpWidget(
          _app(
            textScale: scale,
            standing: _kitchen.copyWith(
              displayName: 'Bartholomew Featherstonehaugh-Wentworth',
              chefScore: 987654.5,
              totalLikes: 240000,
              totalSaves: 180000,
              totalViews: 990000,
            ),
            profile: Profile(
              id: 'ssk',
              displayName: 'Bartholomew Featherstonehaugh-Wentworth',
              createdAt: DateTime(2025, 3, 14),
              publicRecipeCount: 128,
              bio: 'Cooking since 1994, mostly braises and long ferments.',
            ),
            pages: [
              [_recipe('r1', 'Slow-Braised Short Rib with Gremolata')],
            ],
          ),
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
}
