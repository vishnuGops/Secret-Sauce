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
