import 'dart:async';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app/features/recipe_editor/recipe_editor_providers.dart';

/// `profiles_text_lengths` in `0001_init.sql`: `char_length(display_name) <= 80`.
/// Mirrored so the field stops the reader instead of the check constraint
/// refusing the save.
const int kProfileDisplayNameMaxLength = 80;

/// The same constraint's `char_length(bio) <= 500`.
const int kProfileBioMaxLength = 500;

/// The dialog's width on medium and wider; compact opens full-screen instead.
const double _kDialogWidth = 440;

/// The avatar preview in the form (72 wide).
const double _kAvatarRadius = 36;

/// The spinner inside the Save button while a save is in flight.
const double _kSpinnerSize = AppIconSize.sm;
const double _kSpinnerStroke = AppStroke.thin;

/// Opens the profile editor (UX-038). Resolves to true when a save landed.
///
/// `useRootNavigator: true` because `/profile` is a shell screen: a default
/// dialog attaches below the shell's chrome, so the top bar stays undimmed on
/// web and the bottom bar paints over a full-screen dialog on a phone
/// (Gotcha 23, B030).
Future<bool?> showEditProfileDialog(BuildContext context, Profile profile) {
  return showDialog<bool>(
    context: context,
    useRootNavigator: true,
    builder: (_) => EditProfileDialog(profile: profile),
  );
}

/// Name, bio and photo — the three columns a member may write on their own
/// `profiles` row (the column grants in `0001_init.sql`; everything else there
/// is server-owned).
///
/// A picked photo is held as **bytes** until Save, exactly like the recipe
/// editor's cover: an abandoned edit uploads nothing, so it leaves no orphan
/// object in the `avatars` bucket.
class EditProfileDialog extends ConsumerStatefulWidget {
  const EditProfileDialog({super.key, required this.profile});

  final Profile profile;

  @override
  ConsumerState<EditProfileDialog> createState() => _EditProfileDialogState();
}

