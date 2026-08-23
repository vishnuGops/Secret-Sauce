import 'dart:async';

import 'package:flutter/material.dart';

import 'package:design_system/src/theme/app_theme.dart';

/// How a rail introduces itself.
enum CardRailVariant {
  /// A glyph in a rounded primary-container tile, then title over subtitle.
  /// The chefs page's three shelves.
  badged,

  /// A set numeral, the title in spaced caps, and a hairline rule running out
  /// to the controls — Discover's shelves. Print furniture rather than UI
  /// chrome: the shelves are a *sequence*, and a numeral says that where a
  /// third icon tile would just say "another list".
  numbered,
}

/// A titled horizontal shelf of fixed-width cards, paged by two arrows.
///
/// Used three times down the chefs page and three times down Discover. Generic
/// over its children on purpose — nothing here knows what a chef or a recipe
/// is; the caller sizes its own tiles (a horizontal [ListView] gives a child a
/// tight height and an **unbounded width**, so a tile that does not fix its own
/// width must be wrapped in a `SizedBox`).
///
/// The draft animates a `transform: translateX` on a flex row. This scrolls a
/// real [ListView] instead: on the web a rail also has to answer a trackpad, a
/// drag and a scrollbar, and a transform answers none of them. The arrows are
/// the same gesture expressed as [ScrollController.animateTo].
///
/// A variant rather than a second widget, on the [ChefStandingCard] precedent:
/// the scroll controller, the pitch arithmetic and the `1–3 / 10` window are
/// the substance here, and none of it differs between the two headers.
class CardRail extends StatefulWidget {
  const CardRail({
    super.key,
    required this.title,
    required this.subtitle,
    required this.height,
    required this.cardWidth,
    required this.itemCount,
    required this.itemBuilder,
    this.variant = CardRailVariant.badged,
    this.icon,
    this.index,
    this.kicker,
    this.accent,
    this.gap = AppSpacing.md,
    this.page = 3,
    this.footnote,
  }) : assert(
         variant == CardRailVariant.badged ? icon != null : index != null,
         'a badged rail needs an icon; a numbered rail needs an index',
       );

  final CardRailVariant variant;

  /// Leading glyph, drawn in a rounded primary-container tile. [CardRailVariant.badged] only.
  final IconData? icon;

  /// The set numeral — `01`. [CardRailVariant.numbered] only.
  final String? index;

  /// Small caps at the far end of the rule, for stating the ranking rule
  /// (`RANKED BY SAVES`). Dropped before anything else when the header runs out
  /// of width. [CardRailVariant.numbered] only.
  final String? kicker;

  /// Tints the numeral and its rule. Defaults to `colorScheme.primary`.
  final Color? accent;

  final String title;
  final String subtitle;

  /// Height handed to the scroll viewport. Fixed-size tiles need it — a
  /// horizontal [ListView] gives its children a tight cross-axis extent.
  final double height;

  /// Width of one card. With [gap] it fixes the scroll pitch, so an arrow press
  /// always lands on a card edge.
  final double cardWidth;

  /// Space between two cards.
  final double gap;

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  /// How many cards an arrow press moves. Also the width of the `1–3 / 10`
  /// window in the position label.
  final int page;

  /// Optional line under the rail, for saying why a shelf looks the way it does.
  final String? footnote;

  @override
  State<CardRail> createState() => _CardRailState();
}

class _CardRailState extends State<CardRail> {
  final ScrollController _controller = ScrollController();

  /// Index of the leftmost card, derived from the scroll offset. Kept in state
  /// so the position label and the arrow states can rebuild without rebuilding
  /// the cards.
  int _first = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  /// Distance from one card's leading edge to the next.
  double get _pitch => widget.cardWidth + widget.gap;

  void _onScroll() {
    if (!_controller.hasClients) return;
    final next = (_controller.offset / _pitch).round().clamp(0, _maxFirst);
    // Only rebuild when the label would actually change — a scroll fires this
    // every frame.
    if (next != _first) setState(() => _first = next);
  }

  /// Leftmost index once the rail is scrolled to its end. Below a full page
  /// there is nothing to scroll, so this is 0.
  int get _maxFirst =>
      widget.itemCount <= widget.page ? 0 : widget.itemCount - widget.page;

  bool get _canGoBack => _first > 0;
  bool get _canGoForward => _first < _maxFirst;

