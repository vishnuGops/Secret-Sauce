import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:core/src/models/profile.dart';

/// Read/update user profiles; used by sharing (user lookup) and profile screen.
abstract interface class ProfileRepository {
  Future<Profile?> getById(String id);

  /// Profiles whose display name contains [query], best match first (OPT-A5).
  ///
  /// Returns a **list** because `profiles.display_name` is not unique: the old
  /// exact-`ilike` + `limit(1)` silently picked one of the Daras and shared the
  /// recipe with them, reporting success either way. Deciding which one is a
  /// question only the person sharing can answer, so the repository ranks and
  /// the dialog asks.
  Future<List<Profile>> searchByName(String query, {int limit});

  Future<Profile> updateMine(Profile profile);
}

class SupabaseProfileRepository implements ProfileRepository {
  SupabaseProfileRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<Profile?> getById(String id) async {
    final row =
        await _client.from('profiles').select().eq('id', id).maybeSingle();
    return row == null ? null : Profile.fromJson(row);
  }

  @override
  Future<List<Profile>> searchByName(String query, {int limit = 10}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    // Profiles are world-readable; match anywhere in the name so "dara" finds
    // "Dara Okonkwo". The order here is only the tie-break — the ranking that
    // decides what the reader sees first happens below, because PostgREST
    // cannot order by "is this an exact match".
    final rows = await _client
        .from('profiles')
        .select()
        .ilike('display_name', '%${_escapeLike(trimmed)}%')
        .order('display_name', ascending: true)
        .limit(limit);

    final profiles = rows.map<Profile>(Profile.fromJson).toList();
    final needle = trimmed.toLowerCase();
    profiles.sort((a, b) {
      final byRank = _rank(a.displayName, needle) - _rank(b.displayName, needle);
      if (byRank != 0) return byRank;
      final byName = a.displayName.toLowerCase().compareTo(
            b.displayName.toLowerCase(),
          );
      // `id` last so two people with the same name keep a stable order between
      // calls rather than swapping under the reader's finger.
      return byName != 0 ? byName : a.id.compareTo(b.id);
    });
    return profiles;
  }

  /// 0 exact, 1 prefix, 2 anywhere — the order someone typing a name expects.
  static int _rank(String name, String lowercaseQuery) {
    final lower = name.toLowerCase();
    if (lower == lowercaseQuery) return 0;
    if (lower.startsWith(lowercaseQuery)) return 1;
    return 2;
  }

  /// `%` and `_` are SQL LIKE wildcards, so a name typed with either in it would
  /// otherwise match far more than the reader asked for — `_` alone matches any
  /// single character. Backslash is the default LIKE escape, so it has to be
  /// doubled first.
  static String _escapeLike(String value) => value
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');

  @override
  Future<Profile> updateMine(Profile profile) async {
    final row = await _client
        .from('profiles')
        .update({
          'display_name': profile.displayName,
          'avatar_url': profile.avatarUrl,
          'bio': profile.bio,
        })
        .eq('id', profile.id)
        .select()
        .single();
    return Profile.fromJson(row);
  }
}
