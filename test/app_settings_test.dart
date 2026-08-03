// Tests for the settings added alongside the speedometer.
//
// The point of interest is that these preferences actually DO something. A
// settings screen full of switches that persist but change no behaviour is the
// failure mode worth guarding against, so the clock-format tests assert on
// rendered output rather than just on the stored boolean.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_train/data/app_settings_controller.dart';
import 'package:my_train/data/language_controller.dart'
    show sharedPreferencesProvider;
import 'package:my_train/utils/formatters.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> containerWithPrefs([
  Map<String, Object> initial = const {},
]) async {
  SharedPreferences.setMockInitialValues(initial);
  final prefs = await SharedPreferences.getInstance();
  final c = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  // Fmt holds a process-wide static, so leave it as found.
  final original = Fmt.use12HourClock;
  tearDown(() => Fmt.use12HourClock = original);

  group('clock format', () {
    test('24-hour pads to a fixed width', () {
      Fmt.use12HourClock = false;
      expect(Fmt.hhmm(DateTime(2026, 1, 1, 6, 5)), '06:05');
      expect(Fmt.hhmm(DateTime(2026, 1, 1, 17, 30)), '17:30');
      expect(Fmt.hhmm(DateTime(2026, 1, 1, 0, 0)), '00:00');
    });

    test('12-hour maps midnight and noon to 12, not 0', () {
      Fmt.use12HourClock = true;
      // The classic off-by-twelve bug.
      expect(Fmt.hhmm(DateTime(2026, 1, 1, 0, 0)), '12:00 AM');
      expect(Fmt.hhmm(DateTime(2026, 1, 1, 12, 0)), '12:00 PM');
      expect(Fmt.hhmm(DateTime(2026, 1, 1, 0, 30)), '12:30 AM');
      expect(Fmt.hhmm(DateTime(2026, 1, 1, 12, 30)), '12:30 PM');
    });

    test('12-hour covers both halves of the day', () {
      Fmt.use12HourClock = true;
      expect(Fmt.hhmm(DateTime(2026, 1, 1, 6, 5)), '6:05 AM');
      expect(Fmt.hhmm(DateTime(2026, 1, 1, 11, 59)), '11:59 AM');
      expect(Fmt.hhmm(DateTime(2026, 1, 1, 13, 0)), '1:00 PM');
      expect(Fmt.hhmm(DateTime(2026, 1, 1, 23, 59)), '11:59 PM');
    });

    test('hhmm24 ignores the preference entirely', () {
      Fmt.use12HourClock = true;
      expect(Fmt.hhmm24(DateTime(2026, 1, 1, 17, 30)), '17:30');
    });
  });

  group('persistence', () {
    test('defaults apply on a fresh install', () async {
      final c = await containerWithPrefs();
      final s = c.read(appSettingsProvider);

      expect(s.use12HourClock, isTrue);
      expect(s.suggestInsideTrain, isTrue);
      expect(s.speedometerEnabled, isTrue);
      expect(s.spotNotifications, isFalse);
      expect(s.alarmTone, AlarmTone.classicBell);
    });

    test('stored values win over defaults', () async {
      final c = await containerWithPrefs({
        'settings_use_12_hour': false,
        'settings_suggest_inside_train': false,
        'settings_speedometer': false,
        'settings_alarm_tone': 'hornShort',
      });
      final s = c.read(appSettingsProvider);

      expect(s.use12HourClock, isFalse);
      expect(s.suggestInsideTrain, isFalse);
      expect(s.speedometerEnabled, isFalse);
      expect(s.alarmTone, AlarmTone.hornShort);
    });

    test('reading the settings pushes the clock format into Fmt', () async {
      Fmt.use12HourClock = true;
      final c = await containerWithPrefs({'settings_use_12_hour': false});

      c.read(appSettingsProvider);

      // Without this the toggle would persist but nothing would reformat.
      expect(Fmt.use12HourClock, isFalse);
    });

    test('each setter updates state, Fmt and storage together', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(c.dispose);

      final n = c.read(appSettingsProvider.notifier);

      n.setUse12HourClock(false);
      expect(c.read(appSettingsProvider).use12HourClock, isFalse);
      expect(Fmt.use12HourClock, isFalse);
      expect(prefs.getBool('settings_use_12_hour'), isFalse);

      n.setSuggestInsideTrain(false);
      expect(prefs.getBool('settings_suggest_inside_train'), isFalse);

      n.setSpeedometerEnabled(false);
      expect(prefs.getBool('settings_speedometer'), isFalse);

      n.setAlarmTone(AlarmTone.gentleRise);
      expect(prefs.getString('settings_alarm_tone'), 'gentleRise');
      expect(c.read(appSettingsProvider).alarmTone, AlarmTone.gentleRise);
    });

    test('an unknown stored tone falls back instead of throwing', () async {
      final c = await containerWithPrefs({
        'settings_alarm_tone': 'tone_from_a_future_version',
      });
      expect(c.read(appSettingsProvider).alarmTone, AlarmTone.classicBell);
    });
  });

  group('platform honesty', () {
    test('spot notifications are reported supported in this build', () {
      expect(AppSettingsController.spotNotificationsSupported, isTrue);
    });
  });
}
