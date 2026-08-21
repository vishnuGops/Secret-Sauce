import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

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

  String _requireUid() {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) {
      throw StateError('Must be signed in to upload files.');
    }
    return uid;
  }

  Uint8List _toUint8(List<int> bytes) =>
      bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
}
