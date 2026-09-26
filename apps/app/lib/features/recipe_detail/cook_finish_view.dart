import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app/features/recipe_detail/cook_mode_model.dart';
import 'package:app/features/recipe_detail/cook_mode_providers.dart';
import 'package:app/features/recipe_detail/fork_action.dart';
import 'package:app/features/recipe_detail/rating_actions.dart';
import 'package:app/features/recipe_detail/recipe_detail_providers.dart';
import 'package:app/routing/auth_return.dart';

/// The finish screen's reading measure (canvas frame E).
const double _kFinishMaxWidth = 560;

/// The screen after the last step (canvas frame E).
///
/// It exists to ask for the rating, and the reason it is worth a screen is
/// timing: this is the one moment the cook knows the answer. Everywhere else in
/// the product the rating control sits beside a recipe someone is *reading*.
///
/// The canvas also draws a "note for next time" field. There is no column behind
/// it — `recipe_ratings` holds a rating and two timestamps, nothing else — so it
/// is not drawn here rather than drawn dead. Adding it means a schema change
/// (column, grant, RLS check, a check in `rls_matrix.sql`), which is its own
/// change set; see ROADMAP Phase 27.
class CookFinishView extends ConsumerWidget {
  const CookFinishView({
    super.key,
    required this.recipe,
    required this.steps,
    required this.startedAt,
    required this.onBackToRecipe,
    required this.onReviewSteps,
    required this.onCookAgain,
  });

  final Recipe recipe;
  final List<CookStep> steps;
  final DateTime startedAt;
  final VoidCallback onBackToRecipe;

  /// Back to the last step — the finish screen is a state of the session, not a
  /// dead end, so "I wasn't done" has somewhere to go.
  final VoidCallback onReviewSteps;

  /// A fresh session from step one (UX-025). The session provider is not
  /// autoDispose, so this is the only way the next cook of this recipe does
  /// not open on this screen.
  final VoidCallback onCookAgain;

  /// `9 steps, 1 h 31 m from start to finish. Four minutes over the estimate.`
  ///
  /// Elapsed is wall-clock from when cook mode opened, which is honest about
  /// what it measures: it includes the time the phone sat on the counter, and it
  /// is not the recipe's `total_minutes`. The comparison is only offered when the
  /// recipe carries an estimate at all.
  ///
  /// Reads [cookClockProvider] rather than `DateTime.now()` for the same reason
  /// the timers do — [startedAt] is stamped from that clock, and mixing the two
  /// would measure this session against a different wall.
  String _summary(WidgetRef ref) {
    final elapsed = ref.read(cookClockProvider)().difference(startedAt);
    final elapsedMinutes = elapsed.inMinutes;
    final estimate = recipe.totalMinutes;
    final counted =
        '${countOf(steps.length, 'steps')}, '
        '${formatMinutes(elapsedMinutes)} from start to finish.';
    if (estimate <= 0) return counted;
    final delta = elapsedMinutes - estimate;
    if (delta.abs() < 2) return '$counted Right on the estimate.';
    return delta > 0
        ? '$counted ${formatMinutes(delta)} over the estimate.'
        : '$counted ${formatMinutes(-delta)} under the estimate.';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    // `ownerId` is a profiles.id, so it is compared with the caller's profile
    // id — never the auth uid, which differs for a member who claimed an
    // imported chef page (Phase 35b, B128/UX-019). Still loading counts as not
    // the owner: the rating the owner branch would hide is denied by RLS
    // anyway, and the frame after resolution corrects it.
    final myProfileId = ref.watch(ownershipIdProvider);
    final isOwner = myProfileId != null && myProfileId == recipe.ownerId;

    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _kFinishMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.check_circle,
                  size: AppIconSize.xxl,
                  color: scheme.primary,
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'That’s ${recipe.title} done',
                  style: textTheme.headlineMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _summary(ref),
                  style: textTheme.bodyLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                _FinishRating(recipe: recipe, isOwner: isOwner),
                const SizedBox(height: AppSpacing.lg),
                if (!isOwner)
                  FilledButton.tonalIcon(
                    onPressed: () => forkRecipe(context, ref, recipe.id),
                    icon: const Icon(Icons.call_split),
                    label: const Text('Fork with my changes'),
                  ),
                const SizedBox(height: AppSpacing.sm),
                TextButton(
                  onPressed: onBackToRecipe,
                  child: const Text('Back to the recipe'),
                ),
                TextButton(
                  onPressed: onReviewSteps,
                  child: const Text('Not done — back to the last step'),
                ),
                TextButton.icon(
                  onPressed: onCookAgain,
                  icon: const Icon(Icons.replay),
                  label: const Text('Cook again'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "How did it turn out?" — the same three cases the reading page's rating block
/// handles (owner, signed out, signed in), stated for the moment they land in.
///
/// It writes through `setRating`, so RLS is what actually forbids rating your
/// own recipe; the owner branch here explains it rather than enforcing it.
class _FinishRating extends ConsumerWidget {
  const _FinishRating({required this.recipe, required this.isOwner});

  final Recipe recipe;
  final bool isOwner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final signedIn = ref.watch(currentUserIdProvider) != null;
    final myRating = ref.watch(myRatingProvider(recipe.id)).valueOrNull;

    final Widget body;
    if (isOwner) {
      body = Text(
        'It’s your recipe, so you can’t rate it — but you cooked it, which is '
        'the better review.',
        style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
      );
    } else if (!signedIn) {
      body = Row(
        children: [
          Expanded(
            child: Text(
              'Sign in to rate it.',
              style: textTheme.bodyMedium?.copyWith(
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
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StarRatingInput(
            value: myRating,
            size: AppIconSize.xl,
            onChanged: (_) {},
            onChangeEnd: (v) => saveRating(context, ref, recipe.id, v),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            myRating == null
                ? 'Tap to rate · half stars allowed'
                : 'You rated it ${myRating.toStringAsFixed(1)}',
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('How did it turn out?', style: textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          body,
        ],
      ),
    );
  }
}
