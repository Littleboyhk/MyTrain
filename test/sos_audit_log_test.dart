// Tests for the client-side SOS audit log.
//
// The failure mode this file is built around is a log that OVERSTATES what
// happened. "Tapped" and "connected" are different facts, and the app can only
// observe the first: a `tel:` handoff the OS accepted still needed the user to
// press the dialer's own call button. So the outcome tests are the important ones
// here, and there is no state in the model that can claim a call connected.
//
// Second-order concern: a log is worthless if it loses entries. Hence tests for
// the 20-entry cap dropping the OLDEST, for ordering, for a corrupt row not
// taking its neighbours down with it, and for a recorded action surviving the
// sheet being dismissed mid-launch.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_train/data/emergency_contact_store.dart';
import 'package:my_train/data/language_controller.dart'
    show sharedPreferencesProvider;
import 'package:my_train/data/nearest_station_service.dart';
import 'package:my_train/data/sos_audit_log.dart';
import 'package:my_train/data/sos_context.dart';
import 'package:my_train/l10n/app_localizations.dart';
import 'package:my_train/screens/sos_audit_screen.dart';
import 'package:my_train/theme/app_colors.dart';
import 'package:my_train/theme/app_theme.dart';
import 'package:my_train/utils/formatters.dart';
import 'package:my_train/widgets/emergency_sheet.dart';
import 'package:my_train/widgets/sos_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A fully-populated snapshot, so "every field is captured" has a baseline.
const SosContext _snapshot = SosContext(
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

Future<({ProviderContainer container, SharedPreferences prefs})> withPrefs([
  Map<String, Object> initial = const {},
]) async {
  SharedPreferences.setMockInitialValues(initial);
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  addTearDown(container.dispose);
  return (container: container, prefs: prefs);
}

void main() {
  final originalClock = Fmt.use12HourClock;
  setUp(() => Fmt.use12HourClock = true);
  tearDown(() => Fmt.use12HourClock = originalClock);

  // ===========================================================================
  group('recording', () {
    test('a fresh install has no history', () async {
      final env = await withPrefs();
      expect(env.container.read(sosAuditLogProvider), isEmpty);
    });

    test('an entry captures the whole snapshot as it stood', () async {
      final env = await withPrefs();
      final at = DateTime(2026, 8, 7, 15, 52);

      env.container.read(sosAuditLogProvider.notifier).record(
            action: SosAuditAction.callRailwayHelpline,
            outcome: SosAuditOutcome.handedOff,
            context: _snapshot,
            at: at,
          );

      final e = env.container.read(sosAuditLogProvider).single;
      expect(e.at, at);
      expect(e.action, SosAuditAction.callRailwayHelpline);
      expect(e.outcome, SosAuditOutcome.handedOff);
      expect(e.trainNumber, '12951');
      expect(e.trainLine, '12951 Mumbai Rajdhani Express');
      expect(e.coach, 'B3');
      expect(e.pnr, '2154783921');
      expect(e.locationLabel, 'Near Kalyan Jn (KYN) · 2.1 km');
      expect(e.latitude, 19.24313);
      expect(e.longitude, 73.13052);
      expect(e.mapsUrl, 'https://maps.google.com/?q=19.24313,73.13052');
      expect(e.noContactFallback, isFalse);
    });

    test('absent context fields are stored as null, never as blanks', () async {
      final env = await withPrefs();

      env.container.read(sosAuditLogProvider.notifier).record(
            action: SosAuditAction.callEmergency,
            outcome: SosAuditOutcome.handedOff,
            // No train tracked, coach left empty, no PNR looked up.
            context: const SosContext(coach: '   '),
          );

      final e = env.container.read(sosAuditLogProvider).single;
      expect(e.trainNumber, isNull);
      expect(e.trainLine, isNull);
      expect(e.coach, isNull);
      expect(e.pnr, isNull);
      expect(e.hasCoordinates, isFalse);
      expect(e.mapsUrl, isNull);
    });

    test('a still-resolving location records nothing, unavailable records so',
        () async {
      final env = await withPrefs();
      final log = env.container.read(sosAuditLogProvider.notifier);

      log.record(
        action: SosAuditAction.callEmergency,
        outcome: SosAuditOutcome.handedOff,
        context: const SosContext(location: SosLocationResolving()),
      );
      // "Finding your location…" is a spinner, not a fact about where they were.
      expect(env.container.read(sosAuditLogProvider).single.locationLabel, isNull);

      log.record(
        action: SosAuditAction.callEmergency,
        outcome: SosAuditOutcome.handedOff,
        context: const SosContext(location: SosLocationUnavailable()),
      );
      // "Location unavailable" IS a fact, and worth having in the record.
      expect(
        env.container.read(sosAuditLogProvider).first.locationLabel,
        'Location unavailable',
      );
    });

    test('recording never throws, whatever it is handed', () async {
      final env = await withPrefs();
      expect(
        () => env.container.read(sosAuditLogProvider.notifier).record(
              action: SosAuditAction.textContact,
              outcome: SosAuditOutcome.notAttempted,
              context: null,
            ),
        returnsNormally,
      );
      expect(env.container.read(sosAuditLogProvider), hasLength(1));
    });
  });

  // ===========================================================================
  group('outcome is never overstated', () {
    test('the three outcomes stay distinct and none claims a connection', () {
      // If a fourth value ever appears meaning "connected", this test should be
      // the thing that stops it: the app cannot observe that.
      expect(SosAuditOutcome.values, hasLength(3));
      for (final o in SosAuditOutcome.values) {
        expect(o.label.toLowerCase(), isNot(contains('connected')));
        expect(o.label.toLowerCase(), isNot(contains('delivered')));
      }
      expect(SosAuditOutcome.handedOff.label, 'Opened on your phone');
    });

    test('a failed launch is still recorded, distinctly', () async {
      final env = await withPrefs();
      final log = env.container.read(sosAuditLogProvider.notifier);

      log.record(
        action: SosAuditAction.callRailwayHelpline,
        outcome: SosAuditOutcome.launchFailed,
        context: _snapshot,
      );

      final e = env.container.read(sosAuditLogProvider).single;
      // The attempt happened and is worth knowing about.
      expect(e.action, SosAuditAction.callRailwayHelpline);
      // But it is not filed as though the dialer opened.
      expect(e.outcome, SosAuditOutcome.launchFailed);
      expect(e.outcome, isNot(SosAuditOutcome.handedOff));
    });

    test('the no-contact fallback is its own shape, not a failed send', () async {
      final env = await withPrefs();

      env.container.read(sosAuditLogProvider.notifier).record(
            action: SosAuditAction.textContact,
            outcome: SosAuditOutcome.notAttempted,
            context: _snapshot,
            noContactFallback: true,
          );

      final e = env.container.read(sosAuditLogProvider).single;
      expect(e.noContactFallback, isTrue);
      expect(e.outcome, SosAuditOutcome.notAttempted);
      // No URI was built, so no contact details exist to record.
      expect(e.contactLabel, isNull);
      expect(e.contactMasked, isNull);
    });

    test('an outcome from a future version degrades to the weakest claim',
        () async {
      final env = await withPrefs({
        kSosAuditLogKey: <String>[
          '{"at":"2026-08-07T15:52:00.000","action":"callEmergency",'
              '"outcome":"definitelyRescued"}',
        ],
      });

      // Never silently upgraded to handedOff.
      expect(
        env.container.read(sosAuditLogProvider).single.outcome,
        SosAuditOutcome.launchFailed,
      );
    });
  });

  // ===========================================================================
  group('cap and ordering', () {
    test('the cap drops the OLDEST entries, keeping the newest 20', () async {
      final env = await withPrefs();
      final log = env.container.read(sosAuditLogProvider.notifier);

      for (int i = 0; i < 25; i++) {
        log.record(
          action: SosAuditAction.callEmergency,
          outcome: SosAuditOutcome.handedOff,
          context: SosContext(trainNumber: '$i'),
          at: DateTime(2026, 8, 7, 10, i),
        );
      }

      final entries = env.container.read(sosAuditLogProvider);
      expect(entries, hasLength(kMaxSosAuditEntries));
      // Newest first: the 25th recorded (minute 24) leads.
      expect(entries.first.trainNumber, '24');
      // The oldest survivor is #5; #0–#4 were dropped.
      expect(entries.last.trainNumber, '5');
      expect(entries.map((e) => e.trainNumber), isNot(contains('4')));
    });

    test('history is newest-first after a reload', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final first = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      final log = first.read(sosAuditLogProvider.notifier);
      log.record(
        action: SosAuditAction.callEmergency,
        outcome: SosAuditOutcome.handedOff,
        context: const SosContext(trainNumber: 'older'),
        at: DateTime(2026, 8, 7, 9),
      );
      log.record(
        action: SosAuditAction.callRailwayHelpline,
        outcome: SosAuditOutcome.handedOff,
        context: const SosContext(trainNumber: 'newer'),
        at: DateTime(2026, 8, 7, 11),
      );
      first.dispose();

      final second = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(second.dispose);

      final reloaded = second.read(sosAuditLogProvider);
      expect(reloaded.map((e) => e.trainNumber), ['newer', 'older']);
    });

    test('out-of-order stored rows are sorted on read', () async {
      final env = await withPrefs({
        kSosAuditLogKey: <String>[
          '{"at":"2026-08-01T09:00:00.000","action":"callEmergency",'
              '"outcome":"handedOff","trainNumber":"old"}',
          '{"at":"2026-08-07T09:00:00.000","action":"callEmergency",'
              '"outcome":"handedOff","trainNumber":"new"}',
        ],
      });

      expect(
        env.container.read(sosAuditLogProvider).map((e) => e.trainNumber),
        ['new', 'old'],
      );
    });

    test('a stored file already over the cap is trimmed on read', () async {
      final rows = <String>[
        for (int i = 0; i < 30; i++)
          '{"at":"2026-08-07T10:${i.toString().padLeft(2, '0')}:00.000",'
              '"action":"callEmergency","outcome":"handedOff"}',
      ];
      final env = await withPrefs({kSosAuditLogKey: rows});

      expect(
        env.container.read(sosAuditLogProvider),
        hasLength(kMaxSosAuditEntries),
      );
    });
  });

  // ===========================================================================
  group('persistence robustness', () {
    test('entries persist under the versioned key', () async {
      final env = await withPrefs();

      env.container.read(sosAuditLogProvider.notifier).record(
            action: SosAuditAction.textContact,
            outcome: SosAuditOutcome.handedOff,
            context: _snapshot,
            contactLabel: 'Mum',
            contactMasked: '+91 ••••• 3210',
          );

      final stored = env.prefs.getStringList(kSosAuditLogKey);
      expect(stored, hasLength(1));
      expect(stored!.single, contains('Kalyan Jn'));
    });

    test('the full contact number is never written to the log', () async {
      final env = await withPrefs();
      const contact = EmergencyContact(number: '+91 98765 43210', label: 'Mum');

      env.container.read(sosAuditLogProvider.notifier).record(
            action: SosAuditAction.textContact,
            outcome: SosAuditOutcome.handedOff,
            context: _snapshot,
            contactLabel: contact.displayLabel,
            contactMasked: contact.maskedNumber,
          );

      final raw = env.prefs.getStringList(kSosAuditLogKey)!.single;
      expect(raw, contains('Mum'));
      expect(raw, contains('3210'));
      // The middle digits must not be duplicated into the log in the clear.
      expect(raw, isNot(contains('98765')));
      expect(raw, isNot(contains('919876543210')));
    });

    test('one unreadable row does not cost the others', () async {
      final env = await withPrefs({
        kSosAuditLogKey: <String>[
          'not json at all',
          '{"at":"2026-08-07T15:52:00.000","action":"callEmergency",'
              '"outcome":"handedOff","trainNumber":"12951"}',
          // No timestamp: says nothing useful, so it is dropped.
          '{"action":"callEmergency","outcome":"handedOff"}',
          // Unrecognised action: likewise.
          '{"at":"2026-08-07T15:00:00.000","action":"telepathy"}',
        ],
      });

      final entries = env.container.read(sosAuditLogProvider);
      expect(entries, hasLength(1));
      expect(entries.single.trainNumber, '12951');
    });

    test('clear wipes both state and storage', () async {
      final env = await withPrefs();
      final log = env.container.read(sosAuditLogProvider.notifier);
      log.record(
        action: SosAuditAction.callEmergency,
        outcome: SosAuditOutcome.handedOff,
        context: _snapshot,
      );
      expect(env.container.read(sosAuditLogProvider), hasLength(1));

      log.clear();

      expect(env.container.read(sosAuditLogProvider), isEmpty);
      expect(env.prefs.getStringList(kSosAuditLogKey), isEmpty);
    });
  });

  // ===========================================================================
  group('logging from the Emergency sheet', () {
    final launched = <Uri>[];

    setUp(() {
      launched.clear();
      AppColors.palette = AppPalette.dark;
    });

    tearDown(() => sosUrlLauncher = defaultSosUrlLauncher);

    Future<ProviderContainer> openSheet(
      WidgetTester tester, {
      bool launchSucceeds = true,
      List<String> contacts = const [],
      String? pnr,
    }) async {
      sosUrlLauncher = (uri) async {
        launched.add(uri);
        return launchSucceeds;
      };

      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          nearestStationServiceProvider.overrideWith(_NoLocation.new),
        ],
      );
      addTearDown(container.dispose);

      for (final n in contacts) {
        container.read(emergencyContactsProvider.notifier).add(n, label: 'Mum');
      }
      if (pnr != null) container.read(sessionPnrProvider.notifier).set(pnr);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.themeFor(AppPalette.dark),
            // The gated text action pushes the real Settings screen, which reads
            // L10n. Without these delegates that push throws in the harness even
            // though it is fine in the app, where MyTrainApp supplies them.
            locale: const Locale('en'),
            supportedLocales: L10n.supportedLocales,
            localizationsDelegates: const [
              L10n.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: SosButton(
                    onTap: () => showEmergencySheet(
                      context,
                      trainNumber: '12951',
                      trainName: 'Rajdhani',
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
      return container;
    }

    testWidgets('opening the sheet logs nothing', (tester) async {
      final c = await openSheet(tester);
      // Only actions are actions.
      expect(c.read(sosAuditLogProvider), isEmpty);
    });

    testWidgets('a successful 139 tap logs handedOff with the snapshot',
        (tester) async {
      final c = await openSheet(tester, pnr: '2154783921');

      await tester.enterText(find.byType(TextField), 'B3');
      await tester.pump();
      await tester.tap(find.text('Call 139 – Railway Helpline'));
      await tester.pumpAndSettle();

      final e = c.read(sosAuditLogProvider).single;
      expect(e.action, SosAuditAction.callRailwayHelpline);
      expect(e.outcome, SosAuditOutcome.handedOff);
      expect(e.trainLine, '12951 Rajdhani');
      expect(e.coach, 'B3');
      expect(e.pnr, '2154783921');
      expect(e.locationLabel, 'Location unavailable');
    });

    testWidgets('112 logs as its own action', (tester) async {
      final c = await openSheet(tester);

      await tester.tap(find.text('Call 112 – Emergency'));
      await tester.pumpAndSettle();

      expect(
        c.read(sosAuditLogProvider).single.action,
        SosAuditAction.callEmergency,
      );
    });

    testWidgets('a launch that cannot resolve still logs the attempt',
        (tester) async {
      final c = await openSheet(tester, launchSucceeds: false);

      await tester.tap(find.text('Call 139 – Railway Helpline'));
      await tester.pumpAndSettle();

      // The URI was built and offered to the OS...
      expect(launched.single.toString(), 'tel:139');
      final e = c.read(sosAuditLogProvider).single;
      // ...the tap is on the record...
      expect(e.action, SosAuditAction.callRailwayHelpline);
      // ...but it is not filed as though the dialer opened.
      expect(e.outcome, SosAuditOutcome.launchFailed);
    });

    testWidgets('texting logs the contact, masked', (tester) async {
      final c = await openSheet(tester, contacts: const ['9876543210']);

      await tester.tap(find.text('Text my emergency contact'));
      await tester.pumpAndSettle();

      final e = c.read(sosAuditLogProvider).single;
      expect(e.action, SosAuditAction.textContact);
      expect(e.outcome, SosAuditOutcome.handedOff);
      expect(e.contactLabel, 'Mum');
      expect(e.contactMasked, contains('3210'));
      expect(e.contactMasked, isNot(contains('98765')));
      expect(e.noContactFallback, isFalse);
    });

    testWidgets('the gated text action logs the fallback before navigating',
        (tester) async {
      final c = await openSheet(tester);

      await tester.tap(find.text('Add an emergency contact'));
      await tester.pumpAndSettle();

      final e = c.read(sosAuditLogProvider).single;
      expect(e.action, SosAuditAction.textContact);
      expect(e.outcome, SosAuditOutcome.notAttempted);
      expect(e.noContactFallback, isTrue);
      // Nothing was handed to the OS.
      expect(launched, isEmpty);
    });

    testWidgets('two actions in one session both land, newest first',
        (tester) async {
      final c = await openSheet(tester);

      await tester.tap(find.text('Call 139 – Railway Helpline'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Call 112 – Emergency'));
      await tester.pumpAndSettle();

      final entries = c.read(sosAuditLogProvider);
      expect(entries, hasLength(2));
      expect(entries.first.action, SosAuditAction.callEmergency);
      expect(entries.last.action, SosAuditAction.callRailwayHelpline);
    });
  });

  // ===========================================================================
  group('SOS activity screen', () {
    setUp(() => AppColors.palette = AppPalette.dark);

    Future<ProviderContainer> openScreen(
      WidgetTester tester, {
      Map<String, Object> prefs = const {},
    }) async {
      SharedPreferences.setMockInitialValues(prefs);
      final loaded = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(loaded)],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.themeFor(AppPalette.dark),
            home: const SosAuditScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('an empty log explains itself instead of showing a bare list',
        (tester) async {
      await openScreen(tester);

      expect(find.text('No SOS activity yet'), findsOneWidget);
      // Nothing to clear, so no destructive button is offered.
      expect(find.text('Clear all'), findsNothing);
    });

    testWidgets('entries list newest first and expand to the full snapshot',
        (tester) async {
      final c = await openScreen(tester);
      final log = c.read(sosAuditLogProvider.notifier);
      log.record(
        action: SosAuditAction.callEmergency,
        outcome: SosAuditOutcome.handedOff,
        context: const SosContext(trainNumber: '11111', trainName: 'Older'),
        at: DateTime.now().subtract(const Duration(hours: 3)),
      );
      log.record(
        action: SosAuditAction.callRailwayHelpline,
        outcome: SosAuditOutcome.handedOff,
        context: _snapshot,
        at: DateTime.now(),
      );
      await tester.pumpAndSettle();

      expect(find.text(SosAuditAction.callRailwayHelpline.label), findsOneWidget);
      expect(find.text(SosAuditAction.callEmergency.label), findsOneWidget);

      // Newest first: the 139 tile sits above the 112 tile.
      final newest = tester
          .getTopLeft(find.text(SosAuditAction.callRailwayHelpline.label))
          .dy;
      final oldest =
          tester.getTopLeft(find.text(SosAuditAction.callEmergency.label)).dy;
      expect(newest, lessThan(oldest));

      // Collapsed: the snapshot is hidden.
      expect(find.text('12951 Mumbai Rajdhani Express'), findsNothing);

      await tester.tap(find.text(SosAuditAction.callRailwayHelpline.label));
      await tester.pumpAndSettle();

      expect(find.text('12951 Mumbai Rajdhani Express'), findsOneWidget);
      expect(find.text('B3'), findsOneWidget);
      expect(find.text('2154783921'), findsOneWidget);
      expect(find.text('Near Kalyan Jn (KYN) · 2.1 km'), findsOneWidget);
      expect(find.text('19.24313, 73.13052'), findsOneWidget);
    });

    testWidgets('an expanded entry omits fields that were unknown',
        (tester) async {
      final c = await openScreen(tester);
      c.read(sosAuditLogProvider.notifier).record(
            action: SosAuditAction.callEmergency,
            outcome: SosAuditOutcome.handedOff,
            context: const SosContext(location: SosLocationUnavailable()),
          );
      await tester.pumpAndSettle();

      await tester.tap(find.text(SosAuditAction.callEmergency.label));
      await tester.pumpAndSettle();

      expect(find.text('LOCATION'), findsOneWidget);
      // No train, coach, PNR or contact was known, so no empty rows for them.
      expect(find.text('TRAIN'), findsNothing);
      expect(find.text('COACH'), findsNothing);
      expect(find.text('PNR'), findsNothing);
      expect(find.text('CONTACT'), findsNothing);
      expect(find.text('COORDS'), findsNothing);
    });

    testWidgets('the fallback entry says why nothing was sent', (tester) async {
      final c = await openScreen(tester);
      c.read(sosAuditLogProvider.notifier).record(
            action: SosAuditAction.textContact,
            outcome: SosAuditOutcome.notAttempted,
            context: _snapshot,
            noContactFallback: true,
          );
      await tester.pumpAndSettle();

      expect(find.textContaining('No contact was configured'), findsOneWidget);

      await tester.tap(find.text(SosAuditAction.textContact.label));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('No emergency contact was saved at this point'),
        findsOneWidget,
      );
    });

    testWidgets('the screen refuses to claim a call connected', (tester) async {
      final c = await openScreen(tester);
      c.read(sosAuditLogProvider.notifier).record(
            action: SosAuditAction.callEmergency,
            outcome: SosAuditOutcome.handedOff,
            context: _snapshot,
          );
      await tester.pumpAndSettle();

      // The disclaimer is on screen next to the entries, not buried.
      expect(
        find.textContaining('does not confirm a call connected'),
        findsOneWidget,
      );
    });

    testWidgets('there is no per-entry delete, only Clear all', (tester) async {
      final c = await openScreen(tester);
      c.read(sosAuditLogProvider.notifier).record(
            action: SosAuditAction.callEmergency,
            outcome: SosAuditOutcome.handedOff,
            context: _snapshot,
          );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.delete_outline_rounded), findsNothing);
      expect(find.byIcon(Icons.close_rounded), findsNothing);
      expect(find.text('Clear all'), findsOneWidget);
    });

    testWidgets('Clear all is confirmed, and cancelling keeps the history',
        (tester) async {
      final c = await openScreen(tester);
      c.read(sosAuditLogProvider.notifier).record(
            action: SosAuditAction.callEmergency,
            outcome: SosAuditOutcome.handedOff,
            context: _snapshot,
          );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Clear all'));
      await tester.pumpAndSettle();
      expect(find.text('Clear all SOS activity?'), findsOneWidget);

      await tester.tap(find.text('Keep'));
      await tester.pumpAndSettle();
      expect(c.read(sosAuditLogProvider), hasLength(1));

      await tester.tap(find.text('Clear all'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(Container, 'Clear all').last);
      await tester.pumpAndSettle();

      expect(c.read(sosAuditLogProvider), isEmpty);
      expect(find.text('No SOS activity yet'), findsOneWidget);
    });
  });
}

/// Stands in for [NearestStationService] so no geolocator channel is touched and
/// no 6s/20s permission timeout outlives a widget test.
class _NoLocation extends NearestStationService {
  _NoLocation(super.ref);

  @override
  Future<NearestStationResult> find({
    bool forceRefresh = false,
    bool requestPermission = true,
  }) async =>
      const NearestStationFailure(
        NearestStationError.permissionDenied,
        'Location access is needed to find the nearest station.',
      );

  @override
  ({double lat, double lng, double? accuracyM, DateTime at})? get lastFix => null;
}
