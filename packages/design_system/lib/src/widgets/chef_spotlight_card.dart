import 'package:cached_network_image/cached_network_image.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';

import 'package:design_system/src/layout/adaptive.dart';
import 'package:design_system/src/theme/app_theme.dart';
import 'package:design_system/src/widgets/chef_avatar.dart';
import 'package:design_system/src/widgets/interactive_tile.dart';
import 'package:design_system/src/widgets/tier_chip.dart';

/// Width of every [ChefSpotlightCard]. The rails pack cards at this width and
/// scroll horizontally rather than reflowing, so unlike [RecipeCard] there is no
/// min/max pair — one width, one column count per rail page.
const double kSpotlightCardWidth = 280;

/// Height of the card at 1.0× text scale.
///
/// The card is a **fixed-size** tile: a horizontal rail hands its children a
/// tight height, so every band except the portrait is intrinsic and comes out of
/// this budget. See [spotlightCardHeight] for what happens when text grows.
const double kSpotlightCardHeight = 356;

/// How much taller the card gets at 2.0× text scale.
///
/// Roughly the height of everything on the card that is text — header, rarity
/// band, driver row, stat grid and ladder line come to ~160px at 1.0×, and text
/// scaling doubles them. The portrait does not scale, so growing the tile by
/// exactly the text's growth keeps the portrait the same size instead of
/// squeezing it to nothing.
const double _kSpotlightTextGrowth = 168;

// --- Foil-card geometry ------------------------------------------------------
// The spotlight card is a fixed-size "foil trading card" (DESIGN.md Preserve
// list). These are its own measurements, not steps on the spacing scale — a
// re-skin that changes one of them is redrawing the card.

/// Outer corner of the foil frame.
const double _kFrameRadius = 18;

/// The foil band between the frame's edge and the inset surface panel.
const double _kFramePadding = 7;

/// The panel's clip, concentric with the frame: outer radius minus the band.
const double _kPanelClipRadius = _kFrameRadius - _kFramePadding; // 11

/// The panel's highlight border, drawn outside the clip.
const double _kPanelBorderWidth = 1;

/// The panel's own corner: the clip plus its border.
const double _kPanelRadius = _kPanelClipRadius + _kPanelBorderWidth; // 12

/// The frame's lift off the rail.
const double _kFrameShadowBlur = 26;
const Offset _kFrameShadowOffset = Offset(0, 10);

/// How far the gradient's top-left lerps toward white, and its lower edge
/// toward [AppPalette.foilShade].
const double _kFoilLift = 0.18;
const double _kFoilShadeDepth = 0.38;

/// Foil stripes: stroke width and the distance between stripe starts.
const double _kFoilStripeWidth = 2;
const double _kFoilStripePeriod = 9;

/// Side inset shared by every band inside the panel.
const double _kInset = 10;

/// The looser vertical inset: header top, rarity band gap, footer bottom.
const double _kInsetLoose = 9;

/// The tighter vertical inset: header bottom, caption bottom, footer rule.
const double _kInsetTight = 7;

/// The portrait window's corner and tinted border; the photo inside is
/// clipped concentric with it.
const double _kPortraitRadius = 9;
const double _kPortraitBorder = 3;
const double _kPortraitClipRadius = _kPortraitRadius - _kPortraitBorder; // 6

/// The RANK pill on the portrait caption.
const EdgeInsets _kRankPillPadding = EdgeInsets.symmetric(
  horizontal: 7,
  vertical: AppSpacing.xxs,
);

/// The driver row's icon tile.
const double _kDriverTileSize = 28;
const double _kDriverTileRadius = 7;

/// The footer's tier-ladder bar and the gap under it.
const double _kLadderBarHeight = 4;
const double _kLadderLabelGap = 3;

