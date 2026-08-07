// The shared availability body, and the bottom sheet built on it.
//
// The rendering is shared between the full screen (Home) and this sheet (results
// card) precisely because a duplicated status→colour mapping is how the
// 'WAITLIST' bug survived: it read grey in one place while looking correct in the
// other. These tests assert the shared widget's five states and the sheet's
// no-auto-fetch contract.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_train/data/railkit_mappers.dart';
import 'package:my_train/data/railkit_service.dart';
import 'package:my_train/models/seat_availability.dart';
import 'package:my_train/theme/app_colors.dart';
import 'package:my_train/theme/glass_theme.dart';
import 'package:my_train/widgets/availability_results.dart';
import 'package:my_train/widgets/seat_availability_sheet.dart';

SeatAvailability realAvailability() {
  final raw = File('test/fixtures/railkit_seat_availability_16525.json')
      .readAsStringSync();
  final data = (jsonDecode(raw) as Map)['data'];
  return availabilityFromRailkit(data, 'KYJ', 'SBC', '3A', 'GN')!;
}

/// Counts calls so "no auto-fetch" can be asserted rather than assumed.
class _FakeRailKit extends RailKitService {
  _FakeRailKit({this.throwCode});

  int calls = 0;
  final RailKitErrorCode? throwCode;

  @override
  Future<RailKitResponse> getAvailability({
    required String trainNumber,
    required String from,
    required String to,
    required String date,
    String classCode = 'SL',
    String quota = 'GN',
  }) async {
    calls++;
    if (throwCode != null) {
      throw RailKitException(throwCode!, 'Unable to perform Transaction.');
    }
    final raw = File('test/fixtures/railkit_seat_availability_16525.json')
        .readAsStringSync();
    return RailKitResponse(
      data: (jsonDecode(raw) as Map)['data'],
      cached: false,
      usage: const RailKitUsage(count: 1, limit: 10000, warn: false),
    );
  }
}

