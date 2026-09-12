import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:core/src/models/enums.dart';

part 'profile.freezed.dart';
part 'profile.g.dart';

@freezed
class Profile with _$Profile {
  const factory Profile({
    required String id,
    @JsonKey(name: 'display_name') @Default('') String displayName,
    @JsonKey(name: 'avatar_url') String? avatarUrl,
    String? bio,
    @JsonKey(name: 'created_at') DateTime? createdAt,
    // Denormalized chef standing. Server-owned: maintained by the
    // on_recipe_stats_change trigger over this user's *public* recipes, and
    // omitted from every client write payload.
    @JsonKey(name: 'chef_score') @Default(0) double chefScore,
    @JsonKey(name: 'chef_tier', unknownEnumValue: ChefTier.homeCook)
    @Default(ChefTier.homeCook)
    ChefTier chefTier,
    @JsonKey(name: 'public_recipe_count') @Default(0) int publicRecipeCount,
    // Phase 35b. `member` unless the row was written by the corpus importer.
    // Server-owned: `kind` is absent from the column grants entirely, so a
    // client PATCH of it fails 42501 (rls_matrix G16).
    @JsonKey(name: 'kind', unknownEnumValue: ProfileKind.member)
    @Default(ProfileKind.member)
    ProfileKind kind,

    /// When a real chef took over this imported page. Null for every member and
    /// for every unclaimed imported profile.
    @JsonKey(name: 'claimed_at') DateTime? claimedAt,
  }) = _Profile;

  factory Profile.fromJson(Map<String, dynamic> json) =>
      _$ProfileFromJson(json);
}
