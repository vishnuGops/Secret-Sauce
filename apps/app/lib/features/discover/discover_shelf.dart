import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:app/features/discover/discover_providers.dart';
import 'package:app/routing/app_router.dart';

/// One numbered shelf on Discover: a [CardRail] of [RecipeCard]s over a
/// [FutureProvider] of rows.
///
/// The three shelves differ in four strings, one provider and an accent, so
/// they are one widget configured three times rather than three widgets — and
/// the ranking rule each one uses is *printed on it* ([kicker]), because a
/// shelf that will not say why these twelve recipes is just a row of pictures.
class DiscoverShelf extends ConsumerWidget {
  const DiscoverShelf({
    super.key,
    required this.index,
    required this.title,
    required this.subtitle,
    required this.kicker,
    required this.accent,
    required this.provider,
    required this.emptyReason,
  });

  /// The set numeral — `01`.
  final String index;
  final String title;
  final String subtitle;

  /// The ranking rule, in caps: `RANKED BY SAVES`.
  final String kicker;

  final Color accent;
  final AutoDisposeFutureProvider<List<Recipe>> provider;

  /// What to say when the shelf has no rows — the *reason*, not "nothing here".
  ///
  /// Two of the three shelves are genuinely empty on a database that has only
  /// had `seed.sql` and `seed_recipes.sql` applied: the fourteen authored
  /// recipes top out at 85 minutes and none of them has ever been forked. That
  /// is a fixture fact, not a failure, and the strip says so rather than
  /// implying the query broke.
  final String emptyReason;

  /// Card width inside the rail. The narrow value is deliberate on a phone: at
  /// [kRecipeCardMinWidth] the next card peeks past the screen edge, which is
  /// the only affordance a touch rail gets once the arrows are dropped.
  static double cardWidthFor(BuildContext context) =>
      context.isCompact ? kRecipeCardMinWidth : kRecipeCardMaxWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(provider);
    final recipes = async.valueOrNull ?? const <Recipe>[];
    // Three states, not two: a shelf that has loaded and is genuinely empty
    // must not render placeholders, which would read as loading forever.
    final loading = async.isLoading && recipes.isEmpty;
    final cardWidth = cardWidthFor(context);

    if (async.hasError) {
      return _Strip(
        accent: accent,
        index: index,
        title: title,
        child: ErrorView(
          message: friendlyError(async.error),
          onRetry: () => ref.invalidate(provider),
        ),
      );
    }
    if (!loading && recipes.isEmpty) {
      return _Strip(
        accent: accent,
        index: index,
        title: title,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.lg,
          ),
          child: Text(
            emptyReason,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return CardRail(
      variant: CardRailVariant.numbered,
      index: index,
      title: title,
      subtitle: subtitle,
      kicker: kicker,
      accent: accent,
      height: kRecipeCardHeight,
      cardWidth: cardWidth,
      // An arrow press moves one card on a phone and three on a pointer: three
      // cards is most of a phone screen, and a rail that jumps that far reads
      // as a page change rather than a scroll.
      page: context.isCompact ? 1 : 3,
      itemCount: loading ? kShelfLength : recipes.length,
      itemBuilder:
          (context, i) => SizedBox(
            // A horizontal ListView hands its child a tight height and an
            // unbounded width, and `RecipeCard` does not fix its own.
            width: cardWidth,
            child:
                loading
                    ? const RecipeCardPlaceholder()
                    : RecipeCard(
                      recipe: recipes[i],
                      onTap: () => context.push(Routes.recipe(recipes[i].id)),
                    ),
          ),
    );
  }
}

/// The shelf header over something that is not a rail — an error or a reason.
///
/// Keeps the numeral and the title so the page still reads as three shelves
/// when one of them has nothing in it, and stays the height of its content
/// rather than a card: three full-size empty states would be the whole page.
class _Strip extends StatelessWidget {
  const _Strip({
    required this.accent,
    required this.index,
    required this.title,
    required this.child,
  });

  final Color accent;
  final String index;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text(
              index,
              style: theme.textTheme.titleLarge?.copyWith(
                color: accent,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Text(
                title.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: theme.colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(AppRadii.card),
          ),
          child: child,
        ),
      ],
    );
  }
}
