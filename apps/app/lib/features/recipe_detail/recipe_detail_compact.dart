import 'package:cached_network_image/cached_network_image.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:app/features/recipe_detail/detail_chips.dart';
import 'package:app/features/recipe_detail/rail_panel.dart';
import 'package:app/features/recipe_detail/method_column.dart';
import 'package:app/features/recipe_detail/rating_section.dart';
import 'package:app/features/recipe_detail/recipe_detail_expanded.dart'
    show FactsStrip;
import 'package:app/features/recipe_detail/recipe_detail_providers.dart';
import 'package:app/features/recipe_detail/version_history_sheet.dart';
import 'package:app/routing/app_router.dart';
import 'package:app/widgets/share_dialog.dart';

/// The v2 reading page below 1000px — the canvas's frame B, with frame F's owner
/// state folded in.
///
/// This **replaced** the v1 hero layout rather than sitting beside it, so the
/// page below 1000px is no longer a different design from the page above it. It
/// serves compact *and* medium: the canvas draws no medium screen, and a
/// single-column cover-first page reads correctly at 800px, whereas keeping v1
/// alive for the 600–1000 band would have meant maintaining a third layout for a
/// width nobody designed.
///
/// Reading order is the canvas's: cover → identity → facts → **jump bar** →
/// ingredients → method, with `Ready to cook?` pinned to the bottom so the one
/// thing you came to do is always one tap away.
class RecipeDetailCompact extends ConsumerStatefulWidget {
  const RecipeDetailCompact({
    super.key,
    required this.recipe,
    required this.isOwner,
    required this.onFork,
  });

  final Recipe recipe;
  final bool isOwner;
  final VoidCallback onFork;

  @override
  ConsumerState<RecipeDetailCompact> createState() =>
      _RecipeDetailCompactState();
}

class _RecipeDetailCompactState extends ConsumerState<RecipeDetailCompact> {
  // The jump bar's targets. `Scrollable.ensureVisible` needs a laid-out element,
  // which is why these are keys on the section headers rather than offsets: an
  // offset would have to be recomputed for every text scale and every recipe
  // length, and would be wrong for the first frame.
  final _ingredientsKey = GlobalKey();
  final _methodKey = GlobalKey();

  // Named methods rather than `() => _jumpTo(key)` lambdas at the call site, so
  // the values handed to the pinned header are **identity-stable** across
  // builds. A tear-off of an instance method on the same receiver compares
  // equal; a fresh closure never does, and `shouldRebuild` comparing fresh
  // closures would answer true on every single build — rebuilding a pinned
  // sliver every frame, which is worse than the incomplete comparison it was
  // meant to fix.
  // Also resets the rail to the Ingredients tab (Phase 28). The chip promises
  // to take you to the ingredient list, and after a visit to the Nutrition tab
  // that list is not on screen — scrolling to a section whose content is hidden
  // behind the other tab is the chip lying about where it went.
  void _jumpToIngredients() {
    ref.read(railTabProvider(widget.recipe.id).notifier).state =
        RailTab.ingredients;
    _jumpTo(_ingredientsKey);
  }

  void _jumpToMethod() => _jumpTo(_methodKey);

