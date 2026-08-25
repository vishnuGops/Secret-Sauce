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
import 'package:app/features/recipe_detail/rail_panel.dart';
import 'package:app/features/recipe_detail/recipe_detail_providers.dart';
import 'package:app/features/recipe_detail/recipe_detail_screen.dart';
import 'package:app/routing/app_router.dart';
import 'package:core/core.dart';
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

/// [_fullRecipe] with a nutrition label. 8 servings × 320 kcal, so the batch
/// line is a four-figure number and the grouping is exercised too.
final _labelledRecipe = _fullRecipe.copyWith(
  nutrition: const RecipeNutrition(
    calories: 320,
    totalFatG: 12,
    saturatedFatG: 5,
    sodiumMg: 480,
    totalCarbsG: 30,
    proteinG: 9,
  ),
);

class _FakeAuth implements AuthRepository {
  _FakeAuth(this.uid);

  final String? uid;

  @override
  String? get currentUserId => uid;

  @override
  Stream<AuthState> authStateChanges() => const Stream.empty();

  @override
  Future<void> signIn({
    required String email,
    required String password,
  }) async {}

  @override
  Future<void> signUp({
    required String email,
    required String password,
    required String displayName,
  }) async {}

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

  @override
  Future<Recipe> getById(String id) async => recipe;

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
    saveWrites.add(saved);
    this.saved = saved;
  }

  @override
  Future<void> logView(String recipeId) async => viewLogs++;

  @override
  Future<double?> myRating(String recipeId) async => null;

  @override
  Future<List<RecipeVersion>> versions(String recipeId) async => const [];

  // Unused on this screen's read path.
  @override
  Future<Recipe> create(Recipe recipe) => throw UnimplementedError();

  @override
  Future<Recipe> update(Recipe recipe, {String changeSummary = 'Updated'}) =>
      throw UnimplementedError();

  @override
  Future<void> delete(String id) => throw UnimplementedError();

  @override
  Future<String> fork(String sourceRecipeId) => throw UnimplementedError();

  @override
  Future<List<Recipe>> listMine({
    int limit = kRecipePageSize,
    int offset = 0,
  }) => throw UnimplementedError();

  @override
  Future<List<Recipe>> listSharedWithMe({
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
  Future<void> setRating(String recipeId, double rating) =>
      throw UnimplementedError();

  @override
  Future<void> clearRating(String recipeId) => throw UnimplementedError();
}

/// Pumps the detail screen behind a real router, so `context.go(Routes.auth)`
/// actually resolves instead of being asserted on a mock.
Future<GoRouter> _pump(
  WidgetTester tester, {
  required _FakeRecipeRepository repo,
  required String? uid,
  Size? size,
  double textScale = 1,
  RailTab? railTab,
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
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        recipeRepositoryProvider.overrideWithValue(repo),
        authRepositoryProvider.overrideWithValue(_FakeAuth(uid)),
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
  await tester.pumpAndSettle();
  return router;
}

void main() {
  testWidgets('signed out, tapping like goes to /auth and writes nothing', (
    tester,
  ) async {
    final repo = _FakeRecipeRepository();
    await _pump(tester, repo: repo, uid: null);

    await tester.tap(find.byIcon(Icons.favorite_border));
    await tester.pumpAndSettle();

    expect(find.text('AUTH SCREEN'), findsOneWidget);
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
      await _pump(tester, repo: repo, uid: null, size: const Size(390, 844));

      // Facts quad: the four that fit, not the six the wide strip carries.
      expect(find.text('TOTAL'), findsOneWidget);
      expect(find.text('HANDS ON'), findsOneWidget);
      expect(find.text('LONGEST WAIT'), findsOneWidget);
      expect(find.text('DIFFICULTY'), findsOneWidget);
      expect(find.text('COOK'), findsNothing);
      expect(find.text('VISIBILITY'), findsNothing);
      // Private, so the badge is on the cover instead.
      expect(find.text('Private'), findsOneWidget);

      // Jump bar, ingredients rail, method column, sticky cook bar.
      expect(find.text('Ingredients'), findsWidgets);
      expect(find.text('Method'), findsWidgets);
      expect(find.text('Ready to cook?'), findsOneWidget);
      expect(find.text('3 steps · 1 h 25 m'), findsOneWidget);
      // The attribution box (frame F).
      expect(find.textContaining('Rosa’s kitchen'), findsOneWidget);

      // v1 is gone: no collapsing hero, no "Instructions" heading.
      expect(find.byType(SliverAppBar), findsNothing);
      expect(find.text('Instructions'), findsNothing);
    });

    testWidgets('the sticky bar starts cooking', (tester) async {
      final repo = _FakeRecipeRepository(recipe: _fullRecipe);
      await _pump(tester, repo: repo, uid: null, size: const Size(390, 844));

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
      await _pump(tester, repo: repo, uid: null, size: const Size(390, 844));

      // Same widget as the expanded page's left column — scaled quantity in the
      // gutter, sentence-cased name, check-off counter.
      expect(find.text('1.25 cup'), findsOneWidget);
      expect(find.text('Wheat flour'), findsOneWidget);
      expect(find.text('0 of 1 gathered'), findsOneWidget);
      // And it is bare here rather than a bordered card. The flag moved from
      // `IngredientRail` to `RailPanel` in Phase 28, when the container went up
      // to the tab host — an expected API break, not a regression.
      expect(
        tester.widget<RailPanel>(find.byType(RailPanel)).bordered,
        isFalse,
      );
    });

    testWidgets('the owner gets edit and share, and no fork chip', (
      tester,
    ) async {
      final repo = _FakeRecipeRepository(recipe: _fullRecipe);
      await _pump(
        tester,
        repo: repo,
        uid: 'someone-else',
        size: const Size(390, 844),
      );

      expect(find.byIcon(Icons.edit), findsOneWidget);
      expect(find.byIcon(Icons.share), findsOneWidget);
      // You cannot fork your own recipe, so the chip is absent.
      expect(find.widgetWithText(ActionChip, 'Fork'), findsNothing);
    });

    testWidgets('a non-owner gets the fork chip and no editing', (
      tester,
    ) async {
      final repo = _FakeRecipeRepository(recipe: _fullRecipe);
      await _pump(tester, repo: repo, uid: 'me', size: const Size(390, 844));

      expect(find.widgetWithText(ActionChip, 'Fork'), findsOneWidget);
      expect(find.byIcon(Icons.edit), findsNothing);
      expect(find.byIcon(Icons.share), findsNothing);
    });
  });

  // Phase 28. The rail is two tabs under one shared servings stepper.
  group('nutrition tab (compact)', () {
    testWidgets('opens on Ingredients, with both chips present', (
      tester,
    ) async {
      final repo = _FakeRecipeRepository(recipe: _labelledRecipe);
      await _pump(tester, repo: repo, uid: 'me', size: const Size(390, 1600));

      expect(find.widgetWithText(ChoiceChip, 'Ingredients'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Nutrition'), findsOneWidget);
      // The ingredient list, not the label.
      expect(find.text('Wheat flour'), findsOneWidget);
      expect(find.text('Nutrition Facts'), findsNothing);
    });

    testWidgets('switching shows the label and keeps the stepper', (
      tester,
    ) async {
      final repo = _FakeRecipeRepository(recipe: _labelledRecipe);
      await _pump(tester, repo: repo, uid: 'me', size: const Size(390, 1600));

      await tester.tap(find.widgetWithText(ChoiceChip, 'Nutrition'));
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

      await tester.tap(find.widgetWithText(ChoiceChip, 'Nutrition'));
      await tester.pumpAndSettle();

      // 8 servings × 320 kcal.
      expect(find.textContaining('8 servings · 2,560 kcal total'), findsOne);

      await tester.tap(find.byTooltip('More servings'));
      await tester.pumpAndSettle();

      expect(find.textContaining('9 servings · 2,880 kcal total'), findsOne);
      // The per-serving number is unchanged. This is the decision, not a
      // detail: scaling 8 → 9 makes a bigger batch, not a bigger serving.
      expect(find.text('320'), findsOneWidget);
    });

    testWidgets('a recipe with no data shows the empty state', (tester) async {
      final repo = _FakeRecipeRepository(recipe: _fullRecipe);
      await _pump(tester, repo: repo, uid: 'me', size: const Size(390, 1600));

      await tester.tap(find.widgetWithText(ChoiceChip, 'Nutrition'));
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

      await tester.tap(find.widgetWithText(ChoiceChip, 'Nutrition'));
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
      expect(find.text('1.25 cup'), findsOneWidget);
    });

    testWidgets('the jump chip sends the rail back to Ingredients', (
      tester,
    ) async {
      final repo = _FakeRecipeRepository(recipe: _labelledRecipe);
      await _pump(tester, repo: repo, uid: 'me', size: const Size(390, 1600));

      await tester.tap(find.widgetWithText(ChoiceChip, 'Nutrition'));
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

  // Same two-axis matrix as the expanded page (B062–B064) and cook mode (B067):
  // 390 is the phone the layout was drawn for, 800 is the medium band that used
  // to get v1 and now gets this, and 2.0× is the accessibility envelope. The
  // pinned jump bar and the sticky cook bar are both fixed-height regions, which
  // is the shape Gotcha 22 is about.
  //
  // Re-run **per tab** since Phase 28: the rail restructure re-opens the
  // envelope B070 lives in (Gotcha 26), and the nutrition label is a widget
  // neither layout had ever handed a width before.
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