/// The card's height at the ambient text scale.
///
/// A fixed 356 would work at 1.0× and overflow at 2.0×, and the usual fix —
/// letting the flexible band absorb it — cannot work here: the intrinsic bands
/// alone exceed 356 well before 2.0×. A rail scrolls inside a page that scrolls,
/// so a taller card at a larger text scale costs nothing and hides nothing,
/// which dropping bands would.
double spotlightCardHeight(BuildContext context) =>
    kSpotlightCardHeight +
    (context.textScale - 1).clamp(0.0, 1.5) * _kSpotlightTextGrowth;

/// A chef as a collectible card — the "spotlight" variant from draft `1e`.
///
/// Everything here comes from the leaderboard payload the rail already holds:
/// the tier drives the frame foil, the rarity band, the accent and the glyph;
/// the score sits where a trading card puts its HP; the driver row names the
/// input doing the most work with the arithmetic behind it; and the footer is
/// the same tier-ladder progress the expanded chef card draws. No per-card
/// fetch, so a rail of ten cards is one round trip.
///
/// **Fixed-size tile — the [RecipeCard] rules apply** (B001/B002/B016). The
/// portrait is the only flexible band; a longer name eats portrait height rather
/// than growing the card, and the tile itself grows only with text scale, via
/// [spotlightCardHeight].
class ChefSpotlightCard extends StatelessWidget {
  const ChefSpotlightCard({
    super.key,
    required this.standing,
    required this.onTap,
    this.totalChefs,
    this.window,
    this.windowLabel,
  });

  final ChefStanding standing;

  /// What the chef earned inside a time window (Phase 33) — the Trending and
  /// month rails. When set, the driver row reads the window instead of the
  /// lifetime totals: `+312 · last 7 days`, then the input doing most of that
  /// work. Same two lines as the all-time row, so the fixed-size tile's budget
  /// is unchanged (Gotcha 13). Everything else on the card stays all-time.
  final ChefWindowStats? window;

  /// The span [window] covers — `last 7 days`. Ignored without a [window].
  final String? windowLabel;

  /// Opens the expanded chef card. Required for the same reason the leaderboard
  /// row's is: a card with no destination is what this design set out to fix.
  final VoidCallback onTap;

  /// Denominator of the serial — `004 / 148`. The serial drops to the rank
  /// alone while the count is still loading, rather than blocking the card.
  final int? totalChefs;

  /// Foil intensity per tier: Home Cook is a flat frame, Master Chef the full
  /// sheen. Straight from the `1E` note on the draft.
  static double foilFor(ChefTier tier) => switch (tier) {
    ChefTier.homeCook => 0.06,
    ChefTier.lineCook => 0.10,
    ChefTier.sousChef => 0.14,
    ChefTier.headChef => 0.20,
    ChefTier.masterChef => 0.28,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tier = TierChip.colorFor(standing.chefTier, theme.brightness);

    return SizedBox(
      width: kSpotlightCardWidth,
      height: spotlightCardHeight(context),
      child: _FoilFrame(
        color: tier,
        foil: foilFor(standing.chefTier),
        // The portrait is opaque, so an `InkWell`'s own focus highlight showed
        // only on the bands around it (UX-013). [InteractiveTile] paints the
        // ring and the hover wash over the whole panel instead — at the panel's
        // clip radius, because the frame's clip is what it is drawn inside.
        child: InteractiveTile(
          onTap: onTap,
          borderRadius: BorderRadius.circular(_kPanelClipRadius),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(standing: standing, color: tier),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: _kInset),
                  child: _Portrait(
                    standing: standing,
                    color: tier,
                    totalChefs: totalChefs,
                  ),
                ),
              ),
              _RarityBand(standing: standing, color: tier),
              _DriverRow(
                standing: standing,
                color: tier,
                window: window,
                windowLabel: windowLabel,
              ),
              _Footer(standing: standing, color: tier),
            ],
          ),
        ),
      ),
    );
  }
}

/// The card's outer frame: a tier gradient under diagonal foil stripes, wrapped
/// around an inset surface panel. Shared with [SpotlightCardPlaceholder] so a
/// loading rail has the same geometry as a loaded one.
class _FoilFrame extends StatelessWidget {
  const _FoilFrame({
    required this.color,
    required this.foil,
    required this.child,
  });

