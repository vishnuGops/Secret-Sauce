import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app/features/recipe_detail/recipe_detail_providers.dart';

/// Write the signed-in user's rating for [recipeId], then refresh what depends
/// on it.
///
/// One handler for the two surfaces that can rate — the reading page's
/// `RatingSection` and cook mode's finish screen — which carried the same body,
/// the same two invalidations and the same three snackbar strings in two files
/// (32c5). They are the same write: the finish screen is a *moment*, not a
/// different rule, and RLS is what forbids rating your own recipe either way.
///
/// Both invalidations matter: [myRatingProvider] is the star input's own value
/// and [recipeProvider] carries the average the block above it prints.
///
/// The messenger is captured **before** the write and used without a
/// `context.mounted` gate, the same shape `forkRecipe` uses: it belongs to the
/// `MaterialApp` above every screen here, not to the widget that started the
/// write, so it outlives a cook who taps a star and immediately backs out — and
/// the outcome of a write they asked for is worth saying either way.
Future<void> saveRating(
  BuildContext context,
  WidgetRef ref,
  String recipeId,
  double value,
) async {
  final messenger = ScaffoldMessenger.of(context);
  // The container too (Phase 37 review): after a cook taps a star and backs
  // out, `ref.invalidate` on the dead element threw into the catch below and a
  // rating that **was** saved reported "Could not save rating".
  final container = ProviderScope.containerOf(context, listen: false);
  try {
    await container.read(recipeRepositoryProvider).setRating(recipeId, value);
    container.invalidate(myRatingProvider(recipeId));
    container.invalidate(recipeProvider(recipeId));
    messenger
      // One confirmation on screen, not a queue of them.
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text('Rated ${value.toStringAsFixed(1)} stars')),
      );
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text('Could not save rating — ${friendlyError(e)}')),
    );
  }
}

/// Removes the user's own rating. Silent on success — the stars emptying is the
/// feedback — and a snackbar only when it fails.
Future<void> clearRating(
  BuildContext context,
  WidgetRef ref,
  String recipeId,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref.read(recipeRepositoryProvider).clearRating(recipeId);
    ref.invalidate(myRatingProvider(recipeId));
    ref.invalidate(recipeProvider(recipeId));
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text('Could not remove rating — ${friendlyError(e)}')),
    );
  }
}
