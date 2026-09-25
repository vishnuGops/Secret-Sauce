import 'package:flutter/material.dart';

/// Responsive breakpoints and helpers used to adapt the UI between mobile,
/// tablet, and desktop/web layouts from a single codebase.
class Breakpoints {
  Breakpoints._();
  static const double compact = 600; // phones
  static const double medium = 1000; // tablets / small web
}

enum ScreenSize { compact, medium, expanded }

extension ScreenSizeContext on BuildContext {
  ScreenSize get screenSize {
    final width = MediaQuery.sizeOf(this).width;
    if (width < Breakpoints.compact) return ScreenSize.compact;
    if (width < Breakpoints.medium) return ScreenSize.medium;
    return ScreenSize.expanded;
  }

  bool get isCompact => screenSize == ScreenSize.compact;
  bool get isExpanded => screenSize == ScreenSize.expanded;

  /// The ambient text scale as a plain multiplier — 1.0 normally, 2.0 at the
  /// accessibility envelope the card tests use.
  ///
  /// Derived by scaling a real font size rather than read off the `TextScaler`
  /// directly: scaling is non-linear above 1.0 on some platforms, so this
  /// measures what a widget's text will actually get. Layouts that must reserve
  /// height for text — a fixed-size tile, a row of columns that cannot scroll —
  /// size themselves from this.
  double get textScale => MediaQuery.textScalerOf(this).scale(14) / 14;
}

/// Renders different widgets depending on available width. Any of [medium] or
/// [expanded] falls back to [compact] when not provided.
class AdaptiveLayout extends StatelessWidget {
  const AdaptiveLayout({
    super.key,
    required this.compact,
    this.medium,
    this.expanded,
  });

  final WidgetBuilder compact;
  final WidgetBuilder? medium;
  final WidgetBuilder? expanded;

  @override
  Widget build(BuildContext context) {
    return switch (context.screenSize) {
      ScreenSize.expanded => (expanded ?? medium ?? compact)(context),
      ScreenSize.medium => (medium ?? compact)(context),
      ScreenSize.compact => compact(context),
    };
  }
}

/// How many tiles of a bounded width fit across [available], and how wide each
/// one ends up.
///
/// This is the "wrap to the next line" rule for a grid whose tiles have both a
/// minimum and a maximum width: fit as many columns as can each hold
/// `minTileWidth`, then share the width between them — but never stretch a tile
/// past `maxTileWidth`. Whatever is left over becomes [gutter] on each side, so
/// a capped row stays centred instead of drifting to one edge.
///
/// It is a pure function of the available width, so a resize just recomputes it
/// — there is no breakpoint to cross and nothing to animate.
@immutable
class FlowGridMetrics {
  const FlowGridMetrics({
    required this.columns,
    required this.tileWidth,
    required this.gutter,
    this.trailing = 0,
  });

  /// Fits [minTileWidth]-wide tiles across [available], capped at
  /// [maxTileWidth].
  ///
  /// Below one minimum-width tile the single column is allowed to shrink under
  /// [minTileWidth] — a tile that refuses to get smaller than its container is
  /// an overflow, and the card is built to degrade instead.
  ///
  /// [maxColumns], when given, caps the count however wide [available] is
  /// (B049). The tiles then hit [maxTileWidth] and everything past the capped
  /// row becomes [trailing] — slack on the **end** side only, so the block
  /// stays left-aligned. Centring it would move the first card away from every
  /// header drawn above the grid at the page's own inset (Discover's
  /// masthead and shelves, the chef and entity headers), which is B059's
  /// shared left edge broken by 900px on a 4K window. Uncapped, a row this wide
  /// had no gutter at all, so left-aligned is also the continuous answer.
  /// Null keeps the uncapped behaviour.
  factory FlowGridMetrics.fit({
    required double available,
    required double minTileWidth,
    required double maxTileWidth,
    required double spacing,
    int? maxColumns,
  }) {
    assert(minTileWidth <= maxTileWidth, 'min tile width exceeds the max');
    assert(maxColumns == null || maxColumns >= 1, 'maxColumns must be >= 1');
    final width = available.isFinite && available > 0 ? available : 0.0;
    // How many (tile + spacing) slots fit, counting the last tile's missing
    // trailing spacing. At least one column, however narrow the container.
    final fits = (width + spacing) ~/ (minTileWidth + spacing);
    var columns = fits < 1 ? 1 : fits;
    final capped = maxColumns != null && columns > maxColumns;
    if (capped) columns = maxColumns;
    final shared = (width - spacing * (columns - 1)) / columns;
    final tileWidth = shared.clamp(0.0, maxTileWidth);
    final rowWidth = tileWidth * columns + spacing * (columns - 1);
    final leftover = (width - rowWidth).clamp(0.0, double.infinity);
    return FlowGridMetrics(
      columns: columns,
      tileWidth: tileWidth,
      gutter: capped ? 0 : leftover / 2,
      trailing: capped ? leftover : 0,
    );
  }

  /// Number of tiles per row.
  final int columns;

  /// Width each tile is laid out at — never more than `maxTileWidth`.
  final double tileWidth;

  /// Leftover space to inset on **each** side so the row stays centred. Zero
  /// unless the tiles hit their maximum width, and zero when the column cap
  /// applied (see [trailing]).
  final double gutter;

  /// Leftover space to inset on the **end** side only — what a column cap
  /// leaves past the capped row. Zero unless `maxColumns` bound the count.
  final double trailing;
}
