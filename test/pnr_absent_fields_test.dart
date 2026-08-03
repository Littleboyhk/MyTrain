// Honest absence for the fields TrainSummary and PnrResult used to fabricate.
//
// WHAT WAS BEING INVENTED. The RapidAPI PNR mapper stamped every train with
// departure 17:00, arrival 08:35, duration 15h 35m and daysLabel Daily, set the
// journey date to tomorrow without reading the payload, defaulted the class to 3A
// and hardcoded the chart as prepared. The RailKit mapper was better but still
// used '--:--' sentinels, a fabricated 'Daily', a chart default of notPrepared,
// and a date parser that fell through to DateTime.now().
//
// A PNR response carries booking data, not a timetable, so the times are
// genuinely unavailable — but the journey date, class and chart flag ARE in the
// payload and were simply not being read on one path. These tests pin both: real
// values are read, and absent values stay absent.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_train/data/railkit_mappers.dart';
import 'package:my_train/l10n/app_localizations.dart';
import 'package:my_train/models/pnr_status.dart';
import 'package:my_train/models/train_summary.dart';
import 'package:my_train/theme/glass_theme.dart';
import 'package:my_train/widgets/journey_duration_bar.dart';
import 'package:my_train/widgets/running_days_row.dart';

/// A minimal RailKit PNR payload. Anything omitted is genuinely absent.
Map<String, dynamic> payload({
  Object? journeyDate,
  Object? travelClass,
  Object? chartStatus,
}) {
  return {
    'train_no': '12951',
    'train_name': 'MUMBAI RAJDHANI',
    'boarding_point': 'BCT',
    'reservation_upto': 'NDLS',
    'journey_date': ?journeyDate,
    'class': ?travelClass,
    'chart_status': ?chartStatus,
    'passengers': [
      {'booking_status': 'CNF/B2/34/LB', 'current_status': 'CNF/B2/34/LB'},
    ],
  };
}

/// RunningDaysRow reads L10n, so the delegates have to be wired or `L10n.of`
/// throws a null-check error rather than the widget failing on the data.
Widget host(Widget child, {bool dark = true}) => MaterialApp(
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      theme: ThemeData(
        brightness: dark ? Brightness.dark : Brightness.light,
        extensions: <ThemeExtension<dynamic>>[
          dark ? GlassTheme.dark : GlassTheme.light,
        ],
      ),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  group('TrainSummary absent timetable', () {
    test('the four timetable fields default to null, not placeholders', () {
      const t = TrainSummary(
        number: '12951',
        name: 'Mumbai Rajdhani',
        fromCode: 'BCT',
        fromName: 'BCT',
        toCode: 'NDLS',
        toName: 'NDLS',
        type: 'Rajdhani',
      );
      expect(t.departure, isNull);
      expect(t.arrival, isNull);
      expect(t.duration, isNull);
      expect(t.daysLabel, isNull);
    });
  });

  group('RailKit PNR mapping', () {
    test('real journey date, class and chart flag are read', () {
      final r = pnrFromRailkit(payload(
        journeyDate: '20-07-2026',
        travelClass: 'SL',
        chartStatus: 'Chart Prepared',
      ), '1234567890')!;

      expect(r.journeyDate, DateTime(2026, 7, 20));
      expect(r.travelClass, 'SL');
      expect(r.chartStatus, ChartStatus.prepared);
      expect(r.dateLabel, isNotNull);
      expect(r.classLabel, 'Sleeper (SL)');
    });

    test('an ISO journey date is read', () {
      final r = pnrFromRailkit(payload(journeyDate: '2026-07-20'), '1234567890')!;
      expect(r.journeyDate, DateTime(2026, 7, 20));
    });

    test('chart not prepared is read as such', () {
      final r =
          pnrFromRailkit(payload(chartStatus: 'Chart Not Prepared'), '1')!;
      expect(r.chartStatus, ChartStatus.notPrepared);
    });

    test('an absent journey date is null, NOT today', () {
      final r = pnrFromRailkit(payload(), '1234567890')!;
      expect(r.journeyDate, isNull);
      expect(r.dateLabel, isNull, reason: 'header omits the chip');
    });

    test('an unparseable journey date is null, NOT today', () {
      final r = pnrFromRailkit(payload(journeyDate: 'not a date'), '1')!;
      expect(r.journeyDate, isNull);
    });

    test('an absent class is null, NOT 3A', () {
      final r = pnrFromRailkit(payload(), '1234567890')!;
      expect(r.travelClass, isNull);
      expect(r.classLabel, isNull);
    });

    test('an absent chart flag is null, NOT a default either way', () {
      // Used to fall through to notPrepared, which is the safer guess but still
      // a claim the response never made.
      final r = pnrFromRailkit(payload(), '1234567890')!;
      expect(r.chartStatus, isNull);
    });

    test('an unrecognised chart value is null rather than coerced', () {
      final r = pnrFromRailkit(payload(chartStatus: 'whatever'), '1')!;
      expect(r.chartStatus, isNull);
    });

    test('the timetable fields are absent, not sentinel strings', () {
      final t = pnrFromRailkit(payload(), '1234567890')!.train;
      expect(t.departure, isNull, reason: "was '--:--'");
      expect(t.arrival, isNull, reason: "was '--:--'");
      expect(t.duration, isNull, reason: "was '—'");
      expect(t.daysLabel, isNull, reason: "was 'Daily'");
    });

    test('the berth allocation still parses, so nothing regressed', () {
      final r = pnrFromRailkit(payload(travelClass: 'SL'), '1234567890')!;
      final a = r.passengers.single.current;
      expect(a.coach, 'B2');
      expect(a.berth, '34');
      expect(a.berthType, 'LB');
    });
  });

  group('widgets survive null', () {
    testWidgets('JourneyDurationBar renders dashes, not a crash',
        (tester) async {
      await tester.pumpWidget(host(const SizedBox(
        width: 340,
        child: JourneyDurationBar(),
      )));
      await tester.pump(const Duration(milliseconds: 200));

      expect(tester.takeException(), isNull);
      expect(find.text('—'), findsNWidgets(3));
    });

    testWidgets('JourneyDurationBar still shows real values', (tester) async {
      await tester.pumpWidget(host(const SizedBox(
        width: 340,
        child: JourneyDurationBar(
          departure: '16:55',
          arrival: '06:40',
          duration: '13h 45m',
        ),
      )));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('16:55'), findsOneWidget);
      expect(find.text('06:40'), findsOneWidget);
      expect(find.text('13h 45m'), findsOneWidget);
    });

    testWidgets('RunningDaysRow with no mask and no label shows a dash',
        (tester) async {
      await tester.pumpWidget(host(const SizedBox(
        width: 340,
        child: RunningDaysRow(
          train: TrainSummary(
            number: '12951',
            name: 'X',
            fromCode: 'A',
            fromName: 'A',
            toCode: 'B',
            toName: 'B',
            type: 'Express',
          ),
        ),
      )));
      await tester.pump(const Duration(milliseconds: 200));

      expect(tester.takeException(), isNull);
      // Never a green "Daily" for an unknown schedule.
      expect(find.text('Daily'), findsNothing);
      expect(find.text('—'), findsOneWidget);
    });
  });
}
