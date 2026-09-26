import 'package:cached_network_image/cached_network_image.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';

import 'package:design_system/src/layout/adaptive.dart';
import 'package:design_system/src/theme/app_theme.dart';
import 'package:design_system/src/widgets/category_cover.dart';
import 'package:design_system/src/widgets/chef_badge.dart';
import 'package:design_system/src/widgets/difficulty_badge.dart';
import 'package:design_system/src/widgets/interactive_tile.dart';
import 'package:design_system/src/widgets/star_rating.dart';

/// Height of every [RecipeCard], in logical pixels.
///
/// The card is a **fixed-height** tile rather than a fixed-aspect one: the grid
/// passes this as `mainAxisExtent`, so a wide window no longer leaves dead
/// space under each card. The banner is a fixed band of its own
/// (`kRecipeCardBannerHeight`) whatever the title's length, so at default text
/// scale nothing inside the card moves between one recipe and the next; the
/// cover is the band that gives up height when text scaling grows the other
/// two.
const double kRecipeCardHeight = 352;

/// Narrowest width the card is designed for, and the width its layout tests
/// use as the worst realistic envelope.
///
/// A grid packs as many columns as can each hold this much (see
/// `FlowGridMetrics`). Nothing enforces it below one column — a phone narrower
/// than this gets a single card that degrades rather than overflows.
///
/// **288, not 264**: this is the floor at which the whole time / rating /
/// difficulty row still fits with its longest labels, and *nothing in that row
/// may truncate*. At 264 a wide grid packed one more column by buying it out of
/// the footer — `4.9 (8)` ellipsized to fit. A column fewer is the cheaper
/// trade.
///
/// Setting the floor is necessary and was not sufficient: B080 truncated the
/// rating here anyway, because the row's flex factors gave the space to the
/// wrong children. The width buys the room; the metadata row's degradation
/// order decides who gets it.
const double kRecipeCardMinWidth = 288;

/// Height of the title banner, before text scale.
///
/// Fixed, and two lines' worth: the title is vertically centred inside it, so a
/// one-line name and a two-line name give the **same** banner and every card in
/// a row lines its cover up with its neighbours'. A longer name clamps to two
/// lines with an ellipsis rather than growing the band.
///
/// Multiplied by `context.textScale` at build time (up to
/// [kRecipeCardBannerMaxScale]) — a fixed pixel height would clip two lines of
/// 2.0× text, and the point of the constant is that the two cases stay equal at
/// every scale the card is contracted to survive.
const double kRecipeCardBannerHeight = 65;

/// Ceiling on the text-scale factor the banner band is multiplied by.
///
/// The card's total height is fixed, so a band that keeps growing eventually
/// leaves the cover nothing and the column overflows — 65 × 3.0 is 195px of
/// banner against a 352px card whose footer alone wants ~190 at that scale
/// (a 48px overflow, measured). Past this ceiling the band stops growing and
/// the title's own two lines drive it, which is the pre-B047 behaviour and
/// still taller than the text needs: 130px holds two lines of 3.0× type with
/// room to spare, so the one-line/two-line match survives the clamp.
const double kRecipeCardBannerMaxScale = 2.0;

/// Widest the card is ever laid out at.
///
/// The card does **not** clamp itself: a grid cell hands it tight constraints,
/// which win over any `ConstrainedBox` inside. The grid owns the cap — it turns
/// spare width into another column, and centres the row once the tiles are at
/// their maximum.
const double kRecipeCardMaxWidth = 340;

/// Most columns a recipe grid ever lays out, however wide the window (B049).
///
/// **6, because that is what a 1920px window already packs** — the widest
/// common desktop viewport, (1920 − 32 + 16) ÷ (288 + 16) = 6.26. So the cap
/// changes nothing on any window up to full HD, and past it the extra width
/// becomes a centred gutter instead of a seventh … twelfth column: a 3840px
/// window used to lay out twelve cards per row, a wall no reader scans as a
/// row. The widest a grid row can get is therefore
/// `6 × kRecipeCardMaxWidth + 5 × 16` = 2120px, which is still wider than any
/// other page in the app (recipe detail measures 1140).
///
/// A column **count** rather than a pixel width on purpose: the cards already
/// cap their own width, so a count is the one number that says how much a row
/// holds, and it cannot leave a row one tile short of full the way a width cap
/// that is not a multiple of a tile can.
const int kRecipeGridMaxColumns = 6;

