import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// Width of one tile in the compact scrolling row, at 1.0× (it grows with the
/// text to 2.0×, so `Breakfast` in `titleLarge` still sets on one line).
const double _kRowTileWidth = 140;

/// Narrowest a tile may get in the wide grid, at 1.0× — the same measure as
/// the row, so a tile never reads smaller on a desktop than on a phone.
const double _kGridTileMinWidth = 140;

/// Space between two tiles, both ways.
const double _kTileGap = AppSpacing.smPlus;

/// Column counts the grid may use: divisors of the six tiles, so every row is
/// full — a 4 + 2 split leaves a ragged hole where a tile should be.
const List<int> _kGridColumns = [6, 3];

/// Discover's category tiles (Phase 36c, the owner's Q6): reference 1's colour
/// blocks, one per [DiscoverCategory], each a **filter** on the browse grid.
///
/// Stateless on purpose — the selection is URL state (`/discover?category=`),
/// owned by the router and handed down, and a tap only reports which tile was
/// pressed. Whether that selects or clears is the screen's decision.
///
/// Two layouts, one rule: a compact window scrolls a single row sideways (the
/// next tile peeking past the edge is the affordance); a wider one lays all
/// six out as full rows — six across, or three by two. When even three
/// columns cannot hold a tile at its minimum (600px at 2.0× text), the row
/// comes back rather than stacking six tiles into a column taller than the
/// screen.
class DiscoverCategoryTiles extends StatelessWidget {
  const DiscoverCategoryTiles({
    super.key,
    required this.selected,
    required this.onSelect,
  });

  /// The tile the URL names, or null.
  final DiscoverCategory? selected;

  final ValueChanged<DiscoverCategory> onSelect;

  /// Key of one tile — stable, so tests and screenshots can find it by slug.
  static Key tileKey(DiscoverCategory category) =>
      ValueKey('discover-category-${category.slug}');

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'BROWSE BY CATEGORY',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          // The index line at section level, in the accent — the same mark
          // the shelves and EVERYTHING ELSE are headed with.
          style: context.appText.kickerLarge.copyWith(color: scheme.tertiary),
        ),
        const SizedBox(height: AppSpacing.smPlus),
        LayoutBuilder(
          builder: (context, constraints) {
            final scale = context.textScale.clamp(1.0, 2.0);
            final columns =
                context.isCompact
                    ? null
                    : _columnsFor(constraints.maxWidth, scale);
            return columns == null
                ? _row(context, scale)
                : _grid(constraints.maxWidth, columns);
          },
        ),
      ],
    );
  }

  /// The most columns from [_kGridColumns] whose tiles still clear their
  /// minimum width, or null when none does.
  int? _columnsFor(double width, double scale) {
    for (final columns in _kGridColumns) {
      final tile = (width - _kTileGap * (columns - 1)) / columns;
      if (tile >= _kGridTileMinWidth * scale) return columns;
    }
    return null;
  }

  Widget _tile(DiscoverCategory category) => CategoryTile(
    key: tileKey(category),
    // The palette is keyed by raw category spellings; the first raw value is
    // the curated one, so a tile and the covers of the recipes under it share
    // a colour. The label is the tile's own plural name (`Starters` has no
    // palette key of its own).
    category: category.rawValues.first,
    label: category.label,
    selected: category == selected,
    onTap: () => onSelect(category),
  );

  Widget _row(BuildContext context, double scale) {
    final width = _kRowTileWidth * scale;
    return SizedBox(
      // The tile sizes its own height from the text scale; the viewport of a
      // horizontal list has to be told the same number up front.
      height:
          kCategoryTileHeight * context.textScale.clamp(1.0, double.infinity),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: DiscoverCategory.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: _kTileGap),
        itemBuilder:
            (context, i) => SizedBox(
              width: width,
              child: _tile(DiscoverCategory.values[i]),
            ),
      ),
    );
  }

  Widget _grid(double width, int columns) {
    // Floored so rounding can never push the last tile of a row onto a row of
    // its own — a `Wrap` breaks on a fraction of a pixel.
    final tile =
        ((width - _kTileGap * (columns - 1)) / columns).floorToDouble();
    return Wrap(
      spacing: _kTileGap,
      runSpacing: _kTileGap,
      children: [
        for (final category in DiscoverCategory.values)
          SizedBox(width: tile, child: _tile(category)),
      ],
    );
  }
}
