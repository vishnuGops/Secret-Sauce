import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// WCAG 2.2 AA for every foreground/background role pair the product draws,
/// in light **and** dark (Phase 36b, B133). 4.5:1 for text, 3:1 for a UI
/// graphic (a star, an outline that identifies a control).
///
/// A failure here means a token moved below the floor — fix the token, not the
/// threshold. Pairs deliberately left out, and why:
///  - `outlineVariant` — card borders and dividers. Separation, not
///    identification: every bordered surface is also a tonal step or holds
///    content that identifies it (1.4.11 does not apply).
///  - `imageOutline`, `floatingShadow`, `heroShadow`, `foilShade`,
///    `foilHighlight`, `coverScrim` — decoration; nothing is read off them.
///  - Anything over a photograph other than the scrim, which is measured
///    against the worst case (a pure-white plate).
void main() {
  double contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  /// [fg] at [alpha] composited over [bg] — how a tint actually renders.
  Color over(Color fg, double alpha, Color bg) =>
      Color.alphaBlend(fg.withValues(alpha: alpha), bg);

  const text = 4.5;
  const ui = 3.0;
  const white = Color(0xFFFFFFFF);

  for (final brightness in Brightness.values) {
    final theme =
        brightness == Brightness.light ? AppTheme.light() : AppTheme.dark();
    final s = theme.colorScheme;
    final p = theme.extension<AppPalette>()!;
    final name = brightness.name;

    // The surfaces text actually sits on: the page; an M3 `Card`, whose
    // default fill is `surfaceContainerLow` (the theme sets no card colour);
    // the lowest container (sheets, the spotlight panel); and the highest
    // (inputs, chips, the cook-mode timer track). The first three are where
    // badges and chips sit.
    final surfaces = <String, Color>{
      'surface': s.surface,
      'surfaceContainerLow (Card)': s.surfaceContainerLow,
      'surfaceContainerLowest': s.surfaceContainerLowest,
      'surfaceWarm (hero band)': p.surfaceWarm,
      'surfaceContainerHighest': s.surfaceContainerHighest,
    };
    final badgeSurfaces = surfaces.entries.take(4);

    void expectPair(String label, Color fg, Color bg, double min) {
      test('$name · $label ≥ $min:1', () {
        final ratio = contrast(fg, bg);
        expect(
          ratio,
          greaterThanOrEqualTo(min),
          reason: '$label measured ${ratio.toStringAsFixed(2)}:1',
        );
      });
    }

    group('scheme roles', () {
      for (final e in surfaces.entries) {
        expectPair('onSurface on ${e.key}', s.onSurface, e.value, text);
        expectPair(
          'onSurfaceVariant on ${e.key}',
          s.onSurfaceVariant,
          e.value,
          text,
        );
        // Links, selected tabs and sort labels are primary-coloured text;
        // kickers, step numbers and nutrition figures are tertiary (36c).
        expectPair('primary on ${e.key}', s.primary, e.value, text);
        expectPair('tertiary on ${e.key}', s.tertiary, e.value, text);
        expectPair('secondary on ${e.key}', s.secondary, e.value, text);
        expectPair('outline on ${e.key}', s.outline, e.value, ui);
      }
      expectPair('onPrimary on primary', s.onPrimary, s.primary, text);
      expectPair(
        'onPrimaryContainer on primaryContainer',
        s.onPrimaryContainer,
        s.primaryContainer,
        text,
      );
      expectPair(
        'onSecondaryContainer on secondaryContainer',
        s.onSecondaryContainer,
        s.secondaryContainer,
        text,
      );
      expectPair(
        'onTertiaryContainer on tertiaryContainer',
        s.onTertiaryContainer,
        s.tertiaryContainer,
        text,
      );
      expectPair('onError on error', s.onError, s.error, text);
      expectPair(
        'onErrorContainer on errorContainer',
        s.onErrorContainer,
        s.errorContainer,
        text,
      );
      expectPair('error on surface', s.error, s.surface, text);
      // Snackbars: message and action.
      expectPair(
        'onInverseSurface on inverseSurface',
        s.onInverseSurface,
        s.inverseSurface,
        text,
      );
      expectPair(
        'inversePrimary on inverseSurface',
        s.inversePrimary,
        s.inverseSurface,
        text,
      );
    });

    group('AppPalette', () {
      // UX-011: stars are UI graphics that carry the value.
      for (final e in badgeSurfaces) {
        expectPair('rating on ${e.key}', p.rating, e.value, ui);
      }

      // UX-010: the badge's 11px word on its own wash, on a page and a card.
      for (final d in Difficulty.values) {
        final fg = p.difficulty(d);
        for (final e in badgeSurfaces) {
          expectPair(
            'difficulty ${d.name} on its wash over ${e.key}',
            fg,
            over(fg, AppAlpha.badge, e.value),
            text,
          );
        }
      }

      // The tier chip's 11px label on its wash, on a page and a card.
      for (final t in ChefTier.values) {
        final fg = p.tier(t);
        for (final e in badgeSurfaces) {
          expectPair(
            'tier ${t.name} on its wash over ${e.key}',
            fg,
            over(fg, AppAlpha.tint, e.value),
            text,
          );
        }
      }

      // Category blocks (the tiles and the no-photo cover) and the rank
      // ribbon carry large and small text in their own ink.
      for (final c in [
        'Main',
        'Breakfast',
        'Dessert',
        'Appetizer',
        'Salad',
        'Drink',
      ]) {
        final block = p.category(c);
        expectPair(
          'ink on the $c block',
          block.foreground,
          block.background,
          text,
        );
      }
      expectPair(
        'onRankRibbon on rankRibbon',
        p.onRankRibbon,
        p.rankRibbon,
        text,
      );
      expectPair(
        'onTertiaryContainer on tertiaryContainer (tag pill)',
        s.onTertiaryContainer,
        s.tertiaryContainer,
        text,
      );

      // Text on a photo: the scrim over the worst case, a white plate.
      expectPair(
        'onImage on scrim over white',
        p.onImage,
        Color.alphaBlend(p.scrim, white),
        text,
      );
      expectPair(
        'onImage glyph on imageControl over white',
        p.onImage,
        Color.alphaBlend(p.imageControl, white),
        ui,
      );

      // The always-dark chefs hero: every stop of the gradient, and the
      // translucent fill of the pills and the Master Chef tile at its light end.
      for (final stop in [p.heroStart, p.heroMid, p.heroEnd]) {
        expectPair('onHero on hero ${_hex(stop)}', p.onHero, stop, text);
        expectPair(
          'onHeroMuted on hero ${_hex(stop)}',
          Color.alphaBlend(p.onHeroMuted, stop),
          stop,
          text,
        );
      }
      final fillAtEnd = Color.alphaBlend(p.heroFill, p.heroEnd);
      expectPair(
        'onHeroMuted on heroFill at the gradient end',
        Color.alphaBlend(p.onHeroMuted, fillAtEnd),
        fillAtEnd,
        text,
      );
      expectPair(
        'heroSelectedInk on the selected segment',
        p.heroSelectedInk,
        p.onHero,
        text,
      );
    });

    // UX-012: the spotlight card's RANK pill is near-white in both themes, so
    // its tier text resolves at light brightness. It sits on the cover scrim
    // over a photo; the worst backdrop is a black plate under the scrim.
    group('rank pill', () {
      const black = Color(0xFF000000);
      final pill = over(
        white,
        AppAlpha.frosted,
        Color.alphaBlend(p.scrim, black),
      );
      for (final t in ChefTier.values) {
        expectPair(
          'light tier ${t.name} on the rank pill',
          AppPalette.light.tier(t),
          pill,
          text,
        );
      }
    });
  }
}

String _hex(Color c) =>
    '#${c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';
