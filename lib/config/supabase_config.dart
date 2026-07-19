/// Supabase connection config.
///
/// Values are read from `--dart-define` at build time so nothing secret is
/// committed. Leaving them blank keeps the app in **mock/offline mode** — the
/// tracking screen falls back to the local simulation and no network calls are
/// made — so the app still builds and runs without a backend.
///
/// To go live:
///   flutter run --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
///               --dart-define=SUPABASE_ANON_KEY=eyJ...
class SupabaseConfig {
  const SupabaseConfig._();

  static const String url =
      String.fromEnvironment("SUPABASE_URL", defaultValue: "");
  static const String anonKey =
      String.fromEnvironment("SUPABASE_ANON_KEY", defaultValue: "");

  /// When false, the app runs entirely on local mock data.
  static bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;
}
