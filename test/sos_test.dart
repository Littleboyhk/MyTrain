// Tests for the one-tap SOS feature.
//
// PLATFORM CAVEAT, READ BEFORE TRUSTING A GREEN RUN: `tel:` and `sms:` intents do
// not resolve on Flutter Web and do not resolve on emulators without a dialer or
// messaging app installed. Nothing in this file exercises the real url_launcher
// plugin — the widget tests inject [sosUrlLauncher] instead, so what they prove is
// "a tap produces exactly this URI", NOT "the dialer opened". The handoff itself
// is only verifiable on a physical device.
//
// The other thing these tests are built around: this is a safety feature, so the
// failure worth guarding against is a message that lies. Every "omit the field"
// rule has its own test, because a blank coach or a fabricated PNR in an
// emergency SMS is worse than a shorter message.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_train/data/emergency_contact_store.dart';
import 'package:my_train/data/language_controller.dart'
    show sharedPreferencesProvider;
import 'package:my_train/data/nearest_station_service.dart';
import 'package:my_train/data/sos_context.dart';
import 'package:my_train/models/rail_station.dart';
import 'package:my_train/theme/app_colors.dart';
import 'package:my_train/theme/app_theme.dart';
import 'package:my_train/utils/formatters.dart';
import 'package:my_train/widgets/emergency_contact_sheet.dart';
import 'package:my_train/widgets/emergency_sheet.dart';
import 'package:my_train/widgets/sos_button.dart';
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

/// A context with every field populated, for the "nothing is missing" baseline.
SosContext fullContext() => const SosContext(
      trainNumber: '12951',
      trainName: 'Mumbai Rajdhani Express',
      coach: 'B3',
      pnr: '2154783921',
      location: SosLocationNamed(
        stationName: 'Kalyan Jn',
        stationCode: 'KYN',
        distanceKm: 2.14,
        latitude: 19.24313,
        longitude: 73.13052,
      ),
    );

