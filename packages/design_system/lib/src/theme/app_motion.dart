import 'package:flutter/widgets.dart';

/// Motion tokens. Character (DESIGN.md §2.4): **quick and quiet — motion
/// confirms, it never performs.** Things arrive with a short ease-out, leave
/// faster than they came, and never bounce.
///
/// Motion must guide attention, communicate state or preserve continuity;
/// otherwise remove it. Animate opacity / transform over layout properties
/// inside grids and lists. Cook-mode timers are clock reads, not animations —
/// never route them through these tokens (32c4).
///
/// **Reduced motion wins over everything** (UX-050): read every duration
/// through [of], which collapses it to zero when the platform asks for less
/// motion (`MediaQuery.disableAnimationsOf`).
abstract final class AppMotion {
  /// Focus ring, a badge swap.
  static const Duration instant = Duration(milliseconds: 80);

  /// A check-off, an icon swap, a chip toggle.
  static const Duration fast = Duration(milliseconds: 150);

  /// Scroll-to-section, a sheet, a state change with some travel.
  static const Duration normal = Duration(milliseconds: 250);

  /// A rail paging a card's width — the longest travel in the product.
  static const Duration slow = Duration(milliseconds: 320);

  /// Exits are shorter than enters.
  static const Duration exit = Duration(milliseconds: 120);

  /// Enter / state change: decelerate into place.
  static const Curve emphasized = Curves.easeOutCubic;

  /// A plain scroll-to: gentle deceleration.
  static const Curve decelerate = Curves.easeOut;

  /// A move between two resting places.
  static const Curve standard = Curves.easeInOutCubic;

  /// Leaving.
  static const Curve exitCurve = Curves.easeInCubic;

  /// A pressed control's scale, where scale is used instead of a ripple.
  static const double pressScale = 0.97;

  /// Whether the platform has asked for reduced motion. Safe without a
  /// `MediaQuery` above (false).
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// [duration], or [Duration.zero] under reduced motion.
  static Duration of(BuildContext context, Duration duration) =>
      reduced(context) ? Duration.zero : duration;

  /// Scrolls [controller] to [offset] with [duration] and [curve] — or jumps
  /// there under reduced motion. `ScrollController.animateTo` asserts a
  /// non-zero duration, so a reduced-motion caller cannot simply pass
  /// `of(context, …)` to it.
  static Future<void> animateScroll(
    BuildContext context,
    ScrollController controller,
    double offset, {
    Duration duration = normal,
    Curve curve = emphasized,
  }) {
    if (reduced(context)) {
      controller.jumpTo(offset);
      return Future<void>.value();
    }
    return controller.animateTo(offset, duration: duration, curve: curve);
  }
}