  final Color color;
  final double foil;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = context.palette;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_kFrameRadius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(color, palette.onImage, _kFoilLift)!,
            color,
            Color.lerp(color, palette.foilShade, _kFoilShadeDepth)!,
            color,
          ],
          stops: const [0, 0.38, 0.72, 1],
        ),
        boxShadow: [
          BoxShadow(
            color: palette.floatingShadow,
            blurRadius: _kFrameShadowBlur,
            offset: _kFrameShadowOffset,
          ),
        ],
      ),
      child: CustomPaint(
        painter: _FoilPainter(color: palette.onImage, opacity: foil),
        child: Padding(
          padding: const EdgeInsets.all(_kFramePadding),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(_kPanelRadius),
              border: Border.all(
                // The draft's `inset 0 0 0 1px rgba(255,255,255,0.5)` reads as a
                // highlight on a light panel and as glare on a dark one.
                color: palette.foilHighlight,
                width: _kPanelBorderWidth,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(_kPanelClipRadius),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Diagonal foil stripes over the frame gradient.
///
/// A painter rather than a repeating [LinearGradient]: Flutter's repeated tile
/// mode cannot express "2px on, 7px off at an angle" without a transform whose
/// period depends on the box size, and this is two lines of arithmetic.
class _FoilPainter extends CustomPainter {
  const _FoilPainter({required this.color, required this.opacity});

  /// The stripe colour at full strength; [opacity] is the foil intensity.
  final Color color;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0) return;
    final paint =
        Paint()
          ..color = color.withValues(alpha: opacity)
          ..strokeWidth = _kFoilStripeWidth
          ..style = PaintingStyle.stroke;

    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndRadius(
        Offset.zero & size,
        const Radius.circular(_kFrameRadius),
      ),
    );
    // Lines run down-right at 45°, so each one starts `height` to the left of
    // where it should finish. Starting at -height covers the top-right corner.
    for (
      var x = -size.height;
      x < size.width + size.height;
      x += _kFoilStripePeriod
    ) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x + size.height, size.height),
        paint,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FoilPainter oldDelegate) =>
      oldDelegate.opacity != opacity || oldDelegate.color != color;
}

/// Tier glyph, name, and the score where a trading card puts its HP.
class _Header extends StatelessWidget {
  const _Header({required this.standing, required this.color});

