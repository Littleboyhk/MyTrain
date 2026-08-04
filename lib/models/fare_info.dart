import 'package:flutter/foundation.dart';

@immutable
class ClassFare {
  final String classCode;
  final String className;
  final double baseFare;
  final double totalFare;

  const ClassFare({
    required this.classCode,
    required this.className,
    required this.baseFare,
    required this.totalFare,
  });
}

@immutable
class FareBreakdown {
  final String trainNumber;
  final String fromStation;
  final String toStation;
  final List<ClassFare> fares;

  const FareBreakdown({
    required this.trainNumber,
    required this.fromStation,
    required this.toStation,
    required this.fares,
  });
}
