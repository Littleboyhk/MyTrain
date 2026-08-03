/// A summary of a train service, used in search results and passed into the
/// live tracking screen as the train's identity.
class TrainSummary {
  final String number;
  final String name;
  final String fromCode;
  final String fromName;
  final String toCode;
  final String toName;

  /// Departure / arrival clock times, `HH:MM`. Null when unknown.
  ///
  /// NULLABLE BECAUSE A PNR RESPONSE HAS NO TIMETABLE. These are real on the
  /// search and catalog paths, but a PNR lookup returns booking data, not the
  /// train's schedule. The RapidAPI PNR mapper used to fill in `17:00` and
  /// `08:35` — a specific, plausible, wrong departure time for every train — and
  /// the RailKit one used `--:--` sentinels. Absent is now absent, and callers
  /// render a dash rather than a fiction.
  final String? departure;
  final String? arrival;

  /// e.g. `15h 35m`. Null when unknown — see [departure].
  final String? duration;

  /// e.g. `Daily` or `Mon, Wed, Fri`. Null when unknown.
  ///
  /// Both PNR mappers hardcoded `Daily`, which asserts a running pattern nothing
  /// in the response states. [runningDaysMask] is the precise source and is
  /// already documented as null-when-unknown; this is its human-readable
  /// counterpart and gets the same treatment.
  final String? daysLabel;

  /// e.g. `Rajdhani`, `Superfast`, `Express`.
  final String type;

  /// Whole days the arrival falls after departure (0 = same day, 1 = +1 day).
  final int arrivalDayOffset;

  /// RailKit's raw 7-character running-days bitmask, e.g. `"1111111"` (daily)
  /// or `"0000010"`. **Bit order is Monday-first** (index 0 = Mon … 6 = Sun).
  ///
  /// Null when unknown — the UI then falls back to [daysLabel] rather than
  /// guessing which days a train runs.
  final String? runningDaysMask;

  /// Optional `runs till <date>` note for limited-period services. RailKit's
  /// current search/getTrainInfo payloads don't include this, so it stays null
  /// unless a source provides it — never invented.
  final String? runsUntilLabel;

  const TrainSummary({
    required this.number,
    required this.name,
    required this.fromCode,
    required this.fromName,
    required this.toCode,
    required this.toName,
    this.departure,
    this.arrival,
    this.duration,
    this.daysLabel,
    required this.type,
    this.arrivalDayOffset = 0,
    this.runningDaysMask,
    this.runsUntilLabel,
  });

  /// True when the mask says all seven days.
  bool get runsDaily => runningDaysMask == '1111111';

  /// Whether the train runs on a given weekday, using Dart's
  /// [DateTime.monday]..[DateTime.sunday] (1..7). Null when unknown.
  bool? runsOnWeekday(int weekday) {
    final m = runningDaysMask;
    if (m == null || m.length != 7) return null;
    if (weekday < DateTime.monday || weekday > DateTime.sunday) return null;
    return m[weekday - 1] == '1'; // mask is Monday-first
  }
}
