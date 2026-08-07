// Tests for crowdsourced coach condition reports.
//
// This feature's job is to WARN other passengers, so the failure modes worth
// guarding are the ones that would make a warning wrong:
//
//   * showing yesterday's rake's problems on today's train (journey_date scoping)
//   * showing a problem that was fixed hours ago (kCoachReportWindow)
//   * a badge count that disagrees with the chips underneath it (one source)
//   * clutter on a coach nobody has complained about (render nothing at zero)
//
// Unlike the SOS button there is no telephony here, so all of this runs on
// Flutter Web and the emulator. Only the live Supabase round trip is unexercised,
// which is why the service tests target the pure aggregation and the widget tests
// inject summaries directly.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_train/data/coach_report_service.dart';
import 'package:my_train/models/coach_condition_report.dart';
import 'package:my_train/models/coach_position.dart';
import 'package:my_train/screens/coach_position_screen.dart';
import 'package:my_train/theme/app_colors.dart';
import 'package:my_train/theme/app_theme.dart';
import 'package:my_train/utils/formatters.dart';
import 'package:my_train/widgets/coach_report_chips.dart';

final DateTime _now = DateTime(2026, 8, 7, 15, 0);

CoachConditionReport report(
  String coach,
  CoachReportCategory category, {
  Duration ago = Duration.zero,
  String? note,
}) {
  return CoachConditionReport(
    coachCode: coach,
    category: category,
    createdAt: _now.subtract(ago),
    note: note,
  );
}

