import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../models/coach_condition_report.dart';
import 'anon_id.dart';
import 'nearest_station_service.dart';

/// Reads and writes crowdsourced coach condition reports.
///
/// READS come from `coach_condition_reports_public`, a view that excludes the
/// submitter digest, the moderation columns, and every flagged row. The base table
/// is admin-only, so this is the whole client-visible surface.
///
/// WRITES go through the `submit-coach-report` Edge Function, never a direct
/// insert: the submitter identifier has to be hashed with a salt the client must
/// not hold, and the corridor plausibility check has to run somewhere the client
/// cannot skip.
///
/// ONE FETCH PER TRAIN-DAY. Everything the UI needs — the per-coach badge counts
/// on the strip and the chip list for the selected coach — is derived from a
/// single query for the whole rake. Two queries could disagree with each other
/// about a count, and a badge that contradicts the chips beneath it is worse than
/// either being slightly stale.
class CoachReportService {
  const CoachReportService(this._ref);

  final Ref _ref;

  /// The view, not the table. See the class doc.
  static const String _view = 'coach_condition_reports_public';

  static const Duration _timeout = Duration(seconds: 10);

  /// Ceiling on rows fetched for one train-day. A 24-coach rake would need a
  /// remarkable day to exceed this, and an unbounded select on public UGC is a
  /// denial-of-service waiting to happen.
  static const int _maxRows = 500;

  /// Every current report for one train-day, newest first.
  ///
  /// Returns an empty list rather than throwing on any failure: this is a warning
  /// overlay on someone's journey, and it must never be able to break the coach
  /// screen it decorates.
  Future<List<CoachConditionReport>> fetch({
    required String trainNumber,
    required String journeyDate,
    Duration window = kCoachReportWindow,
    DateTime? now,
  }) async {
    if (!SupabaseConfig.isConfigured) return const [];

    final since = (now ?? DateTime.now()).toUtc().subtract(window);

    try {
      final rows = await Supabase.instance.client
          .from(_view)
          // Explicit columns. `select('*')` on a view is a standing invitation to
          // leak a column someone adds later without thinking about the client.
          .select('coach_code, category, note, created_at')
          .eq('train_number', trainNumber)
          // NEVER just train_number: the same number is a different rake
          // tomorrow, and yesterday's fixed washroom must not warn today.
          .eq('journey_date', journeyDate)
          .gte('created_at', since.toIso8601String())
          .order('created_at', ascending: false)
          .limit(_maxRows)
          .timeout(_timeout);

      final out = <CoachConditionReport>[];
      for (final row in rows) {
        final parsed = CoachConditionReport.fromJson(row);
        if (parsed != null) out.add(parsed);
      }
      return out;
    } on TimeoutException {
      debugPrint('[CoachReports] fetch timed out for $trainNumber/$journeyDate');
      return const [];
    } catch (e) {
      // 404 until migration 0008 is applied; PostgrestException for anything
      // else. Either way the screen renders without the overlay.
      debugPrint('[CoachReports] fetch failed: $e');
      return const [];
    }
  }

