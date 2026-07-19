import 'station.dart';

/// Static description of a train and the ordered stops on its route.
class Journey {
  final String trainNumber;
  final String trainName;
  final List<Station> stations;

  const Journey({
    required this.trainNumber,
    required this.trainName,
    required this.stations,
  });

  Station get origin => stations.first;
  Station get destination => stations.last;

  double get totalDistanceKm => stations.last.distanceFromOriginKm;
}