/// Above this text scale the card drops its description (B049).
///
/// The card is a fixed-height tile, and its contract scale is 2.0×. Past that
/// the banner (two lines of `titleMedium`) and the footer (two lines of
/// description over the metadata row) together outgrow [kRecipeCardHeight] and
/// the cover — the only flexible band — has nothing left to give, which was a
/// 13px `RenderFlex` overflow at 3.0× (iOS accessibility sizes reach it).
///
/// The fix degrades rather than grows. Growing the tile would make
/// `kRecipeCardHeight` a function of text scale and `mainAxisExtent` with it,
/// in every grid and every shelf, to preserve the one line on the card a reader
/// can do without: the description is a teaser for the page one tap away, the
/// title and the time / rating / difficulty row are what a card is *for*, and
/// the corpus's imported recipes carry no description at all — so a card
/// without one is already an ordinary state, not a broken one. The divider
/// above the metadata row goes with it, because it separated the two.
const double kRecipeCardDescriptionMaxScale = 2.0;

// Card geometry that is not on the spacing scale (UX-054) — named here so the
// numbers the envelope tests were measured against stay put.

/// The title band's (and the footer's) horizontal inset. Small, because the
/// card has no chrome of its own since 36c: the text lines up with the photo's
/// edge, nudged in by a hair so a round-shouldered glyph does not look outdented.
const double _kTextHPad = AppSpacing.xxs;

/// Gap between the footer's divider and the metadata row under it.
const double _kFooterRuleGap = 10;

/// The metadata row's clock glyph — one px under [AppIconSize.sm] so it sits
/// inside a `labelMedium` line box.
const double _kMetaIconSize = 15;

/// Placeholder bar sizes: each mimics the text line it stands in for.
const double _kPlaceholderTitleBar = 13;
const double _kPlaceholderLineBar = 10;
const double _kPlaceholderMetaBar = 12;
const double _kPlaceholderShortLine = 140;
const double _kPlaceholderTimeBar = 58;
const double _kPlaceholderBadgeBar = 72;

/// Placeholder gap above its metadata row — stands in for the divider band.
const double _kPlaceholderMetaGap = 14;

/// The placeholder's cover glyph.
const double _kPlaceholderIconSize = 34;

/// The primary recipe tile used on Discover and My Recipes (v3 layout, 36c).
///
/// Top to bottom: the **cover** — a rounded photo, or a [CategoryCover] colour
/// block when the recipe has none — then the **title band** under it, then a
/// footer with the truncated description and the time / rating / difficulty
/// row. No border and no fill: the photo is the card (references 1, 2, 5).
///
/// Set [showVisibility] on surfaces that mix private and public recipes (My
/// Recipes) to add a lock/globe chip to the cover's top-right. When
/// [Recipe.owner] is embedded and [showChef] is true, the owning chef is drawn
/// on the cover, bottom-right. [rank] hangs a ribbon from the cover's
/// top-left for a ranked shelf (reference 2).
///
/// The title band is fixed and the footer is intrinsic; the cover is the only
/// flexible child, so text-scale growth eats cover height instead of
/// overflowing (B001/B002/B016 all came from a card row that could not shrink).
/// Past the 2.0× contract the cover alone cannot absorb it, so the description
/// yields too ([kRecipeCardDescriptionMaxScale], B049) and the tile stays
/// [kRecipeCardHeight] tall at 3.0×.
class RecipeCard extends StatelessWidget {
  const RecipeCard({
    super.key,
    required this.recipe,
    this.onTap,
    this.onChefTap,
    this.showVisibility = false,
    this.showChef = true,
    this.rank,
  });

  final Recipe recipe;
  final VoidCallback? onTap;

  /// Tapping the chef overlay on the cover, when one is drawn.
  ///
  /// `design_system` owns no routing, so the destination (`/chef/:id`) is the
  /// app layer's business — the grids supply it. Null leaves the overlay inert
  /// and the whole cover belongs to [onTap], which is what a surface that has
  /// no chef page to send a reader to should do.
  ///
  /// When both are set the badge wins **its own hit area only**: it is deeper
  /// in the hit-test path than the card's `InkWell`, so its recognizer enters
  /// the gesture arena first and takes the sweep. Everywhere else on the card —
  /// the rest of the cover included — still opens the recipe. The focus ring
  /// and hover wash [InteractiveTile] paints above the cover are
  /// [IgnorePointer]s, so they never sit between the badge and the pointer.
  final VoidCallback? onChefTap;

