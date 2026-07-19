import 'delay_status.dart';

/// A single live "fix" of where the train is right now.
///
/// The train is modelled as travelling along the segment that starts at
/// [fromIndex] (the last departed station) towards `fromIndex + 1`, with
/// [segmentProgress] running from 0.0 to 1.0 across that segment.
class LivePosition {
  /// Index of the last station the train has departed.
  final int fromIndex;

  /// Progress along the current segment, 0.0 → 1.0.
  final double segmentProgress;

  final DelayStatus status;
  final int delayMinutes;
  final DateTime updatedAt;

  const LivePosition({
    required this.fromIndex,
    required this.segmentProgress,
    required this.status,
    required this.delayMinutes,
    required this.updatedAt,
  });

  LivePosition copyWith({
    int? fromIndex,
    double? segmentProgress,
    DelayStatus? status,
    int? delayMinutes,
    DateTime? updatedAt,
  }) {
    return LivePosition(
      fromIndex: fromIndex ?? this.fromIndex,
      segmentProgress: segmentProgress ?? this.segmentProgress,
      status: status ?? this.status,
      delayMinutes: delayMinutes ?? this.delayMinutes,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
