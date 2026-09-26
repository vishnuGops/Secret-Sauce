import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:design_system/src/theme/app_theme.dart';

/// Read-only star display. Supports half stars, e.g. `4.5`.
///
/// Pass [count] to append the number of ratings, and set [showValue] to also
/// print the numeric average.
class StarRating extends StatelessWidget {
  const StarRating({
    super.key,
    required this.rating,
    this.size = AppIconSize.sm,
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
                  // UX-046: `1 rating`, not `1 ratings`.
                  '${count == null ? '' : ', ${countOf(count!, 'ratings')}'}',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 5; i++)
            Icon(
              iconFor(rating, i),
              size: size,
              color: unrated ? scheme.outlineVariant : context.palette.rating,
            ),
          if (showValue && !unrated) ...[
            SizedBox(width: size * 0.3),
            Text(
              rating.toStringAsFixed(1),
              style: textTheme.labelMedium?.tabular,
            ),
          ],
          if (count != null) ...[
            SizedBox(width: size * 0.25),
            Text(
              unrated ? 'No ratings' : '($count)',
              style: textTheme.labelSmall?.tabular.copyWith(
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
    this.size = defaultSize,
  });

  /// The star glyph — one px under [AppIconSize.sm], matching the recipe
  /// card's clock glyph beside it.
  static const double defaultSize = AppIconSize.xsPlus;

  final double rating;
  final int? count;
  final double size;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.star_rounded, size: size, color: context.palette.rating),
        const SizedBox(width: AppSpacing.xxs),
        // Both texts give up space when the host row is tight — callers place
        // this pill inside a Flexible. **The count yields first**, and that
        // needs the value to carry the *larger* flex, not the smaller (B080):
        // `RenderFlex` hands each flex child `freeSpace * flex / totalFlex` as
        // its maximum, so a higher factor is a bigger allowance, not an earlier
        // surrender. Written the other way round it did the exact opposite of
        // this comment — on a 288px card the value was clipped to `5…` while
        // the count `(1)` came through whole, which loses the one number the
        // pill exists to show.
        Flexible(
          flex: 2,
          child: Text(
            rating.toStringAsFixed(1),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.labelMedium?.tabular,
          ),
        ),
        if (count != null)
          Flexible(
            child: Text(
              ' ($count)',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.labelSmall?.tabular.copyWith(
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
///
/// It is also a keyboard- and screen-reader-operable slider (B126 / UX-003,
/// WCAG 2.1.1): focusable, ArrowRight/ArrowUp and ArrowLeft/ArrowDown step by
/// [kRatingStep], Home/End jump to [kMinRating]/[kMaxRating], and the
/// semantics node carries the matching increase/decrease actions. A key press
/// or an assistive-technology action is a settled gesture, so it fires
/// [onChanged] **and** [onChangeEnd].
class StarRatingInput extends StatefulWidget {
  const StarRatingInput({
    super.key,
    required this.value,
    required this.onChanged,
    this.onChangeEnd,
    this.size = defaultSize,
    this.enabled = true,
  });

  /// One star's width — a comfortable touch target per half-star.
  static const double defaultSize = 36;

  /// The keyboard focus ring's stroke. Drawn as a foreground decoration inside
  /// the stars' own box, so showing it never changes the widget's size.
  static const double focusRingWidth = AppStroke.thin;

  /// How long keyboard / assistive-technology steps must pause before they
  /// settle. Each step previews and reports [onChanged] at once, but
  /// [onChangeEnd] — where callers persist — waits for the reader to stop:
  /// four arrow presses from 3.0 are one save of 5.0, not four racing upserts
  /// that may land in any order (Phase 37 review). Behaviour, not motion, so
  /// it is not an `AppMotion` duration.
  static const Duration settleDelay = Duration(milliseconds: 400);

  /// Current rating, or null when the user has not rated yet.
  final double? value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
  final double size;
  final bool enabled;

  @override
  State<StarRatingInput> createState() => _StarRatingInputState();
}

/// Move the rating one [kRatingStep] up (`direction > 0`) or down.
class _RatingStepIntent extends Intent {
  const _RatingStepIntent(this.direction);
  final int direction;
}

/// Jump straight to [target] — Home / End.
class _RatingJumpIntent extends Intent {
  const _RatingJumpIntent(this.target);
  final double target;
}

class _StarRatingInputState extends State<StarRatingInput> {
  double? _preview;
  bool _focusHighlight = false;

  static const Map<ShortcutActivator, Intent> _shortcuts = {
    SingleActivator(LogicalKeyboardKey.arrowRight): _RatingStepIntent(1),
    SingleActivator(LogicalKeyboardKey.arrowUp): _RatingStepIntent(1),
    SingleActivator(LogicalKeyboardKey.arrowLeft): _RatingStepIntent(-1),
    SingleActivator(LogicalKeyboardKey.arrowDown): _RatingStepIntent(-1),
    SingleActivator(LogicalKeyboardKey.home): _RatingJumpIntent(kMinRating),
    SingleActivator(LogicalKeyboardKey.end): _RatingJumpIntent(kMaxRating),
  };

  late final Map<Type, Action<Intent>> _actions = {
    _RatingStepIntent: CallbackAction<_RatingStepIntent>(
      onInvoke: (intent) {
        final next = _stepped(intent.direction);
        if (next != null) _commit(next);
        return null;
      },
    ),
    _RatingJumpIntent: CallbackAction<_RatingJumpIntent>(
      onInvoke: (intent) {
        if (intent.target != _current) _commit(intent.target);
        return null;
      },
    ),
  };

  /// What the stars show right now: an in-flight preview, else the owner's.
  double? get _current => _preview ?? widget.value;

  /// The rating one step in [direction] from [_current], or null when there is
  /// nowhere to go — decreasing at (or below) the minimum, increasing at the
  /// maximum. Increasing from unrated lands on [kMinRating].
  double? _stepped(int direction) {
    final current = _current;
    if (current == null || current < kMinRating) {
      return direction > 0 ? kMinRating : null;
    }
    final next = snapRating(current + direction * kRatingStep);
    return next == current ? null : next;
  }

  /// Pending settle for a run of keyboard / semantics steps.
  Timer? _keySettle;

  /// A keyboard or assistive-technology step: preview and report it now, and
  /// settle the run once the steps pause ([StarRatingInput.settleDelay]).
  void _commit(double value) {
    setState(() => _preview = value);
    widget.onChanged(value);
    _keySettle?.cancel();
    _keySettle = Timer(StarRatingInput.settleDelay, () {
      if (mounted) widget.onChangeEnd?.call(value);
    });
  }

  @override
  void dispose() {
    // A run abandoned by leaving the page is dropped rather than saved from a
    // dead widget — the same as a drag the scroll view took over (B017).
    _keySettle?.cancel();
    super.dispose();
  }

  static String _describe(double value) =>
      value == 0 ? 'Not rated' : '${value.toStringAsFixed(1)} stars';

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
    // the widget follows [value] again. Not while a keyboard run is still
    // settling: the stars would jump back under the reader's arrow keys.
    if (oldWidget.value != widget.value && !(_keySettle?.isActive ?? false)) {
      _preview = null;
    }
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
                      ? context.palette.rating
                      : (widget.enabled
                          ? scheme.outline
                          : scheme.outlineVariant),
            ),
        ],
      ),
    );

    // 0.6: a disabled control's fade, not an AppAlpha tint of a colour. No
    // focus, no semantics actions — there is nothing to operate.
    if (!widget.enabled) return Opacity(opacity: 0.6, child: stars);

    final up = _stepped(1);
    final down = _stepped(-1);

    return Semantics(
      container: true,
      label: 'Rate this recipe',
      value: _describe(shown),
      increasedValue: up == null ? null : _describe(up),
      decreasedValue: down == null ? null : _describe(down),
      onIncrease: up == null ? null : () => _commit(up),
      onDecrease: down == null ? null : () => _commit(down),
      slider: true,
      child: FocusableActionDetector(
        enabled: widget.enabled,
        shortcuts: _shortcuts,
        actions: _actions,
        mouseCursor: SystemMouseCursors.click,
        onShowFocusHighlight: (show) {
          if (show != _focusHighlight) setState(() => _focusHighlight = show);
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _update(d.localPosition.dx),
          onTapUp: (_) => _settle(),
          onTapCancel: _cancel,
          onHorizontalDragUpdate: (d) => _update(d.localPosition.dx),
          onHorizontalDragEnd: (_) => _settle(),
          onHorizontalDragCancel: _cancel,
          // 48dp target (UX-048): the row is one star tall — 40px on the
          // cook-mode finish screen, 36 by default. The box grows the area
          // that answers taps and drags; the stars and their ring keep their
          // size, centred in it, and the width (so each half-star's dx) is
          // unchanged.
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: kMinInteractiveDimension,
            ),
            child: Align(
              widthFactor: 1,
              heightFactor: 1,
              // Foreground, inside the box: the ring never moves or resizes
              // the stars (UX-003's visible focus indicator, WCAG 2.4.7).
              child: DecoratedBox(
                position: DecorationPosition.foreground,
                decoration:
                    _focusHighlight
                        ? BoxDecoration(
                          border: Border.all(
                            color: scheme.primary,
                            width: StarRatingInput.focusRingWidth,
                          ),
                          borderRadius: BorderRadius.circular(AppRadii.md),
                        )
                        : const BoxDecoration(),
                child: stars,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