  final bool showVisibility;

  /// Set false on surfaces where every card has the same owner (My Recipes),
  /// so the badge is not repeated on every tile.
  final bool showChef;

  /// 1-based position on a ranked shelf; draws the rank ribbon. Null (the
  /// default) on every unranked surface.
  final int? rank;

  /// `45 min`, `1h 10m`, `2h`, `—` — core's formatter in its **compact** form,
  /// the one documented exception to the product's single duration format
  /// (UX-043, DESIGN.md §2.1). Phase 37 tried the long form here: the label is
  /// capped at its flex share of the metadata row (~57px at the 288px floor),
  /// and `2 h 20 min` (57.1px) already clipped at 1.0× text scale — at the
  /// width Gotcha 13 promises fits uncut. The compact form is a width budget,
  /// not a style.
  String get _timeLabel => formatMinutes(recipe.totalMinutes, compact: true);

  /// Two lines of the description's style at the ambient text scale.
  static double _descriptionHeight(BuildContext context, TextTheme textTheme) {
    final style = textTheme.bodySmall!;
    final line = (style.fontSize ?? 12) * (style.height ?? 1.0);
    return MediaQuery.textScalerOf(context).scale(line) * 2;
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    // B049: past the contract scale the description yields its two lines so
    // the fixed-height tile still fits — see the constant. Keyed on the scale
    // alone, never on whether this recipe *has* a description: an empty one
    // still holds its line below the limit, so a described and an undescribed
    // card side by side keep the same cover height (B047's rule).
    final showDescription = context.textScale <= kRecipeCardDescriptionMaxScale;

    return SizedBox(
      // Tight height so the cover's Expanded always has a bound, including in
      // tests and any caller that lays the card out with unbounded height.
      height: kRecipeCardHeight,
      // No `Card`: the tile has no chrome since 36c. [InteractiveTile] owns the
      // tap target and paints hover, press and keyboard focus *over* the cover
      // rather than under it (UX-013).
      child: InteractiveTile(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.card),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadii.card),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // `displayCoverImageUrl` honours the publisher's image
                    // policy (Phase 35c); no URL means the colour block.
                    _CoverImage(
                      url: recipe.displayCoverImageUrl,
                      category: recipe.category,
                      ranked: rank != null,
                    ),
                    if (rank != null)
                      Positioned(
                        top: 0,
                        left: AppSpacing.smPlus,
                        child: _RankRibbon(rank: rank!),
                      ),
                    if (showVisibility)
                      Positioned(
                        top: AppSpacing.sm,
                        right: AppSpacing.sm,
                        child: _VisibilityBadge(
                          visibility: recipe.visibility,
                          scheme: scheme,
                        ),
                      ),
                    if (showChef && recipe.owner != null)
                      Positioned(
                        left: AppSpacing.sm,
                        right: AppSpacing.sm,
                        bottom: AppSpacing.sm,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: _ChefOverlay(
                            owner: recipe.owner!,
                            onTap: onChefTap,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            _TitleBand(title: recipe.title),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                _kTextHPad,
                0,
                _kTextHPad,
                AppSpacing.sm,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showDescription)
                    // Always two lines tall, whatever the text (36c review):
                    // the title band now sits *under* the cover, so a
                    // one-line description beside a two-line one would
                    // shift the neighbour's cover and title by a line.
                    // `strutStyle` + two lines' height pins it; empty
                    // strings reserve the same space (B047's rule).
                    SizedBox(
                      height: _descriptionHeight(context, textTheme),
                      child: Text(
                        recipe.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  Container(
                    margin:
                        showDescription
                            ? const EdgeInsets.only(top: AppSpacing.xsPlus)
                            : EdgeInsets.zero,
                    padding:
                        showDescription
                            ? const EdgeInsets.only(top: _kFooterRuleGap)
                            : EdgeInsets.zero,
                    decoration:
                        showDescription
                            ? BoxDecoration(
                              border: Border(
                                top: BorderSide(color: scheme.outlineVariant),
                              ),
                            )
                            : null,
                    // The badge takes its intrinsic width, capped at half the
                    // row; the time + rating group takes everything left over
                    // and ellipsizes inside it. Two flex children instead
                    // (what this was) split the row 50/50 whatever the
                    // content, which truncated "4.9 (8)" to "4…" at
                    // one-column widths; a bare intrinsic badge overflows by
                    // 1px at the narrowest column / 2.0x. The cap is what
                    // degrades in the right order (B016) — and
                    // `kRecipeCardMinWidth` is set so that at default scale
                    // this row never has to degrade at all (B048).
                    child: LayoutBuilder(
                      builder:
                          (context, constraints) => Row(
                            children: [
                              Expanded(
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.schedule,
                                      size: _kMetaIconSize,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                    const SizedBox(width: AppSpacing.xs),
                                    // Flex **1 against the rating's 2**, not
                                    // the even split this was (B080). Equal
                                    // factors hand each child half the free
                                    // space whatever it needs, so beside a
                                    // `Medium` badge at 288px the short time
                                    // label sat on ~30px it had no use for
                                    // while `5.0 (1)` was cut to `5…` — the
                                    // same B026/B038 mechanism the badge
                                    // below was fixed for, one level in.
                                    // Both stay flex on purpose: a non-flex
                                    // child of a `Row` is laid out with an
                                    // unbounded main axis and overflows
                                    // rather than ellipsizing (B039), and a
                                    // fixed-fraction `ConstrainedBox` cap
                                    // instead starves the pill until its own
                                    // `Row` overflows — measured, not
                                    // assumed: `maxWidth / 3` here failed
                                    // four cases of the envelope suite below,
                                    // at 264 × 1.0 and at 2.0× on every
                                    // width.
                                    Flexible(
                                      child: Text(
                                        _timeLabel,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: textTheme.labelMedium,
                                      ),
                                    ),
                                    if (recipe.hasRatings) ...[
                                      const SizedBox(width: AppSpacing.sm),
                                      Flexible(
                                        flex: 2,
                                        child: RatingPill(
                                          rating: recipe.ratingAvg,
                                          count: recipe.ratingCount,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: constraints.maxWidth / 2,
                                ),
                                child: DifficultyBadge(
                                  difficulty: recipe.difficulty,
                                ),
                              ),
                            ],
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A [RecipeCard]-shaped hole, for a shelf whose rows have not arrived.
///
/// Same geometry and the same bands, in neutral fills. A rail that collapses
/// while it loads drags every shelf below it up the page and drops them back
/// when the rows land, which reads as a broken page rather than a loading one —
/// the argument [SpotlightCardPlaceholder] was written for, and the reason this
/// is a placeholder rather than a spinner.
class RecipeCardPlaceholder extends StatelessWidget {
  const RecipeCardPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    Widget bar(double width, double height) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
    );

    return SizedBox(
      height: kRecipeCardHeight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppRadii.card),
              ),
              child: Icon(
                Icons.restaurant_menu,
                size: _kPlaceholderIconSize,
                color: scheme.onSurfaceVariant.withValues(alpha: AppAlpha.rule),
              ),
            ),
          ),
          SizedBox(
            height:
                kRecipeCardBannerHeight *
                context.textScale.clamp(1.0, kRecipeCardBannerMaxScale),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: _kTextHPad),
              child: Align(
                alignment: Alignment.centerLeft,
                child: bar(double.infinity, _kPlaceholderTitleBar),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              _kTextHPad,
              0,
              _kTextHPad,
              AppSpacing.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                bar(double.infinity, _kPlaceholderLineBar),
                const SizedBox(height: AppSpacing.xsPlus),
                bar(_kPlaceholderShortLine, _kPlaceholderLineBar),
                const SizedBox(height: _kPlaceholderMetaGap),
                Row(
                  children: [
                    bar(_kPlaceholderTimeBar, _kPlaceholderMetaBar),
                    const Spacer(),
                    bar(_kPlaceholderBadgeBar, _kPlaceholderMetaBar),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The recipe name, in a fixed band under the cover.
///
/// Two lines maximum, then an ellipsis — a longer name eats cover height, it
/// never grows the card. The band is a **fixed** `kRecipeCardBannerHeight ×
/// textScale` (capped at [kRecipeCardBannerMaxScale]) with the title centred
/// in it, so one-line and two-line names produce identical bands and the
/// footers of neighbouring cards start at the same y (B047). It is a
/// *minimum*, not a tight height: anything the text needs beyond it still grows
/// the band (and costs the cover) instead of overflowing.
class _TitleBand extends StatelessWidget {
  const _TitleBand({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      key: const ValueKey('recipe-card-title-band'),
      constraints: BoxConstraints(
        minHeight:
            kRecipeCardBannerHeight *
            context.textScale.clamp(1.0, kRecipeCardBannerMaxScale),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: _kTextHPad,
        vertical: AppSpacing.sm,
      ),
      alignment: Alignment.centerLeft,
      child: Text(
        title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.titleMedium?.copyWith(
          color: theme.colorScheme.onSurface,
        ),
      ),
    );
  }
}

/// The rank flag hanging from the cover's top edge on a ranked shelf
/// (reference 2): `1st`, `2nd`, `3rd`, `4th` … in the ribbon's own ink.
class _RankRibbon extends StatelessWidget {
  const _RankRibbon({required this.rank});

  final int rank;

  static String _ordinal(int n) {
    final teen = n % 100 >= 11 && n % 100 <= 13;
    final suffix =
        teen
            ? 'th'
            : switch (n % 10) {
              1 => 'st',
              2 => 'nd',
              3 => 'rd',
              _ => 'th',
            };
    return '$n$suffix';
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Semantics(
      label: 'Ranked ${_ordinal(rank)}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.sm,
          AppSpacing.sm,
          AppSpacing.sm,
          AppSpacing.xsPlus,
        ),
        decoration: BoxDecoration(
          color: palette.rankRibbon,
          borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(AppRadii.sm),
          ),
        ),
        child: Text(
          _ordinal(rank),
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.tabular.copyWith(color: palette.onRankRibbon),
        ),
      ),
    );
  }
}

/// The owning chef, drawn over the bottom-right of the cover image on a scrim.
///
/// `Positioned` with both `left` and `right` set gives this a bounded width, so
/// the badge's name and tier chip ellipsize instead of overflowing at
/// `kRecipeCardMinWidth` or at 2.0x text scale; the `Align` pulls it to the
/// right edge once it is narrower than that bound.
///
/// The scrim is a [Material] rather than the `Container` + `BoxDecoration` it
/// was, and the swap is not cosmetic: [ChefBadge]'s tap uses an `InkWell`, and
/// the nearest `Material` above this is the card's own transparent one — which
/// paints its ink *under* the cover photo, so the ripple would land where
/// nobody can see it. A local one puts the splash on the scrim, clipped to the pill.
/// Geometry is unchanged: a [StadiumBorder] is what `AppRadii.pill` already
/// rendered on a box this short, and the padding moved into a [Padding] of the
/// same insets.
class _ChefOverlay extends StatelessWidget {
  const _ChefOverlay({required this.owner, this.onTap});

  final Profile owner;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      // Scrim: cover photos are arbitrary, so the badge carries its own
      // contrast rather than relying on the image being dark.
      color: context.palette.scrim,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: ChefBadge.fromProfile(
          owner,
          compact: true,
          onSurfaceImage: true,
          onTap: onTap,
        ),
      ),
    );
  }
}

/// Icon-only public/private chip, on the cover's top-right corner.
///
/// Icon-only on purpose: a "Private" label on a 288px cover competes with the
/// chef badge and the rank ribbon, and is the first thing to overflow at large
/// text scale.
/// The label survives as the tooltip, which is also what screen readers read.
class _VisibilityBadge extends StatelessWidget {
  const _VisibilityBadge({required this.visibility, required this.scheme});

  final RecipeVisibility visibility;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final isPublic = visibility.isPublic;
    return Tooltip(
      message: isPublic ? 'Public' : 'Private',
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.xs),
        decoration: BoxDecoration(
          color: scheme.surface.withValues(alpha: AppAlpha.frosted),
          borderRadius: BorderRadius.circular(AppRadii.pill),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Icon(
          isPublic ? Icons.public : Icons.lock_outline,
          size: AppIconSize.xs,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _CoverImage extends StatelessWidget {
  const _CoverImage({required this.url, this.category, this.ranked = false});

  final String? url;
  final String? category;

  /// A ranked card's ribbon hangs from the top-left, so the colour block's
  /// label moves to the top-right.
  final bool ranked;

  Widget _block() => CategoryCover(
    category: category,
    labelAlignment: ranked ? Alignment.topRight : Alignment.topLeft,
  );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (url == null || url!.isEmpty) {
      return _block();
    }
    return CachedNetworkImage(
      imageUrl: url!,
      fit: BoxFit.cover,
      placeholder: (_, __) => Container(color: scheme.surfaceContainerHighest),
      // A photo that fails to load falls back to the same colour block a
      // recipe without one gets, not a broken-image glyph (UX-029's hotlink
      // failure read as a fault).
      errorWidget: (_, __, ___) => _block(),
    );
  }
}
