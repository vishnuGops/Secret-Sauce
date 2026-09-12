import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:app/features/chefs/chefs_providers.dart';
import 'package:app/features/legal/legal_document.dart';
import 'package:app/routing/app_router.dart';

/// What `/chef/:id` says when the chef has never signed up (Phase 35b).
///
/// An imported profile is a name the corpus credits, with no account behind it.
/// Three things have to be true of this block and each of them is a decision
/// rather than a layout:
///
///  * **It says so plainly.** A page that looks like every other chef page,
///    for someone who never joined, is the thing the Rights position exists to
///    avoid. The copy names where the recipes came from.
///  * **It is not a score.** There is no rank, no tier and no engagement here,
///    and the block explains the absence rather than rendering zeroes the
///    reader has to interpret.
///  * **The claim button is honest.** Claiming is a `security definer` RPC with
///    EXECUTE revoked from every API role — an administrator runs it by hand —
///    so there is nothing for a button to call yet. It is therefore disabled
///    and explains itself through [notYetTooltip], the same treatment the
///    windowed rails and the reserved share permission get. A button that
///    silently does nothing would be worse than no button.
class UnclaimedChefNote extends ConsumerWidget {
  const UnclaimedChefNote({super.key, required this.data});

  final ChefPageData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.person_outline,
                size: 20,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.sm),
              // Expanded, not Flexible-beside-Flexible: the icon is the
              // non-flex child and the text takes everything left (Gotcha 21).
              Expanded(
                child: Text(
                  'This page is a credit, not an account',
                  style: theme.textTheme.titleSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '${data.profile.displayName.isEmpty ? 'This chef' : data.profile.displayName} '
            'has not signed up for Secret-Sauce. The recipes below are credited '
            'to them because they published them elsewhere, and each one links '
            'back to where it came from. There is no score or rank here, and '
            'this page is deliberately absent from the chefs leaderboard.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          // Wrap, not Row: two buttons plus their labels at 2.0x text scale do
          // not share a line on a 390px phone, and a Wrap degrades to two rows
          // instead of overflowing.
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              notYetTooltip(
                enabled: false,
                message:
                    'Claiming is reviewed by hand for now — write to '
                    '${LegalFacts.contactEmail} and we will verify it with you.',
                child: FilledButton.tonalIcon(
                  onPressed: null,
                  icon: const Icon(Icons.verified_user_outlined),
                  label: const Text('Is this you?'),
                ),
              ),
              TextButton.icon(
                onPressed:
                    () => context.push(Routes.legal(LegalDoc.rights.slug)),
                icon: const Icon(Icons.gavel_outlined),
                label: const Text('Credit or removal'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