void main() {
  final originalClock = Fmt.use12HourClock;
  setUp(() => Fmt.use12HourClock = true);
  tearDown(() => Fmt.use12HourClock = originalClock);

  // ===========================================================================
  group('categories', () {
    test('the wire ids match the database CHECK and the Edge Function', () {
      // These three lists must agree or a report is stored that nothing renders.
      // Kept as a literal so a rename in the enum fails here rather than in
      // production.
      expect(
        CoachReportCategory.values.map((c) => c.id).toList(),
        [
          'washroom',
          'ac',
          'overcrowded',
          'seat',
          'smell',
          'water',
          'fittings',
          'safety',
          'other',
        ],
      );
    });

    test('only "other" unlocks free text', () {
      for (final c in CoachReportCategory.values) {
        expect(c.allowsNote, c == CoachReportCategory.other,
            reason: '${c.id} allowsNote should be ${c == CoachReportCategory.other}');
      }
    });

    test('an unknown id from a newer server is dropped, not rendered raw', () {
      expect(CoachReportCategory.fromId('teleporter_broken'), isNull);
      expect(CoachReportCategory.fromId(null), isNull);
      expect(CoachReportCategory.fromId('ac'), CoachReportCategory.ac);
    });

    test('the note cap is 60, matching the server and the CHECK', () {
      expect(kCoachReportNoteMax, 60);
    });

    test('the display window is a named 6 hours, not a magic number', () {
      expect(kCoachReportWindow, const Duration(hours: 6));
    });
  });

  // ===========================================================================
  group('parsing a row from the public view', () {
    test('a well-formed row parses and upper-cases the coach', () {
      final r = CoachConditionReport.fromJson({
        'coach_code': 's9',
        'category': 'washroom',
        'created_at': '2026-08-07T09:30:00.000Z',
        'note': null,
      });

      expect(r, isNotNull);
      expect(r!.coachCode, 'S9');
      expect(r.category, CoachReportCategory.washroom);
    });

    test('an unusable row is dropped rather than half-rendered', () {
      // Unknown category.
      expect(
        CoachConditionReport.fromJson({
          'coach_code': 'S9',
          'category': 'nonsense',
          'created_at': '2026-08-07T09:30:00.000Z',
        }),
        isNull,
      );
      // No coach.
      expect(
        CoachConditionReport.fromJson({
          'coach_code': '  ',
          'category': 'ac',
          'created_at': '2026-08-07T09:30:00.000Z',
        }),
        isNull,
      );
      // Unparseable timestamp: cannot be windowed, so it cannot be trusted.
      expect(
        CoachConditionReport.fromJson({
          'coach_code': 'S9',
          'category': 'ac',
          'created_at': 'whenever',
        }),
        isNull,
      );
    });

    test('a note on a fixed category is discarded', () {
      final r = CoachConditionReport.fromJson({
        'coach_code': 'B2',
        'category': 'ac',
        'created_at': '2026-08-07T09:30:00.000Z',
        'note': 'smuggled free text',
      });
      // Nothing in the UI has a place for this, and the database forbids it.
      expect(r!.note, isNull);
    });

    test('a note on "other" survives', () {
      final r = CoachConditionReport.fromJson({
        'coach_code': 'B2',
        'category': 'other',
        'created_at': '2026-08-07T09:30:00.000Z',
        'note': 'door latch broken',
      });
      expect(r!.note, 'door latch broken');
    });
  });

  // ===========================================================================
  group('counting', () {
    test('same-category reports count together rather than listing each', () {
      final summary = CoachReportSummary.fromReports(
        'S9',
        [
          report('S9', CoachReportCategory.ac, ago: const Duration(minutes: 5)),
          report('S9', CoachReportCategory.ac, ago: const Duration(minutes: 20)),
          report('S9', CoachReportCategory.ac, ago: const Duration(minutes: 40)),
          report('S9', CoachReportCategory.washroom, ago: const Duration(minutes: 8)),
        ],
        now: _now,
      );

      expect(summary.counts, hasLength(2));
      expect(summary.counts.first.category, CoachReportCategory.ac);
      expect(summary.counts.first.count, 3);
      expect(summary.total, 4);
    });

    test('a single report has no "×1" suffix', () {
      final summary = CoachReportSummary.fromReports(
        'S9',
        [report('S9', CoachReportCategory.smell)],
        now: _now,
      );
      // "×1" reads like a defect count rather than a report count.
      expect(summary.counts.single.chipLabel, 'Bad smell');
    });

    test('multiples get the count suffix', () {
      final summary = CoachReportSummary.fromReports(
        'S9',
        [
          report('S9', CoachReportCategory.ac),
          report('S9', CoachReportCategory.ac),
        ],
        now: _now,
      );
      expect(summary.counts.single.chipLabel, 'AC not working ×2');
    });

    test('the loudest category leads, ties broken by recency', () {
      final summary = CoachReportSummary.fromReports(
        'S9',
        [
          report('S9', CoachReportCategory.washroom, ago: const Duration(hours: 2)),
          report('S9', CoachReportCategory.ac, ago: const Duration(minutes: 30)),
          report('S9', CoachReportCategory.ac, ago: const Duration(minutes: 10)),
          report('S9', CoachReportCategory.smell, ago: const Duration(minutes: 1)),
        ],
        now: _now,
      );

      expect(summary.counts.map((c) => c.category), [
        CoachReportCategory.ac, // 2 reports
        CoachReportCategory.smell, // 1, most recent
        CoachReportCategory.washroom, // 1, older
      ]);
    });

    test('other coaches are ignored entirely', () {
      final summary = CoachReportSummary.fromReports(
        'S9',
        [
          report('S9', CoachReportCategory.ac),
          report('B2', CoachReportCategory.ac),
          report('B2', CoachReportCategory.washroom),
        ],
        now: _now,
      );
      expect(summary.total, 1);
    });

    test('latestAt is the newest report in any category', () {
      final summary = CoachReportSummary.fromReports(
        'S9',
        [
          report('S9', CoachReportCategory.washroom, ago: const Duration(hours: 3)),
          report('S9', CoachReportCategory.ac, ago: const Duration(minutes: 7)),
        ],
        now: _now,
      );
      expect(summary.latestAt, _now.subtract(const Duration(minutes: 7)));
    });
  });

  // ===========================================================================
  group('the 6-hour window', () {
    test('a report inside the window counts', () {
      final summary = CoachReportSummary.fromReports(
        'S9',
        [report('S9', CoachReportCategory.ac, ago: const Duration(hours: 5, minutes: 59))],
        now: _now,
      );
      expect(summary.total, 1);
    });

    test('a report exactly at the boundary is out', () {
      final summary = CoachReportSummary.fromReports(
        'S9',
        [report('S9', CoachReportCategory.ac, ago: kCoachReportWindow)],
        now: _now,
      );
      // Strictly newer than the cutoff, so the boundary itself has expired.
      expect(summary.total, 0);
    });

    test('everything aged out reads as zero, not as a stale summary', () {
      final summary = CoachReportSummary.fromReports(
        'S9',
        [
          report('S9', CoachReportCategory.ac, ago: const Duration(hours: 7)),
          report('S9', CoachReportCategory.washroom, ago: const Duration(days: 1)),
        ],
        now: _now,
      );

      expect(summary.isEmpty, isTrue);
      expect(summary.total, 0);
      expect(summary.latestAt, isNull);
    });

    test('a mixed-age set keeps only the current half', () {
      final summary = CoachReportSummary.fromReports(
        'S9',
        [
          report('S9', CoachReportCategory.ac, ago: const Duration(minutes: 10)),
          report('S9', CoachReportCategory.ac, ago: const Duration(hours: 9)),
          report('S9', CoachReportCategory.ac, ago: const Duration(hours: 20)),
        ],
        now: _now,
      );
      // A washroom cleaned at the last halt stops being advertised as dirty.
      expect(summary.counts.single.count, 1);
    });
  });

  // ===========================================================================
  group('grouping a whole rake', () {
    test('one fetch feeds every coach, keyed by code', () {
      final byCoach = CoachReportSummary.byCoach(
        [
          report('S9', CoachReportCategory.washroom),
          report('S9', CoachReportCategory.washroom),
          report('B2', CoachReportCategory.ac),
        ],
        now: _now,
      );

      expect(byCoach.keys.toSet(), {'S9', 'B2'});
      expect(byCoach['S9']!.total, 2);
      expect(byCoach['B2']!.total, 1);
    });

    test('coaches with nothing to report are absent, not present and empty', () {
      final byCoach = CoachReportSummary.byCoach(
        [report('S9', CoachReportCategory.ac, ago: const Duration(hours: 8))],
        now: _now,
      );
      // A lookup miss and "no reports" must be the same thing, so no caller has
      // to special-case an empty summary.
      expect(byCoach, isEmpty);
      expect(byCoach['S9'], isNull);
    });

    test('the badge total and the chip counts come from one source', () {
      final byCoach = CoachReportSummary.byCoach(
        [
          report('S9', CoachReportCategory.ac),
          report('S9', CoachReportCategory.ac),
          report('S9', CoachReportCategory.smell),
        ],
        now: _now,
      );

      final summary = byCoach['S9']!;
      // The badge shows `total`; the chips show per-category counts. They are
      // derived from the same grouping, so they cannot drift apart.
      expect(summary.total, 3);
      expect(summary.counts.fold<int>(0, (s, c) => s + c.count), summary.total);
    });

    test('an empty report list groups to an empty map', () {
      expect(CoachReportSummary.byCoach(const [], now: _now), isEmpty);
    });
  });

  // ===========================================================================
  group('badge', () {
    setUp(() => AppColors.palette = AppPalette.dark);

    Future<void> pumpBadge(WidgetTester tester, int count) {
      return tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.themeFor(AppPalette.dark),
          home: Scaffold(body: Center(child: CoachReportBadge(count: count))),
        ),
      );
    }

    testWidgets('zero renders nothing at all', (tester) async {
      await pumpBadge(tester, 0);
      // No dot, no outline, no placeholder: a clean coach looks exactly as it did
      // before this feature existed.
      expect(find.byType(Container), findsNothing);
      expect(find.textContaining('0'), findsNothing);
    });

    testWidgets('a count is shown', (tester) async {
      await pumpBadge(tester, 3);
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('past nine it caps rather than overflowing', (tester) async {
      await pumpBadge(tester, 14);
      expect(find.text('9+'), findsOneWidget);
      expect(find.text('14'), findsNothing);
    });
  });

  // ===========================================================================
  group('chip list', () {
    setUp(() => AppColors.palette = AppPalette.dark);

    Future<void> pumpChips(
      WidgetTester tester,
      CoachReportSummary? summary, {
      VoidCallback? onReport,
    }) {
      return tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.themeFor(AppPalette.dark),
          home: Scaffold(
            body: SingleChildScrollView(
              child: CoachReportChips(summary: summary, onReport: onReport),
            ),
          ),
        ),
      );
    }

    testWidgets('a null summary renders nothing', (tester) async {
      await pumpChips(tester, null);
      expect(find.textContaining('CROWDSOURCED'), findsNothing);
    });

    testWidgets('an empty summary renders nothing — no empty-state clutter',
        (tester) async {
      await pumpChips(
        tester,
        const CoachReportSummary(coachCode: 'S9', counts: []),
      );
      expect(find.textContaining('CROWDSOURCED'), findsNothing);
      // Specifically NOT a "no recent reports" tombstone.
      expect(find.textContaining('no recent'), findsNothing);
      expect(find.textContaining('No reports'), findsNothing);
    });

    testWidgets('counts render as chips with the unverified heading',
        (tester) async {
      await pumpChips(
        tester,
        CoachReportSummary.fromReports(
          'S9',
          [
            report('S9', CoachReportCategory.ac, ago: const Duration(minutes: 8)),
            report('S9', CoachReportCategory.ac, ago: const Duration(minutes: 30)),
            report('S9', CoachReportCategory.washroom, ago: const Duration(minutes: 50)),
          ],
          now: _now,
        ),
      );

      expect(find.text('AC not working ×2'), findsOneWidget);
      expect(find.text('Washroom dirty'), findsOneWidget);
      expect(find.text('CROWDSOURCED REPORTS · UNVERIFIED'), findsOneWidget);
    });

    testWidgets('the copy never implies the claim is confirmed or official',
        (tester) async {
      await pumpChips(
        tester,
        CoachReportSummary.fromReports(
          'S9',
          [report('S9', CoachReportCategory.ac)],
          now: _now,
        ),
      );

      expect(find.textContaining('UNVERIFIED'), findsOneWidget);
      expect(find.textContaining('Not checked by anyone'), findsOneWidget);
      // Words that would misrepresent an anonymous tap as an established fact.
      for (final forbidden in ['Confirmed', 'Verified by', 'Official', 'Railway confirms']) {
        expect(find.textContaining(forbidden), findsNothing,
            reason: 'copy must not contain "$forbidden"');
      }
    });

    testWidgets('an updated-ago line is shown', (tester) async {
      await pumpChips(
        tester,
        CoachReportSummary.fromReports(
          'S9',
          [report('S9', CoachReportCategory.ac, ago: const Duration(minutes: 8))],
          now: DateTime.now(),
        ),
      );
      expect(find.textContaining('updated'), findsOneWidget);
    });

    testWidgets('the report affordance appears only when wired', (tester) async {
      final summary = CoachReportSummary.fromReports(
        'S9',
        [report('S9', CoachReportCategory.ac)],
        now: _now,
      );

      await pumpChips(tester, summary);
      expect(find.text('Report an issue'), findsNothing);

      var taps = 0;
      await pumpChips(tester, summary, onReport: () => taps++);
      expect(find.text('Report an issue'), findsOneWidget);
      await tester.tap(find.text('Report an issue'));
      expect(taps, 1);
    });
  });

  // ===========================================================================
  group('standalone report action', () {
    setUp(() => AppColors.palette = AppPalette.dark);

    testWidgets('names the coach when one is selected', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.themeFor(AppPalette.dark),
          home: Scaffold(
            body: CoachReportAction(coachCode: 'S9', onTap: () {}),
          ),
        ),
      );
      expect(find.text('Report an issue in S9'), findsOneWidget);
    });

    testWidgets('falls back to a generic label with no coach', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.themeFor(AppPalette.dark),
          home: Scaffold(body: CoachReportAction(onTap: () {})),
        ),
      );
      expect(find.text('Report an issue'), findsOneWidget);
    });
  });

  // ===========================================================================
  group('journey-date scoping', () {
    test('the report key distinguishes two runs of the same train number', () {
      const monday =
          CoachReportKey(trainNumber: '12951', journeyDate: '2026-08-07');
      const tuesday =
          CoachReportKey(trainNumber: '12951', journeyDate: '2026-08-08');
      // The whole reason journey_date exists in this feature: the same number is
      // a different physical rake tomorrow, so a fixed problem must not carry
      // over.
      expect(monday == tuesday, isFalse);
      expect(monday.hashCode == tuesday.hashCode, isFalse);
      expect(
        monday,
        const CoachReportKey(trainNumber: '12951', journeyDate: '2026-08-07'),
      );
    });
  });

  // ===========================================================================
  group('coach selectability', () {
    test('engines and power cars carry nothing worth reporting', () {
      // The sheet filters these out. An engine has no washroom to be dirty and no
      // passengers to be crowded, so offering it would only produce noise.
      const rake = [
        CoachInfo(
          code: 'ENG',
          label: 'Locomotive',
          type: CoachType.engine,
          index: 0,
          confidence: CoachConfidence.confirmed,
        ),
        CoachInfo(
          code: 'EOG',
          label: 'Power car',
          type: CoachType.powerCar,
          index: 1,
          confidence: CoachConfidence.confirmed,
        ),
        CoachInfo(
          code: 'B2',
          label: 'AC 3-Tier',
          type: CoachType.ac3,
          index: 2,
          confidence: CoachConfidence.confirmed,
        ),
      ];

      final reportable = rake
          .where((c) =>
              c.type != CoachType.engine &&
              c.type != CoachType.powerCar &&
              c.code.trim().isNotEmpty)
          .map((c) => c.code)
          .toList();
      expect(reportable, ['B2']);
    });
  });

  // ===========================================================================
  group('Coach Position screen wiring', () {
    setUp(() => AppColors.palette = AppPalette.dark);

    /// A rake with two sleeper and two AC-3 coaches behind a loco.
    const sequence = 'ENG-S1-S2-B1-B2';

    Future<void> pumpScreen(
      WidgetTester tester, {
      String? journeyDate,
      List<CoachConditionReport> reports = const [],
      CoachReportSubmission? outcome,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            coachReportServiceProvider.overrideWith(
              (ref) => _FakeCoachReportService(ref, reports, outcome: outcome),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.themeFor(AppPalette.dark),
            home: CoachPositionScreen(
              trainNumber: '12951',
              trainName: 'MUMBAI RAJDHANI EXPRESS',
              coachPosition: sequence,
              journeyDate: journeyDate,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('with a journey date, reported coaches get a badge',
        (tester) async {
      await pumpScreen(
        tester,
        journeyDate: '2026-08-07',
        reports: [
          CoachConditionReport(
            coachCode: 'S2',
            category: CoachReportCategory.washroom,
            createdAt: DateTime.now().subtract(const Duration(minutes: 8)),
          ),
          CoachConditionReport(
            coachCode: 'S2',
            category: CoachReportCategory.smell,
            createdAt: DateTime.now().subtract(const Duration(minutes: 20)),
          ),
        ],
      );

      final badges = tester.widgetList<CoachReportBadge>(
        find.byType(CoachReportBadge),
      );
      // Exactly one coach was reported, so exactly one badge exists.
      expect(badges, hasLength(1));
      expect(badges.single.count, 2);
    });

    testWidgets('coaches with no reports get no badge', (tester) async {
      await pumpScreen(tester, journeyDate: '2026-08-07');
      expect(find.byType(CoachReportBadge), findsNothing);
    });

    testWidgets('with NO journey date the whole feature stays inert',
        (tester) async {
      await pumpScreen(
        tester,
        journeyDate: null,
        reports: [
          CoachConditionReport(
            coachCode: 'S2',
            category: CoachReportCategory.washroom,
            createdAt: DateTime.now(),
          ),
        ],
      );

      // No date means no honest way to pick a day's reports, so nothing shows —
      // not the badge, not the chips, and not the way in.
      expect(find.byType(CoachReportBadge), findsNothing);
      expect(find.textContaining('CROWDSOURCED'), findsNothing);
      expect(find.textContaining('Report an issue'), findsNothing);
      // The screen itself still works.
      expect(find.text('Coach Position'), findsOneWidget);
    });

    testWidgets('the selected coach shows its chips and a way to report',
        (tester) async {
      await pumpScreen(
        tester,
        journeyDate: '2026-08-07',
        reports: [
          CoachConditionReport(
            coachCode: 'S1',
            category: CoachReportCategory.ac,
            createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
          ),
          CoachConditionReport(
            coachCode: 'S1',
            category: CoachReportCategory.ac,
            createdAt: DateTime.now().subtract(const Duration(minutes: 25)),
          ),
        ],
      );

      // S1 is pre-selected: it is the first non-engine car.
      expect(find.text('CROWDSOURCED REPORTS · UNVERIFIED'), findsOneWidget);
      expect(find.text('AC not working ×2'), findsOneWidget);
      expect(find.text('Report an issue'), findsOneWidget);
    });

    testWidgets('a clean selected coach gets the quiet action, not the amber card',
        (tester) async {
      await pumpScreen(tester, journeyDate: '2026-08-07');

      expect(find.textContaining('CROWDSOURCED'), findsNothing);
      // A clean coach should not be dominated by an invitation to complain, but
      // the way in still has to exist.
      expect(find.textContaining('Report an issue in'), findsOneWidget);
    });

    testWidgets('the report sheet opens with the selected coach pre-filled',
        (tester) async {
      await pumpScreen(tester, journeyDate: '2026-08-07');

      await tester.tap(find.textContaining('Report an issue in'));
      await tester.pumpAndSettle();

      expect(find.text('Report an issue'), findsOneWidget);
      expect(find.text('Warn other passengers on this train today'),
          findsOneWidget);
      // Coach already chosen, so the button asks for the category next.
      expect(find.text('Pick what\'s wrong'), findsOneWidget);
      expect(find.text('Pick a coach'), findsNothing);
    });

    testWidgets('the sheet is single-select and gates Other behind a note',
        (tester) async {
      await pumpScreen(tester, journeyDate: '2026-08-07');
      await tester.tap(find.textContaining('Report an issue in'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('AC not working'));
      await tester.pump();
      expect(find.text('Submit report'), findsOneWidget);

      // A second category MOVES the selection rather than adding to it.
      await tester.tap(find.text('Bad smell'));
      await tester.pump();
      expect(find.text('Submit report'), findsOneWidget);

      // "Other" unlocks the note, and is not submittable until it has words. The
      // button must say WHICH field it is waiting on, not sit there reading
      // "Submit report" while refusing the tap.
      await tester.tap(find.text('Other'));
      await tester.pump();
      expect(find.text('WHAT HAPPENED'), findsOneWidget);
      expect(find.text('Add a few words'), findsOneWidget);
      expect(find.text('Submit report'), findsNothing);

      await tester.enterText(
          find.widgetWithText(TextField, 'Briefly, in a few words'), 'door latch broken');
      await tester.pump();
      expect(find.text('Submit report'), findsOneWidget);
    });

    testWidgets('submitting posts once with the chosen coach and category',
        (tester) async {
      await pumpScreen(tester, journeyDate: '2026-08-07');
      await tester.tap(find.textContaining('Report an issue in'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Overcrowded'));
      await tester.pump();
      await tester.tap(find.text('Submit report'));
      await tester.pumpAndSettle();

      expect(_FakeCoachReportService.submissions, hasLength(1));
      final s = _FakeCoachReportService.submissions.single;
      expect(s.trainNumber, '12951');
      expect(s.journeyDate, '2026-08-07');
      expect(s.coachCode, 'S1');
      expect(s.category, CoachReportCategory.overcrowded);
      expect(s.note, isNull);
    });

    testWidgets('a badge does not shift the strip geometry', (tester) async {
      // The badge is overlaid in a Stack rather than added to the tile's Column,
      // because _CoachStripState._maybeScrollToSelected walks the strip with a
      // hardcoded 67px stride (62 tile + 5 gap) and the coach goldens are pinned
      // to the current layout. If this test fails, the scroll-to-selected maths is
      // wrong and every coach golden needs regenerating.
      await pumpScreen(tester, journeyDate: '2026-08-07');
      final clean = tester.getRect(find.text('B2'));

      // Replace the root so the ProviderScope is disposed. Pumping the screen
      // again on top of itself would reuse the existing scope and keep the first
      // (empty) report fetch cached.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      await pumpScreen(
        tester,
        journeyDate: '2026-08-07',
        reports: [
          CoachConditionReport(
            coachCode: 'S2',
            category: CoachReportCategory.washroom,
            createdAt: DateTime.now(),
          ),
        ],
      );
      final withBadge = tester.getRect(find.text('B2'));

      expect(find.byType(CoachReportBadge), findsOneWidget);
      // A coach two positions after the badged one has not moved a pixel.
      expect(withBadge, clean);
    });

    testWidgets('a server refusal is not shown as a network error',
        (tester) async {
      await pumpScreen(
        tester,
        journeyDate: '2026-08-01',
        outcome: const CoachReportSubmission(
          CoachReportOutcome.rejected,
          message: 'That journey finished more than half a day ago.',
        ),
      );
      await tester.tap(find.textContaining('Report an issue in'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Overcrowded'));
      await tester.pump();
      await tester.tap(find.text('Submit report'));
      await tester.pumpAndSettle();

      // The server's own wording, not "check your connection" — which would send
      // the user to fix something that is not broken.
      expect(find.text('That journey finished more than half a day ago.'),
          findsOneWidget);
      expect(find.textContaining('connection'), findsNothing);

      // And the button stops inviting a retry that will be refused identically.
      expect(find.text('Can\'t report this journey'), findsOneWidget);
      expect(find.text('Submit report'), findsNothing);
    });

    testWidgets('a transient failure DOES invite a retry', (tester) async {
      await pumpScreen(
        tester,
        journeyDate: '2026-08-07',
        outcome: const CoachReportSubmission(
          CoachReportOutcome.failed,
          message: 'Couldn\'t send that report. Try again in a moment.',
        ),
      );
      await tester.tap(find.textContaining('Report an issue in'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Overcrowded'));
      await tester.pump();
      await tester.tap(find.text('Submit report'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Try again'), findsOneWidget);
      // Still submittable: unlike a refusal, this might work next time.
      expect(find.text('Submit report'), findsOneWidget);
    });

    testWidgets('the engine is never offered as a reportable coach',
        (tester) async {
      await pumpScreen(tester, journeyDate: '2026-08-07');
      await tester.tap(find.textContaining('Report an issue in'));
      await tester.pumpAndSettle();

      // The selector inside the sheet lists coaches, not traction.
      expect(find.widgetWithText(Container, 'ENG'), findsNothing);
    });
  });
}

/// Stands in for [CoachReportService] so no Supabase call is made.
///
/// Records submissions statically because the sheet constructs its own read of the
/// provider and the test needs to inspect what was sent.
class _FakeCoachReportService extends CoachReportService {
  _FakeCoachReportService(super.ref, this._reports, {this.outcome})
      : super() {
    submissions.clear();
  }

  final List<CoachConditionReport> _reports;

  /// Non-null forces a failure path, so the sheet's handling of a server refusal
  /// can be exercised without a server.
  final CoachReportSubmission? outcome;

  static final List<_Submission> submissions = [];

  @override
  Future<List<CoachConditionReport>> fetch({
    required String trainNumber,
    required String journeyDate,
    Duration window = kCoachReportWindow,
    DateTime? now,
  }) async =>
      _reports;

  @override
  Future<CoachReportSubmission> submit({
    required String trainNumber,
    required String journeyDate,
    required String coachCode,
    required CoachReportCategory category,
    String? note,
  }) async {
    submissions.add(_Submission(
      trainNumber: trainNumber,
      journeyDate: journeyDate,
      coachCode: coachCode,
      category: category,
      note: note,
    ));
    return outcome ?? const CoachReportSubmission(CoachReportOutcome.filed);
  }
}

class _Submission {
  const _Submission({
    required this.trainNumber,
    required this.journeyDate,
    required this.coachCode,
    required this.category,
    required this.note,
  });

  final String trainNumber;
  final String journeyDate;
  final String coachCode;
  final CoachReportCategory category;
  final String? note;
}
