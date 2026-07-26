// Maps RAW RailRadar JSON into the app's models.
//
// FIELD NAMES BELOW ARE CONFIRMED against a real response captured from
// GET https://api.railradar.in/v1/trains/16525 (see railkit-test/rr16525.json),
// not guessed:
//
//   data: {
//     train: { number, name, type, category, distance, duration, avgSpeed,
//              maxSpeed, totalHalts, returnTrain, coachPosition,
//              source:{code,name,lat,lng}, destination:{...}, runDays:[...] },
//     route: [ { sequence, station:{code,name,lat,lng}, isHalt,
//                platform?, speedToNextStationKmph, distance,
//                arrival?, arrivalDay?, departure?, departureDay? } ]
//   }
//
// The whole point of this source is `isHalt: false` entries — the pass-through
// stations RailKit omits. For 16525: 166 entries = 47 halts + 119 pass-through.
import 'package:flutter/foundation.dart';

import '../models/journey.dart';
import '../models/station.dart';

String _s(dynamic v, [String fallback = '']) {
  final s = v?.toString().trim() ?? '';
  return s.isEmpty ? fallback : s;
}

/// Builds a [Journey] from RailRadar's train route detail.
///
/// Returns null when the payload isn't a recognisable route, so callers can
/// fall back to RailKit — never to fabricated data.
Journey? journeyFromRailRadarRoute(dynamic data) {
  try {
    dynamic node = data;
    // Accept both the unwrapped `data` and a full {success,data} envelope.
    if (node is Map && node['data'] is Map) node = node['data'];
    if (node is! Map) return null;
    final m = node.cast<String, dynamic>();

    final routeRaw = m['route'];
    if (routeRaw is! List || routeRaw.isEmpty) return null;

    final train = (m['train'] is Map)
        ? (m['train'] as Map).cast<String, dynamic>()
        : <String, dynamic>{};
    final number = _s(train['number']);
    final name = _s(
      train['name'],
      number.isEmpty ? 'Train' : 'Train $number',
    );

    // Anchor clock times to today so the timeline can render them.
    // `arrivalDay`/`departureDay` are 1-based day-of-run counters.
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);

    DateTime? parseClock(String? hhmm, int day) {
      final v = (hhmm ?? '').trim();
      final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(v);
      if (match == null) return null; // covers '', '--', null
      final h = int.tryParse(match.group(1)!) ?? 0;
      final min = int.tryParse(match.group(2)!) ?? 0;
      final offset = (day - 1).clamp(0, 10);
      return startOfDay.add(Duration(days: offset, hours: h, minutes: min));
    }

    int dayOf(dynamic v) => (num.tryParse(_s(v, '1')) ?? 1).toInt();

    final stations = <Station>[];
    for (final raw in routeRaw) {
      if (raw is! Map) continue;
      final s = raw.cast<String, dynamic>();

      final stn = (s['station'] is Map)
          ? (s['station'] as Map).cast<String, dynamic>()
          : <String, dynamic>{};
      final code = _s(stn['code'], '—');
      final stnName = _s(stn['name'], code);

      // `isHalt` is authoritative: true = the train stops, false = passes.
      // Anything non-boolean is treated as a halt so we never hide a stop we
      // can't classify.
      final rawHalt = s['isHalt'];
      final isHalt = rawHalt is bool ? rawHalt : true;

      final arrival = parseClock(_s(s['arrival']), dayOf(s['arrivalDay']));
      final departure =
          parseClock(_s(s['departure']), dayOf(s['departureDay']));

      // Dwell time, derived from the two real clock values (RailRadar has no
      // explicit haltMinutes field). Pass-through entries carry equal
      // arrival/departure, so this is 0 for them.
      int? dwell;
      if (arrival != null && departure != null) {
        final diff = departure.difference(arrival).inMinutes;
        dwell = diff >= 0 ? diff : diff + 24 * 60;
      }

      // Platforms are meaningless where the train doesn't stop — drop them for
      // pass-through stations so no platform chip can ever be shown there.
      final platform = isHalt ? _s(s['platform'], '—') : '—';

      stations.add(Station(
        code: code,
        name: stnName,
        distanceFromOriginKm:
            (num.tryParse(_s(s['distance'], '0')) ?? 0).toDouble(),
        scheduledArrival: arrival,
        scheduledDeparture: departure,
        platform: platform,
        // Static schedule data carries no live delay — do NOT invent one.
        delayMinutes: 0,
        haltMinutes: dwell,
        // Existing "brief stop" chip flag: only meaningful for real halts.
        isHalt: isHalt && dwell != null && dwell > 0 && dwell < 2,
        isPassThrough: !isHalt,
      ));
    }

    if (stations.length < 2) return null;

    return Journey(
      trainNumber: number,
      trainName: name,
      stations: stations,
    );
  } catch (e, st) {
    debugPrint('[RailRadar] route mapping failed: $e\n$st');
    return null;
  }
}
