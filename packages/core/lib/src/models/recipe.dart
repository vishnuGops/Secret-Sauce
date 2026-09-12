import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:core/src/models/enums.dart';
import 'package:core/src/models/ingredient_group.dart';
import 'package:core/src/models/profile.dart';
import 'package:core/src/models/recipe_nutrition.dart';
import 'package:core/src/models/step_group.dart';

part 'recipe.freezed.dart';
part 'recipe.g.dart';

Map<String, dynamic>? _nutritionToJson(RecipeNutrition? n) => n?.toJson();

@freezed
class Recipe with _$Recipe {
  const Recipe._();

  const factory Recipe({
    required String id,
    @JsonKey(name: 'owner_id') required String ownerId,
    required String title,
    @Default('') String description,
    @JsonKey(name: 'cover_image_url') String? coverImageUrl,
    String? cuisine,
    String? category,
    @Default(Difficulty.easy) Difficulty difficulty,
    @JsonKey(name: 'prep_minutes') @Default(0) int prepMinutes,
    @JsonKey(name: 'cook_minutes') @Default(0) int cookMinutes,
    @Default(1) int servings,
    @Default(RecipeVisibility.private) RecipeVisibility visibility,
    String? attribution,
    @JsonKey(name: 'forked_from_recipe_id') String? forkedFromRecipeId,
    @JsonKey(name: 'forked_from_version_id') String? forkedFromVersionId,
    @JsonKey(name: 'current_version_id') String? currentVersionId,
    @JsonKey(name: 'like_count') @Default(0) int likeCount,
    @JsonKey(name: 'save_count') @Default(0) int saveCount,
    @JsonKey(name: 'view_count') @Default(0) int viewCount,
    // Denormalized rating aggregates, maintained server-side by trigger.
    @JsonKey(name: 'rating_avg') @Default(0) double ratingAvg,
    @JsonKey(name: 'rating_count') @Default(0) int ratingCount,
    @JsonKey(name: 'created_at') DateTime? createdAt,
    @JsonKey(name: 'updated_at') DateTime? updatedAt,
    // Per-serving nutrition label, or null for "no info" — the ONE
    // representation of the empty state (an all-empty entry is normalized to
    // null before it reaches the repository). Client-writable, so it is in
    // `_writablePayload`, both column grant lists, and `save_recipe`.
    //
    // The explicit `toJson:` is not decoration. `explicitToJson` is off for
    // this package, and every other nested model on `Recipe` is
    // `includeToJson: false`, so this is the first field whose value has to be
    // flattened — without it the generator emits the object itself and
    // `jsonEncode(recipe.toJson())` throws at the call site rather than here.
    @JsonKey(toJson: _nutritionToJson) RecipeNutrition? nutrition,
    // Populated when a full recipe is loaded (not part of the base row).
    //
    // The `name:` is load-bearing (OPT-P3): `getById` now fetches the content as
    // a nested PostgREST embed, which arrives under the **table** names, and
    // without these the groups would silently decode to their empty defaults —
    // an empty recipe, and `update()` re-persists what it read (B035's family).
    // `includeToJson: false` stays, so `toJson()` remains the base row only and
    // the version snapshot keeps its existing `{recipe, ingredient_groups,
    // step_groups}` shape.
    @JsonKey(name: 'ingredient_groups', includeToJson: false)
    @Default(<IngredientGroup>[])
    List<IngredientGroup> ingredientGroups,
    @JsonKey(name: 'step_groups', includeToJson: false)
    @Default(<StepGroup>[])
    List<StepGroup> stepGroups,
    // The owning chef, embedded by PostgREST via kRecipeSelect. Null on any
    // query that does not ask for the embedding — surfaces render no badge
    // rather than failing.
    @JsonKey(includeToJson: false) Profile? owner,

    // ---- Phase 35c: provenance -------------------------------------------
    // Server-owned, every one of them: the importer writes them and no client
    // grant includes any, so a save that carried one would fail 42501. They are
    // here because they are *rendered* — the credit, its link, and whether the
    // cover may be shown.
    /// True when this recipe was captured from the public web rather than
    /// written here. Not the same question as the owner's [ProfileKind]: a chef
    /// who claims their page becomes a member while their imported recipes stay
    /// imported.
    @JsonKey(name: 'is_imported') @Default(false) bool isImported,

    /// Where it was published. The credit line links here, and it is the thing
    /// that makes showing the functional content defensible at all.
    @JsonKey(name: 'source_url') String? sourceUrl,

    /// The publisher's name, denormalised onto the row so a card can print the
    /// credit without a join.
    @JsonKey(name: 'source_name') String? sourceName,

    /// The publisher as an entity, when we have one — what the credit chip
    /// links to.
    @JsonKey(name: 'source_entity_id') String? sourceEntityId,

    /// How much of this recipe may be shown. `blocked` rows never reach a
    /// client (`recipes_corpus` filters them), so this is effectively
    /// `functional` or `linkOnly` in the app.
    @JsonKey(name: 'rights_mode', unknownEnumValue: RightsMode.functional)
    @Default(RightsMode.functional)
    RightsMode rightsMode,

    /// Whether the cover may be shown from the publisher's own address. There
    /// is no third value: we never copy an image and never proxy one.
    @JsonKey(name: 'image_mode', unknownEnumValue: ImageMode.hotlink)
    @Default(ImageMode.hotlink)
    ImageMode imageMode,
  }) = _Recipe;

  factory Recipe.fromJson(Map<String, dynamic> json) => _$RecipeFromJson(json);

  /// Total time to cook (prep + cook), in minutes.
  int get totalMinutes => prepMinutes + cookMinutes;

  bool get isFork => forkedFromRecipeId != null;

  /// The cover a widget may render, as opposed to the one the row holds.
  ///
  /// Phase 35c. An imported recipe whose publisher asked for no images still
  /// *has* a `coverImageUrl` — the crawl captured it — and must not show it.
  /// The rule lives here rather than in each of the five places that render a
  /// cover, because the sixth one is the one that would get it wrong, and a
  /// picture shown against a publisher's wishes is the single most expensive
  /// mistake in the whole rights position (Phase 35a).
  String? get displayCoverImageUrl =>
      imageMode.showsImage ? coverImageUrl : null;

  /// Whether the ingredients and steps may be shown.
  ///
  /// False only for `link_only` rows — a publisher who would rather we sent
  /// readers to them than reproduced the method. `blocked` never reaches a
  /// client at all (`recipes_corpus` filters it), so it is not a case the UI
  /// has to render.
  bool get showsContent => rightsMode.showsContent;

  /// The one-line credit, when there is somebody to credit.
  ///
  /// Null for a member's own recipe, which is credited by its owner badge like
  /// every other.
  String? get sourceCredit => isImported ? sourceName : null;

  /// Whether anyone has rated this recipe yet.
  bool get hasRatings => ratingCount > 0;

  /// Average rating rounded to one decimal, e.g. `4.5`.
  String get ratingLabel => ratingAvg.toStringAsFixed(1);
}
