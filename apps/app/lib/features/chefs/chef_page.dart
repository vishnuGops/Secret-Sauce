import 'dart:math' as math;

import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app/features/chefs/chef_detail_common.dart';
import 'package:app/features/chefs/chef_identity_header.dart';
import 'package:app/features/chefs/chef_momentum_line.dart';
import 'package:app/features/chefs/chef_score_panel.dart';
import 'package:app/features/chefs/entity_affiliations.dart';
import 'package:app/features/chefs/unclaimed_chef_note.dart';
import 'package:app/features/chefs/chefs_providers.dart';
import 'package:app/routing/app_router.dart';
import 'package:app/routing/pop_or_go.dart';
import 'package:app/widgets/recipe_async_grid.dart';
import 'package:app/widgets/route_title.dart';

/// `/chef/:id` — one chef's public page (Phase 30).
///
/// Replaces the expanded dialog this feature used to open from the board. The
/// dialog could not be linked, shared or bookmarked, and it listed only the top
/// three recipes; the page is a destination with the chef's whole public
/// catalogue under it. Signed-out safe — every read behind it is `anon`-callable
/// and none touches the current user.
///
/// Three states, and they are not the same thing:
///  * **profile missing** → the route is wrong; an error with a way back.
///  * **profile present, no rank** → a real chef page for someone who holds no
///    leaderboard row (private-only, or no public recipe yet). The score panel
///    is omitted rather than rendered with zeroes it would have to explain.
///  * **ranked** → the full page.
class ChefPage extends StatelessWidget {
  const ChefPage({super.key, required this.chefId});

  final String chefId;

  @override
  Widget build(BuildContext context) {
    // The scope *is* the argument hand-off. Overriding the notifier alongside
    // its input matters: without the second override `chefRecipesProvider`
    // would be created in the root container and read the root's empty default,
    // so the grid would sit permanently empty with no error anywhere.
    return ProviderScope(
      overrides: [
        viewedChefIdProvider.overrideWithValue(chefId),
        chefRecipesProvider.overrideWith(ChefRecipesNotifier.new),
        // Scoped for the same reason as the notifier: `/chef/:id` is pushed on
        // the root navigator, so two chef pages can be on the stack at once and
        // a root-level selection would have the one underneath silently
        // re-sorting itself.
        chefSortProvider.overrideWith((ref) => ChefSort.all),
      ],
      child: _ChefPageBody(chefId: chefId),
    );
  }
}

class _ChefPageBody extends ConsumerWidget {
  const _ChefPageBody({required this.chefId});

  final String chefId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(chefPageProvider(chefId));

    // UX-051 (Phase 37 review): titled while loading or failed too — the
    // loaded header's own title, nested inside, replaces this one.
    return RouteTitle(
      page: 'Chef',
      child: Scaffold(
        appBar: AppBar(title: const Text('Chef'), leading: const _BackButton()),
        body: async.when(
          loading: () => const LoadingView(),
          error:
              (e, _) => ErrorView(
                message: friendlyError(e),
                onRetry: () => ref.invalidate(chefPageProvider(chefId)),
              ),
          data: (data) => _Loaded(data: data),
        ),
      ),
    );
  }
}

/// Explicit rather than the default: the page is reachable by URL, so a visitor
/// can land here with nothing to pop back to.
class _BackButton extends StatelessWidget {
  const _BackButton();

  @override
  Widget build(BuildContext context) {
    return BackButton(onPressed: () => popOrGo(context, Routes.chefs));
  }
}

class _Loaded extends StatelessWidget {
  const _Loaded({required this.data});

