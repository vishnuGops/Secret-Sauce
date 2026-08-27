import 'dart:math' as math;

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:core/src/models/profile.dart';

/// Ceiling on the rows [SupabaseProfileRepository.searchByName] ranks over.
///
/// Public so a test can state the boundary it is testing rather than restating
/// the number (32d3).
const int kProfileSearchMaxRows = 40;

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
    //
    // The window is deliberately **wider than [limit]** (B083, 32d3). Ranking
    // client-side over a server-side `limit(limit)` ranks the wrong set: the
    // server orders alphabetically, so with more contains-matches than the
    // dialog shows, an exact "Dara" alphabetically behind eight "Darabont"s
    // never arrives and cannot be promoted — the failure appears exactly at the
    // scale OPT-A5 was built for. Over-fetch, rank, then cut.
    final rows = await _client
        .from('profiles')
        .select()
        .ilike('display_name', '%${_escapeLike(trimmed)}%')
        .order('display_name', ascending: true)
        .limit(_searchWindow(limit));

    final profiles = rows.map<Profile>(Profile.fromJson).toList();
    final needle = trimmed.toLowerCase();
    profiles.sort((a, b) {
      final byRank =
          _rank(a.displayName, needle) - _rank(b.displayName, needle);
      if (byRank != 0) return byRank;
      final byName = a.displayName.toLowerCase().compareTo(
        b.displayName.toLowerCase(),
      );
      // `id` last so two people with the same name keep a stable order between
      // calls rather than swapping under the reader's finger.
      return byName != 0 ? byName : a.id.compareTo(b.id);
    });
    return profiles.length > limit ? profiles.sublist(0, limit) : profiles;
  }

  /// How many rows to rank over for a page of [limit].
  ///
  /// Three pages' worth, capped: the cap is what keeps a one-letter query from
  /// dragging the whole `profiles` table across the wire on a population of
  /// thousands. It bounds the fix rather than completing it — an exact match
  /// alphabetically behind [kProfileSearchMaxRows] contains-matches is still
  /// unreachable, and the honest answer there is the one the dialog already
  /// gives: type more.
  static int _searchWindow(int limit) =>
      limit >= kProfileSearchMaxRows
          ? limit
          : math.min(limit * 3, kProfileSearchMaxRows);

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
    final row =
        await _client
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
