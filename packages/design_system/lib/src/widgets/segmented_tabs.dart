import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:design_system/src/theme/app_theme.dart';
import 'package:design_system/src/widgets/not_yet_tooltip.dart';

/// Which surface a [SegmentedTabs] sits on.
enum SegmentedTabsTone {
  /// A page or a panel: a `surfaceContainerHigh` track, the selected segment
  /// lifted to `surfaceContainerLowest`.
  surface,

  /// The always-dark chefs hero gradient: a `heroFill` track, the selected
  /// segment filled `onHero` with `heroSelectedInk` on it — the colours
  /// `/chefs`' window filter always had, identical in both themes.
  onHero,
}

/// The one pill segmented control (UX-032, DESIGN.md §4): a pill track, one
/// option filled, one tap to change it.
///
/// Grown from the chefs board's `ChefPillTabs`, and replaces the four controls
/// that did this one job — that pill, the chefs hero's window filter, Discover's
/// underlined sort links and the recipe rail's two `ChoiceChip`s. `TabBar` and
/// `SegmentedButton` stay where they are the M3-correct control.
///
/// **A 48px target around a ~32px pill** (UX-048). Every segment answers taps,
/// focus and assistive tech over at least [minHitDimension] in both axes; the
/// painted track is a band centred in that height, the way
/// `MaterialTapTargetSize.padded` pads a button without drawing it bigger. The
/// band's height is *computed* from the label role and the text scale rather
/// than measured, because the track is painted once behind the whole row — a
/// per-segment slice of it would seam where two fractional widths meet.
///
/// **One weight in every state** (UX-049): a heavier selected label widened
/// itself and pushed its neighbours along. The fill and the ink carry the
/// selection, and the selection is announced as `selected` on exactly one
/// `button` node (UX-014).
///
/// **Sizing — two modes, and neither overflows:**
///
///   * [expand] `true` divides a *bounded* width equally between the segments
///     (the chefs board and `/chef/:id`, whose pill spans its column). Labels
///     ellipsise rather than wrap, so a long option costs itself letters and
///     never the pill's height. Under unbounded width this is a `Row` of flex
///     children — an assertion, not an overflow (Gotcha 21's other half).
///   * [expand] `false` (default) sizes each segment to its label. Where the
///     width is bounded the row sits in a horizontal scroll view, so at 390px ×
///     2.0 with long labels the pill scrolls rather than overflowing — a `Wrap`
///     was the alternative, and a pill broken over two lines stops reading as
///     one control. Where the width is unbounded (a non-flex child of a `Row`,
///     as in the chefs hero's row layout) it is laid out bare: the caller has
///     already decided it fits. The `LayoutBuilder` that makes that call only
///     asks *whether* the width is bounded, never uses the number, so Gotcha
///     25's infinite-cap trap does not apply.
class SegmentedTabs<T> extends StatelessWidget {
  const SegmentedTabs({
    super.key,
    required this.values,
    required this.selected,
    required this.onSelected,
    required this.labelOf,
    this.semanticLabel,
    this.tone = SegmentedTabsTone.surface,
    this.expand = false,
    this.enabledOf,
    this.disabledMessage = '',
  });

  final List<T> values;
  final T selected;
  final ValueChanged<T> onSelected;
  final String Function(T) labelOf;

  /// Names the whole control to assistive tech (`Sort recipes`). Each segment
  /// is announced by its own label either way.
  final String? semanticLabel;

  final SegmentedTabsTone tone;

  /// Fill a bounded width equally, or size each segment to its label. See the
  /// class comment.
  final bool expand;

  /// Null means every option is live.
  final bool Function(T)? enabledOf;

  /// Shown on hover over a disabled segment. Ignored when [enabledOf] is null.
  final String disabledMessage;

  /// The smallest target a segment answers over, both axes (UX-048):
  /// Material's 48px minimum.
  static const double minHitDimension = kMinInteractiveDimension;

