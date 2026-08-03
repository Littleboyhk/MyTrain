import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../utils/formatters.dart';
import 'train_summary.dart';

/// Reservation state of a single passenger, mapped to the app's semantic
/// colors (green = confirmed, amber = RAC, red = waitlisted).
enum PassengerStatus {
  confirmed,
  rac,
  waitlisted,
  cancelled;

  Color get color => switch (this) {
        PassengerStatus.confirmed => AppColors.onTime,
        PassengerStatus.rac => AppColors.delayed,
        PassengerStatus.waitlisted => AppColors.cancelled,
        PassengerStatus.cancelled => AppColors.textMuted,
      };

  IconData get icon => switch (this) {
        PassengerStatus.confirmed => Icons.check_circle_rounded,
        PassengerStatus.rac => Icons.event_seat_rounded,
        PassengerStatus.waitlisted => Icons.hourglass_bottom_rounded,
        PassengerStatus.cancelled => Icons.cancel_rounded,
      };

  /// Short code shown in pills — CNF / RAC / WL / CAN.
  String get code => switch (this) {
        PassengerStatus.confirmed => 'CNF',
        PassengerStatus.rac => 'RAC',
        PassengerStatus.waitlisted => 'WL',
        PassengerStatus.cancelled => 'CAN',
      };

  String get label => switch (this) {
        PassengerStatus.confirmed => 'Confirmed',
        PassengerStatus.rac => 'RAC',
        PassengerStatus.waitlisted => 'Waitlisted',
        PassengerStatus.cancelled => 'Cancelled',
      };

  /// Ordered desirability, used to detect a booking → current upgrade.
  int get _rank => switch (this) {
        PassengerStatus.cancelled => 0,
        PassengerStatus.waitlisted => 1,
        PassengerStatus.rac => 2,
        PassengerStatus.confirmed => 3,
      };
}

/// A single reservation slot — either the *booking* status or the *current*
/// status of one passenger. Confirmed slots carry a coach + berth; RAC and
/// waitlisted slots carry a queue [position].
class SeatAllocation {
  final PassengerStatus status;

  /// Coach id for a confirmed berth, e.g. `B2`, `A1`, `S7`.
  ///
  /// NULLABLE, AND NULL MEANS UNKNOWN. Both providers used to substitute a
  /// plausible-looking default when the field was missing — RapidAPI filled in
  /// `B1`, RailKit an em dash. A wrong coach on a real ticket sends someone to
  /// the wrong part of the train, so absent data is now absent.
  final String? coach;

  /// Berth number for a confirmed berth, e.g. `34`. Null when not supplied.
  final String? berth;

  /// Berth-type abbreviation as published: `LB`, `MB`, `UB`, `SL`/`SLB`,
  /// `SU`/`SUB`, `SM`/`SMB`. Null when the provider did not say.
  ///
  /// NEVER GUESS THIS. RapidAPI previously hardcoded `MB` for every confirmed
  /// passenger, so the berth type was right only by coincidence.
  final String? berthType;

  /// Queue position for RAC / waitlisted slots (e.g. RAC 5, WL 12).
  ///
  /// Null when the status string carried no unambiguous number. Previously
  /// defaulted to 1, 4 or 12 depending on the code path.
  final int? position;

  const SeatAllocation._({
    required this.status,
    this.coach,
    this.berth,
    this.berthType,
    this.position,
  });

  const SeatAllocation.confirmed(
    String? coach,
    String? berth, [
    String? berthType,
  ]) : this._(
          status: PassengerStatus.confirmed,
          coach: coach,
          berth: berth,
          berthType: berthType,
        );

  const SeatAllocation.rac([int? position])
      : this._(status: PassengerStatus.rac, position: position);

  const SeatAllocation.waitlist([int? position])
      : this._(status: PassengerStatus.waitlisted, position: position);

  const SeatAllocation.cancelled()
      : this._(status: PassengerStatus.cancelled);

  /// Berth-type codes we recognise.
  ///
  /// Wider than the old five: real tickets also use `SLB`/`SUB` for side berths,
  /// and Garib Rath 3A adds a side-middle (`SM`/`SMB`). Codes outside this set —
  /// `GN` in `CNF/S6/50/GN` is a quota, not a berth — are ignored rather than
  /// stored, so a quota code can never be shown as a berth type.
  static const Set<String> berthTypeCodes = {
    'LB', 'MB', 'UB', 'SL', 'SLB', 'SU', 'SUB', 'SM', 'SMB',
  };

