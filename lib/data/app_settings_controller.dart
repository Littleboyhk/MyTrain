import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/formatters.dart';
import 'language_controller.dart' show sharedPreferencesProvider;

/// Alarm tones offered by the destination-alarm picker.
///
/// PLAYBACK IS NOT WIRED. The choice is stored and shown, but this build has no
/// audio plugin (`audioplayers` / `just_audio` are not in pubspec.yaml), so
/// nothing can actually sound a tone yet. The setting is honest about that in
/// the UI rather than pretending — see `settings_screen.dart`.
enum AlarmTone {
  classicBell('Classic bell'),
  stationChime('Station chime'),
  hornShort('Short horn'),
  gentleRise('Gentle rise'),
  vibrateOnly('Vibrate only');

  const AlarmTone(this.label);

  /// Human label. Deliberately not localised yet — see the l10n TODO in
  /// `settings_screen.dart`, which already carries English literals for the
  /// account section.
  final String label;

  static AlarmTone fromName(String? name) {
    for (final t in AlarmTone.values) {
      if (t.name == name) return t;
    }
    return AlarmTone.classicBell;
  }
}

/// Typeface options for the whole-app font picker (Settings › Appearance).
///
/// [system] is the engine default (Roboto / .SF). It needs no download, is the
/// initial value, and is the graceful fallback. Every other option names a
/// Google font that [AppTheme.themeFor] resolves through `google_fonts`: the
/// family is fetched once and cached, and if it cannot be fetched (offline, cold
/// start) the text renders in the default face rather than failing. The bundled
/// Noto Indic fallbacks stay under every option, so non-Latin scripts never
/// regress whichever font is chosen.
enum AppFont {
  sfPro('SF Pro', null),
  system('Default (System)', null),
  inter('Inter', 'Inter'),
  poppins('Poppins', 'Poppins'),
  lora('Lora', 'Lora'),
  robotoMono('Roboto Mono', 'Roboto Mono');

  const AppFont(this.label, this.googleFamily);

  /// Human label shown in the picker.
  final String label;

  /// Google Fonts family name handed to `GoogleFonts.getTextTheme`, or null for
  /// [system] (use the platform default, no download).
  final String? googleFamily;

  static AppFont fromName(String? name) {
    for (final f in AppFont.values) {
      if (f.name == name) return f;
    }
    return AppFont.sfPro;
  }
}

/// Immutable snapshot of the user's app preferences.
@immutable
class AppSettings {
  const AppSettings({
    this.use12HourClock = true,
    this.suggestInsideTrain = true,
    this.spotNotifications = false,
    this.speedometerEnabled = true,
    this.alarmTone = AlarmTone.classicBell,
    this.appFont = AppFont.sfPro,
  });

  /// Render clock times as `4:25 PM` rather than `16:25`.
  final bool use12HourClock;

  /// Offer the "Are you inside this train?" sheet shortly after opening a live
  /// journey. Off means the sheet is never auto-shown; sharing can still be
  /// started manually from the action bar.
  final bool suggestInsideTrain;

  /// Persistent "spot" notification carrying the user's location.
  ///
  /// NOT FUNCTIONAL IN THIS BUILD — see [AppSettingsController.spotNotificationsSupported].
  final bool spotNotifications;

  /// Show the live GPS speedometer on the tracking screen while sharing in GPS
  /// mode.
  final bool speedometerEnabled;

  final AlarmTone alarmTone;

  /// The whole-app typeface. Drives [AppTheme.themeFor] via `main.dart`.
  final AppFont appFont;

  AppSettings copyWith({
    bool? use12HourClock,
    bool? suggestInsideTrain,
    bool? spotNotifications,
    bool? speedometerEnabled,
    AlarmTone? alarmTone,
    AppFont? appFont,
  }) {
    return AppSettings(
      use12HourClock: use12HourClock ?? this.use12HourClock,
      suggestInsideTrain: suggestInsideTrain ?? this.suggestInsideTrain,
      spotNotifications: spotNotifications ?? this.spotNotifications,
      speedometerEnabled: speedometerEnabled ?? this.speedometerEnabled,
      alarmTone: alarmTone ?? this.alarmTone,
      appFont: appFont ?? this.appFont,
    );
  }
}

const String _kUse12Hour = 'settings_use_12_hour';
const String _kSuggestInsideTrain = 'settings_suggest_inside_train';
const String _kSpotNotifications = 'settings_spot_notifications';
const String _kSpeedometer = 'settings_speedometer';
const String _kAlarmTone = 'settings_alarm_tone';
const String _kAppFont = 'settings_app_font';

final appSettingsProvider =
    NotifierProvider<AppSettingsController, AppSettings>(
  AppSettingsController.new,
);

class AppSettingsController extends Notifier<AppSettings> {
  /// Whether a standing location notification can actually be delivered.
  static bool get spotNotificationsSupported => true;

  SharedPreferences? get _prefs => ref.read(sharedPreferencesProvider);

  @override
  AppSettings build() {
    final prefs = _prefs;
    final loaded = AppSettings(
      use12HourClock: prefs?.getBool(_kUse12Hour) ?? true,
      suggestInsideTrain: prefs?.getBool(_kSuggestInsideTrain) ?? true,
      spotNotifications: prefs?.getBool(_kSpotNotifications) ?? false,
      speedometerEnabled: prefs?.getBool(_kSpeedometer) ?? true,
      alarmTone: AlarmTone.fromName(prefs?.getString(_kAlarmTone)),
      appFont: AppFont.fromName(prefs?.getString(_kAppFont)),
    );
    // Push the clock format into the formatter before the first frame builds.
    // Same static-mutable pattern main.dart already uses for AppColors.palette:
    // Fmt is called from dozens of widgets with no BuildContext to read from.
    Fmt.use12HourClock = loaded.use12HourClock;
    return loaded;
  }

  void setUse12HourClock(bool value) {
    Fmt.use12HourClock = value;
    state = state.copyWith(use12HourClock: value);
    _prefs?.setBool(_kUse12Hour, value);
  }

  void setSuggestInsideTrain(bool value) {
    state = state.copyWith(suggestInsideTrain: value);
    _prefs?.setBool(_kSuggestInsideTrain, value);
  }

  void setSpotNotifications(bool value) {
    state = state.copyWith(spotNotifications: value);
    _prefs?.setBool(_kSpotNotifications, value);
  }

  void setSpeedometerEnabled(bool value) {
    state = state.copyWith(speedometerEnabled: value);
    _prefs?.setBool(_kSpeedometer, value);
  }

  void setAlarmTone(AlarmTone tone) {
    state = state.copyWith(alarmTone: tone);
    _prefs?.setString(_kAlarmTone, tone.name);
  }

  void setAppFont(AppFont font) {
    state = state.copyWith(appFont: font);
    _prefs?.setString(_kAppFont, font.name);
  }
}
