import 'dart:async';

// UX-037: an owner can delete a recipe — from the reading page's "More" menu
// (compact cover scrim and expanded header band) and from the editor's app-bar
// overflow — behind one confirm, one in-flight guard, and one set of list
// invalidations (`delete_action.dart`).
import 'package:app/features/my_recipes/my_recipes_providers.dart';
import 'package:app/features/recipe_detail/delete_action.dart';
import 'package:app/features/recipe_detail/recipe_detail_screen.dart';
import 'package:app/features/recipe_editor/recipe_editor_screen.dart';
import 'package:app/routing/app_router.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const _mine = Recipe(
  id: 'r1',
  ownerId: 'me',
  title: 'Grandma’s Jollof',
  description: 'Smoky party rice.',
  prepMinutes: 20,
  cookMinutes: 60,
  servings: 6,
  visibility: RecipeVisibility.public,
  ingredientGroups: [
    IngredientGroup(
      id: 'g1',
      recipeId: 'r1',
      name: 'Base',
      ingredients: [
        Ingredient(id: 'i1', groupId: 'g1', quantity: 2, name: 'cups rice'),
      ],
    ),
  ],
  stepGroups: [
    StepGroup(
      id: 'sg1',
      recipeId: 'r1',
      name: 'Cook',
      steps: [RecipeStep(id: 's1', groupId: 'sg1', text: 'Fry the base.')],
    ),
  ],
);

final _theirs = _mine.copyWith(ownerId: 'someone-else');

class _FakeAuth implements AuthRepository {
  _FakeAuth(this.uid);

  final String? uid;

  @override
  String? get currentUserId => uid;

  // A member: profile id and auth uid agree (Phase 35b).
  @override
  Future<String?> currentProfileId() async => uid;

  @override
  Stream<AuthState> authStateChanges() => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}

/// Serves one recipe, records every delete, and can refuse or hold one.
class _DeleteRepo implements RecipeRepository {
  _DeleteRepo(this.recipe, {this.deny = false, this.hold});

  final Recipe recipe;

  /// Throw what `delete()` throws when RLS matched zero rows (Gotcha 2).
  final bool deny;

  /// When set, `delete()` waits on it — a request still out.
  final Completer<void>? hold;

  final List<String> deleted = [];

  @override
  Future<Recipe> getById(String id) async => recipe;

  @override
  Future<void> delete(String id) async {
    deleted.add(id);
    if (hold != null) await hold!.future;
    if (deny) throw WriteDeniedException('delete this recipe', detail: id);
  }

  /// My Recipes' list: the recipe until it has been deleted.
  @override
  Future<List<Recipe>> listMine({
    int limit = kRecipePageSize,
    int offset = 0,
  }) async => deleted.contains(recipe.id) ? const [] : [recipe];

  @override
  Future<bool> myLiked(String recipeId) async => false;

  @override
  Future<bool> mySaved(String recipeId) async => false;

  @override
  Future<void> logView(String recipeId) async {}

  @override
  Future<double?> myRating(String recipeId) async => null;

  @override
  Future<List<RecipeVersion>> versions(String recipeId) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}

class _StubFood implements FoodRepository {
  @override
  Future<Map<String, String>> displayNames(List<String> ids) async => const {};

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}

/// A stand-in for `/my` that watches the real [myRecipesProvider], so a stale
/// list after a delete is visible as a title that should have gone.
class _MyRecipesStub extends ConsumerWidget {
  const _MyRecipesStub();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final titles = [
      for (final r
          in ref.watch(myRecipesProvider).valueOrNull?.recipes ??
              const <Recipe>[])
        r.title,
    ];
    return Scaffold(
      body: Column(
        children: [
          const Text('MY RECIPES'),
          for (final t in titles) Text('LISTED $t'),
        ],
      ),
    );
  }
}

