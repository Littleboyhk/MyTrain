import 'station.dart';

/// Static description of a train and the ordered stops on its route.
class Journey {
  final String trainNumber;
  final String trainName;
  final List<Station> stations;

  /// Raw hyphen-delimited coach sequence, e.g. `ENG-SLRD-GEN-S1-PC-B1-A1-LPR`.
  ///
  /// Carried as the unparsed string rather than a parsed model so this stays a
  /// plain data holder; [CoachPosition.parse] turns it into something renderable.
  ///
  /// Only RailRadar supplies it, and it arrives inside the route payload the app
  /// already fetches — so surfacing coach position costs NO additional API call.
  /// It was previously parsed and discarded. Null on every other path: the
  /// RailKit-only fallback, the offline cache, and trains RailRadar has no
  /// composition for. Callers must handle null rather than assume a sequence.
  final String? coachPosition;

  const Journey({
    required this.trainNumber,
    required this.trainName,
    required this.stations,
    this.coachPosition,
  });

  Station get origin => stations.first;
  Station get destination => stations.last;

  double get totalDistanceKm => stations.last.distanceFromOriginKm;
}
