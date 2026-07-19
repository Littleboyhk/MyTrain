/// A summary of a train service, used in search results and passed into the
/// live tracking screen as the train's identity.
class TrainSummary {
  final String number;
  final String name;
  final String fromCode;
  final String fromName;
  final String toCode;
  final String toName;

  /// Departure / arrival clock times, `HH:MM`.
  final String departure;
  final String arrival;

  /// e.g. `15h 35m`.
  final String duration;

  /// e.g. `Daily` or `Mon, Wed, Fri`.
  final String daysLabel;

  /// e.g. `Rajdhani`, `Superfast`, `Express`.
  final String type;

  /// Whole days the arrival falls after departure (0 = same day, 1 = +1 day).
  final int arrivalDayOffset;

  const TrainSummary({
    required this.number,
    required this.name,
    required this.fromCode,
    required this.fromName,
    required this.toCode,
    required this.toName,
    required this.departure,
    required this.arrival,
    required this.duration,
    required this.daysLabel,
    required this.type,
    this.arrivalDayOffset = 0,
  });
}
