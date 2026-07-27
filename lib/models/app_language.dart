import 'dart:ui' show Locale;

/// A language the user can pick for the app.
///
/// Selecting one persists the choice AND re-renders the whole app in that
/// locale: `main.dart` feeds [locale] to `MaterialApp`, and translations live in
/// `lib/l10n/*.arb` (generated into `app_localizations_*.dart`). Keys missing
/// from a translated .arb fall back to English automatically.
///
/// Glyph coverage for these scripts is NOT automatic — Roboto has none of them.
/// The Noto Sans faces bundled in `pubspec.yaml` and wired up as
/// `AppTheme.indicFontFallback` are what stop this text rendering as tofu boxes.
/// Adding a language in a new script means adding its Noto face too.
///
/// [script] is a single letter written in the language's own script, used as
/// the tile glyph (like Where Is My Train's picker). [endonym] is the language
/// name written in its own script.
class AppLanguage {
  const AppLanguage({
    required this.code,
    required this.english,
    required this.endonym,
    required this.script,
  });

  /// ISO 639-1 code, also the value persisted to storage.
  final String code;

  /// English name, for accessibility labels and debugging.
  final String english;

  /// Native name, e.g. "മലയാളം".
  final String endonym;

  /// Single glyph in the native script, e.g. "അ".
  final String script;

  Locale get locale => Locale(code);

  /// Supported languages, in display order. English first, then Hindi, then
  /// Malayalam (Kerala is the primary user base), then the rest.
  static const List<AppLanguage> all = [
    AppLanguage(code: 'en', english: 'English', endonym: 'English', script: 'A'),
    AppLanguage(code: 'hi', english: 'Hindi', endonym: 'हिंदी', script: 'अ'),
    AppLanguage(
        code: 'ml', english: 'Malayalam', endonym: 'മലയാളം', script: 'അ'),
    AppLanguage(code: 'ta', english: 'Tamil', endonym: 'தமிழ்', script: 'அ'),
    AppLanguage(code: 'kn', english: 'Kannada', endonym: 'ಕನ್ನಡ', script: 'ಅ'),
    AppLanguage(code: 'te', english: 'Telugu', endonym: 'తెలుగు', script: 'అ'),
    AppLanguage(code: 'bn', english: 'Bengali', endonym: 'বাংলা', script: 'অ'),
    AppLanguage(code: 'mr', english: 'Marathi', endonym: 'मराठी', script: 'अ'),
    AppLanguage(
        code: 'gu', english: 'Gujarati', endonym: 'ગુજરાતી', script: 'અ'),
    AppLanguage(code: 'pa', english: 'Punjabi', endonym: 'ਪੰਜਾਬੀ', script: 'ਅ'),
    AppLanguage(code: 'or', english: 'Odia', endonym: 'ଓଡ଼ିଆ', script: 'ଅ'),
    AppLanguage(code: 'as', english: 'Assamese', endonym: 'অসমীয়া', script: 'অ'),
  ];

  static const AppLanguage english_ = AppLanguage(
    code: 'en',
    english: 'English',
    endonym: 'English',
    script: 'A',
  );

  /// Look up by stored code; falls back to English when unknown/absent.
  static AppLanguage fromCode(String? code) {
    if (code == null) return english_;
    for (final l in all) {
      if (l.code == code) return l;
    }
    return english_;
  }

  /// Best match for a device locale, or English when unsupported.
  static AppLanguage fromLocale(Locale locale) =>
      fromCode(locale.languageCode.toLowerCase());

  @override
  bool operator ==(Object other) =>
      other is AppLanguage && other.code == code;

  @override
  int get hashCode => code.hashCode;
}
