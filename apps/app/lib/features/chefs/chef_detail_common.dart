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
/// Generic over the enum because the two pages switch different things but must
/// not look like two different controls — the board's pill was here first, and a
/// hand-copied second one is how two surfaces in one feature drift apart. Since
/// Phase 33 every option on both pages is live, so neither passes [enabledOf];
/// it stays for the next control that has to ship drawn-but-not-ready.
///
/// **Every segment is `Expanded` inside a `Row`,** so this must be given a
/// bounded width — a `Row` with flex children under unbounded constraints is an
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

  /// The height a segment answers taps over (UX-048): Material's 48px
  /// minimum. The painted pill is ~30px and stays that way — the difference is
  /// a transparent margin above and below it that still selects the segment
  /// under the pointer, the way `MaterialTapTargetSize.padded` pads a button
  /// without drawing it bigger.
  static const double minHitHeight = kMinInteractiveDimension;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    const track = AppInsets.segmentTrack;

    // Two layers over one geometry. The hit layer is full height, one opaque
    // target per segment, and the only thing assistive tech sees — each option
    // is a 48px `button` node that says whether it is `selected` (UX-014). The
    // painted layer on top is the pill as it always looked; its InkWells still
    // take a tap that lands on the paint (a Stack hit tests top-down and stops
    // at the first hit), and its semantics are excluded so no option is
    // announced twice.
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: minHitHeight),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: Padding(
              // The track's inset, so a hit column lines up with the segment
              // painted above it rather than drifting by the track padding.
              padding: EdgeInsets.only(left: track.left, right: track.right),
              child: Row(
                children: [
                  for (final option in options)
                    Expanded(child: _hitTarget(option)),
                ],
              ),
            ),
          ),
          ExcludeSemantics(child: _painted(theme, scheme)),
        ],
      ),
    );
  }

  Widget _hitTarget(T option) {
    final enabled = enabledOf?.call(option) ?? true;
    final VoidCallback? onTap = enabled ? () => onSelected(option) : null;
    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      selected: option == selected,
      label: labelOf(option),
      onTap: onTap,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          // The Semantics above carries the action; a second one here would be
          // a duplicate tap target in the tree.
          excludeFromSemantics: true,
          onTap: onTap,
        ),
      ),
    );
  }

  Widget _painted(ThemeData theme, ColorScheme scheme) {
    return Container(
      padding: AppInsets.segmentTrack,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Row(
        children: [
          for (final option in options)
            Builder(
              builder: (context) {
                final enabled = enabledOf?.call(option) ?? true;
                final isSelected = option == selected;
                return Expanded(
                  child: notYetTooltip(
                    enabled: enabled,
                    message: disabledMessage,
                    child: InkWell(
                      onTap: enabled ? () => onSelected(option) : null,
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                      child: Container(
                        alignment: Alignment.center,
                        // The segment's vertical inset only: each segment is
                        // `Expanded`, so its width is the flex share, and a
                        // horizontal inset would ellipsise labels sooner.
                        padding: AppInsets.segment.copyWith(left: 0, right: 0),
                        decoration: BoxDecoration(
                          color:
                              isSelected ? scheme.surfaceContainerLowest : null,
                          borderRadius: BorderRadius.circular(AppRadii.pill),
                        ),
                        // One weight for both states (UX-049): a heavier
                        // selected label widened itself and shifted its
                        // neighbours. The fill and the colour carry selection.
                        child: Text(
                          labelOf(option),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color:
                                isSelected
                                    ? scheme.onSurface
                                    : scheme.onSurfaceVariant.withValues(
                                      alpha: enabled ? 1 : AppAlpha.muted,
                                    ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
