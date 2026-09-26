import 'package:core/core.dart';
import 'package:flutter/material.dart';

import 'package:design_system/src/theme/app_theme.dart';

/// The one `Load more` control (UX-032) — every paged recipe grid's footer and
/// the chefs leaderboard's.
///
/// A button rather than infinite scroll by product decision: an explicit tap is
/// the only version that works identically on a phone flick and a desktop
/// scrollbar, and it never fetches a page the reader did not ask for.
///
/// While [loading] the button is disabled and a spinner takes the label's
/// place **inside the same box** — the label stays laid out, invisibly, so the
/// button is the same size in both states and nothing under it jumps. The
/// spoken label stays [label]; the in-flight state is its value, `Loading
/// more`.
///
/// A failed page is a snackbar, not an error screen: the notifiers keep the
/// rows already loaded (`PagedRecipesNotifier.loadMore`,
/// `ChefBoardNotifier.loadMore`), so the page is still usable. The message goes
/// through [friendlyError].
class LoadMoreButton extends StatelessWidget {
  const LoadMoreButton({
    super.key,
    required this.onPressed,
    required this.loading,
    this.label = 'Load more',
    this.dense = false,
  });

  /// Fetches the next page. A throw is caught and shown as a snackbar.
  final Future<void> Function() onPressed;

  /// A page is in flight: disabled, spinner in place of the label.
  final bool loading;

  final String label;

  /// The inline form — a text button with no icon, for a footer line that
  /// shares its row with a footnote (the chefs leaderboard panel). The default
  /// is the outlined button a grid's footer centres.
  final bool dense;

  /// Stroke of the in-flight spinner, at [AppIconSize.sm].
  static const double _spinnerStroke = 2;

  Future<void> _load(BuildContext context) async {
    // Captured before the await: the button may be gone when the page lands.
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await onPressed();
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final face = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Sized and coloured by the button's own icon theme.
        if (!dense) ...[
          const Icon(Icons.expand_more),
          const SizedBox(width: AppSpacing.sm),
        ],
        // Flexible, and allowed to wrap: at 288px × 2.0 the label does not fit
        // one line beside the icon, and `Load / more` beats `Load…`. Loose fit
        // in a `min` row is also safe unbounded — the dense form's position,
        // a non-flex child of the chefs panel's footer row.
        Flexible(child: Text(label, textAlign: TextAlign.center)),
      ],
    );

    final child = Semantics(
      label: label,
      value: loading ? 'Loading more' : null,
      child: ExcludeSemantics(
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Hidden, not removed: the face keeps the button's size.
            Visibility(
              visible: !loading,
              maintainSize: true,
              maintainAnimation: true,
              maintainState: true,
              child: face,
            ),
            if (loading)
              const SizedBox.square(
                dimension: AppIconSize.sm,
                child: CircularProgressIndicator(strokeWidth: _spinnerStroke),
              ),
          ],
        ),
      ),
    );

    final onTap = loading ? null : () => _load(context);
    return dense
        ? TextButton(onPressed: onTap, child: child)
        : OutlinedButton(onPressed: onTap, child: child);
  }
}
