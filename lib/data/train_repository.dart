import 'dart:math';

import '../models/rail_station.dart';
import '../models/train_summary.dart';

/// Provides train lookups.
///
/// A small catalog of real, recognisable trains powers the by-number search;
/// route (FROM → TO) results are generated deterministically per station pair
/// so the same route always yields the same plausible list until the real API
/// is wired in.
class TrainRepository {
  const TrainRepository();

  static const List<TrainSummary> catalog = [
    TrainSummary(
      number: '12951',
      name: 'Mumbai Rajdhani Express',
      fromCode: 'BCT',
      fromName: 'Mumbai Central',
      toCode: 'NDLS',
      toName: 'New Delhi',
      departure: '17:00',
      arrival: '08:35',
      duration: '15h 35m',
      daysLabel: 'Daily',
      type: 'Rajdhani',
      arrivalDayOffset: 1,
    ),
    TrainSummary(
      number: '12301',
      name: 'Howrah Rajdhani Express',
      fromCode: 'HWH',
      fromName: 'Howrah Jn',
      toCode: 'NDLS',
      toName: 'New Delhi',
      departure: '16:50',
      arrival: '10:00',
      duration: '17h 10m',
      daysLabel: 'Daily',
      type: 'Rajdhani',
      arrivalDayOffset: 1,
    ),
    TrainSummary(
      number: '12259',
      name: 'Sealdah Duronto Express',
      fromCode: 'SDAH',
      fromName: 'Sealdah',
      toCode: 'NDLS',
      toName: 'New Delhi',
      departure: '12:40',
      arrival: '08:00',
      duration: '19h 20m',
      daysLabel: 'Daily',
      type: 'Duronto',
      arrivalDayOffset: 1,
    ),
    TrainSummary(
      number: '12002',
      name: 'Bhopal Shatabdi Express',
      fromCode: 'NDLS',
      fromName: 'New Delhi',
      toCode: 'BPL',
      toName: 'Bhopal Jn',
      departure: '06:00',
      arrival: '14:05',
      duration: '8h 05m',
      daysLabel: 'Daily',
      type: 'Shatabdi',
    ),
    TrainSummary(
      number: '12615',
      name: 'Grand Trunk Express',
      fromCode: 'NDLS',
      fromName: 'New Delhi',
      toCode: 'MAS',
      toName: 'Chennai Central',
      departure: '18:40',
      arrival: '07:00',
      duration: '36h 20m',
      daysLabel: 'Daily',
      type: 'Superfast',
      arrivalDayOffset: 2,
    ),
    TrainSummary(
      number: '12621',
      name: 'Tamil Nadu Express',
      fromCode: 'MAS',
      fromName: 'Chennai Central',
      toCode: 'NDLS',
      toName: 'New Delhi',
      departure: '22:00',
      arrival: '07:15',
      duration: '33h 15m',
      daysLabel: 'Daily',
      type: 'Superfast',
      arrivalDayOffset: 2,
    ),
    TrainSummary(
      number: '12627',
      name: 'Karnataka Express',
      fromCode: 'SBC',
      fromName: 'Bangalore City Jn',
      toCode: 'NDLS',
      toName: 'New Delhi',
      departure: '19:20',
      arrival: '10:45',
      duration: '39h 25m',
      daysLabel: 'Daily',
      type: 'Superfast',
      arrivalDayOffset: 2,
    ),
    TrainSummary(
      number: '12137',
      name: 'Punjab Mail',
      fromCode: 'CSTM',
      fromName: 'Mumbai CSMT',
      toCode: 'FZR',
      toName: 'Firozpur Cantt',
      departure: '19:35',
      arrival: '05:25',
      duration: '33h 50m',
      daysLabel: 'Daily',
      type: 'Mail',
      arrivalDayOffset: 2,
    ),
    TrainSummary(
      number: '12723',
      name: 'Telangana Express',
      fromCode: 'HYB',
      fromName: 'Hyderabad Deccan',
      toCode: 'NDLS',
      toName: 'New Delhi',
      departure: '06:25',
      arrival: '11:00',
      duration: '28h 35m',
      daysLabel: 'Daily',
      type: 'Superfast',
      arrivalDayOffset: 1,
    ),
    TrainSummary(
      number: '12841',
      name: 'Coromandel Express',
      fromCode: 'SHM',
      fromName: 'Shalimar',
      toCode: 'MAS',
      toName: 'Chennai Central',
      departure: '14:50',
      arrival: '16:50',
      duration: '26h 00m',
      daysLabel: 'Daily',
      type: 'Superfast',
      arrivalDayOffset: 1,
    ),
    TrainSummary(
      number: '12009',
      name: 'Ahmedabad Shatabdi Express',
      fromCode: 'MMCT',
      fromName: 'Mumbai Central',
      toCode: 'ADI',
      toName: 'Ahmedabad Jn',
      departure: '06:25',
      arrival: '13:10',
      duration: '6h 45m',
      daysLabel: 'Daily',
      type: 'Shatabdi',
    ),
    TrainSummary(
      number: '12269',
      name: 'Chennai Duronto Express',
      fromCode: 'MAS',
      fromName: 'Chennai Central',
      toCode: 'NZM',
      toName: 'H Nizamuddin',
      departure: '06:10',
      arrival: '04:30',
      duration: '22h 20m',
      daysLabel: 'Tue, Wed, Fri, Sun',
      type: 'Duronto',
      arrivalDayOffset: 1,
    ),
  ];

