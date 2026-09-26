import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

import 'package:app/features/legal/legal_document.dart';
import 'package:app/routing/app_router.dart';
import 'package:app/widgets/route_title.dart';
import 'package:app/routing/pop_or_go.dart';
import 'package:app/widgets/legal_footer.dart';

/// One screen for all three legal documents (Phase 35a).
///
/// Signed-out safe and deliberately absent from `needsAuth`: a Terms page you
/// have to sign in to read is not a Terms page. It is pushed on the root
/// navigator rather than living in the shell, because it is a destination
/// reached from a link, not a tab — the same call recipe detail and the chef
/// page make, and the reason it uses [popOrGo] (32c5): reached by a tap there
/// is something to pop back to, reached by a shared link there is not.
class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key, required this.doc});

  final LegalDoc doc;

  /// Long-form prose wants a measured column, not the window. 720 is the usual
  /// comfortable reading measure and is narrower than the 1140 the expanded
  /// recipe page uses, because that page is a layout and this one is text.
  static const double maxReadingWidth = 720;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // The document names the browser tab (UX-051).
    return RouteTitle(
      page: doc.title,
      child: Scaffold(
        appBar: AppBar(
          title: Text(doc.title),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            // UX-047: an icon button needs a name, or it is read as "button".
            // The platform's own word, as BackButton uses.
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: () => popOrGo(context, Routes.discover),
          ),
        ),
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: maxReadingWidth),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.xxl,
              ),
              children: [
                // The document's top heading (UX-014).
                Semantics(
                  container: true,
                  header: true,
                  child: Text(doc.title, style: theme.textTheme.headlineSmall),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Last updated $kLegalLastUpdated',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (!LegalFacts.isComplete) ...[
                  const SizedBox(height: AppSpacing.md),
                  const _DraftNotice(),
                ],
                const SizedBox(height: AppSpacing.lg),
                for (final block in doc.blocks) _BlockView(block: block),
                const SizedBox(height: AppSpacing.xl),
                const Divider(),
                const SizedBox(height: AppSpacing.md),
                // Every document links to its two siblings. Someone who arrives
                // on one of these by a shared link has no navigation around them
                // otherwise — there is no nav chrome on this screen by design.
                LegalFooter(current: doc),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown while [LegalFacts.provisional] is set.
///
/// Loud on purpose, and it became *more* necessary when the placeholders stopped
/// looking like placeholders: a document carrying a plausible company name and a
/// plausible jurisdiction reads as finished, and the failure mode this guards
/// against is somebody shipping it for that reason.
class _DraftNotice extends StatelessWidget {
  const _DraftNotice();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: scheme.onErrorContainer),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Draft — not in force. The operating entity, the governing law, '
              'the contact address and the hosting region in this document are '
              'placeholders. They read like real values, which is exactly why '
              'this notice is here: confirm all four and clear '
              'LegalFacts.provisional before publishing.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class _BlockView extends StatelessWidget {
  const _BlockView({required this.block});

  final LegalBlock block;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Exhaustive because [LegalBlock] is sealed: a new block type is a compile
    // error here rather than a silently unrendered paragraph.
    return switch (block) {
      LegalHeading(:final text) => Padding(
        padding: const EdgeInsets.only(
          top: AppSpacing.lg,
          bottom: AppSpacing.sm,
        ),
        // A section heading of the document (UX-014): the sealed type is the
        // one place that knows which lines are headings.
        child: Semantics(
          container: true,
          header: true,
          child: Text(text, style: theme.textTheme.titleMedium),
        ),
      ),
      LegalParagraph(:final text) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: Text(text, style: theme.textTheme.bodyMedium),
      ),
      LegalBullets(:final items) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // A non-flex child of a Row is laid out unbounded, so the
                    // bullet is a fixed-width box and the text is the flexible
                    // one (Gotcha 21). The other way round overflows.
                    const SizedBox(width: AppSpacing.md, child: Text('•')),
                    Expanded(
                      child: Text(item, style: theme.textTheme.bodyMedium),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    };
  }
}
