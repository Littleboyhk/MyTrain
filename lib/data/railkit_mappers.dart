// Maps RAW RailKit JSON into the app's models.
//
// FIELD NAMES BELOW ARE CONFIRMED against real responses captured from
// railkit v4.0.1 (see railkit-test/responses/*.json), not guessed:
//
//   searchTrainBetweenStations -> data: [ { train_no, train_name,
//       source_stn_name/code, dstn_stn_name/code, from_stn_name/code,
//       to_stn_name/code, from_time, to_time, travel_time:"13:46 hrs",
//       running_days:"1111111", distance:"752", halts:29 } ]
//
//   getTrainInfo -> data: { trainInfo: { train_no, train_name,
//       from_stn_name/code, to_stn_name/code, from_time, to_time,
//       travel_time, running_days, type, train_id },
//       route: [ { stnCode, stnName, arrival, departure, halt, haltMinutes,
//       distance, day, platform, coordinates } ] }
//
//   trackTrain -> data: { trainNo, trainName, date:"26-Jul-2026", statusNote,
//       lastUpdate, totalStations, coachPosition[], currentStationCode,
//       timeline: [ { stationCode, stationName, platform, distanceKm,
//       arrival:{scheduled,actual,delay}, departure:{...}, type, status } ] }
//       NOTE: `delay` is a STRING ("On Time"), endpoints use "SRC"/"DSTN",
//       and actual times may carry a trailing "*".
import 'package:flutter/foundation.dart';

import '../models/journey.dart';
import '../models/pnr_status.dart';
import '../models/rail_station.dart';
import '../models/station.dart';
import '../models/train_summary.dart';
import 'train_repository.dart';

// Small null-safe helper: first non-empty value among candidate keys.
dynamic _first(Map map, List<String> keys) {
  for (final k in keys) {
    final v = map[k];
    if (v != null && v.toString().trim().isNotEmpty) return v;
  }
  return null;
}

String _s(dynamic v, [String fallback = '']) {
  final s = v?.toString().trim() ?? '';
  return s.isEmpty ? fallback : s;
}

/// "1111111" -> Daily; otherwise a Mon..Sun day list.
String _daysLabel(String? bitmask) {
  final b = (bitmask ?? '').trim();
  if (b.length != 7 || !RegExp(r'^[01]{7}$').hasMatch(b)) return 'Daily';
  if (b == '1111111') return 'Daily';
  const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final on = <String>[];
  for (var i = 0; i < 7; i++) {
    if (b[i] == '1') on.add(names[i]);
  }
  if (on.isEmpty) return '—';
  if (on.length == 6) {
    final off = names.firstWhere((n) => !on.contains(n));
    return 'Daily except $off';
  }
  return on.join(', ');
}

/// "13:46 hrs" -> "13h 46m"
String _duration(String? raw) {
  final r = (raw ?? '').trim();
  final m = RegExp(r'(\d{1,3}):(\d{2})').firstMatch(r);
  if (m == null) return r.isEmpty ? '—' : r;
  return '${m.group(1)}h ${m.group(2)}m';
}

/// Duration for the leg the user actually searched: RailKit's `travel_time`
/// when present, else derived from the leg's departure/arrival times.
String _legDuration(String travelTime, String fromTime, String toTime) {
  if (travelTime.trim().isNotEmpty) return _duration(travelTime);
  final mins = durationMinutesBetween(fromTime, toTime);
  if (mins == null) return '—';
  return '${mins ~/ 60}h ${(mins % 60).toString().padLeft(2, '0')}m';
}

/// Minutes between two `HH:MM` clock times, rolling past midnight.
/// Returns null if either time can't be parsed.
int? durationMinutesBetween(String? from, String? to) {
  int? mins(String? v) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch((v ?? '').trim());
    if (m == null) return null;
    final h = int.parse(m.group(1)!), mi = int.parse(m.group(2)!);
    if (h > 23 || mi > 59) return null;
    return h * 60 + mi;
  }

  final a = mins(from), b = mins(to);
  if (a == null || b == null) return null;
  final diff = b - a;
  return diff >= 0 ? diff : diff + 24 * 60;
}

