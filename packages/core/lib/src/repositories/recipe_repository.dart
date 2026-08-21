import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:core/src/models/enums.dart';
import 'package:core/src/models/recipe.dart';
import 'package:core/src/models/recipe_version.dart';
import 'package:core/src/paging.dart';
import 'package:core/src/repositories/recipe_queries.dart';
import 'package:core/src/repositories/write_denied_exception.dart';

/// Recipe CRUD, forking, versioning, sharing, and social actions.
abstract interface class RecipeRepository {
  /// Full recipe including grouped ingredients and steps.
  Future<Recipe> getById(String id);

  /// Recipes owned by the current user — one page of [limit] rows starting at
  /// [offset] (OPT-P9). Both lists were unbounded before, so a 400-recipe vault
  /// decoded 400 rows on every visit to `/my`.
  Future<List<Recipe>> listMine({int limit, int offset});

  /// Recipes shared with the current user, same paging contract as [listMine].
  Future<List<Recipe>> listSharedWithMe({int limit, int offset});

  /// Create a new recipe (with nested groups) and its first version.
  Future<Recipe> create(Recipe recipe);

  /// Update a recipe; persists nested content and appends a new version.
  Future<Recipe> update(Recipe recipe, {String changeSummary});

  Future<void> delete(String id);

  /// Deep-copy fork; returns the new recipe id.
  Future<String> fork(String sourceRecipeId);

  /// Version history, newest first.
  Future<List<RecipeVersion>> versions(String recipeId);

  Future<void> share({
    required String recipeId,
    required String userId,
    SharePermission permission,
  });

  Future<void> unshare({required String recipeId, required String userId});

  Future<void> setLiked(String recipeId, {required bool liked});
  Future<void> setSaved(String recipeId, {required bool saved});

  /// Whether the current user has liked / saved [recipeId]. Both return `false`
  /// when signed out — these sit on a signed-out-reachable screen (Gotcha 9),
  /// so they use `currentUser?.id` rather than `_uid`.
  Future<bool> myLiked(String recipeId);
  Future<bool> mySaved(String recipeId);

  Future<void> logView(String recipeId);

  /// The current user's star rating for [recipeId], or null if unrated
  /// (also null when signed out).
  Future<double?> myRating(String recipeId);

  /// Rate a recipe from 0.5 to 5.0 in half-star steps. Re-rating overwrites.
  /// RLS rejects rating your own recipe.
  Future<void> setRating(String recipeId, double rating);

  /// Remove the current user's rating.
  Future<void> clearRating(String recipeId);
}

/// Star ratings are stored in half-star steps between 0.5 and 5.0.
const double kMinRating = 0.5;
const double kMaxRating = 5.0;
const double kRatingStep = 0.5;

/// Snaps [rating] to the nearest half star inside [kMinRating]..[kMaxRating].
double snapRating(double rating) {
  final snapped = (rating / kRatingStep).round() * kRatingStep;
  return snapped.clamp(kMinRating, kMaxRating).toDouble();
}

class SupabaseRecipeRepository implements RecipeRepository {
  SupabaseRecipeRepository(this._client);

  final SupabaseClient _client;

  String get _uid {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw StateError('Not authenticated.');
    return id;
  }

  @override
  Future<Recipe> getById(String id) async {
    // One round trip for the whole recipe (OPT-P3). This used to be 2 + G + S
    // requests — the row, the two group lists, then one per group — so a recipe
    // with 3 ingredient groups and 4 step groups cost 9 sequential round trips.
    //
    // Every `order` here is mandatory and every one is `ascending: true`
    // (B022): postgrest-dart defaults to descending, PostgREST promises no
    // order for an embedded resource at all, and `update()` re-persists the
    // list it just read — so a wrong order here writes a wrong recipe back.
    final row =
        await _client
            .from('recipes')
            .select(kRecipeDetailSelect)
            .eq('id', id)
            .order(
              'sort_order',
              referencedTable: 'ingredient_groups',
              ascending: true,
            )
            .order(
              'sort_order',
              referencedTable: 'ingredient_groups.ingredients',
              ascending: true,
            )
            .order(
              'sort_order',
              referencedTable: 'step_groups',
              ascending: true,
            )
            .order(
              'step_order',
              referencedTable: 'step_groups.steps',
              ascending: true,
            )
            .single();
    return Recipe.fromJson(row);
  }

