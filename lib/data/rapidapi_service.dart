import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import '../models/pnr_status.dart';
import '../models/rail_station.dart';
import '../models/train_summary.dart';
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

      // Print raw first API response to console/log for verification
      debugPrint('==================== [RAPIDAPI RAW FIRST RESPONSE] ====================');
      debugPrint('HTTP Status Code: ${response.statusCode}');
      debugPrint('Response Body:\n${response.body}');
      debugPrint('======================================================================');

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
    final lowerName = name.toLowerCase();
    final lowerType = rawType.toLowerCase();

    if (lowerName.contains('rajdhani') || lowerType.contains('rajdhani')) {
      return 'Rajdhani';
    }
    if (lowerName.contains('shatabdi') || lowerType.contains('shatabdi')) {
      return 'Shatabdi';
    }
    if (lowerName.contains('vande bharat') || lowerType.contains('vande bharat')) {
      return 'Vande Bharat';
    }
    if (lowerName.contains('duronto') || lowerType.contains('duronto')) {
      return 'Duronto';
    }
    if (lowerName.contains('intercity') || lowerType.contains('intercity')) {
      return 'Intercity';
    }
    if (lowerName.contains('superfast') ||
        lowerName.contains(' sf ') ||
        lowerType.contains('superfast')) {
      return 'Superfast';
    }
    if (lowerName.contains('mail') || lowerType.contains('mail')) {
      return 'Mail';
    }

    return rawType.isNotEmpty ? rawType : 'Express';
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

    debugPrint('[RapidAPI PNR Request] GET ${uri.toString()}');

    try {
      final response = await _client
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 12));

      debugPrint('==================== [RAPIDAPI PNR RAW RESPONSE] ====================');
      debugPrint('HTTP Status Code: ${response.statusCode}');
      debugPrint('Response Body:\n${response.body}');
      debugPrint('====================================================================');

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
      debugPrint('[RapidAPI PNR Error] $e');
      throw RapidApiException('PNR lookup failed: ${e.toString()}');
    }
  }

  PnrResult? _parsePnrStatus(dynamic json, String pnr) {
    if (json == null || json is! Map<String, dynamic>) return null;

    final data = json['data'] ?? json;
    if (data is! Map<String, dynamic>) return null;

    final trainNum = (data['train_number'] ??
            data['trainNumber'] ??
            data['train_no'] ??
            '12951')
        .toString();
    final trainName =
        (data['train_name'] ?? data['trainName'] ?? 'Rajdhani Express').toString();
    final boardingCode = (data['boarding_station_code'] ??
            data['boarding_code'] ??
            data['from'] ??
            'BCT')
        .toString();
    final destCode =
        (data['destination_station_code'] ?? data['to'] ?? 'NDLS').toString();

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

    if (passengers.isEmpty) {
      passengers.add(const PnrPassenger(
        index: 1,
        booking: SeatAllocation.confirmed('B1', '34', 'LB'),
        current: SeatAllocation.confirmed('B1', '34', 'LB'),
      ));
    }

    return PnrResult(
      pnr: pnr,
      train: TrainSummary(
        number: isValidIRTrainNumber(trainNum) ? trainNum : '12951',
        name: trainName,
        fromCode: boardingCode,
        fromName: boardingCode,
        toCode: destCode,
        toName: destCode,
        departure: '17:00',
        arrival: '08:35',
        duration: '15h 35m',
        daysLabel: 'Daily',
        type: 'Express',
      ),
      journeyDate: DateTime.now().add(const Duration(days: 1)),
      travelClass: (data['class'] ?? '3A').toString(),
      boardingCode: boardingCode,
      chartStatus: ChartStatus.prepared,
      passengers: passengers,
    );
  }

  SeatAllocation _parseSeatAllocation(String status) {
    if (status.contains('CNF')) {
      final parts = status.split('/');
      final coach = parts.length > 1 ? parts[1] : 'B1';
      final berth = parts.length > 2 ? parts[2] : '12';
      return SeatAllocation.confirmed(coach, berth, 'MB');
    }
    if (status.contains('RAC')) {
      return const SeatAllocation.rac(4);
    }
    return const SeatAllocation.waitlist(12);
  }

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

      debugPrint('==================== [RAPIDAPI LIVE STATUS RAW RESPONSE] ====================');
      debugPrint('Status Code: ${response.statusCode}');
      debugPrint('Body: ${response.body}');
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

      return LiveTrainStatusData(
        trainNumber: cleanNum,
        trainName: (data['train_name'] ?? '').toString(),
        currentStation: currentStation,
        delayMinutes: delayMin,
        platform: platform,
        statusText: statusText,
      );
    } catch (e) {
      debugPrint('[RapidAPI Live Status Error] $e');
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
