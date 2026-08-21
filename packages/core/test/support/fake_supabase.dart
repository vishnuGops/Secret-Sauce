// A `SupabaseClient` whose HTTP layer is a recorder (OPT-T2).
//
// The blocker on repository tests was always "mocking SupabaseClient" — a large
// surface with a `final` API. This goes under it instead: `SupabaseClient`
// accepts an `httpClient`, so a `BaseClient` that records the request and
// replies from a queue turns every repository method into something a plain
// `flutter test` can assert on, with no new dependency and no live database.
//
// The contract this pins is **what the repository asks for**: the URL, the
// `select` fragment, the ordering parameters, the page window, the RPC body.
// That is exactly where this repo's read-path bugs have lived — B022 was a
// missing `ascending: true`, OPT-P3 was N requests where one belongs, and the
// `kRecipeSelect` FK hint breaks every recipe query at once when it is dropped.
//
// What it deliberately does not do is emulate PostgREST. A response is canned,
// so a test can prove the client's half of the conversation and the decode, not
// that Postgres would agree.
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// One recorded outgoing request, reduced to what a test wants to assert.
class RecordedRequest {
  RecordedRequest(this.method, this.url, this.headers, this.body);

  final String method;
  final Uri url;
  final Map<String, String> headers;
  final String body;

  /// The decoded `select=` parameter, or null when the request had none.
  String? get select => url.queryParameters['select'];

  /// The `order=` value for the base table. Several `.order()` calls on one
  /// table arrive comma-joined in a single parameter.
  String? get order => url.queryParameters['order'];

  /// The `order=` for an **embedded** table, which PostgREST namespaces:
  /// `ingredient_groups.ingredients.order=sort_order.asc`. B022's four calls
  /// produce four separate parameters, not one repeated one.
  String? orderOn(String table) => url.queryParameters['$table.order'];

  String? param(String name) => url.queryParameters[name];

  Map<String, dynamic> get json =>
      jsonDecode(body) as Map<String, dynamic>;
}

/// Replies to every request from [responses], in order, and records what was
/// asked. Runs out of responses -> the test fails loudly rather than hanging.
class RecordingHttpClient extends http.BaseClient {
  RecordingHttpClient(this.responses);

  /// `(statusCode, body)` pairs, consumed front to back.
  final List<(int, String)> responses;
  final List<RecordedRequest> requests = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body =
        request is http.Request ? request.body : '<${request.runtimeType}>';
    requests.add(
      RecordedRequest(request.method, request.url, request.headers, body),
    );

    if (responses.isEmpty) {
      throw StateError(
        'Unexpected request ${request.method} ${request.url} — the test queued '
        'no response for it.',
      );
    }
    final (status, payload) = responses.removeAt(0);
    return http.StreamedResponse(
      Stream.value(utf8.encode(payload)),
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
      request: request,
    );
  }
}

/// A client pointed at a URL nothing listens on — every request is intercepted.
SupabaseClient fakeSupabase(RecordingHttpClient http) {
  return SupabaseClient(
    'http://localhost:1',
    'test-anon-key',
    httpClient: http,
    authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit),
  );
}

/// Puts [client] into a signed-in state **offline**.
///
/// `recoverSession` rebuilds a session from JSON and only touches the network
/// when the session has expired, so an unexpired one signs in without a round
/// trip. That is what lets the `_uid`-dependent methods (`listMine`,
/// `setRating`, …) be tested at all.
Future<void> signInAs(SupabaseClient client, String userId) async {
  final expiresAt =
      DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000;
  await client.auth.recoverSession(
    jsonEncode({
      'access_token': 'fake-access-token',
      'token_type': 'bearer',
      'expires_in': 3600,
      'expires_at': expiresAt,
      'refresh_token': 'fake-refresh-token',
      'user': {
        'id': userId,
        'aud': 'authenticated',
        'role': 'authenticated',
        'email': 'cook@example.test',
        'app_metadata': <String, dynamic>{},
        'user_metadata': <String, dynamic>{},
        'created_at': DateTime.now().toIso8601String(),
      },
    }),
  );
}
