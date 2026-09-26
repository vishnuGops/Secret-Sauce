import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

/// The bucket's own `file_size_limit` (32a4), restated here because the client
/// has to know it: Storage refuses a larger upload at the API edge with a `413`
/// that reaches the app as a generic `StorageException`, and the picker cannot
/// prevent it on its own — the desktop `image_picker` implementations ignore
/// `maxWidth` outright, and Android re-encodes an alpha-bearing image as
/// lossless PNG. A caller that checks this before uploading turns a failed save
/// into a sentence about the file.
///
/// Mirrors `storage.buckets.file_size_limit` in `0001_init.sql` — change both
/// together, the same obligation `ChefScoring` carries for the score weights
/// (Gotcha 19).
const int kMaxUploadBytes = 5 * 1024 * 1024;

/// Handles image/file uploads to Supabase Storage.
///
/// Files are stored under a per-user folder (`<uid>/...`) so that storage RLS
/// policies restrict writes to the owner.
class StorageService {
  StorageService(this._client);

  final SupabaseClient _client;

  static const String recipeImagesBucket = 'recipe-images';
  static const String avatarsBucket = 'avatars';

  Future<String> uploadRecipeImage({
    required String fileName,
    required List<int> bytes,
    String contentType = 'image/jpeg',
  }) {
    return _upload(
      bucket: recipeImagesBucket,
      fileName: fileName,
      bytes: bytes,
      contentType: contentType,
    );
  }

  Future<String> uploadAvatar({
    required String fileName,
    required List<int> bytes,
    String contentType = 'image/jpeg',
  }) {
    return _upload(
      bucket: avatarsBucket,
      fileName: fileName,
      bytes: bytes,
      contentType: contentType,
    );
  }

  /// Deletes the avatar object at [publicUrl] **if it is the signed-in
  /// account's own** (B141) — and does nothing otherwise.
  ///
  /// A replaced or removed photo used to stay public at its old URL: Save only
  /// re-points `profiles.avatar_url`. The caller runs this after a successful
  /// profile write, with the URL the profile pointed at before it.
  ///
  /// "Own" is exactly what the `avatars deletable by owner folder` policy
  /// permits: an object in the `avatars` bucket of **this** project whose first
  /// folder is the current **auth uid** (not `profiles.id` — Phase 35b). A URL
  /// on another host, in another bucket, under another account's folder, or one
  /// that does not parse is left alone without a request: the server would
  /// refuse most of them anyway, but a delete this client did not mean to send
  /// is not one to leave to a policy. Signed out is a no-op too.
  ///
  /// Throws what `remove` throws; the caller treats it as best effort.
  Future<void> deleteOwnAvatar(String publicUrl) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return;
    final path = _ownObjectPath(avatarsBucket, publicUrl, uid);
    if (path == null) return;
    await _client.storage.from(avatarsBucket).remove([path]);
  }

  /// The object path inside [bucket] that [publicUrl] names, when it is this
  /// project's public URL for an object under `<uid>/`; null otherwise.
  ///
  /// The prefix is asked of the storage client rather than restated, so it is
  /// the same `<supabase url>/storage/v1/object/public/<bucket>/` that
  /// `getPublicUrl` produced when the object was uploaded.
  String? _ownObjectPath(String bucket, String publicUrl, String uid) {
    final url = Uri.tryParse(publicUrl);
    if (url == null || !url.hasAuthority) return null;
    // `getPublicUrl('x')` ends in `/<bucket>/x`; dropping the `x` leaves the
    // bucket's own prefix as path segments.
    final base = Uri.parse(_client.storage.from(bucket).getPublicUrl('x'));
    if (url.scheme != base.scheme ||
        url.host != base.host ||
        url.port != base.port) {
      return null;
    }
    final prefix = base.pathSegments.sublist(0, base.pathSegments.length - 1);
    final segments = url.pathSegments; // already percent-decoded
    if (segments.length < prefix.length + 2) return null; // `<uid>/<file>`
    for (var i = 0; i < prefix.length; i++) {
      if (segments[i] != prefix[i]) return null;
    }
    final object = segments.sublist(prefix.length);
    if (object.first != uid) return null;
    // An empty segment (`u1//a.jpg`, `u1/a.jpg/`) names no file. `Uri`
    // already resolves `.`/`..`; they are refused again so the rule does not
    // lean on that.
    if (object.any((s) => s.isEmpty || s == '.' || s == '..')) return null;
    return object.join('/');
  }

  /// The upload both public methods do (OPT-A7): they differed by bucket name
  /// and nothing else, twice over.
  ///
  /// The `<uid>/` prefix is not cosmetic — every storage policy on both buckets
  /// is `auth.uid()::text = (storage.foldername(name))[1]`, so a path built any
  /// other way is refused by the server rather than misfiled.
  Future<String> _upload({
    required String bucket,
    required String fileName,
    required List<int> bytes,
    required String contentType,
  }) async {
    final path = '${_requireUid()}/$fileName';
    final storage = _client.storage.from(bucket);
    await storage.uploadBinary(
      path,
      _toUint8(bytes),
      fileOptions: FileOptions(contentType: contentType, upsert: true),
    );
    return storage.getPublicUrl(path);
  }

  /// The signed-out guard, worded to match the mapper (32d4).
  ///
  /// `friendlyError` recognises `StateError` **by its message** — it looks for
  /// `Not authenticated`, which is what `SupabaseRecipeRepository._uid` throws
  /// (Gotcha 9). This threw a different sentence, so a signed-out upload fell
  /// through to "Something went wrong" instead of "You need to be signed in to
  /// do that". Same string, same prompt, one behaviour.
  String _requireUid() {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) {
      throw StateError('Not authenticated.');
    }
    return uid;
  }

  Uint8List _toUint8(List<int> bytes) =>
      bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
}
