import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:app/features/recipe_detail/recipe_detail_compact.dart';
import 'package:app/features/recipe_detail/recipe_detail_expanded.dart';
import 'package:app/features/recipe_detail/recipe_detail_providers.dart';
import 'package:app/routing/app_router.dart';

class RecipeDetailScreen extends ConsumerWidget {
  const RecipeDetailScreen({super.key, required this.recipeId});

  final String recipeId;

  Future<void> _fork(BuildContext context, WidgetRef ref) async {
    try {
      final newId = await ref.read(recipeRepositoryProvider).fork(recipeId);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Forked to your recipes')));
        context.go(Routes.editRecipe(newId));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(recipeProvider(recipeId));
    // One view per visit (OPT-P7). Watched, not read, so it stays alive for as
    // long as the screen does and is not re-run by the recipe invalidations
    // that every like/save/rating triggers.
    ref.watch(recipeViewLoggerProvider(recipeId));
    final currentUser = ref.watch(currentUserIdProvider);

    return Scaffold(
      body: async.when(
        loading: () => const Scaffold(body: LoadingView()),
        error:
            (e, _) => Scaffold(
              appBar: AppBar(),
              body: ErrorView(
                message: friendlyError(e),
                onRetry: () => ref.invalidate(recipeProvider(recipeId)),
              ),
            ),
        data: (recipe) {
          final isOwner = currentUser != null && currentUser == recipe.ownerId;
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
                onFork: () => _fork(context, ref),
              )
              : RecipeDetailCompact(
                recipe: recipe,
                isOwner: isOwner,
                onFork: () => _fork(context, ref),
              );
        },
      ),
    );
  }
}
