import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The theme carries everything the token layer promises (Phase 36b).
///
/// A missing `ThemeExtension` is not a compile error — `context.palette`
/// falls back quietly, and a bare `theme.extension<AppPalette>()!` is a
/// runtime crash on the first frame that reads it. Hence a test.
void main() {
  final themes = {'light': AppTheme.light(), 'dark': AppTheme.dark()};

  for (final MapEntry(key: name, value: theme) in themes.entries) {
    group(name, () {
      test('carries AppPalette for its own brightness', () {
        final palette = theme.extension<AppPalette>();
        expect(palette, isNotNull);
        expect(palette, same(AppPalette.of(theme.brightness)));
      });

      test('carries AppTextStyles', () {
        expect(theme.extension<AppTextStyles>(), isNotNull);
      });

      test('every TextTheme role is set in a bundled family', () {
        final t = theme.textTheme;
        final roles = <String, TextStyle?>{
          'displayLarge': t.displayLarge,
          'displayMedium': t.displayMedium,
          'displaySmall': t.displaySmall,
          'headlineLarge': t.headlineLarge,
          'headlineMedium': t.headlineMedium,
          'headlineSmall': t.headlineSmall,
          'titleLarge': t.titleLarge,
          'titleMedium': t.titleMedium,
          'titleSmall': t.titleSmall,
          'bodyLarge': t.bodyLarge,
          'bodyMedium': t.bodyMedium,
          'bodySmall': t.bodySmall,
          'labelLarge': t.labelLarge,
          'labelMedium': t.labelMedium,
          'labelSmall': t.labelSmall,
        };
        const serif = {
          'displayLarge',
          'displayMedium',
          'displaySmall',
          'headlineLarge',
          'headlineMedium',
          'headlineSmall',
          'titleLarge',
        };
        for (final MapEntry(key: role, value: style) in roles.entries) {
          expect(style, isNotNull, reason: role);
          expect(
            style!.fontFamily,
            serif.contains(role) ? AppFonts.displayFamily : AppFonts.uiFamily,
            reason: role,
          );
          expect(style.fontSize, isNotNull, reason: role);
          expect(style.fontWeight, isNotNull, reason: role);
          // Scheme-coloured by ThemeData's merge, not left null.
          expect(style.color, theme.colorScheme.onSurface, reason: role);
        }
      });

      test('number roles use tabular figures (UX-049)', () {
        final r = theme.extension<AppTextStyles>()!;
        for (final style in [
          r.kicker,
          r.kickerLarge,
          r.stat,
          r.statLarge,
          r.quantity,
          r.clock,
          r.clockSmall,
        ]) {
          expect(
            style.fontFeatures,
            contains(const FontFeature.tabularFigures()),
          );
        }
      });

      test('every button family shares the button corner (UX-033)', () {
        const corner = BorderRadius.all(Radius.circular(AppRadii.button));
        final styles = {
          'filled': theme.filledButtonTheme.style,
          'outlined': theme.outlinedButtonTheme.style,
          'elevated': theme.elevatedButtonTheme.style,
          'text': theme.textButtonTheme.style,
        };
        for (final MapEntry(key: family, value: style) in styles.entries) {
          final shape = style?.shape?.resolve({});
          expect(shape, isA<RoundedRectangleBorder>(), reason: family);
          expect(
            (shape! as RoundedRectangleBorder).borderRadius,
            corner,
            reason: family,
          );
        }
      });
    });
  }

  // Here the package is the root, so the manifest lists bare family names;
  // a dependent (the app) sees them as `packages/design_system/<family>`,
  // which is what AppFonts resolves to — `apps/app/test/theme_fonts_test.dart`
  // checks that half.
  testWidgets('both families are bundled and declared', (tester) async {
    final manifest = await rootBundle.loadString('FontManifest.json');
    expect(manifest, contains('"${AppFonts.ui}"'));
    expect(manifest, contains('"${AppFonts.display}"'));
  });

  group('AppMotion', () {
    Future<Duration> resolve(
      WidgetTester tester, {
      required bool reduce,
    }) async {
      late Duration out;
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(disableAnimations: reduce),
          child: Builder(
            builder: (context) {
              out = AppMotion.of(context, AppMotion.normal);
              return const SizedBox();
            },
          ),
        ),
      );
      return out;
    }

    testWidgets('passes durations through normally', (tester) async {
      expect(await resolve(tester, reduce: false), AppMotion.normal);
    });

    testWidgets('collapses to zero under reduced motion (UX-050)', (
      tester,
    ) async {
      expect(await resolve(tester, reduce: true), Duration.zero);
    });

    test('exits are shorter than enters', () {
      expect(AppMotion.exit, lessThan(AppMotion.fast));
    });
  });
}
