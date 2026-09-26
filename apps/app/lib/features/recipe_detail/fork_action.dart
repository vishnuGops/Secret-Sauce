import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:app/routing/app_router.dart';
import 'package:app/routing/auth_return.dart';

/// True while a fork of this recipe is in flight (B129 / UX-026).
///
/// A double tap on Fork used to create two forks: nothing remembered that the
/// first `fork_recipe` call had not returned yet. [forkRecipe] refuses a second
/// call while this is set — that is the guard, and it holds for every caller —
/// and the Fork buttons watch it to render disabled, which is the affordance.
///
/// Not `autoDispose`: [forkRecipe] reads and writes it with `ref.read`, and an
/// auto-disposed provider with no listener (cook mode's finish screen does not
/// watch it) would be torn down between the write and the next tap, forgetting
/// the flag it exists to hold.
final forkInFlightProvider = StateProvider.family<bool, String>(
  (ref, recipeId) => false,
);

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
    // UX-017: back to this recipe after signing in, not to Discover.
    goToSignIn(context);
    return;
  }
  final inFlight = ref.read(forkInFlightProvider(recipeId).notifier);
  if (inFlight.state) return;
  // Captured before the await: `context.go` below unmounts this subtree, and
  // `ScaffoldMessenger.of` on a dead context is the failure this pattern exists
  // to avoid (the `recipe_async_grid.dart` shape). Before the flag, too: a
  // lookup that throws must not leave the flag set for the session.
  final messenger = ScaffoldMessenger.of(context);
  inFlight.state = true;
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
  } finally {
    // The notifier, not `ref`: after `context.go` the page that owned `ref`
    // is gone, and a `ref.read` on a disposed element throws.
    inFlight.state = false;
  }
}
