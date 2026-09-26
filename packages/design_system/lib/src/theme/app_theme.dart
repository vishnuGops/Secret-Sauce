import 'package:flutter/material.dart';

import 'package:design_system/src/theme/app_palette.dart';
import 'package:design_system/src/theme/app_typography.dart';

// Every token file travels with this one: `design_system` widgets import
// `app_theme.dart` directly (the barrel is for other packages), and a token
// they cannot see is a token they hard-code instead.
export 'package:design_system/src/theme/app_motion.dart';
export 'package:design_system/src/theme/app_palette.dart';
export 'package:design_system/src/theme/app_typography.dart';

/// The Secret-Sauce theme: colour scheme, type ramp, component themes and the
/// two `ThemeExtension`s ([AppPalette], [AppTextStyles]).
///
/// **Re-skinning happens here.** Phase 36b routed every colour, type style,
/// spacing, radius and duration in the app through a token; a change of look
/// is a change of values in `src/theme/`, not a sweep across screens. See
/// `docs/design/DESIGN.md` §7 for the token ↔ code map.
class AppTheme {
  AppTheme._();

  /// Tomato — the brand accent (Phase 36c, reference 1's `#E54A3A` darkened
  /// until white text on it clears 4.5:1). `fromSeed` supplies the roles the
  /// schemes below do not name; every role the product leans on is explicit.
  static const Color seed = Color(0xFFBE3526);

  /// The light scheme: neutral white pages (no M3 tonal tint — the photos
  /// and the category blocks carry the colour), tomato primary, deep-brown
  /// secondary, burnt-orange tertiary for kickers and figures (DESIGN §3.1).
  static final ColorScheme _lightScheme = ColorScheme.fromSeed(
    seedColor: seed,
  ).copyWith(
    primary: const Color(0xFFBE3526),
    onPrimary: const Color(0xFFFFFFFF),
    primaryContainer: const Color(0xFFFFE4DE),
    onPrimaryContainer: const Color(0xFF6B1A10),
    secondary: const Color(0xFF492511),
    onSecondary: const Color(0xFFFFFFFF),
    secondaryContainer: const Color(0xFFF4E7DE),
    onSecondaryContainer: const Color(0xFF492511),
    tertiary: const Color(0xFFAD4A00),
    onTertiary: const Color(0xFFFFFFFF),
    tertiaryContainer: const Color(0xFFFFE8D5),
    onTertiaryContainer: const Color(0xFF6B2E00),
    surface: const Color(0xFFFFFFFF),
    onSurface: const Color(0xFF1F1A17),
    onSurfaceVariant: const Color(0xFF5E5650),
    surfaceContainerLowest: const Color(0xFFFFFFFF),
    surfaceContainerLow: const Color(0xFFFAF8F6),
    surfaceContainer: const Color(0xFFF5F2EF),
    surfaceContainerHigh: const Color(0xFFF1EDE9),
    surfaceContainerHighest: const Color(0xFFECE7E2),
    outline: const Color(0xFF857D77),
    outlineVariant: const Color(0xFFE3DDD8),
    inverseSurface: const Color(0xFF2B2521),
    onInverseSurface: const Color(0xFFF6F1ED),
    inversePrimary: const Color(0xFFFFB4A6),
    surfaceTint: Colors.transparent,
  );

