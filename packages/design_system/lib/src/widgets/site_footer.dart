import 'package:flutter/material.dart';

import 'package:design_system/src/layout/adaptive.dart';
import 'package:design_system/src/theme/app_theme.dart';

/// One link in a [SiteFooter].
class SiteFooterLink {
  const SiteFooterLink({
    required this.label,
    required this.onTap,
    this.isCurrent = false,
  });

  final String label;
  final VoidCallback onTap;

  /// The page the reader is already on. Rendered as plain text rather than a
  /// link, so the row does not offer a tap that goes nowhere.
  final bool isCurrent;
}

/// Above this text scale the copyright line is dropped and only the links
/// remain.
///
/// The row is a [Wrap], so it cannot overflow — what it does instead is grow
/// taller, and in the web chrome it grows into the viewport. Dropping the one
/// part a reader never needs keeps it to a single line for longer. 1.6 rather
/// than 2.0 because the copyright is the widest single item and it is the first
/// thing to cost a second row.
const double kSiteFooterCopyrightMaxScale = 1.6;

/// The legal links row (Phase 35a).
///
/// **Why this is a persistent bar on web and not a page footer.** Discover,
/// Chefs and My Recipes all page forever, so a footer appended to the end of
/// their scroll is a footer nobody can reach. The web chrome therefore carries
/// it in `Scaffold.bottomNavigationBar`, where it costs one row of height and
/// is always available. On compact that slot belongs to the `NavigationBar`, so
/// the same links appear where a phone user can actually get at them: on the
/// profile screen, under the sign-up form, and on the legal pages themselves.
///
/// It takes callbacks rather than routes because `design_system` knows nothing
/// about `go_router` — the same arrangement `ChefBadge.onTap` uses.
class SiteFooter extends StatelessWidget {
  const SiteFooter({
    super.key,
    required this.links,
    this.copyright,
    this.dense = false,
  });

  final List<SiteFooterLink> links;

  /// Optional leading text. Dropped above [kSiteFooterCopyrightMaxScale].
  final String? copyright;

  /// The web chrome form: a bordered bar with its own background and safe-area
  /// padding. `false` is the in-page form, which inherits the surface it sits
  /// on.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );

    final row = Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.xs,
      children: [
        if (copyright != null &&
            context.textScale < kSiteFooterCopyrightMaxScale)
          Text(copyright!, style: muted),
        for (final link in links)
          if (link.isCurrent)
            Text(
              link.label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            )
          else
            // A plain InkWell rather than a TextButton: three TextButtons carry
            // ~48px of built-in padding each, which is most of the height
            // budget the web bar has.
            InkWell(
              onTap: link.onTap,
              borderRadius: BorderRadius.circular(AppRadii.button),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xs,
                  vertical: AppSpacing.xs,
                ),
                child: Text(
                  link.label,
                  style: muted?.copyWith(
                    decoration: TextDecoration.underline,
                    decorationColor: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
      ],
    );

    if (!dense) return row;

    return Material(
      color: scheme.surface,
      child: SafeArea(
        top: false,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          // A BorderSide on the box that holds the content, never a sibling
          // divider above it (B060): a zero-height box in an unbounded position
          // draws nothing, and this one sits in a slot whose constraints are
          // not obvious from here.
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: scheme.outlineVariant)),
          ),
          child: row,
        ),
      ),
    );
  }
}
