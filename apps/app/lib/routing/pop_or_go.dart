import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Leave the current screen: pop when there is something to pop back to,
/// otherwise `go` to [fallback].
///
/// Every screen pushed on the root navigator needs this, because "back" has two
/// meanings here. Reached by a tap from a list there is a route underneath and
/// popping is right; reached by a deep link, a refresh on the web, or a `go`
/// that replaced the stack there is nothing underneath and popping would leave
/// the user on a blank navigator. Five copies of the same four lines said so
/// separately (32c5); this is the one.
///
/// It asks the **navigator**, not `GoRouter.canPop()`: `recipe_detail_expanded`
/// asks the same question during `build` to decide whether to draw a Back
/// button, and a widget test that pumps a screen without a router must not
/// throw there.
void popOrGo(BuildContext context, String fallback) {
  final navigator = Navigator.of(context);
  if (navigator.canPop()) {
    navigator.pop();
  } else {
    context.go(fallback);
  }
}
