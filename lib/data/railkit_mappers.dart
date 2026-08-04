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
//       lastUpdate, totalStations, currentStationCode,
//       timeline: [ { stationCode, stationName, platform, distanceKm,
//       arrival:{scheduled,actual,delay}, departure:{...}, type, status,
//       coachPosition: [ {type,number,position} ] } ] }
//       NOTE: `delay` is a STRING ("On Time"), endpoints use "SRC"/"DSTN",
//       and actual times may carry a trailing "*".
//       CORRECTED: `coachPosition[]` was listed at the `data:` level here.
//       RailKit's published SDK reference places it INSIDE each `timeline[]`
//       entry; only `getTrainHistory` returns it top-level. Code reading
//       `data.coachPosition` finds nothing and reports the train as having no
//       published composition. See [coachPositionFromRailkitTrack].
import 'package:flutter/foundation.dart';

import '../models/journey.dart';
import '../models/pnr_status.dart';
import '../models/rail_station.dart';
import '../models/station.dart';
import '../models/station_live_status.dart';
import '../models/train_summary.dart';
import '../models/seat_availability.dart';
import '../models/station_board.dart';
import '../models/fare_info.dart';
import '../models/train_history_entry.dart';
import '../models/cancelled_train.dart';
import '../utils/train_type_helper.dart';
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
  return TrainTypeHelper.inferType(name, rawType);
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
/// `getTrainInfo` or RailRadar; this overlays "where is it now, how late, and
/// what actually happened at each stop".
class RailkitLiveStatus {
  final String? currentStationCode;
  final String statusNote;
  final int delayMinutes;
  final bool started;

  /// Per-station live timing, keyed by UPPERCASE station code.
  ///
  /// Only `type: "stoppage"` entries appear here. RailKit's `intermediate`
  /// entries carry no times at all — the documented sample has only `type`,
  /// `status`, `stationCode` and `stationName` — so there is nothing to record.
  final Map<String, StationLiveStatus> stationStatus;

  const RailkitLiveStatus({
    required this.currentStationCode,
    required this.statusNote,
    required this.delayMinutes,
    required this.started,
    this.stationStatus = const {},
  });
}

/// Sentinels RailKit uses where a time cannot exist: the origin has no arrival,
/// the terminus no departure.
const Set<String> _kEndpointSentinels = {'SRC', 'DSTN'};

/// Pulls the coach order out of a `trackTrain` payload as the same
/// hyphen-delimited string RailRadar returns, so [CoachPosition.parse] and the
/// Coach Position screen need no second code path per provider.
///
/// COSTS NO QUOTA. `trackTrain` is already called for live status on every
/// tracking session, so this reads a field out of a response the app has in hand
/// and that the Edge Function has already cached. It never issues a request.
///
/// UNVERIFIED AGAINST A LIVE PAYLOAD — deliberately tolerant because of it. The
/// shape comes from RailKit's published SDK reference, not from an observed
/// response: no successful `trackTrain` body has been captured locally, the only
/// local capture being a 132-byte
/// `{"success":false,"error":"Train data not available for date: ..."}`. This
/// file's own header comment had the nesting wrong, which is exactly the reason
/// not to trust a single documented shape. So both documented nestings and both
/// plausible element shapes are accepted, and anything unrecognised yields null
/// rather than a partial or invented sequence.
///
/// Remove the tolerance once a real payload confirms which shape ships.
String? coachPositionFromRailkitTrack(dynamic data) {
  if (data is! Map) return null;

  // 1) Top level. Where `getTrainHistory` documents it, and where this file's
  //    header comment used to claim `trackTrain` returns it.
  final top = _coachSequence(data['coachPosition']);
  if (top != null) return top;

  // 2) Inside a timeline entry, where the SDK reference actually documents it.
  //    Entries are scanned in order and the first usable array wins; the rake is
  //    a property of the train, so any stop that carries it carries the same one.
  final timeline = data['timeline'];
  if (timeline is List) {
    for (final entry in timeline) {
      if (entry is! Map) continue;
      final seq = _coachSequence(entry['coachPosition']);
      if (seq != null) return seq;
    }
  }
  return null;
}

