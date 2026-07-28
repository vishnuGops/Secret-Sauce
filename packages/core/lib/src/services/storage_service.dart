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
  }) async {
    final uid = _requireUid();
    final path = '$uid/$fileName';
    await _client.storage.from(recipeImagesBucket).uploadBinary(
          path,
          _toUint8(bytes),
          fileOptions: FileOptions(contentType: contentType, upsert: true),
        );
    return _client.storage.from(recipeImagesBucket).getPublicUrl(path);
  }

  Future<String> uploadAvatar({
    required String fileName,
    required List<int> bytes,
    String contentType = 'image/jpeg',
  }) async {
    final uid = _requireUid();
    final path = '$uid/$fileName';
    await _client.storage.from(avatarsBucket).uploadBinary(
          path,
          _toUint8(bytes),
          fileOptions: FileOptions(contentType: contentType, upsert: true),
        );
    return _client.storage.from(avatarsBucket).getPublicUrl(path);
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
