import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:app/features/recipe_detail/cook_finish_view.dart';
import 'package:app/features/recipe_detail/cook_mode_model.dart';
import 'package:app/features/recipe_detail/cook_mode_providers.dart';
import 'package:app/features/recipe_detail/cook_step_view.dart';
import 'package:app/features/recipe_detail/recipe_detail_providers.dart';
import 'package:app/routing/app_router.dart';

/// Cook mode — the full-screen, one-step-at-a-time mode behind every
/// "Start cooking" control (canvas frames C, D, E, H).
///
/// Three things make it a **mode** rather than another layout of the recipe:
///
/// - **It is always dark.** The canvas is explicit about why: the phone is
///   propped on a counter under kitchen lighting, and a light page is glare. So
///   this subtree pins [AppTheme.dark] regardless of the platform's setting —
///   the only screen in the app that overrides the theme.
/// - **It owns a session** ([cookSessionProvider]): where the cook is, and every
///   running timer. Leaving and coming back resumes rather than restarts.
/// - **It is keyboard-driven on the web** (space advances, arrows move, escape
///   leaves), because at 1440 the laptop is across the counter and the pointer
///   is not in the cook's hand.
///
/// Signed-out safe, like recipe detail: nothing here writes until the finish
/// screen's rating, which handles the signed-out case itself.
class CookModeScreen extends ConsumerWidget {
  const CookModeScreen({super.key, required this.recipeId});

  final String recipeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(recipeProvider(recipeId));
    // Pinned dark, and pinned *outside* the AsyncValue branch so the loading and
    // error states are dark too — a white flash on the way into cook mode is
    // exactly the glare the mode exists to avoid.
    return Theme(
      data: AppTheme.dark(),
      child: Builder(
        builder:
            (context) => Scaffold(
              body: async.when(
                loading: () => const LoadingView(),
                error:
                    (e, _) => ErrorView(
                      message: friendlyError(e),
                      onRetry: () => ref.invalidate(recipeProvider(recipeId)),
                    ),
                data: (recipe) => _CookMode(recipe: recipe),
              ),
            ),
      ),
    );
  }
}

class _CookMode extends ConsumerWidget {
  const _CookMode({required this.recipe});

  final Recipe recipe;

  void _leave(BuildContext context) {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      // Deep-linked straight into cook mode: there is nothing to pop back to,
      // so go to the recipe rather than leaving the cook on a dead screen.
      context.go(Routes.recipe(recipe.id));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final steps = flattenCookSteps(recipe);
    if (steps.isEmpty) {
      return EmptyView(
        title: 'Nothing to cook yet',
        message:
            'This recipe has no steps written down, so there is nothing for '
            'cook mode to walk through.',
        icon: Icons.outdoor_grill,
        action: FilledButton(
          onPressed: () => _leave(context),
          child: const Text('Back to the recipe'),
        ),
      );
    }

    final session = ref.watch(cookSessionProvider(recipe.id));
    final notifier = ref.read(cookSessionProvider(recipe.id).notifier);
    // A recipe edited mid-session can be shorter than it was; clamping here
    // keeps the index in range without writing to the notifier during a build.
    final index = session.stepIndex.clamp(0, steps.length - 1);

    final Widget body =
        session.finished
            ? CookFinishView(
              recipe: recipe,
              steps: steps,
              startedAt: session.startedAt,
              onBackToRecipe: () => _leave(context),
              onReviewSteps: () => notifier.goTo(steps.length - 1),
            )
            : CookStepView(
              recipe: recipe,
              steps: steps,
              index: index,
              onClose: () => _leave(context),
            );

    // Shortcuts wrap both views: escape must leave from the finish screen too,
    // and `Focus(autofocus:)` is what makes any of them reach us at all — a
    // pointerless page has no focused node otherwise, so the keys go nowhere.
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () => _leave(context),
        const SingleActivator(LogicalKeyboardKey.space):
            () => notifier.next(steps.length),
        const SingleActivator(LogicalKeyboardKey.arrowRight):
            () => notifier.next(steps.length),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): notifier.previous,
      },
      child: Focus(autofocus: true, child: body),
    );
  }
}
