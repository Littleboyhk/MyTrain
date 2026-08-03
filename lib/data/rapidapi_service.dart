import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import '../models/pnr_status.dart';
import '../models/rail_station.dart';
import '../models/train_summary.dart';
import '../utils/train_type_helper.dart';
import 'train_repository.dart';

/// Exception thrown when RapidAPI operations fail.
class RapidApiException implements Exception {
  const RapidApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  @override
  String toString() =>
      'RapidApiException: $message ${statusCode != null ? '(Status: $statusCode)' : ''}';
}

class _RouteCacheEntry {
  const _RouteCacheEntry(this.results, this.timestamp);
  final List<TrainSummary> results;
  final DateTime timestamp;

  bool isExpired(Duration ttl) => DateTime.now().difference(timestamp) > ttl;
}

/// Service connecting to the unofficial IRCTC RapidAPI.
class RapidApiService {
  RapidApiService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// In-memory cache for route search results (20-minute TTL).
  final Map<String, _RouteCacheEntry> _routeCache = {};
  static const Duration _cacheTtl = Duration(minutes: 20);

  /// Reads API Key strictly from environment or .env.
  String get _apiKey {
    try {
      final envKey = dotenv.env['RAPIDAPI_KEY'];
      if (envKey != null && envKey.trim().isNotEmpty) {
        return envKey.trim();
      }
    } catch (_) {}
    try {
      final env = Platform.environment['RAPIDAPI_KEY'];
      if (env != null && env.trim().isNotEmpty) {
        return env.trim();
      }
    } catch (_) {}
    return const String.fromEnvironment('RAPIDAPI_KEY');
  }

  /// Reads API Host strictly from environment or .env.
  String get _apiHost {
    try {
      final envHost = dotenv.env['RAPIDAPI_HOST'];
      if (envHost != null && envHost.trim().isNotEmpty) {
        return envHost.trim();
      }
    } catch (_) {}
    try {
      final env = Platform.environment['RAPIDAPI_HOST'];
      if (env != null && env.trim().isNotEmpty) {
        return env.trim();
      }
    } catch (_) {}
    final compileHost = const String.fromEnvironment('RAPIDAPI_HOST');
    if (compileHost.trim().isNotEmpty) return compileHost.trim();
    return 'irctc1.p.rapidapi.com';
  }

  Map<String, String> get _headers => {
        'X-RapidAPI-Key': _apiKey,
        'X-RapidAPI-Host': _apiHost,
        'Accept': 'application/json',
      };

  /// Fetches real trains between [from] and [to] from RapidAPI.
  Future<List<TrainSummary>> getTrainsBetweenStations({
    required RailStation from,
    required RailStation to,
    DateTime? date,
  }) async {
    final journeyDate = date ?? DateTime.now();
    final dateStr =
        '${journeyDate.year}-${journeyDate.month.toString().padLeft(2, '0')}-${journeyDate.day.toString().padLeft(2, '0')}';
    final cacheKey =
        '${from.code.toUpperCase()}_${to.code.toUpperCase()}_$dateStr';

    // 1. Check in-memory cache
    if (_routeCache.containsKey(cacheKey)) {
      final entry = _routeCache[cacheKey]!;
      if (!entry.isExpired(_cacheTtl)) {
        debugPrint(
            '[RapidAPI Cache] Returning cached results for $cacheKey (${entry.results.length} trains)');
        return entry.results;
      }
    }

    final fromCode = from.code.trim().toUpperCase();
    final toCode = to.code.trim().toUpperCase();

    final Uri uri = Uri.https(_apiHost, '/api/v3/trainBetweenStations', {
      'fromStationCode': fromCode,
      'toStationCode': toCode,
      'dateOfJourney': dateStr,
    });

    debugPrint('[RapidAPI Request] GET ${uri.toString()}');

    try {
      final response = await _client
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 12));

      // Search responses carry timetables rather than personal data, but they are
      // logged by shape too — one convention for the file, and a full body dump
      // is how the PNR leak got there in the first place.
      _logShape('trainsBetweenStations', response.statusCode, response.body);