  /// The dark scheme: neutral near-black (reference 4), accents lifted until
  /// they read on it. Cook mode renders this one always.
  static final ColorScheme _darkScheme = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: Brightness.dark,
  ).copyWith(
    primary: const Color(0xFFFF8A78),
    onPrimary: const Color(0xFF5C130B),
    primaryContainer: const Color(0xFF8E2217),
    onPrimaryContainer: const Color(0xFFFFDAD4),
    secondary: const Color(0xFFE9C4AE),
    onSecondary: const Color(0xFF3A1B0A),
    secondaryContainer: const Color(0xFF4A2E20),
    onSecondaryContainer: const Color(0xFFF6DDCF),
    tertiary: const Color(0xFFFFB77A),
    onTertiary: const Color(0xFF4A2300),
    tertiaryContainer: const Color(0xFF6B3400),
    onTertiaryContainer: const Color(0xFFFFDCC2),
    surface: const Color(0xFF161616),
    onSurface: const Color(0xFFEDEAE7),
    onSurfaceVariant: const Color(0xFFBDB7B2),
    surfaceContainerLowest: const Color(0xFF101010),
    surfaceContainerLow: const Color(0xFF1D1D1D),
    surfaceContainer: const Color(0xFF222222),
    surfaceContainerHigh: const Color(0xFF2B2B2B),
    surfaceContainerHighest: const Color(0xFF363636),
    outline: const Color(0xFF8F8983),
    outlineVariant: const Color(0xFF3A3A3A),
    inverseSurface: const Color(0xFFEDEAE7),
    onInverseSurface: const Color(0xFF2B2521),
    inversePrimary: const Color(0xFFB8321F),
    surfaceTint: Colors.transparent,
  );

  static ThemeData light() => _base(Brightness.light);
  static ThemeData dark() => _base(Brightness.dark);

  /// The shape every button family shares (UX-033), a pill since 36c
  /// (references 2 and 5 pill their actions and tags).
  static final OutlinedBorder _buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(AppRadii.button),
  );

  static ThemeData _base(Brightness brightness) {
    final scheme = brightness == Brightness.dark ? _darkScheme : _lightScheme;
    final palette = AppPalette.of(brightness);
    final text = AppTypography.textTheme;
    // Buttons read a touch heavier than the ramp's labelLarge (the mockups'
    // `.btn` is 700): an action is the one label that must win its row.
    final buttonText = text.labelLarge!.copyWith(fontWeight: FontWeight.w700);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: AppFonts.uiFamily,
      textTheme: text,
      scaffoldBackgroundColor: scheme.surface,
      extensions: [palette, AppTypography.roles],
      // Cards are quiet tonal panels with no outline (references 1, 2, 5): a
      // step off the page, not a box drawn round it. `theme_contrast_test`
      // measures text on this fill as "Card".
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
        ),
      ),
      // --- Buttons: one shape, one height, one label weight (UX-033) -------
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: _buttonShape,
          padding: AppInsets.button,
          textStyle: buttonText,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: _buttonShape,
          padding: AppInsets.button,
          textStyle: buttonText,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape: _buttonShape,
          padding: AppInsets.button,
          textStyle: buttonText,
        ),
      ),
      // Text buttons keep M3's compact padding — they have no container, so
      // their height does not show beside a filled one — but share the
      // corner and the label weight, which is what their ripple and focus
      // ring draw.
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(shape: _buttonShape, textStyle: buttonText),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(iconSize: AppIconSize.lg),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(textStyle: buttonText),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
        ),
        extendedTextStyle: buttonText,
      ),
      // --- Selection controls -------------------------------------------
      // No `labelStyle` here, and no `labelTextStyle` on the navigation bar
      // below: a theme-level style *replaces* M3's state-resolved one, and the
      // ramp's styles carry no colour, so chip and nav labels lost their
      // enabled / selected / disabled colours (white text on a light chip on
      // native). The M3 defaults already read our `labelLarge` / `labelMedium`
      // from the ramp. `theme_extensions_test.dart` pins the resolved colours.
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
      ),
      // TabBar colours its labels from `labelColor`, not from the style, so a
      // colourless style is safe here.
      tabBarTheme: TabBarThemeData(
        labelStyle: text.titleSmall,
        unselectedLabelStyle: text.titleSmall,
      ),
      // The active destination is tomato (reference 5). The label style carries
      // its own state colours — a colourless one would replace M3's (36b
      // review; `theme_extensions_test` pins them).
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color:
                states.contains(WidgetState.selected)
                    ? scheme.primary
                    : scheme.onSurfaceVariant,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => text.labelMedium!.copyWith(
            color:
                states.contains(WidgetState.selected)
                    ? scheme.primary
                    : scheme.onSurfaceVariant,
          ),
        ),
      ),
      // --- Overlays -----------------------------------------------------
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.dialog),
        ),
        titleTextStyle: text.headlineSmall?.copyWith(color: scheme.onSurface),
        contentTextStyle: text.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        contentTextStyle: text.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
        actionTextColor: scheme.inversePrimary,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
        filled: true,
        fillColor: scheme.surfaceContainer,
      ),
    );
  }
}

/// Spacing scale — an 8pt grid with three half-steps.
///
/// `xs … xxl` is the scale. The half-steps (`xxs`, `xsPlus`, `smPlus`) are
/// there because the audit found them in repeated use as an unofficial second
/// scale (UX-054); naming them makes that scale official and finite. A value
/// that is none of these is either a component inset ([AppInsets]) or a named
/// constant on the one widget whose geometry it is.
class AppSpacing {
  AppSpacing._();
  static const double xxs = 2;
  static const double xs = 4;
  static const double xsPlus = 6;
  static const double sm = 8;
  static const double smPlus = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}

