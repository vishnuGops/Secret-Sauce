import 'package:core/core.dart';
import 'package:flutter/material.dart';

import 'package:design_system/src/theme/app_theme.dart';

/// Read-only star display. Supports half stars, e.g. `4.5`.
///
/// Pass [count] to append the number of ratings, and set [showValue] to also
/// print the numeric average.
class StarRating extends StatelessWidget {
  const StarRating({
    super.key,
    required this.rating,
    this.size = 16,
    this.count,
    this.showValue = true,
  });

  final double rating;
  final double size;
  final int? count;
  final bool showValue;

  static IconData iconFor(double rating, int index) {
    final value = rating - index;
    if (value >= 0.75) return Icons.star_rounded;
    if (value >= 0.25) return Icons.star_half_rounded;
    return Icons.star_outline_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final unrated = (count ?? 0) == 0 && rating <= 0;

    return Semantics(
      label:
          unrated
              ? 'Not rated yet'
              : '${rating.toStringAsFixed(1)} out of 5 stars'
                  '${count == null ? '' : ', $count ratings'}',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 5; i++)
            Icon(
              iconFor(rating, i),
              size: size,
              color: unrated ? scheme.outlineVariant : AppTheme.rating,
            ),
          if (showValue && !unrated) ...[
            SizedBox(width: size * 0.3),
            Text(rating.toStringAsFixed(1), style: textTheme.labelMedium),
          ],
          if (count != null) ...[
            SizedBox(width: size * 0.25),
            Text(
              unrated ? 'No ratings' : '($count)',
              style: textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Compact single-star + value chip for dense surfaces such as `RecipeCard`.
class RatingPill extends StatelessWidget {
  const RatingPill({
    super.key,
    required this.rating,
    this.count,
    this.size = 15,
  });

  final double rating;
  final int? count;
  final double size;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.star_rounded, size: size, color: AppTheme.rating),
        const SizedBox(width: 2),
        // Both texts give up space when the host row is tight — callers place
        // this pill inside a Flexible. The count yields first (flex 2 vs 1).
        Flexible(
          child: Text(
            rating.toStringAsFixed(1),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.labelMedium,
          ),
        ),
        if (count != null)
          Flexible(
            flex: 2,
            child: Text(
              ' ($count)',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

/// Interactive star input in half-star steps (0.5 … 5.0).
///
/// Tapping the left half of a star selects `n - 0.5`, the right half selects
/// `n`. Dragging across the row previews continuously; [onChangeEnd] fires
/// once the gesture settles, so callers can persist there instead of on every
/// intermediate value.
class StarRatingInput extends StatefulWidget {
  const StarRatingInput({
    super.key,
    required this.value,
    required this.onChanged,
    this.onChangeEnd,
    this.size = 36,
    this.enabled = true,
  });

  /// Current rating, or null when the user has not rated yet.
  final double? value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
  final double size;
  final bool enabled;

  @override
  State<StarRatingInput> createState() => _StarRatingInputState();
}

class _StarRatingInputState extends State<StarRatingInput> {
  double? _preview;

  /// Left half of star `n` → `n - 0.5`, right half → `n`.
  double _ratingAt(double dx) {
    final halves = (dx / widget.size * 2).ceil();
    return (halves * kRatingStep).clamp(kMinRating, kMaxRating).toDouble();
  }

  void _update(double dx) {
    final value = _ratingAt(dx);
    if (value == _preview) return;
    setState(() => _preview = value);
    widget.onChanged(value);
  }

  void _settle() {
    final value = _preview;
    if (value != null) widget.onChangeEnd?.call(value);
  }

  /// The gesture was taken over by an ancestor (typically a scroll view after
  /// press-then-scroll). `onChangeEnd` never fires, so the preview must be
  /// dropped — otherwise the stars keep showing a rating that was never saved,
  /// and `didUpdateWidget` cannot clear it because [widget.value] never changed.
  void _cancel() {
    if (_preview == null) return;
    setState(() => _preview = null);
    final restored = widget.value;
    if (restored != null) widget.onChanged(restored);
  }

  @override
  void didUpdateWidget(StarRatingInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The owner confirmed (or cleared) the rating — drop the local preview so
    // the widget follows [value] again.
    if (oldWidget.value != widget.value) _preview = null;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shown = _preview ?? widget.value ?? 0;

    final stars = SizedBox(
      width: widget.size * 5,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 5; i++)
            Icon(
              StarRating.iconFor(shown, i),
              size: widget.size,
              color:
                  shown - i >= 0.25
                      ? AppTheme.rating
                      : (widget.enabled
                          ? scheme.outline
                          : scheme.outlineVariant),
            ),
        ],
      ),
    );

    if (!widget.enabled) return Opacity(opacity: 0.6, child: stars);

    return Semantics(
      label: 'Rate this recipe',
      value: shown == 0 ? 'Not rated' : '${shown.toStringAsFixed(1)} stars',
      slider: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => _update(d.localPosition.dx),
        onTapUp: (_) => _settle(),
        onTapCancel: _cancel,
        onHorizontalDragUpdate: (d) => _update(d.localPosition.dx),
        onHorizontalDragEnd: (_) => _settle(),
        onHorizontalDragCancel: _cancel,
        child: stars,
      ),
    );
  }
}
