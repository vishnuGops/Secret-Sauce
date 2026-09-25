import 'package:flutter/material.dart';

/// The two bundled families (OFL, `packages/design_system/fonts/`).
///
/// **Newsreader** (serif) sets names and headings — display, headline and
/// `titleLarge`. **Manrope** (sans) sets everything a cook acts on: titles
/// from `titleMedium` down, body, labels, numbers. Owner decision 2026-09-25;
/// the Claude Design mockups (`_ds_bundle.css`) drew the same pairing.
///
/// Bundled rather than fetched: CanvasKit has no system fonts to fall back to,
/// so a runtime fetch flashes unstyled text, and a bundle works offline.
abstract final class AppFonts {
  /// The package the font assets are declared in — a family from another
  /// package resolves as `packages/<package>/<family>`.
  static const String package = 'design_system';

  static const String ui = 'Manrope';
  static const String display = 'Newsreader';

  /// The resolved family names, for APIs that take a bare string
  /// (`ThemeData.fontFamily`, a `TextPainter`).
  static const String uiFamily = 'packages/$package/$ui';
  static const String displayFamily = 'packages/$package/$display';
}

/// Tabular (fixed-width) digits — for anything that changes while you watch
/// it or lines up in a column: timers, counts, scores, ranks, quantities,
/// the servings stepper (UX-049).
const List<FontFeature> kTabularFigures = [FontFeature.tabularFigures()];

/// The type ramp: the full Material 3 `TextTheme`, every role defined.
///
/// Sizes and line heights are Material 3's (so the 2.0× envelope maths —
/// `kRecipeCardBannerHeight` and friends — is unchanged); families and
/// weights are ours. **Call sites pick a role; they do not re-bold.** A weight
/// that keeps being overridden is a missing role — add it to [AppTextStyles].
abstract final class AppTypography {
  static TextStyle _display(double size, double lineHeight, {double ls = 0}) =>
      TextStyle(
        fontFamily: AppFonts.display,
        package: AppFonts.package,
        fontSize: size,
        height: lineHeight / size,
        fontWeight: FontWeight.w600,
        letterSpacing: ls,
      );

  static TextStyle _ui(
    double size,
    double lineHeight,
    FontWeight weight, {
    double ls = 0,
  }) => TextStyle(
    fontFamily: AppFonts.ui,
    package: AppFonts.package,
    fontSize: size,
    height: lineHeight / size,
    fontWeight: weight,
    letterSpacing: ls,
  );

  /// Colourless: `ThemeData` merges it over the scheme-coloured default, so
  /// each role picks up `onSurface` the way M3's own ramp does.
  static final TextTheme textTheme = TextTheme(
    displayLarge: _display(57, 64, ls: -0.5),
    displayMedium: _display(45, 52, ls: -0.4),
    displaySmall: _display(36, 44, ls: -0.3),
    headlineLarge: _display(32, 40, ls: -0.2),
    headlineMedium: _display(28, 36),
    headlineSmall: _display(24, 32),
    titleLarge: _display(22, 28),
    titleMedium: _ui(16, 24, FontWeight.w700),
    titleSmall: _ui(14, 20, FontWeight.w700),
    bodyLarge: _ui(16, 24, FontWeight.w400),
    bodyMedium: _ui(14, 20, FontWeight.w400),
    bodySmall: _ui(12, 16, FontWeight.w400),
    labelLarge: _ui(14, 20, FontWeight.w600),
    labelMedium: _ui(12, 16, FontWeight.w600),
    // w700 rather than the mockups' 600: 11px is the smallest text in the
    // product and it carries chips, badges and counters — kitchen-proof wins.
    // It also absorbs the 21 call sites that re-bolded labelSmall to 700/800.
    labelSmall: _ui(11, 16, FontWeight.w700, ls: 0.2),
  );

  /// The product-specific roles, built on [textTheme]'s metrics.
  static final AppTextStyles roles = AppTextStyles(
    kicker: _ui(
      11,
      16,
      FontWeight.w700,
      ls: 1.4,
    ).copyWith(fontFeatures: kTabularFigures),
    kickerLarge: _ui(
      14,
      20,
      FontWeight.w700,
      ls: 1.4,
    ).copyWith(fontFeatures: kTabularFigures),
    overline: _ui(11, 16, FontWeight.w700, ls: 0.8),
    stat: _ui(16, 24, FontWeight.w800).copyWith(fontFeatures: kTabularFigures),
    statLarge: _ui(
      22,
      28,
      FontWeight.w800,
    ).copyWith(fontFeatures: kTabularFigures),
    quantity: _ui(
      14,
      20,
      FontWeight.w800,
    ).copyWith(fontFeatures: kTabularFigures),
    clock: _ui(24, 32, FontWeight.w600).copyWith(fontFeatures: kTabularFigures),
    clockSmall: _ui(
      22,
      28,
      FontWeight.w600,
    ).copyWith(fontFeatures: kTabularFigures),
    step: _ui(24, 32, FontWeight.w500),
    stepLarge: _ui(36, 46, FontWeight.w500),
  );
}

