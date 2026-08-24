import 'dart:async';

// The v2 expanded (web) recipe-detail layout: header band + facts strip +
// ingredients rail / method column. These tests pump at a 1440×900 window so
// `context.isExpanded` selects the v2 path; the v1 suite in
// recipe_detail_test.dart pumps at the default 800×600 and keeps covering the
// compact/medium layout.
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
  description: 'Smoky skewers with a peanut-chilli crust.',
  prepMinutes: 30,
  cookMinutes: 40,
  servings: 4,
  visibility: RecipeVisibility.public,
  likeCount: 12,
  saveCount: 3,
  ingredientGroups: [
    IngredientGroup(
      id: 'g1',
      recipeId: 'r1',
      name: 'Marinade',
      ingredients: [
        Ingredient(
          id: 'i1',
          groupId: 'g1',
          quantity: 600,
          unit: 'g',
          name: 'boneless chicken thigh',
        ),
        Ingredient(id: 'i2', groupId: 'g1', name: 'salt', note: 'to taste'),
      ],
    ),
  ],
  stepGroups: [
    StepGroup(
      id: 'sg1',
      recipeId: 'r1',
      name: 'Grill',
      steps: [
        RecipeStep(
          id: 's1',
          groupId: 'sg1',
          text: 'Marinate the skewers.',
          durationMinutes: 30,
          tip: 'Longer is better.',
        ),
        RecipeStep(id: 's2', groupId: 'sg1', text: 'Grill until charred.'),
      ],
    ),
  ],
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

class _FakeRecipeRepository implements RecipeRepository {
  _FakeRecipeRepository([this.recipe = _recipe]);

  final Recipe recipe;

  @override
  Future<Recipe> getById(String id) async => recipe;

  @override
  Future<bool> myLiked(String recipeId) async => false;

  @override
  Future<bool> mySaved(String recipeId) async => false;

  @override
  Future<void> setLiked(String recipeId, {required bool liked}) async {}

  @override
  Future<void> setSaved(String recipeId, {required bool saved}) async {}

  @override
  Future<void> logView(String recipeId) async {}

  @override
  Future<double?> myRating(String recipeId) async => null;

  @override
  Future<List<RecipeVersion>> versions(String recipeId) async => const [
    RecipeVersion(
      id: 'v2',
      recipeId: 'r1',
      versionNumber: 2,
      authorId: 'someone-else',
      changeSummary: 'Hotter rub',
    ),
  ];

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

Future<void> _pump(
  WidgetTester tester, {
  String? uid,
  Size size = const Size(1440, 900),
  double textScale = 1,
  Recipe recipe = _recipe,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

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
        path: Routes.auth,
        builder: (_, __) => const Scaffold(body: Text('AUTH SCREEN')),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        recipeRepositoryProvider.overrideWithValue(
          _FakeRecipeRepository(recipe),
        ),
        authRepositoryProvider.overrideWithValue(_FakeAuth(uid)),
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
}

void main() {
  testWidgets('expanded window renders the v2 layout, not the v1 hero', (
    tester,
  ) async {
    await _pump(tester);

    // v2 furniture.
    expect(find.text('Method'), findsOneWidget);
    expect(find.text('TOTAL'), findsOneWidget);
    expect(find.text('LONGEST WAIT'), findsOneWidget);
    // The version line doubles as the history opener.
    expect(find.textContaining('Version 2'), findsOneWidget);
    // Two cook-mode entry points, both live since Phase 27's cook mode landed:
    // header band + teaser panel.
    expect(find.text('Start cooking'), findsNWidgets(2));
    for (final button in tester.widgetList<ButtonStyleButton>(
      find.ancestor(
        of: find.text('Start cooking'),
        matching: find.byType(ButtonStyleButton),
      ),
    )) {
      expect(button.onPressed, isNotNull);
    }
    // v1 furniture must be gone.
    expect(find.text('Instructions'), findsNothing);
    expect(find.byType(SliverAppBar), findsNothing);
  });

  testWidgets('facts strip formats times and longest wait', (tester) async {
    await _pump(tester);

    expect(find.text('1 h 10 m'), findsOneWidget); // total 70
    expect(find.text('40 min'), findsOneWidget); // cook
    // Three "30 min": the Hands on cell, the Longest wait cell (= the longest
    // single step duration), and step 1's own duration chip.
    expect(find.text('30 min'), findsNWidgets(3));
  });

  testWidgets('ticking an ingredient updates the gathered counter', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('0 of 2 gathered'), findsOneWidget);
    // Sentence-cased at render from the lowercase DB value.
    await tester.tap(
      find.textContaining('Boneless chicken thigh', findRichText: true),
    );
    await tester.pump();
    expect(find.text('1 of 2 gathered'), findsOneWidget);

    // Clear checks resets it.
    await tester.tap(find.text('Clear checks'));
    await tester.pump();
    expect(find.text('0 of 2 gathered'), findsOneWidget);
  });

