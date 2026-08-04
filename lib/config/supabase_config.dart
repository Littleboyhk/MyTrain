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

  static const String _defaultUrl = "https://mokxoomaujfuhusxbojx.supabase.co";
  static const String _defaultAnonKey =
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1va3hvb21hdWpmdWh1c3hib2p4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQ0NTE5MzEsImV4cCI6MjEwMDAyNzkzMX0.qaKsihNfiHeRq95mGGxV5wjMAOjG3sYcz417L-YATA8";

  /// Reads from .env without throwing when dotenv hasn't loaded (e.g. tests).
  static String _fromEnvFile(String key) {
    try {
      return dotenv.env[key]?.trim() ?? '';
    } catch (_) {
      return '';
    }
  }

  static String get url {
    if (_urlDefine.isNotEmpty) return _urlDefine;
    final envVal = _fromEnvFile('SUPABASE_URL');
    return envVal.isNotEmpty ? envVal : _defaultUrl;
  }

  static String get anonKey {
    if (_anonKeyDefine.isNotEmpty) return _anonKeyDefine;
    final envVal = _fromEnvFile('SUPABASE_ANON_KEY');
    return envVal.isNotEmpty ? envVal : _defaultAnonKey;
  }

  /// When false, the app runs entirely offline (no backend calls).
  static bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;
}
