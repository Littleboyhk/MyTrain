import 'package:flutter/foundation.dart';

@immutable
class CancelledTrain {
  final String trainNumber;
  final String trainName;
  final String origin;
  final String destination;
  final String cancellationType; // 'FULL' | 'PARTIAL'
  final String startDate;
  final String endDate;

  const CancelledTrain({
    required this.trainNumber,
    required this.trainName,
    required this.origin,
    required this.destination,
    required this.cancellationType,
    required this.startDate,
    required this.endDate,
  });

  bool get isFullyCancelled => cancellationType.toUpperCase() == 'FULL';
}