class _EditProfileDialogState extends ConsumerState<EditProfileDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name = TextEditingController(
    text: widget.profile.displayName,
  );
  late final TextEditingController _bio = TextEditingController(
    text: widget.profile.bio ?? '',
  );

  /// A photo picked in this dialog and not yet stored.
  Uint8List? _pendingBytes;

  /// The public URL [_pendingBytes] was uploaded to. Kept so a save whose
  /// profile write fails after the upload landed does not upload the same file
  /// again on the retry; cleared by the next pick.
  String? _uploadedUrl;

  /// The stored photo was removed in this dialog (and nothing picked since).
  bool _removed = false;

  /// Photos this dialog uploaded that the profile never came to point at
  /// (B146): an upload whose profile write failed and was then replaced or
  /// removed, or one left behind by closing the dialog. B141's cleanup never
  /// sees them — it deletes the photo the profile *used* to point at — so
  /// they are deleted here, best effort, once the dialog knows they are
  /// strays: after a successful save, or when it closes without one.
  final Set<String> _strayUploads = {};

  /// Whether a save landed. Decides what closing the dialog cleans up.
  bool _saved = false;

  /// Captured while the element is active: `dispose` may not look it up.
  ProviderContainer? _container;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _container = ProviderScope.containerOf(context, listen: false);
  }

  /// Moves the current upload, if any, onto [_strayUploads].
  void _forgetUpload() {
    final url = _uploadedUrl;
    if (url != null) _strayUploads.add(url);
    _uploadedUrl = null;
  }

  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    // Closed without a save: nothing this dialog uploaded is on the profile.
    final container = _container;
    if (!_saved && container != null) {
      _forgetUpload();
      for (final url in _strayUploads) {
        unawaited(_deletePreviousAvatar(container, url));
      }
    }
    _name.dispose();
    _bio.dispose();
    super.dispose();
  }

  bool get _hasStoredPhoto =>
      !_removed && (widget.profile.avatarUrl?.isNotEmpty ?? false);

  bool get _hasPhoto => _pendingBytes != null || _hasStoredPhoto;

  Future<void> _pick() async {
    final Uint8List? bytes;
    try {
      bytes = await ref.read(imagePickerProvider)();
    } catch (e) {
      // A denied permission is a sentence, never a raw platform exception.
      if (mounted) setState(() => _error = friendlyError(e));
      return;
    }
    if (bytes == null || !mounted) return;
    // The bucket's `file_size_limit` (32a4). Checked where the file was chosen,
    // so the refusal names the size instead of failing the save later.
    if (bytes.length > kMaxUploadBytes) {
      setState(() => _error = kImageTooLargeMessage);
      return;
    }
    setState(() {
      _pendingBytes = bytes;
      _forgetUpload();
      _removed = false;
      _error = null;
    });
  }

  void _removePhoto() => setState(() {
    _pendingBytes = null;
    _forgetUpload();
    _removed = true;
    _error = null;
  });

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    // Captured before the first await (B140): the dialog can be gone by the
    // time the save returns, and a dead `ref` would throw out of the success
    // path — after the write landed. Storage is read from it lazily: a save
    // that touches no photo never builds the storage client.
    final container = ProviderScope.containerOf(context, listen: false);
    final profiles = container.read(profileRepositoryProvider);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final previousUrl = widget.profile.avatarUrl;
      var avatarUrl = _removed ? null : previousUrl;
      final pending = _pendingBytes;
      if (pending != null) {
        // The storage path is `<auth uid>/<fileName>` (StorageService — the
        // bucket policies are keyed on the auth uid, not `profiles.id`). A
        // timestamped name, because `upsert` on a fixed one would keep serving
        // the old photo from every cache that already holds its URL.
        _uploadedUrl ??= await container
            .read(storageServiceProvider)
            .uploadAvatar(
              fileName: 'avatar_${DateTime.now().millisecondsSinceEpoch}.jpg',
              bytes: pending,
            );
        avatarUrl = _uploadedUrl;
      }
      final bio = _bio.text.trim();
      await profiles.updateMine(
        widget.profile.copyWith(
          displayName: _name.text.trim(),
          bio: bio.isEmpty ? null : bio,
          avatarUrl: avatarUrl,
        ),
      );
      // B141: the photo the profile pointed at until this write stays public
      // unless it is removed. Only now — a failed save must leave the object
      // the profile still points at — and only when the photo actually moved.
      // Not awaited: the save has landed, and closing the dialog should not
      // wait on a cleanup the reader cannot see.
      if (previousUrl != null &&
          previousUrl.isNotEmpty &&
          previousUrl != avatarUrl) {
        unawaited(_deletePreviousAvatar(container, previousUrl));
      }
      // B146: uploads from earlier failed attempts that this save replaced.
      _saved = true;
      for (final url in _strayUploads) {
        if (url != avatarUrl) {
          unawaited(_deletePreviousAvatar(container, url));
        }
      }
      _strayUploads.clear();
      // One read feeds this screen and the web avatar menu; refreshing it is
      // what moves both to the new name at once.
      container.invalidate(myProfileProvider);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      // The dialog stays open with what the reader typed, so a failed save is
      // a retry rather than a re-type.
      if (mounted) {
        setState(() {
          _saving = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  /// Best effort (B141). The profile no longer points at [url], so a failure
  /// here costs an orphan object, not the save: it is logged through
  /// `friendlyError` and never shown. `deleteOwnAvatar` itself leaves any URL
  /// outside this account's `avatars/<auth uid>/` folder alone — a photo set
  /// some other way (an external URL) is not ours to delete.
  ///
  /// The storage read is inside the `try` too: nothing about the cleanup may
  /// throw back into a save that has already succeeded.
  static Future<void> _deletePreviousAvatar(
    ProviderContainer container,
    String url,
  ) async {
    try {
      await container.read(storageServiceProvider).deleteOwnAvatar(url);
    } catch (e) {
      friendlyError(e); // logs; the sentence is deliberately discarded
    }
  }

  String? _validateName(String? value) {
    final name = (value ?? '').trim();
    if (name.isEmpty) return 'Enter a display name';
    // `maxLength` counts what the reader sees (grapheme clusters); Postgres's
    // `char_length` counts code points, so a family emoji is one to the field
    // and several to the constraint. Checked here rather than refused there.
    if (name.runes.length > kProfileDisplayNameMaxLength) {
      return 'Keep it under $kProfileDisplayNameMaxLength characters';
    }
    return null;
  }

  String? _validateBio(String? value) =>
      (value ?? '').trim().runes.length > kProfileBioMaxLength
          ? 'Keep it under $kProfileBioMaxLength characters'
          : null;

  Widget _saveButton() => FilledButton(
    onPressed: _saving ? null : _save,
    child:
        _saving
            ? const SizedBox.square(
              dimension: _kSpinnerSize,
              child: CircularProgressIndicator(strokeWidth: _kSpinnerStroke),
            )
            : const Text('Save'),
  );

  Widget _form(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final profile = widget.profile;

    final Widget avatar =
        _pendingBytes != null
            ? ClipOval(
              child: Image.memory(
                _pendingBytes!,
                width: _kAvatarRadius * 2,
                height: _kAvatarRadius * 2,
                fit: BoxFit.cover,
                semanticLabel: 'New profile photo',
              ),
            )
            : ChefAvatar(
              name: _name.text.isEmpty ? profile.displayName : _name.text,
              avatarUrl: _hasStoredPhoto ? profile.avatarUrl : null,
              radius: _kAvatarRadius,
              backgroundColor: scheme.primaryContainer,
              foregroundColor: scheme.onPrimaryContainer,
            );

    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // A Wrap, not a Row: at 2.0x on a phone the two photo buttons do
          // not fit beside the circle, and they drop under it instead of
          // overflowing (Gotcha 21/26).
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              avatar,
              OutlinedButton.icon(
                onPressed: _saving ? null : _pick,
                icon: const Icon(Icons.photo_camera_outlined),
                label: Text(_hasPhoto ? 'Change photo' : 'Add photo'),
              ),
              if (_hasPhoto)
                TextButton.icon(
                  onPressed: _saving ? null : _removePhoto,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Remove photo'),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          TextFormField(
            controller: _name,
            enabled: !_saving,
            maxLength: kProfileDisplayNameMaxLength,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.name],
            decoration: const InputDecoration(labelText: 'Display name'),
            validator: _validateName,
            // Rebuild so the initials preview follows the name being typed.
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            controller: _bio,
            enabled: !_saving,
            maxLength: kProfileBioMaxLength,
            minLines: 3,
            maxLines: 6,
            keyboardType: TextInputType.multiline,
            decoration: const InputDecoration(
              labelText: 'Bio',
              hintText: 'A line or two about how you cook',
              alignLabelWithHint: true,
            ),
            validator: _validateBio,
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Semantics(
              liveRegion: true,
              child: Text(
                _error!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.error,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // A save in flight cannot be dismissed out from under itself.
    final body = PopScope(canPop: !_saving, child: _form(context));

    if (context.isCompact) {
      return Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            leading: IconButton(
              tooltip: 'Cancel',
              icon: const Icon(Icons.close),
              onPressed: _saving ? null : () => Navigator.of(context).pop(),
            ),
            title: const Text('Edit profile'),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.sm),
                child: _saveButton(),
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: body,
          ),
        ),
      );
    }

    return AlertDialog(
      // Scrollable so 2.0x text on a short window scrolls instead of
      // overflowing the dialog.
      scrollable: true,
      title: const Text('Edit profile'),
      content: SizedBox(width: _kDialogWidth, child: body),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        _saveButton(),
      ],
    );
  }
}