void main() {
  // Fmt holds a process-wide static that the SMS timestamp reads.
  final originalClock = Fmt.use12HourClock;
  setUp(() => Fmt.use12HourClock = true);
  tearDown(() => Fmt.use12HourClock = originalClock);

  // ===========================================================================
  group('emergency contact storage', () {
    test('a fresh install has no contacts', () async {
      final c = await containerWithPrefs();
      expect(c.read(emergencyContactsProvider), isEmpty);
    });

    test('adding persists under the versioned key', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(c.dispose);

      final n = c.read(emergencyContactsProvider.notifier);
      expect(n.add('+91 98765 43210', label: 'Mum'), isNull);

      expect(c.read(emergencyContactsProvider).single.label, 'Mum');
      final stored = prefs.getStringList(kEmergencyContactsKey);
      expect(stored, hasLength(1));
      expect(stored!.single, contains('98765'));
    });

    test('stored contacts load back on the next run', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final first = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      first.read(emergencyContactsProvider.notifier).add('9876543210', label: 'Ravi');
      first.dispose();

      final second = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(second.dispose);

      final loaded = second.read(emergencyContactsProvider);
      expect(loaded, hasLength(1));
      expect(loaded.single.label, 'Ravi');
      expect(loaded.single.dialNumber, '9876543210');
    });

    test('the list is capped at kMaxEmergencyContacts', () async {
      final c = await containerWithPrefs();
      final n = c.read(emergencyContactsProvider.notifier);

      expect(n.add('9000000001'), isNull);
      expect(n.add('9000000002'), isNull);
      expect(n.add('9000000003'), isNull);
      expect(n.add('9000000004'), EmergencyContactError.full);

      expect(c.read(emergencyContactsProvider), hasLength(kMaxEmergencyContacts));
    });

    test('the same number in different formatting is a duplicate', () async {
      final c = await containerWithPrefs();
      final n = c.read(emergencyContactsProvider.notifier);

      expect(n.add('+91 98765 43210'), isNull);
      expect(n.add('+91-98765-43210'), EmergencyContactError.duplicate);
      expect(c.read(emergencyContactsProvider), hasLength(1));
    });

    test('validation rejects nothing-dialable and absurd lengths', () async {
      final c = await containerWithPrefs();
      final n = c.read(emergencyContactsProvider.notifier);

      expect(n.add('   '), EmergencyContactError.empty);
      expect(n.add('abc'), EmergencyContactError.empty);
      expect(n.add('12'), EmergencyContactError.tooShort);
      expect(n.add('1234567890123456'), EmergencyContactError.tooLong);
      // 3 digits is allowed: short codes are legitimate contacts.
      expect(n.add('100'), isNull);
    });

    test('removeAt and replaceAt keep the rest of the list intact', () async {
      final c = await containerWithPrefs();
      final n = c.read(emergencyContactsProvider.notifier);
      n.add('9000000001', label: 'A');
      n.add('9000000002', label: 'B');
      n.add('9000000003', label: 'C');

      expect(n.replaceAt(1, '9000000009', label: 'B2'), isNull);
      expect(c.read(emergencyContactsProvider)[1].label, 'B2');

      // A replace must not be allowed to collide with a sibling.
      expect(n.replaceAt(1, '9000000003'), EmergencyContactError.duplicate);

      n.removeAt(0);
      final left = c.read(emergencyContactsProvider);
      expect(left.map((e) => e.label), ['B2', 'C']);

      // Out-of-range indices are ignored rather than throwing.
      n.removeAt(99);
      expect(c.read(emergencyContactsProvider), hasLength(2));
    });

    test('one unreadable stored row does not cost the others', () async {
      final c = await containerWithPrefs({
        kEmergencyContactsKey: <String>[
          'this is not json',
          '{"number":"9876543210","label":"Mum"}',
          '{"number":"","label":"blank"}',
        ],
      });

      final loaded = c.read(emergencyContactsProvider);
      expect(loaded, hasLength(1));
      expect(loaded.single.label, 'Mum');
    });

    test('masking shows only the last four digits', () {
      const c = EmergencyContact(number: '+91 98765 43210', label: 'Mum');
      expect(c.dialNumber, '+919876543210');
      expect(c.maskedNumber, contains('3210'));
      expect(c.maskedNumber, isNot(contains('98765')));
    });

    test('an unlabelled contact still has something to call it', () {
      const c = EmergencyContact(number: '9876543210');
      expect(c.displayLabel, 'Emergency contact');
    });
  });

  // ===========================================================================
  group('SMS body composition', () {
    final at = DateTime(2026, 8, 7, 15, 52);

    test('a fully-populated context includes every field once', () {
      final body = composeSosMessage(fullContext(), at: at);

      expect(
        body,
        'SOS - need help. Train 12951 Mumbai Rajdhani Express, Coach B3, '
        'PNR 2154783921, near Kalyan Jn (KYN). '
        'https://maps.google.com/?q=19.24313,73.13052 '
        'Sent via My Train app, 7 Aug, 3:52 PM.',
      );
    });

    test('no train tracked omits BOTH the train and the coach', () {
      // A coach with no train is meaningless, so it goes too — even though one is
      // set here, which is the case a naive implementation gets wrong.
      final body = composeSosMessage(
        const SosContext(
          coach: 'B3',
          location: SosLocationCoordinates(latitude: 19.076, longitude: 72.8777),
        ),
        at: at,
      );

      // NB: matched precisely, because the signature "Sent via My Train app"
      // contains the word Train.
      expect(body, isNot(contains('Train 12951')));
      expect(body, isNot(contains('Coach')));
      expect(body, startsWith('SOS - need help. near 19.07600, 72.87770.'));
    });

    test('a train with no coach entered omits only the coach', () {
      final body = composeSosMessage(
        fullContext().copyWith(coach: ''),
        at: at,
      );
      expect(body, contains('Train 12951'));
      expect(body, isNot(contains('Coach')));
    });

    test('whitespace-only coach counts as no coach', () {
      final body = composeSosMessage(fullContext().copyWith(coach: '   '), at: at);
      expect(body, isNot(contains('Coach')));
    });

    test('no PNR this session omits the field entirely', () {
      final body = composeSosMessage(
        const SosContext(
          trainNumber: '12951',
          trainName: 'Mumbai Rajdhani Express',
          coach: 'B3',
          location: SosLocationNamed(
            stationName: 'Kalyan Jn',
            stationCode: 'KYN',
            distanceKm: 2.14,
            latitude: 19.24313,
            longitude: 73.13052,
          ),
        ),
        at: at,
      );
      expect(body, isNot(contains('PNR')));
      expect(body, contains('Coach B3'));
    });

    test('no location drops the "near" clause AND the maps link', () {
      final body = composeSosMessage(
        fullContext().copyWith(location: const SosLocationUnavailable()),
        at: at,
      );

      expect(body, isNot(contains('near')));
      expect(body, isNot(contains('maps.google.com')));
      expect(body, isNot(contains('unavailable')));
      // Everything else survives — the message is still worth sending.
      expect(body, contains('Train 12951 Mumbai Rajdhani Express'));
      expect(body, contains('Coach B3'));
    });

    test('a still-resolving location behaves like no location', () {
      final body = composeSosMessage(
        fullContext().copyWith(location: const SosLocationResolving()),
        at: at,
      );
      expect(body, isNot(contains('maps.google.com')));
      expect(body, isNot(contains('Finding')));
    });

    test('with nothing at all it is still a valid distress message', () {
      final body = composeSosMessage(const SosContext(), at: at);
      expect(body, 'SOS - need help. Sent via My Train app, 7 Aug, 3:52 PM.');
    });

    test('the timestamp follows the 24-hour preference', () {
      Fmt.use12HourClock = false;
      final body = composeSosMessage(const SosContext(), at: at);
      expect(body, contains('7 Aug, 15:52'));
    });
  });

  // ===========================================================================
  group('location model', () {
    test('a named location reads as station, code and honest distance', () {
      const near = SosLocationNamed(
        stationName: 'Kalyan Jn',
        stationCode: 'KYN',
        distanceKm: 0.42,
        latitude: 19.24313,
        longitude: 73.13052,
      );
      expect(near.label, 'Near Kalyan Jn (KYN) · 420 m');
      expect(near.mapsUrl, 'https://maps.google.com/?q=19.24313,73.13052');
    });

    test('a named location with no readable fix yields no maps link', () {
      const named = SosLocationNamed(
        stationName: 'Kalyan Jn',
        stationCode: 'KYN',
        distanceKm: 2.1,
      );
      expect(named.hasCoordinates, isFalse);
      expect(named.mapsUrl, isNull);
      // The station name is still true and still shown.
      expect(named.label, contains('Kalyan Jn'));
    });

    test('non-finite coordinates never reach a maps link', () {
      const bad = SosLocationNamed(
        stationName: 'X',
        stationCode: 'X',
        distanceKm: 1,
        latitude: double.nan,
        longitude: double.nan,
      );
      expect(bad.hasCoordinates, isFalse);
      expect(bad.mapsUrl, isNull);
    });

    test('unavailable distinguishes "needs permission" from "just failed"', () {
      expect(const SosLocationUnavailable().needsPermission, isFalse);
      expect(
        const SosLocationUnavailable(needsPermission: true).needsPermission,
        isTrue,
      );
      expect(const SosLocationUnavailable().label, 'Location unavailable');
    });
  });

  // ===========================================================================
  group('URIs handed to the OS', () {
    test('tel: carries the bare number and nothing else', () {
      expect(sosTelUri('139').toString(), 'tel:139');
      expect(sosTelUri('112').toString(), 'tel:112');
    });

    test('tel: survives a number typed with spaces, dashes and brackets', () {
      expect(sosTelUri('+91 (98765) 43-210').toString(), 'tel:+919876543210');
    });

    test('sms: percent-encodes spaces rather than form-encoding them', () {
      final uri = sosSmsUri('9876543210', 'SOS - need help. Coach B3');
      // A '+' here would show up literally in the SMS composer.
      expect(uri.toString(), isNot(contains('+')));
      expect(uri.toString(), startsWith('sms:9876543210?body='));
      expect(uri.queryParameters['body'], 'SOS - need help. Coach B3');
    });

    test('sms: round-trips a body containing a maps URL and punctuation', () {
      final body = composeSosMessage(fullContext(), at: DateTime(2026, 8, 7, 15, 52));
      final uri = sosSmsUri('+91 98765 43210', body);

      expect(uri.scheme, 'sms');
      expect(uri.path, '+919876543210');
      // The recipient must receive the body byte-for-byte as composed.
      expect(uri.queryParameters['body'], body);
    });
  });

  // ===========================================================================
  group('session sourcing', () {
    test('the coach is remembered for the session and can be cleared', () async {
      final c = await containerWithPrefs();
      expect(c.read(sessionCoachProvider), isNull);

      c.read(sessionCoachProvider.notifier).set('B3');
      expect(c.read(sessionCoachProvider), 'B3');

      // Deselecting on the Coach screen clears it.
      c.read(sessionCoachProvider.notifier).set(null);
      expect(c.read(sessionCoachProvider), isNull);

      // Blank input is the same as no coach, never an empty string.
      c.read(sessionCoachProvider.notifier).set('   ');
      expect(c.read(sessionCoachProvider), isNull);
    });

    test('the coach is NOT persisted across runs', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final first = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      first.read(sessionCoachProvider.notifier).set('B3');
      first.dispose();

      final second = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(second.dispose);
      // A coach is true for one journey; carrying it forward would put a stale
      // coach into a future emergency message.
      expect(second.read(sessionCoachProvider), isNull);
    });

    test('the PNR is session-scoped too', () async {
      final c = await containerWithPrefs();
      expect(c.read(sessionPnrProvider), isNull);
      c.read(sessionPnrProvider.notifier).set('2154783921');
      expect(c.read(sessionPnrProvider), '2154783921');
      c.read(sessionPnrProvider.notifier).set('');
      expect(c.read(sessionPnrProvider), isNull);
    });
  });

  // ===========================================================================
  group('helplines offered', () {
    test('139 and 112 only — 182 is not a button', () {
      expect(SosHelpline.railway.number, '139');
      expect(SosHelpline.emergency.number, '112');

      final all = [SosHelpline.railway, SosHelpline.emergency];
      expect(all.map((h) => h.number), isNot(contains('182')));
    });
  });

  // ===========================================================================
  group('emergency contact editor', () {
    setUp(() => AppColors.palette = AppPalette.dark);

    /// Pumps the editor on its own. This is the same widget Settings › Emergency
    /// Contact uses, so testing it here covers both entry points without pumping
    /// the whole Settings screen and its auth/cache dependencies.
    Future<ProviderContainer> openEditor(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.themeFor(AppPalette.dark),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => showEmergencyContactEditor(context),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('saving a valid number stores it', (tester) async {
      final container = await openEditor(tester);

      await tester.enterText(
          find.widgetWithText(TextField, '+91 98765 43210'), '9876543210');
      await tester.enterText(find.widgetWithText(TextField, 'Mum'), 'Mum');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final saved = container.read(emergencyContactsProvider);
      expect(saved, hasLength(1));
      expect(saved.single.dialNumber, '9876543210');
      expect(saved.single.label, 'Mum');
      // Sheet dismissed on success.
      expect(find.text('Save'), findsNothing);
    });

    testWidgets('an invalid number is refused in place, not silently dropped',
        (tester) async {
      final container = await openEditor(tester);

      await tester.enterText(
          find.widgetWithText(TextField, '+91 98765 43210'), '12');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text(EmergencyContactError.tooShort.message), findsOneWidget);
      expect(container.read(emergencyContactsProvider), isEmpty);
      // Still open, so the mistake can be corrected.
      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('cancelling stores nothing', (tester) async {
      final container = await openEditor(tester);

      await tester.enterText(
          find.widgetWithText(TextField, '+91 98765 43210'), '9876543210');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(container.read(emergencyContactsProvider), isEmpty);
    });

    testWidgets('the sheet says where the number is stored', (tester) async {
      await openEditor(tester);
      // Non-negotiable for the most sensitive value the app holds: the promise
      // has to be on screen at the moment it is typed.
      expect(find.textContaining('Stored on this device only'), findsOneWidget);
    });
  });

  // ===========================================================================
  group('Emergency sheet', () {
    final launched = <Uri>[];

    setUp(() {
      launched.clear();
      sosUrlLauncher = (uri) async {
        launched.add(uri);
        return true;
      };
      AppColors.palette = AppPalette.dark;
    });

    tearDown(() => sosUrlLauncher = defaultSosUrlLauncher);

    /// Pumps a host with the SOS button, then opens the sheet.
    ///
    /// [location] replaces the real [NearestStationService], so no geolocator
    /// platform channel is touched. That is not just convenience: the real service
    /// arms 6s and 20s timeouts that outlive a widget test, and under `flutter
    /// test` there is no location provider for it to talk to anyway.
    ///
    /// Providers are seeded on a container BEFORE the first build —
    /// `UncontrolledProviderScope` rather than seeding inside a builder, which
    /// would be a write during build.
    Future<void> openSheet(
      WidgetTester tester, {
      String? trainNumber,
      String? trainName,
      List<String> contacts = const [],
      String? pnr,
      _FakeNearestStation? location,
    }) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          nearestStationServiceProvider.overrideWith(
            (ref) => location ?? _FakeNearestStation.denied(ref),
          ),
        ],
      );
      addTearDown(container.dispose);

      for (final number in contacts) {
        container
            .read(emergencyContactsProvider.notifier)
            .add(number, label: 'Mum');
      }
      if (pnr != null) container.read(sessionPnrProvider.notifier).set(pnr);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.themeFor(AppPalette.dark),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: SosButton(
                    onTap: () => showEmergencySheet(
                      context,
                      trainNumber: trainNumber,
                      trainName: trainName,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(SosButton));
      await tester.pumpAndSettle();
    }

    testWidgets('the FAB opens the sheet and never dials by itself',
        (tester) async {
      await openSheet(tester, trainNumber: '12951', trainName: 'Rajdhani');

      expect(find.text('Emergency'), findsOneWidget);
      // The whole point: opening is not acting.
      expect(launched, isEmpty);
    });

    testWidgets('both helplines are offered, 182 is not', (tester) async {
      await openSheet(tester);

      expect(find.text('Call 139 – Railway Helpline'), findsOneWidget);
      expect(find.text('Call 112 – Emergency'), findsOneWidget);
      expect(find.textContaining('182'), findsNothing);
    });

    testWidgets('tapping Call 139 produces exactly tel:139', (tester) async {
      await openSheet(tester, trainNumber: '12951', trainName: 'Rajdhani');

      await tester.tap(find.text('Call 139 – Railway Helpline'));
      await tester.pumpAndSettle();

      expect(launched, hasLength(1));
      expect(launched.single.toString(), 'tel:139');
    });

    testWidgets('tapping Call 112 produces exactly tel:112', (tester) async {
      await openSheet(tester);

      await tester.tap(find.text('Call 112 – Emergency'));
      await tester.pumpAndSettle();

      expect(launched.single.toString(), 'tel:112');
    });

    testWidgets('with a train, the train row shows and the coach is editable',
        (tester) async {
      await openSheet(tester, trainNumber: '12951', trainName: 'Rajdhani');

      expect(find.text('TRAIN'), findsOneWidget);
      expect(find.text('12951 Rajdhani'), findsOneWidget);
      expect(find.text('COACH'), findsOneWidget);
      // Empty session coach → the placeholder, not a blank line.
      expect(find.text('Add your coach'), findsOneWidget);
    });

    testWidgets('with no train, the train and coach rows are omitted',
        (tester) async {
      await openSheet(tester);

      expect(find.text('TRAIN'), findsNothing);
      expect(find.text('COACH'), findsNothing);
      // Location is still offered, and the calls still work.
      expect(find.text('LOCATION'), findsOneWidget);
      expect(find.text('Call 139 – Railway Helpline'), findsOneWidget);
    });

    testWidgets('no location fix shows "Location unavailable" and blocks nothing',
        (tester) async {
      await openSheet(tester);

      expect(find.text('Location unavailable'), findsOneWidget);
      // Permission is the blocker, so the offer is to enable it — from a tap.
      expect(find.text('Enable'), findsOneWidget);

      await tester.tap(find.text('Call 139 – Railway Helpline'));
      await tester.pumpAndSettle();
      expect(launched.single.toString(), 'tel:139');
    });

    testWidgets('a map-matched fix shows the station and lands in the message',
        (tester) async {
      await openSheet(
        tester,
        trainNumber: '12951',
        trainName: 'Rajdhani',
        contacts: const ['9876543210'],
        location: _FakeNearestStation.found(),
      );

      expect(find.text('Near Kalyan Jn (KYN) · 2.1 km'), findsOneWidget);

      await tester.tap(find.text('Text my emergency contact'));
      await tester.pumpAndSettle();

      final body = launched.single.queryParameters['body']!;
      expect(body, contains('near Kalyan Jn (KYN)'));
      expect(body, contains('https://maps.google.com/?q=19.24313,73.13052'));
    });

    testWidgets('the text action is gated when no contact is saved',
        (tester) async {
      await openSheet(tester, trainNumber: '12951', trainName: 'Rajdhani');

      expect(find.text('Add an emergency contact'), findsOneWidget);
      expect(find.text('Text my emergency contact'), findsNothing);
      // Gating the text button must not gate the calls.
      expect(find.text('Call 139 – Railway Helpline'), findsOneWidget);
    });

    testWidgets('with a contact saved, texting composes the sms: URI',
        (tester) async {
      await openSheet(
        tester,
        trainNumber: '12951',
        trainName: 'Rajdhani',
        contacts: const ['9876543210'],
        pnr: '2154783921',
      );

      expect(find.text('Text my emergency contact'), findsOneWidget);
      await tester.tap(find.text('Text my emergency contact'));
      await tester.pumpAndSettle();

      expect(launched, hasLength(1));
      final uri = launched.single;
      expect(uri.scheme, 'sms');
      expect(uri.path, '9876543210');

      final body = uri.queryParameters['body']!;
      expect(body, startsWith('SOS - need help.'));
      expect(body, contains('Train 12951 Rajdhani'));
      expect(body, contains('PNR 2154783921'));
      // No fix in this scenario, so no location and no link — and no lie.
      expect(body, isNot(contains('maps.google.com')));
      expect(body, contains('Sent via My Train app'));
    });

    testWidgets('a coach typed into the sheet reaches the message',
        (tester) async {
      await openSheet(
        tester,
        trainNumber: '12951',
        trainName: 'Rajdhani',
        contacts: const ['9876543210'],
      );

      await tester.enterText(find.byType(TextField), 'B3');
      await tester.pump();

      await tester.tap(find.text('Text my emergency contact'));
      await tester.pumpAndSettle();

      expect(launched.single.queryParameters['body'], contains('Coach B3'));
    });
  });
}

