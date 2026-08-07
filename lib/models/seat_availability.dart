import 'package:flutter/foundation.dart';

// Models for RailKit's `getAvailability`.
//
// VERIFIED AGAINST A REAL RESPONSE, not guessed: see
// `test/fixtures/railkit_seat_availability_16525.json`, captured 2026-08-08 for
// 16525 KYJ→SBC 3A/GN. Every key below occurs in that payload.
//
// WHAT THE PREVIOUS VERSION GOT WRONG, because it was written from assumed key
// names with no recorded response to check against:
//   * read `trainNumber`/`train_number`/`trainNo` off the top-level object, but
//     the number lives at `data.train.trainNo` — so it always came back empty;
//   * read a per-day `fare`/`base_fare`, but there is no per-day fare at all:
//     `data.fare` is ONE breakdown for the whole query — so every row showed ₹0;
//   * classified status by searching for the substring `'WL'`, which does not
//     occur in `'WAITLIST'` — so every waitlisted date fell through to UNKNOWN
//     and was colour-coded as unknown rather than amber/red.
// All three were silent: the screen rendered, it was just wrong.

/// How a date's availability should be read, and coloured.
enum AvailabilityStatus {
  /// Confirmed seats on sale.
  available,

  /// Reservation Against Cancellation — a shared berth, boarding permitted.
  rac,

  /// Waitlisted. `WAITLIST` is the verified upstream spelling.
  waitlist,

  /// Booking closed for this date: regret / not available.
  regret,

  /// Upstream said something this build does not recognise. Rendered neutrally
  /// and never coloured as if it were good news.
  unknown;

  /// Classify from the upstream `status` field, with `availabilityText` and
  /// `rawStatus` as corroboration.
  ///
  /// `WAITLIST` is the only value observed so far and is matched exactly. The
  /// others are matched on the spellings Indian Railways uses throughout the rest
  /// of this codebase (see `SeatAllocation.fromStatusString`) and are marked
  /// UNVERIFIED until a response carrying them is captured — but a wrong guess
  /// here degrades to [unknown] rather than to a false "available".
  static AvailabilityStatus parse(String status, String text, String raw) {
    final all = '${status.toUpperCase()} ${text.toUpperCase()} '
        '${raw.toUpperCase()}';

    // VERIFIED: status == "WAITLIST", availabilityText == "WL 15",
    // rawStatus == "GNWL41/WL15".
    if (status.toUpperCase() == 'WAITLIST') return AvailabilityStatus.waitlist;

    // Checked before the WL patterns: "RAC 12" contains no WL, but a rawStatus
    // can carry both, and RAC is the better news of the two.
    if (all.contains('RAC')) return AvailabilityStatus.rac;

    // UNVERIFIED spellings below.
    if (all.contains('REGRET') ||
        all.contains('NOT AVAILABLE') ||
        all.contains('BOOKING CLOSED')) {
      return AvailabilityStatus.regret;
    }
    if (all.contains('WAITLIST') ||
        all.contains('WAITING') ||
        // Word-ish match so 'WL' in a longer token is still caught, e.g. GNWL41.
        RegExp(r'\bWL\b|WL\s*\d|GNWL|PQWL|RLWL|TQWL').hasMatch(all)) {
      return AvailabilityStatus.waitlist;
    }
    if (all.contains('AVAILABLE') || all.contains('AVL')) {
      return AvailabilityStatus.available;
    }
    return AvailabilityStatus.unknown;
  }
}

/// Fare breakdown for the whole query — NOT per date.
///
/// One object at `data.fare`. All amounts are whole rupees in the observed
/// payload, and are read as num so a paise-bearing response cannot throw.
@immutable
class AvailabilityFare {
  final num baseFare;
  final num reservationCharge;
  final num superfastCharge;
  final num serviceTax;
  final num totalFare;

  const AvailabilityFare({
    required this.baseFare,
    required this.reservationCharge,
    required this.superfastCharge,
    required this.serviceTax,
    required this.totalFare,
  });