/// Component paddings — the insets of a shared shape, named once so every
/// instance of that shape stays the same size.
abstract final class AppInsets {
  /// Every button family (Filled, Outlined, Elevated) — about 48dp tall.
  static const EdgeInsets button = EdgeInsets.symmetric(
    horizontal: 20,
    vertical: 14,
  );

  /// A small status badge: difficulty, tier.
  static const EdgeInsets badge = EdgeInsets.symmetric(
    horizontal: AppSpacing.sm,
    vertical: AppSpacing.xxs,
  );

  /// The same badge where horizontal space is the scarce resource.
  static const EdgeInsets badgeDense = EdgeInsets.symmetric(
    horizontal: AppSpacing.xsPlus,
    vertical: 1,
  );

  /// An icon + label pill (the chefs hero's "N ranked").
  static const EdgeInsets pill = EdgeInsets.symmetric(
    horizontal: 10,
    vertical: AppSpacing.xs,
  );

  /// The track around a row of segments (a pill-shaped segmented control).
  static const EdgeInsets segmentTrack = EdgeInsets.all(3);

  /// One segment inside that track.
  static const EdgeInsets segment = EdgeInsets.symmetric(
    horizontal: AppSpacing.smPlus,
    vertical: 5,
  );

  /// A bordered callout box — the provenance block, cook mode's timer panel.
  static const EdgeInsets callout = EdgeInsets.all(14);
}

class AppRadii {
  AppRadii._();

  /// A small inner corner — a check box, a chip inside a card.
  static const double sm = 6;

  /// M3's chip corner — for a small rounded box that is not a pill.
  static const double chip = 8;

  /// A control or text box that is not a button: inputs, the ink region of a
  /// tappable text link, the nutrition label's frame.
  static const double md = 12;

  /// Every button family — a pill since 36c (it was 12, now [md]).
  static const double button = pill;

  /// Photos and panels (the photo is the card now — 36c).
  static const double card = 16;

  /// The chefs hero panel — the one large brand surface.
  static const double hero = 26;

  /// Dialogs (M3's extra-large corner).
  static const double dialog = 28;

  /// The top corners of the recipe detail sheet that overlaps its photo
  /// (reference 5).
  static const double sheet = 28;

  /// A fully rounded end — chips, badges, pills, the nav bar's selection.
  ///
  /// 999 rather than a computed half-height: `BorderRadius.circular` clamps to
  /// half the shorter side, so any number past the tallest pill in the product
  /// renders identically and none of the 22 call sites (32d6) has to know its
  /// own height. It was that literal, twelve files over, until this constant
  /// gave the shape a name.
  static const double pill = 999;
}

/// Icon sizes. `sm` sits inline with label text, `button` is M3's in-button
/// size, `md` a chip or list glyph, `lg` app bars, navigation and standalone
/// icon buttons; `xl`/`xxl` are empty-state and placeholder glyphs.
abstract final class AppIconSize {
  static const double xs = 14;

  /// A glyph set inside a line of 12–14px metadata — the recipe card's time
  /// and rating row and `StarRating`'s default star (Phase 38: two named
  /// per-widget 15s collapsed into it).
  static const double xsPlus = 15;
  static const double sm = 16;
  static const double button = 18;
  static const double md = 20;
  static const double lg = 24;
  static const double xl = 40;
  static const double xxl = 56;
}

/// Line and bar thicknesses (Phase 38). Named per widget until two or more
/// consts agreed on a value; these are the values that did.
///
/// `hairline` an inner focus hairline or a panel edge · `thin` a spinner's
/// stroke, a check box's outline, a focus ring on a small control, a rule ·
/// `medium` the keyboard focus ring on a tile, a selected ring, a portrait
/// border · `thick` a slim progress or ladder bar · `bar` a score or tier bar.
abstract final class AppStroke {
  static const double hairline = 1;
  static const double thin = 2;
  static const double medium = 3;
  static const double thick = 4;
  static const double bar = 8;
}

/// Content measures — the widest a single column of a given kind may run
/// (Phase 38). Breakpoints decide the layout; these decide how wide one column
/// of it reads.
///
/// `narrow` a single-field form or a small dialog (sign in, share) ·
/// `column` a single-column page of controls (profile, cook mode's finish) ·
/// `reading` a long form or running prose (the recipe editor, the legal
/// documents, cook mode's step text).
abstract final class AppMeasure {
  static const double narrow = 420;
  static const double column = 560;
  static const double reading = 720;
}
