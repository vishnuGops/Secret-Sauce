// `StorageService.deleteOwnAvatar` (B141): a replaced or removed profile photo
// stayed public at its old URL, because Save only re-points `avatar_url`.
//
// Same harness as the repository suites — a recording `http.BaseClient` under a
// real `SupabaseClient` — so these pin the request the service sends (and, as
// much, the requests it must NOT send), never that the storage policy agrees.
import 'dart:convert';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import 'support/fake_supabase.dart';

const _uid = 'u1';

/// `fakeSupabase` points at `http://localhost:1`, so this is the prefix
/// `getPublicUrl` produces for the avatars bucket.
const _avatars = 'http://localhost:1/storage/v1/object/public/avatars';

({RecordingHttpClient http, SupabaseClient client, StorageService storage})
_service(List<(int, String)> responses) {
  final http = RecordingHttpClient(responses);
  final client = fakeSupabase(http);
  return (http: http, client: client, storage: StorageService(client));
}

/// What Storage answers a `remove`: the objects it deleted.
final _removed = (200, jsonEncode(<Object>[]));

void main() {
  group('deleteOwnAvatar (B141)', () {
    test('an own-folder URL deletes that object from avatars', () async {
      final (:http, :client, :storage) = _service([_removed]);
      await signInAs(client, _uid);

      await storage.deleteOwnAvatar('$_avatars/$_uid/avatar_1.jpg');

      final req = http.requests.single;
      expect(req.method, 'DELETE');
      expect(req.url.path, '/storage/v1/object/avatars');
      expect(req.json['prefixes'], ['$_uid/avatar_1.jpg']);
    });

    test('the URL uploadAvatar returned is the object it deletes', () async {
      final (:http, :client, :storage) = _service([
        (200, jsonEncode({'Key': 'avatars/$_uid/my photo.jpg'})),
        _removed,
      ]);
      await signInAs(client, _uid);

      // A space in the name: the public URL percent-encodes it, and the
      // delete has to name the object, not the encoding.
      final url = await storage.uploadAvatar(
        fileName: 'my photo.jpg',
        bytes: const [1, 2, 3],
      );
      await storage.deleteOwnAvatar(url);

      expect(http.requests, hasLength(2));
      expect(http.requests.last.json['prefixes'], ['$_uid/my photo.jpg']);
    });

    test('a query string on the URL does not reach the path', () async {
      final (:http, :client, :storage) = _service([_removed]);
      await signInAs(client, _uid);

      await storage.deleteOwnAvatar('$_avatars/$_uid/a.jpg?v=2');

      expect(http.requests.single.json['prefixes'], ['$_uid/a.jpg']);
    });

    for (final (why, url) in <(String, String)>[
      ("another account's folder", '$_avatars/someone-else/avatar_1.jpg'),
      (
        'the recipe-images bucket',
        'http://localhost:1/storage/v1/object/public/recipe-images/$_uid/a.jpg',
      ),
      (
        'a foreign host with the same path',
        'https://cdn.example.test/storage/v1/object/public/avatars/$_uid/a.jpg',
      ),
      (
        'a different port',
        'http://localhost:2/storage/v1/object/public/avatars/$_uid/a.jpg',
      ),
      ('the uid as a bare file, no folder', '$_avatars/$_uid'),
      ('a folder that only starts with the uid', '$_avatars/${_uid}x/a.jpg'),
      // `Uri` resolves dot segments itself, so this one climbs out of the
      // uid folder before the service sees it — and is refused for that.
      ('a dot-dot segment', '$_avatars/$_uid/%2E%2E/a.jpg'),
      ('an empty segment', '$_avatars/$_uid//a.jpg'),
      ('a trailing slash (a folder, not a file)', '$_avatars/$_uid/a.jpg/'),
      ('a relative URL', '/storage/v1/object/public/avatars/$_uid/a.jpg'),
      ('not a URL at all', 'http://[::1'),
      ('an empty string', ''),
    ]) {
      test('$why: no request at all', () async {
        // No response queued: any request fails the test loudly.
        final (:http, :client, :storage) = _service([]);
        await signInAs(client, _uid);

        await storage.deleteOwnAvatar(url);

        expect(http.requests, isEmpty);
      });
    }

    test('signed out: no request at all', () async {
      final (:http, :client, :storage) = _service([]);

      await storage.deleteOwnAvatar('$_avatars/$_uid/avatar_1.jpg');

      expect(http.requests, isEmpty);
    });

    test(
      'a refused delete throws to the caller, which owns best effort',
      () async {
        final (:http, :client, :storage) = _service([
          (403, jsonEncode({'statusCode': '403', 'message': 'denied'})),
        ]);
        await signInAs(client, _uid);

        await expectLater(
          storage.deleteOwnAvatar('$_avatars/$_uid/avatar_1.jpg'),
          throwsA(isA<Exception>()),
        );
      },
    );
  });
}