  static num _num(dynamic v) => v is num ? v : num.tryParse('$v') ?? 0;

  factory AvailabilityFare.fromMap(Map<String, dynamic> m) => AvailabilityFare(
        baseFare: _num(m['baseFare']),
        reservationCharge: _num(m['reservationCharge']),
        superfastCharge: _num(m['superfastCharge']),
        serviceTax: _num(m['serviceTax']),
        totalFare: _num(m['totalFare']),
      );
}

/// One date's availability.
@immutable
class AvailabilityDay {
  /// As sent: `"15-8-2026"` — D-M-YYYY, and NOT zero-padded, so it cannot be
  /// parsed with a fixed-width format. Kept verbatim for display fidelity.
  final String date;

  /// Parsed form of [date], or null when it would not parse.
  final DateTime? journeyDate;

  /// Upstream classification, e.g. `"WAITLIST"`.
  final String status;

  /// The short display string, e.g. `"WL 15"`. This is what belongs on screen —
  /// [status] is the category, this is the number that matters.
  final String availabilityText;

  /// The booking-system string, e.g. `"GNWL41/WL15"`. Kept because it carries the
  /// quota prefix and the original queue position.
  final String rawStatus;

  /// Confirmation-chance label, e.g. `"89% Chance"`.
  final String prediction;

  /// Numeric form of [prediction], 0–100. Null when absent.
  final int? predictionPercentage;

  /// Whether the upstream considers this date bookable. Note this is true even
  /// for a long waitlist, so it must not be shown as "seats available".
  final bool canBook;

  final AvailabilityStatus statusType;

  const AvailabilityDay({
    required this.date,
    required this.journeyDate,
    required this.status,
    required this.availabilityText,
    required this.rawStatus,
    required this.prediction,
    required this.predictionPercentage,
    required this.canBook,
    required this.statusType,
  });

  /// Parse `"15-8-2026"` / `"05-08-2026"` — day and month may be 1 or 2 digits.
  static DateTime? parseDate(String s) {
    final parts = s.trim().split('-');
    if (parts.length != 3) return null;
    final d = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final y = int.tryParse(parts[2]);
    if (d == null || m == null || y == null) return null;
    if (m < 1 || m > 12 || d < 1 || d > 31) return null;
    return DateTime(y, m, d);
  }

  static String _s(dynamic v) => v == null ? '' : v.toString();

  factory AvailabilityDay.fromMap(Map<String, dynamic> m) {
    final status = _s(m['status']);
    final text = _s(m['availabilityText']);
    final raw = _s(m['rawStatus']);
    final pct = m['predictionPercentage'];

    return AvailabilityDay(
      date: _s(m['date']),
      journeyDate: parseDate(_s(m['date'])),
      status: status,
      availabilityText: text,
      rawStatus: raw,
      prediction: _s(m['prediction']),
      predictionPercentage:
          pct is num ? pct.toInt() : int.tryParse(_s(pct)),
      // Absent means "not stated", which must not read as bookable.
      canBook: m['canBook'] == true,
      statusType: AvailabilityStatus.parse(status, text, raw),
    );
  }

  /// Best single string for a status chip: the numbered text when present, else
  /// the bare category.
  String get displayStatus =>
      availabilityText.isNotEmpty ? availabilityText : status;
}

/// A full availability answer for one train, route, class and quota.
@immutable
class SeatAvailability {
  final String trainNumber;
  final String trainName;
  final String fromCode;
  final String toCode;
  final String fromStationName;
  final String toStationName;

  /// Route distance in km for the queried leg. Null when not sent.
  final num? distanceKm;

  final String classCode;
  final String quota;

  /// One breakdown for the whole query. Null when the upstream omitted it.
  final AvailabilityFare? fare;

  final List<AvailabilityDay> days;

  const SeatAvailability({
    required this.trainNumber,
    required this.trainName,
    required this.fromCode,
    required this.toCode,
    required this.fromStationName,
    required this.toStationName,
    required this.distanceKm,
    required this.classCode,
    required this.quota,
    required this.fare,
    required this.days,
  });
}
