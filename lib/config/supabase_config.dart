import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Supabase connection config.
///
/// Resolution order for each value:
///   1. `--dart-define` (compile-time) — wins, useful for CI / release builds.
///   2. `.env` (runtime, loaded in `main()`) — convenient for local dev.
///   3. empty -> the app stays in **offline mode**: no network calls, and
///      screens that need live railway data say so honestly instead of
///      showing mock/substituted data.
///
/// Only PUBLIC values belong here. `.env` is bundled as a Flutter asset
/// (see pubspec.yaml), so it is readable by anyone who downloads the app.
/// The anon key is safe by design — it's guarded by Row Level Security, not by
/// secrecy. Privileged keys (RailKit, service-role) live ONLY as Supabase
/// Edge Function secrets and must never appear in this file or in `.env`.
///
/// To go live:
///   flutter run --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
///               --dart-define=SUPABASE_ANON_KEY=eyJ...
/// ...or just put those two keys in `.env` and run `flutter run`.
class SupabaseConfig {
  const SupabaseConfig._();

  static const String _urlDefine =
      String.fromEnvironment("SUPABASE_URL", defaultValue: "");
  static const String _anonKeyDefine =
      String.fromEnvironment("SUPABASE_ANON_KEY", defaultValue: "");

  /// Reads from .env without throwing when dotenv hasn't loaded (e.g. tests).
  static String _fromEnvFile(String key) {
    try {
      return dotenv.env[key]?.trim() ?? '';
    } catch (_) {
      return '';
    }
  }

  static String get url =>
      _urlDefine.isNotEmpty ? _urlDefine : _fromEnvFile('SUPABASE_URL');

  static String get anonKey => _anonKeyDefine.isNotEmpty
      ? _anonKeyDefine
      : _fromEnvFile('SUPABASE_ANON_KEY');

  /// When false, the app runs entirely offline (no backend calls).
  static bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;
}
