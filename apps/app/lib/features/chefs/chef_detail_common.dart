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
    return Text(
      text.toUpperCase(),
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.8,
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(3),
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
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        decoration: BoxDecoration(
                          color:
                              isSelected ? scheme.surfaceContainerLowest : null,
                          borderRadius: BorderRadius.circular(AppRadii.pill),
                        ),
                        child: Text(
                          labelOf(option),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight:
                                isSelected ? FontWeight.w800 : FontWeight.w700,
                            color:
                                isSelected
                                    ? scheme.onSurface
                                    : scheme.onSurfaceVariant.withValues(
                                      alpha: enabled ? 1 : 0.5,
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