/// Normalises RailKit's running-days value to a 7-char Monday-first bitmask,
/// or null when it isn't in that form.
String? _runningMask(String? raw) {
  final v = (raw ?? '').trim();
  return RegExp(r'^[01]{7}$').hasMatch(v) ? v : null;
}

String _inferType(String name, [String? rawType]) {
  final n = '$name ${rawType ?? ''}'.toLowerCase();
  if (n.contains('rajdhani')) return 'Rajdhani';
  if (n.contains('shatabdi')) return 'Shatabdi';
  if (n.contains('vande bharat')) return 'Vande Bharat';
  if (n.contains('duronto')) return 'Duronto';
  if (n.contains('humsafar')) return 'Humsafar';
  if (n.contains('intercity')) return 'Intercity';
  if (n.contains('superfast')) return 'Superfast';
  if (n.contains('mail')) return 'Mail';
  if (n.contains('express') || n.contains('exp')) return 'Express';
  return 'Express';
}

// ---------------------------------------------------------------------------
// searchTrainBetweenStations
// ---------------------------------------------------------------------------
List<TrainSummary> trainsFromRailkitSearch(
  dynamic data,
  RailStation from,
  RailStation to,
) {
  try {
    // The Edge Function already unwraps {success,data}; accept either.
    dynamic node = data;
    if (node is Map) node = node['data'] ?? node;
    if (node is! List) return const [];

    final out = <TrainSummary>[];
    for (final raw in node) {
      if (raw is! Map) continue;
      final t = raw.cast<String, dynamic>();

      final rawNumber = _s(_first(t, ['train_no', 'train_number', 'trainNo']));
      if (rawNumber.isEmpty) continue;
      final number =
          isValidIRTrainNumber(rawNumber) ? rawNumber : rawNumber.trim();

      final name = _s(_first(t, ['train_name', 'trainName']), 'Train $number');

      out.add(TrainSummary(
        number: number,
        name: name,
        // from_/to_ describe the queried leg (what the user searched).
        fromCode: _s(_first(t, ['from_stn_code']), from.code).toUpperCase(),
        fromName: _s(_first(t, ['from_stn_name']), from.name),
        toCode: _s(_first(t, ['to_stn_code']), to.code).toUpperCase(),
        toName: _s(_first(t, ['to_stn_name']), to.name),
        departure: _s(_first(t, ['from_time']), '--:--'),
        arrival: _s(_first(t, ['to_time']), '--:--'),
        // `travel_time` from search is already for the QUERIED leg (KYJ→SBC),
        // not the train's full run, so prefer it; fall back to computing from
        // the leg's own clock times.
        duration: _legDuration(
          _s(_first(t, ['travel_time'])),
          _s(_first(t, ['from_time'])),
          _s(_first(t, ['to_time'])),
        ),
        daysLabel: _daysLabel(_s(_first(t, ['running_days']))),
        type: _inferType(name, _s(_first(t, ['type', 'train_type']))),
        runningDaysMask: _runningMask(_s(_first(t, ['running_days']))),
      ));
    }
    return out;
  } catch (e, st) {
    debugPrint('[RailKit] search mapping failed: $e\n$st');
    return const [];
  }
}

// ---------------------------------------------------------------------------
// getTrainInfo -> Journey (the REAL per-train route/timeline)
// ---------------------------------------------------------------------------