  /// Stroke of the keyboard focus ring — WCAG 2.4.13's 2px minimum. The
  /// ring sits on a flat fill here, not a photo, so it does not need
  /// `InteractiveTile`'s third pixel.
  static const double focusRingWidth = AppStroke.thin;

  /// Key of the focus ring, which exists only while a segment holds
  /// **keyboard** focus. For tests.
  static const Key focusRingKey = ValueKey('segmented-tabs-focus-ring');

  /// The label role. One role, one weight, in every state (UX-049).
  ///
  /// `labelLarge` (14px), not `labelSmall`: this control now carries the
  /// Discover sort and the rail's Ingredients / Nutrition switch, which were
  /// 14px text before they were consolidated, and a control a cook reads at
  /// arm's length is not the place to shrink type (DESIGN §1, "kitchen-proof").
  static TextStyle labelStyle(BuildContext context) =>
      (Theme.of(context).textTheme.labelLarge ?? const TextStyle()).tabular;

  @override
  Widget build(BuildContext context) {
    final style = labelStyle(context);
    final scaler =
        MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling;
    // The label's line box, exactly: the Text forces its strut to this, so a
    // fallback glyph cannot make one segment taller than the band.
    final fontSize = style.fontSize ?? 14;
    final lineHeight = scaler.scale(fontSize) * (style.height ?? 1);
    const track = AppInsets.segmentTrack;
    final chipHeight = lineHeight + AppInsets.segment.vertical;
    final bandHeight = chipHeight + track.vertical;
    final hitHeight = math.max(minHitDimension, bandHeight);
    final colors = _ToneColors.of(context, tone);

    final segments = [
      for (final value in values)
        _Segment(
          label: labelOf(value),
          selected: value == selected,
          enabled: enabledOf?.call(value) ?? true,
          disabledMessage: disabledMessage,
          onTap: () => onSelected(value),
          style: style,
          chipHeight: chipHeight,
          expand: expand,
          colors: colors,
        ),
    ];

    final Widget control = SizedBox(
      height: hitHeight,
      child: Stack(
        children: [
          // The track, painted once behind every segment and centred in the
          // hit height.
          Positioned.fill(
            child: Center(
              child: SizedBox(
                height: bandHeight,
                width: double.infinity,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.track,
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(left: track.left, right: track.right),
            child: Row(
              mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
              // Every segment is the full hit height; its paint is centred.
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final segment in segments)
                  expand ? Expanded(child: segment) : segment,
              ],
            ),
          ),
        ],
      ),
    );

    final Widget sized =
        expand
            ? control
            : LayoutBuilder(
              builder:
                  (context, constraints) =>
                      constraints.hasBoundedWidth
                          ? SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: control,
                          )
                          : control,
            );

    final label = semanticLabel;
    return label == null
        ? sized
        : Semantics(container: true, label: label, child: sized);
  }
}

class _ToneColors {
  const _ToneColors({
    required this.track,
    required this.fill,
    required this.selectedInk,
    required this.ink,
    required this.hover,
    required this.focusRing,
    required this.focusRingOnFill,
  });

  factory _ToneColors.of(BuildContext context, SegmentedTabsTone tone) {
    final scheme = Theme.of(context).colorScheme;
    final palette = context.palette;
    return switch (tone) {
      SegmentedTabsTone.surface => _ToneColors(
        track: scheme.surfaceContainerHigh,
        fill: scheme.surfaceContainerLowest,
        selectedInk: scheme.onSurface,
        ink: scheme.onSurfaceVariant,
        hover: scheme.onSurface.withValues(alpha: AppAlpha.faint),
        focusRing: scheme.primary,
        focusRingOnFill: scheme.primary,
      ),
      SegmentedTabsTone.onHero => _ToneColors(
        track: palette.heroFill,
        fill: palette.onHero,
        selectedInk: palette.heroSelectedInk,
        ink: palette.onHeroMuted,
        hover: palette.onHero.withValues(alpha: AppAlpha.wash),
        focusRing: palette.onHero,
        // The selected fill *is* `onHero`, so a ring in it would vanish.
        focusRingOnFill: palette.heroSelectedInk,
      ),
    };
  }