  /// Parses a provider status string into an allocation, inventing nothing.
  ///
  /// THE SINGLE PARSER. RailKit and RapidAPI each had their own, and they
  /// disagreed about what to do with missing fields: one substituted em dashes
  /// and a position of 1, the other substituted `B1`/`12`/`MB` and positions of
  /// 4 and 12. Both are gone. Anything the string does not state comes back null.
  ///
  /// Handles `CNF/B2/34/LB`, `B2 34 LB`, `RAC 21`, `GNWL/34`, `CAN`.
  static SeatAllocation fromStatusString(String raw) {
    final s = raw.toUpperCase().trim();
    if (s.isEmpty) return const SeatAllocation.confirmed(null, null);

    if (s.contains('CAN')) return const SeatAllocation.cancelled();

    // Only a bare `RAC <n>` yields a position. In a charted string like
    // `RAC/S3/45` the first digits belong to the coach, so grabbing "the first
    // number" produced a confidently wrong queue position.
    if (s.startsWith('RAC')) {
      final m = RegExp(r'^RAC[\s/]*(\d+)$').firstMatch(s);
      return SeatAllocation.rac(
        m == null ? null : int.tryParse(m.group(1)!),
      );
    }

    // Covers WL, GNWL, PQWL, RLWL, TQWL. The number is always the tail.
    if (s.contains('WL') || s.contains('WAIT')) {
      final m = RegExp(r'(\d+)\s*$').firstMatch(s);
      return SeatAllocation.waitlist(
        m == null ? null : int.tryParse(m.group(1)!),
      );
    }

    String? coach;
    String? berth;
    String? berthType;
    for (final p in s.split(RegExp(r'[\/ ]')).where((p) => p.isNotEmpty)) {
      if (p == 'CNF' || p == 'CONF') continue;
      if (RegExp(r'^\d+$').hasMatch(p)) {
        berth ??= p;
      } else if (berthTypeCodes.contains(p)) {
        berthType ??= p;
      } else {
        coach ??= p;
      }
    }
    return SeatAllocation.confirmed(coach, berth, berthType);
  }

  /// Primary one-line value, e.g. `B2 / 34`, `RAC 5`, `WL 12`.
  ///
  /// Degrades honestly rather than printing `null` or a fabricated placeholder.
  String get display => switch (status) {
        PassengerStatus.confirmed => switch ((coach, berth)) {
            (final String c, final String b) => '$c / $b',
            (final String c, null) => c,
            (null, final String b) => 'Berth $b',
            _ => 'Confirmed',
          },
        PassengerStatus.rac =>
          position == null ? 'RAC' : 'RAC $position',
        PassengerStatus.waitlisted =>
          position == null ? 'Waitlisted' : 'WL $position',
        PassengerStatus.cancelled => 'Cancelled',
      };

  /// Secondary qualifier for confirmed berths, e.g. `Lower`, `Side upper`.
  String? get detail {
    if (status != PassengerStatus.confirmed || berthType == null) return null;
    return switch (berthType!.toUpperCase()) {
      'LB' => 'Lower berth',
      'MB' => 'Middle berth',
      'UB' => 'Upper berth',
      'SL' || 'SLB' => 'Side lower',
      'SU' || 'SUB' => 'Side upper',
      'SM' || 'SMB' => 'Side middle',
      _ => berthType,
    };
  }

  /// Everything the ticket states about the physical spot, on one line —
  /// `S6 · 34 · Side lower`.
  ///
  /// This is the honest floor for EVERY class. It asserts nothing beyond the
  /// three values the provider actually sent, so 1A, 2A and 3E get it on exactly
  /// the same footing as SL, and it is what a bay diagram degrades to whenever
  /// the modulo-8 derivation cannot be trusted.
  ///
  /// Each part is dropped when absent rather than substituted — the coach in
  /// particular, which the earlier text path omitted unconditionally even when
  /// the provider had sent it. A lone berth number is prefixed so `34` on its own
  /// is never misread as a coach id.
  String get berthLine {
    if (status != PassengerStatus.confirmed) return display;
    final b = berth;
    final d = detail;
    final parts = <String>[
      ?coach,
      if (b != null) (coach != null ? b : 'Berth $b'),
      ?d,
    ];
    return parts.isEmpty ? display : parts.join(' · ');
  }
}

