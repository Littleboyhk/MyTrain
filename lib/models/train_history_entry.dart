import 'package:flutter/foundation.dart';

@immutable
class StationHistoryEntry {
  final String stationCode;
  final String stationName;
  final String scheduledArrival;
  final String actualArrival;
  final String scheduledDeparture;
  final String actualDeparture;
  final int delayMinutes;

  const StationHistoryEntry({
    required this.stationCode,
    required this.stationName,
    required this.scheduledArrival,
    required this.actualArrival,
    required this.scheduledDeparture,
    required this.actualDeparture,
    required this.delayMinutes,
  });
}

@immutable
class TrainHistoryEntry {
  final String trainNumber;
  final String date;
  final String statusNote;
  final int totalDelayMinutes;
  final List<StationHistoryEntry> stops;

  const TrainHistoryEntry({
    required this.trainNumber,
    required this.date,
    required this.statusNote,
    required this.totalDelayMinutes,
    required this.stops,
  });

  bool get isOnTime => totalDelayMinutes <= 0;
}
