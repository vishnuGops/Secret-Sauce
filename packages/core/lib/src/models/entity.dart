import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:core/src/models/enums.dart';
import 'package:core/src/models/profile.dart';

part 'entity.freezed.dart';
part 'entity.g.dart';

/// The group that **published** a recipe, as opposed to the person who cooked
/// it (Phase 35b).
///
/// This is Phase 25's `restaurants` generalised. The corpus needs an
/// attribution entity for 560 publishers and the north star needs a restaurant
/// entity; they are the same table with an [EntityKind], and building both
/// would mean writing the directory page twice.
///
/// An entity is **not a principal**. Nobody signs in as one — it is a row
/// managed by its `owner`-role members, which is the decision that keeps auth,
/// RLS and the engagement model untouched. It also collects no engagement of
/// its own: it reads its numbers through its members and its signature dishes.
@freezed
class Entity with _$Entity {
  const Entity._();

  const factory Entity({
    required String id,

    /// The stable identity, and the importer's idempotency key — the corpus
    /// already keys every source on a slug.
    required String slug,
    @Default('') String name,
    @JsonKey(unknownEnumValue: EntityKind.brand)
    @Default(EntityKind.brand)
    EntityKind kind,
    String? homepage,
    String? country,
    String? description,
    @JsonKey(name: 'cover_image_url') String? coverImageUrl,

    /// Null for an imported entity: nobody on this service registered it.
    @JsonKey(name: 'created_by') String? createdBy,
    @JsonKey(name: 'created_at') DateTime? createdAt,
    @JsonKey(name: 'updated_at') DateTime? updatedAt,
  }) = _Entity;

  factory Entity.fromJson(Map<String, dynamic> json) => _$EntityFromJson(json);

  /// True when this entity came from the corpus rather than from a member
  /// registering it here — the entity-level twin of `ProfileKind.imported`.
  bool get isImported => createdBy == null;
}

/// One seat on an entity's roster.
///
/// Association is optional by construction: a profile with zero rows here is
/// the normal case, and always will be.
@freezed
class EntityMember with _$EntityMember {
  const EntityMember._();

  const factory EntityMember({
    @JsonKey(name: 'entity_id') required String entityId,
    @JsonKey(name: 'profile_id') required String profileId,
    @JsonKey(unknownEnumValue: EntityRole.chef)
    @Default(EntityRole.chef)
    EntityRole role,

    /// Free text — 'Head Chef', 'Pastry'. Null is the common case.
    String? title,
    @JsonKey(name: 'created_at') DateTime? createdAt,

    /// The member themselves, embedded by the roster query.
    ///
    /// Nullable because the row is meaningful without it (a membership check
    /// does not need the person), and because a query that forgets the embed
    /// should degrade rather than throw. `includeToJson: false` keeps B071 out
    /// of reach: `explicitToJson` is off for this package, so a model-typed
    /// field written back out would emit the object itself and make
    /// `jsonEncode` throw at whatever call site touched it.
    @JsonKey(includeToJson: false) Profile? profile,
  }) = _EntityMember;

  factory EntityMember.fromJson(Map<String, dynamic> json) =>
      _$EntityMemberFromJson(json);

  bool get isOwner => role == EntityRole.owner;
}
