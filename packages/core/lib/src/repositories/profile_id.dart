import 'package:supabase_flutter/supabase_flutter.dart';

/// Resolves the signed-in account to its `profiles.id` (Phase 35b).
///
/// Until Phase 35b those were the same uuid: `profiles.id` was a foreign key to
/// `auth.users(id)`, so every repository could write `auth.currentUser!.id`
/// straight into an `owner_id` / `user_id` column. The decoupling keeps that
/// true for every member — `handle_new_user` still writes `id = new.id` — with
/// exactly one exception, and it is the exception the whole phase exists for: a
/// member who has **claimed an imported chef page** owns content under the
/// claimed profile's id, which is not their auth uid.
///
/// For that person, writing the auth uid into `user_id` does not fail loudly.
/// The old profile survives the claim as a `merged_into` tombstone, so the
/// foreign key still resolves and the row is merely *denied* by RLS
/// (`user_id = current_profile_id()`) — a 42501 on an insert, and on an update
/// or delete the silent zero rows of Gotcha 2. So the client has to ask the
/// database who it is rather than assume.
///
/// One RPC per session, cached against the auth user id so a sign-out or an
/// account switch re-resolves. `current_profile_id()` is the same `security
/// definer` function every RLS policy calls, so the client and the policies can
/// never disagree about the answer.
///
/// **There is exactly one of these per session, and that is load-bearing.**
/// Two instances would hold two caches, and the moment they could disagree is
/// the moment that matters: an approved claim moves the account's link without
/// changing its auth uid, so a resolver that keys only on the auth uid keeps
/// returning the old profile id until something clears it. One cache means one
/// [invalidate] clears every reader. See `profileIdResolverProvider`.
class ProfileIdResolver {
  ProfileIdResolver(this._client);

  final SupabaseClient _client;

  String? _forAuthId;
  String? _profileId;

  /// The current user's profile id, or null when signed out.
  ///
  /// Null-returning rather than throwing, for the signed-out-reachable paths
  /// (Gotcha 9) — `logView`, `myLiked`, `mySaved`, `myRating` all sit on screens
  /// a visitor can open without an account.
  Future<String?> currentOrNull() async {
    final authId = _client.auth.currentUser?.id;
    if (authId == null) {
      _forAuthId = null;
      _profileId = null;
      return null;
    }
    if (_forAuthId == authId && _profileId != null) return _profileId;

    final id = await _client.rpc('current_profile_id') as String?;
    _forAuthId = authId;
    _profileId = id;
    return id;
  }

  /// The current user's profile id, or `StateError` when signed out.
  ///
  /// The replacement for `SupabaseRecipeRepository._uid`, and it throws the same
  /// message on purpose: `friendlyError()` matches on it (Gotcha 9), and the
  /// detail chips send a signed-out visitor to `/auth` rather than letting it
  /// surface.
  ///
  /// It also throws when a signed-in account has **no** profile row — a state
  /// the `handle_new_user` trigger plus 0001's B015 backfill exist to make
  /// impossible, so reaching it means the database is broken rather than the
  /// user signed out. Saying `Not authenticated` there is a small lie in a state
  /// that should never occur, and it beats a null-pointer further down.
  Future<String> require() async {
    final id = await currentOrNull();
    if (id == null) throw StateError('Not authenticated.');
    return id;
  }

  /// Forget the cached answer. Called after anything that can move the link —
  /// today only an approved claim, which is an administrative action, so this is
  /// here for the client that will eventually observe one.
  void invalidate() {
    _forAuthId = null;
    _profileId = null;
  }
}
