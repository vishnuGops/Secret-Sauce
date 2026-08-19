import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:core/src/models/enums.dart';
import 'package:core/src/models/ingredient.dart';
import 'package:core/src/models/ingredient_group.dart';
import 'package:core/src/models/recipe.dart';
import 'package:core/src/models/recipe_step.dart';
import 'package:core/src/models/recipe_version.dart';
import 'package:core/src/models/step_group.dart';
import 'package:core/src/repositories/recipe_queries.dart';

/// Recipe CRUD, forking, versioning, sharing, and social actions.
abstract interface class RecipeRepository {
  /// Full recipe including grouped ingredients and steps.
  Future<Recipe> getById(String id);

  /// Recipes owned by the current user.
  Future<List<Recipe>> listMine();

  /// Recipes shared with the current user.
  Future<List<Recipe>> listSharedWithMe();

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
    final row =
        await _client.from('recipes').select(kRecipeSelect).eq('id', id).single();
    final recipe = Recipe.fromJson(row);
    return recipe.copyWith(
      ingredientGroups: await _fetchIngredientGroups(id),
      stepGroups: await _fetchStepGroups(id),
    );
  }

  @override
  Future<List<Recipe>> listMine() async {
    final rows = await _client
        .from('recipes')
        .select(kRecipeSelect)
        .eq('owner_id', _uid)
        .order('updated_at', ascending: false);
    return rows.map<Recipe>(Recipe.fromJson).toList();
  }

  @override
  Future<List<Recipe>> listSharedWithMe() async {
    final rows = await _client
        .from('recipe_shares')
        .select('recipes($kRecipeSelect)')
        .eq('shared_with_user_id', _uid);
    return rows
        .map<Recipe>((r) => Recipe.fromJson(r['recipes'] as Map<String, dynamic>))
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
    final payload = _writablePayload(recipe)..['owner_id'] = _uid;
    final row = await _client.from('recipes').insert(payload).select().single();
    final created = Recipe.fromJson(row);
    await _persistContent(created.id, recipe.ingredientGroups, recipe.stepGroups);
    await _appendVersion(created.id, 'Initial version');
    return getById(created.id);
  }

  @override
  Future<Recipe> update(Recipe recipe, {String changeSummary = 'Updated'}) async {
    await _client
        .from('recipes')
        .update(_writablePayload(recipe))
        .eq('id', recipe.id);
    // Replace nested content wholesale (groups cascade-delete their children).
    await _client.from('ingredient_groups').delete().eq('recipe_id', recipe.id);
    await _client.from('step_groups').delete().eq('recipe_id', recipe.id);
    await _persistContent(recipe.id, recipe.ingredientGroups, recipe.stepGroups);
    await _appendVersion(recipe.id, changeSummary);
    return getById(recipe.id);
  }

  @override
  Future<void> delete(String id) async {
    await _client.from('recipes').delete().eq('id', id);
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
  Future<void> unshare({required String recipeId, required String userId}) async {
    await _client
        .from('recipe_shares')
        .delete()
        .eq('recipe_id', recipeId)
        .eq('shared_with_user_id', userId);
  }

  @override
  Future<void> setLiked(String recipeId, {required bool liked}) async {
    if (liked) {
      await _client
          .from('recipe_likes')
          .upsert({'user_id': _uid, 'recipe_id': recipeId});
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
      await _client
          .from('recipe_saves')
          .upsert({'user_id': _uid, 'recipe_id': recipeId});
    } else {
      await _client
          .from('recipe_saves')
          .delete()
          .eq('user_id', _uid)
          .eq('recipe_id', recipeId);
    }
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
    final row = await _client
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

  // postgrest-dart's `.order()` defaults to `ascending: false`, so nested
  // content must ask for ascending explicitly or it renders last-first (B022).
  Future<List<IngredientGroup>> _fetchIngredientGroups(String recipeId) async {
    final groups = await _client
        .from('ingredient_groups')
        .select()
        .eq('recipe_id', recipeId)
        .order('sort_order', ascending: true);
    final result = <IngredientGroup>[];
    for (final g in groups) {
      final items = await _client
          .from('ingredients')
          .select()
          .eq('group_id', g['id'] as String)
          .order('sort_order', ascending: true);
      result.add(
        IngredientGroup.fromJson(g).copyWith(
          ingredients: items.map<Ingredient>(Ingredient.fromJson).toList(),
        ),
      );
    }
    return result;
  }

  Future<List<StepGroup>> _fetchStepGroups(String recipeId) async {
    final groups = await _client
        .from('step_groups')
        .select()
        .eq('recipe_id', recipeId)
        .order('sort_order', ascending: true);
    final result = <StepGroup>[];
    for (final g in groups) {
      final items = await _client
          .from('steps')
          .select()
          .eq('group_id', g['id'] as String)
          .order('step_order', ascending: true);
      result.add(
        StepGroup.fromJson(g).copyWith(
          steps: items.map<RecipeStep>(RecipeStep.fromJson).toList(),
        ),
      );
    }
    return result;
  }

  Future<void> _persistContent(
    String recipeId,
    List<IngredientGroup> ingredientGroups,
    List<StepGroup> stepGroups,
  ) async {
    for (var gi = 0; gi < ingredientGroups.length; gi++) {
      final group = ingredientGroups[gi];
      final gRow = await _client
          .from('ingredient_groups')
          .insert({
            'recipe_id': recipeId,
            'name': group.name,
            'sort_order': gi,
          })
          .select()
          .single();
      final groupId = gRow['id'] as String;
      if (group.ingredients.isNotEmpty) {
        await _client.from('ingredients').insert([
          for (var i = 0; i < group.ingredients.length; i++)
            {
              'group_id': groupId,
              'quantity': group.ingredients[i].quantity,
              'unit': group.ingredients[i].unit,
              'name': group.ingredients[i].name,
              'note': group.ingredients[i].note,
              'is_optional': group.ingredients[i].isOptional,
              'sort_order': i,
            },
        ]);
      }
    }

    for (var gi = 0; gi < stepGroups.length; gi++) {
      final group = stepGroups[gi];
      final gRow = await _client
          .from('step_groups')
          .insert({
            'recipe_id': recipeId,
            'name': group.name,
            'sort_order': gi,
          })
          .select()
          .single();
      final groupId = gRow['id'] as String;
      if (group.steps.isNotEmpty) {
        await _client.from('steps').insert([
          for (var i = 0; i < group.steps.length; i++)
            {
              'group_id': groupId,
              'step_order': i,
              'text': group.steps[i].text,
              'image_url': group.steps[i].imageUrl,
              'duration_minutes': group.steps[i].durationMinutes,
              'temperature': group.steps[i].temperature,
              'tip': group.steps[i].tip,
              'sort_order': i,
            },
        ]);
      }
    }
  }

  Future<void> _appendVersion(String recipeId, String changeSummary) async {
    final existing = await _client
        .from('recipe_versions')
        .select('version_number, id')
        .eq('recipe_id', recipeId)
        .order('version_number', ascending: false)
        .limit(1);

    final nextNumber =
        existing.isEmpty ? 1 : (existing.first['version_number'] as int) + 1;
    final parentId = existing.isEmpty ? null : existing.first['id'] as String?;

    final full = await getById(recipeId);
    final snapshot = <String, dynamic>{
      'recipe': full.toJson(),
      'ingredient_groups': [
        for (final g in full.ingredientGroups) g.toJson(),
      ],
      'step_groups': [for (final g in full.stepGroups) g.toJson()],
    };

    final vRow = await _client
        .from('recipe_versions')
        .insert({
          'recipe_id': recipeId,
          'version_number': nextNumber,
          'parent_version_id': parentId,
          'author_id': _uid,
          'change_summary': changeSummary,
          'content_snapshot': snapshot,
        })
        .select()
        .single();

    await _client
        .from('recipes')
        .update({'current_version_id': vRow['id']})
        .eq('id', recipeId);
  }
}
