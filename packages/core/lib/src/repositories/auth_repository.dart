import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:core/src/repositories/profile_id.dart';

/// What a successful [AuthRepository.signUp] left behind (UX-018).
///
/// With email confirmation **on** — the hosted project's default — GoTrue
/// creates the user and returns **no session**: the account exists, nobody is
/// signed in, and the next step is the confirmation mail. With it off (the
/// local stack's `config.toml`) the same call signs the user in. The UI has to
/// say different things in the two cases, so the repository reports which one
/// happened instead of the screen guessing from the auth stream.
enum SignUpOutcome {
  /// A session came back: the user is signed in.
  signedIn,

  /// No session: the account waits on the confirmation email.
  confirmEmail,
}

/// Authentication contract. UI depends on this, not on Supabase directly.
abstract interface class AuthRepository {
  /// The currently authenticated user id, or null.
  ///
  /// This is the **auth** id. It is the right answer for "is anyone signed in"
  /// and for the storage bucket, whose folders are namespaced by it — and the
  /// wrong one for any row keyed on a `profiles` id. Use [currentProfileId] for
  /// those; see [ProfileIdResolver] for why the two parted company.
  String? get currentUserId;

  /// The signed-in account's `profiles.id`, or null when signed out.
  ///
  /// Equal to [currentUserId] for every member and different for exactly one
  /// person: a member who has claimed an imported chef page (Phase 35b).
  Future<String?> currentProfileId();

  /// Emits on sign-in / sign-out.
  Stream<AuthState> authStateChanges();

  Future<void> signIn({required String email, required String password});

  Future<SignUpOutcome> signUp({
    required String email,
    required String password,
    required String displayName,
  });

  Future<void> signOut();
}

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._client, {ProfileIdResolver? profileIds})
    : _profileIds = profileIds ?? ProfileIdResolver(_client);

  final SupabaseClient _client;

  /// The same instance the recipe repository holds — see
  /// [ProfileIdResolver]'s class comment for why two caches would be a bug
  /// rather than a duplication.
  final ProfileIdResolver _profileIds;

  @override
  String? get currentUserId => _client.auth.currentUser?.id;

  @override
  Future<String?> currentProfileId() => _profileIds.currentOrNull();

  @override
  Stream<AuthState> authStateChanges() => _client.auth.onAuthStateChange;

  @override
  Future<void> signIn({required String email, required String password}) async {
    await _client.auth.signInWithPassword(email: email, password: password);
  }

  @override
  Future<SignUpOutcome> signUp({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final response = await _client.auth.signUp(
      email: email,
      password: password,
      data: {'display_name': displayName},
    );
    return response.session == null
        ? SignUpOutcome.confirmEmail
        : SignUpOutcome.signedIn;
  }

  @override
  Future<void> signOut() => _client.auth.signOut();
}