/// Builds a [Journey] (train identity + ordered stops) from `getTrainInfo`.
/// Returns null if the payload isn't a recognisable route — callers must then
/// show an error state, NEVER a substitute/hardcoded route.
Journey? journeyFromRailkitTrainInfo(dynamic data) {
  try {
    dynamic node = data;
    if (node is Map && node['data'] is Map) node = node['data'];
    if (node is! Map) return null;
    final m = node.cast<String, dynamic>();

    final info = (m['trainInfo'] is Map)
        ? (m['trainInfo'] as Map).cast<String, dynamic>()
        : <String, dynamic>{};
    final routeRaw = m['route'];
    if (routeRaw is! List || routeRaw.isEmpty) return null;

    final number = _s(_first(info, ['train_no', 'trainNo']));
    final name = _s(_first(info, ['train_name', 'trainName']),
        number.isEmpty ? 'Train' : 'Train $number');

    // Anchor times to today so the timeline can render clock values. `day`
    // (1-based) rolls the date forward for multi-day runs.
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);

    DateTime? parseClock(String? hhmm, int dayOffset) {
      final v = (hhmm ?? '').trim();
      final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(v);
      if (match == null) return null; // covers '--', 'SRC', 'DSTN', ''
      final h = int.tryParse(match.group(1)!) ?? 0;
      final min = int.tryParse(match.group(2)!) ?? 0;
      return startOfDay.add(Duration(days: dayOffset, hours: h, minutes: min));
    }

    final stations = <Station>[];
    for (final raw in routeRaw) {
      if (raw is! Map) continue;
      final s = raw.cast<String, dynamic>();
      final code = _s(_first(s, ['stnCode', 'stationCode']), '—');
      final stnName = _s(_first(s, ['stnName', 'stationName']), code);
      final dayOffset =
          ((num.tryParse(_s(s['day'], '1')) ?? 1).toInt() - 1).clamp(0, 10);
      final dist = num.tryParse(_s(_first(s, ['distance', 'distanceKm']), '0'))
              ?.toDouble() ??
          0;
      final haltMin = num.tryParse(_s(s['haltMinutes'], '0'))?.toInt() ?? 0;

      stations.add(Station(
        code: code,
        name: stnName,
        distanceFromOriginKm: dist,
        scheduledArrival: parseClock(_s(s['arrival']), dayOffset),
        scheduledDeparture: parseClock(_s(s['departure']), dayOffset),
        platform: _s(s['platform'], '—'),
        // Real schedule data carries no live delay — do NOT invent one.
        delayMinutes: 0,
        // RailKit gives e.g. haltMinutes: 1 (brief stop) .. 5 (major stop);
        // 0 at origin/terminus. Kept raw so the UI can classify.
        haltMinutes: haltMin,
        isHalt: haltMin > 0 && haltMin < 2,
      ));
    }

    if (stations.length < 2) return null;

    return Journey(
      trainNumber: number,
      trainName: name,
      stations: stations,
    );
  } catch (e, st) {
    debugPrint('[RailKit] trainInfo mapping failed: $e\n$st');
    return null;
  }
}

/// Real platform number for [stationCode] on this train's route, from
/// `getTrainInfo`. Returns null when RailKit reports no platform for that stop
/// (many smaller stations genuinely have none published) — callers must then
/// show "Platform TBA" rather than inventing a number.
String? platformForStation(dynamic data, String stationCode) {
  try {
    final wanted = stationCode.trim().toUpperCase();
    if (wanted.isEmpty) return null;

    dynamic node = data;
    if (node is Map && node['data'] is Map) node = node['data'];
    if (node is! Map) return null;
    final route = node['route'];
    if (route is! List) return null;

    for (final raw in route) {
      if (raw is! Map) continue;
      final s = raw.cast<String, dynamic>();
      final code = _s(_first(s, ['stnCode', 'stationCode'])).toUpperCase();
      if (code != wanted) continue;
      final pf = _s(s['platform']);
      // RailKit uses '' or '-' when the platform isn't published.
      if (pf.isEmpty || pf == '-' || pf == '0') return null;
      return pf;
    }
    return null;
  } catch (e) {
    debugPrint('[RailKit] platform lookup failed: $e');
    return null;
  }
}

