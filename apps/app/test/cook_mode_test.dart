import 'dart:async';

// Cook mode (Phase 27, canvas frames C/D/E/H). Two halves:
//
//  - the pure derivations in `cook_mode_model.dart` — the flatten, the weighted
//    progress segments, and the ingredient-to-step matching, which has no schema
//    behind it and therefore needs its behaviour pinned rather than trusted;
//  - the two layouts, pumped at 390px (compact, frames C/D) and 1440px (web,
//    frame H), including a 2.0× text-scale envelope. Same shape as
//    recipe_detail_v2_test.dart: pumping the page and asserting no exception is
//    the overflow assertion.
import 'package:app/features/recipe_detail/cook_mode_model.dart';
import 'package:app/features/recipe_detail/cook_mode_providers.dart';
import 'package:app/features/recipe_detail/cook_mode_screen.dart';
import 'package:app/features/recipe_detail/method_column.dart';
import 'package:app/routing/app_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const _recipe = Recipe(
  id: 'r1',
  ownerId: 'someone-else',
  title: 'Spring Vegetable Tart',
  description: 'A flaky all-butter crust.',
  prepMinutes: 30,
  cookMinutes: 55,
  servings: 8,
  visibility: RecipeVisibility.public,
  ingredientGroups: [
    IngredientGroup(
      id: 'ig1',
      recipeId: 'r1',
      name: 'Crust',
      ingredients: [
        Ingredient(
          id: 'i1',
          groupId: 'ig1',
          quantity: 6,
          unit: 'tbsp',
          name: 'butter',
        ),
        Ingredient(
          id: 'i2',
          groupId: 'ig1',
          quantity: 1.25,
          unit: 'cup',
          name: 'unbleached wheat flour',
        ),
        Ingredient(
          id: 'i3',
          groupId: 'ig1',
          name: 'kosher salt',
          note: 'a tsp',
        ),
      ],
    ),
    IngredientGroup(
      id: 'ig2',
      recipeId: 'r1',
      name: 'Filling',
      ingredients: [
        Ingredient(
          id: 'i4',
          groupId: 'ig2',
          quantity: 1,
          name: 'yellow onion, chopped',
        ),
        Ingredient(
          id: 'i5',
          groupId: 'ig2',
          quantity: 1,
          unit: 'large',
          name: 'leek, thinly sliced',
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
        RecipeStep(
          id: 's1',
          groupId: 'sg1',
          text: 'Mix the flour and salt, then blend in the cold butter.',
          tip: 'Stop as soon as it holds together.',
        ),
        RecipeStep(
          id: 's2',
          groupId: 'sg1',
          text: 'Wrap the disk and refrigerate.',
          durationMinutes: 60,
        ),
      ],
    ),
    StepGroup(
      id: 'sg2',
      recipeId: 'r1',
      name: 'Filling',
      steps: [
        RecipeStep(
          id: 's3',
          groupId: 'sg2',
          text: 'Fry the onion until translucent, then add the leek.',
          durationMinutes: 12,
          temperature: 'Medium',
        ),
        RecipeStep(id: 's4', groupId: 'sg2', text: 'Serve warm.'),
      ],
    ),
  ],
);

class _FakeAuth implements AuthRepository {
  _FakeAuth(this.uid, {String? profileId}) : profileId = profileId ?? uid;

  final String? uid;

  /// Phase 35b: `profiles.id` and the auth uid are the same value for a
  /// member, which is the default here. They differ for a member who claimed
  /// an imported chef page — B128's fixture passes one explicitly.
  final String? profileId;

  @override
  String? get currentUserId => uid;

  @override
  Future<String?> currentProfileId() async => profileId;

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

class _FakeRecipeRepository implements RecipeRepository {
  _FakeRecipeRepository([this.recipe = _recipe]);

  final Recipe recipe;
  final List<double> ratings = [];

  /// Every recipe id `fork()` was asked to copy, and a switch to drive the
  /// failure path. Both fork call sites share one handler now (32c1), so the
  /// finish screen's button is tested here and the reading page's chip in
  /// `recipe_detail_test.dart`.
  final List<String> forkedFrom = [];
  bool forkFails = false;

  @override
  Future<Recipe> getById(String id) async => recipe;

  @override
  Future<void> setRating(String recipeId, double rating) async {
    ratings.add(rating);
  }

  @override
  Future<double?> myRating(String recipeId) async => null;

