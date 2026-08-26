import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:app/features/chefs/chef_detail_common.dart';
import 'package:app/features/chefs/chef_identity_header.dart';
import 'package:app/features/chefs/chef_score_panel.dart';
import 'package:app/features/chefs/chefs_providers.dart';
import 'package:app/routing/app_router.dart';
import 'package:app/widgets/recipe_async_grid.dart';

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

    return Scaffold(
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
    );
  }
}

/// Explicit rather than the default: the page is reachable by URL, so a visitor
/// can land here with nothing to pop back to.
class _BackButton extends StatelessWidget {
  const _BackButton();

  @override
  Widget build(BuildContext context) {
    return BackButton(
      onPressed: () {
        final nav = Navigator.of(context);
        if (nav.canPop()) {
          nav.pop();
        } else {
          context.go(Routes.chefs);
        }
      },
    );
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
        SliverPadding(
          padding: EdgeInsets.fromLTRB(pad, pad, pad, AppSpacing.sm),
          sliver: SliverToBoxAdapter(
            // `countOf` singularizes, so a one-recipe chef reads `1 public
            // recipe` rather than B031's `1 public recipes`.
            child: ChefKicker(
              text: countOf(data.profile.publicRecipeCount, 'public recipes'),
            ),
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
