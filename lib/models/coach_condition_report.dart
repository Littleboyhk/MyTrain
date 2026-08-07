import 'package:flutter/foundation.dart';

/// Crowdsourced coach condition reports.
///
/// WHAT THIS IS NOT: a complaint ticket. Nothing here reaches railway staff, and
/// there is no per-user history. Reports are PUBLIC inside the app — anyone
/// looking at that coach on that train-day sees them — because the point is
/// warning the next passenger, not routing a grievance.
///
/// EVERY read and count is scoped to (trainNumber, journeyDate, coachCode). The
/// same train number runs a different physical rake every day, so a report keyed
/// on the train number alone would warn tomorrow's passengers about a problem
/// that was fixed overnight.

/// How long a report stays "current".
///
/// Named because it is load-bearing, not incidental: it is the only thing that
/// makes a report expire. Six hours is long enough to cover the stretch of a
/// journey a passenger is actually in, and short enough that a washroom cleaned
/// at the last halt stops being advertised as dirty.
const Duration kCoachReportWindow = Duration(hours: 6);

/// Maximum length of the free-text note on an `other` report.
///
/// Mirrored by NOTE_MAX in supabase/functions/submit-coach-report/index.ts and by
/// the CHECK constraint in migration 0008. Long free text on public anonymous UGC
/// is an abuse surface; this is enough to name a problem the fixed categories
/// missed and not enough to write anything else.
const int kCoachReportNoteMax = 60;

/// What can be reported about a coach.
///
/// The wire values are the `category` column and the Edge Function's CATEGORIES
/// set — they must not be renamed without changing both. [label] is what the
/// chips and the sheet show.
///
/// Coach-level granularity only. There is deliberately no per-washroom-number
/// option: "the S9 washroom" is the unit a passenger can act on.
enum CoachReportCategory {
  washroom('washroom', 'Washroom dirty / not working'),
  ac('ac', 'AC not working'),
  overcrowded('overcrowded', 'Overcrowded'),
  seat('seat', 'Seat/berth dirty or damaged'),
  smell('smell', 'Bad smell'),
  water('water', 'No drinking water'),
  fittings('fittings', 'Charging point / light / fan broken'),
  safety('safety', 'Safety concern'),

  /// The only category that unlocks free text. See [kCoachReportNoteMax].
  other('other', 'Other');

  const CoachReportCategory(this.id, this.label);

  /// Stored value. Stable wire format.
  final String id;

  /// Human label for the sheet and the chips.
  final String label;

  /// Shorter form for the count chips, where horizontal space is tight and the
  /// full sentence would wrap. Falls back to [label] where there is nothing
  /// sensible to shorten.
  String get shortLabel => switch (this) {
        CoachReportCategory.washroom => 'Washroom dirty',
        CoachReportCategory.ac => 'AC not working',
        CoachReportCategory.overcrowded => 'Overcrowded',
        CoachReportCategory.seat => 'Seat/berth damaged',
        CoachReportCategory.smell => 'Bad smell',
        CoachReportCategory.water => 'No water',
        CoachReportCategory.fittings => 'Fittings broken',
        CoachReportCategory.safety => 'Safety concern',
        CoachReportCategory.other => 'Other',
      };

  /// True only for [other]. Everything else stores no note at all.
  bool get allowsNote => this == CoachReportCategory.other;

  /// Null for an id this build does not know — a category added server-side
  /// later must not crash an older client, and a report nothing can label is
  /// better dropped than rendered as its raw id.
  static CoachReportCategory? fromId(String? id) {
    if (id == null) return null;
    for (final c in CoachReportCategory.values) {
      if (c.id == id) return c;
    }
    return null;
  }
}

/// One report as the public view returns it.
///
/// No submitter identifier and no moderation columns: those live on the base
/// table and never reach a client. See `coach_condition_reports_public` in
/// migration 0008.
@immutable
class CoachConditionReport {
  const CoachConditionReport({
    required this.coachCode,
    required this.category,
    required this.createdAt,
    this.note,
  });

  final String coachCode;
  final CoachReportCategory category;
  final DateTime createdAt;

  /// Present only for [CoachReportCategory.other].
  final String? note;