/// Stands in for [NearestStationService] so widget tests never reach geolocator.
class _FakeNearestStation extends NearestStationService {
  _FakeNearestStation(super.ref, this._result, this._fix);

  /// Permission not granted: the degraded path the sheet must stay usable in.
  factory _FakeNearestStation.denied(Ref ref) => _FakeNearestStation(
        ref,
        const NearestStationFailure(
          NearestStationError.permissionDenied,
          'Location access is needed to find the nearest station.',
        ),
        null,
      );

  /// A good fix, map-matched to a station 2.14 km away.
  factory _FakeNearestStation.found() => _FakeNearestStation(
        _throwawayRef,
        const NearestStationFound(
          nearby: [
            NearbyStation(
              station: RailStation(code: 'KYN', name: 'Kalyan Jn'),
              distanceKm: 2.14,
            ),
          ],
          accuracyM: 12,
        ),
        (lat: 19.24313, lng: 73.13052, accuracyM: 12.0, at: _fixedAt),
      );

  final NearestStationResult _result;
  final ({double lat, double lng, double? accuracyM, DateTime at})? _fix;

  @override
  Future<NearestStationResult> find({
    bool forceRefresh = false,
    bool requestPermission = true,
  }) async =>
      _result;

  @override
  ({double lat, double lng, double? accuracyM, DateTime at})? get lastFix => _fix;
}

final DateTime _fixedAt = DateTime(2026, 8, 7, 15, 52);

/// The base class stores a [Ref] it never uses on these paths, and the `.found`
/// factory has none to hand. Only the overridden members are ever called.
final Ref _throwawayRef = ProviderContainer().read(_refProvider);
final _refProvider = Provider<Ref>((ref) => ref);

