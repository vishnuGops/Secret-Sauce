import 'dart:async';

import 'package:flutter/material.dart';

import 'package:design_system/src/theme/app_theme.dart';

/// A titled horizontal shelf of fixed-width cards, paged by two arrows.
///
/// Used three times down the chefs page. Generic over its children on purpose —
/// nothing here knows what a chef is.
///
/// The draft animates a `transform: translateX` on a flex row. This scrolls a
/// real [ListView] instead: on the web a rail also has to answer a trackpad, a
/// drag and a scrollbar, and a transform answers none of them. The arrows are
/// the same gesture expressed as [ScrollController.animateTo].
class CardRail extends StatefulWidget {
  const CardRail({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.height,
    required this.cardWidth,
    required this.itemCount,
    required this.itemBuilder,
    this.gap = AppSpacing.md,
    this.page = 3,
    this.footnote,
  });

  /// Leading glyph, drawn in a rounded primary-container tile.
  final IconData icon;

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final last = (_first + widget.page).clamp(0, widget.itemCount);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  widget.icon,
                  size: 20,
                  color: scheme.onPrimaryContainer,
                ),
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
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      widget.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (widget.itemCount > widget.page) ...[
                const SizedBox(width: AppSpacing.sm),
                Text(
                  '${_first + 1}–$last / ${widget.itemCount}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
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
              ],
            ],
          ),
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
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
      ],
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
        disabledBackgroundColor:
            scheme.surfaceContainerHigh.withValues(alpha: 0.4),
        disabledForegroundColor:
            scheme.onSurfaceVariant.withValues(alpha: 0.38),
      ),
    );
  }
}
