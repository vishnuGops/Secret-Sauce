import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:app/features/recipe_detail/recipe_detail_providers.dart';
import 'package:app/routing/app_router.dart';

/// The small controls the detail screen's header row is built from: a
/// read-only metadata chip, the like/save counter button, and the paired
/// like+save row both layouts share (OPT-A8).

/// Cook mode (the v2 canvas's C/D/E/H frames) is not built yet; every
/// "Start cooking" control is inert behind this message until it is.
const kCookModeSoon =
    'Cook mode is on the way — follow the steps in order for now.';

class MetaChip extends StatelessWidget {
  const MetaChip({super.key, required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: scheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}

/// Like + save, wired. One widget so the v1 body and the v2 header band cannot
/// drift apart on the toggle behaviour B051 fixed.
class LikeSaveButtons extends ConsumerWidget {
  const LikeSaveButtons({super.key, required this.recipe});

  final Recipe recipe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CountAction(
          icon: Icons.favorite_border,
          activeIcon: Icons.favorite,
          active: ref.watch(myLikedProvider(recipe.id)).valueOrNull ?? false,
          count: recipe.likeCount,
          tooltip: 'Like',
          activeTooltip: 'Unlike',
          onTap:
              (active) => _toggleEngagement(
                context,
                ref,
                recipeId: recipe.id,
                stateProvider: myLikedProvider(recipe.id),
                write: (repo, next) => repo.setLiked(recipe.id, liked: next),
                active: active,
                failure: 'Could not update your like',
              ),
        ),
        const SizedBox(width: AppSpacing.md),
        CountAction(
          icon: Icons.bookmark_border,
          activeIcon: Icons.bookmark,
          active: ref.watch(mySavedProvider(recipe.id)).valueOrNull ?? false,
          count: recipe.saveCount,
          tooltip: 'Save',
          activeTooltip: 'Remove from saved',
          onTap:
              (active) => _toggleEngagement(
                context,
                ref,
                recipeId: recipe.id,
                stateProvider: mySavedProvider(recipe.id),
                write: (repo, next) => repo.setSaved(recipe.id, saved: next),
                active: active,
                failure: 'Could not update your save',
              ),
        ),
      ],
    );
  }
}

/// Like/save tap handler, shared by both buttons (B051).
///
/// Three things it must do that the old one-way `liked: true` call did not:
/// send a signed-out visitor to `/auth` instead of letting `_uid` throw
/// `StateError` inside an unawaited closure (Gotcha 9), pass the **opposite**
/// of the current state so the action is a toggle, and surface a failure
/// instead of swallowing it. Invalidating the state provider *and* the recipe
/// refreshes both the icon and the trigger-maintained counter.
Future<void> _toggleEngagement(
  BuildContext context,
  WidgetRef ref, {
  required String recipeId,
  required ProviderBase<AsyncValue<bool>> stateProvider,
  required Future<void> Function(RecipeRepository repo, bool next) write,
  required bool active,
  required String failure,
}) async {
  if (ref.read(currentUserIdProvider) == null) {
    context.go(Routes.auth);
    return;
  }
  try {
    await write(ref.read(recipeRepositoryProvider), !active);
    ref.invalidate(stateProvider);
    ref.invalidate(recipeProvider(recipeId));
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$failure — ${friendlyError(e)}')));
    }
  }
}

class CountAction extends StatelessWidget {
  const CountAction({
    super.key,
    required this.icon,
    required this.activeIcon,
    required this.active,
    required this.count,
    required this.tooltip,
    required this.activeTooltip,
    required this.onTap,
  });

  final IconData icon;

  /// Filled variant, shown once the current user has liked/saved this recipe.
  /// This was a dead parameter until B051 gave the screen something to read.
  final IconData activeIcon;
  final bool active;
  final int count;
  final String tooltip;
  final String activeTooltip;

  /// Receives the state the button is currently in, so the handler can write
  /// the opposite of it.
  final void Function(bool active) onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: active ? activeTooltip : tooltip,
      child: OutlinedButton.icon(
        onPressed: () => onTap(active),
        icon: Icon(
          active ? activeIcon : icon,
          size: 18,
          color: active ? scheme.primary : null,
        ),
        // Grouped, like every other counter in the product (B031's family):
        // a recipe with 1,500 likes read `1500` here and `1,500` on the chef
        // card three taps away.
        label: Text(groupedCount(count)),
      ),
    );
  }
}
