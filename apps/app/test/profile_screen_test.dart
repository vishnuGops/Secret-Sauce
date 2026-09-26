// `/profile` had no test at all (32e1) — the only screen with a sign-out button
// on it, and the one place a wrong branch strands someone on a page the router
// then bounces to `/auth`.
//
// Driven through the real router and the real providers: the overrides swap the
// two **repositories**, so `myProfileProvider`'s own wiring (it watches
// `currentUserIdProvider`, which watches the auth stream) is exercised rather
// than stubbed out — the same choice `recipe_detail_test.dart` makes.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:app/features/profile/edit_profile_dialog.dart';
import 'package:app/features/profile/profile_screen.dart';
import 'package:app/features/recipe_editor/recipe_editor_providers.dart';
import 'package:app/routing/app_router.dart';
import 'package:app/widgets/legal_footer.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

/// A 1x1 PNG: real image bytes, so the dialog's `Image.memory` preview
/// decodes rather than throwing into the test.
final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
  '+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);

class _FakeAuth implements AuthRepository {
  _FakeAuth(this.uid, {this.profileId});

  String? uid;
  int signOuts = 0;

  /// `profiles.id` when it differs from the auth uid: a member who claimed an
  /// imported chef page (Phase 35b). Null means "the same as [uid]".
  final String? profileId;

  @override
  String? get currentUserId => uid;

  // Phase 35b: the profile a screen shows is keyed on `profiles.id`, which is
  // the auth uid for a member. The fake states that equality rather than
  // inheriting it, so a test can make them differ.
  @override
  Future<String?> currentProfileId() async =>
      uid == null ? null : profileId ?? uid;

  @override
  Stream<AuthState> authStateChanges() => const Stream.empty();

  @override
  Future<void> signOut() async {
    signOuts++;
    uid = null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}

class _FakeProfiles implements ProfileRepository {
  _FakeProfiles({this.profile, this.error, this.hang = false});

  /// Mutable: a successful [updateMine] replaces it, so a re-read after the
  /// save returns what the server would.
  Profile? profile;
  final Object? error;

  /// Never completes — the loading state has to be reachable without a race.
  final bool hang;

  int reads = 0;

  /// Every profile handed to [updateMine], in order.
  final List<Profile> updates = [];

  /// Thrown by [updateMine] when set.
  Object? updateError;

  /// When set, [updateMine] waits on it: the saving state, held open.
  Completer<void>? updateGate;

  /// When set, [getById] waits on it — a refresh held in flight.
  Completer<void>? readGate;

  @override
  Future<Profile?> getById(String id) async {
    reads++;
    if (readGate != null) await readGate!.future;
    if (hang) return Completer<Profile?>().future;
    if (error != null) return Future.error(error!);
    return Future.value(profile);
  }

  @override
  Future<Profile> updateMine(Profile next) async {
    updates.add(next);
    if (updateGate != null) await updateGate!.future;
    if (updateError != null) throw updateError!;
    profile = next;
    return next;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}

/// Records avatar uploads and hands back a public URL, the shape
/// `StorageService` really returns. Implemented rather than subclassed: the
/// real one needs a `SupabaseClient`.
class _FakeStorage implements StorageService {
  _FakeStorage({this.profiles});

  /// When set, each delete records how many profile writes had landed by
  /// then — the order B141 depends on.
  final _FakeProfiles? profiles;

  /// (fileName, byte length) per upload.
  final List<(String, int)> uploads = [];

  /// (public URL, profile writes so far) per `deleteOwnAvatar` call.
  final List<(String, int)> deletes = [];

  /// Thrown by [deleteOwnAvatar] when set.
  Object? deleteError;

  @override
  Future<void> deleteOwnAvatar(String publicUrl) async {
    deletes.add((publicUrl, profiles?.updates.length ?? -1));
    if (deleteError != null) throw deleteError!;
  }