  /// Null when the row is unusable — an unknown category, a missing coach or an
  /// unparseable timestamp. Dropping it is right: a report that cannot be
  /// labelled or dated cannot warn anyone.
  static CoachConditionReport? fromJson(Map<String, dynamic> map) {
    final coach = map['coach_code']?.toString().trim().toUpperCase();
    final category = CoachReportCategory.fromId(map['category']?.toString());
    final createdAt = DateTime.tryParse(map['created_at']?.toString() ?? '');
    if (coach == null || coach.isEmpty || category == null || createdAt == null) {
      return null;
    }

    final rawNote = map['note']?.toString().trim();
    return CoachConditionReport(
      coachCode: coach,
      category: category,
      createdAt: createdAt.toLocal(),
      // A note on a fixed category is dropped rather than shown: nothing in the
      // UI has a place for it, and the database forbids it anyway.
      note: (category.allowsNote && rawNote != null && rawNote.isNotEmpty)
          ? rawNote
          : null,
    );
  }
}

/// One category and how many people reported it.
@immutable
class CoachReportCount {
  const CoachReportCount({
    required this.category,
    required this.count,
    required this.latestAt,
  });

  final CoachReportCategory category;

  /// How many reports, across all submitters. Duplicate same-category reports
  /// count TOGETHER — that repetition is the only corroboration signal in v1,
  /// which is why there is no upvote button.
  final int count;

  /// Most recent report in this category, for the "updated N min ago" line.
  final DateTime latestAt;

  /// `AC not working ×2`, or just `Bad smell` for a single report — an "×1"
  /// suffix reads like a defect count rather than a report count.
  String get chipLabel =>
      count > 1 ? '${category.shortLabel} ×$count' : category.shortLabel;
}

/// Everything currently reported about one coach on one train-day.
///
/// Only ever constructed from reports already filtered to [kCoachReportWindow];
/// [CoachReportSummary.fromReports] does that filtering itself so no caller can
/// forget to.
@immutable
class CoachReportSummary {
  const CoachReportSummary({
    required this.coachCode,
    required this.counts,
  });

  final String coachCode;

  /// Descending by count, then most-recent-first, so the loudest signal leads.
  final List<CoachReportCount> counts;

  /// Total reports across every category. This is the badge number.
  int get total => counts.fold(0, (sum, c) => sum + c.count);

  /// True when there is nothing to show. Callers render NOTHING in this case —
  /// no badge, no chips, and no "no recent reports" message, which would be
  /// clutter that says nothing.
  bool get isEmpty => counts.isEmpty;

  /// Most recent report in any category.
  DateTime? get latestAt {
    if (counts.isEmpty) return null;
    return counts
        .map((c) => c.latestAt)
        .reduce((a, b) => a.isAfter(b) ? a : b);
  }

  /// Groups [reports] for one coach, dropping anything outside the window.
  ///
  /// [now] is injectable so window behaviour is testable without waiting.
  static CoachReportSummary fromReports(
    String coachCode,
    Iterable<CoachConditionReport> reports, {
    DateTime? now,
    Duration window = kCoachReportWindow,
  }) {
    final cutoff = (now ?? DateTime.now()).subtract(window);
    final byCategory = <CoachReportCategory, List<DateTime>>{};

    for (final r in reports) {
      if (r.coachCode != coachCode) continue;
      // Aged out. Treated as if it never existed, NOT as a stale note — a report
      // past the window has no claim on the present.
      if (!r.createdAt.isAfter(cutoff)) continue;
      byCategory.putIfAbsent(r.category, () => <DateTime>[]).add(r.createdAt);
    }

    final counts = byCategory.entries
        .map((e) => CoachReportCount(
              category: e.key,
              count: e.value.length,
              latestAt: e.value.reduce((a, b) => a.isAfter(b) ? a : b),
            ))
        .toList()
      ..sort((a, b) {
        final byCount = b.count.compareTo(a.count);
        return byCount != 0 ? byCount : b.latestAt.compareTo(a.latestAt);
      });

    return CoachReportSummary(coachCode: coachCode, counts: counts);
  }

  /// Groups a whole rake's reports by coach, keyed by coach code.
  ///
  /// ONE fetch per (train, journey date) feeds both the strip badges and the
  /// selected coach's chips, so the two can never disagree about a count.
  /// Coaches with nothing to report are absent from the map rather than present
  /// and empty, so a lookup miss and "no reports" are the same thing.
  static Map<String, CoachReportSummary> byCoach(
    Iterable<CoachConditionReport> reports, {
    DateTime? now,
    Duration window = kCoachReportWindow,
  }) {
    final at = now ?? DateTime.now();
    final codes = <String>{for (final r in reports) r.coachCode};
    final out = <String, CoachReportSummary>{};
    for (final code in codes) {
      final summary =
          fromReports(code, reports, now: at, window: window);
      if (!summary.isEmpty) out[code] = summary;
    }
    return out;
  }
}
