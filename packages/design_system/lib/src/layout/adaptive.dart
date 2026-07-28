import 'package:flutter/material.dart';

/// Responsive breakpoints and helpers used to adapt the UI between mobile,
/// tablet, and desktop/web layouts from a single codebase.
class Breakpoints {
  Breakpoints._();
  static const double compact = 600; // phones
  static const double medium = 1000; // tablets / small web
}

enum ScreenSize { compact, medium, expanded }

extension ScreenSizeContext on BuildContext {
  ScreenSize get screenSize {
    final width = MediaQuery.sizeOf(this).width;
    if (width < Breakpoints.compact) return ScreenSize.compact;
    if (width < Breakpoints.medium) return ScreenSize.medium;
    return ScreenSize.expanded;
  }

  bool get isCompact => screenSize == ScreenSize.compact;
  bool get isExpanded => screenSize == ScreenSize.expanded;
}

/// Renders different widgets depending on available width. Any of [medium] or
/// [expanded] falls back to [compact] when not provided.
class AdaptiveLayout extends StatelessWidget {
  const AdaptiveLayout({
    super.key,
    required this.compact,
    this.medium,
    this.expanded,
  });

  final WidgetBuilder compact;
  final WidgetBuilder? medium;
  final WidgetBuilder? expanded;

  @override
  Widget build(BuildContext context) {
    return switch (context.screenSize) {
      ScreenSize.expanded => (expanded ?? medium ?? compact)(context),
      ScreenSize.medium => (medium ?? compact)(context),
      ScreenSize.compact => compact(context),
    };
  }
}

/// Number of columns for a responsive grid.
int responsiveColumns(BuildContext context) => switch (context.screenSize) {
      ScreenSize.compact => 1,
      ScreenSize.medium => 2,
      ScreenSize.expanded => 3,
    };
