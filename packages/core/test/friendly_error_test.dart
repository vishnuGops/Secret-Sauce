// OPT-A4: screens render `friendlyError(e)`, so this function is the only thing
// standing between a PostgREST error object and the user's screen. The property
// that matters is not which sentence comes back — it is that a raw exception
// dump never does.
import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('a denied write reads as the exception s own sentence, not its class',
      () {
    const e = WriteDeniedException('save this recipe', detail: 'recipe abc');
    final text = friendlyError(e);

    expect(text, contains('Could not save this recipe'));
    expect(text, isNot(contains('WriteDeniedException')));
    // The detail is for the log, not the screen.
    expect(text, isNot(contains('recipe abc')));
  });

  test('42501 is the permission sentence, not "permission denied for table"',
      () {
    final text = friendlyError(
      const PostgrestException(
        message: 'permission denied for table recipes',
        code: '42501',
      ),
    );

    expect(text, 'You do not have permission to do that.');
  });

  test('a single() that found nothing reads as not found', () {
    final text = friendlyError(
      const PostgrestException(message: 'JSON object requested', code: 'PGRST116'),
    );

    expect(text, contains('could not be found'));
  });

  test('an unmapped Postgrest code falls back without leaking the payload', () {
    final text = friendlyError(
      const PostgrestException(
        message: 'syntax error at or near "select"',
        code: '42601',
      ),
    );

    expect(text, 'Something went wrong. Please try again.');
    expect(text, isNot(contains('syntax error')));
  });

  test('auth messages are passed through — GoTrue already writes them for users',
      () {
    expect(
      friendlyError(const AuthException('Invalid login credentials')),
      'Invalid login credentials',
    );
  });

  test('the signed-out StateError points at signing in (Gotcha 9)', () {
    expect(
      friendlyError(StateError('Not authenticated.')),
      'You need to be signed in to do that.',
    );
  });

  test('a timeout reads as a connection problem', () {
    expect(friendlyError(TimeoutException('nope')), contains('connection'));
  });

  test('null and unknown objects still produce a sentence', () {
    expect(friendlyError(null), 'Something went wrong. Please try again.');
    expect(friendlyError(Object()), 'Something went wrong. Please try again.');
  });
}