  @override
  Future<List<Recipe>> listMine({
    int limit = kRecipePageSize,
    int offset = 0,
  }) async {
    // `id` after `updated_at` because paging needs a **total** order: a save
    // that touches two recipes in the same second would otherwise let them swap
    // between the page-1 and page-2 reads, showing one twice and hiding the
    // other. `range` is inclusive at both ends.
    final rows = await _client
        .from('recipes')
        .select(kRecipeSelect)
        .eq('owner_id', _uid)
        .order('updated_at', ascending: false)
        .order('id', ascending: false)
        .range(offset, offset + limit - 1);
    return rows.map<Recipe>(Recipe.fromJson).toList();
  }

  @override
  Future<List<Recipe>> listSharedWithMe({
    int limit = kRecipePageSize,
    int offset = 0,
  }) async {
    // Ordered by when the share was made — newest first, `recipe_id` breaking
    // the tie — because `recipe_shares` is the table being paged here, not
    // `recipes`; ordering by an embedded column is not something PostgREST can
    // page over.
    final rows = await _client
        .from('recipe_shares')
        .select('recipes($kRecipeSelect)')
        .eq('shared_with_user_id', _uid)
        .order('created_at', ascending: false)
        .order('recipe_id', ascending: false)
        .range(offset, offset + limit - 1);
    return rows
        .map<Recipe>(
          (r) => Recipe.fromJson(r['recipes'] as Map<String, dynamic>),
        )
        .toList();
  }

  /// Only the columns a client is allowed to write. Server-managed columns
  /// (timestamps, counters, current_version_id) are intentionally excluded.
  Map<String, dynamic> _writablePayload(Recipe recipe) => {
    'title': recipe.title,
    'description': recipe.description,
    'cover_image_url': recipe.coverImageUrl,
    'cuisine': recipe.cuisine,
    'category': recipe.category,
    'difficulty': recipe.difficulty.name,
    'prep_minutes': recipe.prepMinutes,
    'cook_minutes': recipe.cookMinutes,
    'servings': recipe.servings,
    'visibility': recipe.visibility.name,
    'attribution': recipe.attribution,
    'forked_from_recipe_id': recipe.forkedFromRecipeId,
    'forked_from_version_id': recipe.forkedFromVersionId,
  };

  @override
  Future<Recipe> create(Recipe recipe) async {
    final newId = await _save(null, recipe, 'Initial version');
    return getById(newId);
  }

  @override
  Future<Recipe> update(
    Recipe recipe, {
    String changeSummary = 'Updated',
  }) async {
    await _save(recipe.id, recipe, changeSummary);
    return getById(recipe.id);
  }

  /// One `save_recipe` call: the row, its content, and its version row, in a
  /// single server-side transaction (OPT-A1).
  ///
  /// What this replaced: an update, two deletes, one insert per group and one
  /// per group's children, a read, and a version insert — each its own request,
  /// each able to be the last one that lands. A failure between the deletes and
  /// the re-inserts left the recipe with its title saved and its content gone
  /// (Gotcha 11), and `version_number` was read and incremented client-side, so
  /// two saves of one recipe could pick the same number.
  ///
  /// `p_recipe_id` null creates; the function reads `auth.uid()` for the owner
  /// and the version author, so neither is trusted from here.
  Future<String> _save(
    String? recipeId,
    Recipe recipe,
    String changeSummary,
  ) async {
    try {
      final id = await _client.rpc(
        'save_recipe',
        params: {
          'p_recipe_id': recipeId,
          'p_payload': _writablePayload(recipe),
          'p_ingredient_groups': [
            for (final group in recipe.ingredientGroups)
              {
                'name': group.name,
                'ingredients': [
                  for (final i in group.ingredients)
                    {
                      'quantity': i.quantity,
                      'unit': i.unit,
                      'name': i.name,
                      'note': i.note,
                      'is_optional': i.isOptional,
                    },
                ],
              },
          ],
          'p_step_groups': [
            for (final group in recipe.stepGroups)
              {
                'name': group.name,
                'steps': [
                  for (final s in group.steps)
                    {
                      'text': s.text,
                      'image_url': s.imageUrl,
                      'duration_minutes': s.durationMinutes,
                      'temperature': s.temperature,
                      'tip': s.tip,
                    },
                ],
              },
          ],
          'p_change_summary': changeSummary,
        },
      );
      return id as String;
    } on PostgrestException catch (e) {
      // The function raises `42501` when the caller does not own the recipe or
      // is signed out. Translated back into the exception the callers already
      // handle (OPT-S2), so a denial still cannot be mistaken for a save — the
      // RPC never had the silent-0-rows problem, but the contract stays one
      // thing rather than two.
      if (e.code == '42501') {
        throw WriteDeniedException(
          'save this recipe',
          detail: 'recipe ${recipeId ?? '(new)'}',
        );
      }
      rethrow;
    }
  }