/// Normalises one `coachPosition` value into `ENG-B1-S1`, or null when there is
/// nothing usable in it.
String? _coachSequence(dynamic raw) {
  if (raw == null) return null;

  // Already the RailRadar-style string. Accepted so a provider switch to the
  // simpler shape does not silently empty the screen.
  if (raw is String) {
    final v = raw.trim();
    return v.isEmpty ? null : v;
  }
  if (raw is! List || raw.isEmpty) return null;

  // (label, position) pairs. `position` is an ordinal in the rake, sent as a
  // string in the reference sample.
  final entries = <({String label, int? at})>[];
  for (final e in raw) {
    if (e is String) {
      final v = e.trim();
      if (v.isNotEmpty) entries.add((label: v, at: null));
      continue;
    }
    if (e is! Map) continue;
    // `number` is the coach label a passenger reads off the side (B1, S4, ENG);
    // `type` is the class (3A). Prefer the label, fall back to the class so a
    // payload carrying only `type` still renders something true.
    final label = (e['number'] ?? e['type'])?.toString().trim() ?? '';
    if (label.isEmpty) continue;
    entries.add((
      label: label,
      at: int.tryParse((e['position'] ?? '').toString().trim()),
    ));
  }
  if (entries.isEmpty) return null;

  // Order by `position` only when every entry has one. A partial ordering would
  // rearrange some coaches and leave others where they fell, which is worse than
  // trusting the array order the provider sent.
  if (entries.every((e) => e.at != null)) {
    entries.sort((a, b) => a.at!.compareTo(b.at!));
  }
  return entries.map((e) => e.label).join('-');
}

/// `"17:05"` (or `"17:05*"`) anchored onto [anchor] plus [dayOffset] days.
///
/// The trailing `*` is stripped: this file's header records that RailKit marks
/// some actual times that way. I have not observed one in a live payload —
/// RailKit's published sample shows none — so this is defensive, not confirmed.
/// Anything that is not a clock time (`SRC`, `DSTN`, `--`, `""`) yields null
/// rather than a guessed value.
DateTime? _clockOnto(String raw, DateTime anchor, int dayOffset) {
  final v = raw.trim().replaceAll('*', '').trim();
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(v);
  if (m == null) return null;
  final h = int.tryParse(m.group(1)!) ?? 0;
  final min = int.tryParse(m.group(2)!) ?? 0;
  if (h > 23 || min > 59) return null;
  final base = DateTime(anchor.year, anchor.month, anchor.day);
  return base.add(Duration(days: dayOffset, hours: h, minutes: min));
}

/// Minutes since midnight for a bare `HH:MM`, or null when it is not a time.
int? _minuteOfDay(String raw) {
  final v = raw.trim().replaceAll('*', '').trim();
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(v);
  if (m == null) return null;
  final h = int.tryParse(m.group(1)!) ?? 0;
  final min = int.tryParse(m.group(2)!) ?? 0;
  if (h > 23 || min > 59) return null;
  return h * 60 + min;
}

/// RailKit's `"31-Mar-2026"` journey date. Null when absent or unparseable, so
/// the caller can fall back rather than inventing a date.
DateTime? _railkitDate(String raw) {
  final m = RegExp(r'^(\d{1,2})-([A-Za-z]{3})-(\d{4})$').firstMatch(raw.trim());
  if (m == null) return null;
  const months = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };
  final month = months[m.group(2)!.toLowerCase()];
  if (month == null) return null;
  final day = int.tryParse(m.group(1)!);
  final year = int.tryParse(m.group(3)!);
  if (day == null || year == null) return null;
  return DateTime(year, month, day);
}

/// Parses one `{scheduled, actual, delay}` leg.
StationLegStatus _legFromRailkit(dynamic raw, DateTime anchor, int dayOffset) {
  if (raw is! Map) return const StationLegStatus();
  final m = raw.cast<String, dynamic>();

  final schedRaw = _s(m['scheduled']);
  final actualRaw = _s(m['actual']);

  final sentinel = _kEndpointSentinels.contains(schedRaw.toUpperCase()) ||
      _kEndpointSentinels.contains(actualRaw.toUpperCase());

  return StationLegStatus(
    scheduled: _clockOnto(schedRaw, anchor, dayOffset),
    actual: _clockOnto(actualRaw, anchor, dayOffset),
    rawDelay: _s(m['delay']),
    isTerminusSentinel: sentinel,
  );
}

