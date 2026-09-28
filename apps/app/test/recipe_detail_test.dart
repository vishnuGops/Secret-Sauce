import 'dart:async';

// Recipe-detail interactions — the suite OPT-T3 asks for, opened by B051.
//
// The like/save buttons used to call `setLiked(liked: true)` unconditionally.
// Signed out that reached `_uid`, which throws `StateError` inside an unawaited
// closure: no feedback, unhandled error (Gotcha 9). Signed in it was one-way —
// nothing read whether the user had already liked, so the heart never filled
// and there was no unlike, even though `setLiked(liked: false)` existed.
//
// These overrides swap `recipeRepositoryProvider` / `authRepositoryProvider`
// (core) rather than the screen's own providers, so the wiring in
// recipe_detail_providers.dart is exercised instead of stubbed out.
//
// This suite pumps the **compact/medium** layout — it used to mean "the v1 hero"
// and now means `recipe_detail_compact.dart`, since the v1 layout was deleted
// when compact v2 landed. Every engagement test below survived that swap
// untouched, which is the point of testing behaviour rather than widget trees:
// they assert what reached the repository, not what the page looked like. The
// layout's own assertions are in the two groups at the bottom.
import 'package:app/features/my_recipes/my_recipes_providers.dart';
import 'package:app/features/recipe_detail/detail_provenance.dart';
import 'package:app/features/recipe_detail/fork_action.dart';
import 'package:app/features/recipe_detail/rail_panel.dart';
import 'package:app/features/recipe_detail/recipe_detail_providers.dart';
import 'package:app/features/recipe_detail/recipe_detail_screen.dart';
import 'package:app/routing/app_router.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const _recipe = Recipe(
  id: 'r1',
  ownerId: 'someone-else',
  title: 'Suya-Spiced Lamb Skewers',
  likeCount: 12,
  saveCount: 3,
);

/// A recipe with the shape the compact layout has furniture for: two step
/// groups, ingredients, an attribution, a private visibility badge.
const _fullRecipe = Recipe(
  id: 'r1',
  ownerId: 'someone-else',
  title: 'Spring Vegetable Tart',
  description: 'A flaky all-butter crust.',
  attribution: 'Written down from Rosa’s kitchen in 1987.',
  prepMinutes: 30,
  cookMinutes: 55,
  servings: 8,
  visibility: RecipeVisibility.private,
  ingredientGroups: [
    IngredientGroup(
      id: 'ig1',
      recipeId: 'r1',
      name: 'Crust',
      ingredients: [
        Ingredient(
          id: 'i1',
          groupId: 'ig1',
          quantity: 1.25,
          unit: 'cup',
          name: 'wheat flour',
        ),
      ],
    ),
  ],
  stepGroups: [
    StepGroup(
      id: 'sg1',
      recipeId: 'r1',
      name: 'Crust',
      steps: [
        RecipeStep(id: 's1', groupId: 'sg1', text: 'Mix the flour and salt.'),
        RecipeStep(
          id: 's2',
          groupId: 'sg1',
          text: 'Chill the dough.',
          durationMinutes: 60,
        ),
      ],
    ),
    StepGroup(
      id: 'sg2',
      recipeId: 'r1',
      name: 'Bake',
      steps: [RecipeStep(id: 's3', groupId: 'sg2', text: 'Bake until golden.')],
    ),
  ],
);

/// [_fullRecipe] with its owner embedded — what `kRecipeSelect`'s FK-hinted
/// `owner:profiles!recipes_owner_id_fkey(...)` actually delivers. Every list
/// query carries it, so the detail header can name the chef without a lookup.
final _ownedRecipe = _fullRecipe.copyWith(
  ownerId: 'd1',
  owner: const Profile(
    id: 'd1',
    displayName: 'Amara Baptiste',
    chefTier: ChefTier.masterChef,
  ),
);

/// [_fullRecipe] with a nutrition label. 8 servings × 320 kcal, so the batch
/// line is a four-figure number and the grouping is exercised too. Tagged
/// (36c) so the envelope below pumps the tag row and the category cover too.
final _labelledRecipe = _fullRecipe.copyWith(
  cuisine: 'Pan-Mediterranean Coastal',
  category: 'Appetizer',
  nutrition: const RecipeNutrition(
    calories: 320,
    totalFatG: 12,
    saturatedFatG: 5,
    sodiumMg: 480,
    totalCarbsG: 30,
    proteinG: 9,
  ),
);

/// The phone the compact tests pump: 390 wide, the width the layout was drawn
/// for. 1200 tall rather than a real 844 since Phase 36c — an intended
/// contract change. The identity is now reference 5's sheet over a full cover
/// (210px, where a photo-less recipe used to get a 96px strip), so under
/// `flutter test`'s wide fixed-pitch font the jump bar, and the rail and
/// method behind it, start below an 844px viewport and are never built. With
/// the real font the jump bar still makes the first screen; the envelope
/// group below is what proves nothing overflows at any height.
const _phone = Size(390, 1200);

class _FakeAuth implements AuthRepository {
  _FakeAuth(this.uid, {this.profileId, this.profileFails = false});

  /// The `current_profile_id` RPC fails (a network blip on its first call).
  final bool profileFails;

  final String? uid;

  /// Set for a member who has **claimed** an imported chef page (Phase 35b):
  /// the one account whose `profiles.id` is not its auth uid (B128).
  final String? profileId;

  @override
  String? get currentUserId => uid;

  // Phase 35b: `profiles.id` and the auth uid are the same value for a member,
  // which every fixture in this file is.
  @override
  Future<String?> currentProfileId() async {
    if (profileFails) throw Exception('network');
    return profileId ?? uid;
  }

  @override
  Stream<AuthState> authStateChanges() => const Stream.empty();

  @override
  Future<void> signIn({
    required String email,
    required String password,
  }) async {}

  @override
  Future<SignUpOutcome> signUp({
    required String email,
    required String password,
    required String displayName,
  }) async => SignUpOutcome.signedIn;

  @override
  Future<void> signOut() async {}
}

/// Records every engagement write so a test can assert the *value* sent, which
/// is the half B051 got wrong — it always sent `true`.
class _FakeRecipeRepository implements RecipeRepository {
  _FakeRecipeRepository({
    this.liked = false,
    this.saved = false,
    this.recipe = _recipe,
  });

  bool liked;
  bool saved;
  final Recipe recipe;

  final List<bool> likeWrites = [];
  final List<bool> saveWrites = [];
  int viewLogs = 0;

  /// Every recipe id `fork()` was asked to copy. It used to throw
  /// `UnimplementedError`, which is why the fork flow had never been driven from
  /// a test at all (B084).
  final List<String> forkedFrom = [];

  /// Make the next fork fail, to drive the snackbar path.
  bool forkFails = false;

  /// When set, `setSaved()` waits on it — the reader can leave mid-write.
  Completer<void>? saveGate;

