import 'package:supabase_flutter/supabase_flutter.dart';

/// Thin wrapper around Supabase initialization and client access.
///
/// Credentials are provided at build time via `--dart-define` and must never be
/// committed to source control.
class SupabaseService {
  SupabaseService._();

  static const String _url = String.fromEnvironment('SUPABASE_URL');
  static const String _anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Initialize Supabase. Call once in `main()` before running the app.
  static Future<void> init() async {
    assert(
      _url.isNotEmpty && _anonKey.isNotEmpty,
      'Provide SUPABASE_URL and SUPABASE_ANON_KEY via --dart-define.',
    );
    // ignore: deprecated_member_use
    await Supabase.initialize(url: _url, anonKey: _anonKey);
  }

  static SupabaseClient get client => Supabase.instance.client;
}
