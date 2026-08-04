import 'train_summary.dart';

/// Represents a 2-leg split journey via an intermediate junction station.
class SplitJourneyCombo {
  const SplitJourneyCombo({
    required this.leg1,
    required this.leg2,
    required this.junctionCode,
    required this.junctionName,
    required this.layoverMinutes,
    required this.totalDurationMinutes,
    required this.isNextDayLeg2,
    this.estimatedCombinedFare,
  });

  /// Leg 1: Origin → Junction train.
  final TrainSummary leg1;

  /// Leg 2: Junction → Destination train.
  final TrainSummary leg2;

  /// Intermediate transfer station code (e.g. `CBE`, `KPD`).
  final String junctionCode;

  /// Intermediate transfer station name (e.g. `Coimbatore Junction`).
  final String junctionName;

  /// Layover buffer at the junction station, in minutes.
  final int layoverMinutes;

  /// Total travel + layover time, in minutes.
  final int totalDurationMinutes;

  /// True if Leg 2 departs on the next calendar day after Leg 1 arrival.
  final bool isNextDayLeg2;

  /// Estimated combined fare in INR (if available).
  final int? estimatedCombinedFare;

  /// Formatted layover duration, e.g. `1h 25m`.
  String get layoverFormatted {
    final h = layoverMinutes ~/ 60;
    final m = layoverMinutes % 60;
    if (h == 0) return '${m}m';
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }

  /// Formatted total journey duration, e.g. `12h 45m`.
  String get totalDurationFormatted {
    final h = totalDurationMinutes ~/ 60;
    final m = totalDurationMinutes % 60;
    if (h == 0) return '${m}m';
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }

  /// Whether this combo has a tight layover (< 20 min) that should be hidden by default.
  bool get isTightConnection => layoverMinutes < 20;

  /// Whether to display a tight-layover warning banner (< 60 min).
  bool get isTightLayoverWarning => layoverMinutes < 60;

  /// Layover buffer safety tier for color coding.
  BufferSafetyLevel get bufferSafety {
    if (layoverMinutes >= 60) return BufferSafetyLevel.safe;
    if (layoverMinutes >= 30) return BufferSafetyLevel.moderate;
    return BufferSafetyLevel.tight;
  }
}

enum BufferSafetyLevel {
  /// 60+ min buffer (Green)
  safe,

  /// 30-60 min buffer (Amber)
  moderate,

  /// Under 30 min buffer (Red)
  tight,
}