StationLiveStage _stageFromRailkit(String raw) => switch (raw.toLowerCase()) {
      'passed' => StationLiveStage.passed,
      'current' => StationLiveStage.current,
      'upcoming' => StationLiveStage.upcoming,
      // An unrecognised status is treated as upcoming, the cautious end: it
      // withholds the actual row rather than presenting it as observed.
      _ => StationLiveStage.upcoming,
    };

RailkitLiveStatus? liveStatusFromRailkitTrack(dynamic data) {
  try {
    dynamic node = data;
    if (node is Map && node['data'] is Map) node = node['data'];
    if (node is! Map) return null;
    final m = node.cast<String, dynamic>();
    if (m['timeline'] is! List) return null;

    final note = _s(m['statusNote']);
    var current = _s(_first(m, [
      'currentStationCode',
      'current_station_code',
      'currentStation',
      'current_station',
      'lastStationCode',
      'last_station_code',
      'currentStnCode',
    ]));

    // Clock times in the timeline are bare `HH:MM`, so they need a date to hang
    // off. `date` looks like "31-Mar-2026"; if it will not parse we fall back to
    // today, which is what the route mappers already anchor to.
    final anchor = _railkitDate(_s(m['date'])) ?? DateTime.now();

    // Delay arrives as a label ("On Time", "15 Min Late") on each stop; take
    // the latest non-empty one at/behind the current position. Kept for the
    // train-level figure the hero card and the projected-time caption still use.
    int delay = 0;
    final perStation = <String, StationLiveStatus>{};

    // Day counter: the timeline is in route order with bare clock times, so a
    // time going backwards means the run has crossed midnight.
    var dayOffset = 0;
    int? previousMinuteOfDay;

    for (final raw in (m['timeline'] as List)) {
      if (raw is! Map) continue;
      final s = raw.cast<String, dynamic>();

      final stage = _stageFromRailkit(_s(s['status']));
      final code = _s(_first(s, ['stationCode', 'code', 'stnCode', 'station_code'])).toUpperCase();

      if (stage != StationLiveStage.upcoming && code.isNotEmpty) {
        if (current.isEmpty || stage == StationLiveStage.current || stage == StationLiveStage.passed) {
          current = code;
        }
        for (final key in ['departure', 'arrival']) {
          final leg = s[key];
          if (leg is Map) {
            final d = _s(leg['delay']);
            final mins = RegExp(r'(\d+)').firstMatch(d)?.group(1);
            if (mins != null) delay = int.tryParse(mins) ?? delay;
          }
        }
      }

      // `intermediate` points carry no times, platform or distance — only an
      // identity and a status — so they contribute nothing here.
      if (_s(s['type']).toLowerCase() != 'stoppage') continue;
      if (code.isEmpty) continue;

      // Advance the day counter when this stop's scheduled time runs backwards
      // against the previous stop's — the route is in order, so that only
      // happens at midnight. Compared as minute-of-day to keep it independent
      // of the anchor date.
      final minuteOfDay = _minuteOfDay(
            _s((s['arrival'] is Map) ? s['arrival']['scheduled'] : null),
          ) ??
          _minuteOfDay(
            _s((s['departure'] is Map) ? s['departure']['scheduled'] : null),
          );
      if (minuteOfDay != null) {
        if (previousMinuteOfDay != null && minuteOfDay < previousMinuteOfDay) {
          dayOffset++;
        }
        previousMinuteOfDay = minuteOfDay;
      }

      final platform = _s(s['platform']);
      perStation[code] = StationLiveStatus(
        stationCode: code,
        stage: stage,
        arrival: _legFromRailkit(s['arrival'], anchor, dayOffset),
        departure: _legFromRailkit(s['departure'], anchor, dayOffset),
        platform: platform.isEmpty ? null : platform,
      );
    }

    final hasDepartedStops = perStation.values.any((s) =>
        s.stage == StationLiveStage.passed ||
        s.stage == StationLiveStage.current);

    return RailkitLiveStatus(
      currentStationCode: current.isEmpty ? null : current,
      statusNote: note,
      delayMinutes: delay,
      started: current.isNotEmpty ||
          hasDepartedStops ||
          !note.toLowerCase().contains('yet to start'),
      stationStatus: perStation,
    );
  } catch (e) {
    debugPrint('[RailKit] track mapping failed: $e');
    return null;
  }
}