  /// Files one report.
  ///
  /// A single POST, no login: this app has no user accounts and this feature does
  /// not introduce one.
  ///
  /// Location is attached ONLY from a fix already in hand — the 60-second cache in
  /// [NearestStationService] — and never by requesting one. Raising a permission
  /// prompt in the middle of reporting a dirty washroom would be intrusive.
  ///
  /// A report WITHOUT coordinates can be refused outright by the server's timing
  /// gate (see `submit-coach-report`), which is why this returns a result rather
  /// than a bool: "your journey date doesn't look current" and "the network is
  /// down" need different words in front of the user.
  Future<CoachReportSubmission> submit({
    required String trainNumber,
    required String journeyDate,
    required String coachCode,
    required CoachReportCategory category,
    String? note,
  }) async {
    if (!SupabaseConfig.isConfigured) {
      return const CoachReportSubmission(
        CoachReportOutcome.failed,
        message: 'Reporting needs a connection to the app\'s backend.',
      );
    }

    final fix = _ref.read(nearestStationServiceProvider).lastFix;
    final fresh = fix != null &&
        DateTime.now().difference(fix.at) < NearestStationService.fixTtl;

    try {
      await Supabase.instance.client.functions
          .invoke(
            'submit-coach-report',
            body: {
              'train_number': trainNumber,
              'journey_date': journeyDate,
              'coach_code': coachCode,
              'category': category.id,
              // Sent only where it means something. The server drops a note on a
              // fixed category and the database forbids it.
              if (category.allowsNote && note != null && note.trim().isNotEmpty)
                'note': note.trim(),
              if (fresh) 'lat': fix.lat,
              if (fresh) 'lng': fix.lng,
              if (fresh) 'gps_accuracy_m': fix.accuracyM,
              // Hashed server-side with a per-train-day salt; never stored as
              // sent. Session-scoped so the server's duplicate and rate-limit
              // checks have something stable to group by.
              'anon_id': _ref.read(sessionAnonIdProvider),
            },
          )
          .timeout(_timeout);
      return const CoachReportSubmission(CoachReportOutcome.filed);
    } on TimeoutException {
      debugPrint('[CoachReports] submit timed out');
      return const CoachReportSubmission(
        CoachReportOutcome.failed,
        message: 'That took too long. Check your connection and try again.',
      );
    } on FunctionException catch (e) {
      debugPrint('[CoachReports] submit-coach-report failed: '
          'status=${e.status} details=${e.details}');

      // The server refused it on timing grounds. Its message is already written
      // for a passenger, so it is shown verbatim rather than translated into a
      // generic failure the user cannot act on.
      final details = e.details;
      if (details is Map && details['code'] == 'implausible_timing') {
        final message = details['error']?.toString();
        return CoachReportSubmission(
          CoachReportOutcome.rejected,
          message: (message == null || message.trim().isEmpty)
              ? 'That journey doesn\'t look like it\'s running right now.'
              : message.trim(),
        );
      }

      return const CoachReportSubmission(
        CoachReportOutcome.failed,
        message: 'Couldn\'t send that report. Try again in a moment.',
      );
    } catch (e) {
      debugPrint('[CoachReports] submit failed: $e');
      return const CoachReportSubmission(
        CoachReportOutcome.failed,
        message: 'Couldn\'t send that report. Try again in a moment.',
      );
    }
  }
}

/// Why a submission did or did not land.
enum CoachReportOutcome {
  filed,

  /// The server refused it — currently only the GPS-less timing gate. NOT a
  /// transient failure: retrying the same payload will be refused again, so the
  /// UI must not invite a retry.
  rejected,

  /// Transient. Worth trying again.
  failed,
}

@immutable
class CoachReportSubmission {
  const CoachReportSubmission(this.outcome, {this.message});

  final CoachReportOutcome outcome;

  /// User-facing reason. Null only when [filed].
  final String? message;

  bool get filed => outcome == CoachReportOutcome.filed;
}

final coachReportServiceProvider =
    Provider<CoachReportService>(CoachReportService.new);

/// Identifies one train-day's reports. Both parts are required — see the note on
/// journey_date throughout this feature.
@immutable
class CoachReportKey {
  const CoachReportKey({required this.trainNumber, required this.journeyDate});

  final String trainNumber;

  /// `YYYY-MM-DD`.
  final String journeyDate;

  @override
  bool operator ==(Object other) =>
      other is CoachReportKey &&
      other.trainNumber == trainNumber &&
      other.journeyDate == journeyDate;

  @override
  int get hashCode => Object.hash(trainNumber, journeyDate);

  @override
  String toString() => 'CoachReportKey($trainNumber, $journeyDate)';
}

/// Current reports for a train-day, grouped by coach code.
///
/// Coaches with nothing to report are ABSENT from the map, so a lookup miss and
/// "no current reports" are the same thing and no caller has to special-case an
/// empty summary.
///
/// An [AsyncNotifier] rather than a [FutureProvider] so submitting can refresh it
/// directly: after filing a report the user should see their own count appear,
/// which is the only feedback this feature gives.
///
/// Same `Notifier(this.arg)` + `.family` shape as [TrackingController] and
/// [PlatformVoteNotifier].
class CoachReports extends AsyncNotifier<Map<String, CoachReportSummary>> {
  CoachReports(this.arg);

  /// Which train-day this instance covers.
  final CoachReportKey arg;

  @override
  Future<Map<String, CoachReportSummary>> build() => _load();

  Future<Map<String, CoachReportSummary>> _load() async {
    final reports = await ref.read(coachReportServiceProvider).fetch(
          trainNumber: arg.trainNumber,
          journeyDate: arg.journeyDate,
        );
    return CoachReportSummary.byCoach(reports);
  }

  /// Re-reads after a submission. The service swallows its own failures, so this
  /// settles to an empty map rather than an error state.
  Future<void> refresh() async {
    state = AsyncValue.data(await _load());
  }
}

final coachReportsProvider = AsyncNotifierProvider.family<CoachReports,
    Map<String, CoachReportSummary>, CoachReportKey>(CoachReports.new);
