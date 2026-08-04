import 'package:flutter/foundation.dart';

@immutable
class StationBoardEntry {
  final String trainNumber;
  final String trainName;
  final String origin;
  final String destination;
  final String scheduledTime;
  final String expectedTime;
  final int delayMinutes;
  final String platform;
  final String status; // 'ARRIVED' | 'DEPARTED' | 'ON TIME' | 'DELAYED' | 'CANCELLED'

  const StationBoardEntry({
    required this.trainNumber,
    required this.trainName,
    required this.origin,
    required this.destination,
    required this.scheduledTime,
    required this.expectedTime,
    required this.delayMinutes,
    required this.platform,
    required this.status,
  });

  bool get isDelayed => delayMinutes > 0;
}
