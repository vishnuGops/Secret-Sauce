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

  /// Every ranking the page asked for: which RPC, for whom, and the page
  /// window. The two tabs are indistinguishable on screen — same cards, one
  /// order apart — so the request is the only thing worth asserting.
  final List<(String, String, int, int)> calls = [];

  @override
  Future<ChefStanding?> standing(String chefId) {
    if (fail) return Future.error(Exception('boom'));
    return Future.value(result);
  }

  @override
  Future<List<ChefStanding>> leaderboard({int limit = 50, int offset = 0}) =>
      throw UnimplementedError();

  @override
  Future<List<Recipe>> topRecipes(
    String chefId, {
    int limit = 3,
    int offset = 0,
  }) async {
    calls.add(('top', chefId, limit, offset));
    return offset == 0 ? [_recipe('pop', 'Most Liked Thing')] : const [];
  }

  @override
  Future<List<Recipe>> trendingRecipes(
    String chefId, {
    int limit = 20,
    int offset = 0,
  }) async {
    calls.add(('trending', chefId, limit, offset));
    return offset == 0 ? [_recipe('trend', 'Hot This Week')] : const [];
  }

  @override
  Future<Map<ChefTier, int>> tierCounts() => throw UnimplementedError();
}

/// Phase 35b: `/chef/:id` now also reads the chef's entity affiliations, so the
/// page needs this override or the provider reaches for the real Supabase
/// client. Empty by default — most profiles belong to no entity, and the
/// affiliation row is absent rather than empty when they do not.
class _FakeEntityRepository implements EntityRepository {
  _FakeEntityRepository({this.entities = const []});

  final List<Entity> entities;

  @override
  Future<List<Entity>> forProfile(String profileId) async => entities;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
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
  _FakeChefRepository? chefs,
  double textScale = 1.0,
  String chefId = 'ssk',

