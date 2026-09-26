import 'package:cached_network_image/cached_network_image.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:app/features/recipe_detail/delete_action.dart';
import 'package:app/features/recipe_detail/detail_chips.dart';
import 'package:app/features/recipe_detail/detail_provenance.dart';
import 'package:app/features/recipe_detail/rail_panel.dart';
import 'package:app/features/recipe_detail/method_column.dart';
import 'package:app/features/recipe_detail/rating_section.dart';
import 'package:app/features/recipe_detail/recipe_detail_expanded.dart'
    show FactsStrip;
import 'package:app/features/recipe_detail/recipe_detail_providers.dart';
import 'package:app/features/recipe_detail/version_history_sheet.dart';
import 'package:app/routing/app_router.dart';
import 'package:app/routing/pop_or_go.dart';
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
/// thing you came to do is always one tap away. Phase 36c dressed it in
/// reference 5's language: the identity is a white sheet riding up over the
/// cover, and ingredients and method are two open panels (the owner's Q4).
class RecipeDetailCompact extends ConsumerStatefulWidget {
  const RecipeDetailCompact({
    super.key,
    required this.recipe,
    required this.isOwner,
    required this.onFork,
    this.forking = false,
  });

  final Recipe recipe;
  final bool isOwner;
  final VoidCallback onFork;

  /// A fork is in flight: the jump bar's Fork chip renders disabled (B129).
  final bool forking;

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
      // Collapses to a jump under reduced motion (UX-050).
      duration: AppMotion.of(context, AppMotion.normal),
      curve: AppMotion.decelerate,
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
                child: _CoverAndSheet(recipe: recipe, isOwner: widget.isOwner),
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _JumpBarDelegate(
                  textScale: context.textScale,
                  onIngredients: _jumpToIngredients,
                  onMethod: _jumpToMethod,
                  onFork: widget.isOwner ? null : widget.onFork,
                  forking: widget.forking,
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.md,
                    AppSpacing.md,
                    AppSpacing.xl,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Ingredients and Method are two open panels (the
                      // owner's Q4, 2026-09-25): reference 5's rounded panels
                      // without its accordions — a recipe is read top to
                      // bottom, and a collapsed method is one more tap between
                      // a cook and the next step. Same widgets as the expanded
                      // page's two columns, one implementation either way.
                      KeyedSubtree(
                        key: _ingredientsKey,
                        child: RailPanel(recipe: recipe),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      KeyedSubtree(
                        key: _methodKey,
                        child: MethodColumn(recipe: recipe),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      RatingSection(recipe: recipe, isOwner: widget.isOwner),
                    ],
                  ),
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

/// How far the identity sheet rides up over the cover — its own corner
/// radius, so the rounded corners always have cover behind them, never page.
const double _kSheetOverlap = AppRadii.sheet;

/// The cover with the identity sheet laid over its bottom edge — reference 5's
/// "sheet over the photo" (Phase 36c).
///
/// A `Stack` rather than a `Transform` on the sheet: a translated sheet keeps
/// its old layout slot, which leaves a gap the height of the overlap between
/// it and the pinned jump bar. Here the sheet is the stack's only
/// non-positioned child, so the stack is exactly cover − overlap + sheet tall
/// and the cover sits behind the sheet's rounded top corners.
/// `StackFit.passthrough` hands the sheet the sliver's tight width, so it
/// spans the page whatever its content measures.
class _CoverAndSheet extends StatelessWidget {
  const _CoverAndSheet({required this.recipe, required this.isOwner});

  final Recipe recipe;
  final bool isOwner;

  @override
  Widget build(BuildContext context) {
    final coverHeight = _Cover.heightOf(context);
    return Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: coverHeight,
          child: _Cover(recipe: recipe, isOwner: isOwner),
        ),
        Padding(
          padding: EdgeInsets.only(top: coverHeight - _kSheetOverlap),
          child: _IdentityBand(recipe: recipe),
        ),
      ],
    );
  }
}

