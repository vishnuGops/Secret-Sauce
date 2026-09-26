import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

/// Picks one image from the device gallery and returns its bytes, or null when
/// the user backed out.
typedef ImagePickFn = Future<Uint8List?> Function();

/// The gallery pick, behind a provider.
///
/// What every image pick says when it is over the bucket's limit — the editor's
/// cover and step photos and the profile's avatar. Derived from
/// [kMaxUploadBytes] rather than restating the number: the limit has one source
/// of truth (32a4), and a second literal is how the two surfaces drift.
const String kImageTooLargeMessage =
    'That image is over ${kMaxUploadBytes ~/ (1024 * 1024)} MB. '
    'Please pick a smaller one.';

/// One function for the cover tile and every step photo — the two used to be
/// one method with the cover's `setState` welded onto it, and a second copy is
/// how the size guard and the error path start disagreeing.
///
/// It is a provider rather than a plain function so the editor's tests can hand
/// the screen bytes: `image_picker` is a platform channel, and there is no
/// headless device photo pick on any machine this repo is developed on. The
/// guard rail (5 MB, `kMaxUploadBytes`) and the error message stay in the
/// screen, so overriding this in a test still exercises both.
final imagePickerProvider = Provider<ImagePickFn>(
  (ref) => pickImageFromGallery,
);

/// The real implementation. `maxWidth`/`imageQuality` shrink the common case
/// before the caller's size guard ever fires; they are an optional complement,
/// not the guard — the desktop pickers ignore every option they are given.
Future<Uint8List?> pickImageFromGallery() async {
  final picked = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    maxWidth: 1600,
    imageQuality: 85,
  );
  return picked?.readAsBytes();
}
