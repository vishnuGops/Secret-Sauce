/// Turns a stored image value into a URL a widget can load.
///
/// A cover column holds one of two things. Everything written before this —
/// an upload's `getPublicUrl`, an imported recipe's hotlink — is an absolute
/// `http(s)` URL and passes through untouched. A **key** (`ai/<slug>.jpg`) is
/// an object in the `recipe-images` bucket of whichever project the app is
/// pointed at, so the same seed row works on the local stack and on hosted:
/// the database stores where the file is, the client supplies which server.
/// That is BL-11's "store keys, not URLs", in the one place that needs it now.
///
/// Configured once, from [SupabaseService.init]. Unconfigured (a widget test
/// that never initialises Supabase), a key resolves to null — the caller's
/// no-photo state — rather than to a URL on no host.
abstract final class MediaUrl {
  static String? _publicBase;

  /// Bucket every stored key lives in. Mirrors
  /// `StorageService.recipeImagesBucket`.
  static const String bucket = 'recipe-images';

  /// Key prefix of a **generated** image (DESIGN §2.2). Only the service role
  /// can write under it — every upload policy on the bucket requires the first
  /// folder to be the uploader's auth uid — so a value under `ai/` names a
  /// file tool/recipe_covers.dart made and `covers:upload` put there.
  static const String generatedPrefix = 'ai/';

  /// Points keys at [supabaseUrl]'s public Storage endpoint.
  static void configure(String supabaseUrl) {
    final base =
        supabaseUrl.endsWith('/')
            ? supabaseUrl.substring(0, supabaseUrl.length - 1)
            : supabaseUrl;
    _publicBase = '$base/storage/v1/object/public/$bucket/';
  }

  /// Test-only: forget [configure].
  static void reset() => _publicBase = null;

  /// The loadable URL for [stored], or null when there is nothing to load.
  static String? resolve(String? stored) {
    if (stored == null || stored.isEmpty) return null;
    if (stored.startsWith('http://') || stored.startsWith('https://')) {
      return stored;
    }
    final base = _publicBase;
    if (base == null) return null;
    return '$base$stored';
  }

  /// Whether [stored] is a generated image — the key form under
  /// [generatedPrefix]. An absolute URL never is: nothing we did not make is
  /// labelled as made by us.
  static bool isGenerated(String? stored) =>
      stored != null && stored.startsWith(generatedPrefix);
}