  /// When set, `fork()` waits on it — holds the RPC in flight so a second tap
  /// lands while the first is outstanding (B129).
  Completer<String>? forkGate;

  /// The rating half (32e2). Both detail layouts mount `RatingSection` and only
  /// cook mode's twin was ever driven, so the reading page's write, its clear,
  /// and its failure path had no coverage at all.
  double? rating;
  final List<double> ratingWrites = [];
  int ratingClears = 0;
  bool ratingFails = false;

  /// What the version sheet is handed. Empty by default — every suite fake
  /// returned `const []` until 32e3, so the sheet had never rendered a row.
  List<RecipeVersion> versionRows = const [];

  /// Card-level rows `findSummary` answers with, by id — a fork's parent
  /// (UX-036). An id missing here is a parent RLS hides: null, not an error.
  Map<String, Recipe> summaries = const {};
  final List<String> summaryReads = [];

  /// What opening a version returns, by version id (UX-052). Missing is the
  /// seeded `{}` snapshot: null.
  Map<String, Recipe> versionContents = const {};

  /// Every id `getById` was asked for — a fork's parent link opens its id.
  final List<String> gets = [];

  /// When set, `getById` waits on it — the page sits in its loading state.
  Completer<Recipe>? getGate;

  @override
  Future<Recipe> getById(String id) async {
    gets.add(id);
    if (getGate != null) return getGate!.future;
    return recipe;
  }

  @override
  Future<Recipe?> findSummary(String id) async {
    summaryReads.add(id);
    return summaries[id];
  }

  @override
  Future<Recipe?> versionContent(String versionId) async =>
      versionContents[versionId];

  @override
  Future<bool> myLiked(String recipeId) async => liked;

  @override
  Future<bool> mySaved(String recipeId) async => saved;

  @override
  Future<void> setLiked(String recipeId, {required bool liked}) async {
    likeWrites.add(liked);
    this.liked = liked;
  }

  @override
  Future<void> setSaved(String recipeId, {required bool saved}) async {
    if (saveGate != null) await saveGate!.future;
    saveWrites.add(saved);
    this.saved = saved;
  }

  @override
  Future<void> logView(String recipeId) async => viewLogs++;

  @override
  Future<double?> myRating(String recipeId) async => rating;

  @override
  Future<List<RecipeVersion>> versions(String recipeId) async => versionRows;

  // Unused on this screen's read path.
  @override
  Future<Recipe> create(Recipe recipe) => throw UnimplementedError();

  @override
  Future<Recipe> update(Recipe recipe, {String changeSummary = 'Updated'}) =>
      throw UnimplementedError();

  @override
  Future<void> delete(String id) => throw UnimplementedError();

  @override
  Future<String> fork(String sourceRecipeId) async {
    forkedFrom.add(sourceRecipeId);
    if (forkFails) throw Exception('nope');
    if (forkGate != null) return forkGate!.future;
    return 'r2';
  }

  @override
  Future<List<Recipe>> listMine({
    int limit = kRecipePageSize,
    int offset = 0,
  }) => throw UnimplementedError();

  /// How many times the Saved tab's list was read — the save toggle must
  /// refresh it (UX-020).
  int savedReads = 0;

  @override
  Future<List<Recipe>> listSaved({
    int limit = kRecipePageSize,
    int offset = 0,
  }) async {
    savedReads++;
    return const [];
  }

  @override
  Future<List<Recipe>> listSharedWithMe({
    int limit = kRecipePageSize,
    int offset = 0,
  }) => throw UnimplementedError();

  @override
  Future<List<Recipe>> listByChef(
    String chefId, {
    int limit = kRecipePageSize,
    int offset = 0,
  }) => throw UnimplementedError();

  @override
  Future<void> share({
    required String recipeId,
    required String userId,
    SharePermission permission = SharePermission.view,
  }) => throw UnimplementedError();

  @override
  Future<void> unshare({required String recipeId, required String userId}) =>
      throw UnimplementedError();

  @override
  Future<void> setRating(String recipeId, double value) async {
    if (ratingFails) throw Exception('nope');
    ratingWrites.add(value);
    rating = value;
  }

  @override
  Future<void> clearRating(String recipeId) async {
    ratingClears++;
    rating = null;
  }
}

