import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

import 'package:app/features/recipe_detail/version_view.dart';

/// Bottom sheet listing a recipe's version history (git-like snapshots).
///
/// Each row opens that version read-only in [VersionView] (UX-052) — the rows
/// used to be inert, so the history said a version existed and gave no way to
/// see it. The list itself still carries no snapshot (B065); the view fetches
/// the one a reader opens.
class VersionHistorySheet extends StatelessWidget {
  const VersionHistorySheet({super.key, required this.versions});

  final List<RecipeVersion> versions;

  static Future<void> show(BuildContext context, List<RecipeVersion> versions) {
    return showModalBottomSheet(
      context: context,
      showDragHandle: true,
      // Both detail layouts are on the root navigator already; saying so keeps
      // the sheet above any shell chrome if that ever changes (Gotcha 23).
      useRootNavigator: true,
      builder: (_) => VersionHistorySheet(versions: versions),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (versions.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.xl),
        child: Text('No version history yet.'),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: versions.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final v = versions[i];
        final isLatest = i == 0;
        // The "Current" chip rides under the title, beside the date, rather
        // than in `trailing`: a trailing chip is a fixed-width box beside the
        // title, and at 2.0x on a phone it left the change summary a column
        // two words wide. A `Wrap`, so the chip drops below the date when the
        // pair does not fit.
        final subtitle = [
          if (v.createdAt != null) Text(isoDate(v.createdAt!)),
          if (isLatest)
            const Chip(
              label: Text('Current'),
              visualDensity: VisualDensity.compact,
            ),
        ];
        // A `ListTile` with `onTap` is a >= 48dp button already; the label
        // says what the tap does, ahead of the summary and date it merges.
        return Semantics(
          button: true,
          label: 'Open version ${v.versionNumber}',
          child: ListTile(
            onTap: () => VersionView.show(context, v),
            leading: CircleAvatar(child: Text('v${v.versionNumber}')),
            title: Text(
              v.changeSummary.isEmpty
                  ? 'Version ${v.versionNumber}'
                  : v.changeSummary,
            ),
            subtitle:
                subtitle.isEmpty
                    ? null
                    : Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: subtitle,
                    ),
            trailing: const Icon(Icons.chevron_right),
          ),
        );
      },
    );
  }
}