  testWidgets('ticking a step updates the done counter and collapses chips', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.textContaining('0 of 2 done'), findsOneWidget);
    // The full card shows the tip; ticking collapses it away.
    expect(find.textContaining('Longer is better.'), findsOneWidget);

    await tester.tap(find.text('Marinate the skewers.'));
    await tester.pump();

    expect(find.textContaining('1 of 2 done'), findsOneWidget);
    expect(find.textContaining('Longer is better.'), findsNothing);
  });

  testWidgets('servings stepper rescales and recolours quantities', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('600 g'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    // 4 → 5 servings: 600 × 1.25.
    expect(find.text('750 g'), findsOneWidget);
    expect(find.textContaining('Scaled from 4'), findsOneWidget);
  });

  // B066: `quantity` is nullable and the editor reaches that state by accident
  // — typing `1/2` fails the parse and saves the unit alone. The gutter's
  // fallback chain is quantity+unit → unit → note → `—`, and the note rides
  // with the name unless it is the only thing the gutter has.
  testWidgets('the quantity gutter falls back through all four states', (
    tester,
  ) async {
    await _pump(
      tester,
      recipe: _recipe.copyWith(
        servings: 4,
        ingredientGroups: const [
          IngredientGroup(
            id: 'g1',
            recipeId: 'r1',
            name: 'Marinade',
            ingredients: [
              // Unit, no quantity: the unit must not vanish (v1 prints it).
              Ingredient(id: 'i1', groupId: 'g1', unit: 'cup', name: 'yoghurt'),
              // Unit AND note, no quantity: the unit takes the gutter and the
              // note goes beside the name, so neither is lost.
              Ingredient(
                id: 'i2',
                groupId: 'g1',
                unit: 'tbsp',
                name: 'ghee',
                note: 'melted',
              ),
              // Note only: it is the quantity, and must not also appear twice.
              Ingredient(
                id: 'i3',
                groupId: 'g1',
                name: 'salt',
                note: 'to taste',
              ),
              // Nothing at all.
              Ingredient(id: 'i4', groupId: 'g1', name: 'coriander'),
            ],
          ),
        ],
      ),
    );

    expect(find.text('cup'), findsOneWidget);
    expect(find.text('tbsp'), findsOneWidget);
    expect(find.textContaining('Ghee (melted)', findRichText: true), findsOne);
    // The note-as-quantity row shows it once, in the gutter — not beside the
    // name as well.
    expect(find.text('to taste'), findsOneWidget);
    expect(
      find.textContaining('Salt (to taste)', findRichText: true),
      findsNothing,
    );
    expect(find.text('—'), findsOneWidget); // coriander
  });

  // The facts strip divides a fixed width between six cells and the rail holds
  // a fixed 86px quantity gutter, so both are the shape that overflowed three
  // times on the card (B001/B002/B016). A RenderFlex overflow throws in a
  // widget test, so pumping the whole page is the assertion.
  group('layout envelope', () {
    for (final width in [1000.0, 1440.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('no overflow at ${width}px, textScale $scale', (
          tester,
        ) async {
          await _pump(tester, size: Size(width, 2400), textScale: scale);
          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}