      if (response.statusCode == 429) {
        throw const RapidApiException(
            'RapidAPI rate limit exceeded. Please try again later.',
            statusCode: 429);
      }
      if (response.statusCode == 504 || response.statusCode == 503) {
        throw RapidApiException(
            'IRCTC service timed out (${response.statusCode}). Please retry.',
            statusCode: response.statusCode);
      }
      if (response.statusCode != 200) {
        throw RapidApiException(
            'IRCTC API error (${response.statusCode}): ${response.reasonPhrase}',
            statusCode: response.statusCode);
      }

      final dynamic bodyJson = jsonDecode(response.body);
      final trains = _parseTrainsBetweenStations(bodyJson, from, to);

      // Cache verified results
      _routeCache[cacheKey] = _RouteCacheEntry(trains, DateTime.now());
      return trains;
    } on TimeoutException {
      throw const RapidApiException(
          'Connection timed out. Please check your network.');
    } on SocketException {
      throw const RapidApiException(
          'Network error. Could not connect to IRCTC server.');
    } on FormatException {
      throw const RapidApiException(
          'Received malformed response format from IRCTC API.');
    } on RapidApiException {
      rethrow;
    } catch (e) {
      debugPrint('[RapidAPI Error] Route lookup failed: $e');
      throw RapidApiException('API Request failed: ${e.toString()}');
    }
  }

  /// Parses JSON response into validated TrainSummary objects.
  List<TrainSummary> _parseTrainsBetweenStations(
    dynamic json,
    RailStation from,
    RailStation to,
  ) {
    if (json == null) return [];

    List<dynamic> trainList = [];

    if (json is Map<String, dynamic>) {
      if (json['data'] is List) {
        trainList = json['data'] as List;
      } else if (json['data'] is Map<String, dynamic>) {
        final dataMap = json['data'] as Map<String, dynamic>;
        if (dataMap['trains'] is List) {
          trainList = dataMap['trains'] as List;
        } else if (dataMap['train_array'] is List) {
          trainList = dataMap['train_array'] as List;
        } else if (dataMap['result'] is List) {
          trainList = dataMap['result'] as List;
        }
      } else if (json['result'] is List) {
        trainList = json['result'] as List;
      }
    } else if (json is List) {
      trainList = json;
    }

    final results = <TrainSummary>[];

    for (final item in trainList) {
      if (item is! Map<String, dynamic>) continue;

      final rawNumber = (item['train_number'] ??
              item['trainNumber'] ??
              item['number'] ??
              item['train_num'] ??
              '')
          .toString()
          .trim();

      final name = (item['train_name'] ??
              item['trainName'] ??
              item['name'] ??
              '')
          .toString()
          .trim();

      final number = isValidIRTrainNumber(rawNumber)
          ? rawNumber
          : (rawNumber.length >= 5 ? rawNumber.substring(0, 5) : '');

      if (number.isEmpty) continue;

      final fromCode = (item['from_station_code'] ??
              item['from_code'] ??
              item['from'] ??
              from.code)
          .toString()
          .toUpperCase();
      final fromName = (item['from_station_name'] ??
              item['from_name'] ??
              from.name)
          .toString();
      final toCode = (item['to_station_code'] ??
              item['to_code'] ??
              item['to'] ??
              to.code)
          .toString()
          .toUpperCase();
      final toName =
          (item['to_station_name'] ?? item['to_name'] ?? to.name).toString();

      final dep = (item['from_std'] ??
              item['departure_time'] ??
              item['departure'] ??
              item['std'] ??
              '08:00')
          .toString();
      final arr = (item['to_sta'] ??
              item['arrival_time'] ??
              item['arrival'] ??
              item['sta'] ??
              '20:00')
          .toString();
      final duration =
          (item['duration'] ?? item['travel_time'] ?? '12h 00m').toString();

      String daysLabel = 'Daily';
      final runDays = item['run_days'] ?? item['running_days'] ?? item['days'];
      if (runDays is List) {
        daysLabel = runDays.map((e) => e.toString()).join(', ');
      } else if (runDays is String && runDays.isNotEmpty) {
        daysLabel = runDays;
      }

      final rawType = (item['train_type'] ?? item['type'] ?? '').toString();
      final type = _inferTrainType(name, rawType);

      results.add(TrainSummary(
        number: number,
        name: name.isEmpty ? 'Express $number' : name,
        fromCode: fromCode,
        fromName: fromName,
        toCode: toCode,
        toName: toName,
        departure: dep,
        arrival: arr,
        duration: duration,
        daysLabel: daysLabel,
        type: type,
      ));
    }

    return results;
  }

  String _inferTrainType(String name, String rawType) {
    return TrainTypeHelper.inferType(name, rawType);
  }

  /// Real PNR status lookup from RapidAPI.
  Future<PnrResult?> getPnrStatus(String pnr) async {
    final cleanPnr = pnr.trim();
    if (cleanPnr.length != 10) {
      throw const RapidApiException('PNR number must be exactly 10 digits.');
    }

    final Uri uri = Uri.https(_apiHost, '/api/v3/getPNRStatus', {
      'pnrNumber': cleanPnr,
    });

    // Path only. The full URI carries `?pnrNumber=...`, and a PNR is enough on
    // its own to look up a booking and its passengers.
    debugPrint('[RapidAPI] PNR lookup requested (${uri.path})');

    try {
      final response = await _client
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 12));

      // Shape, never content. This printed the entire response body, which for a
      // PNR includes each passenger's booking and current status strings — coach,
      // berth and queue position per person — straight into the device log.
      _logShape('PNR', response.statusCode, response.body);

      if (response.statusCode == 429) {
        throw const RapidApiException(
            'RapidAPI rate limit exceeded. Please try again later.',
            statusCode: 429);
      }
      if (response.statusCode != 200) {
        throw RapidApiException(
            'PNR API returned status ${response.statusCode}',
            statusCode: response.statusCode);
      }

      final dynamic json = jsonDecode(response.body);
      return _parsePnrStatus(json, cleanPnr);
    } on TimeoutException {
      throw const RapidApiException('PNR lookup timed out. Check network.');
    } on SocketException {
      throw const RapidApiException('Network error connecting to PNR service.');
    } catch (e) {
      // A decode failure can quote the offending source, so redact before it
      // reaches the log or the exception message the UI may surface.
      debugPrint('[RapidAPI] PNR lookup failed: ${_redact(e.toString())}');
      throw RapidApiException('PNR lookup failed: ${_redact(e.toString())}');
    }
  }

  /// Masks anything that looks like a PNR (a bare 10-digit run).
  ///
  /// Deliberately keeps the last three digits so a support conversation can still
  /// match a report to a request without the log holding the identifier.
  static String _redact(String s) => s.replaceAllMapped(
        RegExp(r'\b\d{10}\b'),
        (m) => '*******${m[0]!.substring(7)}',
      );

  /// Logs the shape of a response without any of its values.
  ///
  /// Top-level key NAMES are safe and are what actually helps when a provider
  /// renames a field — which is how several of this file's silent fallbacks went
  /// unnoticed. Values are never logged.
  void _logShape(String label, int status, String body) {
    if (!kDebugMode) return;
    String shape;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final inner = decoded['data'];
        final keys = (inner is Map ? inner.keys : decoded.keys)
            .map((k) => k.toString())
            .toList()
          ..sort();
        final rows = inner is Map
            ? (inner['passengers'] ?? inner['passenger_list'])
            : null;
        shape = 'keys=${keys.join(",")}'
            '${rows is List ? " passengerRows=${rows.length}" : ""}';
      } else if (decoded is List) {
        shape = 'topLevelList length=${decoded.length}';
      } else {
        shape = 'scalar';
      }
    } catch (_) {
      shape = 'undecodable';
    }
    debugPrint('[RapidAPI] $label response: HTTP $status, '
        '${body.length} bytes, $shape');
  }

  PnrResult? _parsePnrStatus(dynamic json, String pnr) {
    if (json == null || json is! Map<String, dynamic>) return null;

    final data = json['data'] ?? json;
    if (data is! Map<String, dynamic>) return null;

    final trainNum = _optional(data, const [
          'train_number',
          'trainNumber',
          'train_no',
        ]) ??
        '';

    // Key lists widened to match the RailKit mapper's. This path was checking
    // only two or three aliases each, so a response that stated the boarding
    // point under `boarding_point`, `from_stn_code` or `source` — all of which
    // RailKit reads — fell through to the hardcoded 'BCT'. Same story for
    // `reservation_upto` / `to_stn_code` / `destination` and 'NDLS'.
    final boardingCode = _optional(data, const [
      'boarding_point',
      'boarding_station_code',
      'boarding_code',
      'from_stn_code',
      'from',
      'source',
    ])?.toUpperCase();

    final destCode = _optional(data, const [
      'reservation_upto',
      'destination_station_code',
      'to_stn_code',
      'to',
      'destination',
    ])?.toUpperCase();

    // Derived from the real train number rather than naming a specific real
    // train. This defaulted to 'Rajdhani Express', so any response missing a name
    // was presented as a Rajdhani.
    final trainName = _optional(data, const ['train_name', 'trainName']) ??
        'Train $trainNum';

    final passengersList = data['passengers'] ?? data['passenger_list'];
    final passengers = <PnrPassenger>[];

    if (passengersList is List) {
      for (var i = 0; i < passengersList.length; i++) {
        final p = passengersList[i];
        if (p is Map<String, dynamic>) {
          final curStatus =
              (p['current_status'] ?? p['currentStatus'] ?? 'CNF').toString();
          final bookStatus =
              (p['booking_status'] ?? p['bookingStatus'] ?? 'CNF').toString();
          passengers.add(PnrPassenger(
            index: i + 1,
            booking: _parseSeatAllocation(bookStatus),
            current: _parseSeatAllocation(curStatus),
          ));
        }
      }
    }

    // No usable passenger rows means we cannot describe this booking. This used
    // to inject a fabricated confirmed passenger on B1/34/LB, which is the exact
    // failure mode pnr_service.dart calls trust-breaking a few lines from its own
    // fallback. A null return surfaces "PNR not found" instead.
    if (passengers.isEmpty) return null;

    // Likewise the train itself: this defaulted to 12951 "Rajdhani Express",
    // so an unparseable response produced a real train number that had nothing
    // to do with the ticket.
    if (!isValidIRTrainNumber(trainNum)) return null;

    return PnrResult(
      pnr: pnr,
      train: TrainSummary(
        number: trainNum,
        name: trainName,
        // An em dash when the response did not state it, matching what the
        // RailKit mapper already does. Obviously-not-a-station-code beats a
        // specific real station: this path used to claim every unstated journey
        // ran BCT to NDLS.
        //
        // fromName/toName carry the CODE rather than a station name on both PNR
        // paths. That is lossy rather than fabricated and is flagged separately —
        // resolving a name needs StationRepository, which loads asynchronously
        // and is not reachable from a pure mapper.
        fromCode: boardingCode ?? '—',
        fromName: boardingCode ?? '—',
        toCode: destCode ?? '—',
        toName: destCode ?? '—',
        // Derived, not hardcoded. Every PNR-sourced train used to be typed
        // 'Express', including a Rajdhani. This reuses the inference already in
        // this class, and also reads the payload's own type field — which was a
        // second available-but-unread value.
        type: _inferTrainType(
          trainName,
          _optional(data, const ['train_type', 'type']) ?? '',
        ),
        // WERE '17:00' / '08:35' / '15h 35m' / 'Daily' — a specific, plausible,
        // wrong timetable applied to every train that came through this path. A
        // PNR response carries booking data, not the schedule, so these are
        // genuinely unavailable here and are now simply absent.
      ),
      // Was `now + 1 day` without ever consulting the payload.
      journeyDate: _journeyDateOf(data),
      travelClass: _optional(data, const ['class', 'journey_class', 'travel_class']),
      // Now READ rather than assumed. This was hardcoded to prepared, so the
      // screen always claimed berths were final. The RailKit mapper reads the
      // same field, which is what showed the value was obtainable all along —
      // the same situation as the berth type two rounds ago.
      chartStatus: _chartStatusOf(data),
      passengers: passengers,
    );
  }

  /// First non-empty value among [keys], or null. No plausible default.
  String? _optional(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k]?.toString().trim();
      if (v != null && v.isNotEmpty && v != '—') return v;
    }
    return null;
  }

  /// Reads the chart flag if the payload states it, else null.
  ChartStatus? _chartStatusOf(Map<String, dynamic> data) {
    final raw = _optional(data, const [
      'chart_status',
      'chartStatus',
      'chart_prepared',
    ])?.toLowerCase();
    if (raw == null) return null;
    if (raw.contains('not') || raw == 'false') return ChartStatus.notPrepared;
    if (raw.contains('prepared') || raw == 'true') return ChartStatus.prepared;
    return null;
  }

  /// Reads the date of journey if stated, else null.
  DateTime? _journeyDateOf(Map<String, dynamic> data) {
    final raw =
        _optional(data, const ['journey_date', 'doj', 'date', 'travel_date']);
    if (raw == null) return null;
    final iso = DateTime.tryParse(raw);
    if (iso != null) return iso;
    // DD-MM-YYYY.
    final parts = raw.split(RegExp(r'[-/]'));
    if (parts.length == 3) {
      final d = int.tryParse(parts[0]);
      final mo = int.tryParse(parts[1]);
      final y = int.tryParse(parts[2]);
      if (d != null && mo != null && y != null) return DateTime(y, mo, d);
    }
    return null;
  }

  /// Delegates to [SeatAllocation.fromStatusString].
  ///
  /// FABRICATION REMOVED. This previously hardcoded the berth type to `MB` for
  /// every confirmed passenger — the fourth segment of the status string, which
  /// actually carries it, was parsed and discarded. It also substituted coach
  /// `B1` and berth `12` when segments were missing, forced RAC to position 4 and
  /// treated every non-CNF, non-RAC status as waitlist 12, so a cancelled ticket
  /// came back as "WL 12".
  SeatAllocation _parseSeatAllocation(String status) =>
      SeatAllocation.fromStatusString(status);

  /// Fetches real live train status & platform info from RapidAPI.
  Future<LiveTrainStatusData?> getLiveTrainStatus(String trainNumber) async {
    final cleanNum = trainNumber.trim();
    if (!isValidIRTrainNumber(cleanNum)) return null;

    final Uri uri = Uri.https(_apiHost, '/api/v3/getTrainLiveStatus', {
      'trainNo': cleanNum,
      'startDay': '0',
    });

    debugPrint('[RapidAPI Live Status Request] GET ${uri.toString()}');

    try {
      final response = await _client.get(uri, headers: _headers).timeout(const Duration(seconds: 10));

      _logShape('liveStatus', response.statusCode, response.body);
      debugPrint('=============================================================================');

      if (response.statusCode != 200) return null;

      final dynamic json = jsonDecode(response.body);
      if (json == null || json is! Map<String, dynamic>) return null;

      final data = json['data'] ?? json;
      if (data is! Map<String, dynamic>) return null;

      final currentStation = (data['current_station_name'] ?? data['current_station'] ?? data['currentStation'] ?? '').toString();
      final delayStr = (data['delay'] ?? data['delay_minutes'] ?? data['late_minutes'] ?? 0).toString();
      final delayMin = int.tryParse(delayStr) ?? 0;
      final rawPf = (data['platform'] ?? data['platform_number'] ?? data['pf_num'])?.toString();
      final platform = (rawPf != null && rawPf.isNotEmpty && rawPf != 'null' && rawPf != '0') ? rawPf : null;
      final statusText = (data['status'] ?? data['status_as_of'] ?? (delayMin > 0 ? 'Delayed ${delayMin}m' : 'On time')).toString();

      final rawName = (data['train_name'] ?? data['train_name_full'] ?? data['name'])?.toString().trim();
      final trainName = (rawName != null && rawName.isNotEmpty) ? rawName : 'Train $cleanNum';

      return LiveTrainStatusData(
        trainNumber: cleanNum,
        trainName: trainName,
        currentStation: currentStation,
        delayMinutes: delayMin,
        platform: platform,
        statusText: statusText,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[RapidAPI Live Status Error] $e');
      return null;
    }
  }
}

/// Real live status model returned from RapidAPI.
class LiveTrainStatusData {
  const LiveTrainStatusData({
    required this.trainNumber,
    required this.trainName,
    required this.currentStation,
    required this.delayMinutes,
    required this.platform,
    required this.statusText,
  });

  final String trainNumber;
  final String trainName;
  final String currentStation;
  final int delayMinutes;
  final String? platform;
  final String statusText;

  bool get isOnTime => delayMinutes <= 0;
}

/// Shared RapidApiService instance.
final rapidApiService = RapidApiService();
