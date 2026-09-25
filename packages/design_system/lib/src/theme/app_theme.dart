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

  /// Warm, kitchen-inspired seed color — every `ColorScheme` role derives from
  /// it (`ColorScheme.fromSeed`, tonal spot).
  static const Color seed = Color(0xFFD2492A); // paprika red

  static ThemeData light() => _base(Brightness.light);
  static ThemeData dark() => _base(Brightness.dark);

  /// The shape every button family shares (UX-033: Outlined and Text buttons
  /// were M3 stadiums beside the themed Filled's 12px corners, in one row).
  static final OutlinedBorder _buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(AppRadii.button),
  );

  static ThemeData _base(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );
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
      cardTheme: CardThemeData(
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
          side: BorderSide(color: scheme.outlineVariant),
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
          borderRadius: BorderRadius.circular(AppRadii.chip),
        ),
      ),
      // TabBar colours its labels from `labelColor`, not from the style, so a
      // colourless style is safe here.
      tabBarTheme: TabBarThemeData(
        labelStyle: text.titleSmall,
        unselectedLabelStyle: text.titleSmall,
      ),
      navigationBarTheme: NavigationBarThemeData(
        indicatorColor: scheme.secondaryContainer,
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
          borderRadius: BorderRadius.circular(AppRadii.button),
        ),
        filled: true,
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

  /// M3's chip corner.
  static const double chip = 8;

  static const double button = 12;
  static const double card = 16;

  /// The chefs hero panel — the one large brand surface.
  static const double hero = 26;

  /// Dialogs (M3's extra-large corner).
  static const double dialog = 28;

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
  static const double sm = 16;
  static const double button = 18;
  static const double md = 20;
  static const double lg = 24;
  static const double xl = 40;
  static const double xxl = 56;
}