  /// Phase 35b: the groups this chef is listed under. Empty for every existing
  /// case, which is the normal state — most profiles never join one.
  List<Entity> entities = const [],
}) {
  return ProviderScope(
    overrides: [
      entityRepositoryProvider.overrideWithValue(
        _FakeEntityRepository(entities: entities),
      ),
      chefRepositoryProvider.overrideWithValue(
        chefs ?? _FakeChefRepository(result: standing, fail: standingFails),
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

  // Phase 31. All three tabs show the same recipes in three orders, so nothing
  // on screen distinguishes them — the assertion has to be which read was made.
  group('the sort tabs', () {
    testWidgets('default to All, which is the plain table read', (
      tester,
    ) async {
      _size(tester, 1000);
      final chefs = _FakeChefRepository();
      final recipes = _FakeRecipeRepository(
        pages: [
          [_recipe('r1', 'Newest Thing')],
        ],
      );
      await tester.pumpWidget(_app(chefs: chefs, recipes: recipes));
      await tester.pumpAndSettle();

      expect(find.text('All'), findsOneWidget);
      expect(find.text('Popular'), findsOneWidget);
      expect(find.text('Trending'), findsOneWidget);

      // `all` costs no RPC: PostgREST can order by `created_at` on its own.
      expect(recipes.calls.single, ('ssk', kRecipePageSize, 0));
      expect(chefs.calls, isEmpty);
    });

    testWidgets('send Popular and Trending to their own RPCs', (tester) async {
      _size(tester, 1000);
      final chefs = _FakeChefRepository();
      await tester.pumpWidget(_app(chefs: chefs));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Popular'));
      await tester.pumpAndSettle();
      expect(chefs.calls.last, ('top', 'ssk', kRecipePageSize, 0));
      expect(find.text('Most Liked Thing'), findsOneWidget);

      await tester.tap(find.text('Trending'));
      await tester.pumpAndSettle();
      expect(chefs.calls.last, ('trending', 'ssk', kRecipePageSize, 0));
      expect(find.text('Hot This Week'), findsOneWidget);
      // The previous tab's rows are gone, not appended: a sort is a new list.
      expect(find.text('Most Liked Thing'), findsNothing);
    });

    testWidgets('restart paging at offset 0 when the sort changes', (
      tester,
    ) async {
      // Gotcha 24 one level in: carrying an offset across a re-sort pages one
      // ordering's window against another ordering's rows, which shows a recipe
      // twice and hides another with no error anywhere.
      _size(tester, 1000);
      final chefs = _FakeChefRepository();
      final recipes = _FakeRecipeRepository(
        pages: [
          [for (var i = 0; i < kRecipePageSize; i++) _recipe('r$i', 'R$i')],
          [_recipe('last', 'Last One')],
        ],
      );
      await tester.pumpWidget(_app(chefs: chefs, recipes: recipes));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('Load more'), 600);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Load more'));
      await tester.pumpAndSettle();
      expect(recipes.calls.last, ('ssk', kRecipePageSize, kRecipePageSize));

      await tester.scrollUntilVisible(find.text('Popular'), -600);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Popular'));
      await tester.pumpAndSettle();

      expect(chefs.calls.single, ('top', 'ssk', kRecipePageSize, 0));
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

  // Phase 35b. A chef page for somebody who never signed up. The distinction
  // that matters is not "unranked" — a brand-new member is unranked too — it is
  // that there is no account behind this page at all, and the two states have
  // to say different things.
  group('an unclaimed chef', () {
    Profile imported({String name = 'Aurelie Fontaine'}) => Profile(
      id: 'ssk',
      displayName: name,
      kind: ProfileKind.imported,
      createdAt: DateTime(2025, 3, 14),
      publicRecipeCount: 4,
    );

    testWidgets('says the page is a credit, not an account', (tester) async {
      _size(tester, 1000);
      await tester.pumpWidget(
        _app(standing: null, profile: imported(), pages: const [[]]),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('This page is a credit, not an account'),
        findsOneWidget,
      );
      expect(
        find.textContaining('has not signed up for Secret-Sauce'),
        findsOneWidget,
      );
    });

    testWidgets('does not show the brand-new-member note instead', (
      tester,
    ) async {
      // The two notes occupy the same slot, so the wrong branch is a silent
      // substitution rather than a missing widget.
      _size(tester, 1000);
      await tester.pumpWidget(
        _app(standing: null, profile: imported(), pages: const [[]]),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('has no public recipes yet'),
        findsNothing,
        reason: 'an imported chef got the unranked-member copy',
      );
    });

    testWidgets('offers the claim button, disabled', (tester) async {
      // Claiming is a security definer RPC with EXECUTE revoked from every API
      // role, so there is nothing for this button to call. Enabled, it would
      // silently do nothing — which is worse than no button at all.
      _size(tester, 1000);
      await tester.pumpWidget(
        _app(standing: null, profile: imported(), pages: const [[]]),
      );
      await tester.pumpAndSettle();

      final button = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('Is this you?'),
          matching: find.byType(FilledButton),
        ),
      );
      expect(button.onPressed, isNull);
      expect(find.byType(Tooltip), findsWidgets);
    });

    testWidgets('a ranked member never gets the unclaimed note', (
      tester,
    ) async {
      _size(tester, 1000);
      await tester.pumpWidget(_app(pages: const [[]]));
      await tester.pumpAndSettle();

      expect(find.text('This page is a credit, not an account'), findsNothing);
    });
  });

  group('entity affiliations (Phase 35b)', () {
    const bakery = Entity(
      id: 'e1',
      slug: 'northern-bakehouse',
      name: 'Northern Bakehouse',
      kind: EntityKind.brand,
    );

    testWidgets('are absent when the chef belongs to none', (tester) async {
      // Absent, not an empty state: most profiles never join one, and
      // "No affiliations" is a sentence nobody needs.
      _size(tester, 1000, 2000);
      await tester.pumpWidget(_app(pages: const [[]]));
      await tester.pumpAndSettle();

      expect(find.text('Appears in'), findsNothing);
    });

    testWidgets('render as chips when they exist', (tester) async {
      // Tall: the chips sit below the score panel, and a finder for something
      // below the fold of a CustomScrollView fails for a reason that has
      // nothing to do with what is being tested.
      _size(tester, 1000, 2000);
      await tester.pumpWidget(
        _app(pages: const [[]], entities: const [bakery]),
      );
      await tester.pumpAndSettle();

      expect(find.text('Appears in'), findsOneWidget);
      expect(find.text('Northern Bakehouse'), findsOneWidget);
    });
  });
}
