import 'dart:async' show TimeoutException;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthException, PostgrestException, StorageException;

import 'package:core/src/repositories/write_denied_exception.dart';

/// Turns whatever a repository threw into one sentence a reader can act on
/// (OPT-A4).
///
/// Screens used to render `e.toString()` straight into an `ErrorView` or a
/// snackbar, so a denied save read as
/// `PostgrestException(message: permission denied for table recipes, code:
/// 42501, details: , hint: null)` and a dropped connection read as
/// `ClientException with SocketException: Connection refused …`. Neither tells
/// the reader what to do, and both leak schema detail into the UI.
///
/// The raw error still goes to the console — this is the only place that
/// translates, so it is also the only place that has to log.
String friendlyError(Object? error) {
  debugPrint('friendlyError: $error');

  if (error == null) return _generic;

  if (error is WriteDeniedException) return error.message;

  if (error is PostgrestException) return _postgrest(error);

  // Supabase's auth messages are already written for end users ("Invalid login
  // credentials", "User already registered"), so they are passed through rather
  // than re-mapped — a switch over them would go stale silently every time
  // GoTrue rewords one.
  if (error is AuthException) return error.message;

  if (error is StorageException) {
    return 'That image could not be uploaded. Try a different file.';
  }

  // `SupabaseRecipeRepository._uid` throws this when signed out (Gotcha 9).
  if (error is StateError && error.message.contains('Not authenticated')) {
    return 'You need to be signed in to do that.';
  }

  if (_isNetwork(error)) {
    return 'Cannot reach the server. Check your connection and try again.';
  }

  return _generic;
}

const _generic = 'Something went wrong. Please try again.';

String _postgrest(PostgrestException e) {
  switch (e.code) {
    // Column- or table-level grant refused the statement. Since OPT-S1 this is
    // also what a client write to a server-owned column looks like.
    case '42501':
      return 'You do not have permission to do that.';
    case '23505':
      return 'That already exists.';
    case '23503':
      return 'Something this refers to no longer exists.';
    case '23514':
      return 'Some of that information is not valid.';
    // `.single()` found no row — usually a deleted or private recipe.
    case 'PGRST116':
      return 'That could not be found.';
    case 'PGRST301':
      return 'Your session expired. Sign in again.';
    // The function is missing from the database, not from the request: an app
    // built against a schema the project has not had applied yet.
    case 'PGRST202':
      return 'This feature is not available on the server yet.';
    default:
      return _generic;
  }
}

/// Network failures cross an awkward platform line: `SocketException` lives in
/// `dart:io`, which does not exist on web, and `http`'s `ClientException` is a
/// transitive dependency this package does not declare. Matching the type name
/// keeps one implementation for both platforms without importing either.
bool _isNetwork(Object error) {
  if (error is TimeoutException) return true;
  final name = error.runtimeType.toString();
  return name == 'SocketException' ||
      name == 'ClientException' ||
      name == 'HandshakeException' ||
      name == 'HttpException';
}
