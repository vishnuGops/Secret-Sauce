import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:core/src/models/profile.dart';

/// Read/update user profiles; used by sharing (user lookup) and profile screen.
abstract interface class ProfileRepository {
  Future<Profile?> getById(String id);
  Future<Profile?> findByEmailOrName(String query);
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
  Future<Profile?> findByEmailOrName(String query) async {
    // Profiles are world-readable; match on display name.
    final row = await _client
        .from('profiles')
        .select()
        .ilike('display_name', query)
        .limit(1)
        .maybeSingle();
    return row == null ? null : Profile.fromJson(row);
  }

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