/// Pumps the detail screen behind a real router, so `context.go(Routes.auth)`
/// actually resolves instead of being asserted on a mock.
Future<GoRouter> _pump(
  WidgetTester tester, {
  required _FakeRecipeRepository repo,
  required String? uid,
  String? profileId,
  bool profileFails = false,
  Size? size,
  double textScale = 1,
  RailTab? railTab,
  bool settle = true,
}) async {
  if (size != null) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  final router = GoRouter(
    initialLocation: '/recipe/r1',
    routes: [
      GoRoute(
        path: Routes.discover,
        builder: (_, __) => const Scaffold(body: Text('DISCOVER')),
      ),
      GoRoute(
        path: '/recipe/:id',
        builder:
            (_, state) =>
                RecipeDetailScreen(recipeId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: Routes.cookRecipePattern,
        builder: (_, __) => const Scaffold(body: Text('COOK MODE')),
      ),
      GoRoute(
        path: Routes.auth,
        builder: (_, __) => const Scaffold(body: Text('AUTH SCREEN')),
      ),
      GoRoute(
        path: Routes.editRecipePattern,
        builder:
            (_, state) =>
                Scaffold(body: Text('EDITOR ${state.pathParameters['id']}')),
      ),
      GoRoute(
        path: Routes.chefPattern,
        builder:
            (_, state) =>
                Scaffold(body: Text('CHEF ${state.pathParameters['id']}')),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        recipeRepositoryProvider.overrideWithValue(repo),
        authRepositoryProvider.overrideWithValue(
          _FakeAuth(uid, profileId: profileId, profileFails: profileFails),
        ),
        // Lets the envelope matrix run per TAB without depending on the chip
        // being scrolled into view first — at 2.0× on a 390px page it is not.
        if (railTab != null)
          railTabProvider(repo.recipe.id).overrideWith((ref) => railTab),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        builder:
            (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
  return router;
}

void main() {
  testWidgets('signed out, tapping like goes to /auth and writes nothing', (
    tester,
  ) async {
    final repo = _FakeRecipeRepository();
    final router = await _pump(tester, repo: repo, uid: null);

    await tester.tap(find.byIcon(Icons.favorite_border));
    await tester.pumpAndSettle();

    expect(find.text('AUTH SCREEN'), findsOneWidget);
    // UX-017: the recipe rides along, so signing in lands back here.
    expect(
      router.routerDelegate.currentConfiguration.uri.queryParameters['from'],
      '/recipe/r1',
    );
    expect(
      repo.likeWrites,
      isEmpty,
      reason: 'a signed-out tap must not reach the repository',
    );
  });

  testWidgets('signed out, tapping save goes to /auth and writes nothing', (
    tester,
  ) async {
    final repo = _FakeRecipeRepository();
    await _pump(tester, repo: repo, uid: null);

    await tester.tap(find.byIcon(Icons.bookmark_border));
    await tester.pumpAndSettle();

    expect(find.text('AUTH SCREEN'), findsOneWidget);
    expect(repo.saveWrites, isEmpty);
  });

  testWidgets('signed in and not yet liked: tap sends liked: true', (
    tester,
  ) async {
    final repo = _FakeRecipeRepository();
    await _pump(tester, repo: repo, uid: 'me');

    expect(find.byIcon(Icons.favorite_border), findsOneWidget);
    await tester.tap(find.byIcon(Icons.favorite_border));
    await tester.pumpAndSettle();

    expect(repo.likeWrites, [true]);
  });

  testWidgets('already liked: the icon is filled and the tap UNLIKES (B051)', (
    tester,
  ) async {
    final repo = _FakeRecipeRepository(liked: true);
    await _pump(tester, repo: repo, uid: 'me');

    // The filled variant is what `activeIcon` was for — it was dead until now.
    expect(find.byIcon(Icons.favorite), findsOneWidget);
    expect(find.byIcon(Icons.favorite_border), findsNothing);

    await tester.tap(find.byIcon(Icons.favorite));
    await tester.pumpAndSettle();

    expect(repo.likeWrites, [
      false,
    ], reason: 'the action must be a toggle, not a one-way like');
    expect(find.byIcon(Icons.favorite_border), findsOneWidget);
  });

  // UX-020: the Saved tab lives in the shell under this pushed page, so its
  // provider stays alive while the reader unsaves; the toggle must refresh it.
  testWidgets('a save toggle refreshes the Saved tab behind the page', (
    tester,
  ) async {
    final repo = _FakeRecipeRepository(saved: true);
    await _pump(tester, repo: repo, uid: 'me');
    final container = ProviderScope.containerOf(
      tester.element(find.byType(RecipeDetailScreen)),
    );
    final keepAlive = container.listen(savedRecipesProvider, (_, __) {});
    addTearDown(keepAlive.close);
    await tester.pumpAndSettle();
    expect(repo.savedReads, 1);

    await tester.tap(find.byIcon(Icons.bookmark));
    await tester.pumpAndSettle();

    expect(repo.savedReads, 2);
  });

  // Phase 37 review: the refresh ran through the button's `ref`, which throws
  // once the reader has left — silently, inside the catch.
  testWidgets('the Saved tab refreshes even if the reader leaves mid-write', (
    tester,
  ) async {
    final repo = _FakeRecipeRepository(saved: true)..saveGate = Completer();
    final router = await _pump(tester, repo: repo, uid: 'me');
    final container = ProviderScope.containerOf(
      tester.element(find.byType(RecipeDetailScreen)),
    );
    final keepAlive = container.listen(savedRecipesProvider, (_, __) {});
    addTearDown(keepAlive.close);
    await tester.pumpAndSettle();
    expect(repo.savedReads, 1);

    await tester.tap(find.byIcon(Icons.bookmark));
    await tester.pump();
    router.go(Routes.auth);
    await tester.pumpAndSettle();
    repo.saveGate!.complete();
    await tester.pumpAndSettle();

    expect(repo.savedReads, 2);
  });

  testWidgets('already saved: the icon is filled and the tap UNSAVES', (
    tester,
  ) async {
    final repo = _FakeRecipeRepository(saved: true);
    await _pump(tester, repo: repo, uid: 'me');

    expect(find.byIcon(Icons.bookmark), findsOneWidget);
    await tester.tap(find.byIcon(Icons.bookmark));
    await tester.pumpAndSettle();

    expect(repo.saveWrites, [false]);
    expect(find.byIcon(Icons.bookmark_border), findsOneWidget);
  });

  // OPT-P7. logView used to live inside recipeProvider, which the screen
  // invalidates on every like/save/rating — so one visit with a couple of
  // interactions appended three or four rows to the append-only recipe_views
  // log. It now sits in its own autoDispose provider: one row per visit.
  group('view logging (OPT-P7)', () {
    testWidgets('logs exactly one view for a plain visit', (tester) async {
      final repo = _FakeRecipeRepository();
      await _pump(tester, repo: repo, uid: 'me');
      expect(repo.viewLogs, 1);
    });

    testWidgets('engagement does not re-log the view', (tester) async {
      final repo = _FakeRecipeRepository();
      await _pump(tester, repo: repo, uid: 'me');
      expect(repo.viewLogs, 1);

      await tester.tap(find.byIcon(Icons.favorite_border));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.bookmark_border));
      await tester.pumpAndSettle();
      // Both taps invalidate recipeProvider; neither may touch the view log.
      await tester.tap(find.byIcon(Icons.favorite));
      await tester.pumpAndSettle();

      expect(
        repo.viewLogs,
        1,
        reason:
            'three engagement writes re-resolved the recipe; only the '
            'original visit may count as a view',
      );
    });

    testWidgets('logs a view when signed out too', (tester) async {
      // `logView` uses currentUser?.id, so an anonymous row is valid (B012) —
      // it just never moves view_count.
      final repo = _FakeRecipeRepository();
      await _pump(tester, repo: repo, uid: null);
      expect(repo.viewLogs, 1);
    });
  });

  // The compact v2 layout (canvas frame B + frame F's owner state), which
  // replaced the v1 hero below 1000px.
  group('compact v2 (frame B)', () {
    testWidgets('renders the v2 furniture and none of v1’s', (tester) async {
      final repo = _FakeRecipeRepository(recipe: _fullRecipe);
      await _pump(tester, repo: repo, uid: null, size: _phone);

      // Facts quad: the four that fit, not the six the wide strip carries.
      expect(find.text('TOTAL'), findsOneWidget);
      expect(find.text('HANDS ON'), findsOneWidget);
      expect(find.text('LONGEST WAIT'), findsOneWidget);
      expect(find.text('DIFFICULTY'), findsOneWidget);
      expect(find.text('COOK'), findsNothing);
      expect(find.text('VISIBILITY'), findsNothing);
      // Private, so the tag row carries a Private pill (on the cover until
      // 36c, where the colour block now sets its category label).
      expect(find.text('Private'), findsOneWidget);

      // Jump bar (and the rail's tab chip), then the two panels' headings —
      // kickers since 36c — and the sticky cook bar.
      expect(find.text('Ingredients'), findsWidgets);
      expect(find.text('Method'), findsWidgets);
      expect(find.text('INGREDIENTS'), findsOneWidget);
      expect(find.text('METHOD'), findsOneWidget);
      expect(find.text('Ready to cook?'), findsOneWidget);
      expect(find.text('3 steps · 1 h 25 min'), findsOneWidget); // UX-043
      // The attribution box (frame F).
      expect(find.textContaining('Rosa’s kitchen'), findsOneWidget);

      // v1 is gone: no collapsing hero, no "Instructions" heading.
      expect(find.byType(SliverAppBar), findsNothing);
      expect(find.text('Instructions'), findsNothing);
    });

    testWidgets('the sticky bar starts cooking', (tester) async {
      final repo = _FakeRecipeRepository(recipe: _fullRecipe);
      await _pump(tester, repo: repo, uid: null, size: _phone);

      // Two entry points on this page — the method column's teaser inside the
      // scroll, and the pinned bar after it. `.last` is the bar.
      expect(find.text('Start cooking'), findsNWidgets(2));
      await tester.tap(find.text('Start cooking').last);
      await tester.pumpAndSettle();
      expect(find.text('COOK MODE'), findsOneWidget);
    });

    testWidgets('the ingredients rail shares the reading page’s gutter', (
      tester,
    ) async {
      final repo = _FakeRecipeRepository(recipe: _fullRecipe);
      await _pump(tester, repo: repo, uid: null, size: _phone);

      // Same widget as the expanded page's left column — scaled quantity in the
      // gutter, sentence-cased name, check-off counter.
      expect(find.text('1¼ cups'), findsOneWidget); // UX-023
      expect(find.text('Wheat flour'), findsOneWidget);
      expect(find.text('0 of 1 gathered'), findsOneWidget);
      // And it is a panel here too. It was bare on compact (`bordered: false`)
      // until Phase 36c: the owner's Q4 made ingredients and method two open,
      // rounded panels on the phone as well — an intended contract change,
      // not a regression. The flag moved from `IngredientRail` to `RailPanel`
      // in Phase 28, when the container went up to the tab host.
      expect(tester.widget<RailPanel>(find.byType(RailPanel)).bordered, isTrue);
    });

    testWidgets('the owner gets edit and share, and no fork chip', (
      tester,
    ) async {
      final repo = _FakeRecipeRepository(recipe: _fullRecipe);
      await _pump(tester, repo: repo, uid: 'someone-else', size: _phone);

      expect(find.byIcon(Icons.edit), findsOneWidget);
      expect(find.byIcon(Icons.share), findsOneWidget);
      // You cannot fork your own recipe, so the chip is absent.
      expect(find.widgetWithText(ActionChip, 'Fork'), findsNothing);
    });

    testWidgets('a non-owner gets the fork chip and no editing', (
      tester,
    ) async {
      final repo = _FakeRecipeRepository(recipe: _fullRecipe);
      await _pump(tester, repo: repo, uid: 'me', size: _phone);

      expect(find.widgetWithText(ActionChip, 'Fork'), findsOneWidget);
      expect(find.byIcon(Icons.edit), findsNothing);
      expect(find.byIcon(Icons.share), findsNothing);
    });
  });

  // 32c1 / B084. The chip fired the RPC while signed out and rendered whatever
  // Postgres said back; cook mode's finish screen had the guard. Both call sites
  // are `forkRecipe` now, and this is the reading page's half — the finish
  // screen's is in `cook_mode_test.dart`.
  group('fork (compact)', () {
    // The jump bar scrolls horizontally (a pinned sliver cannot wrap), so at
    // 390px the Fork chip sits off the right edge: `ensureVisible` first, or the
    // tap lands on nothing and the assertion below blames the handler.
    Future<void> tapFork(WidgetTester tester) async {
      final fork = find.widgetWithText(ActionChip, 'Fork');
      await tester.ensureVisible(fork);
      await tester.pumpAndSettle();
      await tester.tap(fork);
      await tester.pumpAndSettle();
    }

    testWidgets('signed out, the chip goes to /auth and writes nothing', (
      tester,
    ) async {
      final repo = _FakeRecipeRepository(recipe: _fullRecipe);
      await _pump(tester, repo: repo, uid: null, size: _phone);

      await tapFork(tester);

      expect(find.text('AUTH SCREEN'), findsOneWidget);
      expect(
        repo.forkedFrom,
        isEmpty,
        reason: 'a signed-out fork must not reach the RPC',
      );
    });

    testWidgets('signed in, it copies the recipe and opens the editor', (
      tester,
    ) async {
      final repo = _FakeRecipeRepository(recipe: _fullRecipe);
      await _pump(tester, repo: repo, uid: 'me', size: _phone);

      await tapFork(tester);

      expect(repo.forkedFrom, ['r1']);
      // The copy, not the original — a fork exists to be changed.
      expect(find.text('EDITOR r2'), findsOneWidget);
    });

    // B129 / UX-026: a double tap made two forks. The second tap lands while
    // the first RPC is still outstanding, which the gate holds open.
    testWidgets('a second tap while forking is ignored, and the chip is off', (
      tester,
    ) async {
      final repo = _FakeRecipeRepository(recipe: _fullRecipe)
        ..forkGate = Completer<String>();
      await _pump(tester, repo: repo, uid: 'me', size: _phone);

      final fork = find.widgetWithText(ActionChip, 'Fork');
      await tester.ensureVisible(fork);
      await tester.pumpAndSettle();
      await tester.tap(fork);
      await tester.pump();
      await tester.tap(fork, warnIfMissed: false);
      await tester.pump();

      expect(repo.forkedFrom, ['r1'], reason: 'one fork per gesture');
      expect(tester.widget<ActionChip>(fork).onPressed, isNull);

      repo.forkGate!.complete('r2');
      await tester.pumpAndSettle();
      expect(find.text('EDITOR r2'), findsOneWidget);
    });

    // The chip's disabled state is the affordance; the flag inside
    // `forkRecipe` is the guard, and it has to hold for a caller that renders
    // no disabled state at all (cook mode's finish screen). Two calls in one
    // frame, with no button in between.
    testWidgets('forkRecipe itself refuses a second call in flight', (
      tester,
    ) async {
      final repo = _FakeRecipeRepository(recipe: _fullRecipe)
        ..forkGate = Completer<String>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            recipeRepositoryProvider.overrideWithValue(repo),
            authRepositoryProvider.overrideWithValue(_FakeAuth('me')),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder:
                    (context, ref, _) => TextButton(
                      onPressed: () {
                        unawaited(forkRecipe(context, ref, 'r1'));
                        unawaited(forkRecipe(context, ref, 'r1'));
                      },
                      child: const Text('FORK TWICE'),
                    ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('FORK TWICE'));
      await tester.pump();

      expect(repo.forkedFrom, ['r1']);
    });

    testWidgets('a failed fork says so and stays on the recipe', (
      tester,
    ) async {
      final repo = _FakeRecipeRepository(recipe: _fullRecipe);
      repo.forkFails = true;
      await _pump(tester, repo: repo, uid: 'me', size: _phone);

      await tapFork(tester);

      expect(find.textContaining('Could not fork'), findsOneWidget);
      expect(find.text('EDITOR r2'), findsNothing);
    });
  });

  // 32e2. `RatingSection` is mounted by both detail layouts and was driven by
  // neither: the only rating test in the suite was cook mode's finish screen.
  // These go through the shared handler (32c5), so they cover the write path
  // both surfaces now share — what reaches the repository, and what the block
  // does afterwards.
  // B128 / UX-019. `isOwner` compared the auth uid with `ownerId`, which is a
  // `profiles.id`. The two agree for every member except one who has claimed
  // an imported chef page — exactly the account these fixtures model.
  // UX-051: the browser tab names the recipe once it has loaded.
  testWidgets('the tab title is the recipe', (tester) async {
    await _pump(tester, repo: _FakeRecipeRepository(), uid: null);

    final titles = tester
        .widgetList<Title>(find.byType(Title))
        .map((t) => t.title);
    expect(titles, contains('Suya-Spiced Lamb Skewers · Secret Sauce'));
  });

  group('ownership is the profile id (B128)', () {
    testWidgets('a claimed member owns the claimed profile’s recipe', (
      tester,
    ) async {
      final repo = _FakeRecipeRepository(recipe: _fullRecipe);
      await _pump(
        tester,
        repo: repo,
        uid: 'auth-uid',
        profileId: 'someone-else',
        size: _phone,
      );

      expect(find.byTooltip('Edit'), findsOneWidget);
      expect(find.widgetWithText(ActionChip, 'Fork'), findsNothing);
    });

    // Phase 37 review: one failed lookup used to hide the owner's controls on
    // every recipe until the next auth event.
    testWidgets('a failed profile lookup falls back to the auth uid', (
      tester,
    ) async {
      final repo = _FakeRecipeRepository(recipe: _fullRecipe);
      await _pump(
        tester,
        repo: repo,
        uid: 'someone-else',
        profileFails: true,
        size: _phone,
      );

      expect(find.byTooltip('Edit'), findsOneWidget);
    });

    testWidgets('an auth uid equal to ownerId is not ownership', (
      tester,
    ) async {
      final repo = _FakeRecipeRepository(recipe: _fullRecipe);
      await _pump(
        tester,
        repo: repo,
        uid: 'someone-else',
        profileId: 'claimed-profile',
        size: _phone,
      );

      expect(find.byTooltip('Edit'), findsNothing);
      expect(find.widgetWithText(ActionChip, 'Fork'), findsOneWidget);
    });
  });

  group('rating (compact)', () {
    Future<void> rate(WidgetTester tester) async {
      final stars = find.byType(StarRatingInput);
      await tester.ensureVisible(stars);
      await tester.pumpAndSettle();
      await tester.tap(stars);
      await tester.pumpAndSettle();
    }

    // UX-055: the block sat at the foot of the page with no prompt, so
    // "No ratings yet" over a row of stars did not say they were for you.
    testWidgets('the block says what it is for, and whose it is', (
      tester,
    ) async {
      final repo = _FakeRecipeRepository(recipe: _fullRecipe);
      await _pump(tester, repo: repo, uid: 'me', size: _phone);

      final heading = find.text('Rate this recipe');
      await tester.ensureVisible(heading);
      expect(heading, findsOneWidget);
      expect(find.text('Made it? Tap a star.'), findsOneWidget);
      expect(
        tester.getSemantics(heading),
        matchesSemantics(label: 'Rate this recipe', isHeader: true),
      );
    });

    testWidgets('the owner sees Ratings, not a prompt to rate', (tester) async {
      final repo = _FakeRecipeRepository(recipe: _ownedRecipe);
      await _pump(tester, repo: repo, uid: 'd1', size: _phone);

      await tester.ensureVisible(find.text('Ratings'));
      expect(find.text('Rate this recipe'), findsNothing);
      expect(find.text('Made it? Tap a star.'), findsNothing);
    });

    testWidgets('signed in, a tap writes and the block catches up', (
      tester,
    ) async {
      final repo = _FakeRecipeRepository(recipe: _fullRecipe);
      await _pump(tester, repo: repo, uid: 'me', size: _phone);

      await rate(tester);

      expect(repo.ratingWrites, hasLength(1));
      expect(repo.ratingWrites.single, inInclusiveRange(0.5, 5.0));
      expect(find.textContaining('Rated'), findsOneWidget);
      // The Remove button only appears once `myRatingProvider` has re-resolved,
      // so its presence *is* the invalidation assertion.
      expect(find.text('Remove'), findsOneWidget);
    });

    testWidgets('Remove clears the rating', (tester) async {
      final repo = _FakeRecipeRepository(recipe: _fullRecipe)..rating = 4;
      await _pump(tester, repo: repo, uid: 'me', size: _phone);

      final remove = find.text('Remove');
      await tester.ensureVisible(remove);
      await tester.pumpAndSettle();
      await tester.tap(remove);
      await tester.pumpAndSettle();

      expect(repo.ratingClears, 1);
      // Clearing is silent on success — the stars emptying is the feedback —
      // and the button leaves with the rating it removed.
      expect(find.text('Remove'), findsNothing);
      expect(find.textContaining('Could not'), findsNothing);
    });

    testWidgets('a refused rating says so and writes nothing', (tester) async {
      final repo = _FakeRecipeRepository(recipe: _fullRecipe)
        ..ratingFails = true;
      await _pump(tester, repo: repo, uid: 'me', size: _phone);

      await rate(tester);

      expect(repo.ratingWrites, isEmpty);
      expect(find.textContaining('Could not save rating'), findsOneWidget);
    });

    testWidgets('signed out, there is no star input, only the way in', (
      tester,
    ) async {
      final repo = _FakeRecipeRepository(recipe: _fullRecipe);
      await _pump(tester, repo: repo, uid: null, size: _phone);

      expect(find.byType(StarRatingInput), findsNothing);
      final signIn = find.text('Sign in');
      await tester.ensureVisible(signIn);
      await tester.pumpAndSettle();
      await tester.tap(signIn);
      await tester.pumpAndSettle();

      expect(find.text('AUTH SCREEN'), findsOneWidget);
      expect(repo.ratingWrites, isEmpty);
    });

    testWidgets('the owner is told why the stars are missing', (tester) async {
      final repo = _FakeRecipeRepository(recipe: _fullRecipe);
      await _pump(tester, repo: repo, uid: 'someone-else', size: _phone);

      expect(find.byType(StarRatingInput), findsNothing);
      // RLS is what actually refuses a self-rating; this branch explains it.
      expect(find.textContaining('rate your own recipe'), findsOneWidget);
    });
  });

  // 32e3. Every fake in every suite returned `const []` for `versions()`, so
  // the sheet had only ever rendered its empty state.
  group('version history sheet', () {
    testWidgets('lists the versions newest first, marking the current one', (
      tester,
    ) async {
      final repo = _FakeRecipeRepository(recipe: _fullRecipe)
        ..versionRows = [
          RecipeVersion(
            id: 'v2',
            recipeId: 'r1',
            versionNumber: 2,
            authorId: 'someone-else',
            changeSummary: 'Hotter rub',
            createdAt: DateTime.utc(2026, 8, 21),
          ),
          RecipeVersion(
            id: 'v1',
            recipeId: 'r1',
            versionNumber: 1,
            authorId: 'someone-else',
            createdAt: DateTime.utc(2026, 8, 1),
          ),
        ];
      await _pump(tester, repo: repo, uid: null, size: _phone);

      await tester.tap(find.byTooltip('Version history'));
      await tester.pumpAndSettle();

      expect(find.text('Hotter rub'), findsOneWidget);
      // No summary on v1 — the row says what it knows rather than going blank.
      expect(find.text('Version 1'), findsOneWidget);
      expect(find.text('2026-08-21'), findsOneWidget);
      // `versions()` is ordered newest first, so the chip belongs to row 0.
      expect(find.widgetWithText(Chip, 'Current'), findsOneWidget);
      expect(find.text('v2'), findsOneWidget);
    });

    testWidgets('a recipe with no history says so', (tester) async {
      final repo = _FakeRecipeRepository(recipe: _fullRecipe);
      await _pump(tester, repo: repo, uid: null, size: _phone);

      await tester.tap(find.byTooltip('Version history'));
      await tester.pumpAndSettle();

      expect(find.text('No version history yet.'), findsOneWidget);
    });
  });

  // 32c3. The provider was declared `autoDispose` while `cook_step_view.dart`
  // documented the opposite, so a cook who scaled a recipe, stepped into cook
  // mode and came back was reading a page that had silently reset — the B066
  // failure (two surfaces, two quantities for one ingredient) with a detour.
  group('servings scale lifetime (32c3)', () {
    testWidgets('survives leaving the screen and coming back', (tester) async {
      final repo = _FakeRecipeRepository(recipe: _fullRecipe);
      final router = await _pump(tester, repo: repo, uid: null, size: _phone);

      await tester.tap(find.byTooltip('More servings'));
      await tester.pumpAndSettle();
      expect(find.text('9'), findsOneWidget);
      expect(find.textContaining('Scaled from 8'), findsOneWidget);

      router.go(Routes.cookRecipe('r1'));
      await tester.pumpAndSettle();
      expect(find.text('COOK MODE'), findsOneWidget);

      router.go(Routes.recipe('r1'));
      await tester.pumpAndSettle();

      expect(find.text('9'), findsOneWidget);
      expect(find.textContaining('Scaled from 8'), findsOneWidget);
    });
  });

  group('owner badge (compact)', () {
    // Phase 18 shipped the badge and listed "recipe detail renders the owner
    // badge" as uncovered, blocked on a `RecipeRepository` fake that now exists
    // in this file. The read path it pins is `kRecipeSelect`'s FK-hinted embed:
    // drop the hint and `recipe.owner` is null on every surface at once, which
    // renders as *nothing* rather than as an error (Gotcha 17).
    testWidgets('names the embedded owner and their tier', (tester) async {
      final repo = _FakeRecipeRepository(recipe: _ownedRecipe);
      await _pump(tester, repo: repo, uid: null, size: _phone);

      expect(find.byType(ChefBadge), findsOneWidget);
      expect(find.text('Amara Baptiste'), findsOneWidget);
      expect(find.text('Master Chef'), findsOneWidget);
    });

    testWidgets('no embed, no badge — and no empty furniture', (tester) async {
      final repo = _FakeRecipeRepository(recipe: _fullRecipe);
      await _pump(tester, repo: repo, uid: null, size: _phone);

      expect(find.byType(ChefBadge), findsNothing);
    });

    testWidgets('tapping it opens that chef’s page (Phase 30)', (tester) async {
      // The `ChefBadge.onTap` branch Phase 18 recorded as unreachable. It has a
      // destination now, and the id must come from the *owner*, not the recipe:
      // both are on the same object, so a wrong one still navigates somewhere.
      final repo = _FakeRecipeRepository(recipe: _ownedRecipe);
      await _pump(tester, repo: repo, uid: null, size: _phone);

      await tester.tap(find.byType(ChefBadge));
      await tester.pumpAndSettle();

      expect(find.text('CHEF d1'), findsOneWidget);
    });
  });

  // Phase 28. The rail is two tabs under one shared servings stepper.
  group('nutrition tab (compact)', () {
    testWidgets('opens on Ingredients, with both chips present', (
      tester,
    ) async {
      final repo = _FakeRecipeRepository(recipe: _labelledRecipe);
      await _pump(tester, repo: repo, uid: 'me', size: const Size(390, 1600));

      expect(_railTab('Ingredients'), findsOneWidget);
      expect(_railTab('Nutrition'), findsOneWidget);
      // The ingredient list, not the label.
      expect(find.text('Wheat flour'), findsOneWidget);
      expect(find.text('Nutrition Facts'), findsNothing);
    });

    testWidgets('switching shows the label and keeps the stepper', (
      tester,
    ) async {
      final repo = _FakeRecipeRepository(recipe: _labelledRecipe);
      await _pump(tester, repo: repo, uid: 'me', size: const Size(390, 1600));

      await tester.tap(_railTab('Nutrition'));
      await tester.pumpAndSettle();

      expect(find.text('Nutrition Facts'), findsOneWidget);
      expect(find.textContaining('Total Fat 12 g'), findsOneWidget);
      expect(find.text('Wheat flour'), findsNothing);
      // The stepper is hoisted above the tabs precisely so it survives the
      // switch — the batch line below depends on it.
      expect(find.text('Servings'), findsOneWidget);
      expect(find.byTooltip('More servings'), findsOneWidget);
    });

    testWidgets('the stepper moves the batch line, not the per-serving row', (
      tester,
    ) async {
      final repo = _FakeRecipeRepository(recipe: _labelledRecipe);
      await _pump(tester, repo: repo, uid: 'me', size: const Size(390, 1600));

      await tester.tap(_railTab('Nutrition'));
      await tester.pumpAndSettle();

      // 8 servings × 320 kcal.
      expect(find.textContaining('8 servings · 2,560 kcal total'), findsOne);

      await tester.tap(find.byTooltip('More servings'));
      await tester.pumpAndSettle();

      expect(find.textContaining('9 servings · 2,880 kcal total'), findsOne);
      // The per-serving number is unchanged. This is the decision, not a
      // detail: scaling 8 → 9 makes a bigger batch, not a bigger serving.
      // Scoped to the label since 36c: the sheet's `NutritionSummary` prints
      // the same per-serving 320, and it must not move either.
      expect(
        find.descendant(
          of: find.byType(NutritionFactsLabel),
          matching: find.text('320'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(NutritionSummary),
          matching: find.text('320'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a recipe with no data shows the empty state', (tester) async {
      final repo = _FakeRecipeRepository(recipe: _fullRecipe);
      await _pump(tester, repo: repo, uid: 'me', size: const Size(390, 1600));

      await tester.tap(_railTab('Nutrition'));
      await tester.pumpAndSettle();

      expect(find.text('No nutrition info available'), findsOneWidget);
      expect(find.text('Nutrition Facts'), findsNothing);
    });

    // Phase 29c: provenance reaches the reader. A stored `source: 'auto'`
    // renders the disclosure footnote; the manual label above renders none
    // (the 'switching shows the label' test would catch a stray footnote as
    // an extra line, but say it explicitly here).
    testWidgets('an estimated label carries the footnote', (tester) async {
      final repo = _FakeRecipeRepository(
        recipe: _labelledRecipe.copyWith(
          nutrition: _labelledRecipe.nutrition!.copyWith(source: 'auto'),
        ),
      );
      await _pump(tester, repo: repo, uid: 'me', size: const Size(390, 1600));

      await tester.tap(_railTab('Nutrition'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Estimated from ingredients'), findsOneWidget);
    });

    // The stepper and the ingredient list have to agree about what "scaled"
    // means. `servings = 0` is reachable — the editor's box is
    // `int.tryParse(…) ?? 1`, `save_recipe` only coalesces a null, and the
    // column has no positive check — and the rail deliberately leaves such a
    // recipe's quantities unscaled, so the banner must not promise a colour
    // change the list below does not make.
    testWidgets('a 0-serving recipe never claims to be scaled', (tester) async {
      final repo = _FakeRecipeRepository(
        recipe: _fullRecipe.copyWith(servings: 0),
      );
      await _pump(tester, repo: repo, uid: 'me', size: const Size(390, 1600));

      await tester.tap(find.byTooltip('More servings'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Scaled from'), findsNothing);
      // The quantity is unscaled, which is what makes the absent banner right.
      expect(find.text('1¼ cups'), findsOneWidget); // UX-023
    });

    testWidgets('the jump chip sends the rail back to Ingredients', (
      tester,
    ) async {
      final repo = _FakeRecipeRepository(recipe: _labelledRecipe);
      await _pump(tester, repo: repo, uid: 'me', size: const Size(390, 1600));

      await tester.tap(_railTab('Nutrition'));
      await tester.pumpAndSettle();
      expect(find.text('Wheat flour'), findsNothing);

      // The pinned jump bar's chip, not the tab chip of the same name.
      await tester.tap(find.widgetWithText(ActionChip, 'Ingredients'));
      await tester.pumpAndSettle();

      // Otherwise the chip scrolls to a section whose content is hidden behind
      // the other tab.
      expect(find.text('Wheat flour'), findsOneWidget);
    });
  });

  // Phase 36c: reference 5's sheet over the cover. What the reader can see —
  // a designed cover when there is no photo (the owner's Q1), the kicker, the
  // tag pills, and the nutrition summary only when there is a label.
  group('sheet (36c, compact)', () {
    testWidgets('no photo: the category colour block is the cover', (
      tester,
    ) async {
      final repo = _FakeRecipeRepository(recipe: _labelledRecipe);
      await _pump(tester, repo: repo, uid: null, size: const Size(390, 1600));

      final cover = tester.widget<CategoryCover>(find.byType(CategoryCover));
      expect(cover.category, 'Appetizer');
      expect(cover.large, isTrue);
      // The back button still floats on it, on its own scrim.
      expect(find.byTooltip('Back'), findsOneWidget);
    });

    // Contract change (36c review): the kicker is always RECIPE, so the
    // category is not printed three times on a photo-less recipe.
    testWidgets('the kicker names the page; the category is on the cover', (
      tester,
    ) async {
      final repo = _FakeRecipeRepository(recipe: _labelledRecipe);
      await _pump(tester, repo: repo, uid: null, size: const Size(390, 1600));
      expect(find.text('RECIPE'), findsOneWidget);
      // Only the colour block's own label.
      expect(find.text('APPETIZER'), findsOneWidget);
    });

    testWidgets('no category: the kicker says RECIPE', (tester) async {
      final repo = _FakeRecipeRepository(recipe: _fullRecipe);
      await _pump(tester, repo: repo, uid: null, size: const Size(390, 1600));
      expect(find.text('RECIPE'), findsOneWidget);
    });

    testWidgets('cuisine and category are tag pills; private joins them', (
      tester,
    ) async {
      final repo = _FakeRecipeRepository(recipe: _labelledRecipe);
      await _pump(tester, repo: repo, uid: null, size: const Size(390, 1600));

      expect(
        find.widgetWithText(TagPill, 'Pan-Mediterranean Coastal'),
        findsOneWidget,
      );
      expect(find.widgetWithText(TagPill, 'Appetizer'), findsOneWidget);
      // The private badge left the cover for the tag row (see the sheet).
      expect(find.widgetWithText(TagPill, 'Private'), findsOneWidget);
    });

    testWidgets('an untagged public recipe draws no tag row at all', (
      tester,
    ) async {
      final repo = _FakeRecipeRepository(
        recipe: _fullRecipe.copyWith(visibility: RecipeVisibility.public),
      );
      await _pump(tester, repo: repo, uid: null, size: const Size(390, 1600));

      expect(find.byType(TagPill), findsNothing);
    });

    testWidgets('a labelled recipe shows the nutrition summary', (
      tester,
    ) async {
      final repo = _FakeRecipeRepository(recipe: _labelledRecipe);
      await _pump(tester, repo: repo, uid: null, size: const Size(390, 1600));

      expect(find.byType(NutritionSummary), findsOneWidget);
      // Additive: the FDA label still lives behind the Nutrition tab.
      expect(find.byType(NutritionFactsLabel), findsNothing);
    });

    testWidgets('no label (null): no nutrition summary', (tester) async {
      final repo = _FakeRecipeRepository(recipe: _fullRecipe);
      await _pump(tester, repo: repo, uid: null, size: const Size(390, 1600));

      expect(find.byType(NutritionSummary), findsNothing);
    });

    testWidgets('an all-empty label counts as none', (tester) async {
      final repo = _FakeRecipeRepository(
        recipe: _fullRecipe.copyWith(
          nutrition: const RecipeNutrition(source: 'auto'),
        ),
      );
      await _pump(tester, repo: repo, uid: null, size: const Size(390, 1600));

      expect(find.byType(NutritionSummary), findsNothing);
    });

    testWidgets('ingredients and method are headed panels', (tester) async {
      final repo = _FakeRecipeRepository(recipe: _labelledRecipe);
      await _pump(tester, repo: repo, uid: null, size: const Size(390, 2400));

      expect(find.text('INGREDIENTS'), findsOneWidget);
      expect(find.text('METHOD'), findsOneWidget);
    });
  });

  // Same two-axis matrix as the expanded page (B062–B064) and cook mode (B067):
  // 390 is the phone the layout was drawn for, 800 is the medium band that used
  // to get v1 and now gets this, and 2.0× is the accessibility envelope. The
  // pinned jump bar and the sticky cook bar are both fixed-height regions, which
  // is the shape Gotcha 22 is about.
  //
  // Re-run **per tab** since Phase 28: the rail restructure re-opens the
  // envelope B070 lives in (Gotcha 26), and the nutrition label is a widget
  // neither layout had ever handed a width before.
  // UX-036: "Forked recipe" named neither the parent nor its author.
  group('fork lineage (UX-036)', () {
    final fork = _fullRecipe.copyWith(forkedFromRecipeId: 'p1');
    final parent = _fullRecipe.copyWith(
      id: 'p1',
      title: 'Nonna’s Tart',
      owner: const Profile(id: 'n1', displayName: 'Rosa Bianchi'),
      ingredientGroups: const [],
      stepGroups: const [],
    );

    testWidgets('names the parent and its author, and opens it', (
      tester,
    ) async {
      final repo = _FakeRecipeRepository(recipe: fork)
        ..summaries = {'p1': parent};
      await _pump(tester, repo: repo, uid: 'me', size: _phone);

      expect(repo.summaryReads, ['p1']);
      expect(
        find.textContaining(
          'Forked from Nonna’s Tart by Rosa Bianchi',
          findRichText: true,
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(ForkedLabel.linkKey));
      await tester.pumpAndSettle();
      expect(repo.gets.last, 'p1');
    });

    testWidgets('a parent the reader cannot see says so, and links nowhere', (
      tester,
    ) async {
      // No summary: RLS returned no row (gone private, or deleted since).
      final repo = _FakeRecipeRepository(recipe: fork);
      await _pump(tester, repo: repo, uid: 'me', size: _phone);

      expect(
        find.textContaining('private or no longer exists', findRichText: true),
        findsOneWidget,
      );
      expect(find.byKey(ForkedLabel.linkKey), findsNothing);
    });

    testWidgets('a recipe that is not a fork reads no parent', (tester) async {
      final repo = _FakeRecipeRepository(recipe: _fullRecipe);
      await _pump(tester, repo: repo, uid: 'me', size: _phone);

      expect(repo.summaryReads, isEmpty);
      expect(find.textContaining('Forked', findRichText: true), findsNothing);
    });

    for (final scale in [1.0, 2.0]) {
      testWidgets('a long parent title holds at 390 × $scale', (tester) async {
        final repo = _FakeRecipeRepository(recipe: fork)
          ..summaries = {
            'p1': parent.copyWith(
              title:
                  'The Very Long Sunday Braise My Grandmother Made Every Winter',
            ),
          };
        await _pump(
          tester,
          repo: repo,
          uid: 'me',
          size: const Size(390, 1600),
          textScale: scale,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  // UX-053: the loading state had no way back, so a slow deep link was a
  // spinner with no exit but the browser.
  group('loading and error exits (UX-053)', () {
    testWidgets('the loading page has Back, and a deep link goes to Discover', (
      tester,
    ) async {
      final repo = _FakeRecipeRepository()..getGate = Completer();
      await _pump(tester, repo: repo, uid: null, size: _phone, settle: false);

      expect(find.byType(LoadingView), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('DISCOVER'), findsOneWidget);
    });
  });

  // UX-047: the cover photo was an unnamed image.
  testWidgets('the cover photo is named for a screen reader', (tester) async {
    final handle = tester.ensureSemantics();
    final repo = _FakeRecipeRepository(
      recipe: _fullRecipe.copyWith(coverImageUrl: 'https://img.test/t.jpg'),
    );
    await _pump(tester, repo: repo, uid: 'me', size: _phone, settle: false);
    await tester.pump();
    expect(
      find.bySemanticsLabel('Photo of Spring Vegetable Tart'),
      findsOneWidget,
    );
    handle.dispose();
  });

  // DESIGN §2.2: a generated cover is tagged `AI` and never called a photo.
  testWidgets('a generated cover is tagged AI and not called a photo', (
    tester,
  ) async {
    MediaUrl.configure('http://storage.test');
    addTearDown(MediaUrl.reset);
    final handle = tester.ensureSemantics();
    final repo = _FakeRecipeRepository(
      recipe: _fullRecipe.copyWith(
        coverImageUrl: 'ai/spring-vegetable-tart.jpg',
      ),
    );
    await _pump(tester, repo: repo, uid: 'me', size: _phone, settle: false);
    await tester.pump();
    expect(find.byType(GeneratedImageTag), findsOneWidget);
    expect(
      find.bySemanticsLabel('AI-generated image of Spring Vegetable Tart'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Photo of Spring Vegetable Tart'),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
    handle.dispose();
  });

  // A screen reader said `1 1⁄3 cup` as "1 fraction slash 3".
  group('spoken quantities', () {
    testWidgets('the gutter reads a third as words; the print is unchanged', (
      tester,
    ) async {
      final thirds = _fullRecipe.copyWith(
        ingredientGroups: const [
          IngredientGroup(
            id: 'ig1',
            recipeId: 'r1',
            name: 'Crust',
            ingredients: [
              Ingredient(
                id: 'i1',
                groupId: 'ig1',
                quantity: 4 / 3,
                unit: 'cup',
                name: 'wheat flour',
              ),
            ],
          ),
        ],
      );
      final semantics = tester.ensureSemantics();
      final repo = _FakeRecipeRepository(recipe: thirds);
      await _pump(tester, repo: repo, uid: 'me', size: const Size(390, 2400));

      expect(find.text('1 1⁄3 cups'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('1 and 1 third cups')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(RegExp('⁄')), findsNothing);
      semantics.dispose();
    });
  });

  // UX-048: every control on the page is at least 48 × 48 (WCAG 2.5.8 via
  // Flutter's Android guideline, the stricter of the two it ships).
  testWidgets('every tap target meets the 48dp guideline', (tester) async {
    final handle = tester.ensureSemantics();
    final repo = _FakeRecipeRepository(
      recipe: _fullRecipe.copyWith(forkedFromRecipeId: 'p1'),
    )..summaries = {'p1': _fullRecipe.copyWith(id: 'p1', title: 'Parent')};
    await _pump(tester, repo: repo, uid: 'me', size: const Size(390, 2400));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    handle.dispose();
  });

  group('layout envelope', () {
    for (final tab in RailTab.values) {
      for (final width in [390.0, 600.0, 800.0]) {
        for (final scale in [1.0, 2.0]) {
          testWidgets(
            'no overflow at ${width}px, textScale $scale on ${tab.name}',
            (tester) async {
              final repo = _FakeRecipeRepository(recipe: _labelledRecipe);
              await _pump(
                tester,
                repo: repo,
                uid: 'me',
                size: Size(width, 1600),
                textScale: scale,
                railTab: tab,
              );
              expect(tester.takeException(), isNull);
            },
          );
        }
      }
    }
  });
}

/// A rail tab by its label — the segment itself, not the centre of the pill
/// (`widgetWithText` would tap the pill's middle).
Finder _railTab(String label) => find.descendant(
  of: find.byType(SegmentedTabs<RailTab>),
  matching: find.text(label),
);
