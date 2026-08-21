import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// Bottom sheet listing a recipe's version history (git-like snapshots).
class VersionHistorySheet extends StatelessWidget {
  const VersionHistorySheet({super.key, required this.versions});

  final List<RecipeVersion> versions;

  static Future<void> show(
    BuildContext context,
    List<RecipeVersion> versions,
  ) {
    return showModalBottomSheet(
      context: context,
      showDragHandle: true,
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
        return ListTile(
          leading: CircleAvatar(child: Text('v${v.versionNumber}')),
          title: Text(
            v.changeSummary.isEmpty ? 'Version ${v.versionNumber}' : v.changeSummary,
          ),
          subtitle: v.createdAt == null
              ? null
              : Text(isoDate(v.createdAt!)),
          trailing: isLatest
              ? const Chip(label: Text('Current'))
              : null,
        );
      },
    );
  }
}
