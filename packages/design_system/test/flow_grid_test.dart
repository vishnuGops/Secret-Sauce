import 'package:design_system/design_system.dart';
import 'package:flutter_test/flutter_test.dart';

/// The recipe grid's real parameters — card 264–340 wide, 16px gaps.
FlowGridMetrics fit(double available) => FlowGridMetrics.fit(
      available: available,
      minTileWidth: kRecipeCardMinWidth,
      maxTileWidth: kRecipeCardMaxWidth,
      spacing: AppSpacing.md,
    );

void main() {
  group('FlowGridMetrics', () {
    test('one capped column on a phone', () {
      // 390px device minus the grid's 16px padding on each side.
      final m = fit(358);
      expect(m.columns, 1);
      expect(m.tileWidth, kRecipeCardMaxWidth);
      expect(m.gutter, (358 - 340) / 2);
    });

    test('adds a column instead of stretching the cards', () {
      // 700 could stretch two cards to 342; the cap holds them at 340 and the
      // 4px left over is split into gutters.
      final two = fit(700);
      expect(two.columns, 2);
      expect(two.tileWidth, kRecipeCardMaxWidth);
      expect(two.gutter, 2);

      // 1400 fits five minimum-width cards, so it gets five — not three
      // stretched ones.
      final five = fit(1400);
      expect(five.columns, 5);
      expect(five.tileWidth, closeTo(267.2, 0.001));
      expect(five.gutter, 0);
    });

    test('a container narrower than one card gets one shrinking card', () {
      final m = fit(200);
      expect(m.columns, 1);
      expect(m.tileWidth, 200, reason: 'shrink, never overflow');
      expect(m.gutter, 0);
    });

    test('degenerate widths do not throw or produce zero columns', () {
      for (final width in <double>[0, -50, double.infinity, double.nan]) {
        final m = fit(width);
        expect(m.columns, 1, reason: 'width $width');
        expect(m.tileWidth, 0, reason: 'width $width');
        expect(m.gutter, 0, reason: 'width $width');
      }
    });

    // The resize contract: sweep every width a window can be dragged through
    // and check the invariants hold at each one. A rule that only holds at the
    // breakpoints is what makes a drag-resize jump.
    test('holds its invariants across a continuous resize', () {
      var previousColumns = 0;
      for (var width = 264.0; width <= 2400; width += 1) {
        final m = fit(width);
        final rowWidth =
            m.tileWidth * m.columns + AppSpacing.md * (m.columns - 1);

        expect(
          m.tileWidth,
          lessThanOrEqualTo(kRecipeCardMaxWidth),
          reason: 'card stretched past its max at $width',
        );
        expect(
          m.tileWidth,
          greaterThanOrEqualTo(kRecipeCardMinWidth),
          reason: 'card squeezed under its min at $width',
        );
        expect(
          rowWidth + m.gutter * 2,
          closeTo(width, 0.001),
          reason: 'row plus gutters must account for every pixel at $width',
        );
        expect(
          m.columns,
          greaterThanOrEqualTo(previousColumns),
          reason: 'columns went down as the window got wider at $width',
        );
        previousColumns = m.columns;
      }
    });

    test('packs the most columns the width can actually hold', () {
      for (var width = 264.0; width <= 2400; width += 7) {
        final m = fit(width);
        final oneMore = m.columns + 1;
        final needed =
            kRecipeCardMinWidth * oneMore + AppSpacing.md * (oneMore - 1);
        expect(
          needed,
          greaterThan(width),
          reason: 'another column would have fit at $width',
        );
      }
    });
  });
}