  @override
  Future<void> delete(String id) async {
    final removed = await _client
        .from('recipes')
        .delete()
        .eq('id', id)
        .select('id');
    if (removed.isEmpty) {
      throw WriteDeniedException('delete this recipe', detail: 'recipe $id');
    }
  }

  @override
  Future<String> fork(String sourceRecipeId) async {
    final newId = await _client.rpc(
      'fork_recipe',
      params: {'p_source': sourceRecipeId},
    );
    return newId as String;
  }

  @override
  Future<List<RecipeVersion>> versions(String recipeId) async {
    final rows = await _client
        .from('recipe_versions')
        .select()
        .eq('recipe_id', recipeId)
        .order('version_number', ascending: false);
    return rows.map<RecipeVersion>(RecipeVersion.fromJson).toList();
  }

  @override
  Future<void> share({
    required String recipeId,
    required String userId,
    SharePermission permission = SharePermission.view,
  }) async {
    await _client.from('recipe_shares').upsert({
      'recipe_id': recipeId,
      'shared_with_user_id': userId,
      'permission': permission.name,
    });
  }

  @override
  Future<void> unshare({
    required String recipeId,
    required String userId,
  }) async {
    // Same Gotcha 2 trap as update()/delete(): `shares_owner_all` is scoped to
    // `owns_recipe(recipe_id)`, so a non-owner's revoke matches 0 rows and the
    // dialog would report the person removed while they keep their access.
    final removed = await _client
        .from('recipe_shares')
        .delete()
        .eq('recipe_id', recipeId)
        .eq('shared_with_user_id', userId)
        .select('recipe_id');
    if (removed.isEmpty) {
      throw WriteDeniedException(
        'remove this person',
        detail: 'share $recipeId/$userId',
      );
    }
  }

  @override
  Future<void> setLiked(String recipeId, {required bool liked}) async {
    if (liked) {
      await _client.from('recipe_likes').upsert({
        'user_id': _uid,
        'recipe_id': recipeId,
      });
    } else {
      await _client
          .from('recipe_likes')
          .delete()
          .eq('user_id', _uid)
          .eq('recipe_id', recipeId);
    }
  }

  @override
  Future<void> setSaved(String recipeId, {required bool saved}) async {
    if (saved) {
      await _client.from('recipe_saves').upsert({
        'user_id': _uid,
        'recipe_id': recipeId,
      });
    } else {
      await _client
          .from('recipe_saves')
          .delete()
          .eq('user_id', _uid)
          .eq('recipe_id', recipeId);
    }
  }

  @override
  Future<bool> myLiked(String recipeId) => _hasMyRow('recipe_likes', recipeId);

  @override
  Future<bool> mySaved(String recipeId) => _hasMyRow('recipe_saves', recipeId);

  /// Shared body for [myLiked] / [mySaved]: does a `(user_id, recipe_id)` row
  /// exist for the current user? Signed out is not an error here — the detail
  /// screen is reachable without an account — so it answers `false`.
  Future<bool> _hasMyRow(String table, String recipeId) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return false;
    final row =
        await _client
            .from(table)
            .select('recipe_id')
            .eq('recipe_id', recipeId)
            .eq('user_id', uid)
            .maybeSingle();
    return row != null;
  }

  @override
  Future<void> logView(String recipeId) async {
    await _client.from('recipe_views').insert({
      'recipe_id': recipeId,
      'user_id': _client.auth.currentUser?.id,
    });
  }

  @override
  Future<double?> myRating(String recipeId) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return null;
    final row =
        await _client
            .from('recipe_ratings')
            .select('rating')
            .eq('recipe_id', recipeId)
            .eq('user_id', uid)
            .maybeSingle();
    final value = row?['rating'];
    return value == null ? null : (value as num).toDouble();
  }

  @override
  Future<void> setRating(String recipeId, double rating) async {
    await _client.from('recipe_ratings').upsert({
      'user_id': _uid,
      'recipe_id': recipeId,
      'rating': snapRating(rating),
    });
  }

  @override
  Future<void> clearRating(String recipeId) async {
    await _client
        .from('recipe_ratings')
        .delete()
        .eq('user_id', _uid)
        .eq('recipe_id', recipeId);
  }

  // ---------- helpers ----------

  // Three helpers used to live here and are now one `save_recipe` call
  // (OPT-A1): `_persistContent`, which walked the group tree issuing an insert
  // per group, and `_appendVersion`, which read `max(version_number)` and added
  // one from the client. `_fetchIngredientGroups` / `_fetchStepGroups` went
  // earlier, to OPT-P3's nested embed in `getById`. What survives all three
  // removals is B022: content order is explicit, at every level, on the read
  // (`getById`) and on the write (the array index becomes `sort_order`, in SQL
  // now).
}