  @override
  Future<String> uploadAvatar({
    required String fileName,
    required List<int> bytes,
    String contentType = 'image/jpeg',
  }) async {
    uploads.add((fileName, bytes.length));
    return 'https://cdn.test/$fileName';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}

late GoRouter _router;

Future<_FakeAuth> _pump(
  WidgetTester tester, {
  required _FakeProfiles profiles,
  String? uid = 'u1',
  String? profileId,
  double? width,
  double height = 900,
  double textScale = 1.0,
  ImagePickFn? pick,
  StorageService? storage,
}) async {
  if (width != null) {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }
  final auth = _FakeAuth(uid, profileId: profileId);
  final router =
      _router = GoRouter(
        initialLocation: Routes.profile,
        routes: [
          GoRoute(
            path: Routes.profile,
            builder: (_, __) => const ProfileScreen(),
          ),
          GoRoute(
            path: Routes.chefPattern,
            builder:
                (_, state) =>
                    Scaffold(body: Text('CHEF ${state.pathParameters['id']}')),
          ),
          GoRoute(
            path: Routes.discover,
            builder: (_, __) => const Scaffold(body: Text('DISCOVER')),
          ),
          GoRoute(
            path: Routes.auth,
            builder: (_, __) => const Scaffold(body: Text('AUTH SCREEN')),
          ),
          GoRoute(
            path: Routes.newRecipe,
            builder: (_, __) => const Scaffold(body: Text('NEW RECIPE')),
          ),
        ],
      );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        profileRepositoryProvider.overrideWithValue(profiles),
        if (pick != null) imagePickerProvider.overrideWithValue(pick),
        if (storage != null) storageServiceProvider.overrideWithValue(storage),
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
  return auth;
}

const _amara = Profile(
  id: 'u1',
  displayName: 'Amara Baptiste',
  bio: 'Sunday cook, weekday improviser.',
  chefTier: ChefTier.sousChef,
  chefScore: 1234,
  publicRecipeCount: 3,
);

/// Opens the editor from a loaded profile screen.
Future<void> _openEditor(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.tap(find.text('Edit profile'));
  await tester.pumpAndSettle();
  expect(find.byType(EditProfileDialog), findsOneWidget);
}

Finder get _nameField => find.widgetWithText(TextFormField, 'Display name');
Finder get _bioField => find.widgetWithText(TextFormField, 'Bio');
Finder get _saveButton => find.widgetWithText(FilledButton, 'Save');

void main() {
  testWidgets('shows a spinner while the profile is loading', (tester) async {
    await _pump(tester, profiles: _FakeProfiles(hang: true));
    await tester.pump();

    expect(find.byType(LoadingView), findsOneWidget);
    expect(find.text('Sign out'), findsNothing);
  });

  testWidgets('a failed read is an ErrorView, not an empty profile', (
    tester,
  ) async {
    await _pump(tester, profiles: _FakeProfiles(error: Exception('offline')));
    await tester.pumpAndSettle();

    expect(find.byType(ErrorView), findsOneWidget);
    // `friendlyError` is the only thing that renders a raw exception (OPT-A4),
    // so the screen must not be printing the object.
    expect(find.textContaining('Exception:'), findsNothing);
  });

  testWidgets('renders the profile it loaded', (tester) async {
    await _pump(
      tester,
      profiles: _FakeProfiles(
        profile: const Profile(
          id: 'u1',
          displayName: 'Amara Baptiste',
          bio: 'Sunday cook, weekday improviser.',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Amara Baptiste'), findsOneWidget);
    expect(find.text('Sunday cook, weekday improviser.'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
  });

  testWidgets('with no avatar it falls back to the first initial', (
    tester,
  ) async {
    await _pump(
      tester,
      profiles: _FakeProfiles(
        profile: const Profile(id: 'u1', displayName: 'amara'),
      ),
    );
    await tester.pumpAndSettle();

    // No seeded or simulated profile carries an `avatar_url` (a standing BL-5
    // limit), so this branch is the one every real render takes.
    expect(find.text('A'), findsOneWidget);
  });

  testWidgets('an unnamed cook still gets a name and a letter', (tester) async {
    await _pump(
      tester,
      profiles: _FakeProfiles(profile: const Profile(id: 'u1')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Unnamed cook'), findsOneWidget);
    expect(find.text('?'), findsOneWidget);
  });

  testWidgets('signed out, it offers the way in rather than an empty page', (
    tester,
  ) async {
    await _pump(tester, profiles: _FakeProfiles(), uid: null);
    await tester.pumpAndSettle();

    expect(find.text('Not signed in'), findsOneWidget);
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('AUTH SCREEN'), findsOneWidget);
    // UX-017: the way in remembers the way back.
    final uri = _router.routerDelegate.currentConfiguration.uri;
    expect(uri.path, Routes.auth);
    expect(uri.queryParameters['from'], Routes.profile);
  });

  testWidgets('sign out lands on /discover, not on `/`', (tester) async {
    final auth = await _pump(
      tester,
      profiles: _FakeProfiles(
        profile: const Profile(id: 'u1', displayName: 'Amara'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();

    expect(auth.signOuts, 1);
    // Staying on `/profile` would leave the redirect to bounce them to `/auth`,
    // and `/` is a redirect-only route with no screen behind it (the retired
    // home page) — Discover is the front door.
    expect(find.text('DISCOVER'), findsOneWidget);
  });

  testWidgets('New recipe goes to the editor', (tester) async {
    await _pump(
      tester,
      profiles: _FakeProfiles(
        profile: const Profile(id: 'u1', displayName: 'Amara'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('New recipe'));
    await tester.pumpAndSettle();

    expect(find.text('NEW RECIPE'), findsOneWidget);
  });

  testWidgets('the avatar is ChefAvatar, with the tier under the name', (
    tester,
  ) async {
    await _pump(tester, profiles: _FakeProfiles(profile: _amara));
    await tester.pumpAndSettle();

    // UX-053: a bare NetworkImage drew a blank circle for a broken URL;
    // ChefAvatar carries the error fallback (UX-032: one avatar).
    expect(find.byType(ChefAvatar), findsOneWidget);
    expect(find.byType(TierChip), findsOneWidget);
    expect(find.text('Sous Chef'), findsOneWidget);
  });

  group('edit profile (UX-038)', () {
    testWidgets('saves name and bio, and nothing else changes', (tester) async {
      final profiles = _FakeProfiles(profile: _amara);
      await _pump(tester, profiles: profiles);
      await _openEditor(tester);
      final readsBefore = profiles.reads;

      await tester.enterText(_nameField, '  Amara B.  ');
      await tester.enterText(_bioField, 'Braises, mostly.');
      await tester.tap(_saveButton);
      await tester.pumpAndSettle();

      // Exactly the two edited fields moved; id, tier, score and the photo
      // travel through unchanged (the name is trimmed).
      expect(profiles.updates, [
        _amara.copyWith(displayName: 'Amara B.', bio: 'Braises, mostly.'),
      ]);
      expect(find.byType(EditProfileDialog), findsNothing);
      // `myProfileProvider` was invalidated and re-read the profile.
      expect(profiles.reads, greaterThan(readsBefore));
      expect(find.text('Amara B.'), findsOneWidget);
      expect(find.text('Braises, mostly.'), findsOneWidget);
      expect(find.text('Profile updated'), findsOneWidget);
    });

    testWidgets('an empty bio is saved as null, not as an empty string', (
      tester,
    ) async {
      final profiles = _FakeProfiles(profile: _amara);
      await _pump(tester, profiles: profiles);
      await _openEditor(tester);

      await tester.enterText(_bioField, '   ');
      await tester.tap(_saveButton);
      await tester.pumpAndSettle();

      expect(profiles.updates.single.bio, isNull);
    });

    testWidgets('an empty name is refused before any write', (tester) async {
      final profiles = _FakeProfiles(profile: _amara);
      await _pump(tester, profiles: profiles);
      await _openEditor(tester);

      await tester.enterText(_nameField, '   ');
      await tester.tap(_saveButton);
      await tester.pumpAndSettle();

      expect(find.text('Enter a display name'), findsOneWidget);
      expect(profiles.updates, isEmpty);
      expect(find.byType(EditProfileDialog), findsOneWidget);
    });

    testWidgets('the fields mirror profiles_text_lengths', (tester) async {
      await _pump(tester, profiles: _FakeProfiles(profile: _amara));
      await _openEditor(tester);

      TextField field(Finder f) => tester.widget<TextField>(
        find.descendant(of: f, matching: find.byType(TextField)),
      );
      expect(field(_nameField).maxLength, 80);
      expect(field(_bioField).maxLength, 500);
    });

    testWidgets('a failed save stays open with a friendly message', (
      tester,
    ) async {
      final profiles = _FakeProfiles(profile: _amara)
        ..updateError = const PostgrestException(
          message: 'permission denied for table profiles',
          code: '42501',
        );
      await _pump(tester, profiles: profiles);
      await _openEditor(tester);

      await tester.enterText(_nameField, 'Amara B.');
      await tester.tap(_saveButton);
      await tester.pumpAndSettle();

      expect(find.byType(EditProfileDialog), findsOneWidget);
      expect(
        find.text('You do not have permission to do that.'),
        findsOneWidget,
      );
      expect(find.textContaining('PostgrestException'), findsNothing);
      // What the reader typed survives for the retry.
      expect(find.text('Amara B.'), findsWidgets);
      expect(
        tester.widget<FilledButton>(_saveButton).onPressed,
        isNotNull,
        reason: 'Save re-enables after a failure',
      );
    });

    testWidgets('Save is disabled while the save is in flight', (tester) async {
      final profiles = _FakeProfiles(profile: _amara)..updateGate = Completer();
      await _pump(tester, profiles: profiles);
      await _openEditor(tester);

      await tester.tap(_saveButton);
      await tester.pump();

      final save = find.ancestor(
        of: find.byType(CircularProgressIndicator),
        matching: find.byType(FilledButton),
      );
      expect(tester.widget<FilledButton>(save).onPressed, isNull);

      profiles.updateGate!.complete();
      await tester.pumpAndSettle();
      expect(profiles.updates, hasLength(1));
      expect(find.byType(EditProfileDialog), findsNothing);
    });

    testWidgets('a picked photo is uploaded on Save, not on pick', (
      tester,
    ) async {
      final profiles = _FakeProfiles(profile: _amara);
      final storage = _FakeStorage();
      await _pump(
        tester,
        profiles: profiles,
        pick: () async => _png,
        storage: storage,
      );
      await _openEditor(tester);

      await tester.tap(find.text('Add photo'));
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsWidgets); // previewed from memory
      expect(storage.uploads, isEmpty, reason: 'upload belongs to the save');

      await tester.tap(_saveButton);
      await tester.pumpAndSettle();

      expect(storage.uploads, hasLength(1));
      expect(storage.uploads.single.$1, startsWith('avatar_'));
      expect(storage.uploads.single.$2, _png.length);
      expect(
        profiles.updates.single,
        _amara.copyWith(
          avatarUrl: 'https://cdn.test/${storage.uploads.single.$1}',
        ),
      );
    });

    testWidgets('a pick abandoned with Cancel uploads nothing', (tester) async {
      final profiles = _FakeProfiles(profile: _amara);
      final storage = _FakeStorage();
      await _pump(
        tester,
        profiles: profiles,
        pick: () async => _png,
        storage: storage,
      );
      await _openEditor(tester);

      await tester.tap(find.text('Add photo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(EditProfileDialog), findsNothing);
      expect(storage.uploads, isEmpty);
      expect(profiles.updates, isEmpty);
    });

    testWidgets("an over-size pick is refused in the editor's words", (
      tester,
    ) async {
      final storage = _FakeStorage();
      await _pump(
        tester,
        profiles: _FakeProfiles(profile: _amara),
        pick: () async => Uint8List(kMaxUploadBytes + 1),
        storage: storage,
      );
      await _openEditor(tester);

      await tester.tap(find.text('Add photo'));
      await tester.pumpAndSettle();

      // The same sentence recipe_editor_test pins for the step photo.
      expect(
        find.text('That image is over 5 MB. Please pick a smaller one.'),
        findsOneWidget,
      );
      expect(find.text('Remove photo'), findsNothing);
      expect(storage.uploads, isEmpty);
    });

    testWidgets('Remove photo saves avatar_url as null', (tester) async {
      final profiles = _FakeProfiles(
        profile: _amara.copyWith(avatarUrl: 'https://cdn.test/old.jpg'),
      );
      final storage = _FakeStorage();
      await _pump(tester, profiles: profiles, storage: storage);
      await _openEditor(tester);

      await tester.tap(find.text('Remove photo'));
      await tester.pumpAndSettle();
      await tester.tap(_saveButton);
      await tester.pumpAndSettle();

      expect(profiles.updates.single.avatarUrl, isNull);
      expect(profiles.updates.single.displayName, _amara.displayName);
      expect(storage.uploads, isEmpty);
    });
  });

  // B141: Save only re-pointed `avatar_url`, so a replaced or removed photo
  // stayed public at its old URL. Which URLs are this account's to delete is
  // `StorageService.deleteOwnAvatar`'s call (storage_service_test.dart); these
  // pin *when* the dialog asks.
  group('the previous photo is deleted after a save (B141)', () {
    const oldUrl = 'https://cdn.test/avatars/u1/old.jpg';
    final withPhoto = _amara.copyWith(avatarUrl: oldUrl);

    Future<(_FakeProfiles, _FakeStorage)> open(
      WidgetTester tester, {
      Object? updateError,
      Object? deleteError,
    }) async {
      final profiles = _FakeProfiles(profile: withPhoto)
        ..updateError = updateError;
      final storage = _FakeStorage(profiles: profiles)
        ..deleteError = deleteError;
      await _pump(
        tester,
        profiles: profiles,
        pick: () async => _png,
        storage: storage,
      );
      await _openEditor(tester);
      return (profiles, storage);
    }

    testWidgets('a replaced photo: the old URL, once the save landed', (
      tester,
    ) async {
      final (profiles, storage) = await open(tester);

      await tester.tap(find.text('Change photo'));
      await tester.pumpAndSettle();
      await tester.tap(_saveButton);
      await tester.pumpAndSettle();

      expect(
        profiles.updates.single.avatarUrl,
        startsWith('https://cdn.test/avatar_'),
      );
      // (url, profile writes already landed): after the save, never before.
      expect(storage.deletes, [(oldUrl, 1)]);
    });

    testWidgets('a removed photo: the old URL, once the save landed', (
      tester,
    ) async {
      final (profiles, storage) = await open(tester);

      await tester.tap(find.text('Remove photo'));
      await tester.pumpAndSettle();
      await tester.tap(_saveButton);
      await tester.pumpAndSettle();

      expect(profiles.updates.single.avatarUrl, isNull);
      expect(storage.deletes, [(oldUrl, 1)]);
    });

    testWidgets('a save that leaves the photo alone deletes nothing', (
      tester,
    ) async {
      final (profiles, storage) = await open(tester);

      await tester.enterText(_nameField, 'Amara B.');
      await tester.tap(_saveButton);
      await tester.pumpAndSettle();

      expect(profiles.updates.single.avatarUrl, oldUrl);
      expect(storage.deletes, isEmpty);
    });

    testWidgets('a failed save deletes nothing — the profile still points '
        'at the old photo', (tester) async {
      final (profiles, storage) = await open(
        tester,
        updateError: const PostgrestException(
          message: 'permission denied for table profiles',
          code: '42501',
        ),
      );

      await tester.tap(find.text('Remove photo'));
      await tester.pumpAndSettle();
      await tester.tap(_saveButton);
      await tester.pumpAndSettle();

      expect(profiles.updates, hasLength(1));
      expect(find.byType(EditProfileDialog), findsOneWidget);
      expect(storage.deletes, isEmpty);
    });

    // B146: an upload whose profile write failed is on no profile, so B141's
    // cleanup never sees it. Closing the dialog, or a later save that
    // replaced it, deletes it.
    testWidgets('an upload left by a failed save goes when the dialog closes', (
      tester,
    ) async {
      final (profiles, storage) = await open(
        tester,
        updateError: const PostgrestException(message: 'nope', code: '500'),
      );

      await tester.tap(find.text('Change photo'));
      await tester.pumpAndSettle();
      await tester.tap(_saveButton);
      await tester.pumpAndSettle();
      expect(storage.deletes, isEmpty);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(EditProfileDialog), findsNothing);
      expect(storage.deletes, hasLength(1));
      expect(storage.deletes.single.$1, startsWith('https://cdn.test/avatar_'));
    });

    testWidgets('a later save deletes the stray upload it replaced', (
      tester,
    ) async {
      final (profiles, storage) = await open(
        tester,
        updateError: const PostgrestException(message: 'nope', code: '500'),
      );

      await tester.tap(find.text('Change photo'));
      await tester.pumpAndSettle();
      await tester.tap(_saveButton);
      await tester.pumpAndSettle();
      profiles.updateError = null;
      await tester.tap(find.text('Remove photo'));
      await tester.pumpAndSettle();
      await tester.tap(_saveButton);
      await tester.pumpAndSettle();

      expect(profiles.updates.last.avatarUrl, isNull);
      final urls = storage.deletes.map((d) => d.$1).toList();
      expect(urls, contains(oldUrl));
      expect(
        urls.where((u) => u.startsWith('https://cdn.test/avatar_')),
        hasLength(1),
      );
    });

    // Phase 38 review: web's browser Back is new route information, not a
    // pop, so `PopScope` is never asked and the dialog goes with its page
    // while a save is in flight. The upload may be what that save is about
    // to set, so dispose must not delete it — the save decides.
    Future<void> closeMidSave(WidgetTester tester) async {
      await tester.tap(find.text('Change photo'));
      await tester.pumpAndSettle();
      await tester.tap(_saveButton);
      await tester.pump();
      _router.go(Routes.discover);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(EditProfileDialog), findsNothing);
    }

    testWidgets('closed mid-save that lands: the new photo survives', (
      tester,
    ) async {
      final (profiles, storage) = await open(tester);
      profiles.updateGate = Completer();
      await closeMidSave(tester);
      expect(storage.deletes, isEmpty);

      profiles.updateGate!.complete();
      await tester.pumpAndSettle();
      final newUrl = profiles.updates.single.avatarUrl;
      expect(newUrl, startsWith('https://cdn.test/avatar_'));
      expect(storage.deletes.map((d) => d.$1), [oldUrl]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('closed mid-save that fails: the upload goes', (tester) async {
      final (profiles, storage) = await open(
        tester,
        updateError: const PostgrestException(message: 'nope', code: '500'),
      );
      profiles.updateGate = Completer();
      await closeMidSave(tester);

      profiles.updateGate!.complete();
      await tester.pumpAndSettle();
      final urls = storage.deletes.map((d) => d.$1).toList();
      expect(urls, hasLength(1));
      expect(urls.single, startsWith('https://cdn.test/avatar_'));
    });

    testWidgets('a failing delete does not fail the save or show an error', (
      tester,
    ) async {
      final (profiles, storage) = await open(
        tester,
        deleteError: Exception('storage down'),
      );

      await tester.tap(find.text('Change photo'));
      await tester.pumpAndSettle();
      await tester.tap(_saveButton);
      await tester.pumpAndSettle();

      expect(storage.deletes, hasLength(1));
      expect(find.byType(EditProfileDialog), findsNothing);
      expect(find.text('Profile updated'), findsOneWidget);
      expect(find.textContaining('storage down'), findsNothing);
      expect(
        find.text('Something went wrong. Please try again.'),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  });

  // Phase 38 review: while the profile refreshes the page shows the previous
  // row, and a dialog opened on it would write back a photo URL the last
  // save already deleted (B141). Edit waits for the refresh.
  testWidgets('Edit profile waits out a refresh', (tester) async {
    final profiles = _FakeProfiles(profile: _amara);
    await _pump(tester, profiles: profiles);
    await tester.pumpAndSettle();
    final edit = find.ancestor(
      of: find.text('Edit profile'),
      matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
    );
    expect(tester.widget<ButtonStyleButton>(edit).onPressed, isNotNull);

    profiles.readGate = Completer();
    ProviderScope.containerOf(
      tester.element(find.byType(ProfileScreen)),
    ).invalidate(myProfileProvider);
    await tester.pump();
    await tester.pump();
    expect(profiles.reads, 2, reason: 'the refresh is in flight');
    expect(tester.widget<ButtonStyleButton>(edit).onPressed, isNull);

    profiles.readGate!.complete();
    await tester.pumpAndSettle();
    expect(tester.widget<ButtonStyleButton>(edit).onPressed, isNotNull);
  });

  testWidgets('View my chef page opens /chef/<profiles.id>', (tester) async {
    // A claimed member: `profiles.id` is not the auth uid, and `/chef/:id`
    // takes the former (Phase 35b).
    await _pump(
      tester,
      uid: 'auth-uid',
      profileId: 'p-claimed',
      profiles: _FakeProfiles(profile: _amara.copyWith(id: 'p-claimed')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('View my chef page'));
    await tester.pumpAndSettle();

    expect(find.text('CHEF p-claimed'), findsOneWidget);
  });

  testWidgets('legal links are page content on compact only', (tester) async {
    await _pump(tester, profiles: _FakeProfiles(profile: _amara), width: 390);
    await tester.pumpAndSettle();
    // The one route a signed-in phone reader has to Privacy / Terms / Rights.
    expect(find.byType(LegalFooter), findsOneWidget);
  });

  testWidgets('wider, the web chrome carries the legal links instead', (
    tester,
  ) async {
    await _pump(tester, profiles: _FakeProfiles(profile: _amara), width: 1440);
    await tester.pumpAndSettle();
    expect(find.byType(LegalFooter), findsNothing);
  });

  testWidgets('at 1440 the page keeps a readable measure', (tester) async {
    await _pump(tester, profiles: _FakeProfiles(profile: _amara), width: 1440);
    await tester.pumpAndSettle();

    final button = tester.getRect(
      find.widgetWithText(FilledButton, 'Edit profile'),
    );
    expect(button.width, lessThanOrEqualTo(kProfileMaxWidth));
    // Centred, not left-aligned.
    expect((button.center.dx - 720).abs(), lessThan(1));
  });

  // UX-048: every control on the page is at least 48 × 48 (WCAG 2.5.8 via
  // Flutter's Android guideline, the stricter of the two it ships) — the
  // page, then the edit dialog with both photo buttons showing.
  for (final width in [390.0, 1440.0]) {
    testWidgets('every tap target meets the 48dp guideline at ${width}px', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        profiles: _FakeProfiles(profile: _amara),
        width: width,
        height: 1400,
        pick: () async => _png,
      );
      await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));

      await _openEditor(tester);
      await tester.tap(find.text('Add photo'));
      await tester.pumpAndSettle();
      expect(find.text('Remove photo'), findsOneWidget);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      handle.dispose();
    });
  }

  for (final width in <double>[390, 600, 1000, 1440]) {
    for (final scale in <double>[1.0, 2.0]) {
      testWidgets('fits at ${width}px, textScale $scale: page and dialog', (
        tester,
      ) async {
        await _pump(
          tester,
          profiles: _FakeProfiles(
            profile: _amara.copyWith(
              displayName: 'Amara Baptiste-Okonkwo de la Cruz',
              bio: 'Sunday cook, weekday improviser. ' * 6,
            ),
          ),
          width: width,
          textScale: scale,
          pick: () async => _png,
        );
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: 'page overflow at ${width}px @ ${scale}x',
        );

        await tester.ensureVisible(find.text('Edit profile'));
        await _openEditor(tester);
        // Both photo buttons on screen: the widest state of the avatar row.
        await tester.tap(find.text('Add photo'));
        await tester.pumpAndSettle();
        expect(find.text('Remove photo'), findsOneWidget);
        expect(
          tester.takeException(),
          isNull,
          reason: 'dialog overflow at ${width}px @ ${scale}x',
        );
      });
    }
  }
}
