import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:app/routing/app_router.dart';

/// Fork [recipeId] into the signed-in user's own recipes and open the copy in
/// the editor.
///
/// One handler for both places a fork can start — the reading page's chip and
/// cook mode's finish screen — because they disagreed (B084). The finish screen
/// checked for a signed-in user and sent a visitor to `/auth`; the reading page
/// fired the RPC regardless, so a signed-out tap surfaced a Postgres denial as a
/// snackbar. The guard is UX either way: `fork_recipe` is the real gate.
///
/// It lands in the **editor**, not on the new recipe's reading page: a fork
/// exists to be changed, and the copy is private until its owner says otherwise.
Future<void> forkRecipe(
  BuildContext context,
  WidgetRef ref,
  String recipeId,
) async {
  if (ref.read(currentUserIdProvider) == null) {
    context.go(Routes.auth);
    return;
  }
  // Captured before the await: `context.go` below unmounts this subtree, and
  // `ScaffoldMessenger.of` on a dead context is the failure this pattern exists
  // to avoid (the `recipe_async_grid.dart` shape).
  final messenger = ScaffoldMessenger.of(context);
  try {
    final newId = await ref.read(recipeRepositoryProvider).fork(recipeId);
    if (!context.mounted) return;
    messenger.showSnackBar(
      const SnackBar(content: Text('Forked to your recipes')),
    );
    context.go(Routes.editRecipe(newId));
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text('Could not fork — ${friendlyError(e)}')),
    );
  }
}
