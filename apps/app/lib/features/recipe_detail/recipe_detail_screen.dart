import 'package:cached_network_image/cached_network_image.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:app/features/my_recipes/share_dialog.dart';
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
            .showSnackBar(SnackBar(content: Text('Fork failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(recipeProvider(recipeId));
    final currentUser = ref.watch(currentUserIdProvider);

    return Scaffold(
      body: async.when(
        loading: () => const Scaffold(body: LoadingView()),
        error: (e, _) => Scaffold(
          appBar: AppBar(),
          body: ErrorView(
            message: e.toString(),
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
                count: recipe.likeCount,
                onTap: () async {
                  await ref
                      .read(recipeRepositoryProvider)
                      .setLiked(recipe.id, liked: true);
                  ref.invalidate(recipeProvider(recipe.id));
                },
              ),
              const SizedBox(width: AppSpacing.md),
              _CountAction(
                icon: Icons.bookmark_border,
                activeIcon: Icons.bookmark,
                count: recipe.saveCount,
                onTap: () async {
                  await ref
                      .read(recipeRepositoryProvider)
                      .setSaved(recipe.id, saved: true);
                  ref.invalidate(recipeProvider(recipe.id));
                },
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
    required this.count,
    required this.onTap,
  });

  final IconData icon;
  final IconData activeIcon;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text('$count'),
    );
  }
}
