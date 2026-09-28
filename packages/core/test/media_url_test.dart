import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stored cover values: absolute URLs pass through, keys resolve against the
/// configured project, and only a shown key under `ai/` is "generated".
void main() {
  tearDown(MediaUrl.reset);

  group('MediaUrl.resolve', () {
    test('an absolute URL passes through, configured or not', () {
      const url = 'https://example.test/a.jpg';
      expect(MediaUrl.resolve(url), url);
      MediaUrl.configure('http://127.0.0.1:54621');
      expect(MediaUrl.resolve(url), url);
    });

    test('a key resolves against the project, with or without a slash', () {
      MediaUrl.configure('http://127.0.0.1:54621/');
      expect(
        MediaUrl.resolve('ai/fresh-guacamole.jpg'),
        'http://127.0.0.1:54621/storage/v1/object/public/recipe-images/'
        'ai/fresh-guacamole.jpg',
      );
      MediaUrl.configure('https://ref.supabase.co');
      expect(
        MediaUrl.resolve('ai/x.jpg'),
        'https://ref.supabase.co/storage/v1/object/public/recipe-images/'
        'ai/x.jpg',
      );
    });

    test('unconfigured, a key is no cover rather than a URL on no host', () {
      expect(MediaUrl.resolve('ai/x.jpg'), isNull);
    });

    test('null and empty are no cover', () {
      MediaUrl.configure('http://h');
      expect(MediaUrl.resolve(null), isNull);
      expect(MediaUrl.resolve(''), isNull);
    });

    test('the bucket matches the one uploads go to', () {
      expect(MediaUrl.bucket, StorageService.recipeImagesBucket);
    });
  });

  group('Recipe cover', () {
    Recipe recipe(String? cover, {ImageMode mode = ImageMode.hotlink}) =>
        Recipe(
          id: 'r',
          ownerId: 'o',
          title: 't',
          coverImageUrl: cover,
          imageMode: mode,
        );

    test('a generated key shows, resolved, and is tagged', () {
      MediaUrl.configure('http://h');
      final r = recipe('ai/fresh-guacamole.jpg');
      expect(
        r.displayCoverImageUrl,
        'http://h/storage/v1/object/public/recipe-images/ai/fresh-guacamole.jpg',
      );
      expect(r.coverIsGenerated, isTrue);
    });

    test('an uploaded photo is never tagged', () {
      MediaUrl.configure('http://h');
      final r = recipe(
        'http://h/storage/v1/object/public/recipe-images/u1/ai/photo.jpg',
      );
      expect(r.coverIsGenerated, isFalse);
    });

    test('a cover the publisher withholds is neither shown nor tagged', () {
      MediaUrl.configure('http://h');
      final r = recipe('ai/x.jpg', mode: ImageMode.none);
      expect(r.displayCoverImageUrl, isNull);
      expect(r.coverIsGenerated, isFalse);
    });

    test('an unresolvable key is not tagged either', () {
      final r = recipe('ai/x.jpg');
      expect(r.displayCoverImageUrl, isNull);
      expect(r.coverIsGenerated, isFalse);
    });
  });
}