/// One passenger on the ticket, with a booking → current status comparison.
class PnrPassenger {
  /// 1-based passenger number as printed on the ticket.
  final int index;
  final SeatAllocation booking;
  final SeatAllocation current;

  const PnrPassenger({
    required this.index,
    required this.booking,
    required this.current,
  });

  /// Current status is better than at booking (e.g. WL → CNF).
  bool get improved => current.status._rank > booking.status._rank;

  /// Current status is worse than at booking.
  bool get worsened => current.status._rank < booking.status._rank;
}

/// Whether the reservation chart has been prepared (berths finalized).
enum ChartStatus {
  prepared,
  notPrepared;

  Color get color => switch (this) {
        ChartStatus.prepared => AppColors.onTime,
        ChartStatus.notPrepared => AppColors.delayed,
      };

  IconData get icon => switch (this) {
        ChartStatus.prepared => Icons.fact_check_rounded,
        ChartStatus.notPrepared => Icons.pending_actions_rounded,
      };

  String get label => switch (this) {
        ChartStatus.prepared => 'Chart prepared',
        ChartStatus.notPrepared => 'Chart not prepared',
      };

  /// Short pill text.
  String get short => switch (this) {
        ChartStatus.prepared => 'PREPARED',
        ChartStatus.notPrepared => 'NOT PREPARED',
      };

  String get detail => switch (this) {
        ChartStatus.prepared =>
          'Coach and berth allocations are final for this journey.',
        ChartStatus.notPrepared =>
          'Berths may still change. The chart is usually prepared about 4 hours '
              'before departure.',
      };
}

/// The full result of a PNR lookup.
class PnrResult {
  final String pnr;
  final TrainSummary train;

  /// Date of journey. Null when the response did not carry a parseable one.
  ///
  /// The RailKit mapper reads a real `journey_date`/`doj` field but its date
  /// parser fell through to `DateTime.now()`, and the RapidAPI mapper never read
  /// the field at all — it used `now + 1 day`. Either way an unparseable response
  /// produced a confident, wrong travel date.
  final DateTime? journeyDate;

  /// Reserved class code, e.g. `3A`, `SL`, `2A`. Null when not stated.
  ///
  /// Real on the RailKit path. The RapidAPI path defaulted to `3A`, which also
  /// fed the berth-bay gating — a fabricated class could have decided whether a
  /// berth diagram was drawn.
  final String? travelClass;

  // `boardingCode` was removed: it was assigned by both mappers and all three
  // demo fixtures and read by nothing, so it existed only to carry the RapidAPI
  // mapper's hardcoded 'BCT'. The boarding station is already on
  // `train.fromCode`. Restore it only if a consumer actually needs it, and read
  // it from the payload rather than defaulting.

  /// Whether the chart is prepared. Null when the response did not say.
  ///
  /// RailKit reads `chart_status`; RapidAPI hardcoded [ChartStatus.prepared] and
  /// never looked, so it always claimed berths were final. "Chart prepared" is a
  /// claim a passenger acts on, so not knowing has to be representable.
  final ChartStatus? chartStatus;

  final List<PnrPassenger> passengers;

  const PnrResult({
    required this.pnr,
    required this.train,
    this.journeyDate,
    this.travelClass,
    this.chartStatus,
    required this.passengers,
  });

  int get confirmedCount =>
      passengers.where((p) => p.current.status == PassengerStatus.confirmed).length;

  /// Friendly class label for the header, e.g. `AC 3-Tier (3A)`.
  ///
  /// Null when the class is unknown, so the header omits the chip rather than
  /// showing a guessed class.
  String? get classLabel {
    final c = travelClass;
    if (c == null || c.trim().isEmpty) return null;
    return switch (c.toUpperCase()) {
      '1A' => 'AC First (1A)',
      '2A' => 'AC 2-Tier (2A)',
      '3A' => 'AC 3-Tier (3A)',
      '3E' => 'AC 3-Economy (3E)',
      'CC' => 'Chair Car (CC)',
      'EC' => 'Exec. Chair (EC)',
      'SL' => 'Sleeper (SL)',
      '2S' => 'Second Sitting (2S)',
      _ => c,
    };
  }

  /// e.g. `Sun, 20 Jul`. Null when the journey date is unknown.
  String? get dateLabel {
    final d = journeyDate;
    if (d == null) return null;
    return '${Fmt.weekdayShort(d)}, ${d.day} ${Fmt.monthShort(d)}';
  }
}
