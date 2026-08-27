import 'package:flutter/material.dart';

/// Explains a control that is deliberately inert, and gets out of the way of
/// one that is not.
///
/// The conditional matters: `Tooltip` with an empty message still opens an
/// empty box on hover, so wrapping every control unconditionally would put a
/// blank tooltip under the ones that work.
///
/// In `design_system` rather than in the app (32d6): three callers use it —
/// `/chefs`' windowed rails, the disabled segments of `ChefPillTabs` (the board
/// and `/chef/:id` share it), and the share dialog's reserved
/// `share_permission.edit` — and it holds no app state, no routing and no data.
/// It moved out of
/// `features/chefs/` when the share dialog became its second caller (OPT-S5)
/// and out of `apps/app/lib/widgets/` when it turned out to be a plain
/// presentational primitive. Exported from `design_system.dart` (Gotcha 14),
/// like every other widget here.
Widget notYetTooltip({
  required bool enabled,
  required String message,
  required Widget child,
}) => enabled ? child : Tooltip(message: message, child: child);