Future<GoRouter> _pump(
  WidgetTester tester, {
  required _DeleteRepo repo,
  String? uid = 'me',
  Size size = const Size(390, 844),
  double textScale = 1,
  String initialLocation = '/recipe/r1',
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: Routes.myRecipes,
        builder: (_, __) => const _MyRecipesStub(),
      ),
      GoRoute(
        path: Routes.editRecipePattern,
        builder:
            (_, state) =>
                RecipeEditorScreen(recipeId: state.pathParameters['id']),
      ),
      GoRoute(
        path: Routes.newRecipe,
        builder: (_, __) => const RecipeEditorScreen(),
      ),
      GoRoute(
        path: Routes.recipePattern,
        builder:
            (_, state) =>
                RecipeDetailScreen(recipeId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: Routes.discover,
        builder: (_, __) => const Scaffold(body: Text('DISCOVER')),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        recipeRepositoryProvider.overrideWithValue(repo),
        authRepositoryProvider.overrideWithValue(_FakeAuth(uid)),
        foodRepositoryProvider.overrideWithValue(_StubFood()),
      ],
      child: MaterialApp.router(
        theme: AppTheme.light(),
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

/// More → Delete recipe → the confirm dialog.
Future<void> _openConfirm(WidgetTester tester) async {
  // At 1000 × 2.0 the header band is taller than the window.
  await tester.ensureVisible(find.byTooltip('More'));
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('More'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Delete recipe'));
  await tester.pumpAndSettle();
}

Finder get _confirmButton => find.widgetWithText(FilledButton, 'Delete');

void main() {
  group('the owner gets Delete behind More', () {
    for (final (label, size) in [
      ('compact 390', const Size(390, 844)),
      ('expanded 1440', const Size(1440, 900)),
    ]) {
      testWidgets('$label: owner sees More → Delete recipe', (tester) async {
        await _pump(tester, repo: _DeleteRepo(_mine), size: size);

        await tester.tap(find.byTooltip('More'));
        await tester.pumpAndSettle();
        expect(find.text('Delete recipe'), findsOneWidget);
      });

      testWidgets('$label: a reader gets no More menu', (tester) async {
        await _pump(tester, repo: _DeleteRepo(_theirs), size: size);

        expect(find.byTooltip('More'), findsNothing);
        expect(find.text('Delete recipe'), findsNothing);
      });
    }
  });

  testWidgets('the confirm names the recipe and states what survives', (
    tester,
  ) async {
    await _pump(tester, repo: _DeleteRepo(_mine));
    await _openConfirm(tester);

    expect(find.text('Delete this recipe?'), findsOneWidget);
    expect(find.textContaining('“Grandma’s Jollof”'), findsOneWidget);
    expect(find.textContaining('cannot be undone'), findsOneWidget);
    // `forked_from_recipe_id … on delete set null`: forks are kept.
    expect(find.textContaining('are kept'), findsOneWidget);
  });

  testWidgets('Cancel deletes nothing and stays on the recipe', (tester) async {
    final repo = _DeleteRepo(_mine);
    await _pump(tester, repo: repo);
    await _openConfirm(tester);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(repo.deleted, isEmpty);
    expect(find.text('Delete this recipe?'), findsNothing);
    expect(find.text('MY RECIPES'), findsNothing);
  });

  testWidgets('confirm deletes once and lands on My Recipes', (tester) async {
    final repo = _DeleteRepo(_mine);
    await _pump(tester, repo: repo, size: const Size(1440, 900));
    await _openConfirm(tester);

    await tester.tap(_confirmButton);
    await tester.pumpAndSettle();

    expect(repo.deleted, ['r1']);
    expect(find.text('MY RECIPES'), findsOneWidget);
    expect(find.text('Recipe deleted'), findsOneWidget);
  });

  // The provider that matters: a detail page opened from My Recipes is pushed
  // over it, so the tab — and `myRecipesProvider` — stays alive underneath.
  // Without the invalidation the owner lands back on a list still showing the
  // recipe they just deleted.
  testWidgets('My Recipes underneath no longer lists the deleted recipe', (
    tester,
  ) async {
    final repo = _DeleteRepo(_mine);
    final router = await _pump(
      tester,
      repo: repo,
      initialLocation: Routes.myRecipes,
    );
    expect(find.text('LISTED Grandma’s Jollof'), findsOneWidget);

    unawaited(router.push(Routes.recipe('r1')));
    await tester.pumpAndSettle();
    await _openConfirm(tester);
    await tester.tap(_confirmButton);
    await tester.pumpAndSettle();

    expect(find.text('MY RECIPES'), findsOneWidget);
    expect(find.text('LISTED Grandma’s Jollof'), findsNothing);
  });

  testWidgets('a refused delete shows the friendly error and stays', (
    tester,
  ) async {
    final repo = _DeleteRepo(_mine, deny: true);
    await _pump(tester, repo: repo);
    await _openConfirm(tester);

    await tester.tap(_confirmButton);
    await tester.pumpAndSettle();

    expect(repo.deleted, ['r1']);
    expect(
      find.text(
        'Could not delete — '
        '${const WriteDeniedException('delete this recipe').message}',
      ),
      findsOneWidget,
    );
    expect(find.text('MY RECIPES'), findsNothing);
    expect(find.text('Recipe deleted'), findsNothing);
    // Still on the page, with the menu usable again (the flag was released).
    expect(find.byTooltip('More'), findsOneWidget);
  });

  testWidgets('a second delete cannot start while one is in flight', (
    tester,
  ) async {
    final hold = Completer<void>();
    final repo = _DeleteRepo(_mine, hold: hold);
    await _pump(tester, repo: repo);
    await _openConfirm(tester);
    await tester.tap(_confirmButton);
    await tester.pumpAndSettle();
    expect(repo.deleted, ['r1']);

    // The affordance: the menu entry renders disabled.
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    final item = tester.widget<PopupMenuItem<RecipeOwnerAction>>(
      find.ancestor(
        of: find.text('Delete recipe'),
        matching: find.byType(PopupMenuItem<RecipeOwnerAction>),
      ),
    );
    expect(item.enabled, isFalse);
    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();

    // The guard, for any caller: a direct second call returns without asking.
    final element = tester.element(find.byType(RecipeDetailScreen));
    final second = confirmAndDeleteRecipe(element, element as WidgetRef, _mine);
    await tester.pumpAndSettle();
    // Checked before awaiting `second`: without the guard it would be parked
    // on this dialog, and the await would hang the test instead of failing it.
    expect(find.text('Delete this recipe?'), findsNothing);
    expect(await second, isFalse);

    hold.complete();
    await tester.pumpAndSettle();
    expect(repo.deleted, ['r1']);
    expect(find.text('MY RECIPES'), findsOneWidget);
  });

  // Phase 37 review: navigation used to hinge on the *caller's* mounted flag.
  // Tapping Edit while the delete was out unmounted the menu, so a successful
  // delete left the reader in the editor of a recipe that no longer existed.
  testWidgets('leaving for the editor mid-delete still lands on My Recipes', (
    tester,
  ) async {
    final hold = Completer<void>();
    final repo = _DeleteRepo(_mine, hold: hold);
    final router = await _pump(tester, repo: repo);
    await _openConfirm(tester);
    await tester.tap(_confirmButton);
    await tester.pumpAndSettle();

    router.go(Routes.editRecipe('r1'));
    await tester.pumpAndSettle();
    hold.complete();
    await tester.pumpAndSettle();

    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      Routes.myRecipes,
    );
  });

  testWidgets('a reader who went elsewhere mid-delete is left there', (
    tester,
  ) async {
    final hold = Completer<void>();
    final repo = _DeleteRepo(_mine, hold: hold);
    final router = await _pump(tester, repo: repo);
    await _openConfirm(tester);
    await tester.tap(_confirmButton);
    await tester.pumpAndSettle();

    router.go(Routes.discover);
    await tester.pumpAndSettle();
    hold.complete();
    await tester.pumpAndSettle();

    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      Routes.discover,
    );
  });

  group('editor', () {
    testWidgets('overflow deletes without the discard prompt', (tester) async {
      final repo = _DeleteRepo(_mine);
      await _pump(
        tester,
        repo: repo,
        size: const Size(1440, 900),
        initialLocation: Routes.editRecipe('r1'),
      );
      // Dirty the draft, so the unsaved-changes guard is armed.
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Grandma’s Jollof'),
        'Half-typed new title',
      );
      await tester.pump();

      await _openConfirm(tester);
      // The dialog names the stored recipe, not the half-typed draft.
      expect(find.textContaining('“Grandma’s Jollof”'), findsOneWidget);
      await tester.tap(_confirmButton);
      await tester.pumpAndSettle();

      expect(repo.deleted, ['r1']);
      expect(find.text('Discard changes?'), findsNothing);
      expect(find.text('MY RECIPES'), findsOneWidget);
      expect(find.text('Recipe deleted'), findsOneWidget);
    });

    testWidgets('a new recipe has nothing to delete', (tester) async {
      await _pump(
        tester,
        repo: _DeleteRepo(_mine),
        initialLocation: Routes.newRecipe,
      );

      expect(find.byTooltip('More'), findsNothing);
    });
  });

  group('envelope: owner header with More', () {
    for (final width in [390.0, 1000.0, 1440.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('${width.toInt()} × $scale', (tester) async {
          await _pump(
            tester,
            repo: _DeleteRepo(_mine),
            size: Size(width, 900),
            textScale: scale,
          );
          expect(tester.takeException(), isNull);
          expect(find.byTooltip('More'), findsOneWidget);

          // The open menu and the confirm are part of the envelope too.
          await _openConfirm(tester);
          expect(tester.takeException(), isNull);
          expect(find.text('Delete this recipe?'), findsOneWidget);
        });
      }
    }
  });
}
