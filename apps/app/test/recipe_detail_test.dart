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

class _FakeAuth implements AuthRepository {
  _FakeAuth(this.uid);

  final String? uid;

  @override
  String? get currentUserId => uid;

  @override
  Stream<AuthState> authStateChanges() => const Stream.empty();

  @override
  Future<void> signIn({required String email, required String password}) async {}

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
  _FakeRecipeRepository({this.liked = false, this.saved = false});

  bool liked;
  bool saved;

  final List<bool> likeWrites = [];
  final List<bool> saveWrites = [];
  int viewLogs = 0;

  @override
  Future<Recipe> getById(String id) async => _recipe;

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
  Future<List<Recipe>> listMine({int limit = kRecipePageSize, int offset = 0}) =>
      throw UnimplementedError();

  @override
  Future<List<Recipe>> listSharedWithMe({
    int limit = kRecipePageSize,
    int offset = 0,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> share({
    required String recipeId,
    required String userId,
    SharePermission permission = SharePermission.view,
  }) =>
      throw UnimplementedError();

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
}) async {
  final router = GoRouter(
    initialLocation: '/recipe/r1',
    routes: [
      GoRoute(
        path: '/recipe/:id',
        builder: (_, state) =>
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
        recipeRepositoryProvider.overrideWithValue(repo),
        authRepositoryProvider.overrideWithValue(_FakeAuth(uid)),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

void main() {
  testWidgets('signed out, tapping like goes to /auth and writes nothing',
      (tester) async {
    final repo = _FakeRecipeRepository();
    await _pump(tester, repo: repo, uid: null);

    await tester.tap(find.byIcon(Icons.favorite_border));
    await tester.pumpAndSettle();

    expect(find.text('AUTH SCREEN'), findsOneWidget);
    expect(repo.likeWrites, isEmpty,
        reason: 'a signed-out tap must not reach the repository');
  });

  testWidgets('signed out, tapping save goes to /auth and writes nothing',
      (tester) async {
    final repo = _FakeRecipeRepository();
    await _pump(tester, repo: repo, uid: null);

    await tester.tap(find.byIcon(Icons.bookmark_border));
    await tester.pumpAndSettle();

    expect(find.text('AUTH SCREEN'), findsOneWidget);
    expect(repo.saveWrites, isEmpty);
  });

  testWidgets('signed in and not yet liked: tap sends liked: true', (tester) async {
    final repo = _FakeRecipeRepository();
    await _pump(tester, repo: repo, uid: 'me');

    expect(find.byIcon(Icons.favorite_border), findsOneWidget);
    await tester.tap(find.byIcon(Icons.favorite_border));
    await tester.pumpAndSettle();

    expect(repo.likeWrites, [true]);
  });

  testWidgets('already liked: the icon is filled and the tap UNLIKES (B051)',
      (tester) async {
    final repo = _FakeRecipeRepository(liked: true);
    await _pump(tester, repo: repo, uid: 'me');

    // The filled variant is what `activeIcon` was for — it was dead until now.
    expect(find.byIcon(Icons.favorite), findsOneWidget);
    expect(find.byIcon(Icons.favorite_border), findsNothing);

    await tester.tap(find.byIcon(Icons.favorite));
    await tester.pumpAndSettle();

    expect(repo.likeWrites, [false],
        reason: 'the action must be a toggle, not a one-way like');
    expect(find.byIcon(Icons.favorite_border), findsOneWidget);
  });

  testWidgets('already saved: the icon is filled and the tap UNSAVES',
      (tester) async {
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
        reason: 'three engagement writes re-resolved the recipe; only the '
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
}
