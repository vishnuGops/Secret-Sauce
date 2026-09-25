import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:app/routing/app_router.dart';

/// The groups a chef is listed under, as a row of chips (Phase 35b).
///
/// Rendered only when there is at least one — most profiles never join an
/// entity, and "No affiliations" is a sentence nobody needs. The chef page
/// gates on `entities.isNotEmpty` rather than this widget drawing an empty
/// state, so the spacing above it disappears too.
///
/// A `Wrap`, because a chef can belong to several and the label is a publisher
/// name of unbounded length: a `Row` would overflow at the first long one, and
/// the 2.0x-scale case arrives long before that.
class EntityAffiliations extends StatelessWidget {
  const EntityAffiliations({super.key, required this.entities});

  final List<Entity> entities;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Appears in',
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final entity in entities)
              ActionChip(
                avatar: Icon(_iconFor(entity.kind), size: AppIconSize.button),
                label: Text(entity.name),
                onPressed: () => context.push(Routes.entity(entity.id)),
              ),
          ],
        ),
      ],
    );
  }

  static IconData _iconFor(EntityKind kind) => switch (kind) {
    EntityKind.restaurant => Icons.restaurant_outlined,
    EntityKind.brand => Icons.storefront_outlined,
    EntityKind.publication => Icons.menu_book_outlined,
    EntityKind.community => Icons.groups_outlined,
    EntityKind.chefSite => Icons.person_outline,
  };
}
