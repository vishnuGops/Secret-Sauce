// OPT-T3's last gap: the auth screen had no test at all, on the one path where
// a wrong branch means someone cannot get into the app.
//
// Driven through the **real router**, because half of what matters here is the
// wiring: `?mode=signup` has to open the sign-up side (the top bar offers both
// doors and they must not land on the same one), and a successful submit has to
// leave the screen — `_submit` calls `context.canPop()`, which asserts without a
// GoRouter in the tree, so a test that pumps the widget bare cannot see that
// path at all.
import 'package:app/features/auth/auth_screen.dart';
import 'package:app/routing/app_router.dart';
import 'package:app/routing/auth_return.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
// Directly, not through core's barrel: the barrel re-exports only the two auth
// *types* the UI renders, and this test needs the exception the repository
// throws.
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

class _FakeAuth implements AuthRepository {
  _FakeAuth({
    this.failWith,
    this.signUpOutcome = SignUpOutcome.signedIn,
    this.uid,
  });

  /// Non-null for an already signed-in visitor.
  final String? uid;

  final Object? failWith;

  /// What a successful sign-up reports — [SignUpOutcome.confirmEmail] models
  /// the hosted project, where GoTrue returns no session (UX-018).
  final SignUpOutcome signUpOutcome;
  final List<String> calls = [];

  @override
  String? get currentUserId => uid;

  // Phase 35b: `profiles.id` and the auth uid are the same value for a member,
  // which every fixture in this file is.
  @override
  Future<String?> currentProfileId() async => null;

  @override
  Stream<AuthState> authStateChanges() => const Stream.empty();

  @override
  Future<void> signIn({required String email, required String password}) async {
    calls.add('signIn:$email');
    if (failWith != null) throw failWith!;
  }

  @override
  Future<SignUpOutcome> signUp({
    required String email,
    required String password,
    required String displayName,
  }) async {
    calls.add('signUp:$email:$displayName');
    if (failWith != null) throw failWith!;
    return signUpOutcome;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}

/// Discover is where a successful submit lands, so it has to resolve — with
/// nothing in it, since this test is about the door, not the room.
class _FakeDiscover implements DiscoverRepository {
  // Phase 35c: the corpus surface. Empty in every fixture here — these tests are
  // about Discover and the ranked shelves, which exclude imported content by
  // construction.
  @override
  Future<List<Recipe>> corpus({
    int limit = kRecipePageSize,
    int offset = 0,
    String? cuisine,
  }) async => const [];

  @override
  Future<int> corpusCount() async => 0;

  @override
  Future<List<Recipe>> popular({
    int limit = kRecipePageSize,
    int offset = 0,
  }) async => const [];

  @override
  Future<List<Recipe>> trending({
    int limit = kRecipePageSize,
    int offset = 0,
  }) async => const [];

  @override
  Future<List<Recipe>> recent({
    int limit = kRecipePageSize,
    int offset = 0,
  }) async => const [];

  // Phase 36c: the category filter. Empty, like every other read here.
  @override
  Future<List<Recipe>> byCategories(
    List<String> categories, {
    int limit = kRecipePageSize,
    int offset = 0,
  }) async => const [];

  @override
  Future<List<Recipe>> search(
    String query, {
    int limit = kRecipePageSize,
    int offset = 0,
  }) async => const [];

  @override
  Future<List<Recipe>> quick({
    int limit = kRecipePageSize,
    int offset = 0,
  }) async => const [];

  @override
  Future<List<Recipe>> projects({
    int limit = kRecipePageSize,
    int offset = 0,
  }) async => const [];

  @override
  Future<List<Recipe>> mostForked({
    int limit = kRecipePageSize,
    int offset = 0,
  }) async => const [];

  @override
  Future<int> publicCount() async => 0;
}

Future<GoRouter> _pumpAt(
  WidgetTester tester,
  String location,
  _FakeAuth auth,
) async {
  tester.view.physicalSize = const Size(1000, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      discoverRepositoryProvider.overrideWithValue(_FakeDiscover()),
    ],
  );
  addTearDown(container.dispose);

  final router = container.read(appRouterProvider);
  router.go(location);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

String _location(GoRouter router) =>
    router.routerDelegate.currentConfiguration.uri.path;

Future<void> _fill(
  WidgetTester tester, {
  required String email,
  required String password,
  String? name,
}) async {
  if (name != null) {
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Display name'),
      name,
    );
  }
  await tester.enterText(find.widgetWithText(TextFormField, 'Email'), email);
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Password'),
    password,
  );
}