  final ChefStanding standing;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        _kInset,
        _kInsetLoose,
        _kInset,
        _kInsetTight,
      ),
      // The score is capped at half the row and takes its intrinsic width
      // inside that; the name takes everything left over. Two flex children
      // instead — `Expanded` name plus `Flexible` score — split the row 50/50
      // whatever the content, so "Secret Sauce Kitchen" truncated at 104px
      // beside a 75px score and 29px of dead space. Same shape and same fix as
      // the recipe card's difficulty badge (B016).
      child: LayoutBuilder(
        builder:
            (context, constraints) => Row(
              children: [
                Icon(
                  TierChip.iconFor(standing.chefTier),
                  size: AppIconSize.md,
                  color: color,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    standing.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    // The draft sets this in the display face, but the serif
                    // roles start at titleLarge (22px) — more than this fixed
                    // tile's header band can give. Sans titleSmall keeps 14/20.
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                ConstrainedBox(
                  // A third, not a half: the name is the identity and the score can
                  // shrink, so the cap is set where the score stops crowding it.
                  constraints: BoxConstraints(
                    maxWidth: constraints.maxWidth / 3,
                  ),
                  // A six-figure score at 2.0× fits no sane column; shrink it
                  // rather than truncate it, the same call the board row makes.
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          standing.scoreLabel,
                          maxLines: 1,
                          style: context.appText.stat.copyWith(
                            color: color,
                            height: 1,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xxs),
                        Text(
                          'PTS',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
      ),
    );
  }
}

/// The portrait window: the chef's avatar, their serial, and their rank.
///
/// The draft draws a dedicated 4:3 chef portrait. There is no such asset and no
/// column to hold one, so the window falls back to the profile picture, and to
/// the same monogram [ChefAvatar] draws everywhere else when there is not even
/// that.
class _Portrait extends StatelessWidget {
  const _Portrait({
    required this.standing,
    required this.color,
    required this.totalChefs,
  });

  final ChefStanding standing;
  final Color color;
  final int? totalChefs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final palette = context.palette;
    final url = standing.avatarUrl;

    // "004 / 148", or "004" until the count lands.
    final serial =
        totalChefs == null
            ? '${standing.chefRank}'.padLeft(3, '0')
            : '${'${standing.chefRank}'.padLeft(3, '0')} / '
                '${groupedCount(totalChefs!)}';

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_kPortraitRadius),
        border: Border.all(
          color: Color.alphaBlend(
            color.withValues(alpha: AppAlpha.glow),
            scheme.surfaceContainerHigh,
          ),
          width: _kPortraitBorder,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_kPortraitClipRadius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (url != null && url.isNotEmpty)
              CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                placeholder:
                    (_, __) =>
                        ColoredBox(color: scheme.surfaceContainerHighest),
                errorWidget:
                    (_, __, ___) =>
                        _MonogramPortrait(standing: standing, color: color),
              )
            else
              // TODO(portrait): there is no chef portrait asset and no column
              // for one. When a portrait lands, it replaces this branch — the
              // window is already the right shape for it.
              _MonogramPortrait(standing: standing, color: color),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      palette.coverScrim,
                      palette.coverScrim.withValues(alpha: 0),
                    ],
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    _kInsetLoose,
                    _kInset,
                    _kInsetLoose,
                    _kInsetTight,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Text(
                          serial,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          // The draft's mono serial: tracked, tabular digits.
                          style: context.appText.overline.tabular.copyWith(
                            color: palette.onImage,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      // A bare pill here is a non-flex child of a Row, so it is
                      // laid out unbounded and `RANK 128` at 3.0× ran 13px past
                      // the portrait's edge. Bounded plus scale-down instead —
                      // the rank must stay readable, so it shrinks, not clips.
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: _RankPill(
                            rank: standing.chefRank,
                            tier: standing.chefTier,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonogramPortrait extends StatelessWidget {
  const _MonogramPortrait({required this.standing, required this.color});

  final ChefStanding standing;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ColoredBox(
      color: Color.alphaBlend(
        color.withValues(alpha: AppAlpha.wash),
        scheme.surfaceContainerHighest,
      ),
      // The window is short at large text scales; scale the monogram down with
      // it rather than letting a fixed radius overflow.
      child: LayoutBuilder(
        builder:
            (context, constraints) => Center(
              child: ChefAvatar(
                name: standing.displayName,
                radius: (constraints.maxHeight * 0.28).clamp(12.0, 44.0),
                backgroundColor: Color.alphaBlend(
                  color.withValues(alpha: AppAlpha.tintStrong),
                  scheme.surfaceContainerHigh,
                ),
                foregroundColor: color,
              ),
            ),
      ),
    );
  }
}

class _RankPill extends StatelessWidget {
  const _RankPill({required this.rank, required this.tier});

  final int rank;
  final ChefTier tier;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The pill is near-white in both themes, so its ink resolves at *light*
    // brightness whatever the page's is. The page-brightness tier colour is a
    // pastel in dark mode and measured ~1.5:1 on this pill (UX-012).
    final color = TierChip.colorFor(tier, Brightness.light);

    return Container(
      padding: _kRankPillPadding,
      decoration: BoxDecoration(
        color: context.palette.onImage.withValues(alpha: AppAlpha.frosted),
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.workspace_premium, size: AppIconSize.xs, color: color),
          const SizedBox(width: AppSpacing.xs),
          Text(
            'RANK $rank',
            maxLines: 1,
            style: theme.textTheme.labelSmall?.tabular.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

/// Tier as rarity, plus how many public recipes back it.
class _RarityBand extends StatelessWidget {
  const _RarityBand({required this.standing, required this.color});

  final ChefStanding standing;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.fromLTRB(_kInset, _kInsetLoose, _kInset, 0),
      padding: const EdgeInsets.symmetric(
        horizontal: _kInsetLoose,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withValues(alpha: AppAlpha.tint),
          theme.colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(AppRadii.chip),
      ),
      child: Row(
        children: [
          Flexible(
            child: Text(
              standing.chefTier.label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.appText.overline.copyWith(color: color),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          // `countOf`, not string interpolation: "1 recipes" shipped once
          // already (B031).
          Flexible(
            child: Text(
              countOf(standing.publicRecipeCount, 'recipes'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: theme.textTheme.labelSmall?.tabular.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// The card's one "move": whichever input contributes most to the score, with
/// the arithmetic behind it and what it is worth.
///
/// The draft puts the chef's signature dish here. That needs a per-chef recipe
/// read, which would turn a ten-card rail into eleven round trips.
///
/// The draft's windowed variant ("+330 this week") is what a [window] draws
/// (Phase 33): the gain and its span on top, then the input that earned most of
/// it, all counted inside the window.
// TODO(rails): swap this for `Signature · <dish>` once `chef_spotlights` batches
// the top recipe into the rail's single call.
class _DriverRow extends StatelessWidget {
  const _DriverRow({
    required this.standing,
    required this.color,
    this.window,
    this.windowLabel,
  });

  final ChefStanding standing;
  final Color color;
  final ChefWindowStats? window;
  final String? windowLabel;

  static IconData _iconFor(String label) => switch (label) {
    'likes' => Icons.favorite,
    'saves' => Icons.bookmark,
    _ => Icons.visibility,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final w = window;
    final top =
        ChefScoring.breakdown(
          likes: w?.likes ?? standing.totalLikes,
          saves: w?.saves ?? standing.totalSaves,
          views: w?.viewers ?? standing.totalViews,
        ).first;
    final arithmetic =
        '${countOf(top.count, top.label)} × ${groupedScore(top.weight)}';
    final title =
        w == null
            ? 'Driven by ${top.label}'
            : '${w.gainLabel} · ${windowLabel ?? 'in window'}';
    final detail =
        w == null ? arithmetic : 'Driven by ${top.label} · $arithmetic';

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: _kInset,
        vertical: AppSpacing.sm,
      ),
      // Same allocation as the header: the points take their intrinsic width up
      // to a third of the row, the description takes the rest.
      child: LayoutBuilder(
        builder:
            (context, constraints) => Row(
              children: [
                Container(
                  width: _kDriverTileSize,
                  height: _kDriverTileSize,
                  decoration: BoxDecoration(
                    color: Color.alphaBlend(
                      color.withValues(alpha: AppAlpha.tintStrong),
                      scheme.surfaceContainerHigh,
                    ),
                    borderRadius: BorderRadius.circular(_kDriverTileRadius),
                  ),
                  child: Icon(
                    _iconFor(top.label),
                    size: AppIconSize.xs,
                    color: color,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Both lines carry counts (`+312`, `1,980 likes × 3`).
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.tabular,
                      ),
                      Text(
                        detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.tabular.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: constraints.maxWidth / 3,
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      groupedScore(top.points),
                      maxLines: 1,
                      style: theme.textTheme.titleSmall?.tabular,
                    ),
                  ),
                ),
              ],
            ),
      ),
    );
  }
}

/// The four totals, then the tier-ladder progress bar and where it leads.
class _Footer extends StatelessWidget {
  const _Footer({required this.standing, required this.color});

  final ChefStanding standing;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final next = standing.nextTier;
    final atTop = next == null;

    Widget cell(int value, String label) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            groupedCount(value),
            maxLines: 1,
            style: theme.textTheme.labelSmall?.tabular,
          ),
        ),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(_kInset, 0, _kInset, _kInsetLoose),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: _kInsetTight),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: scheme.outlineVariant)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: cell(standing.publicRecipeCount, 'rec')),
                Expanded(child: cell(standing.totalLikes, 'likes')),
                Expanded(child: cell(standing.totalSaves, 'saves')),
                Expanded(child: cell(standing.totalViews, 'views')),
              ],
            ),
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.pill),
            child: LinearProgressIndicator(
              value: standing.tierProgress,
              minHeight: _kLadderBarHeight,
              backgroundColor: scheme.surfaceContainerHigh,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(height: _kLadderLabelGap),
          Row(
            children: [
              // Expanded, not Flexible: the rung line is the one that can give
              // ground, so it should also get the slack the "to go" figure
              // leaves rather than both sitting at half a row.
              Expanded(
                child: Text(
                  atTop
                      ? 'TOP TIER REACHED'
                      : '${standing.chefTier.label.split(' ').first.toUpperCase()}'
                          ' → ${next.label.split(' ').first.toUpperCase()}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.appText.overline.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  atTop ? 'max' : '${standing.pointsToNextLabel} to go',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: theme.textTheme.labelSmall?.tabular.copyWith(
                    color: atTop ? color : scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A spotlight card with no chef in it — same frame, same geometry, neutral
/// bands where the data would be.
///
/// The Trending and "best of the month" rails rank on engagement earned inside a
/// time window. Every row of that is derivable from `recipe_likes.created_at` /
/// `recipe_saves.created_at` / `recipe_views.viewed_at`, but the seed writes the
/// counters directly and leaves those logs almost empty, so a real windowed rail
/// would render three empty shelves today. These stand in until there is dated
/// engagement to rank.
// TODO(rails): replace with real cards once the seed carries dated engagement
// rows and the windowed RPC exists (see EXECUTION-PLAN Phase 23, D4/D6).
class SpotlightCardPlaceholder extends StatelessWidget {
  const SpotlightCardPlaceholder({super.key, this.tier = ChefTier.homeCook});

  /// Which tier's frame to draw. Varying it across a rail keeps the row from
  /// reading as one repeated grey block.
  final ChefTier tier;

  /// Foil intensity: under Home Cook's 0.06, so a placeholder is the flattest
  /// frame on the rail.
  static const double _foil = 0.05;

  /// Skeleton bars — a text line, a taller one, and the widths that stand in
  /// for the score and the driver line.
  static const double _lineHeight = 12;
  static const double _lineHeightTall = 14;
  static const double _scoreWidth = 44;
  static const double _driverWidth = 160;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = TierChip.colorFor(tier, theme.brightness);

    Widget bar(double width, double height) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
    );

    return SizedBox(
      width: kSpotlightCardWidth,
      height: spotlightCardHeight(context),
      child: _FoilFrame(
        // Muted: a placeholder should not out-shine a real card beside it.
        color: Color.alphaBlend(
          color.withValues(alpha: AppAlpha.rule),
          scheme.surfaceContainerHighest,
        ),
        foil: _foil,
        child: Padding(
          padding: const EdgeInsets.all(_kInset),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Stands in for the header's tier glyph.
                  bar(AppIconSize.md, AppIconSize.md),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: bar(double.infinity, _lineHeight)),
                  const SizedBox(width: AppSpacing.sm),
                  bar(_scoreWidth, _lineHeightTall),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(_kPortraitRadius),
                  ),
                  child: Center(
                    child: Icon(
                      Icons.hourglass_empty,
                      color: scheme.onSurfaceVariant.withValues(
                        alpha: AppAlpha.muted,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              bar(double.infinity, _lineHeightTall),
              const SizedBox(height: AppSpacing.sm),
              bar(_driverWidth, _lineHeight),
              const SizedBox(height: AppSpacing.sm),
              bar(double.infinity, _kLadderBarHeight),
            ],
          ),
        ),
      ),
    );
  }
}
