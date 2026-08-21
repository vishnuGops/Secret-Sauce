import 'package:cached_network_image/cached_network_image.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:app/widgets/share_dialog.dart';
import 'package:app/features/recipe_detail/recipe_detail_providers.dart';
import 'package:app/features/recipe_detail/version_history_sheet.dart';
import 'package:app/routing/app_router.dart';

class RecipeDetailScreen extends ConsumerWidget {
  const RecipeDetailScreen({super.key, required this.recipeId});

  final String recipeId;

  Future<void> _fork(BuildContext context, WidgetRef ref) async {
    try {
      final newId = await ref.read(recipeRepositoryProvider).fork(recipeId);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Forked to your recipes')),
        );
        context.go(Routes.editRecipe(newId));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(e))));
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
        error: (e, _) => Scaffold(
          appBar: AppBar(),
          body: ErrorView(
            message: friendlyError(e),
            onRetry: () => ref.invalidate(recipeProvider(recipeId)),
          ),
        ),
        data: (recipe) {
          final isOwner = currentUser != null && currentUser == recipe.ownerId;
          return CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 240,
                pinned: true,
                actions: [
                  IconButton(
                    tooltip: 'Version history',
                    icon: const Icon(Icons.history),
                    onPressed: () async {
                      final versions = await ref
                          .read(recipeVersionsProvider(recipeId).future);
                      if (context.mounted) {
                        await VersionHistorySheet.show(context, versions);
                      }
                    },
                  ),
                  if (isOwner) ...[
                    IconButton(
                      tooltip: 'Share',
                      icon: const Icon(Icons.share),
                      onPressed: () => ShareDialog.show(context, recipeId),
                    ),
                    IconButton(
                      tooltip: 'Edit',
                      icon: const Icon(Icons.edit),
                      onPressed: () => context.go(Routes.editRecipe(recipeId)),
                    ),
                  ],
                ],
                flexibleSpace: FlexibleSpaceBar(
                  title: Text(recipe.title),
                  background: recipe.coverImageUrl == null
                      ? Container(color: Theme.of(context).colorScheme.surfaceContainerHighest)
                      : CachedNetworkImage(
                          imageUrl: recipe.coverImageUrl!,
                          fit: BoxFit.cover,
                        ),
                ),
              ),
              SliverToBoxAdapter(
                child: _Body(recipe: recipe, isOwner: isOwner, onFork: () => _fork(context, ref)),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Like/save tap handler, shared by both buttons (B051).
///
/// Three things it must do that the old one-way `liked: true` call did not:
/// send a signed-out visitor to `/auth` instead of letting `_uid` throw
/// `StateError` inside an unawaited closure (Gotcha 9), pass the **opposite** of
/// the current state so the action is a toggle, and surface a failure instead of
/// swallowing it. Invalidating the state provider *and* the recipe refreshes
/// both the icon and the trigger-maintained counter.
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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$failure — ${friendlyError(e)}')));
    }
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.recipe, required this.isOwner, required this.onFork});

  final Recipe recipe;
  final bool isOwner;
  final VoidCallback onFork;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servings = ref.watch(selectedServingsProvider(recipe.id)) ?? recipe.servings;
    final factor = recipe.servings == 0 ? 1.0 : servings / recipe.servings;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (recipe.isFork)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                children: [
                  const Icon(Icons.call_split, size: 16),
                  const SizedBox(width: 4),
                  Text('Forked recipe', style: textTheme.labelMedium),
                ],
              ),
            ),
          // The owning chef, directly under the title in the collapsing app
          // bar. Null whenever the recipe was loaded without the owner
          // embedding — render nothing rather than an empty badge.
          if (recipe.owner != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: ChefBadge.fromProfile(recipe.owner!),
            ),
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: StarRating(
              rating: recipe.ratingAvg,
              count: recipe.ratingCount,
              size: 20,
            ),
          ),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              DifficultyBadge(difficulty: recipe.difficulty),
              _MetaChip(icon: Icons.schedule, label: '${recipe.totalMinutes} min total'),
              _MetaChip(icon: Icons.timer_outlined, label: 'Prep ${recipe.prepMinutes}m'),
              _MetaChip(icon: Icons.local_fire_department, label: 'Cook ${recipe.cookMinutes}m'),
              _MetaChip(
                icon: recipe.visibility.isPublic ? Icons.public : Icons.lock,
                label: recipe.visibility.isPublic ? 'Public' : 'Private',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (recipe.description.isNotEmpty)
            Text(recipe.description, style: textTheme.bodyLarge),
          if (recipe.attribution != null && recipe.attribution!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppRadii.card),
              ),
              child: Row(
                children: [
                  const Icon(Icons.auto_stories),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text(recipe.attribution!, style: textTheme.bodyMedium)),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              _CountAction(
                icon: Icons.favorite_border,
                activeIcon: Icons.favorite,
                active: ref.watch(myLikedProvider(recipe.id)).valueOrNull ?? false,
                count: recipe.likeCount,
                tooltip: 'Like',
                activeTooltip: 'Unlike',
                onTap: (active) => _toggleEngagement(
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
              _CountAction(
                icon: Icons.bookmark_border,
                activeIcon: Icons.bookmark,
                active: ref.watch(mySavedProvider(recipe.id)).valueOrNull ?? false,
                count: recipe.saveCount,
                tooltip: 'Save',
                activeTooltip: 'Remove from saved',
                onTap: (active) => _toggleEngagement(
                  context,
                  ref,
                  recipeId: recipe.id,
                  stateProvider: mySavedProvider(recipe.id),
                  write: (repo, next) => repo.setSaved(recipe.id, saved: next),
                  active: active,
                  failure: 'Could not update your save',
                ),
              ),
              const Spacer(),
              if (!isOwner)
                FilledButton.tonalIcon(
                  onPressed: onFork,
                  icon: const Icon(Icons.call_split),
                  label: const Text('Fork'),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _RatingSection(recipe: recipe, isOwner: isOwner),
          const Divider(height: AppSpacing.xl),
          // Servings scaler
          Row(
            children: [
              Text('Ingredients', style: textTheme.titleLarge),
              const Spacer(),
              IconButton.filledTonal(
                icon: const Icon(Icons.remove),
                onPressed: servings > 1
                    ? () => ref
                        .read(selectedServingsProvider(recipe.id).notifier)
                        .state = servings - 1
                    : null,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: Text('$servings servings', style: textTheme.titleMedium),
              ),
              IconButton.filledTonal(
                icon: const Icon(Icons.add),
                onPressed: () => ref
                    .read(selectedServingsProvider(recipe.id).notifier)
                    .state = servings + 1,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final group in recipe.ingredientGroups)
            _IngredientGroupView(group: group, factor: factor),
          const Divider(height: AppSpacing.xl),
          Text('Instructions', style: textTheme.titleLarge),
          const SizedBox(height: AppSpacing.sm),
          for (final group in recipe.stepGroups)
            _StepGroupView(group: group),
          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }
}

/// "Rate this recipe" block: half-star input for signed-in non-owners, plus the
/// current average. Owners see why they can't rate (RLS rejects self-ratings).
class _RatingSection extends ConsumerWidget {
  const _RatingSection({required this.recipe, required this.isOwner});

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

class _IngredientGroupView extends StatelessWidget {
  const _IngredientGroupView({required this.group, required this.factor});

  final IngredientGroup group;
  final double factor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (group.name.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: 4),
            child: Text(group.name,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
          ),
        for (final ing in group.ingredients)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 6, right: 8),
                  child: Icon(Icons.circle, size: 6),
                ),
                Expanded(
                  child: Text(
                    _format(ing),
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  String _format(Ingredient ing) {
    final parts = <String>[];
    if (ing.quantity != null) {
      final scaled = ing.quantity! * factor;
      parts.add(_trim(scaled));
    }
    if (ing.unit != null && ing.unit!.isNotEmpty) parts.add(ing.unit!);
    parts.add(ing.name);
    var text = parts.join(' ');
    if (ing.note != null && ing.note!.isNotEmpty) text += ' (${ing.note})';
    if (ing.isOptional) text += ' — optional';
    return text;
  }

  String _trim(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }
}

class _StepGroupView extends StatelessWidget {
  const _StepGroupView({required this.group});

  final StepGroup group;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (group.name.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: 4),
            child: Text(group.name,
                style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          ),
        for (var i = 0; i < group.steps.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(radius: 14, child: Text('${i + 1}')),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(group.steps[i].text, style: textTheme.bodyLarge),
                      _StepMeta(step: group.steps[i]),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _StepMeta extends StatelessWidget {
  const _StepMeta({required this.step});
  final RecipeStep step;

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[
      if (step.durationMinutes != null)
        _MetaChip(icon: Icons.timer, label: '${step.durationMinutes} min'),
      if (step.temperature != null && step.temperature!.isNotEmpty)
        _MetaChip(icon: Icons.thermostat, label: step.temperature!),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (chips.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(spacing: AppSpacing.sm, children: chips),
          ),
        if (step.tip != null && step.tip!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Tip: ${step.tip}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontStyle: FontStyle.italic,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    )),
          ),
      ],
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
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

class _CountAction extends StatelessWidget {
  const _CountAction({
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
        label: Text('$count'),
      ),
    );
  }
}