// ---------------------------------------------------------------------------
// checkPNRStatus
// ---------------------------------------------------------------------------
/// First non-empty value for [keys] across [maps], in order.
///
/// RailKit's PNR payload is NESTED, so identity fields have to be looked for in
/// the sub-object that owns them AND at the top level, where a flat variant would
/// put them. Checking both is what keeps this working if either shape ships.
dynamic _firstIn(List<Map<String, dynamic>> maps, List<String> keys) {
  for (final m in maps) {
    final v = _first(m, keys);
    if (v != null) return v;
  }
  return null;
}

/// A nested sub-object, or an empty map when absent.
Map<String, dynamic> _obj(dynamic v) =>
    v is Map ? v.cast<String, dynamic>() : const <String, dynamic>{};

/// A station reference that may be a bare code or a `{code, name}` object.
///
/// Returns [fallback] when nothing usable is present, so the em-dash convention
/// the PNR screen relies on for "not stated" is preserved — resolving a nested
/// object must not quietly change absence from `—` to an empty string.
String _stationRef(dynamic v, [String fallback = '—']) {
  if (v is Map) {
    final s = _s(_first(v.cast<String, dynamic>(), ['code', 'stnCode', 'name']));
    return s.isEmpty ? fallback : s;
  }
  final s = _s(v);
  return s.isEmpty ? fallback : s;
}

/// The human-readable station name from a `{code, name}` ref.
///
/// Falls back to [codeFallback] so the UI still has something true to print — the
/// code repeated is honest, if redundant. Never invents a name.
String _stationName(dynamic v, String codeFallback) {
  if (v is Map) {
    final n = _s(_first(v.cast<String, dynamic>(), ['name', 'stnName']));
    if (n.isNotEmpty) return n;
  }
  return codeFallback;
}

/// `HH:MM` out of a RailKit PNR datetime such as `Aug 23, 2026 8:45:00 PM`.
///
/// THESE ARE REAL SCHEDULED TIMES, not booking timestamps. Checked against train
/// 12257: `dateOfJourney` 20:45 from YPR, `arrivalDate` 10:48 next day at KYJ,
/// 708 km apart — about fourteen hours, which is exactly the run. An earlier round
/// of this file assumed a PNR carried no timetable and dashed both fields out;
/// that was wrong, and the values were sitting in the payload the whole time.
///
/// Returns null rather than guessing when there is no clock in the string, since
/// some responses carry a bare date.
String? _clockFrom(dynamic raw) {
  final s = _s(raw);
  if (s.isEmpty) return null;
  final m = RegExp(r'(\d{1,2}):(\d{2})(?::\d{2})?\s*([AaPp][Mm])?').firstMatch(s);
  if (m == null) return null;
  var h = int.tryParse(m.group(1)!);
  final min = int.tryParse(m.group(2)!);
  if (h == null || min == null || min > 59) return null;
  final suffix = m.group(3)?.toLowerCase();
  if (suffix == 'pm' && h < 12) h += 12;
  if (suffix == 'am' && h == 12) h = 0;
  if (h > 23) return null;
  return '${h.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')}';
}

/// Whole days between two PNR datetimes, or 0 when either is unusable.
///
/// Drives the `+1 day` marker on the arrival, so an overnight run does not read
/// as arriving before it left.
int _dayOffsetBetween(dynamic from, dynamic to) {
  final a = _parseDateOrNull(from);
  final b = _parseDateOrNull(to);
  if (a == null || b == null) return 0;
  final days = DateTime(b.year, b.month, b.day)
      .difference(DateTime(a.year, a.month, a.day))
      .inDays;
  return days < 0 ? 0 : days;
}

/// Date AND clock combined, for arithmetic across midnight.
DateTime? _dateTimeFrom(dynamic raw) {
  final d = _parseDateOrNull(raw);
  if (d == null) return null;
  final clock = _clockFrom(raw);
  if (clock == null) return d;
  final parts = clock.split(':');
  return DateTime(d.year, d.month, d.day,
      int.parse(parts[0]), int.parse(parts[1]));
}

/// Journey length as `14h 03m`, matching the format the rest of the app uses.
///
/// Computed from the two full datetimes rather than the clocks alone, so an
/// overnight run does not come out negative — 20:45 to 10:48 is 14h 03m, not
/// minus ten hours.
///
/// Null when either end is missing or the arithmetic is not positive. The centre
/// of the hero card then keeps its dash instead of showing `0h 00m`, which would
/// read as a fact.
String? _durationBetween(dynamic from, dynamic to) {
  final a = _dateTimeFrom(from);
  final b = _dateTimeFrom(to);
  if (a == null || b == null) return null;
  final mins = b.difference(a).inMinutes;
  if (mins <= 0) return null;
  return '${mins ~/ 60}h ${(mins % 60).toString().padLeft(2, '0')}m';
}