  /// Search the catalog by number prefix or name substring.
  List<TrainSummary> searchByNumberOrName(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return [
      for (final t in catalog)
        if (t.number.startsWith(q) ||
            t.name.toLowerCase().contains(q) ||
            t.type.toLowerCase().contains(q))
          t,
    ];
  }

  /// Resolve a typed number to a catalog train, or synthesize a trackable
  /// placeholder so any valid-looking number can still be tracked in the demo.
  TrainSummary resolveNumber(String number) {
    final n = number.trim();
    for (final t in catalog) {
      if (t.number == n) return t;
    }
    return TrainSummary(
      number: n,
      name: 'Train $n',
      fromCode: '—',
      fromName: 'Origin',
      toCode: '—',
      toName: 'Destination',
      departure: '--:--',
      arrival: '--:--',
      duration: '—',
      daysLabel: 'Daily',
      type: 'Express',
    );
  }

  /// Deterministically generate a plausible list of trains for a route.
  List<TrainSummary> betweenStations(RailStation from, RailStation to) {
    final rng = Random('${from.code}>${to.code}'.hashCode);
    final fromCity = _city(from.name);
    final toCity = _city(to.name);

    const shapes = <String>[
      'Rajdhani',
      'Superfast',
      'Express',
      'SF Express',
      'Mail',
      'Intercity',
      'Duronto',
    ];

    final count = 4 + rng.nextInt(3); // 4..6
    final results = <TrainSummary>[];
    final usedNumbers = <String>{};

    for (var i = 0; i < count; i++) {
      final type = shapes[rng.nextInt(shapes.length)];
      final depMinutes = rng.nextInt(24 * 60);
      final durMinutes = 240 + rng.nextInt(20 * 60); // 4h..24h
      final dep = _fmtMinutes(depMinutes);
      final arrTotal = depMinutes + durMinutes;
      final arr = _fmtMinutes(arrTotal % (24 * 60));
      final dayOffset = arrTotal ~/ (24 * 60);

      String number;
      do {
        number = '${12000 + rng.nextInt(7000)}';
      } while (!usedNumbers.add(number));

      results.add(TrainSummary(
        number: number,
        name: _composeName(fromCity, toCity, type, rng),
        fromCode: from.code,
        fromName: from.name,
        toCode: to.code,
        toName: to.name,
        departure: dep,
        arrival: arr,
        duration: '${durMinutes ~/ 60}h ${(durMinutes % 60).toString().padLeft(2, '0')}m',
        daysLabel: rng.nextInt(3) == 0 ? _randomDays(rng) : 'Daily',
        type: type.replaceAll(' Express', ''),
        arrivalDayOffset: dayOffset,
      ));
    }

    results.sort((a, b) => a.departure.compareTo(b.departure));
    return results;
  }

  String _composeName(String fromCity, String toCity, String type, Random rng) {
    if (type == 'Rajdhani' || type == 'Duronto') {
      return '$toCity $type Express';
    }
    if (type == 'Intercity') {
      return '$fromCity–$toCity Intercity Express';
    }
    return '$fromCity–$toCity $type${type.endsWith('Express') ? '' : ' Express'}';
  }

  String _city(String stationName) {
    // First word, stripping common suffixes, for a cleaner train name.
    final first = stationName.split(RegExp(r'[ \-]')).first;
    return first.isEmpty ? stationName : first;
  }

  String _fmtMinutes(int minutes) {
    final h = (minutes ~/ 60) % 24;
    final m = minutes % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  String _randomDays(Random rng) {
    const all = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final days = [
      for (final d in all)
        if (rng.nextBool()) d,
    ];
    if (days.length < 2) return 'Mon, Thu';
    if (days.length > 4) return 'Daily';
    return days.join(', ');
  }
}

/// A single shared instance is fine — the repository is stateless.
const trainRepository = TrainRepository();
