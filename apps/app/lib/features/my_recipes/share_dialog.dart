import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app/widgets/not_yet_tooltip.dart';

/// Dialog to share a recipe with another user (by display name) and set
/// their permission. Writes to `recipe_shares` via the repository.
class ShareDialog extends ConsumerStatefulWidget {
  const ShareDialog({super.key, required this.recipeId});

  final String recipeId;

  static Future<void> show(BuildContext context, String recipeId) {
    return showDialog(
      context: context,
      builder: (_) => ShareDialog(recipeId: recipeId),
    );
  }

  @override
  ConsumerState<ShareDialog> createState() => _ShareDialogState();
}

class _ShareDialogState extends ConsumerState<ShareDialog> {
  final _name = TextEditingController();
  SharePermission _permission = SharePermission.view;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _share() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final profile = await ref
          .read(profileRepositoryProvider)
          .findByEmailOrName(_name.text.trim());
      if (profile == null) {
        setState(() => _error = 'No user found with that name.');
        return;
      }
      await ref.read(recipeRepositoryProvider).share(
            recipeId: widget.recipeId,
            userId: profile.id,
            permission: _permission,
          );
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Shared with ${profile.displayName}')),
        );
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Share recipe'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'User display name',
              prefixIcon: Icon(Icons.person_search),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          // `share_permission.edit` exists in the enum and the column, but
          // nothing reads it: `recipes_update` is `owner_id = auth.uid()`, so a
          // recipe shared "Can edit" is still read-only to the recipient.
          // Offering it promised an access level the database does not grant, so
          // the segment is disabled until the policy catches up (OPT-S5).
          SegmentedButton<SharePermission>(
            segments: [
              const ButtonSegment(
                value: SharePermission.view,
                label: Text('Can view'),
                icon: Icon(Icons.visibility),
              ),
              ButtonSegment(
                value: SharePermission.edit,
                enabled: false,
                label: notYetTooltip(
                  enabled: false,
                  message: 'Shared editing is not built yet — '
                      'recipes stay read-only for the people you share them with',
                  child: const Text('Can edit'),
                ),
                icon: const Icon(Icons.edit),
              ),
            ],
            selected: {_permission},
            onSelectionChanged: (s) => setState(() => _permission = s.first),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _share,
          child: _busy
              ? const SizedBox(
                  height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Share'),
        ),
      ],
    );
  }
}