  void _move(int delta) {
    if (!_controller.hasClients) return;
    final target = (_first + delta).clamp(0, _maxFirst);
    unawaited(
      _controller.animateTo(
        target * _pitch,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  /// Whether the shelf is longer than one page — the only reason to draw
  /// controls at all.
  bool get _pages => widget.itemCount > widget.page;

  /// `1–3 / 10`, and the two arrows.
  ///
  /// Shared by both headers, and both of them may omit it: a rail is scrolled
  /// by drag on a touch screen, so on a narrow one these are decoration that
  /// costs the title its width.
  List<Widget> _controls(ThemeData theme, {required bool showLabel}) {
    final last = (_first + widget.page).clamp(0, widget.itemCount);
    return [
      if (showLabel) ...[
        Text(
          '${_first + 1}–$last / ${widget.itemCount}',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
      ],
      _Arrow(
        icon: Icons.chevron_left,
        tooltip: 'Previous',
        onPressed: _canGoBack ? () => _move(-widget.page) : null,
      ),
      const SizedBox(width: AppSpacing.xs),
      _Arrow(
        icon: Icons.chevron_right,
        tooltip: 'Next',
        onPressed: _canGoForward ? () => _move(widget.page) : null,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: switch (widget.variant) {
            CardRailVariant.badged => _badgedHeader(theme),
            CardRailVariant.numbered => _numberedHeader(theme),
          },
        ),
        SizedBox(
          height: widget.height,
          child: ListView.separated(
            controller: _controller,
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            itemCount: widget.itemCount,
            separatorBuilder: (_, __) => SizedBox(width: widget.gap),
            itemBuilder: widget.itemBuilder,
          ),
        ),
        if (widget.footnote != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              widget.footnote!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }

  /// Icon tile, title over subtitle, controls. The chefs page's header.
  Widget _badgedHeader(ThemeData theme) {
    final scheme = theme.colorScheme;

    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(widget.icon, size: 20, color: scheme.onPrimaryContainer),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                widget.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (_pages) ...[
          const SizedBox(width: AppSpacing.sm),
          ..._controls(theme, showLabel: true),
        ],
      ],
    );
  }

  /// `01 ─ UNDER 30 ────────── RANKED BY SAVES  1–3 / 12  ‹ ›`, subtitle under.
  ///
  /// The rule is the flex child, so it is the part that gives up width, and
  /// every other child is intrinsic. That inverts the usual arrangement for a
  /// reason: a rule has no minimum and a title does, and two flex children
  /// would split the row 50/50 whatever the content says (B038). The title is
  /// therefore capped against the row instead — below the cap it takes what it
  /// needs, above it, it ellipsizes.
  ///
  /// Both trailing groups are dropped by width before the title is squeezed:
  /// the position label and the arrows are a pointer affordance, and the shelf
  /// answers a drag on a phone whether or not they are drawn.
  Widget _numberedHeader(ThemeData theme) {
    final scheme = theme.colorScheme;
    final accent = widget.accent ?? scheme.primary;

    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final width = constraints.maxWidth;
        // The numeral sits in a fixed box so the subtitle can hang off the same
        // left edge as the title. The box grows with the text — but only to
        // 2.0×, the envelope the card is contracted to (Gotcha 13); past that
        // the numeral scales down inside the box rather than pushing the title
        // along and taking the row with it.
        final numeralWidth = 30 * scale.clamp(1.0, 2.0);
        final showControls = _pages && width >= 460 * scale;
        final showLabel = width >= 620 * scale;
        final showKicker = widget.kicker != null && width >= 700 * scale;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                SizedBox(
                  width: numeralWidth,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      widget.index!,
                      maxLines: 1,
                      // TODO(fonts): the drafts set numerals in a mono face;
                      // approximated with weight and tracking until the
                      // app-wide type decision lands.
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        height: 1,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: width * 0.55),
                  child: Text(
                    widget.title.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.4,
                      height: 1,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Container(
                    height: 1,
                    color: accent.withValues(alpha: 0.35),
                  ),
                ),
                if (showKicker) ...[
                  const SizedBox(width: AppSpacing.sm),
                  // Capped, not intrinsic (B057, the B039 class): a non-flex
                  // child of a Row is laid out against an unbounded main axis,
                  // so a caller's longer kicker would overflow the header
                  // instead of ellipsizing. The width gate above only decides
                  // whether it is drawn at all — it says nothing about how wide
                  // this particular string is.
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: width * 0.25),
                    child: Text(
                      widget.kicker!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        letterSpacing: 1,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
                if (showControls) ...[
                  const SizedBox(width: AppSpacing.sm),
                  ..._controls(theme, showLabel: showLabel),
                ],
              ],
            ),
            const SizedBox(height: 2),
            Padding(
              padding: EdgeInsets.only(left: numeralWidth + AppSpacing.sm),
              child: Text(
                widget.subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Arrow extends StatelessWidget {
  const _Arrow({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(icon, size: 20),
      visualDensity: VisualDensity.compact,
      style: IconButton.styleFrom(
        backgroundColor: scheme.surfaceContainerHigh,
        foregroundColor: scheme.onSurfaceVariant,
        // Disabled arrows stay visible but recede, the way the draft dims them
        // to 35% rather than removing them — a rail that loses its controls at
        // the ends reads as broken.
        disabledBackgroundColor: scheme.surfaceContainerHigh.withValues(
          alpha: 0.4,
        ),
        disabledForegroundColor: scheme.onSurfaceVariant.withValues(
          alpha: 0.38,
        ),
      ),
    );
  }
}
