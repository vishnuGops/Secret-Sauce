import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A page's browser-tab title (UX-051): `Chefs · Secret Sauce`.
///
/// `MaterialApp.title` names the app once, so every tab read "Secret-Sauce"
/// whatever it showed. A bare [Title] per page is not enough either: it speaks
/// only when it is first built or its string changes, so popping a pushed page
/// (`/chef/:id` → back to Discover) would leave the chef's name on the tab —
/// the page underneath never rebuilt with a *different* title. This wrapper
/// re-announces when its route becomes current again, and holds its title
/// still while it is covered so a background rebuild cannot overwrite the page
/// on top.
///
/// Every page that can be current names itself: the shell (from its location)
/// and each root-navigator page.
class RouteTitle extends StatefulWidget {
  const RouteTitle({super.key, required this.page, required this.child});

  /// The page's own name. Null titles the tab with the brand alone.
  final String? page;
  final Widget child;

  static const String brand = 'Secret Sauce';

  /// `<page> · Secret Sauce`, or the brand alone.
  static String format(String? page) =>
      page == null || page.isEmpty ? brand : '$page · $brand';

  @override
  State<RouteTitle> createState() => _RouteTitleState();
}

class _RouteTitleState extends State<RouteTitle> {
  /// What the [Title] below says. Follows [RouteTitle.page] only while this
  /// route is current.
  late String _title = RouteTitle.format(widget.page);
  bool _current = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // No route at all (a bare widget test) counts as current.
    final current = ModalRoute.isCurrentOf(context) ?? true;
    if (current && !_current) {
      _title = RouteTitle.format(widget.page);
      // Uncovered: the page that was on top set its own title, and [Title]
      // will not repeat an unchanged string on its own.
      SystemChrome.setApplicationSwitcherDescription(
        ApplicationSwitcherDescription(
          label: _title,
          primaryColor: Theme.of(context).colorScheme.primary.toARGB32(),
        ),
      );
    }
    _current = current;
  }

  @override
  void didUpdateWidget(RouteTitle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_current) _title = RouteTitle.format(widget.page);
  }

  @override
  Widget build(BuildContext context) => Title(
    title: _title,
    // The brand tomato: the colour a platform tints the task-switcher card
    // with. Opaque, which [Title] asserts.
    color: Theme.of(context).colorScheme.primary,
    child: widget.child,
  );
}
