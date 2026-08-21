import 'dart:async';

import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app/widgets/not_yet_tooltip.dart';

/// Dialog to share a recipe with another user and set their permission. Writes
/// to `recipe_shares` via the repository.
///
/// Lives here rather than in `features/my_recipes` (OPT-A3): sharing is reached
/// from the recipe detail screen, so a feature was importing another feature's
/// internals to open it — the same shape that put `notYetTooltip` in this
/// directory during OPT-S5.
///
/// It **asks which person** (OPT-A5). `display_name` is not unique, and the old
/// version took the first exact match the database happened to return: typing
/// "Dara" shared your recipe with a Dara, and told you it worked.
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

/// How long typing pauses before the lookup runs — the same 300 ms Discover's
/// search uses, for the same reason (OPT-P8).
const _kLookupDebounce = Duration(milliseconds: 300);

/// Matches shown at once. More than this and the answer is "type more", not
/// "scroll".
const _kMaxMatches = 8;

class _ShareDialogState extends ConsumerState<ShareDialog> {
  final _name = TextEditingController();
  Timer? _debounce;

  SharePermission _permission = SharePermission.view;
  List<Profile> _matches = const [];
  Profile? _selected;

  /// A lookup has finished for the current query — the difference between "no
  /// results yet" and "no such person".
  bool _searched = false;
  bool _searching = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _name.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    setState(() {
      // The selection belongs to the old query; keeping it is how you share
      // with someone whose name is no longer on screen.
      _selected = null;
      _searched = false;
      _error = null;
      if (value.trim().isEmpty) {
        _matches = const [];
        _searching = false;
        return;
      }
      _searching = true;
    });
    if (value.trim().isEmpty) return;
    _debounce = Timer(_kLookupDebounce, () => _lookup(value));
  }

  Future<void> _lookup(String query) async {
    try {
      final found = await ref
          .read(profileRepositoryProvider)
          .searchByName(query, limit: _kMaxMatches);
      if (!mounted || _name.text != query) return;
      setState(() {
        // Sharing with yourself is a no-op the database would happily store.
        final me = ref.read(currentUserIdProvider);
        _matches = [
          for (final p in found)
            if (p.id != me) p,
        ];
        _selected = _matches.length == 1 ? _matches.single : null;
        _searching = false;
        _searched = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyError(e);
        _searching = false;
        _searched = true;
      });
    }
  }

  Future<void> _share() async {
    final person = _selected;
    if (person == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(recipeRepositoryProvider)
          .share(
            recipeId: widget.recipeId,
            userId: person.id,
            permission: _permission,
          );
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Shared with ${person.displayName}')),
        );
      }
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Share recipe'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Search by display name',
                prefixIcon: const Icon(Icons.person_search),
                suffixIcon:
                    _searching
                        ? const Padding(
                          padding: EdgeInsets.all(AppSpacing.sm),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                        : null,
              ),
              onChanged: _onQueryChanged,
            ),
            const SizedBox(height: AppSpacing.sm),
            _Matches(
              matches: _matches,
              selected: _selected,
              searched: _searched,
              onSelect: (p) => setState(() => _selected = p),
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
                    message:
                        'Shared editing is not built yet — '
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
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          // Disabled until a person is picked: with two Daras on screen there is
          // no defensible "just share with whichever".
          onPressed: _busy || _selected == null ? null : _share,
          child:
              _busy
                  ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : const Text('Share'),
        ),
      ],
    );
  }
}

/// The candidate list. Bounded in height so a dialog with eight matches is the
/// same size as one with two, and scrollable inside that box at any text scale.
class _Matches extends StatelessWidget {
  const _Matches({
    required this.matches,
    required this.selected,
    required this.searched,
    required this.onSelect,
  });

  final List<Profile> matches;
  final Profile? selected;
  final bool searched;
  final ValueChanged<Profile> onSelect;

  @override
  Widget build(BuildContext context) {
    if (matches.isEmpty) {
      return searched
          ? const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Text('No user found with that name.'),
          )
          : const SizedBox.shrink();
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 220),
      // `RadioGroup` owns the selection now; `RadioListTile.groupValue` /
      // `onChanged` are deprecated in the pinned Flutter (3.44.8).
      child: RadioGroup<String>(
        groupValue: selected?.id,
        onChanged: (id) {
          if (id != null) {
            onSelect(matches.firstWhere((p) => p.id == id));
          }
        },
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: matches.length,
          itemBuilder: (context, i) {
            final person = matches[i];
            return RadioListTile<String>(
              value: person.id,
              dense: true,
              title: Text(
                person.displayName.isEmpty
                    ? 'Unnamed cook'
                    : person.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              // The tier is the only other thing the profile row carries that
              // tells two people with the same name apart.
              subtitle: Text(person.chefTier.label),
              secondary: ChefAvatar(
                name: person.displayName,
                avatarUrl: person.avatarUrl,
                radius: 16,
                tier: person.chefTier,
              ),
            );
          },
        ),
      ),
    );
  }
}
