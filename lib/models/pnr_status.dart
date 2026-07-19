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
  final String? coach;

  /// Berth number for a confirmed berth, e.g. `34`.
  final String? berth;

  /// Berth-type abbreviation, e.g. `LB`, `MB`, `UB`, `SL`, `SU`.
  final String? berthType;

  /// Queue position for RAC / waitlisted slots (e.g. RAC 5, WL 12).
  final int? position;

  const SeatAllocation._({
    required this.status,
    this.coach,
    this.berth,
    this.berthType,
    this.position,
  });

  const SeatAllocation.confirmed(String coach, String berth, [String? berthType])
      : this._(
          status: PassengerStatus.confirmed,
          coach: coach,
          berth: berth,
          berthType: berthType,
        );

  const SeatAllocation.rac(int position)
      : this._(status: PassengerStatus.rac, position: position);

  const SeatAllocation.waitlist(int position)
      : this._(status: PassengerStatus.waitlisted, position: position);

  const SeatAllocation.cancelled()
      : this._(status: PassengerStatus.cancelled);

  /// Primary one-line value, e.g. `B2 / 34`, `RAC 5`, `WL 12`.
  String get display => switch (status) {
        PassengerStatus.confirmed => '$coach / $berth',
        PassengerStatus.rac => 'RAC $position',
        PassengerStatus.waitlisted => 'WL $position',
        PassengerStatus.cancelled => 'Cancelled',
      };

  /// Secondary qualifier for confirmed berths, e.g. `Lower`, `Side upper`.
  String? get detail {
    if (status != PassengerStatus.confirmed || berthType == null) return null;
    return switch (berthType!.toUpperCase()) {
      'LB' => 'Lower berth',
      'MB' => 'Middle berth',
      'UB' => 'Upper berth',
      'SL' => 'Side lower',
      'SU' => 'Side upper',
      _ => berthType,
    };
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
  final DateTime journeyDate;

  /// Reserved class code, e.g. `3A`, `SL`, `2A`.
  final String travelClass;

  /// Boarding station code (usually the train's origin).
  final String boardingCode;
  final ChartStatus chartStatus;
  final List<PnrPassenger> passengers;

  const PnrResult({
    required this.pnr,
    required this.train,
    required this.journeyDate,
    required this.travelClass,
    required this.boardingCode,
    required this.chartStatus,
    required this.passengers,
  });

  int get confirmedCount =>
      passengers.where((p) => p.current.status == PassengerStatus.confirmed).length;

  /// Friendly class label for the header, e.g. `AC 3-Tier (3A)`.
  String get classLabel => switch (travelClass.toUpperCase()) {
        '1A' => 'AC First (1A)',
        '2A' => 'AC 2-Tier (2A)',
        '3A' => 'AC 3-Tier (3A)',
        '3E' => 'AC 3-Economy (3E)',
        'CC' => 'Chair Car (CC)',
        'EC' => 'Exec. Chair (EC)',
        'SL' => 'Sleeper (SL)',
        '2S' => 'Second Sitting (2S)',
        _ => travelClass,
      };

  /// e.g. `Sun, 20 Jul`.
  String get dateLabel =>
      '${Fmt.weekdayShort(journeyDate)}, ${journeyDate.day} ${Fmt.monthShort(journeyDate)}';
}
