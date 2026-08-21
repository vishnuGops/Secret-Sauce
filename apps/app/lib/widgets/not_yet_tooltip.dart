import 'package:flutter/material.dart';

/// Explains a control that is deliberately inert, and gets out of the way of
/// one that is not.
///
/// The conditional matters: `Tooltip` with an empty message still opens an
/// empty box on hover, so wrapping every control unconditionally would put a
/// blank tooltip under the ones that work.
///
/// App-level rather than feature-level: `/chefs` uses it for the windowed rails
/// that have no dated data yet, and the share dialog for the reserved
/// `share_permission.edit` segment. A second feature reaching into
/// `features/chefs/` for it would be exactly the cross-feature import OPT-A3
/// exists to remove.
Widget notYetTooltip({
  required bool enabled,
  required String message,
  required Widget child,
}) => enabled ? child : Tooltip(message: message, child: child);
