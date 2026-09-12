import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

import 'package:app/features/legal/legal_document.dart';
import 'package:app/routing/app_router.dart';
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

    return Scaffold(
      appBar: AppBar(
        title: Text(doc.title),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
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
              Text(doc.title, style: theme.textTheme.headlineSmall),
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
    );
  }
}

/// Shown until [LegalFacts] is filled in.
///
/// Loud on purpose. A legal document that is missing its operator and its
/// jurisdiction still *reads* like a legal document, and the failure mode this
/// guards against is somebody shipping it because it looked finished.
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
              'Draft — not in force. This document is missing the operating '
              'entity, the governing law, a contact address or the hosting '
              'region, which appear below as bracketed placeholders. It must '
              'not be published in this state.',
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
        child: Text(text, style: theme.textTheme.titleMedium),
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
