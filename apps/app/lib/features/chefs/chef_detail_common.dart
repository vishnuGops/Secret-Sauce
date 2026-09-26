import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// The small pieces the chefs feature shares between the board and `/chef/:id`:
/// the all-caps section kicker, the muted note an empty or failed section falls
/// back to (OPT-A8), and the segmented pill both pages switch a ranking with.

class ChefKicker extends StatelessWidget {
  const ChefKicker({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Counts land in here (`14 public recipes`), so the digits stay tabular.
    // A heading to assistive tech (UX-014): every use opens a section —
    // `Why this score`, `Tier ladder`, the catalogue count, the momentum span —
    // and heading navigation is how a screen reader skims a long page.
    return Semantics(
      container: true,
      header: true,
      child: Text(
        text.toUpperCase(),
        style: context.appText.overline.tabular.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class ChefNote extends StatelessWidget {
  const ChefNote({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// The segmented pill that switches a ranking: the board's Score / Momentum /
/// New, and `/chef/:id`'s All / Popular / Trending (Phase 31).
///
/// Since Phase 37 (UX-032) this is the design system's [SegmentedTabs] in its
/// `expand` mode, under the name both pages already call — the 48px hit layer
/// (UX-048), the per-segment `selected` semantics (UX-014) and the one-weight
/// labels (UX-049) this widget grew now live there, shared with the chefs
/// hero's window filter, Discover's sort and the recipe rail's tabs. Generic
/// over the enum because the two pages switch different things but must not
/// look like two different controls. Since Phase 33 every option on both pages
/// is live, so neither passes [enabledOf]; it stays for the next control that
/// has to ship drawn-but-not-ready.
///
/// **The segments divide the width equally,** so this must be given a bounded
/// width — a `Row` with flex children under unbounded constraints is an
/// assertion failure, not an overflow (Gotcha 21's other half). Labels degrade
/// by ellipsis rather than wrapping, so a long option costs itself letters and
/// never the pill's height.
class ChefPillTabs<T> extends StatelessWidget {
  const ChefPillTabs({
    super.key,
    required this.options,
    required this.selected,
    required this.labelOf,
    required this.onSelected,
    this.enabledOf,
    this.disabledMessage = '',
  });

  final List<T> options;
  final T selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onSelected;

  /// Null means every option is live.
  final bool Function(T)? enabledOf;

  /// Shown on hover over a disabled segment. Ignored when [enabledOf] is null.
  final String disabledMessage;

  @override
  Widget build(BuildContext context) => SegmentedTabs<T>(
    values: options,
    selected: selected,
    onSelected: onSelected,
    labelOf: labelOf,
    expand: true,
    enabledOf: enabledOf,
    disabledMessage: disabledMessage,
  );
}
