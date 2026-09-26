import 'package:core/core.dart';
import 'package:flutter/material.dart';

/// The colours Secret-Sauce needs that Material 3's `ColorScheme` has no role
/// for — difficulty, rating, chef tiers, the always-dark chefs hero, and the
/// treatments that sit on top of a photograph.
///
/// **Every literal colour in the product lives here or in the scheme.** A
/// widget reads `context.palette.<field>`; it never branches on brightness to
/// pick a hex itself. Both brightnesses are defined, and
/// `theme_contrast_test.dart` asserts each foreground/background pair against
/// WCAG 2.2 AA (4.5:1 text, 3:1 UI) in light *and* dark.
///
/// Values chosen 2026-09-25 (Phase 36b). Where they differ from what the
/// widgets used to hard-code, the difference is a contrast fix and cites its
/// audit id (B133 / UX-010 / UX-011 / UX-012).
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.rating,
    required this.difficultyEasy,
    required this.difficultyMedium,
    required this.difficultyHard,
    required this.tierHomeCook,
    required this.tierLineCook,
    required this.tierSousChef,
    required this.tierHeadChef,
    required this.tierMasterChef,
    required this.scrim,
    required this.onImage,
    required this.imageControl,
    required this.imageOutline,
    required this.coverScrim,
    required this.foilShade,
    required this.foilHighlight,
    required this.floatingShadow,
    required this.heroStart,
    required this.heroMid,
    required this.heroEnd,
    required this.onHero,
    required this.onHeroMuted,
    required this.heroFill,
    required this.heroFillSubtle,
    required this.heroSelectedInk,
    required this.heroShadow,
    required this.surfaceWarm,
    required this.categoryYellow,
    required this.categoryCoral,
    required this.categoryPink,
    required this.categoryBrown,
    required this.categorySage,
    required this.categorySky,
    required this.onCategoryLight,
    required this.onCategoryDark,
    required this.rankRibbon,
    required this.onRankRibbon,
  });

  /// Filled rating stars and the rating pill's star. Light was saffron
  /// `#F2A93B` (1.9:1 on the surface — UX-011); now a deeper saffron that
  /// clears 3:1 for a UI graphic on both the page and a card.
  final Color rating;

  /// Difficulty badge text + icon; the badge fill is this colour at
  /// [AppAlpha.badge] over whatever surface holds it. Light values replace
  /// `Colors.green.shade600` / `orange.shade700` (2.8 / 2.3:1 — UX-010) and
  /// stop `Hard` borrowing `scheme.error`, which read as an error state.
  final Color difficultyEasy;
  final Color difficultyMedium;
  final Color difficultyHard;

  /// Chef tier accents (chip, ladder, spotlight card). Light home/sous/master
  /// were darkened (B133 follow-through): at the chip's 14% wash the old
  /// shades measured 4.3 / 4.5 / 3.5:1 for 11px text. Measured on the page,
  /// on a `Card` (`surfaceContainerLow` — where the standing card puts the
  /// chip) and on `surfaceContainerLowest`.
  final Color tierHomeCook;
  final Color tierLineCook;
  final Color tierSousChef;
  final Color tierHeadChef;
  final Color tierMasterChef;

  /// The dark wash under text that sits on a cover photo (chef badge on a
  /// recipe card). Black at 55%: white on it over a pure-white photo is 4.7:1.
  final Color scrim;

  /// Foreground on [scrim] / [imageControl] — always white, whatever the
  /// page's brightness, because the surface under it is a photograph.
  final Color onImage;

  /// Background of a round control floating on a cover (the compact detail
  /// page's back button). Black at 45% — the old 40% left the white glyph at
  /// 2.9:1 over a white plate, under the 3:1 a UI graphic needs.
  final Color imageControl;

  /// Neutral inset hairline around photos so a pale plate does not bleed into
  /// a pale surface. Never brand-tinted.
  final Color imageOutline;

  /// Top of the gradient behind the spotlight card's cover caption; the
  /// gradient runs to this colour at zero alpha.
  final Color coverScrim;

  /// The spotlight card's foil: the tier colour is lerped toward this shade
  /// for the lower edge of the frame.
  final Color foilShade;

  /// The spotlight card's inner highlight — bright on light surfaces, barely
  /// there on dark ones.
  final Color foilHighlight;

  /// Shadow for a floating layer (the spotlight card lifts off the rail). The
  /// border-not-shadow policy applies to everything else.
  final Color floatingShadow;

  /// The chefs hero — a brand surface that is **dark in both themes**, so all
  /// of these are identical in [light] and [dark].
  final Color heroStart;
  final Color heroMid;
  final Color heroEnd;

  /// Primary text on the hero.
  final Color onHero;

  /// Secondary text on the hero. White at 70%: the old 58% "faint" step
  /// measured 3.7:1 on the Master Chef tile at the gradient's light end.
  final Color onHeroMuted;

  /// Translucent fills on the hero (pills, the window filter track, the top
  /// tier tile) and the subtler one under the other tier tiles.
  final Color heroFill;
  final Color heroFillSubtle;

  /// Text on the hero's selected (white) segment.
  final Color heroSelectedInk;

  /// The hero's drop shadow.
  final Color heroShadow;

  /// The warm cream band a page opens on — Discover's masthead (reference
  /// 2's `#FBF7F4`). A section surface, not a card.
  final Color surfaceWarm;

  /// Reference 1's colour blocks: the category tiles on Discover, and the
  /// cover a recipe with **no photo** gets (Phase 36c, owner's Q1). Flat,
  /// saturated, the same in both themes — they are illustrations, not
  /// surfaces. Text on them is [onCategoryLight] (dark ink) except on
  /// [categoryBrown], which takes [onCategoryDark] (white); read them through
  /// [category] so a caller cannot pair them wrong.
  final Color categoryYellow;
  final Color categoryCoral;
  final Color categoryPink;
  final Color categoryBrown;
  final Color categorySage;
  final Color categorySky;
  final Color onCategoryLight;
  final Color onCategoryDark;

  /// The rank flag on a ranked shelf's cards (reference 2), with its ink.
  final Color rankRibbon;
  final Color onRankRibbon;

  /// The colour block and its ink for a recipe [category] (free text in the
  /// database). A category in one of Discover's six tile groups
  /// (`DiscoverCategory`) takes that tile's block, so a cover and the filter
  /// that finds it agree; any other string hashes to one of the six so it is
  /// stable across renders; null (no category) takes coral.
  CategoryColors category(String? category) {
    final blocks = <(Color, Color)>[
      (categoryCoral, onCategoryLight),
      (categoryYellow, onCategoryLight),
      (categoryPink, onCategoryLight),
      (categoryBrown, onCategoryDark),
      (categorySage, onCategoryLight),
      (categorySky, onCategoryLight),
    ];
    // One mapping: the Discover tiles' groups (core's `DiscoverCategory`),
    // in the same order as [blocks]. Anything else hashes to a stable block.
    final tile = DiscoverCategory.forCategory(category);
    final key = category?.trim().toLowerCase();
    final index =
        tile != null
            ? tile.index
            : key == null || key.isEmpty
            ? 0
            : key.codeUnits.fold<int>(0, (h, c) => (h * 31 + c) & 0x7fffffff) %
                blocks.length;
    final (background, foreground) = blocks[index];
    return CategoryColors(background: background, foreground: foreground);
  }

  /// The tier accent for [tier] at this palette's brightness.
  Color tier(ChefTier tier) => switch (tier) {
    ChefTier.homeCook => tierHomeCook,
    ChefTier.lineCook => tierLineCook,
    ChefTier.sousChef => tierSousChef,
    ChefTier.headChef => tierHeadChef,
    ChefTier.masterChef => tierMasterChef,
  };

  /// The difficulty accent for [difficulty].
  Color difficulty(Difficulty difficulty) => switch (difficulty) {
    Difficulty.easy => difficultyEasy,
    Difficulty.medium => difficultyMedium,
    Difficulty.hard => difficultyHard,
  };

  /// The palette for [brightness] — for the few places that must resolve a
  /// colour at a brightness other than the page's (a tier chip on a photo
  /// scrim, the always-dark hero, the always-light rank pill).
  static AppPalette of(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  // Hero values shared by both palettes.
  static const _heroStart = Color(0xFF241A17);
  static const _heroMid = Color(0xFF3B2823);
  static const _heroEnd = Color(0xFF5C3B2D);
  static const _white = Color(0xFFFFFFFF);
  static const _white70 = Color(0xB3FFFFFF);
  static const _white10 = Color(0x1AFFFFFF);
  static const _white7 = Color(0x12FFFFFF);
  static const _heroInk = Color(0xFF2C1F1B);
  static const _heroShadow = Color(0x42231917);
  static const _black55 = Color(0x8C000000);
  static const _black45 = Color(0x73000000);
  static const _coverScrim = Color(0xC7140C0A);
  static const _foilShade = Color(0xFF2A1D1A);
  // Reference 1's blocks (M), plus sage and sky for the two categories it
  // has no tile for. All ≥ 5.8:1 with their ink (theme_contrast_test).
  static const _yellow = Color(0xFFFED801);
  static const _coral = Color(0xFFFF6449);
  static const _pink = Color(0xFFFDB5C0);
  static const _brown = Color(0xFF8C4411);
  static const _sage = Color(0xFFA8D08D);
  static const _sky = Color(0xFF9FD3E6);
  static const _blockInk = Color(0xFF231917);
  static const _ribbon = Color(0xFFF2CF3B);
  static const _ribbonInk = Color(0xFF3A2A00);

  static const light = AppPalette(
    rating: Color(0xFFB7700A),
    difficultyEasy: Color(0xFF2A6E2E),
    difficultyMedium: Color(0xFF8A4F00),
    difficultyHard: Color(0xFF9F2B26),
    tierHomeCook: Color(0xFF4A626D), // slate
    tierLineCook: Color(0xFF00695C), // teal
    tierSousChef: Color(0xFF1360B5), // blue
    tierHeadChef: Color(0xFF6A1B9A), // purple
    tierMasterChef: Color(0xFF8F5000), // amber
    scrim: _black55,
    onImage: _white,
    imageControl: _black45,
    imageOutline: Color(0x1A000000),
    coverScrim: _coverScrim,
    foilShade: _foilShade,
    foilHighlight: Color(0x80FFFFFF),
    floatingShadow: Color(0x38000000),
    heroStart: _heroStart,
    heroMid: _heroMid,
    heroEnd: _heroEnd,
    onHero: _white,
    onHeroMuted: _white70,
    heroFill: _white10,
    heroFillSubtle: _white7,
    heroSelectedInk: _heroInk,
    heroShadow: _heroShadow,
    surfaceWarm: Color(0xFFFBF7F4),
    categoryYellow: _yellow,
    categoryCoral: _coral,
    categoryPink: _pink,
    categoryBrown: _brown,
    categorySage: _sage,
    categorySky: _sky,
    onCategoryLight: _blockInk,
    onCategoryDark: _white,
    rankRibbon: _ribbon,
    onRankRibbon: _ribbonInk,
  );

  static const dark = AppPalette(
    rating: Color(0xFFF2A93B), // saffron
    difficultyEasy: Color(0xFF66BB6A),
    difficultyMedium: Color(0xFFFFA726),
    difficultyHard: Color(0xFFFFB4A8),
    tierHomeCook: Color(0xFFB0BEC5),
    tierLineCook: Color(0xFF80CBC4),
    tierSousChef: Color(0xFF90CAF9),
    tierHeadChef: Color(0xFFCE93D8),
    tierMasterChef: Color(0xFFFFCC80),
    scrim: _black55,
    onImage: _white,
    imageControl: _black45,
    imageOutline: Color(0x1AFFFFFF),
    coverScrim: _coverScrim,
    foilShade: _foilShade,
    foilHighlight: Color(0x1FFFFFFF),
    floatingShadow: Color(0x66000000),
    heroStart: _heroStart,
    heroMid: _heroMid,
    heroEnd: _heroEnd,
    onHero: _white,
    onHeroMuted: _white70,
    heroFill: _white10,
    heroFillSubtle: _white7,
    heroSelectedInk: _heroInk,
    heroShadow: _heroShadow,
    surfaceWarm: Color(0xFF1E1B19),
    categoryYellow: _yellow,
    categoryCoral: _coral,
    categoryPink: _pink,
    categoryBrown: _brown,
    categorySage: _sage,
    categorySky: _sky,
    onCategoryLight: _blockInk,
    onCategoryDark: _white,
    rankRibbon: _ribbon,
    onRankRibbon: _ribbonInk,
  );

  /// The chefs hero's `linear-gradient(104deg, …)`.
  LinearGradient get heroGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [heroStart, heroMid, heroEnd],
    stops: const [0, 0.52, 1],
  );

  @override
  AppPalette copyWith({
    Color? rating,
    Color? difficultyEasy,
    Color? difficultyMedium,
    Color? difficultyHard,
    Color? tierHomeCook,
    Color? tierLineCook,
    Color? tierSousChef,
    Color? tierHeadChef,
    Color? tierMasterChef,
    Color? scrim,
    Color? onImage,
    Color? imageControl,
    Color? imageOutline,
    Color? coverScrim,
    Color? foilShade,
    Color? foilHighlight,
    Color? floatingShadow,
    Color? heroStart,
    Color? heroMid,
    Color? heroEnd,
    Color? onHero,
    Color? onHeroMuted,
    Color? heroFill,
    Color? heroFillSubtle,
    Color? heroSelectedInk,
    Color? heroShadow,
    Color? surfaceWarm,
    Color? categoryYellow,
    Color? categoryCoral,
    Color? categoryPink,
    Color? categoryBrown,
    Color? categorySage,
    Color? categorySky,
    Color? onCategoryLight,
    Color? onCategoryDark,
    Color? rankRibbon,
    Color? onRankRibbon,
  }) => AppPalette(
    rating: rating ?? this.rating,
    difficultyEasy: difficultyEasy ?? this.difficultyEasy,
    difficultyMedium: difficultyMedium ?? this.difficultyMedium,
    difficultyHard: difficultyHard ?? this.difficultyHard,
    tierHomeCook: tierHomeCook ?? this.tierHomeCook,
    tierLineCook: tierLineCook ?? this.tierLineCook,
    tierSousChef: tierSousChef ?? this.tierSousChef,
    tierHeadChef: tierHeadChef ?? this.tierHeadChef,
    tierMasterChef: tierMasterChef ?? this.tierMasterChef,
    scrim: scrim ?? this.scrim,
    onImage: onImage ?? this.onImage,
    imageControl: imageControl ?? this.imageControl,
    imageOutline: imageOutline ?? this.imageOutline,
    coverScrim: coverScrim ?? this.coverScrim,
    foilShade: foilShade ?? this.foilShade,
    foilHighlight: foilHighlight ?? this.foilHighlight,
    floatingShadow: floatingShadow ?? this.floatingShadow,
    heroStart: heroStart ?? this.heroStart,
    heroMid: heroMid ?? this.heroMid,
    heroEnd: heroEnd ?? this.heroEnd,
    onHero: onHero ?? this.onHero,
    onHeroMuted: onHeroMuted ?? this.onHeroMuted,
    heroFill: heroFill ?? this.heroFill,
    heroFillSubtle: heroFillSubtle ?? this.heroFillSubtle,
    heroSelectedInk: heroSelectedInk ?? this.heroSelectedInk,
    heroShadow: heroShadow ?? this.heroShadow,
    surfaceWarm: surfaceWarm ?? this.surfaceWarm,
    categoryYellow: categoryYellow ?? this.categoryYellow,
    categoryCoral: categoryCoral ?? this.categoryCoral,
    categoryPink: categoryPink ?? this.categoryPink,
    categoryBrown: categoryBrown ?? this.categoryBrown,
    categorySage: categorySage ?? this.categorySage,
    categorySky: categorySky ?? this.categorySky,
    onCategoryLight: onCategoryLight ?? this.onCategoryLight,
    onCategoryDark: onCategoryDark ?? this.onCategoryDark,
    rankRibbon: rankRibbon ?? this.rankRibbon,
    onRankRibbon: onRankRibbon ?? this.onRankRibbon,
  );

  @override
  AppPalette lerp(covariant AppPalette? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppPalette(
      rating: l(rating, other.rating),
      difficultyEasy: l(difficultyEasy, other.difficultyEasy),
      difficultyMedium: l(difficultyMedium, other.difficultyMedium),
      difficultyHard: l(difficultyHard, other.difficultyHard),
      tierHomeCook: l(tierHomeCook, other.tierHomeCook),
      tierLineCook: l(tierLineCook, other.tierLineCook),
      tierSousChef: l(tierSousChef, other.tierSousChef),
      tierHeadChef: l(tierHeadChef, other.tierHeadChef),
      tierMasterChef: l(tierMasterChef, other.tierMasterChef),
      scrim: l(scrim, other.scrim),
      onImage: l(onImage, other.onImage),
      imageControl: l(imageControl, other.imageControl),
      imageOutline: l(imageOutline, other.imageOutline),
      coverScrim: l(coverScrim, other.coverScrim),
      foilShade: l(foilShade, other.foilShade),
      foilHighlight: l(foilHighlight, other.foilHighlight),
      floatingShadow: l(floatingShadow, other.floatingShadow),
      heroStart: l(heroStart, other.heroStart),
      heroMid: l(heroMid, other.heroMid),
      heroEnd: l(heroEnd, other.heroEnd),
      onHero: l(onHero, other.onHero),
      onHeroMuted: l(onHeroMuted, other.onHeroMuted),
      heroFill: l(heroFill, other.heroFill),
      heroFillSubtle: l(heroFillSubtle, other.heroFillSubtle),
      heroSelectedInk: l(heroSelectedInk, other.heroSelectedInk),
      heroShadow: l(heroShadow, other.heroShadow),
      surfaceWarm: l(surfaceWarm, other.surfaceWarm),
      categoryYellow: l(categoryYellow, other.categoryYellow),
      categoryCoral: l(categoryCoral, other.categoryCoral),
      categoryPink: l(categoryPink, other.categoryPink),
      categoryBrown: l(categoryBrown, other.categoryBrown),
      categorySage: l(categorySage, other.categorySage),
      categorySky: l(categorySky, other.categorySky),
      onCategoryLight: l(onCategoryLight, other.onCategoryLight),
      onCategoryDark: l(onCategoryDark, other.onCategoryDark),
      rankRibbon: l(rankRibbon, other.rankRibbon),
      onRankRibbon: l(onRankRibbon, other.onRankRibbon),
    );
  }
}

