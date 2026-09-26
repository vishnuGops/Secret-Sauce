import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app/features/recipe_detail/rating_actions.dart';
import 'package:app/features/recipe_detail/recipe_detail_providers.dart';
import 'package:app/routing/auth_return.dart';

/// "Rate this recipe" block: half-star input for signed-in non-owners, plus the
/// current average. Owners see why they can't rate (RLS rejects self-ratings).
class RatingSection extends ConsumerWidget {
  const RatingSection({super.key, required this.recipe, required this.isOwner});

  final Recipe recipe;
  final bool isOwner;

  /// The half-star input's star — large enough to hit a half.
  static const double _kStarSize = 34;

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
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          TextButton(
            onPressed: () => goToSignIn(context),
            child: const Text('Sign in'),
          ),
        ],
      );
    } else {
      action = Row(
        children: [
          StarRatingInput(
            value: myRating,
            size: _kStarSize,
            onChanged: (_) {},
            onChangeEnd: (v) => saveRating(context, ref, recipe.id, v),
          ),
          const SizedBox(width: AppSpacing.sm),
          if (myRating != null)
            TextButton(
              onPressed: () => clearRating(context, ref, recipe.id),
              child: const Text('Remove'),
            ),
        ],
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        // The same panel fill as the rail and the method above it (36c).
        color: scheme.surfaceContainerLow,
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
            // Tabular: the average and the count move when you rate (UX-049).
            style: textTheme.titleSmall?.tabular,
          ),
          const SizedBox(height: AppSpacing.sm),
          action,
        ],
      ),
    );
  }
}
