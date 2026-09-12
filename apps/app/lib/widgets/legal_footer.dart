import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:app/features/legal/legal_document.dart';
import 'package:app/routing/app_router.dart';

/// The Privacy / Terms / Rights links, wired to the router (Phase 35a).
///
/// App-level rather than a legal-feature widget because four places reach it
/// and only one of them is the legal feature: the web chrome ([AppShell]), the
/// profile screen, the sign-up form and the legal pages themselves. The split
/// of *where* it appears is explained on [SiteFooter]; the short version is
/// that Discover, Chefs and My Recipes page forever, so a footer at the end of
/// their scroll would be unreachable.
class LegalFooter extends StatelessWidget {
  const LegalFooter({super.key, this.current, this.dense = false});

  /// The document the reader is already on, rendered as text rather than a
  /// link. Null everywhere except on a legal page.
  final LegalDoc? current;

  /// The bordered web-chrome form. See [SiteFooter.dense].
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return SiteFooter(
      dense: dense,
      copyright: '© ${LegalFacts.entity}',
      links: [
        for (final doc in LegalDoc.values)
          SiteFooterLink(
            label: doc.shortLabel,
            isCurrent: doc == current,
            // `push`, not `go`: these are opened from on top of whatever the
            // reader was doing, and they should hand it back. `popOrGo` on the
            // legal screen covers the other arrival — a shared link, where
            // there is nothing underneath to pop to.
            onTap: () => context.push(Routes.legal(doc.slug)),
          ),
      ],
    );
  }
}
