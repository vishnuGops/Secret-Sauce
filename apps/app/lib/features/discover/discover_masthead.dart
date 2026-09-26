import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// A one-pixel rule — the hairline in the kicker.
const double _kHairline = 1;

/// The square printer's mark that opens the kicker.
const double _kMarkSize = 7;

/// The top of Discover: reference 2's cream hero band (Phase 36c).
///
/// A full-bleed [AppPalette.surfaceWarm] band — the one warm surface on an
/// otherwise white page — holding the kicker line, a large bold headline, one
/// line of copy and the search field as a pill. The reference also bleeds a
/// food photograph off the band's right edge; that is **deliberately absent**:
/// no curated recipe has a cover (REBUILD-LOG seed-data fit) and the rights
/// position rules out stock or hotlinked imagery, so the band is type alone
/// until a featured recipe with a real photo exists.
///
/// `/chefs` opens with a dark brand gradient; this stays light and editorial so
/// the two front pages do not read as one page with different words in it.
///
/// It scrolls with the page. Nothing here is fixed-height, so the B037 trap
/// (a header taller than the viewport starving everything under it) cannot
/// apply — at 2.0× text scale this simply becomes a taller band.
class DiscoverMasthead extends StatelessWidget {
  const DiscoverMasthead({
    super.key,
    required this.search,
    this.publicCount,
    this.gutter = AppSpacing.md,
  });

  /// The search field. Supplied by the screen, which owns the controller.
  final Widget search;

  /// Public recipes in the vault, or null while the count is in flight.
  final int? publicCount;

  /// The page's horizontal margin. The band itself runs edge to edge; its
  /// content keeps the same left edge as the tiles and shelves below it.
  final double gutter;

  /// Widest the search field is allowed to get beside the title. Past this it
  /// stops looking like a field and starts looking like a second column.
  static const double _searchMaxWidth = 380;

  /// Below this the title and the search field stack.
  static const double _rowWidth = 720;

  /// Measure of the one line of copy under the title.
  static const double _copyMaxWidth = 460;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final palette = context.palette;
    // Reference 2's headline is the largest type on the page; a phone gets
    // the next role down so `Discover` still sets on one line at 2.0×.
    final headline =
        context.isExpanded
            ? theme.textTheme.displaySmall
            : theme.textTheme.headlineMedium;

    return ColoredBox(
      color: palette.surfaceWarm,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          gutter,
          AppSpacing.lg,
          gutter,
          AppSpacing.xl,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final row = constraints.maxWidth >= _rowWidth * context.textScale;

            final title = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Discover',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: headline?.copyWith(color: scheme.secondary, height: 1),
                ),
                const SizedBox(height: AppSpacing.sm),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _copyMaxWidth),
                  child: Text(
                    'Three shelves for three kinds of hunger — then everything '
                    'else the vault has made public.',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            );

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                _Kicker(publicCount: publicCount),
                const SizedBox(height: AppSpacing.lg),
                if (row)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // One flex child only: the title block takes what is
                      // left after a field that never exceeds its cap. Two
                      // flex children would split the row 50/50 whatever the
                      // content says (B038).
                      Expanded(child: title),
                      const SizedBox(width: AppSpacing.xl),
                      // A hard width, not a `ConstrainedBox`: a non-flex child
                      // of a Row is laid out against an *unbounded* main axis
                      // (B039), and `SearchBar` has no width of its own to
                      // fall back on.
                      SizedBox(width: _searchMaxWidth, child: search),
                    ],
                  )
                else ...[
                  title,
                  const SizedBox(height: AppSpacing.lg),
                  search,
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The search field as reference 2's pill: fully rounded, the lowest surface
/// (white) on the cream band, a hairline so white-on-cream still has an edge.
///
/// Style only — the controller, the callbacks and the trailing clear button
/// are the screen's, passed straight through, so the debounce and the provider
/// wiring behind the field are untouched by the restyle.
class DiscoverSearchField extends StatelessWidget {
  const DiscoverSearchField({
    super.key,
    required this.controller,
    required this.onChanged,
    this.trailing = const [],
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final List<Widget> trailing;

  /// The pill's height floor: `SearchBar`'s own 56, above the 48dp target.
  static const double _minHeight = 56;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SearchBar(
      controller: controller,
      hintText: 'Search recipes, ingredients, tags…',
      leading: Icon(Icons.search, color: scheme.onSurfaceVariant),
      trailing: trailing,
      onChanged: onChanged,
      constraints: const BoxConstraints(minHeight: _minHeight),
      elevation: const WidgetStatePropertyAll(0),
      backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainerLowest),
      shape: const WidgetStatePropertyAll(StadiumBorder()),
      side: WidgetStateProperty.resolveWith(
        (states) => BorderSide(
          color:
              states.contains(WidgetState.focused)
                  ? scheme.primary
                  : scheme.outlineVariant,
        ),
      ),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: AppSpacing.md),
      ),
    );
  }
}

/// `▪ THE PASS ──────── 1,684 PUBLIC RECIPES`.
///
/// "The pass" is the counter a kitchen sends finished plates out over, which is
/// what this page is: everything the vault has decided to make public. It is
/// also the one piece of copy here that could not have been written about any
/// other product's browse screen.
class _Kicker extends StatelessWidget {
  const _Kicker({required this.publicCount});

  final int? publicCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // The index line in the accent (reference 5's coloured kickers, 36c).
    final style = context.appText.kicker.copyWith(color: scheme.tertiary);

    // The rule is the only flex child. Three flex children — which is what a
    // `Flexible` label either side of it would be — divide the free space by
    // flex factor rather than by need (B038): each label would be handed a
    // third whether or not it wanted one, and the rule would stop short of the
    // count with a gap after it. So both labels are intrinsic, capped against
    // the row so a large text scale ellipsizes them instead of overflowing.
    return LayoutBuilder(
      builder: (context, constraints) {
        Widget label(String text, TextAlign align, double share) =>
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: constraints.maxWidth * share,
              ),
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: align,
                style: style,
              ),
            );

        return Row(
          children: [
            Container(
              width: _kMarkSize,
              height: _kMarkSize,
              color: scheme.primary,
            ),
            const SizedBox(width: AppSpacing.sm),
            label('THE PASS', TextAlign.left, 0.3),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Container(
                height: _kHairline,
                color: scheme.outlineVariant,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            label(
              // A dash, not a hidden line, until the count lands: the row keeps
              // its shape and the masthead does not jump when it arrives.
              publicCount == null
                  ? '— PUBLIC RECIPES'
                  : '${groupedCount(publicCount!)} '
                      '${pluralNoun(publicCount!, 'PUBLIC RECIPES')}',
              TextAlign.right,
              0.45,
            ),
          ],
        );
      },
    );
  }
}