/// Text roles Material 3 has no slot for. Read with `context.appText`.
///
/// Each exists because the audit found the same override repeated at several
/// call sites (UX-031): six hand-rolled kickers, numbers re-bolded to w800,
/// the quantity gutter's own weight.
@immutable
class AppTextStyles extends ThemeExtension<AppTextStyles> {
  const AppTextStyles({
    required this.kicker,
    required this.kickerLarge,
    required this.overline,
    required this.stat,
    required this.statLarge,
    required this.quantity,
    required this.clock,
    required this.clockSmall,
    required this.step,
    required this.stepLarge,
  });

  /// **The index line** — DESIGN.md §1's memorable detail. A small, widely
  /// tracked, tabular kicker set above a heading: `01 UNDER 30`, section
  /// labels, the chefs hero strapline. Callers upper-case the string.
  final TextStyle kicker;

  /// The index line at section level — a shelf's `01 UNDER 30`, Discover's
  /// `EVERYTHING ELSE`: the same tracked, tabular caps at 14px, where the
  /// line *is* the heading rather than a label above one.
  final TextStyle kickerLarge;

  /// A small upper-case label with modest tracking — tier names under a
  /// count, a caption over a stat.
  final TextStyle overline;

  /// A number that is the point of its row: a score, a count, a rank.
  /// Sans, heavy, tabular.
  final TextStyle stat;

  /// The same at headline size — the spotlight card's score, the standing
  /// card's rank.
  final TextStyle statLarge;

  /// An ingredient quantity in the rail's fixed gutter.
  final TextStyle quantity;

  /// A running countdown (cook mode).
  final TextStyle clock;

  /// The same where the timer ring is smaller (cook mode's wide layout).
  final TextStyle clockSmall;

  /// A cook-mode step's instruction, read at arm's length. Sans on purpose:
  /// at headline and display size the M3 roles are the serif, and a step is
  /// something a cook acts on, not a heading (DESIGN.md §1, principle 1).
  final TextStyle step;

  /// The same on the wide cook-mode layout.
  final TextStyle stepLarge;

  @override
  AppTextStyles copyWith({
    TextStyle? kicker,
    TextStyle? kickerLarge,
    TextStyle? overline,
    TextStyle? stat,
    TextStyle? statLarge,
    TextStyle? quantity,
    TextStyle? clock,
    TextStyle? clockSmall,
    TextStyle? step,
    TextStyle? stepLarge,
  }) => AppTextStyles(
    kicker: kicker ?? this.kicker,
    kickerLarge: kickerLarge ?? this.kickerLarge,
    overline: overline ?? this.overline,
    stat: stat ?? this.stat,
    statLarge: statLarge ?? this.statLarge,
    quantity: quantity ?? this.quantity,
    clock: clock ?? this.clock,
    clockSmall: clockSmall ?? this.clockSmall,
    step: step ?? this.step,
    stepLarge: stepLarge ?? this.stepLarge,
  );

  @override
  AppTextStyles lerp(covariant AppTextStyles? other, double t) {
    if (other == null) return this;
    TextStyle l(TextStyle a, TextStyle b) => TextStyle.lerp(a, b, t)!;
    return AppTextStyles(
      kicker: l(kicker, other.kicker),
      kickerLarge: l(kickerLarge, other.kickerLarge),
      overline: l(overline, other.overline),
      stat: l(stat, other.stat),
      statLarge: l(statLarge, other.statLarge),
      quantity: l(quantity, other.quantity),
      clock: l(clock, other.clock),
      clockSmall: l(clockSmall, other.clockSmall),
      step: l(step, other.step),
      stepLarge: l(stepLarge, other.stepLarge),
    );
  }
}

extension AppTextStylesContext on BuildContext {
  /// The [AppTextStyles] of the ambient theme. The roles carry no colour, so
  /// text inherits the ambient `DefaultTextStyle` (onSurface) unless the call
  /// site passes one. Falls back to the unthemed roles rather than throwing.
  AppTextStyles get appText =>
      Theme.of(this).extension<AppTextStyles>() ?? AppTypography.roles;
}

extension TabularFiguresStyle on TextStyle {
  /// This style with tabular digits (UX-049) — for a role that is usually
  /// proportional but shows a changing number at this call site.
  TextStyle get tabular => copyWith(fontFeatures: kTabularFigures);
}
