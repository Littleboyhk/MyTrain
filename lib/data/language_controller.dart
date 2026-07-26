import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_language.dart';

/// [SharedPreferences] instance, loaded once in `main()` and injected via a
/// `ProviderScope` override so reads elsewhere stay synchronous.
final sharedPreferencesProvider = Provider<SharedPreferences?>((ref) => null);

const String _kLanguageCodeKey = 'app_language_code';
const String _kLanguageChosenKey = 'app_language_chosen';

/// The user's selected app language (persisted).
///
/// SCOPE: this preference does not translate the UI yet — see [AppLanguage].
final languageProvider =
    NotifierProvider<LanguageController, AppLanguage>(LanguageController.new);

class LanguageController extends Notifier<AppLanguage> {
  SharedPreferences? get _prefs => ref.read(sharedPreferencesProvider);

  @override
  AppLanguage build() {
    final prefs = _prefs;
    final saved = prefs?.getString(_kLanguageCodeKey);
    if (saved != null) return AppLanguage.fromCode(saved);
    // Nothing stored yet: pre-select the device language when we support it,
    // otherwise English.
    return _deviceDefault();
  }

  static AppLanguage _deviceDefault() {
    try {
      return AppLanguage.fromLocale(PlatformDispatcher.instance.locale);
    } catch (_) {
      return AppLanguage.english_;
    }
  }

  /// Suggested selection for a fresh picker (device locale if supported).
  static AppLanguage get deviceSuggestion => _deviceDefault();

  /// Whether the user has explicitly confirmed a language. Drives the
  /// first-launch sheet: once true, it never auto-opens again.
  bool get hasChosen => _prefs?.getBool(_kLanguageChosenKey) ?? false;

  /// Persist the user's choice and mark onboarding complete.
  Future<void> select(AppLanguage language) async {
    state = language;
    final prefs = _prefs;
    if (prefs == null) {
      debugPrint('[Language] prefs unavailable — selection not persisted');
      return;
    }
    await prefs.setString(_kLanguageCodeKey, language.code);
    await prefs.setBool(_kLanguageChosenKey, true);
  }

  /// Test/debug helper: forget the choice so the first-launch sheet reappears.
  Future<void> reset() async {
    final prefs = _prefs;
    await prefs?.remove(_kLanguageCodeKey);
    await prefs?.remove(_kLanguageChosenKey);
    state = _deviceDefault();
  }
}
