// B125/UX-001: the reading page's method list draws a step's photo.
//
// `steps.image_url` has been uploaded by the editor since Phase 33 and nothing
// rendered it. `MethodColumn` is placed by both detail layouts — compact (the
// cover-first page, below 1000px) and expanded (the 1140px page) — so each
// assertion runs at a width that selects each one. No seeded recipe carries a
// step photo, so the fixture points at a reserved-TLD address; the image never
// resolves under test, which is why these pump frames instead of settling
// (chef_badge_test's rule): which branch rendered is the thing under test.
//
// Cook mode's half of B125 lives in cook_mode_test.dart.
import 'package:app/features/recipe_detail/method_column.dart';
import 'package:app/features/recipe_detail/recipe_detail_screen.dart';
import 'package:app/routing/app_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const _kStepPhoto = 'https://example.test/step.jpg';

const _kPhotoStepText = 'Marinate the skewers.';

/// Step 1 has a photo, step 2 does not. No cover and no owner avatar, so every
/// `CachedNetworkImage` on the page is a step photo.
const _recipe = Recipe(
  id: 'r1',
  ownerId: 'someone-else',
  title: 'Suya-Spiced Lamb Skewers',
  description: 'Smoky skewers with a peanut-chilli crust.',
  prepMinutes: 30,
  cookMinutes: 40,
  servings: 4,
  visibility: RecipeVisibility.public,
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
          name: 'boneless lamb shoulder',
        ),
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
          text: _kPhotoStepText,
          durationMinutes: 30,
          tip: 'Longer is better.',
          imageUrl: _kStepPhoto,
        ),
        RecipeStep(id: 's2', groupId: 'sg1', text: 'Grill until charred.'),
      ],
    ),
  ],
);

final _noPhotos = _recipe.copyWith(
  stepGroups: [
    for (final g in _recipe.stepGroups)
      g.copyWith(steps: [for (final s in g.steps) s.copyWith(imageUrl: null)]),
  ],
);

class _FakeAuth implements AuthRepository {
  @override
  String? get currentUserId => null;

  @override
  Future<String?> currentProfileId() async => null;

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

class _FakeRecipeRepository implements RecipeRepository {
  _FakeRecipeRepository(this.recipe);

  final Recipe recipe;

  @override
  Future<Recipe> getById(String id) async => recipe;

  @override
  Future<Recipe?> findSummary(String id) async => null;

  @override
  Future<Recipe?> versionContent(String versionId) async => null;

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

  // Unused on this screen's read path.
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
  Future<String> fork(String sourceRecipeId) => throw UnimplementedError();

  @override
  Future<List<Recipe>> listMine({
    int limit = kRecipePageSize,
    int offset = 0,
  }) => throw UnimplementedError();

  @override
  Future<List<Recipe>> listSaved({
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
  Future<void> setRating(String recipeId, double rating) =>
      throw UnimplementedError();

  @override
  Future<void> clearRating(String recipeId) => throw UnimplementedError();
}

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump();
  }
}

Future<void> _pump(
  WidgetTester tester, {
  required Size size,
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
        authRepositoryProvider.overrideWithValue(_FakeAuth()),
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
  await _frames(tester);
}

void main() {
  // 390 selects the compact (cover-first) layout, 1440 the expanded one.
  const layouts = {'compact': Size(390, 844), 'expanded': Size(1440, 900)};

  for (final MapEntry(key: name, value: size) in layouts.entries) {
    group('$name detail', () {
      testWidgets('a step with a photo draws exactly one, its own', (
        tester,
      ) async {
        await _pump(tester, size: size);

        final photo = find.byType(CachedNetworkImage);
        expect(photo, findsOneWidget);
        expect(tester.widget<CachedNetworkImage>(photo).imageUrl, _kStepPhoto);
        // It belongs to step 1's row, not step 2's: the nearest tappable row
        // around the photo is the one holding step 1's text.
        final row =
            find
                .ancestor(
                  of: find.byType(StepPhoto),
                  matching: find.byType(InkWell),
                )
                .first;
        expect(
          find.descendant(of: row, matching: find.text(_kPhotoStepText)),
          findsOneWidget,
        );
        expect(
          find.descendant(of: row, matching: find.text('Grill until charred.')),
          findsNothing,
        );
      });

      testWidgets('steps without photos draw none, and no placeholder', (
        tester,
      ) async {
        await _pump(tester, size: size, recipe: _noPhotos);
        expect(find.byType(StepPhoto), findsNothing);
        expect(find.byType(CachedNetworkImage), findsNothing);
      });

      testWidgets('a done step collapses to one line, photo and all', (
        tester,
      ) async {
        await _pump(tester, size: size);
        expect(find.byType(CachedNetworkImage), findsOneWidget);

        await tester.ensureVisible(find.text(_kPhotoStepText));
        await tester.pump();
        await tester.tap(find.text(_kPhotoStepText));
        await _frames(tester);

        expect(find.text('1 of 2 done · tap a step to tick it off'), findsOne);
        expect(find.byType(CachedNetworkImage), findsNothing);
      });

      testWidgets('a publisher who asked for no images gets none', (
        tester,
      ) async {
        // The cover's rights rule (Phase 35c) covers a step's photo too.
        await _pump(
          tester,
          size: size,
          recipe: _recipe.copyWith(imageMode: ImageMode.none),
        );
        expect(find.byType(CachedNetworkImage), findsNothing);
      });
    });
  }

  test('displayStepImageUrl treats blank as absent', () {
    final step = _recipe.stepGroups.first.steps.first;
    expect(displayStepImageUrl(_recipe, step), _kStepPhoto);
    expect(displayStepImageUrl(_recipe, step.copyWith(imageUrl: '  ')), isNull);
    expect(displayStepImageUrl(_recipe, step.copyWith(imageUrl: null)), isNull);
  });

  // The envelope: a 4:3 photo at full text-column width, in both layouts, at
  // both text scales. 600 and 1000 are the compact/medium and medium/expanded
  // edges.
  group('envelope', () {
    for (final width in [390.0, 600.0, 1000.0, 1440.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('no overflow with a step photo at ${width}px, '
            'textScale $scale', (tester) async {
          await _pump(tester, size: Size(width, 900), textScale: scale);
          expect(
            find.byType(CachedNetworkImage, skipOffstage: false),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);

          // The photo's column is the step's text column: full width of it,
          // at 4:3 (plus the gap above it).
          final box = tester.getSize(
            find.byType(StepPhoto, skipOffstage: false),
          );
          expect(box.width, greaterThan(0));
          expect(
            box.height,
            moreOrLessEquals(
              box.width / StepPhoto.kAspectRatio + AppSpacing.smPlus,
              epsilon: 0.5,
            ),
          );
        });
      }
    }
  });
}