  final Color track;
  final Color fill;
  final Color selectedInk;
  final Color ink;
  final Color hover;
  final Color focusRing;

  /// The ring over the selected segment's fill — the ring sits inside the
  /// segment's paint, so it has to read against that fill, not the track.
  final Color focusRingOnFill;
}

class _Segment extends StatefulWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.disabledMessage,
    required this.onTap,
    required this.style,
    required this.chipHeight,
    required this.expand,
    required this.colors,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final String disabledMessage;
  final VoidCallback onTap;
  final TextStyle style;
  final double chipHeight;
  final bool expand;
  final _ToneColors colors;

  @override
  State<_Segment> createState() => _SegmentState();
}

class _SegmentState extends State<_Segment> {
  bool _hovered = false;
  bool _focusShown = false;

  void _activate() {
    if (widget.enabled) widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final enabled = widget.enabled;
    final selected = widget.selected;
    final ink =
        selected
            ? colors.selectedInk
            : enabled
            ? colors.ink
            // Scaled, not replaced: `onHeroMuted` already carries an alpha.
            : colors.ink.withValues(alpha: colors.ink.a * AppAlpha.muted);
    final fill =
        selected
            ? colors.fill
            : _hovered && enabled
            ? colors.hover
            : null;

    final chip = Stack(
      children: [
        AnimatedContainer(
          duration: AppMotion.of(context, AppMotion.fast),
          curve: AppMotion.emphasized,
          height: widget.chipHeight,
          // Filling the flex share in expand mode; at least a 48px target
          // either way, so `All` is as easy to hit as `Trending`.
          width: widget.expand ? double.infinity : null,
          constraints: const BoxConstraints(
            minWidth: SegmentedTabs.minHitDimension,
          ),
          alignment: Alignment.center,
          // Expand mode drops the horizontal inset: the width is the flex
          // share, and an inset would only ellipsise labels sooner.
          padding:
              widget.expand
                  ? EdgeInsets.zero
                  : EdgeInsets.symmetric(horizontal: AppInsets.segment.left),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(AppRadii.pill),
          ),
          child: ExcludeSemantics(
            // The segment's Semantics carries the label, once.
            child: Text(
              widget.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              strutStyle: StrutStyle.fromTextStyle(
                widget.style,
                forceStrutHeight: true,
              ),
              style: widget.style.copyWith(color: ink),
            ),
          ),
        ),
        if (_focusShown)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                key: SegmentedTabs.focusRingKey,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                  border: Border.all(
                    color: selected ? colors.focusRingOnFill : colors.focusRing,
                    width: SegmentedTabs.focusRingWidth,
                  ),
                ),
              ),
            ),
          ),
      ],
    );

    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      selected: selected,
      label: widget.label,
      onTap: enabled ? _activate : null,
      child: notYetTooltip(
        enabled: enabled,
        message: widget.disabledMessage,
        child: FocusableActionDetector(
          enabled: enabled,
          mouseCursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
          // Enter / Space: `ActivateIntent` natively, `ButtonActivateIntent`
          // from the web's default shortcuts.
          actions: <Type, Action<Intent>>{
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) => _activate(),
            ),
            ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(
              onInvoke: (_) => _activate(),
            ),
          },
          // Keyboard focus only, the rule `InkWell` uses: a tap never leaves
          // a ring behind.
          onShowFocusHighlight: (v) => setState(() => _focusShown = v),
          // Hover from a MouseRegion rather than `onShowHoverHighlight`, which
          // is gated on the *focus* highlight mode — a mouse that has only
          // moved (never clicked) on a touch-default platform would get none.
          child: MouseRegion(
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              // The Semantics above carries the tap; a second one here would
              // be a duplicate action in the tree.
              excludeFromSemantics: true,
              onTap: enabled ? _activate : null,
              child: Center(child: chip),
            ),
          ),
        ),
      ),
    );
  }
}