  Future<void> _jumpTo(GlobalKey key) async {
    final ctx = key.currentContext;
    if (ctx == null) return;
    await Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      // Leaves the pinned jump bar's own height clear of the heading it just
      // scrolled to, instead of parking the heading underneath it.
      alignment: 0.08,
    );
  }

  @override
  Widget build(BuildContext context) {
    final recipe = widget.recipe;
    return Column(
      children: [
        Expanded(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: _Cover(recipe: recipe, isOwner: widget.isOwner),
              ),
              SliverToBoxAdapter(
                child: _IdentityBand(recipe: recipe, isOwner: widget.isOwner),
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _JumpBarDelegate(
                  textScale: context.textScale,
                  onIngredients: _jumpToIngredients,
                  onMethod: _jumpToMethod,
                  onFork: widget.isOwner ? null : widget.onFork,
                ),
              ),
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Same widget as the expanded page's left column, minus the
                    // card border: full-width here, a column there, one
                    // implementation either way.
                    KeyedSubtree(
                      key: _ingredientsKey,
                      child: RailPanel(recipe: recipe, bordered: false),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: KeyedSubtree(
                        key: _methodKey,
                        child: MethodColumn(recipe: recipe),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md,
                        0,
                        AppSpacing.md,
                        AppSpacing.xl,
                      ),
                      child: RatingSection(
                        recipe: recipe,
                        isOwner: widget.isOwner,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        _ReadyToCookBar(recipe: recipe),
      ],
    );
  }
}

/// The full-bleed cover with the page's chrome floating on it.
///
/// A recipe with no cover gets the same band in `surfaceContainerHighest` at a
/// shorter height rather than a grey rectangle pretending to be a photo — no
/// seeded recipe carries a cover, so this is the state the local stack always
/// shows and it has to look deliberate.
class _Cover extends ConsumerWidget {
  const _Cover({required this.recipe, required this.isOwner});

  final Recipe recipe;
  final bool isOwner;

  Future<void> _showVersions(BuildContext context, WidgetRef ref) async {
    final versions = await ref.read(recipeVersionsProvider(recipe.id).future);
    if (context.mounted) await VersionHistorySheet.show(context, versions);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final hasCover = recipe.coverImageUrl != null;
    // Bounded against text scale like every other fixed-height region here: the
    // bar of icon buttons on top of it grows with the type (Gotcha 22).
    final height =
        (hasCover ? 210.0 : 96.0) * context.textScale.clamp(1.0, 1.6);

    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (hasCover)
            CachedNetworkImage(
              imageUrl: recipe.coverImageUrl!,
              fit: BoxFit.cover,
            )
          else
            ColoredBox(color: scheme.surfaceContainerHighest),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              child: Row(
                children: [
                  _ScrimButton(
                    icon: Icons.arrow_back,
                    tooltip: 'Back',
                    onCover: hasCover,
                    onPressed: () => _leave(context),
                  ),
                  const Spacer(),
                  _ScrimButton(
                    icon: Icons.history,
                    tooltip: 'Version history',
                    onCover: hasCover,
                    onPressed: () => _showVersions(context, ref),
                  ),
                  if (isOwner) ...[
                    const SizedBox(width: AppSpacing.xs),
                    _ScrimButton(
                      icon: Icons.share,
                      tooltip: 'Share',
                      onCover: hasCover,
                      onPressed: () => ShareDialog.show(context, recipe.id),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    _ScrimButton(
                      icon: Icons.edit,
                      tooltip: 'Edit',
                      onCover: hasCover,
                      onPressed: () => context.go(Routes.editRecipe(recipe.id)),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (!recipe.visibility.isPublic)
            Positioned(
              left: AppSpacing.md,
              bottom: AppSpacing.sm,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: scheme.surface.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      'Private',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _leave(BuildContext context) {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      context.go(Routes.discover);
    }
  }
}

/// An icon button legible on a photo *and* on a flat surface — the two states
/// the cover has. On a photo it carries its own scrim, because a themed icon
/// colour over an unknown image is the B055 mistake (a colour chosen against one
/// background, painted on another).
class _ScrimButton extends StatelessWidget {
  const _ScrimButton({
    required this.icon,
    required this.tooltip,
    required this.onCover,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final bool onCover;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    if (!onCover) {
      return IconButton(
        tooltip: tooltip,
        icon: Icon(icon),
        onPressed: onPressed,
      );
    }
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon),
      style: IconButton.styleFrom(
        backgroundColor: Colors.black.withValues(alpha: 0.4),
        foregroundColor: Colors.white,
      ),
      onPressed: onPressed,
    );
  }
}

/// Lineage, title, chef, rating, description, attribution, facts quad.
class _IdentityBand extends StatelessWidget {
  const _IdentityBand({required this.recipe, required this.isOwner});

  final Recipe recipe;
  final bool isOwner;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Lineage above the title (frame F). Naming the parent needs a second
          // read the page does not make, so it says what it knows.
          if (recipe.isFork) ...[
            Row(
              children: [
                Icon(Icons.call_split, size: 16, color: scheme.primary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Forked recipe',
                    style: textTheme.labelMedium?.copyWith(
                      color: scheme.primary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
          Text(recipe.title, style: textTheme.headlineSmall),
          const SizedBox(height: AppSpacing.sm),
          // Wrap, not Row: the chef badge and the stars are both intrinsically
          // sized and together exceed 390px at 2.0× (Gotcha 21).
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (recipe.owner != null)
                ChefBadge.fromProfile(
                  recipe.owner!,
                  onTap: () => context.push(Routes.chef(recipe.owner!.id)),
                ),
              StarRating(
                rating: recipe.ratingAvg,
                count: recipe.ratingCount,
                size: 18,
              ),
            ],
          ),
          if (recipe.description.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text(recipe.description, style: textTheme.bodyMedium),
          ],
          if ((recipe.attribution ?? '').isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLowest,
                border: Border.all(color: scheme.outlineVariant),
                borderRadius: BorderRadius.circular(AppRadii.card),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.auto_stories,
                    size: 20,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      recipe.attribution!,
                      style: textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          FactsStrip(recipe: recipe, quad: true),
          const SizedBox(height: AppSpacing.md),
          LikeSaveButtons(recipe: recipe),
        ],
      ),
    );
  }
}

/// The pinned jump bar.
///
/// Its content scrolls **horizontally**: a pinned sliver has one fixed height,
/// so a `Wrap` cannot save it and a `Row` of intrinsically-sized chips is the
/// unbounded-child overflow (Gotcha 21) waiting to happen at 2.0×. A horizontal
/// scroller can never overflow in the axis that matters, which leaves the height
/// as the only thing to get right — and that is bounded against text scale.
class _JumpBarDelegate extends SliverPersistentHeaderDelegate {
  _JumpBarDelegate({
    required this.textScale,
    required this.onIngredients,
    required this.onMethod,
    required this.onFork,
  });

  final double textScale;
  final VoidCallback onIngredients;
  final VoidCallback onMethod;

  /// Null for the owner — you cannot fork your own recipe.
  final VoidCallback? onFork;

  double get _extent => 56 * textScale.clamp(1.0, 1.8);

  @override
  double get minExtent => _extent;

  @override
  double get maxExtent => _extent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      alignment: Alignment.centerLeft,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        child: Row(
          children: [
            ActionChip(
              label: const Text('Ingredients'),
              onPressed: onIngredients,
            ),
            const SizedBox(width: AppSpacing.sm),
            ActionChip(label: const Text('Method'), onPressed: onMethod),
            if (onFork != null) ...[
              const SizedBox(width: AppSpacing.sm),
              ActionChip(
                avatar: const Icon(Icons.call_split, size: 16),
                label: const Text('Fork'),
                onPressed: onFork,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Every field that changes what [build] produces, and nothing that does not.
  ///
  /// `onIngredients` / `onMethod` are compared by identity, which only works
  /// because the State passes **method tear-offs** rather than fresh lambdas
  /// (see `_jumpToIngredients`): a tear-off on the same receiver compares equal,
  /// a closure built in `build` never does. Comparing a fresh closure here would
  /// answer true on every build and rebuild this pinned sliver every frame —
  /// worse than the incomplete comparison it looks like it is fixing.
  ///
  /// `onFork` is compared by **nullability only**, deliberately: it arrives from
  /// the screen above as `() => _fork(context, ref)`, a fresh closure per build
  /// that this widget does not own. The only thing it changes about the render is
  /// whether the Fork chip exists at all, and the newest delegate's closure is
  /// what runs whenever anything else does trigger a rebuild.
  @override
  bool shouldRebuild(_JumpBarDelegate old) =>
      old.textScale != textScale ||
      old.onIngredients != onIngredients ||
      old.onMethod != onMethod ||
      (old.onFork == null) != (onFork == null);
}

/// `Ready to cook?` — pinned to the bottom of the page, outside the scroll.
///
/// A `Column(Expanded(scroll), bar)` rather than a `Stack` with a reserved
/// bottom padding: the bar's height grows with text scale, and any reserve
/// constant would be wrong at some scale — either overlapping the last step or
/// leaving a gap. Sized by its own content, it is right at every scale.
class _ReadyToCookBar extends StatelessWidget {
  const _ReadyToCookBar({required this.recipe});

  final Recipe recipe;

  /// Above this the label and the button stop being a row. `Start cooking` is
  /// ~390px at 2.0× — the whole width of the phone — so it takes its own line
  /// (the shape `_CookModeTeaser` and `/chefs` both use).
  static const double _kStackScale = 1.3;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final steps = recipe.stepGroups.fold<int>(
      0,
      (sum, g) => sum + g.steps.length,
    );

    final labels = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${countOf(steps, 'steps')} · ${formatMinutes(recipe.totalMinutes)}',
          style: textTheme.labelMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        Text('Ready to cook?', style: textTheme.titleMedium),
      ],
    );
    final button = FilledButton.icon(
      onPressed: () => context.push(Routes.cookRecipe(recipe.id)),
      icon: const Icon(Icons.outdoor_grill),
      label: const Text('Start cooking'),
    );

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        12,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: SafeArea(
        top: false,
        child:
            context.textScale > _kStackScale
                ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    labels,
                    const SizedBox(height: AppSpacing.sm),
                    button,
                  ],
                )
                : Row(
                  children: [
                    Expanded(child: labels),
                    const SizedBox(width: AppSpacing.md),
                    button,
                  ],
                ),
      ),
    );
  }
}