/// A category block and the ink that reads on it — see
/// [AppPalette.category].
@immutable
class CategoryColors {
  const CategoryColors({required this.background, required this.foreground});

  final Color background;
  final Color foreground;
}

/// Opacity steps for tinting a token colour (a tier accent's wash, a border
/// drawn from an accent). The steps are the ones the product already used,
/// named — a new tint picks one of these rather than a fresh number.
abstract final class AppAlpha {
  /// The quietest wash (hero tier tiles).
  static const double faint = 0.07;

  /// An accent wash behind a header or a pill.
  static const double wash = 0.10;

  /// The difficulty badge's fill.
  static const double badge = 0.12;

  /// A chip's fill (tier chip, rank badge).
  static const double tint = 0.14;

  /// A stronger tint — avatar rings, emphasised badges.
  static const double tintStrong = 0.16;

  /// A tier chip's fill when it sits on a photo scrim (B055).
  static const double onImageTint = 0.28;

  /// A soft accent glow.
  static const double glow = 0.30;

  /// A border or rule drawn from an accent colour.
  static const double rule = 0.35;

  /// An emphasised accent border (the hero's Master Chef tile).
  static const double emphasis = 0.45;

  /// Half-strength: a muted glyph, a disabled rule.
  static const double muted = 0.5;

  /// A surface laid over a cover photo that must stay almost opaque.
  static const double frosted = 0.92;
}

extension AppPaletteContext on BuildContext {
  /// The [AppPalette] of the ambient theme. Both `AppTheme.light()` and
  /// `AppTheme.dark()` carry one (`theme_extensions_test.dart`); a theme built
  /// elsewhere without it falls back to the palette for its brightness rather
  /// than throwing.
  AppPalette get palette {
    final theme = Theme.of(this);
    return theme.extension<AppPalette>() ?? AppPalette.of(theme.brightness);
  }
}
