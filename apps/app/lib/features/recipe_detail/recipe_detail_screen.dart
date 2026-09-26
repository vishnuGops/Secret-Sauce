import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app/features/recipe_detail/fork_action.dart';
import 'package:app/features/recipe_detail/recipe_detail_compact.dart';
import 'package:app/features/recipe_detail/recipe_detail_expanded.dart';
import 'package:app/features/recipe_detail/recipe_detail_providers.dart';
import 'package:app/routing/app_router.dart';
import 'package:app/routing/pop_or_go.dart';
import 'package:app/widgets/route_title.dart';

class RecipeDetailScreen extends ConsumerWidget {
  const RecipeDetailScreen({super.key, required this.recipeId});

  final String recipeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(recipeProvider(recipeId));
    // One view per visit (OPT-P7). Watched, not read, so it stays alive for as
    // long as the screen does and is not re-run by the recipe invalidations
    // that every like/save/rating triggers.
    ref.watch(recipeViewLoggerProvider(recipeId));
    // The **profile** id, not the auth uid (B128 / UX-019): `ownerId` is a
    // `profiles.id`, and the two differ for a member who has claimed an
    // imported chef page — who then got Fork instead of Edit on their own
    // recipes. Null while it resolves, which reads as "not the owner" for one
    // frame; the reverse (an owner's controls flashing for a reader) would be
    // the worse flicker.
    final profileId = ref.watch(ownershipIdProvider);
    final forking = ref.watch(forkInFlightProvider(recipeId));

    // UX-051: the tab names the recipe once it has loaded.
    return RouteTitle(
      page: async.valueOrNull?.title,
      child: Scaffold(
        body: async.when(
          // Both states get a way out (UX-053). The loaded layouts draw their
          // own Back, but until the recipe arrives there is no layout — and a
          // deep link that is slow, or fails, left the reader on a spinner with
          // no exit but the browser. `popOrGo`, not the implied leading: a
          // deep link has nothing to pop to (B132's rule).
          loading:
              () => Scaffold(
                appBar: AppBar(leading: const _BackToDiscover()),
                body: const LoadingView(),
              ),
          error:
              (e, _) => Scaffold(
                appBar: AppBar(leading: const _BackToDiscover()),
                body: ErrorView(
                  message: friendlyError(e),
                  onRetry: () => ref.invalidate(recipeProvider(recipeId)),
                ),
              ),
          data: (recipe) {
            final isOwner = profileId != null && profileId == recipe.ownerId;
            // The whole page is v2 now, in two layouts on one
            // `context.isExpanded` branch. The v1 hero — a 240px `SliverAppBar`
            // over one padded `Column` — is **gone**, not kept for narrow
            // windows: keeping it would have meant a third design for the
            // 600–1000 band nobody drew, and the compact page reads correctly at
            // 800px. `recipe_detail_test.dart` moved onto this layout with it.
            return context.isExpanded
                ? RecipeDetailExpanded(
                  recipe: recipe,
                  isOwner: isOwner,
                  forking: forking,
                  onFork: () => forkRecipe(context, ref, recipeId),
                )
                : RecipeDetailCompact(
                  recipe: recipe,
                  isOwner: isOwner,
                  forking: forking,
                  onFork: () => forkRecipe(context, ref, recipeId),
                );
          },
        ),
      ),
    );
  }
}

class _BackToDiscover extends StatelessWidget {
  const _BackToDiscover();

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Back',
    icon: const Icon(Icons.arrow_back),
    onPressed: () => popOrGo(context, Routes.discover),
  );
}
