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

import '../models/geo_point.dart';
import '../models/journey.dart';
import '../models/station.dart';
import '../models/train_summary.dart';

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
        // Geometry for offline map-matching. RailRadar has carried these all
        // along (documented in this file's header); they were previously
        // dropped. Null when absent or a (0,0) sentinel — never guessed.
        location: GeoPoint.tryParse(stn['lat'], stn['lng']),
      ));
    }

    if (stations.length < 2) return null;

    return Journey(
      trainNumber: number,
      trainName: name,
      stations: stations,
      // Rides along in a payload we are already fetching and caching for the
      // pass-through route, so the Coach Position screen costs no extra request.
      // Verified populated on 12951/12627/16332/16525. A hyphen-delimited string,
      // NOT an array — the `coachPosition[]` notation in railkit_mappers.dart
      // describes RailKit's trackTrain shape, which is a different field.
      coachPosition: _coachPositionOf(train),
    );
  } catch (e, st) {
    debugPrint('[RailRadar] route mapping failed: $e\n$st');
    return null;
  }
}

/// Pulls `train.coachPosition` out, returning null for anything unusable.
///
/// Tolerant on purpose: this is decoration on top of the route, so a surprising
/// value must never cost us the route itself.
String? _coachPositionOf(Map<String, dynamic> train) {
  final raw = train['coachPosition'];
  if (raw == null) return null;
  // Defensive: if the provider ever switches to a list, join it rather than
  // rendering `[ENG, GEN]`.
  if (raw is List) {
    final joined = raw.map((e) => e?.toString().trim() ?? '').where((e) => e.isNotEmpty).join('-');
    return joined.isEmpty ? null : joined;
  }
  final s = raw.toString().trim();
  return s.isEmpty ? null : s;
}

// ===========================================================================
// Search result mapping
// ===========================================================================

/// Builds a [TrainSummary] from RailRadar's train route detail, for the
/// "By Train No." search on the home screen.
///
/// WHAT IS AND ISN'T VERIFIED. The field *names* used here are the ones
/// documented at the top of this file. The nested value *formats* are not
/// verified: `railkit-test/rr16525.json`, cited in that header, is not present
/// in this workspace, so `train.duration`, `train.runDays` and the
/// `type` / `category` split could not be inspected against a real payload.
///
/// Everything below is therefore written to accept several plausible shapes and
/// to fall back to a value derived from the route — which *is* verified, since
/// [journeyFromRailRadarRoute] already parses it in production. Where no shape
/// is recognised the field is left empty rather than guessed at, per the
/// no-invented-data rule the rest of this file follows.
///
/// Returns null when the payload has no usable train identity, so callers can
/// treat it as "not found" instead of showing a blank card.
TrainSummary? trainSummaryFromRailRadarRoute(dynamic data) {
  try {
    dynamic node = data;
    if (node is Map && node['data'] is Map) node = node['data'];
    if (node is! Map) return null;
    final m = node.cast<String, dynamic>();

    Map<String, dynamic> obj(dynamic v) =>
        v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};

    final train = obj(m['train']);
    final number = _s(train['number']);
    if (number.isEmpty) return null;

    final routeRaw = m['route'];
    final route = routeRaw is List
        ? routeRaw.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList()
        : const <Map<String, dynamic>>[];

    // Endpoints: prefer the train object, fall back to the route's own ends.
    final src = obj(train['source']);
    final dst = obj(train['destination']);
    final firstStn = route.isEmpty ? const <String, dynamic>{} : obj(route.first['station']);
    final lastStn = route.isEmpty ? const <String, dynamic>{} : obj(route.last['station']);

    final fromCode = _s(src['code'], _s(firstStn['code'], '—'));
    final toCode = _s(dst['code'], _s(lastStn['code'], '—'));

    // Clock times come off the route ends. The train object carries no
    // top-level departure/arrival, so there is nothing else to read them from.
    final departure = _clock(route.isEmpty ? null : route.first['departure']);
    final arrival = _clock(route.isEmpty ? null : route.last['arrival']);

    final arrivalDay = route.isEmpty
        ? 1
        : (num.tryParse(_s(route.last['arrivalDay'], '1')) ?? 1).toInt();
    final dayOffset = (arrivalDay - 1).clamp(0, 10);

    final days = _railRadarRunDays(train['runDays']);

    return TrainSummary(
      number: number,
      name: _s(train['name'], 'Train $number'),
      fromCode: fromCode,
      fromName: _s(src['name'], _s(firstStn['name'], fromCode)),
      toCode: toCode,
      toName: _s(dst['name'], _s(lastStn['name'], toCode)),
      departure: departure,
      arrival: arrival,
      // `type` drives the Express/Superfast tiering on the home screen, so
      // `category` is accepted as a second chance at it before giving up.
      type: _s(train['type'], _s(train['category'])),
      duration: _railRadarDuration(
        train['duration'],
        departure: departure,
        arrival: arrival,
        dayOffset: dayOffset,
      ),
      daysLabel: days.label,
      arrivalDayOffset: dayOffset,
      // Only set when the run-days shape was unambiguous — see
      // [_railRadarRunDays]. TrainSummary documents null as "unknown", and the
      // UI falls back to daysLabel rather than showing wrong days.
      runningDaysMask: days.mask,
      // RailRadar's train object carries no limited-period end date.
      runsUntilLabel: null,
    );
  } catch (e, st) {
    debugPrint('[RailRadar] train summary mapping failed: $e\n$st');
    return null;
  }
}

