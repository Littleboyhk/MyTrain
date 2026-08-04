import 'package:flutter/foundation.dart';

@immutable
class AvailabilityDay {
  final String date;
  final String status;
  final String fare;
  final String statusType; // 'AVL' | 'WL' | 'RAC' | 'REGRET' | 'UNKNOWN'

  const AvailabilityDay({
    required this.date,
    required this.status,
    required this.fare,
    required this.statusType,
  });

  factory AvailabilityDay.fromMap(Map<String, dynamic> map) {
    final statusStr = (map['status'] ?? map['current_status'] ?? '').toString();
    String type = 'UNKNOWN';
    if (statusStr.toUpperCase().contains('AVAILABLE') || statusStr.toUpperCase().contains('AVL')) {
      type = 'AVL';
    } else if (statusStr.toUpperCase().contains('RAC')) {
      type = 'RAC';
    } else if (statusStr.toUpperCase().contains('WL') || statusStr.toUpperCase().contains('WAITING')) {
      type = 'WL';
    } else if (statusStr.toUpperCase().contains('REGRET') || statusStr.toUpperCase().contains('NOT AVAILABLE')) {
      type = 'REGRET';
    }

    return AvailabilityDay(
      date: (map['date'] ?? map['journey_date'] ?? '').toString(),
      status: statusStr.isEmpty ? 'N/A' : statusStr,
      fare: (map['fare'] ?? map['base_fare'] ?? '0').toString(),
      statusType: type,
    );
  }
}

@immutable
class SeatAvailability {
  final String trainNumber;
  final String fromStation;
  final String toStation;
  final String classCode;
  final String quota;
  final List<AvailabilityDay> days;

  const SeatAvailability({
    required this.trainNumber,
    required this.fromStation,
    required this.toStation,
    required this.classCode,
    required this.quota,
    required this.days,
  });
}
