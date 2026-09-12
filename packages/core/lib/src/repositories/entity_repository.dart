import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:core/src/models/entity.dart';
import 'package:core/src/models/recipe.dart';
import 'package:core/src/repositories/recipe_queries.dart';

/// The entity directory: the groups that publish recipes (Phase 35b).
///
/// Signed-out safe by construction, like [ChefRepository]. `entities`,
/// `entity_members` and `entity_signature_dishes` are all world-readable —
/// a directory that needs an account is not a directory — and nothing here
/// touches the current user, so no call can throw the signed-out `StateError`.
abstract interface class EntityRepository {
  /// One entity by id. Null when it does not exist.
  Future<Entity?> getById(String id);

  /// The directory, newest first. Paged, and the order ends in `id` for the
  /// same reason every other paged read does (Gotcha 24): `offset` over a tie
  /// shows one row twice and hides another, silently.
  Future<List<Entity>> list({int limit, int offset});

  /// An entity's roster, owners first, each with the member's profile embedded.
  Future<List<EntityMember>> members(String entityId);

  /// The recipes an entity lists as its own, in the order it chose.
  ///
  /// Always public: `entity_signature_write` requires it, because the table is
  /// world-readable and listing a private recipe would publish its existence.
  /// The filter is restated here anyway — RLS decides what a *writer* may add,
  /// and a read that leans on a write policy is a read that breaks the day the
  /// policy is relaxed.
  Future<List<Recipe>> signatureDishes(String entityId, {int limit});

  /// The entities a profile belongs to — the affiliation line on a chef page.
  ///
  /// Empty is the normal case and not a failure: most profiles never join one.
  Future<List<Entity>> forProfile(String profileId);
}

/// Every column [Entity] decodes, and nothing more.
///
/// Explicit rather than `*` for the same reason `kRecipeSelect` is (OPT-P1 /
/// B086): a column fetched with no field behind it is payload on every row of
/// every page, and a field with no column decodes as null with no error. The
/// obligation runs both ways.
const String kEntitySelect =
    'id, slug, name, kind, homepage, country, description, cover_image_url, '
    'created_by, created_at, updated_at';

class SupabaseEntityRepository implements EntityRepository {
  SupabaseEntityRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<Entity?> getById(String id) async {
    final row =
        await _client
            .from('entities')
            .select(kEntitySelect)
            .eq('id', id)
            .maybeSingle();
    return row == null ? null : Entity.fromJson(row);
  }

  @override
  Future<List<Entity>> list({int limit = 24, int offset = 0}) async {
    final rows = await _client
        .from('entities')
        .select(kEntitySelect)
        .order('created_at', ascending: false)
        .order('id', ascending: false)
        .range(offset, offset + limit - 1);
    return rows.map<Entity>(Entity.fromJson).toList();
  }

  @override
  Future<List<EntityMember>> members(String entityId) async {
    // No FK hint needed here, and the asymmetry is worth knowing: `entities`
    // and `profiles` are related two ways (`created_by`, plus the membership
    // join), so embedding a profile into an *entity* is the PGRST201 shape
    // Gotcha 17 describes — but `entity_members` reaches `profiles` exactly
    // once, so this embed is unambiguous.
    final rows = await _client
        .from('entity_members')
        .select(
          'entity_id, profile_id, role, title, created_at, '
          'profile:profiles(id, display_name, avatar_url, bio, kind, '
          'chef_score, chef_tier, public_recipe_count)',
        )
        .eq('entity_id', entityId)
        // Owners first, then by name, then by id so the list is totally
        // ordered — a roster is short, but a stable one still beats a stable-ish
        // one when two members share a name.
        .order('role', ascending: true)
        .order('profile_id', ascending: true);
    return rows.map<EntityMember>(EntityMember.fromJson).toList();
  }

  @override
  Future<List<Recipe>> signatureDishes(
    String entityId, {
    int limit = 12,
  }) async {
    final rows = await _client
        .from('entity_signature_dishes')
        .select('recipes!inner($kRecipeSelect)')
        .eq('entity_id', entityId)
        .eq('recipes.visibility', 'public')
        .order('sort_order', ascending: true)
        .order('recipe_id', ascending: true)
        .limit(limit);
    return rows
        .map<Recipe>(
          (r) => Recipe.fromJson(r['recipes'] as Map<String, dynamic>),
        )
        .toList();
  }

  @override
  Future<List<Entity>> forProfile(String profileId) async {
    final rows = await _client
        .from('entity_members')
        .select('entities($kEntitySelect)')
        .eq('profile_id', profileId)
        .order('entity_id', ascending: true);
    return rows
        .map<Entity>(
          (r) => Entity.fromJson(r['entities'] as Map<String, dynamic>),
        )
        .toList();
  }
}