/// One passenger's reservation as a status STRING the shared parser understands.
///
/// RailKit sends `booking` and `current` as OBJECTS —
/// `{status, coach, berthNo, berthCode, details}` — not strings. The previous code
/// stringified the whole Map and handed it to [SeatAllocation.fromStatusString],
/// which then read `{status:` as a coach id. `details` is already the canonical
/// form (`CNF/B5/22/LB`) so it is preferred; otherwise the parts are reassembled
/// in that order. Anything absent stays absent — no placeholders.
String? _pnrStatusString(dynamic slot) {
  if (slot == null) return null;
  if (slot is String) {
    final v = slot.trim();
    return v.isEmpty ? null : v;
  }
  if (slot is! Map) return null;
  final m = slot.cast<String, dynamic>();

  final details = _s(_first(m, ['details', 'detail']));
  // The live payload's `current.details` reads `CNF , B5 - 22 [LB]`, whose
  // separators the parser does not cover. Normalising the punctuation to the
  // slash-delimited form it already handles is cheaper and safer than teaching
  // that parser a second syntax — it is shared with the RapidAPI path.
  if (details.isNotEmpty) {
    final normalised = details
        .replaceAll(RegExp(r'[\[\]]'), ' ')
        .replaceAll(RegExp(r'\s*[,\-]\s*'), '/')
        .replaceAll(RegExp(r'\s+'), '/')
        .replaceAll(RegExp(r'/{2,}'), '/')
        .replaceAll(RegExp(r'^/|/$'), '')
        .trim();
    if (normalised.isNotEmpty) return normalised;
  }

  final parts = <String>[
    ?_part(m, const ['status']),
    ?_part(m, const ['coach', 'coachId']),
    ?_part(m, const ['berthNo', 'berth', 'berth_no']),
    ?_part(m, const ['berthCode', 'berth_code', 'berthType']),
  ];
  return parts.isEmpty ? null : parts.join('/');
}

String? _part(Map<String, dynamic> m, List<String> keys) {
  final v = _s(_first(m, keys));
  return v.isEmpty ? null : v;
}

