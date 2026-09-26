import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app/features/my_recipes/my_recipes_providers.dart';
import 'package:app/features/recipe_detail/recipe_detail_providers.dart';
import 'package:app/routing/auth_return.dart';

/// The small controls the detail screen's header row is built from: the
/// kicker and tag pills (36c), a read-only metadata chip, the like/save
/// counter button, and the paired like+save row both layouts share (OPT-A8).
///
/// `kCookModeSoon` used to live here, holding every "Start cooking" control
/// inert behind a tooltip. Cook mode is built, so the constant is gone rather
/// than kept "just in case" — a message about an unbuilt feature outliving the
/// feature is how dead copy ships.

/// The index line over the title — reference 5's accent `RECIPE` kicker
/// (Phase 36c). It names the category when the recipe has one, because that
/// says more than the word "recipe" on a page that is obviously a recipe.
class DetailKicker extends StatelessWidget {
  const DetailKicker({super.key, required this.recipe});

  final Recipe recipe;

  /// Always `RECIPE` (reference 5). It used to be the category, which on a
  /// photo-less recipe printed it three times over — on the colour-block
  /// cover, in the kicker and in the tag pill. The cover and the pill already
  /// say what kind of dish it is; the kicker names what the page is.
  static String labelFor(Recipe recipe) => 'RECIPE';

  @override
  Widget build(BuildContext context) {
    return Text(
      labelFor(recipe),
      style: context.appText.kickerLarge.copyWith(
        color: Theme.of(context).colorScheme.tertiary,
      ),
    );
  }
}

/// What a recipe *is*, as filled pills: its cuisine and its category
/// (reference 5's tags, Phase 36c) — and, on the compact page, `Private`.
///
/// A `Wrap`, so a long cuisine goes to a second line rather than overflowing
/// (Gotcha 21). Callers ask [hasAny] first, so an untagged recipe leaves no
/// empty row and no orphaned gap.
class DetailTags extends StatelessWidget {
  const DetailTags({super.key, required this.recipe, this.showPrivate = false});

  final Recipe recipe;

  /// Add a `Private` pill for a recipe that is not public. The compact page
  /// does; the expanded page already says it in the facts strip.
  final bool showPrivate;

  static List<String> _labels(Recipe recipe) {
    final cuisine = (recipe.cuisine ?? '').trim();
    final category = (recipe.category ?? '').trim();
    return [
      if (cuisine.isNotEmpty) cuisine,
      if (category.isNotEmpty &&
          category.toLowerCase() != cuisine.toLowerCase())
        category,
    ];
  }

  static bool hasAny(Recipe recipe, {bool showPrivate = false}) =>
      (showPrivate && !recipe.visibility.isPublic) ||
      _labels(recipe).isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        if (showPrivate && !recipe.visibility.isPublic)
          const TagPill(icon: Icons.lock, label: 'Private'),
        for (final label in _labels(recipe)) TagPill(label: label),
      ],
    );
  }
}

class MetaChip extends StatelessWidget {
  /// [icon] is optional: cook mode's "you'll need" chips are ingredient names,
  /// where an icon in front of every one of six chips is noise.
  const MetaChip({
    super.key,
    this.icon,
    required this.label,
    this.large = false,
    this.semanticsLabel,
  });
  final IconData? icon;
  final String label;

  /// What a screen reader says instead of [label] — cook mode's ingredient
  /// chips pass `ingredientOneLineSpoken`, so `1 1⁄3 cup` is heard as "1 and 1
  /// third cup" rather than "fraction slash". Null reads [label].
  final String? semanticsLabel;

  /// Cook mode's step facts (UX-024): `titleMedium` text and a
  /// [AppIconSize.lg] icon, read from across a counter. The reading page and
  /// cook mode's informational chips keep the small `labelSmall` pill.
  final bool large;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding:
          large
              ? const EdgeInsets.symmetric(
                horizontal: AppSpacing.smPlus,
                vertical: AppSpacing.xsPlus,
              )
              : const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: large ? AppIconSize.lg : AppIconSize.xs,
              color: scheme.onSurfaceVariant,
            ),
            SizedBox(width: large ? AppSpacing.sm : AppSpacing.xs),
          ],
          // Flexible, and wrapping to two lines, because the label is not
          // always a short fact. Cook mode puts a whole ingredient
          // ("1¼ cup Unbleached wheat flour") in one of these, which is wider
          // than a 390px phone can hold — and a `Text` in a `Row` with no
          // flexible sibling is laid out at its intrinsic width and overflows
          // rather than shrinking (Gotcha 21). Two lines instead of one so a
          // long ingredient wraps inside the pill instead of ellipsising the
          // part that says which ingredient it is.
          Flexible(
            child: Text(
              label,
              semanticsLabel: semanticsLabel,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: large ? textTheme.titleMedium : textTheme.labelSmall,
            ),
          ),
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
                // The Saved tab (UX-020) sits in the shell under this pushed
                // page, so it stays alive; without this an unsaved recipe is
                // still listed when the reader backs out to it.
                alsoRefresh: [savedRecipesProvider],
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
  List<ProviderOrFamily> alsoRefresh = const [],
}) async {
  if (ref.read(currentUserIdProvider) == null) {
    // UX-017: `?from=` brings the visitor back to this recipe to finish the
    // like or save they started.
    goToSignIn(context);
    return;
  }
  // The container, captured before the await: a reader who backs out while
  // the write is in flight unmounts this element, and `ref.invalidate` on a
  // dead element throws — into the catch below, silently — so the Saved tab
  // under the page kept an unsaved recipe (Phase 37 review).
  final container = ProviderScope.containerOf(context, listen: false);
  try {
    await write(container.read(recipeRepositoryProvider), !active);
    container.invalidate(stateProvider);
    container.invalidate(recipeProvider(recipeId));
    for (final provider in alsoRefresh) {
      container.invalidate(provider);
    }
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
          size: AppIconSize.button,
          color: active ? scheme.primary : null,
        ),
        // Grouped, like every other counter in the product (B031's family):
        // a recipe with 1,500 likes read `1500` here and `1,500` on the chef
        // card three taps away. Tabular so a like that takes 9 to 10 does not
        // shift the icon (UX-049); merged over the button's label style.
        label: Text(
          groupedCount(count),
          style: const TextStyle(fontFeatures: kTabularFigures),
        ),
      ),
    );
  }
}