/// Guard against ever showing one train's route under another train's name
/// (the class of bug where 12677 displayed a Mumbai–Delhi timeline).
///
/// Returns null when the route is consistent, or a human-readable reason when
/// it must be REJECTED (caller logs it and shows an error state).
String? validateRouteMatchesTrain(Journey journey, TrainSummary? train) {
  if (journey.stations.length < 2) return 'route has fewer than 2 stops';

  if (train == null) return null; // nothing to cross-check against

  // 1) Train number must match what we asked for.
  final wanted = train.number.trim();
  final got = journey.trainNumber.trim();
  if (wanted.isNotEmpty && got.isNotEmpty && wanted != got) {
    return 'train number mismatch: asked $wanted, route is for $got';
  }

  // 2) The searched leg's endpoints must appear on the route. (The route is
  //    the FULL run, which can start/end beyond the user's leg, so we check
  //    containment rather than exact first/last equality.)
  String norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
  final codes = journey.stations.map((s) => s.code.toUpperCase()).toSet();
  final names = journey.stations.map((s) => norm(s.name)).toList();

  bool onRoute(String code, String name) {
    final c = code.trim().toUpperCase();
    if (c.isNotEmpty && c != '—' && codes.contains(c)) return true;
    final n = norm(name);
    if (n.isEmpty) return false;
    return names.any((x) => x.contains(n) || n.contains(x));
  }

  if (!onRoute(train.fromCode, train.fromName)) {
    return 'origin ${train.fromCode}/${train.fromName} not found on route '
        '(${journey.stations.first.code}→${journey.stations.last.code})';
  }
  if (!onRoute(train.toCode, train.toName)) {
    return 'destination ${train.toCode}/${train.toName} not found on route '
        '(${journey.stations.first.code}→${journey.stations.last.code})';
  }
  return null;
}

// ---------------------------------------------------------------------------
// trackTrain -> live delay / current position hints
// ---------------------------------------------------------------------------

/// Live status extracted from `trackTrain`. Route/timeline still comes from
/// `getTrainInfo`; this only overlays "where is it now / how late".
class RailkitLiveStatus {
  final String? currentStationCode;
  final String statusNote;
  final int delayMinutes;
  final bool started;

  const RailkitLiveStatus({
    required this.currentStationCode,
    required this.statusNote,
    required this.delayMinutes,
    required this.started,
  });
}

RailkitLiveStatus? liveStatusFromRailkitTrack(dynamic data) {
  try {
    dynamic node = data;
    if (node is Map && node['data'] is Map) node = node['data'];
    if (node is! Map) return null;
    final m = node.cast<String, dynamic>();
    if (m['timeline'] is! List) return null;

    final note = _s(m['statusNote']);
    final current = _s(m['currentStationCode']);

    // Delay arrives as a label ("On Time", "15 Min Late") on each stop; take
    // the latest non-empty one at/behind the current position.
    int delay = 0;
    for (final raw in (m['timeline'] as List)) {
      if (raw is! Map) continue;
      final s = raw.cast<String, dynamic>();
      if (_s(s['status']).toLowerCase() == 'upcoming') continue;
      for (final key in ['departure', 'arrival']) {
        final leg = s[key];
        if (leg is Map) {
          final d = _s(leg['delay']);
          final mins = RegExp(r'(\d+)').firstMatch(d)?.group(1);
          if (mins != null) delay = int.tryParse(mins) ?? delay;
        }
      }
    }

    return RailkitLiveStatus(
      currentStationCode: current.isEmpty ? null : current,
      statusNote: note,
      delayMinutes: delay,
      started: current.isNotEmpty ||
          !note.toLowerCase().contains('yet to start'),
    );
  } catch (e) {
    debugPrint('[RailKit] track mapping failed: $e');
    return null;
  }
}