void main() {
  testWidgets('/auth opens the sign-in side', (tester) async {
    await _pumpAt(tester, Routes.auth, _FakeAuth());

    expect(find.byType(AuthScreen), findsOneWidget);
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Display name'), findsNothing);
  });

  testWidgets('/auth?mode=signup opens the sign-up side', (tester) async {
    await _pumpAt(tester, Routes.signUp, _FakeAuth());

    expect(find.text('Create your account'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Display name'), findsOneWidget);
  });

  testWidgets('the toggle switches sides after the initial mode', (
    tester,
  ) async {
    await _pumpAt(tester, Routes.auth, _FakeAuth());

    await tester.tap(find.text("Don't have an account? Sign up"));
    await tester.pumpAndSettle();

    expect(find.text('Create your account'), findsOneWidget);
  });

  testWidgets('an invalid form never reaches the repository', (tester) async {
    final auth = _FakeAuth();
    await _pumpAt(tester, Routes.auth, auth);

    await _fill(tester, email: 'not-an-email', password: 'short');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(auth.calls, isEmpty);
    expect(find.text('Enter a valid email'), findsOneWidget);
    expect(find.text('Min 6 characters'), findsOneWidget);
  });

  testWidgets('a valid sign-up sends the display name and leaves the screen', (
    tester,
  ) async {
    final auth = _FakeAuth();
    final router = await _pumpAt(tester, Routes.signUp, auth);

    await _fill(
      tester,
      email: 'cook@example.test',
      password: 'good-password',
      name: 'Dara',
    );
    await tester.tap(find.text('Sign up'));
    await tester.pumpAndSettle();

    expect(auth.calls, ['signUp:cook@example.test:Dara']);
    expect(_location(router), Routes.discover);
  });

  testWidgets('a rejected sign-in shows the mapped message and stays put', (
    tester,
  ) async {
    final auth = _FakeAuth(
      failWith: const AuthException('Invalid login credentials'),
    );
    final router = await _pumpAt(tester, Routes.auth, auth);

    await _fill(tester, email: 'cook@example.test', password: 'good-password');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('Invalid login credentials'), findsOneWidget);
    expect(find.textContaining('AuthException'), findsNothing);
    expect(
      _location(router),
      Routes.auth,
      reason: 'a failed sign-in navigated',
    );
  });

  // UX-015: no AutofillGroup, no hints, and Enter did nothing on the web.
  TextField textField(WidgetTester tester, String label) => tester.widget(
    find.descendant(
      of: find.widgetWithText(TextFormField, label),
      matching: find.byType(TextField),
    ),
  );

  testWidgets('sign-in fields carry autofill hints and keyboard actions', (
    tester,
  ) async {
    await _pumpAt(tester, Routes.auth, _FakeAuth());

    expect(find.byType(AutofillGroup), findsOneWidget);
    final email = textField(tester, 'Email');
    final password = textField(tester, 'Password');
    expect(email.autofillHints, [AutofillHints.email]);
    expect(email.textInputAction, TextInputAction.next);
    expect(password.autofillHints, [AutofillHints.password]);
    expect(password.textInputAction, TextInputAction.done);
  });

  testWidgets('sign-up asks for a new password and a name', (tester) async {
    await _pumpAt(tester, Routes.signUp, _FakeAuth());

    final name = textField(tester, 'Display name');
    expect(name.autofillHints, [AutofillHints.name]);
    expect(name.textInputAction, TextInputAction.next);
    expect(textField(tester, 'Email').autofillHints, [AutofillHints.email]);
    expect(textField(tester, 'Password').autofillHints, [
      AutofillHints.newPassword,
    ]);
  });

  testWidgets('Enter in the password field submits', (tester) async {
    final auth = _FakeAuth();
    final router = await _pumpAt(tester, Routes.auth, auth);

    // `_fill` types the password last, so it holds the focus.
    await _fill(tester, email: 'cook@example.test', password: 'good-password');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(auth.calls, ['signIn:cook@example.test']);
    expect(_location(router), Routes.discover);
  });

  testWidgets('Enter on an invalid form validates and sends nothing', (
    tester,
  ) async {
    final auth = _FakeAuth();
    await _pumpAt(tester, Routes.auth, auth);

    await _fill(tester, email: 'nope', password: 'short');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(auth.calls, isEmpty);
    expect(find.text('Enter a valid email'), findsOneWidget);
  });

  // B131 / UX-002. Every entry to `/auth` is a `go`, so there is nothing to pop
  // and the AppBar used to draw no back button: a stranded phone user.
  testWidgets('Back leaves a cold /auth for Discover', (tester) async {
    final router = await _pumpAt(tester, Routes.auth, _FakeAuth());

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(_location(router), Routes.discover);
  });

  // Phase 37 review: Back ignored `from`, so a visitor who changed their mind
  // lost the recipe they came from — but a guarded `from` must not loop.
  testWidgets('Back returns to an open from', (tester) async {
    final router = await _pumpAt(
      tester,
      authLocation(from: '/legal/terms'),
      _FakeAuth(),
    );
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(_location(router), '/legal/terms');
  });

  testWidgets('Back never returns to a guarded from, which would loop', (
    tester,
  ) async {
    final router = await _pumpAt(
      tester,
      authLocation(from: Routes.myRecipes),
      _FakeAuth(),
    );
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(_location(router), Routes.discover);
  });

  // UX-017. Like, Fork, Rate and every guarded route used to drop the visitor
  // on Discover after signing in. `/legal/terms` stands in for "the page they
  // were on": it needs no repository, so the landing is all this asserts.
  group('?from= (UX-017)', () {
    testWidgets('a guarded route sends its own location along', (tester) async {
      final router = await _pumpAt(tester, Routes.myRecipes, _FakeAuth());

      final uri = router.routerDelegate.currentConfiguration.uri;
      expect(uri.path, Routes.auth);
      expect(uri.queryParameters['from'], Routes.myRecipes);
    });

    testWidgets('a sign-in returns to where the visitor came from', (
      tester,
    ) async {
      final auth = _FakeAuth();
      final router = await _pumpAt(
        tester,
        authLocation(from: '/legal/terms'),
        auth,
      );

      await _fill(
        tester,
        email: 'cook@example.test',
        password: 'good-password',
      );
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();

      expect(auth.calls, ['signIn:cook@example.test']);
      expect(_location(router), '/legal/terms');
    });

    testWidgets('signed in, /auth?from= forwards straight there', (
      tester,
    ) async {
      final router = await _pumpAt(
        tester,
        authLocation(from: '/legal/terms'),
        _FakeAuth(uid: 'me'),
      );

      expect(_location(router), '/legal/terms');
    });

    testWidgets('an off-site from is ignored: Discover, not the link', (
      tester,
    ) async {
      final router = await _pumpAt(
        tester,
        '${Routes.auth}?from=${Uri.encodeQueryComponent('https://evil.test/')}',
        _FakeAuth(),
      );

      await _fill(
        tester,
        email: 'cook@example.test',
        password: 'good-password',
      );
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();

      expect(_location(router), Routes.discover);
    });
  });

  // UX-018. With email confirmation on (the hosted default) GoTrue returns no
  // session; the screen used to leave anyway, dropping a signed-out user on
  // Discover with no word about the mail.
  group('sign-up needing confirmation (UX-018)', () {
    testWidgets('says check your inbox, and stays', (tester) async {
      final auth = _FakeAuth(signUpOutcome: SignUpOutcome.confirmEmail);
      final router = await _pumpAt(tester, Routes.signUp, auth);

      await _fill(
        tester,
        email: 'cook@example.test',
        password: 'good-password',
        name: 'Dara',
      );
      await tester.tap(find.text('Sign up'));
      await tester.pumpAndSettle();

      expect(find.text('Check your inbox'), findsOneWidget);
      expect(find.textContaining('cook@example.test'), findsOneWidget);
      expect(_location(router), Routes.auth);

      await tester.tap(find.text('Back to sign in'));
      await tester.pumpAndSettle();
      expect(find.text('Welcome back'), findsOneWidget);
    });

    for (final width in [390.0, 1440.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('the inbox state fits at ${width.toInt()} × $scale', (
          tester,
        ) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

          await _pumpAt(
            tester,
            Routes.signUp,
            _FakeAuth(signUpOutcome: SignUpOutcome.confirmEmail),
          );
          await _fill(
            tester,
            email: 'a-rather-long-address@example.test',
            password: 'good-password',
            name: 'Dara',
          );
          await tester.ensureVisible(find.text('Sign up'));
          await tester.tap(find.text('Sign up'));
          await tester.pumpAndSettle();

          expect(find.text('Check your inbox'), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}