/// Normalises a clock value to `HH:MM`, or '' when there isn't one.
String _clock(dynamic v) {
  final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(_s(v));
  if (match == null) return '';
  final h = (int.tryParse(match.group(1)!) ?? 0).clamp(0, 23);
  return '${h.toString().padLeft(2, '0')}:${match.group(2)}';
}

String _hm(int totalMinutes) {
  final h = totalMinutes ~/ 60;
  final m = totalMinutes % 60;
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

/// Journey duration, accepting whichever shape RailRadar actually sends.
///
/// Tried in order: an already-formatted `12h 30m`; a plain minute count; an
/// `HH:MM` span. Failing all three it is computed from the route's own endpoint
/// clocks, which is the one input here that production code already relies on.
String _railRadarDuration(
  dynamic raw, {
  required String departure,
  required String arrival,
  required int dayOffset,
}) {
  final s = _s(raw);

  if (RegExp(r'^\d+\s*h', caseSensitive: false).hasMatch(s)) return s;

  final minutes = num.tryParse(s);
  if (minutes != null && minutes > 0) return _hm(minutes.toInt());

  final span = RegExp(r'^(\d{1,3}):(\d{2})$').firstMatch(s);
  if (span != null) {
    final h = int.tryParse(span.group(1)!) ?? 0;
    final m = int.tryParse(span.group(2)!) ?? 0;
    if (h > 0 || m > 0) return _hm(h * 60 + m);
  }

  // Derive from the endpoints.
  final dep = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(departure);
  final arr = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(arrival);
  if (dep == null || arr == null) return '';
  final depMin = int.parse(dep.group(1)!) * 60 + int.parse(dep.group(2)!);
  final arrMin = int.parse(arr.group(1)!) * 60 + int.parse(arr.group(2)!);
  var total = arrMin - depMin + dayOffset * 24 * 60;
  if (total < 0) total += 24 * 60;
  return total <= 0 ? '' : _hm(total);
}

/// Run days, as a display label plus an optional Monday-first bitmask.
///
/// The mask is only produced when [raw] is a list of recognisable weekday
/// NAMES, because names map to weekdays unambiguously. A list of booleans or a
/// `"1111111"` string would also be readable, but their day order is not
/// documented for RailRadar, and `TrainSummary.runningDaysMask` is consumed as
/// Monday-first — guessing the order would silently tell users a train runs on
/// days it does not. In that case the mask stays null and only a label is given.
({String label, String? mask}) _railRadarRunDays(dynamic raw) {
  const names = <String, int>{
    'mon': 1, 'monday': 1,
    'tue': 2, 'tues': 2, 'tuesday': 2,
    'wed': 3, 'weds': 3, 'wednesday': 3,
    'thu': 4, 'thur': 4, 'thurs': 4, 'thursday': 4,
    'fri': 5, 'friday': 5,
    'sat': 6, 'saturday': 6,
    'sun': 7, 'sunday': 7,
  };
  const short = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  if (raw is! List || raw.isEmpty) return (label: '', mask: null);

  final weekdays = <int>{};
  for (final e in raw) {
    final key = _s(e).toLowerCase();
    final wd = names[key];
    if (wd == null) return (label: '', mask: null); // unrecognised shape
    weekdays.add(wd);
  }
  if (weekdays.isEmpty) return (label: '', mask: null);

  final mask = [
    for (var wd = 1; wd <= 7; wd++) weekdays.contains(wd) ? '1' : '0',
  ].join();

  if (weekdays.length == 7) return (label: 'Daily', mask: mask);

  final sorted = weekdays.toList()..sort();
  return (
    label: sorted.map((wd) => short[wd - 1]).join(', '),
    mask: mask,
  );
}