// ---------------------------------------------------------------------------
// checkPNRStatus
// ---------------------------------------------------------------------------
PnrResult? pnrFromRailkit(dynamic data, String pnr) {
  try {
    dynamic node = data;
    if (node is Map && node['data'] is Map) node = node['data'];
    if (node is! Map) return null;
    final m = node.cast<String, dynamic>();

    final rawNumber =
        _s(_first(m, ['train_no', 'train_number', 'trainNumber', 'trainNo']));
    if (rawNumber.isEmpty) return null;

    final name = _s(_first(m, ['train_name', 'trainName']), 'Train $rawNumber');
    final boarding = _s(
            _first(m, [
              'boarding_point',
              'boarding_station_code',
              'from_stn_code',
              'from',
              'source',
            ]),
            '—')
        .toUpperCase();
    final dest = _s(
            _first(m, [
              'reservation_upto',
              'destination_station_code',
              'to_stn_code',
              'to',
              'destination',
            ]),
            '—')
        .toUpperCase();
    final travelClass =
        _s(_first(m, ['class', 'journey_class', 'travel_class']), '—');

    final chartRaw =
        _s(_first(m, ['chart_status', 'chartStatus', 'chart_prepared']))
            .toLowerCase();
    final chart = (chartRaw.contains('not') || chartRaw == 'false')
        ? ChartStatus.notPrepared
        : (chartRaw.contains('prepared') || chartRaw == 'true')
            ? ChartStatus.prepared
            : ChartStatus.notPrepared;

    final passengersRaw =
        m['passengers'] ?? m['passenger_list'] ?? m['passengerList'];
    final passengers = <PnrPassenger>[];
    if (passengersRaw is List) {
      for (var i = 0; i < passengersRaw.length; i++) {
        final p = passengersRaw[i];
        if (p is! Map) continue;
        final pm = p.cast<String, dynamic>();
        final booking =
            _s(_first(pm, ['booking_status', 'bookingStatus', 'booking']), 'CNF');
        final current = _s(
            _first(pm, ['current_status', 'currentStatus', 'current']), booking);
        passengers.add(PnrPassenger(
          index: i + 1,
          booking: _seatFromStatus(booking),
          current: _seatFromStatus(current),
        ));
      }
    }
    if (passengers.isEmpty) return null; // no passengers => not usable

    return PnrResult(
      pnr: pnr,
      train: TrainSummary(
        number: rawNumber,
        name: name,
        fromCode: boarding,
        fromName: boarding,
        toCode: dest,
        toName: dest,
        departure: '--:--',
        arrival: '--:--',
        duration: '—',
        daysLabel: 'Daily',
        type: _inferType(name),
      ),
      journeyDate: _parseDate(_first(m, ['journey_date', 'doj', 'date'])),
      travelClass: travelClass,
      boardingCode: boarding,
      chartStatus: chart,
      passengers: passengers,
    );
  } catch (e, st) {
    debugPrint('[RailKit] PNR mapping failed: $e\n$st');
    return null;
  }
}

DateTime _parseDate(dynamic raw) {
  final s = _s(raw);
  if (s.isNotEmpty) {
    final iso = DateTime.tryParse(s);
    if (iso != null) return iso;
    // DD-MM-YYYY or DD-Mon-YYYY
    final parts = s.split(RegExp(r'[-/]'));
    if (parts.length == 3) {
      final d = int.tryParse(parts[0]);
      final y = int.tryParse(parts[2]);
      const months = {
        'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
        'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
      };
      final mo = int.tryParse(parts[1]) ??
          months[parts[1].toLowerCase().substring(
              0, parts[1].length < 3 ? parts[1].length : 3)];
      if (d != null && mo != null && y != null) return DateTime(y, mo, d);
    }
  }
  return DateTime.now();
}

SeatAllocation _seatFromStatus(String status) {
  final s = status.toUpperCase().trim();
  if (s.contains('CAN')) return const SeatAllocation.cancelled();
  if (s.contains('RAC')) return SeatAllocation.rac(_digits(s) ?? 1);
  if (s.contains('WL') || s.contains('WAIT')) {
    return SeatAllocation.waitlist(_digits(s) ?? 1);
  }
  // e.g. "CNF/B2/34/LB" or "B2 34 LB"
  final parts = s.split(RegExp(r'[\/ ]')).where((p) => p.isNotEmpty).toList();
  String coach = '—', berth = '—';
  String? berthType;
  for (final p in parts) {
    if (p == 'CNF' || p == 'CONF') continue;
    if (RegExp(r'^\d+$').hasMatch(p)) {
      berth = p;
    } else if (['LB', 'MB', 'UB', 'SL', 'SU'].contains(p)) {
      berthType = p;
    } else if (coach == '—') {
      coach = p;
    }
  }
  return SeatAllocation.confirmed(coach, berth, berthType);
}

int? _digits(String s) {
  final m = RegExp(r'(\d+)').firstMatch(s);
  return m == null ? null : int.tryParse(m.group(1)!);
}