PnrResult? pnrFromRailkit(dynamic data, String pnr) {
  try {
    dynamic node = data;
    if (node is Map && node['data'] is Map) node = node['data'];
    if (node is! Map) return null;
    final m = node.cast<String, dynamic>();

    // RailKit's PNR payload is NESTED. Verified against a live response:
    //   { pnr, train:{name,number}, chart:{status},
    //     booking:{fare,ticketFare,bookingDate},
    //     journey:{class,quota,source,destination,boardingPoint,dateOfJourney,
    //              arrivalDate,distance},
    //     passengers:[{serialNumber,coachPosition,booking:{...},current:{...}}] }
    //
    // Every read below used to look only at the TOP level, so `rawNumber` came
    // back empty and this returned null for EVERY real PNR — the lookup could
    // only ever succeed for the three canned demo numbers. Both shapes are
    // accepted now: the owning sub-object first, then the top level.
    final train = _obj(m['train']);
    final journey = _obj(m['journey']);
    final chartObj = _obj(m['chart']);

    final rawNumber = _s(_firstIn([train, m],
        ['number', 'train_no', 'train_number', 'trainNumber', 'trainNo']));
    if (rawNumber.isEmpty) return null;

    final name =
        _s(_firstIn([train, m], ['name', 'train_name', 'trainName']),
            'Train $rawNumber');
    // Kept as refs, because each may be a bare code OR a `{code, name}` object —
    // and when it is the object, the NAME was being thrown away and the code
    // written into both fields, so the card read "YPR / YPR" instead of
    // "YPR / Yesvantpur Jn".
    final boardingRef = _firstIn([journey, m], [
      'boardingPoint',
      'boarding_point',
      'boarding_station_code',
      'from_stn_code',
      'from',
      'source',
    ]);
    final destRef = _firstIn([journey, m], [
      'destination',
      'reservation_upto',
      'destination_station_code',
      'to_stn_code',
      'to',
    ]);
    final boarding = _stationRef(boardingRef).toUpperCase();
    final dest = _stationRef(destRef).toUpperCase();
    final boardingName = _stationName(boardingRef, boarding);
    final destName = _stationName(destRef, dest);

    // Full datetimes. Nested on the real payload; the flat keys are kept for the
    // other shape. Both the date and the clock are taken from these.
    final departureRaw = _firstIn(
        [journey, m], ['dateOfJourney', 'journey_date', 'doj', 'date']);
    final arrivalRaw =
        _firstIn([journey, m], ['arrivalDate', 'arrival_date', 'arrival']);
    final travelClass = _s(
        _firstIn([journey, m], ['class', 'journey_class', 'travel_class']), '—');

    final chartRaw = _s(_firstIn(
            [chartObj, m], ['status', 'chart_status', 'chartStatus', 'chart_prepared']))
        .toLowerCase();
    // Null when the field is absent or unrecognised. This previously fell through
    // to notPrepared, which is the safer of the two guesses but still a claim the
    // response never made.
    final chart = (chartRaw.contains('not') || chartRaw == 'false')
        ? ChartStatus.notPrepared
        : (chartRaw.contains('prepared') || chartRaw == 'true')
            ? ChartStatus.prepared
            : null;

    final passengersRaw =
        m['passengers'] ?? m['passenger_list'] ?? m['passengerList'];
    final passengers = <PnrPassenger>[];
    if (passengersRaw is List) {
      for (var i = 0; i < passengersRaw.length; i++) {
        final p = passengersRaw[i];
        if (p is! Map) continue;
        final pm = p.cast<String, dynamic>();
        // Objects, not strings — see [_pnrStatusString]. Falls back to the flat
        // string keys so a flat variant still parses.
        final booking = _pnrStatusString(
                pm['booking'] ?? _first(pm, ['booking_status', 'bookingStatus'])) ??
            'CNF';
        final current = _pnrStatusString(
                pm['current'] ?? _first(pm, ['current_status', 'currentStatus'])) ??
            booking;
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
        fromName: boardingName,
        toCode: dest,
        toName: destName,
        // CORRECTED. This previously read "A PNR response has no timetable" and
        // dashed both fields out. It does carry one: `journey.dateOfJourney` and
        // `journey.arrivalDate` are full datetimes, and their clocks are the
        // scheduled departure and arrival — verified on 12257 (20:45 YPR ->
        // 10:48+1 KYJ, 708 km). Still null when a response omits the clock, so
        // absence is represented rather than invented.
        departure: _clockFrom(departureRaw),
        arrival: _clockFrom(arrivalRaw),
        arrivalDayOffset: _dayOffsetBetween(departureRaw, arrivalRaw),
        // Derived from the two datetimes, not sent by the provider. Safe to
        // derive because it is pure arithmetic on two values we were given —
        // unlike a train name, which cannot be computed from anything.
        duration: _durationBetween(departureRaw, arrivalRaw),
        type: _inferType(name),
      ),
      journeyDate: _parseDateOrNull(departureRaw),
      travelClass: travelClass.isEmpty || travelClass == '—' ? null : travelClass,

      chartStatus: chart,
      passengers: passengers,
    );
  } catch (e) {
    if (kDebugMode) debugPrint('[RailKit] PNR mapping failed: ${e.runtimeType}');
    return null;
  }
}

