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
  edit,
}

enum SuggestionStatus {
  @JsonValue('open')
  open,
  @JsonValue('accepted')
  accepted,
  @JsonValue('rejected')
  rejected,
}

/// What kind of group published a recipe (Phase 35b).
///
/// Phase 25 designed a `restaurant_role`/`restaurants` pair; this is that,
/// generalised, because the corpus's 560 publishers and the north star's
/// restaurants are the same table with a discriminator.
enum EntityKind {
  @JsonValue('restaurant')
  restaurant,
  @JsonValue('brand')
  brand,
  @JsonValue('publication')
  publication,
  @JsonValue('community')
  community,
  @JsonValue('chef_site')
  chefSite;

  String get label => switch (this) {
    EntityKind.restaurant => 'Restaurant',
    EntityKind.brand => 'Brand',
    EntityKind.publication => 'Publication',
    EntityKind.community => 'Community',
    EntityKind.chefSite => 'Chef',
  };
}

/// What a member may do to an entity (Phase 35b). An `owner` manages the row
/// and its roster; a `chef` is listed on it and may curate signature dishes.
enum EntityRole {
  @JsonValue('owner')
  owner,
  @JsonValue('chef')
  chef;

  String get label => switch (this) {
    EntityRole.owner => 'Owner',
    EntityRole.chef => 'Chef',
  };
}

/// Where a chef's request to take over an imported page has got to (Phase 35b).
///
/// The decision is never a client write — `approve_profile_claim()` is
/// `security definer` with EXECUTE revoked from the API roles, because
/// approving transfers ownership of every recipe on the profile.
enum ClaimStatus {
  @JsonValue('pending')
  pending,
  @JsonValue('approved')
  approved,
  @JsonValue('rejected')
  rejected;

  String get label => switch (this) {
    ClaimStatus.pending => 'Pending review',
    ClaimStatus.approved => 'Approved',
    ClaimStatus.rejected => 'Not approved',
  };
}

/// What kind of identity a `profiles` row is (Phase 35b).
///
/// `member` has an account behind it (`profiles.auth_user_id` is set) and is the
/// only kind the leaderboard ranks. `imported` is a chef the corpus credits who
/// has never signed up: world-readable, immutable by construction (nothing can
/// resolve to it, because there is no account to resolve from), and claimable.
///
/// Decoded with `unknownEnumValue: ProfileKind.member` for the same reason
/// [ChefTier] is: a client that predates a future kind should degrade rather
/// than throw.
enum ProfileKind {
  @JsonValue('member')
  member,
  @JsonValue('imported')
  imported;

  /// True when nobody has claimed this page yet — what the chef page reads to
  /// decide whether to offer "Is this you?".
  bool get isImported => this == ProfileKind.imported;
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

  /// Inverse of [wireValue], for rows that arrive outside a generated decoder —
  /// `chefs_tier_counts()` returns a bare `chef_tier` column, not a model
  /// (OPT-P10). Throws on an unknown label rather than guessing: a new tier in
  /// SQL that is missing here should fail loudly, the same way [wireValue]'s
  /// switch would.
  static ChefTier fromWire(String wire) => ChefTier.values.firstWhere(
    (t) => t.wireValue == wire,
    orElse: () => throw ArgumentError.value(wire, 'wire', 'unknown chef_tier'),
  );

  /// Rung index, 0 (lowest) .. 4 (highest). Handy for styling ramps.
  int get rank => index;
}