/// The full-bleed cover with the page's chrome floating on it.
///
/// A recipe with no photograph gets its category's colour block
/// ([CategoryCover], the owner's Q1) at the same height — a designed state,
/// not a grey rectangle pretending to be a photo. No curated recipe carries a
/// cover, so this is what the local stack always shows.
class _Cover extends ConsumerWidget {
  const _Cover({required this.recipe, required this.isOwner});

  final Recipe recipe;
  final bool isOwner;

  /// The band's height at 1.0×, photo and colour block alike.
  static const double _kCoverHeight = 210;

  /// Past this text scale the band stops growing with the type.
  static const double _kMaxGrowth = 1.6;

  /// Bounded against text scale like every other fixed-height region here:
  /// the bar of icon buttons on top of it grows with the type (Gotcha 22).
  ///
  /// Plus the top inset: the cover is full-bleed, so it runs under the status
  /// bar, and the chrome's `SafeArea` pushes the button row down by exactly
  /// that much. Without it a notched phone loses a status bar's worth of band
  /// and the colour block's bottom-left label meets the back button.
  static double heightOf(BuildContext context) =>
      _kCoverHeight * context.textScale.clamp(1.0, _kMaxGrowth) +
      MediaQuery.paddingOf(context).top;

  Future<void> _showVersions(BuildContext context, WidgetRef ref) async {
    final versions = await ref.read(recipeVersionsProvider(recipe.id).future);
    if (context.mounted) await VersionHistorySheet.show(context, versions);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // `displayCoverImageUrl`, not `coverImageUrl`: an imported recipe
    // whose publisher asked for no images has one and must not show it
    // (Phase 35c). The whole layout branches on this, so reading the raw
    // column here would put the picture back in a cover-first design.
    final coverUrl = recipe.displayCoverImageUrl;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (coverUrl != null)
          CachedNetworkImage(imageUrl: coverUrl, fit: BoxFit.cover)
        else
          // The block runs on under the sheet's corners; its label is lifted
          // clear of the overlap so the sheet never cuts it.
          ColoredBox(
            color: context.palette.category(recipe.category).background,
            child: Padding(
              padding: const EdgeInsets.only(bottom: _kSheetOverlap),
              child: CategoryCover(category: recipe.category, large: true),
            ),
          ),
        SafeArea(
          // Pinned to the top. Under the expanding stack a bare `Row` is
          // centred vertically in the band — harmless on a photo, but the
          // colour block sets its label in the lower half, where a centred
          // back button lands on it.
          child: Align(
            alignment: Alignment.topCenter,
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
                    onPressed: () => popOrGo(context, Routes.discover),
                  ),
                  const Spacer(),
                  _ScrimButton(
                    icon: Icons.history,
                    tooltip: 'Version history',
                    onPressed: () => _showVersions(context, ref),
                  ),
                  if (isOwner) ...[
                    const SizedBox(width: AppSpacing.xs),
                    _ScrimButton(
                      icon: Icons.share,
                      tooltip: 'Share',
                      onPressed: () => ShareDialog.show(context, recipe.id),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    _ScrimButton(
                      icon: Icons.edit,
                      tooltip: 'Edit',
                      onPressed: () => context.go(Routes.editRecipe(recipe.id)),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    // UX-037: Delete behind "More", in the same scrim as its
                    // neighbours. Fixed-size icon buttons, so the row stays
                    // back + four at every text scale (Gotcha 21 has nothing
                    // to grow here).
                    RecipeOwnerMenu(
                      recipe: recipe,
                      style: _ScrimButton.styleOf(context),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// An icon button legible on whatever the cover is — a photo or a colour
/// block, either of which may be light or dark. It carries its own scrim,
/// because a themed icon colour over an unknown background is the B055
/// mistake (a colour chosen against one background, painted on another).
class _ScrimButton extends StatelessWidget {
  const _ScrimButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  /// The scrim, as a style — shared with the owner's "More" menu trigger,
  /// which is a `PopupMenuButton` rather than this widget (UX-037).
  static ButtonStyle styleOf(BuildContext context) {
    final palette = context.palette;
    return IconButton.styleFrom(
      backgroundColor: palette.imageControl,
      foregroundColor: palette.onImage,
    );
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon),
      style: styleOf(context),
      onPressed: onPressed,
    );
  }
}

/// The identity sheet: kicker, title, chef, rating, description, credit,
/// tags, facts, nutrition summary, like/save — reference 5's sheet (36c).
///
/// White with 28px top corners, laid over the cover by [_CoverAndSheet]. The
/// page below it is the same surface, so the sheet reads as the page rising
/// over the photo rather than as a card sitting on it.
class _IdentityBand extends StatelessWidget {
  const _IdentityBand({required this.recipe});

  final Recipe recipe;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final nutrition = recipe.nutrition;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadii.sheet),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Lineage above the title (frame F), full width — the expanded page
          // draws the same mark beside the back button instead.
          if (recipe.isFork) ...[
            ForkedLabel(recipe: recipe, expand: true),
            const SizedBox(height: AppSpacing.sm),
          ],
          DetailKicker(recipe: recipe),
          const SizedBox(height: AppSpacing.xs),
          Text(recipe.title, style: textTheme.headlineSmall),
          const SizedBox(height: AppSpacing.smPlus),
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
                size: AppIconSize.button,
              ),
            ],
          ),
          if (recipe.description.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            // Reference 5's grey subtitle under the title.
            Text(
              recipe.description,
              style: textTheme.bodyLarge?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          // Before the cook's own story, because "who published this" is the
          // question a reader of an imported recipe has first — and because the
          // credit is what makes showing the rest of the page defensible.
          if (recipe.isImported) ...[
            const SizedBox(height: AppSpacing.md),
            SourceCredit(recipe: recipe),
          ],
          if ((recipe.attribution ?? '').isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            AttributionBlock(text: recipe.attribution!, boxed: true),
          ],
          // `Private` rides in the tag row on this layout: it used to sit on
          // the cover's bottom-left corner, which is where the colour block
          // sets its category label — and the sheet now covers that edge.
          if (DetailTags.hasAny(recipe, showPrivate: true)) ...[
            const SizedBox(height: AppSpacing.md),
            DetailTags(recipe: recipe, showPrivate: true),
          ],
          const SizedBox(height: AppSpacing.md),
          FactsStrip(recipe: recipe, quad: true),
          // Additive to the FDA label in the Nutrition tab, which stays the
          // authoritative panel (Preserve): the headline numbers, up front.
          if (NutritionSummary.hasAny(nutrition)) ...[
            const SizedBox(height: AppSpacing.md),
            NutritionSummary(nutrition: nutrition!),
          ],
          const SizedBox(height: AppSpacing.md),
          LikeSaveButtons(recipe: recipe),
        ],
      ),
    );
  }
}

// The pinned jump bar.
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
    this.forking = false,
  });

  final double textScale;
  final VoidCallback onIngredients;
  final VoidCallback onMethod;

  /// Null for the owner — you cannot fork your own recipe.
  final VoidCallback? onFork;

  /// A fork is in flight: the chip stays, disabled, rather than vanishing
  /// under the finger that just tapped it (B129).
  final bool forking;

  /// The bar's height at 1.0×, and the text scale past which it stops growing.
  static const double _kBarHeight = 56;
  static const double _kMaxGrowth = 1.8;

  double get _extent => _kBarHeight * textScale.clamp(1.0, _kMaxGrowth);

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
                avatar: const Icon(Icons.call_split, size: AppIconSize.sm),
                label: const Text('Fork'),
                onPressed: forking ? null : onFork,
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
      old.forking != forking ||
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
        AppSpacing.smPlus,
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
