import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Everything `/entity/:id` needs, fetched together (Phase 35b).
///
/// The three reads have different failure meanings, so they are not collapsed
/// into one: the **entity** is the page — without it the route is a 404 — while
/// an empty roster and an empty signature list are ordinary states a new entity
/// is in on its first day.
class EntityPageData {
  const EntityPageData({
    required this.entity,
    this.members = const [],
    this.signatureDishes = const [],
  });

  final Entity entity;
  final List<EntityMember> members;
  final List<Recipe> signatureDishes;
}

/// Entity + roster + signature dishes for one entity.
///
/// All three requests are started before any is awaited — the OPT-P10 shape,
/// and `Future.wait` rather than sequential awaits over started futures, so a
/// fast failure on the second or third has a handler attached when it arrives
/// instead of surfacing as an unhandled zone error first.
final entityPageProvider = FutureProvider.autoDispose
    .family<EntityPageData, String>((ref, entityId) async {
      final entities = ref.watch(entityRepositoryProvider);

      final results = await Future.wait<Object?>([
        entities.getById(entityId),
        entities.members(entityId),
        entities.signatureDishes(entityId),
      ]);

      final entity = results[0] as Entity?;
      if (entity == null) {
        // The one genuine 404. An empty roster is not this.
        throw StateError('No entity with id $entityId');
      }

      return EntityPageData(
        entity: entity,
        members: results[1] as List<EntityMember>,
        signatureDishes: results[2] as List<Recipe>,
      );
    });
