import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:app/features/recipe_detail/recipe_detail_providers.dart';
import 'package:app/routing/app_router.dart';

/// "Rate this recipe" block: half-star input for signed-in non-owners, plus the
/// current average. Owners see why they can't rate (RLS rejects self-ratings).
class RatingSection extends ConsumerWidget {
  const RatingSection({
    super.key,required this.recipe, required this.isOwner});

  final Recipe recipe;
  final bool isOwner;

  Future<void> _save(BuildContext context, WidgetRef ref, double value) async {
    try {
      await ref.read(recipeRepositoryProvider).setRating(recipe.id, value);
      ref.invalidate(myRatingProvider(recipe.id));
      ref.invalidate(recipeProvider(recipe.id));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Rated ${value.toStringAsFixed(1)} stars')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not save rating — ${friendlyError(e)}')));
      }
    }
  }

  Future<void> _clear(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(recipeRepositoryProvider).clearRating(recipe.id);
      ref.invalidate(myRatingProvider(recipe.id));
      ref.invalidate(recipeProvider(recipe.id));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not remove rating — ${friendlyError(e)}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final signedIn = ref.watch(currentUserIdProvider) != null;
    final myRating = ref.watch(myRatingProvider(recipe.id)).valueOrNull;

    final Widget action;
    if (isOwner) {
      action = Text(
        'You can’t rate your own recipe.',
        style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
      );
    } else if (!signedIn) {
      action = Row(
        children: [
          Expanded(
            child: Text(
              'Sign in to rate this recipe.',
              style:
                  textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          TextButton(
            onPressed: () => context.go(Routes.auth),
            child: const Text('Sign in'),
          ),
        ],
      );
    } else {
      action = Row(
        children: [
          StarRatingInput(
            value: myRating,
            size: 34,
            onChanged: (_) {},
            onChangeEnd: (v) => _save(context, ref, v),
          ),
          const SizedBox(width: AppSpacing.sm),
          if (myRating != null)
            TextButton(
              onPressed: () => _clear(context, ref),
              child: const Text('Remove'),
            ),
        ],
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            recipe.hasRatings
                ? '${recipe.ratingLabel} out of 5 · ${recipe.ratingCount} '
                    'rating${recipe.ratingCount == 1 ? '' : 's'}'
                : 'No ratings yet',
            style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.sm),
          action,
        ],
      ),
    );
  }
}