/// Parses a provider date, returning null when it cannot.
///
/// Previously fell through to `DateTime.now()`, so an unparseable or missing
/// journey date silently became today — a confident, wrong travel date on the
/// PNR header.
DateTime? _parseDateOrNull(dynamic raw) {
  final s = _s(raw);
  if (s.isNotEmpty) {
    final iso = DateTime.tryParse(s);
    if (iso != null) return iso;

    const months = {
      'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
      'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
    };

    // `Aug 23, 2026 8:45:00 PM` — the format RailKit's PNR journey date ACTUALLY
    // uses, confirmed against a live response. Month first. The published SDK
    // sample shows `22 Aug 2026, 04:35:00 pm` instead, so both orders are handled
    // rather than trusting either document: whichever ships, the date resolves.
    // Only the date part is taken; the trailing clock is the booking time, not
    // something this field is asked for.
    final monthFirst = RegExp(r'^([A-Za-z]{3,})\.?\s+(\d{1,2}),?\s+(\d{4})')
        .firstMatch(s.trim());
    if (monthFirst != null) {
      final mo = months[monthFirst.group(1)!.toLowerCase().substring(0, 3)];
      final d = int.tryParse(monthFirst.group(2)!);
      final y = int.tryParse(monthFirst.group(3)!);
      if (d != null && mo != null && y != null) return DateTime(y, mo, d);
    }

    // `22 Aug 2026, 04:35:00 pm` — day first.
    final spaced =
        RegExp(r'^(\d{1,2})\s+([A-Za-z]{3,})\.?,?\s+(\d{4})').firstMatch(s.trim());
    if (spaced != null) {
      final d = int.tryParse(spaced.group(1)!);
      final mo = months[spaced.group(2)!.toLowerCase().substring(0, 3)];
      final y = int.tryParse(spaced.group(3)!);
      if (d != null && mo != null && y != null) return DateTime(y, mo, d);
    }

    // DD-MM-YYYY or DD-Mon-YYYY
    final parts = s.split(RegExp(r'[-/]'));
    if (parts.length == 3) {
      final d = int.tryParse(parts[0]);
      final y = int.tryParse(parts[2]);
      final mo = int.tryParse(parts[1]) ??
          months[parts[1].toLowerCase().substring(
              0, parts[1].length < 3 ? parts[1].length : 3)];
      if (d != null && mo != null && y != null) return DateTime(y, mo, d);
    }
  }
  return null;
}

/// Delegates to [SeatAllocation.fromStatusString].
///
/// This used to be a second, subtly different parser: it substituted em dashes
/// for a missing coach or berth, defaulted RAC and waitlist positions to 1, and
/// recognised only five berth-type codes (dropping the real-world `SLB`, `SUB`
/// and `SM`, and occasionally storing a dropped code as the coach). One parser
/// now serves both providers and invents nothing.
/// Delegates to [SeatAllocation.fromStatusString].
SeatAllocation _seatFromStatus(String status) =>
    SeatAllocation.fromStatusString(status);

// ---------------------------------------------------------------------------
// Additional RailKit Feature Mappers
// ---------------------------------------------------------------------------

SeatAvailability? availabilityFromRailkit(
  dynamic data,
  String from,
  String to,
  String classCode,
  String quota,
) {
  try {
    dynamic node = data;
    if (node is Map && node['data'] != null) node = node['data'];
    if (node is! Map) return null;
    final m = node.cast<String, dynamic>();

    final trainNum = _s(m['trainNumber'] ?? m['train_number'] ?? m['trainNo']);
    final list = m['availability'] ?? m['days'] ?? m['availability_list'];

    final days = <AvailabilityDay>[];
    if (list is List) {
      for (final item in list) {
        if (item is Map) {
          days.add(AvailabilityDay.fromMap(item.cast<String, dynamic>()));
        }
      }
    }

    return SeatAvailability(
      trainNumber: trainNum,
      fromStation: from,
      toStation: to,
      classCode: classCode,
      quota: quota,
      days: days,
    );
  } catch (e) {
    debugPrint('[RailKit] availability mapping failed: $e');
    return null;
  }
}

List<StationBoardEntry> stationBoardFromRailkit(dynamic data) {
  final entries = <StationBoardEntry>[];
  try {
    dynamic node = data;
    if (node is Map && node['data'] != null) node = node['data'];
    if (node is List) {
      for (final raw in node) {
        if (raw is Map) {
          final m = raw.cast<String, dynamic>();
          final delayMins = int.tryParse(_s(m['delay'] ?? m['delayMinutes'] ?? '0')) ?? 0;
          entries.add(
            StationBoardEntry(
              trainNumber: _s(m['trainNumber'] ?? m['train_number'] ?? m['trainNo']),
              trainName: _s(m['trainName'] ?? m['train_name'] ?? 'Train'),
              origin: _s(m['origin'] ?? m['from'] ?? ''),
              destination: _s(m['destination'] ?? m['to'] ?? ''),
              scheduledTime: _s(m['scheduledTime'] ?? m['std'] ?? m['sta'] ?? ''),
              expectedTime: _s(m['expectedTime'] ?? m['eta'] ?? m['etd'] ?? ''),
              delayMinutes: delayMins,
              platform: _s(m['platform'] ?? '—'),
              status: _s(m['status'] ?? (delayMins > 0 ? 'DELAYED' : 'ON TIME')),
            ),
          );
        }
      }
    }
  } catch (e) {
    debugPrint('[RailKit] station board mapping failed: $e');
  }
  return entries;
}

