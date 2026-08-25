import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:core/src/models/recipe_nutrition.dart';

part 'nutrition_estimate.freezed.dart';
part 'nutrition_estimate.g.dart';

/// What `estimate_nutrition` returns (Phase 29c): the computed per-serving
/// label plus the honesty bookkeeping the editor's Auto pane renders — how
/// many ingredient rows actually contributed and which names did not.
///
/// **Preview-only on the client.** The stored label is recomputed inside
/// `save_recipe` through the same SQL whenever the save claims
/// `source: 'auto'`, so nothing here is ever sent back as data — which is why
/// there is no Dart mirror of the arithmetic (Gotcha 19's two-implementations
/// tax, not bought).
@freezed
class NutritionEstimate with _$NutritionEstimate {
  const NutritionEstimate._();

  const factory NutritionEstimate({
    /// The estimated per-serving label, carrying `source: 'auto'` — or null
    /// when nothing counted (never an empty object; null is the one spelling
    /// of "no info"). Decode-only: an estimate is never encoded back, so the
    /// nested model stays out of `toJson` (B071).
    @JsonKey(includeToJson: false) RecipeNutrition? label,

    /// Ingredient rows that contributed to the label.
    @Default(0) int counted,

    /// All named ingredient rows the trees carried.
    @Default(0) int total,

    /// Distinct names of the rows that contributed nothing — the editor's
    /// "not counted" list (optional, unlinked, no quantity, or a unit the
    /// registry cannot convert for that food).
    @Default(<String>[]) List<String> unmatched,
  }) = _NutritionEstimate;

  factory NutritionEstimate.fromJson(Map<String, dynamic> json) =>
      _$NutritionEstimateFromJson(json);

  /// True when the estimate produced a usable label. The editor warns and
  /// saves `null` instead of an empty lie when this is false.
  bool get hasLabel => label != null;
}