Widget host(Widget child, {RailKitService? service}) {
  return ProviderScope(
    overrides: [
      if (service != null) railKitServiceProvider.overrideWithValue(service),
    ],
    child: MaterialApp(
      theme: ThemeData(
        brightness: Brightness.dark,
        extensions: <ThemeExtension<dynamic>>[GlassTheme.dark],
      ),
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  group('status colours', () {
    test('each status maps to its own colour, unknown is never green', () {
      expect(availabilityStatusColor(AvailabilityStatus.available),
          AppColors.onTime);
      expect(availabilityStatusColor(AvailabilityStatus.rac), Colors.amber);
      expect(availabilityStatusColor(AvailabilityStatus.waitlist),
          AppColors.delayed);
      expect(availabilityStatusColor(AvailabilityStatus.regret), Colors.red);
      expect(availabilityStatusColor(AvailabilityStatus.unknown),
          AppColors.textMuted);

      // The load-bearing one: an unrecognised status must not read as good news.
      expect(availabilityStatusColor(AvailabilityStatus.unknown),
          isNot(AppColors.onTime));
    });
  });

  group('the shared body distinguishes all five states', () {
    testWidgets('loading shows a spinner and no rows', (t) async {
      await t.pumpWidget(host(const AvailabilityResultsBody(
        loading: true,
        error: null,
        availability: null,
      )));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(AvailabilityDayRow), findsNothing);
    });

    testWidgets('an error is shown verbatim', (t) async {
      await t.pumpWidget(host(const AvailabilityResultsBody(
        loading: false,
        error: 'Date outside Tatkal ARP',
        availability: null,
      )));
      expect(find.text('Date outside Tatkal ARP'), findsOneWidget);
    });

    testWidgets('never-asked prompts for Check, not "no data"', (t) async {
      // These two were one message before, so a screen that had never fetched
      // looked identical to a train with nothing available.
      await t.pumpWidget(host(const AvailabilityResultsBody(
        loading: false,
        error: null,
        availability: null,
      )));
      expect(find.textContaining('tap Check'), findsOneWidget);
      expect(find.textContaining('No availability published'), findsNothing);
    });

    testWidgets('an empty result says nothing is published', (t) async {
      await t.pumpWidget(host(AvailabilityResultsBody(
        loading: false,
        error: null,
        availability: SeatAvailability(
          trainNumber: '16525',
          trainName: 'CAPE SBC EXPRESS',
          fromCode: 'KYJ',
          toCode: 'SBC',
          fromStationName: '',
          toStationName: '',
          distanceKm: null,
          classCode: '3A',
          quota: 'GN',
          fare: null,
          days: const [],
        ),
      )));
      expect(find.textContaining('No availability published'), findsOneWidget);
      expect(find.textContaining('tap Check'), findsNothing);
    });

    testWidgets('a real result renders every date with its queue position',
        (t) async {
      await t.pumpWidget(host(AvailabilityResultsBody(
        loading: false,
        error: null,
        availability: realAvailability(),
      )));
      await t.pumpAndSettle();

      expect(find.byType(AvailabilityDayRow), findsNWidgets(6));
      // "WL 15", not "WAITLIST" — the queue position is the fact wanted.
      expect(find.text('WL 15'), findsOneWidget);
      expect(find.text('WL 3'), findsOneWidget);
      expect(find.text('WAITLIST'), findsNothing);
      expect(find.text('89% Chance'), findsOneWidget);
    });

    testWidgets('the fare appears once, not per row', (t) async {
      // data.fare is one breakdown for the whole query. The old code read a
      // per-day fare that does not exist and printed ₹0 on all six rows.
      await t.pumpWidget(host(AvailabilityResultsBody(
        loading: false,
        error: null,
        availability: realAvailability(),
      )));
      await t.pumpAndSettle();

      expect(find.byType(AvailabilityFareSummary), findsOneWidget);
      expect(find.text('₹1125'), findsOneWidget);
      expect(find.textContaining('₹0'), findsNothing);
    });
  });

  group('the bottom sheet', () {
    Future<void> open(WidgetTester t, _FakeRailKit fake) async {
      await t.pumpWidget(host(
        Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => showSeatAvailabilitySheet(
              ctx,
              trainNumber: '16525',
              trainName: 'CAPE SBC EXPRESS',
              fromCode: 'KYJ',
              toCode: 'SBC',
              date: '2026-08-15',
            ),
            child: const Text('open'),
          ),
        ),
        service: fake,
      ));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
    }

    testWidgets('opens with the query named and spends nothing', (t) async {
      final fake = _FakeRailKit();
      await open(t, fake);

      expect(find.text('Seat availability'), findsOneWidget);
      expect(find.textContaining('16525'), findsWidgets);
      expect(find.textContaining('KYJ → SBC'), findsOneWidget);
      // THE CONTRACT: opening a sheet is not a request to spend a RailKit call.
      expect(fake.calls, 0);
      expect(find.textContaining('tap Check'), findsOneWidget);
    });

    testWidgets('class and quota chips are all present', (t) async {
      await open(t, _FakeRailKit());
      for (final c in ['SL', '3A', '2A', '1A', '3E', 'CC', '2S']) {
        expect(find.text(c), findsOneWidget, reason: 'missing class $c');
      }
      for (final q in ['GN', 'TQ', 'PT', 'LD', 'SS']) {
        expect(find.text(q), findsOneWidget, reason: 'missing quota $q');
      }
    });

    testWidgets('changing a chip does NOT fetch', (t) async {
      // The screen used to fetch on every dropdown change, so browsing four
      // classes cost five requests before the user asked for anything.
      final fake = _FakeRailKit();
      await open(t, fake);

      await t.tap(find.text('3A'));
      await t.pumpAndSettle();
      await t.tap(find.text('TQ'));
      await t.pumpAndSettle();

      expect(fake.calls, 0);
    });

    testWidgets('Check fetches exactly once and renders the result', (t) async {
      final fake = _FakeRailKit();
      await open(t, fake);

      await t.tap(find.text('Check availability'));
      await t.pumpAndSettle();

      expect(fake.calls, 1);
      expect(find.byType(AvailabilityDayRow), findsNWidgets(6));
      expect(find.text('WL 15'), findsOneWidget);
    });

    testWidgets('changing a chip after a result clears the stale answer',
        (t) async {
      // Leaving the previous class's numbers on screen under a new chip would
      // attribute them to a class they do not describe.
      final fake = _FakeRailKit();
      await open(t, fake);

      await t.tap(find.text('Check availability'));
      await t.pumpAndSettle();
      expect(find.byType(AvailabilityDayRow), findsNWidgets(6));

      await t.tap(find.text('2A'));
      await t.pumpAndSettle();

      expect(find.byType(AvailabilityDayRow), findsNothing);
      expect(find.textContaining('tap Check'), findsOneWidget);
      expect(fake.calls, 1, reason: 'the chip must not refetch');
    });

    testWidgets('an outage says try again, never blames the input', (t) async {
      final fake = _FakeRailKit(throwCode: RailKitErrorCode.upstreamUnavailable);
      await open(t, fake);

      await t.tap(find.text('Check availability'));
      await t.pumpAndSettle();

      expect(find.textContaining('not responding right now'), findsOneWidget);
      expect(find.textContaining('try again'), findsOneWidget);
      // Must not read as a validation failure.
      expect(find.textContaining('RailKitException'), findsNothing);
    });

    testWidgets('a validation error shows the upstream wording', (t) async {
      final fake = _FakeRailKit(throwCode: RailKitErrorCode.validation);
      await open(t, fake);

      await t.tap(find.text('Check availability'));
      await t.pumpAndSettle();

      expect(find.textContaining('Unable to perform Transaction'),
          findsOneWidget);
      expect(find.textContaining('not responding right now'), findsNothing);
    });
  });
}
