import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:app/features/entities/entity_providers.dart';
import 'package:app/routing/app_router.dart';
import 'package:app/widgets/route_title.dart';
import 'package:app/routing/pop_or_go.dart';
import 'package:app/widgets/recipe_grid.dart';

/// `/entity/:id` — one publisher's page (Phase 35b).
///
/// The same shape `/chef/:id` established and for the same reasons: pushed on
/// the root navigator rather than living in the shell, signed-out safe, no nav
/// destination (Gotcha 18 — a fifth destination costs the web pill its labels),
/// and its own single-row fetch because a URL carries a uuid and nothing else.
///
/// **An entity is not a principal.** It has no score, no tier and no engagement
/// of its own — it reads its numbers through its members and its signature
/// dishes, which is the Phase 25 decision this page is the payoff for.
class EntityPage extends ConsumerWidget {
  const EntityPage({super.key, required this.entityId});

  final String entityId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(entityPageProvider(entityId));

    // UX-051 (Phase 37 review): titled while loading or failed too — the
    // loaded header's own title, nested inside, replaces this one.
    return RouteTitle(
      page: 'Publisher',
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Publisher'),
          leading: BackButton(
            onPressed: () => popOrGo(context, Routes.discover),
          ),
        ),
        body: async.when(
          loading: () => const LoadingView(),
          error:
              (e, _) => ErrorView(
                message: friendlyError(e),
                onRetry: () => ref.invalidate(entityPageProvider(entityId)),
              ),
          data: (data) => _Loaded(data: data),
        ),
      ),
    );
  }
}

class _Loaded extends StatelessWidget {
  const _Loaded({required this.data});

  final EntityPageData data;

  @override
  Widget build(BuildContext context) {
    final pad = context.isCompact ? AppSpacing.md : AppSpacing.lg;

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(pad, pad, pad, 0),
          sliver: SliverToBoxAdapter(child: _Header(entity: data.entity)),
        ),
        if (data.members.isNotEmpty)
          SliverPadding(
            padding: EdgeInsets.fromLTRB(pad, AppSpacing.lg, pad, 0),
            sliver: SliverToBoxAdapter(child: _Roster(members: data.members)),
          ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(pad, AppSpacing.lg, pad, AppSpacing.sm),
          sliver: SliverToBoxAdapter(
            child: Semantics(
              container: true,
              header: true,
              child: Text(
                'Signature dishes',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
        ),
        if (data.signatureDishes.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.xl),
              child: EmptyView(
                icon: Icons.restaurant_menu_outlined,
                title: 'No signature dishes yet',
                message: 'A member can list any of their public recipes here.',
              ),
            ),
          )
        else
          SliverRecipeGrid(
            recipes: data.signatureDishes,
            padding: EdgeInsets.fromLTRB(pad, 0, pad, pad),
          ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.entity});

  final Entity entity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // The publisher's name titles the browser tab (UX-051); the AppBar only
    // says "Publisher".
    return RouteTitle(
      page: entity.name,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The page's top heading (UX-014).
          Semantics(
            container: true,
            header: true,
            child: Text(entity.name, style: theme.textTheme.headlineSmall),
          ),
          const SizedBox(height: AppSpacing.sm),
          // Wrap: kind, country and the link are three intrinsically-sized chips
          // with no flexible child between them, which is B016's shape in a Row.
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Chip(
                label: Text(entity.kind.label),
                visualDensity: VisualDensity.compact,
              ),
              if (entity.country != null && entity.country!.isNotEmpty)
                Text(
                  entity.country!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              if (entity.homepage != null && entity.homepage!.isNotEmpty)
                // Printed, not launched. `url_launcher` is already a dependency
                // of the app, but an outbound tap from a directory page is a
                // decision (which links open, and whether they are marked
                // `noopener`) rather than a convenience, and Phase 35c is what
                // brings real publisher URLs. Until then the address is the fact
                // worth showing.
                Text(
                  entity.homepage!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          if (entity.description != null && entity.description!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text(entity.description!, style: theme.textTheme.bodyMedium),
          ],
          if (entity.isImported) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              'This publisher was added from the public web. Nobody on '
              'Secret Sauce manages this page yet.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The roster — owners first, each row a link to that chef's page.
class _Roster extends StatelessWidget {
  const _Roster({required this.members});

  final List<EntityMember> members;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          container: true,
          header: true,
          child: Text(
            members.length == 1 ? 'Chef' : 'Chefs',
            style: theme.textTheme.titleMedium,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        for (final member in members)
          _MemberRow(key: ValueKey(member.profileId), member: member),
      ],
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({super.key, required this.member});

  final EntityMember member;

  /// A roster row's avatar — sized to a `ListTile` leading slot.
  static const double _avatarRadius = 20;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profile = member.profile;
    final name =
        (profile?.displayName.isNotEmpty ?? false)
            ? profile!.displayName
            : 'Unnamed cook';

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: ChefAvatar(
        name: name,
        avatarUrl: profile?.avatarUrl,
        // The tier dot is deliberately absent. An entity page is not a
        // ranking, and a member who happens to be a Head Chef elsewhere should
        // not read as this publisher's standing.
        radius: _avatarRadius,
      ),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        member.roleLabel,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      // An imported chef's page is a credit rather than an account, and it says
      // so when you get there — so the row goes somewhere either way.
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push(Routes.chef(member.profileId)),
    );
  }
}