  @override
  Future<bool> myLiked(String recipeId) async => false;

  @override
  Future<bool> mySaved(String recipeId) async => false;

  @override
  Future<void> logView(String recipeId) async {}

  @override
  Future<List<RecipeVersion>> versions(String recipeId) async => const [];

  // Unused on this screen's paths.
  @override
  Future<void> setLiked(String recipeId, {required bool liked}) =>
      throw UnimplementedError();

  @override
  Future<void> setSaved(String recipeId, {required bool saved}) =>
      throw UnimplementedError();

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
    return 'r2';
  }

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
  Future<void> clearRating(String recipeId) => throw UnimplementedError();
}

Future<_FakeRecipeRepository> _pump(
  WidgetTester tester, {
  String? uid,
  Size size = const Size(390, 844),
  double textScale = 1,
  Recipe recipe = _recipe,
  DateTime Function()? clock,
  String? profileId,
  bool settle = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final repo = _FakeRecipeRepository(recipe);
  final router = GoRouter(
    initialLocation: '/recipe/r1/cook',
    routes: [
      GoRoute(
        path: Routes.cookRecipePattern,
        builder:
            (_, state) => CookModeScreen(recipeId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: Routes.recipePattern,
        builder: (_, __) => const Scaffold(body: Text('RECIPE PAGE')),
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
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        recipeRepositoryProvider.overrideWithValue(repo),
        authRepositoryProvider.overrideWithValue(
          _FakeAuth(uid, profileId: profileId),
        ),
        // Cook mode's timers are deadlines on the wall clock (32c4), and
        // `tester.pump(Duration(...))` moves the *fake* clock, not
        // `DateTime.now()`. Pointing the session at the binding's clock is what
        // keeps `pump(seconds: 1)` meaning "a second passed" — without it every
        // countdown below would sit still while its ticks fired.
        cookClockProvider.overrideWithValue(
          clock ?? () => tester.binding.clock.now(),
        ),
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
    // A step photo's `CachedNetworkImage` never resolves under test, so these
    // pump frames rather than settling: enough for the recipe future and the
    // route to land (the same rule as chef_badge_test's avatar).
    await _pumpFrames(tester);
  }
  return repo;
}

Future<void> _pumpFrames(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.pump();
  }
}

/// B125's fixture: no seeded recipe carries a step photo, so step 1 gets one
/// at a reserved-TLD address. Step 2 has none.
const _kStepPhoto = 'https://example.test/step.jpg';

final _photoRecipe = _recipe.copyWith(
  stepGroups: [
    for (final g in _recipe.stepGroups)
      g.copyWith(
        steps: [
          for (final s in g.steps)
            s.id == 's1' ? s.copyWith(imageUrl: _kStepPhoto) : s,
        ],
      ),
  ],
);

/// Walks the four steps of [_recipe] to the finish screen (frame E).
Future<void> _walkToFinish(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.tap(find.text(i == 3 ? 'Finish cooking' : 'Done — next step'));
    await tester.pumpAndSettle();
  }
}

void main() {
  group('flattenCookSteps', () {
    test('keeps group identity and numbers restart per group', () {
      final steps = flattenCookSteps(_recipe);

      expect(steps, hasLength(4));
      expect(steps.map((s) => s.groupName), [
        'Crust',
        'Crust',
        'Filling',
        'Filling',
      ]);
      // Per-group numbering restarts; the overall index does not.
      expect(steps.map((s) => s.indexInGroup), [0, 1, 0, 1]);
      expect(steps.map((s) => s.overallIndex), [0, 1, 2, 3]);
      expect(steps[2].headerLabel(showGroup: true), 'Filling · step 1 of 2');
      expect(steps[2].headerLabel(showGroup: false), 'Step 1 of 2');
    });

    test('an empty group contributes nothing', () {
      // Otherwise it earns a zero-width progress segment and a heading for no
      // steps.
      const recipe = Recipe(
        id: 'r',
        ownerId: 'o',
        title: 't',
        stepGroups: [
          StepGroup(id: 'a', recipeId: 'r', name: 'Empty'),
          StepGroup(
            id: 'b',
            recipeId: 'r',
            name: 'Real',
            steps: [RecipeStep(id: 's', groupId: 'b', text: 'Do it')],
          ),
        ],
      );

      final steps = flattenCookSteps(recipe);
      expect(steps, hasLength(1));
      expect(steps.single.groupName, 'Real');
      expect(steps.single.groupIndex, 0);
    });

    test('an unnamed group still has something to print', () {
      const recipe = Recipe(
        id: 'r',
        ownerId: 'o',
        title: 't',
        stepGroups: [
          StepGroup(
            id: 'b',
            recipeId: 'r',
            steps: [RecipeStep(id: 's', groupId: 'b', text: 'Do it')],
          ),
        ],
      );
      expect(flattenCookSteps(recipe).single.groupName, 'Steps');
    });
  });

  group('cookSegments', () {
    test('weights by step count and fills only completed steps', () {
      const recipe = Recipe(
        id: 'r',
        ownerId: 'o',
        title: 't',
        stepGroups: [
          StepGroup(
            id: 'a',
            recipeId: 'r',
            name: 'Four',
            steps: [
              RecipeStep(id: '1', groupId: 'a', text: 'a'),
              RecipeStep(id: '2', groupId: 'a', text: 'b'),
              RecipeStep(id: '3', groupId: 'a', text: 'c'),
              RecipeStep(id: '4', groupId: 'a', text: 'd'),
            ],
          ),
          StepGroup(
            id: 'b',
            recipeId: 'r',
            name: 'Two',
            steps: [
              RecipeStep(id: '5', groupId: 'b', text: 'e'),
              RecipeStep(id: '6', groupId: 'b', text: 'f'),
            ],
          ),
        ],
      );
      final steps = flattenCookSteps(recipe);

      // A 4-step group and a 2-step group are not halves of the same job.
      expect(cookSegments(steps, 0).map((s) => s.stepCount), [4, 2]);

      // Standing on the very first step: nothing is behind you.
      expect(cookSegments(steps, 0).map((s) => s.fill), [0.0, 0.0]);
      // Standing on the last step of group one: three of its four are done.
      expect(cookSegments(steps, 3).map((s) => s.fill), [0.75, 0.0]);
      // First step of group two: group one completed, group two untouched.
      expect(cookSegments(steps, 4).map((s) => s.fill), [1.0, 0.0]);
      // Second (last) step of group two.
      expect(cookSegments(steps, 5).map((s) => s.fill), [1.0, 0.5]);
    });

    test('no steps, no segments', () {
      expect(cookSegments(const [], 0), isEmpty);
    });
  });

  group('stepIngredients', () {
    final all = _recipe.ingredientGroups.expand((g) => g.ingredients).toList();

    test('matches on a distinctive word of the stored name', () {
      // The stored name is "unbleached wheat flour"; the step says "the flour".
      // Whole-name matching would find nothing, which is why it is word-wise.
      final s1 = _recipe.stepGroups.first.steps.first;
      final names = stepIngredients(s1, all).map((i) => i.name);
      expect(names, containsAll(['butter', 'unbleached wheat flour']));
      expect(names, contains('kosher salt'));
    });

    test('a step that names nothing gets nothing', () {
      final serve = _recipe.stepGroups.last.steps.last;
      expect(stepIngredients(serve, all), isEmpty);
    });

    test('matching is whole-word, so it does not fire on a substring', () {
      const buttermilk = Ingredient(id: 'x', groupId: 'g', name: 'buttermilk');
      const step = RecipeStep(
        id: 's',
        groupId: 'g',
        text: 'Melt the butter in a pan.',
      );
      // "butter" is a substring of "buttermilk" but not a word in the step.
      expect(stepIngredients(step, const [buttermilk]), isEmpty);
      // And the reverse: the real butter still matches.
      const butter = Ingredient(id: 'y', groupId: 'g', name: 'butter');
      expect(stepIngredients(step, const [butter]), hasLength(1));
    });

    test('a stop word alone does not attach an ingredient', () {
      // "chopped" appears in half the names and a third of the steps; matching
      // on it would put every ingredient on every step.
      const chopped = Ingredient(
        id: 'x',
        groupId: 'g',
        name: 'chopped fresh large',
      );
      const step = RecipeStep(
        id: 's',
        groupId: 'g',
        text: 'Add the chopped fresh large pieces.',
      );
      expect(stepIngredients(step, const [chopped]), isEmpty);
    });
  });

  group('formatClock', () {
    test('reads as a countdown, and never negative', () {
      expect(formatClock(const Duration(minutes: 12)), '12:00');
      expect(formatClock(const Duration(minutes: 1, seconds: 5)), '1:05');
      expect(formatClock(const Duration(seconds: 9)), '0:09');
      expect(formatClock(Duration.zero), '0:00');
      expect(formatClock(const Duration(seconds: -3)), '0:00');
    });
  });

  group('compact (frames C and D)', () {
    testWidgets('opens on the first step with its group named', (tester) async {
      await _pump(tester);

      expect(find.text('Crust · step 1 of 2'), findsOneWidget);
      expect(find.text('Step 1 of 4'), findsOneWidget);
      expect(
        find.text('Mix the flour and salt, then blend in the cold butter.'),
        findsOneWidget,
      );
      // The tip is inline, not behind a toggle.
      expect(find.text('Stop as soon as it holds together.'), findsOneWidget);
      // Step 1 has no duration, so there is no timer to start.
      expect(find.text('Start'), findsNothing);
    });

    testWidgets('advancing walks into the next group and renumbers', (
      tester,
    ) async {
      await _pump(tester);

      await tester.tap(find.text('Done — next step'));
      await tester.pumpAndSettle();
      expect(find.text('Crust · step 2 of 2'), findsOneWidget);

      await tester.tap(find.text('Done — next step'));
      await tester.pumpAndSettle();
      // Third overall, but step 1 of its own group.
      expect(find.text('Filling · step 1 of 2'), findsOneWidget);
      expect(find.text('Step 3 of 4'), findsOneWidget);
    });

    testWidgets('the last step offers Finish, which opens the finish screen', (
      tester,
    ) async {
      await _pump(tester);

      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text('Done — next step'));
        await tester.pumpAndSettle();
      }
      expect(find.text('Finish cooking'), findsOneWidget);

      await tester.tap(find.text('Finish cooking'));
      await tester.pumpAndSettle();
      expect(find.text('That’s Spring Vegetable Tart done'), findsOneWidget);
      expect(find.text('How did it turn out?'), findsOneWidget);
    });

    testWidgets('Previous is disabled on the first step', (tester) async {
      await _pump(tester);

      final button = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.arrow_back),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('the step timer counts down and can be paused', (tester) async {
      await _pump(tester);
      // Step 2 is the 60-minute chill.
      await tester.tap(find.text('Done — next step'));
      await tester.pumpAndSettle();

      expect(find.text('60:00'), findsOneWidget);
      await tester.tap(find.text('Start'));
      await tester.pump();
      expect(find.text('of 60:00'), findsOneWidget);

      // Two ticks of the one shared periodic.
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('59:58'), findsOneWidget);

      await tester.tap(find.text('Pause'));
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('59:58'), findsOneWidget);
      expect(find.text('Resume'), findsOneWidget);
    });

    testWidgets('a timer keeps running after the cook moves on', (
      tester,
    ) async {
      await _pump(tester);
      await tester.tap(find.text('Done — next step'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start'));
      await tester.pump();

      // Move to the next step; the chill is still counting.
      await tester.tap(find.text('Done — next step'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      // Back to it: the clock moved while we were away.
      await tester.tap(find.widgetWithIcon(IconButton, Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.textContaining('59:5'), findsOneWidget);
    });

    // 32c4. The timers hold a deadline, not a counter a tick decrements, so
    // what a backgrounded app loses is the *notification*, never the elapsed
    // time. A hand-driven clock is the only way to say "no ticks arrived while
    // this happened" — `tester.pump(d)` delivers every tick inside `d`.
    testWidgets('a suspended app comes back with the time really gone', (
      tester,
    ) async {
      final base = DateTime(2026, 8, 26, 18);
      var offset = Duration.zero;
      await _pump(tester, clock: () => base.add(offset));

      // Step 2 is the 60-minute chill.
      await tester.tap(find.text('Done — next step'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start'));
      await tester.pump();
      expect(find.text('of 60:00'), findsOneWidget);

      // Ten minutes of wall clock, no ticks. One tick on the way back is
      // enough — a counter-based timer would still be reading 60:00 here.
      offset = const Duration(minutes: 10);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('50:00'), findsOneWidget);
    });

    testWidgets('a finished timer rings until acknowledged, on any step', (
      tester,
    ) async {
      // One short step so the timer can actually reach zero in a test.
      const quick = Recipe(
        id: 'r1',
        ownerId: 'o',
        title: 'Quick',
        servings: 1,
        stepGroups: [
          StepGroup(
            id: 'g',
            recipeId: 'r1',
            name: 'Only',
            steps: [
              RecipeStep(
                id: 's1',
                groupId: 'g',
                text: 'Boil it.',
                durationMinutes: 1,
              ),
              RecipeStep(id: 's2', groupId: 'g', text: 'Eat it.'),
            ],
          ),
        ],
      );
      await _pump(tester, recipe: quick);

      await tester.tap(find.text('Start'));
      await tester.pump();
      // Walk to the next step while it runs, then let it expire there.
      await tester.tap(find.text('Done — next step'));
      await tester.pumpAndSettle();
      for (var i = 0; i < 61; i++) {
        await tester.pump(const Duration(seconds: 1));
      }

      // The alarm is state, not an event, so it is visible on the step the cook
      // has moved on to.
      expect(find.textContaining('Time’s up'), findsOneWidget);
      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Time’s up'), findsNothing);
    });

    testWidgets('close leaves cook mode', (tester) async {
      await _pump(tester);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.text('RECIPE PAGE'), findsOneWidget);
    });
  });

  group('finish screen (frame E)', () {
    testWidgets('a signed-in non-owner can rate from it', (tester) async {
      final repo = await _pump(tester, uid: 'me');

      for (var i = 0; i < 4; i++) {
        await tester.tap(
          find.text(i == 3 ? 'Finish cooking' : 'Done — next step'),
        );
        await tester.pumpAndSettle();
      }

      expect(find.text('Tap to rate · half stars allowed'), findsOneWidget);
      // Fork is offered — "I changed things" is freshest right now.
      expect(find.text('Fork with my changes'), findsOneWidget);

      await tester.tap(find.byType(StarRatingInput));
      await tester.pumpAndSettle();
      expect(repo.ratings, isNotEmpty);
    });

    testWidgets('the owner is told why they cannot rate, and gets no fork', (
      tester,
    ) async {
      await _pump(tester, uid: 'someone-else');

      for (var i = 0; i < 4; i++) {
        await tester.tap(
          find.text(i == 3 ? 'Finish cooking' : 'Done — next step'),
        );
        await tester.pumpAndSettle();
      }

      expect(find.textContaining('you can’t rate it'), findsOneWidget);
      expect(find.text('Fork with my changes'), findsNothing);
    });

    // B128/UX-019. `ownerId` is a profiles.id; the auth uid is a different
    // value for a member who claimed an imported chef page, so comparing the
    // two told that owner to rate their own recipe (and offered them a fork).
    testWidgets('a member who claimed the chef page is treated as the owner', (
      tester,
    ) async {
      await _pump(
        tester,
        uid: 'auth-uid',
        profileId: 'claimed-profile',
        recipe: _recipe.copyWith(ownerId: 'claimed-profile'),
      );
      await _walkToFinish(tester);

      expect(find.textContaining('you can’t rate it'), findsOneWidget);
      expect(find.byType(StarRatingInput), findsNothing);
      expect(find.text('Fork with my changes'), findsNothing);
    });

    testWidgets('an auth uid equal to ownerId is not ownership', (
      tester,
    ) async {
      // The reverse: the uid happens to equal the recipe's owner profile id,
      // but the caller's profile is another one — they may rate and fork.
      await _pump(tester, uid: 'someone-else', profileId: 'claimed-profile');
      await _walkToFinish(tester);

      expect(find.textContaining('you can’t rate it'), findsNothing);
      expect(find.text('Tap to rate · half stars allowed'), findsOneWidget);
      expect(find.text('Fork with my changes'), findsOneWidget);
    });

    testWidgets('signed out, rating routes to /auth and writes nothing', (
      tester,
    ) async {
      final repo = await _pump(tester);

      for (var i = 0; i < 4; i++) {
        await tester.tap(
          find.text(i == 3 ? 'Finish cooking' : 'Done — next step'),
        );
        await tester.pumpAndSettle();
      }

      expect(find.text('Sign in to rate it.'), findsOneWidget);
      expect(find.byType(StarRatingInput), findsNothing);
      expect(repo.ratings, isEmpty);
    });

    testWidgets('signed out, forking routes to /auth and writes nothing', (
      tester,
    ) async {
      final repo = await _pump(tester);
      await _walkToFinish(tester);

      await tester.tap(find.text('Fork with my changes'));
      await tester.pumpAndSettle();

      expect(find.text('AUTH SCREEN'), findsOneWidget);
      expect(repo.forkedFrom, isEmpty);
    });

    // 32c1/B084. `fork()` threw `UnimplementedError` in every fake until now, so
    // neither call site's flow had ever been driven — the reading page's chip
    // fired the RPC while signed out and surfaced a Postgres denial. Both go
    // through `forkRecipe` now; the reading page's half of this pair lives in
    // `recipe_detail_test.dart`.
    testWidgets('forking lands in the editor on the new copy', (tester) async {
      final repo = await _pump(tester, uid: 'me');
      await _walkToFinish(tester);

      await tester.tap(find.text('Fork with my changes'));
      await tester.pumpAndSettle();

      expect(repo.forkedFrom, ['r1']);
      expect(find.text('EDITOR r2'), findsOneWidget);
    });

    testWidgets('a failed fork says so and stays put', (tester) async {
      final repo = await _pump(tester, uid: 'me');
      repo.forkFails = true;
      await _walkToFinish(tester);

      await tester.tap(find.text('Fork with my changes'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Could not fork'), findsOneWidget);
      expect(find.text('EDITOR r2'), findsNothing);
    });

    testWidgets('"not done" goes back to the last step', (tester) async {
      await _pump(tester);

      for (var i = 0; i < 4; i++) {
        await tester.tap(
          find.text(i == 3 ? 'Finish cooking' : 'Done — next step'),
        );
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Not done — back to the last step'));
      await tester.pumpAndSettle();

      expect(find.text('Filling · step 2 of 2'), findsOneWidget);
    });
  });

  group('web (frame H)', () {
    testWidgets('uses the width: rail, keyboard hint, honest chips', (
      tester,
    ) async {
      await _pump(tester, size: const Size(1440, 1000));

      expect(find.text('Cook mode'), findsOneWidget);
      expect(find.text('For this step'), findsOneWidget);
      expect(find.text('Coming up'), findsOneWidget);
      expect(
        find.text('Space to advance · ← → to move · Esc to leave'),
        findsOneWidget,
      );
      // The canvas promises a wakelock and a background alarm. Neither is built,
      // so the chips say what actually happens.
      expect(find.text('Keep this screen open'), findsOneWidget);
      expect(find.text('Chime when a timer ends'), findsOneWidget);
      expect(find.text('Screen stays awake'), findsNothing);
      expect(find.text('Alarms on'), findsNothing);
    });

    testWidgets('the rail lists the ingredients the step names', (
      tester,
    ) async {
      await _pump(tester, size: const Size(1440, 1000));

      // Step 1 mentions flour, salt and butter — scaled quantities, sentence
      // case, same helpers the reading page's rail uses.
      expect(find.text('Butter'), findsOneWidget);
      expect(find.text('Unbleached wheat flour'), findsOneWidget);
      expect(find.text('6 tbsp'), findsOneWidget);
      expect(find.text('1.25 cup'), findsOneWidget);
      // "Serve warm" names nothing, and the rail says so rather than lying.
      await tester.tap(find.text('Done — next step'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done — next step'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done — next step'));
      await tester.pumpAndSettle();
      expect(find.textContaining('doesn’t name an ingredient'), findsOneWidget);
    });

    testWidgets('space advances and arrow-left goes back', (tester) async {
      await _pump(tester, size: const Size(1440, 1000));

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(find.text('Crust · step 2 of 2'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(find.text('Crust · step 1 of 2'), findsOneWidget);
    });

    // B130/UX-016. Space used to be a page-wide binding that consumed the key
    // before it could bubble up to the default Space → ActivateIntent
    // shortcut, so a keyboard user who tabbed to "Start" advanced the step
    // instead of starting its timer.
    testWidgets('space presses a focused button instead of advancing', (
      tester,
    ) async {
      await _pump(tester, size: const Size(1440, 1000));
      // Step 2 is the 60-minute chill, the one with a Start button.
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(find.text('Crust · step 2 of 2'), findsOneWidget);

      Focus.of(tester.element(find.text('Start'))).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();

      // The timer started, and the cook is still on step 2.
      expect(find.text('of 60:00'), findsOneWidget);
      expect(find.text('Crust · step 2 of 2'), findsOneWidget);

      // Start was replaced by the running ring, so its focus went back to the
      // page, and Space advances again.
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(find.text('Filling · step 1 of 2'), findsOneWidget);
    });

    testWidgets('space on a focused Previous goes back, not forward', (
      tester,
    ) async {
      await _pump(tester, size: const Size(1440, 1000));
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(find.text('Crust · step 2 of 2'), findsOneWidget);

      Focus.of(tester.element(find.text('Previous'))).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();

      expect(find.text('Crust · step 1 of 2'), findsOneWidget);
    });
  });

  testWidgets('a recipe with no steps says so instead of crashing', (
    tester,
  ) async {
    const empty = Recipe(id: 'r1', ownerId: 'o', title: 'Empty');
    await _pump(tester, recipe: empty);

    expect(find.text('Nothing to cook yet'), findsOneWidget);
    await tester.tap(find.text('Back to the recipe'));
    await tester.pumpAndSettle();
    expect(find.text('RECIPE PAGE'), findsOneWidget);
  });

  // B125/UX-001. The editor has uploaded step photos since Phase 33 and cook
  // mode never showed one. `settle: false` throughout — the image never
  // resolves under test, and which branch rendered is what matters.
  group('step photo (B125)', () {
    testWidgets('compact shows the current step photo, and only its own', (
      tester,
    ) async {
      await _pump(tester, recipe: _photoRecipe, settle: false);

      final image = tester.widget<CachedNetworkImage>(
        find.byType(CachedNetworkImage),
      );
      expect(image.imageUrl, _kStepPhoto);

      // Step 2 has no photo, and gets no placeholder either.
      await tester.tap(find.text('Done — next step'));
      await _pumpFrames(tester);
      expect(find.text('Crust · step 2 of 2'), findsOneWidget);
      expect(find.byType(CachedNetworkImage), findsNothing);
    });

    testWidgets('web shows it too', (tester) async {
      await _pump(
        tester,
        recipe: _photoRecipe,
        size: const Size(1440, 1000),
        settle: false,
      );
      expect(find.byType(CachedNetworkImage), findsOneWidget);
    });

    testWidgets('a recipe without step photos draws none', (tester) async {
      await _pump(tester, settle: false);
      expect(find.byType(CachedNetworkImage), findsNothing);
    });

    testWidgets('a publisher who asked for no images gets none', (
      tester,
    ) async {
      // The cover's rights rule (Phase 35c) covers a step's photo too.
      await _pump(
        tester,
        recipe: _photoRecipe.copyWith(imageMode: ImageMode.none),
        settle: false,
      );
      expect(find.byType(CachedNetworkImage), findsNothing);
    });

    testWidgets('a landscape phone caps the photo against its height', (
      tester,
    ) async {
      // 4:3 across an 844px-wide column would be ~610px — taller than the
      // 390px window. Capped, it keeps the full width and crops.
      await _pump(
        tester,
        recipe: _photoRecipe,
        size: const Size(844, 390),
        settle: false,
      );
      expect(tester.takeException(), isNull);
      final size = tester.getSize(find.byType(StepPhoto));
      expect(size.height, lessThanOrEqualTo(390 * 0.4 + AppSpacing.smPlus));
      expect(size.width, greaterThan(800));
    });

    for (final size in [
      const Size(390, 844),
      const Size(1000, 1200),
      const Size(1440, 1000),
    ]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('no overflow with a photo at ${size.width}px, '
            'textScale $scale', (tester) async {
          await _pump(
            tester,
            recipe: _photoRecipe,
            size: size,
            textScale: scale,
            settle: false,
          );
          expect(find.byType(CachedNetworkImage), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  // The two-axis envelope, same rationale as the reading page's: a step at 40px
  // beside a 400px rail, and a 52px advance button whose label grows with the
  // type, are both shapes that have overflowed here before (B062–B064).
  group('layout envelope', () {
    for (final size in [
      const Size(390, 844),
      const Size(1000, 1200),
      const Size(1440, 1000),
    ]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('no overflow at ${size.width}px, textScale $scale', (
          tester,
        ) async {
          await _pump(tester, size: size, textScale: scale);
          expect(tester.takeException(), isNull);

          // And on the finish screen, which stacks a headline and a rating panel.
          for (var i = 0; i < 4; i++) {
            await tester.tap(
              find.text(i == 3 ? 'Finish cooking' : 'Done — next step'),
            );
            await tester.pumpAndSettle();
          }
          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}