FareBreakdown? fareFromRailkit(
  dynamic data,
  String from,
  String to,
  String trainNumber,
) {
  try {
    dynamic node = data;
    if (node is Map && node['data'] != null) node = node['data'];
    if (node is! Map) return null;
    final m = node.cast<String, dynamic>();

    final fareList = m['fares'] ?? m['fare_list'] ?? m['classes'];
    final fares = <ClassFare>[];
    if (fareList is List) {
      for (final item in fareList) {
        if (item is Map) {
          final f = item.cast<String, dynamic>();
          fares.add(
            ClassFare(
              classCode: _s(f['classCode'] ?? f['class_code'] ?? f['code'] ?? 'SL'),
              className: _s(f['className'] ?? f['class_name'] ?? f['name'] ?? ''),
              baseFare: double.tryParse(_s(f['baseFare'] ?? f['base_fare'] ?? '0')) ?? 0.0,
              totalFare: double.tryParse(_s(f['totalFare'] ?? f['total_fare'] ?? f['fare'] ?? '0')) ?? 0.0,
            ),
          );
        }
      }
    }

    return FareBreakdown(
      trainNumber: trainNumber,
      fromStation: from,
      toStation: to,
      fares: fares,
    );
  } catch (e) {
    debugPrint('[RailKit] fare mapping failed: $e');
    return null;
  }
}

TrainHistoryEntry? trainHistoryFromRailkit(
  dynamic data,
  String trainNumber,
  String date,
) {
  try {
    dynamic node = data;
    if (node is Map && node['data'] != null) node = node['data'];
    if (node is! Map) return null;
    final m = node.cast<String, dynamic>();

    final stopsRaw = m['history'] ?? m['stops'] ?? m['timeline'];
    final stops = <StationHistoryEntry>[];
    if (stopsRaw is List) {
      for (final raw in stopsRaw) {
        if (raw is Map) {
          final s = raw.cast<String, dynamic>();
          stops.add(
            StationHistoryEntry(
              stationCode: _s(s['stationCode'] ?? s['code']),
              stationName: _s(s['stationName'] ?? s['name']),
              scheduledArrival: _s(s['scheduledArrival'] ?? s['sta']),
              actualArrival: _s(s['actualArrival'] ?? s['eta']),
              scheduledDeparture: _s(s['scheduledDeparture'] ?? s['std']),
              actualDeparture: _s(s['actualDeparture'] ?? s['etd']),
              delayMinutes: int.tryParse(_s(s['delay'] ?? '0')) ?? 0,
            ),
          );
        }
      }
    }

    return TrainHistoryEntry(
      trainNumber: trainNumber,
      date: date,
      statusNote: _s(m['statusNote'] ?? m['status'] ?? ''),
      totalDelayMinutes: int.tryParse(_s(m['totalDelay'] ?? '0')) ?? 0,
      stops: stops,
    );
  } catch (e) {
    debugPrint('[RailKit] history mapping failed: $e');
    return null;
  }
}

List<CancelledTrain> cancelledTrainsFromRailkit(dynamic data) {
  final result = <CancelledTrain>[];
  try {
    dynamic node = data;
    if (node is Map && node['data'] != null) node = node['data'];
    if (node is List) {
      for (final raw in node) {
        if (raw is Map) {
          final m = raw.cast<String, dynamic>();
          result.add(
            CancelledTrain(
              trainNumber: _s(m['trainNumber'] ?? m['train_number'] ?? m['trainNo']),
              trainName: _s(m['trainName'] ?? m['train_name'] ?? 'Train'),
              origin: _s(m['origin'] ?? m['from'] ?? ''),
              destination: _s(m['destination'] ?? m['to'] ?? ''),
              cancellationType: _s(m['cancellationType'] ?? m['type'] ?? 'FULL'),
              startDate: _s(m['startDate'] ?? m['date'] ?? ''),
              endDate: _s(m['endDate'] ?? m['date'] ?? ''),
            ),
          );
        }
      }
    }
  } catch (e) {
    debugPrint('[RailKit] cancelled trains mapping failed: $e');
  }
  return result;
}

