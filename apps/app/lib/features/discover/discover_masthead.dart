import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// The top of Discover: a printed masthead, not a hero.
///
/// `/chefs` opens with a dark brand gradient. Doing that twice would make the
/// two pages the same page with different words in it — and a gradient block is
/// the wrong instrument here anyway: the chefs hero *states figures* (five tier
/// counts, a population, a ranking rule), where this has one number and a
/// search field. So this is set like the top of a page in a cookbook: a rule, a
/// kicker in spaced caps, the title, one line of copy, and the search field
/// sitting on the same baseline as the title once there is room for it.
///
/// It scrolls with the page. Nothing here is fixed-height, so the B037 trap
/// (a header taller than the viewport starving everything under it) cannot
/// apply — at 2.0× text scale this simply becomes a taller masthead.
class DiscoverMasthead extends StatelessWidget {
  const DiscoverMasthead({super.key, required this.search, this.publicCount});

  /// The search field. Supplied by the screen, which owns the controller.
  final Widget search;

  /// Public recipes in the vault, or null while the count is in flight.
  final int? publicCount;

  /// Widest the search field is allowed to get beside the title. Past this it
  /// stops looking like a field and starts looking like a second column.
  static const double _searchMaxWidth = 380;

  /// Below this the title and the search field stack.
  static const double _rowWidth = 720;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return LayoutBuilder(
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
              // TODO(fonts): the drafts set this in Newsreader; a font change
              // is app-wide, not a Discover change (Phase 23, D7).
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w600,
                height: 1,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Text(
                'Three shelves for three kinds of hunger — then everything '
                'else the vault has made public.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.4,
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
            const SizedBox(height: AppSpacing.md),
            if (row)
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // One flex child only: the title block takes what is left
                  // after a field that never exceeds its cap. Two flex children
                  // would split the row 50/50 whatever the content says (B038).
                  Expanded(child: title),
                  const SizedBox(width: AppSpacing.xl),
                  // A hard width, not a `ConstrainedBox`: a non-flex child of a
                  // Row is laid out against an *unbounded* main axis (B039),
                  // and `SearchBar` has no width of its own to fall back on.
                  SizedBox(width: _searchMaxWidth, child: search),
                ],
              )
            else ...[
              title,
              const SizedBox(height: AppSpacing.md),
              search,
            ],
            const SizedBox(height: AppSpacing.lg),
            // The rule that closes the masthead: a short accent stroke running
            // into a hairline. The hairline is the flex child for the same
            // reason it is in a shelf header — it is the part with no minimum.
            Row(
              children: [
                Container(
                  width: 56,
                  height: 3,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Expanded(
                  child: Container(height: 1, color: scheme.outlineVariant),
                ),
              ],
            ),
          ],
        );
      },
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final style = theme.textTheme.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
      letterSpacing: 1.8,
      fontWeight: FontWeight.w700,
    );

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
            Container(width: 7, height: 7, color: scheme.primary),
            const SizedBox(width: AppSpacing.sm),
            label('THE PASS', TextAlign.left, 0.3),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: Container(height: 1, color: scheme.outlineVariant)),
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
