/// Domain enums mirroring the Postgres enums exactly.
library;

import 'package:json_annotation/json_annotation.dart';

enum Difficulty {
  @JsonValue('easy')
  easy,
  @JsonValue('medium')
  medium,
  @JsonValue('hard')
  hard;

  String get label => switch (this) {
        Difficulty.easy => 'Easy',
        Difficulty.medium => 'Medium',
        Difficulty.hard => 'Hard',
      };
}

enum RecipeVisibility {
  @JsonValue('private')
  private,
  @JsonValue('public')
  public;

  bool get isPublic => this == RecipeVisibility.public;
}

enum SharePermission {
  @JsonValue('view')
  view,
  @JsonValue('edit')
  edit;
}

enum SuggestionStatus {
  @JsonValue('open')
  open,
  @JsonValue('accepted')
  accepted,
  @JsonValue('rejected')
  rejected;
}

/// A chef's standing, derived server-side from the engagement counters of the
/// public recipes they own. Never written by the client — `chef_tier_for()` in
/// `0001_init.sql` is the single source of truth for the thresholds.
///
/// Decoded with `unknownEnumValue: ChefTier.homeCook` at every call site, so a
/// client that predates a future tier degrades to the lowest rung instead of
/// throwing on an unrecognised value.
enum ChefTier {
  @JsonValue('home_cook')
  homeCook,
  @JsonValue('line_cook')
  lineCook,
  @JsonValue('sous_chef')
  sousChef,
  @JsonValue('head_chef')
  headChef,
  @JsonValue('master_chef')
  masterChef;

  String get label => switch (this) {
        ChefTier.homeCook => 'Home Cook',
        ChefTier.lineCook => 'Line Cook',
        ChefTier.sousChef => 'Sous Chef',
        ChefTier.headChef => 'Head Chef',
        ChefTier.masterChef => 'Master Chef',
      };

  /// The Postgres enum label — the same string as the `@JsonValue` above.
  ///
  /// Restated rather than derived because `json_serializable` keeps its mapping
  /// private to the generated code, and a `.eq('chef_tier', …)` filter needs the
  /// wire string without going through a full decode. The two must move
  /// together; `chef_models_test.dart` pins every pair.
  String get wireValue => switch (this) {
        ChefTier.homeCook => 'home_cook',
        ChefTier.lineCook => 'line_cook',
        ChefTier.sousChef => 'sous_chef',
        ChefTier.headChef => 'head_chef',
        ChefTier.masterChef => 'master_chef',
      };

  /// Rung index, 0 (lowest) .. 4 (highest). Handy for styling ramps.
  int get rank => index;
}
