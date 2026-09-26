import 'package:flutter/material.dart';

import 'package:design_system/src/theme/app_theme.dart';

/// A tappable tile whose states paint **over** its content (UX-013).
///
/// `RecipeCard` and `ChefSpotlightCard` are opaque all the way down — a cover
/// photo, a colour block, a portrait — so an `InkWell` on the card's material
/// painted its focus and hover *under* them, and a keyboard user saw focus only
/// on a footer strip. This owns the tap, focus and semantics through an
/// `InkWell` with its own ink turned off, and paints the wash and the focus
/// ring in a `Stack` above the child, inside the tile's bounds, behind
/// `IgnorePointer` so a nested control (the chef badge on a cover) still takes
/// its own taps. It moved here from `recipe_card.dart` because two widgets use
/// it (Phase 37).

/// Stroke of the keyboard focus ring [InteractiveTile] draws (UX-013).
///
/// 3px, not the 2px minimum WCAG 2.4.13 asks for: the ring lies over an
/// arbitrary cover photo, and the extra pixel is what keeps it readable on a
/// busy one.
const double kTileFocusRingWidth = AppStroke.medium;

/// The hairline inside the focus ring, in the page's surface colour — the
/// second tone that keeps the ring visible on a photo the same hue as
/// `colorScheme.primary`.
const double _kFocusRingInnerWidth = AppStroke.hairline;

/// Key of [InteractiveTile]'s focus ring, for tests.
const Key kTileFocusRingKey = ValueKey('tile-focus-ring');

/// Key of [InteractiveTile]'s hover / press wash, for tests.
const Key kTileInkWashKey = ValueKey('tile-ink-wash');

/// A tile's tap target whose feedback paints **over** its content (UX-013).
///
/// An `InkWell` draws hover, press and focus on the nearest `Material`, which
/// lies *behind* the tile's children — so on a tile whose cover is an opaque
/// photo (a [RecipeCard], the `ChefSpotlightCard` portrait) keyboard focus
/// showed only on the text strip under it, and on a colour-block cover not at
/// all (WCAG 2.4.7). This keeps the `InkWell` for the gesture, its semantics
/// and focus traversal, turns its own ink off, and draws the states itself in
/// a layer above the child: a wash in the theme's hover / highlight colour, and
/// a two-tone ring in `colorScheme.primary` while the tile holds **keyboard**
/// focus — the same rule the `InkWell` uses, so a tap never leaves a ring.
///
/// Both layers are [IgnorePointer]s and neither adds a semantics node: a
/// control inside the child (the chef badge on a recipe cover) is still the
/// deepest hit and still wins its own taps, and the tile is still one tap
/// target read as one node. They paint inside the tile's bounds, so the
/// tile's geometry is exactly its child's.
class InteractiveTile extends StatefulWidget {
  const InteractiveTile({
    super.key,
    required this.onTap,
    required this.borderRadius,
    required this.child,
  });

  /// Null makes the tile inert: no hover, no focus, no ring.
  final VoidCallback? onTap;

  /// The corner the wash and the ring follow — the tile's own.
  final BorderRadius borderRadius;

  final Widget child;

  @override
  State<InteractiveTile> createState() => _InteractiveTileState();
}

class _InteractiveTileState extends State<InteractiveTile> {
  bool _focused = false;
  bool _hovered = false;
  bool _pressed = false;
  FocusHighlightMode _mode = FocusManager.instance.highlightMode;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addHighlightModeListener(_onModeChanged);
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(_onModeChanged);
    super.dispose();
  }

  // Focus stays put when the input device changes, but whether it should be
  // *shown* does not: a keyboard user who picks up the mouse keeps the ring,
  // a tap switches it off. Same trigger `InkWell` listens to.
  void _onModeChanged(FocusHighlightMode mode) {
    if (mounted && mode != _mode) setState(() => _mode = mode);
  }

  bool get _showFocus =>
      _focused &&
      (_mode == FocusHighlightMode.traditional ||
          MediaQuery.maybeNavigationModeOf(context) ==
              NavigationMode.directional);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final wash =
        _pressed
            ? theme.highlightColor
            : _hovered
            ? theme.hoverColor
            : null;

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: widget.borderRadius,
        // Every state is painted by the layers below instead; ink of its own
        // would land under the cover again. `Colors.transparent` is the one
        // literal colour allowed — it is the absence of one.
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        splashFactory: NoSplash.splashFactory,
        onFocusChange: (v) => setState(() => _focused = v),
        onHover: (v) => setState(() => _hovered = v),
        onHighlightChanged: (v) => setState(() => _pressed = v),
        child: Stack(
          // Passthrough: the child is laid out under exactly the constraints
          // the tile was given, as if the Stack were not there.
          fit: StackFit.passthrough,
          children: [
            widget.child,
            if (wash != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    key: kTileInkWashKey,
                    decoration: BoxDecoration(
                      color: wash,
                      borderRadius: widget.borderRadius,
                    ),
                  ),
                ),
              ),
            if (_showFocus)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    key: kTileFocusRingKey,
                    decoration: BoxDecoration(
                      borderRadius: widget.borderRadius,
                      border: Border.all(
                        color: scheme.primary,
                        width: kTileFocusRingWidth,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(kTileFocusRingWidth),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: widget.borderRadius.subtract(
                            BorderRadius.circular(kTileFocusRingWidth),
                          ),
                          border: Border.all(
                            color: scheme.surface,
                            width: _kFocusRingInnerWidth,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