  final ChefPageData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final standing = data.standing;
    final tier = TierChip.colorFor(
      standing?.chefTier ?? data.profile.chefTier,
      theme.brightness,
    );
    final compact = context.isCompact;
    final pad = compact ? AppSpacing.md : AppSpacing.lg;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: ChefIdentityHeader(
            profile: data.profile,
            standing: standing,
            color: tier,
          ),
        ),
        if (standing != null)
          SliverPadding(
            padding: EdgeInsets.fromLTRB(pad, pad, pad, 0),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ChefScorePanel(standing: standing, color: tier),
                  const SizedBox(height: AppSpacing.md),
                  // Phase 33: the all-time panel above explains the score; this
                  // says what moved it lately. Ranked chefs only — the window
                  // function carries the board's population filter, so an
                  // unranked chef would get nothing back anyway.
                  ChefMomentumLine(chefId: data.profile.id),
                  const SizedBox(height: AppSpacing.md),
                  // Carried over from the panel the dialog used to show. The
                  // mockup said "recomputes nightly"; this build recomputes on
                  // every like, save, view and visibility change, so the copy
                  // says that (Phase 22's deliberate correction — losing it
                  // with the dialog would have quietly restored a false claim).
                  Text(
                    'Score and rank update the moment a recipe gains a like, '
                    'save, or view — there is no nightly job.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          )
        else if (data.isUnclaimed)
          SliverPadding(
            padding: EdgeInsets.fromLTRB(pad, pad, pad, 0),
            sliver: SliverToBoxAdapter(child: UnclaimedChefNote(data: data)),
          )
        else
          SliverPadding(
            padding: EdgeInsets.fromLTRB(pad, pad, pad, 0),
            sliver: const SliverToBoxAdapter(
              child: ChefNote(
                text:
                    'This chef has no public recipes yet, so they do not hold '
                    'a rank. Private recipes never count toward score or rank.',
              ),
            ),
          ),
        if (data.entities.isNotEmpty)
          SliverPadding(
            padding: EdgeInsets.fromLTRB(pad, pad, pad, 0),
            sliver: SliverToBoxAdapter(
              child: EntityAffiliations(entities: data.entities),
            ),
          ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(pad, pad, pad, AppSpacing.sm),
          sliver: SliverToBoxAdapter(
            child: _CatalogueHeader(count: data.profile.publicRecipeCount),
          ),
        ),
        RecipeAsyncSliverGrid<ChefRecipesNotifier>(
          provider: chefRecipesProvider,
          // The page already insets its content by `pad`; the default 16 would
          // start the cards half a gutter left of the header above them (B059).
          padding: EdgeInsets.fromLTRB(pad, 0, pad, pad),
          // Their own page, so the chef badge on every card would name the chef
          // whose page you are already on.
          showChef: false,
          empty: const Padding(
            padding: EdgeInsets.all(AppSpacing.xl),
            child: EmptyView(
              icon: Icons.menu_book_outlined,
              title: 'No public recipes',
              message: 'When this chef publishes a recipe it will appear here.',
            ),
          ),
        ),
      ],
    );
  }
}

/// The count, and the sort the grid under it is in (Phase 31).
///
/// One empty state for all three tabs on purpose: the sorts are three orderings
/// of the same set, so a chef whose Popular tab is empty has no public recipes
/// at all — and `chef_trending_recipes` falls through to newest-first rather
/// than returning nothing for a quiet week, so "nothing trending" is not a
/// state this page can reach.
class _CatalogueHeader extends ConsumerWidget {
  const _CatalogueHeader({required this.count});

  final int count;

  /// Left to itself the pill would stretch across the whole 1140px of an
  /// expanded page for three one-word segments. Scaled by text so the labels
  /// still fit at 2.0× instead of all three ellipsising into `A… P… T…`.
  static const double maxTabsWidth = 420;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sort = ref.watch(chefSortProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // `countOf` singularizes, so a one-recipe chef reads `1 public recipe`
        // rather than B031's `1 public recipes`. It counts the catalogue, not
        // the tab — all three tabs hold the same recipes.
        ChefKicker(text: countOf(count, 'public recipes')),
        const SizedBox(height: AppSpacing.sm),
        // The `LayoutBuilder` sits here rather than inside the pill because
        // this is the bounded position (Gotcha 25): the sliver hands its child
        // the full cross-axis extent, and the pill's `Row` of `Expanded`
        // segments needs a real width to divide.
        LayoutBuilder(
          builder:
              (context, constraints) => SizedBox(
                width: math.min(
                  constraints.maxWidth,
                  maxTabsWidth * context.textScale,
                ),
                child: ChefPillTabs<ChefSort>(
                  options: ChefSort.values,
                  selected: sort,
                  labelOf: (option) => option.label,
                  onSelected:
                      (option) =>
                          ref.read(chefSortProvider.notifier).state = option,
                ),
              ),
        ),
      ],
    );
  }
}
