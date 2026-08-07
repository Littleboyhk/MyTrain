import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

/// Documented RailKit error states (mirrors the Edge Function's `code`).
enum RailKitErrorCode {
  /// Supabase isn't configured on this build → stay on local mock data.
  notConfiguredLocally,

  /// Server has no RAILKIT_API_KEY secret.
  notConfigured,

  /// 401 — bad key.
  invalidKey,

  /// 403 — key disabled.
  inactiveKey,

  /// 429 — monthly/burst budget hit. Show "check back later", DO NOT mock.
  quotaExceeded,

  /// 404 — the Edge Function itself isn't deployed. Distinct from a data error
  /// so logs say "not deployed" instead of a vague "request failed".
  functionNotDeployed,

  /// 400 — the request itself is wrong: bad PNR, train number, station code, or
  /// a date the quota does not allow (e.g. "Date outside Tatkal ARP"). Retrying
  /// the same request will never succeed, so the UI must ask the user to change
  /// something rather than offer a retry.
  ///
  /// NARROWER THAN IT WAS. This used to absorb every upstream 400, including
  /// IRCTC's transient refusals, so a booking-host outage was reported to the
  /// user as their own bad input. Those now arrive as [upstreamUnavailable].
  validation,

  /// 503 — the upstream answered, but refused rather than replying.
  ///
  /// Availability and PNR go through IRCTC's live booking system, which has a
  /// nightly maintenance window (roughly 23:45–00:15 IST) and is flaky around it.
  /// Observed messages include "Unable to perform Transaction. Please try later.",
  /// "Booking will be very slow or not accessible…" and "Something went wrong
  /// while fetching availability." Live tracking is unaffected, which is why the
  /// rest of the app can look healthy while this fails.
  ///
  /// Nothing is wrong with the request: retrying later is the correct advice, and
  /// the UI must not imply the user mistyped anything.
  upstreamUnavailable,

  unknown,
}

class RailKitException implements Exception {
  final RailKitErrorCode code;
  final String message;
  const RailKitException(this.code, this.message);

  bool get isQuota => code == RailKitErrorCode.quotaExceeded;

  /// True when the far end refused rather than answering, so trying again later
  /// is the honest advice and the user's input is not at fault.
  bool get isUpstreamUnavailable =>
      code == RailKitErrorCode.upstreamUnavailable;

  /// True when we should silently fall back to mock/local data (i.e. the
  /// backend simply isn't wired up on this build). A quota/keys/validation
  /// error is a REAL state the UI should surface, not hide behind mock data.
  bool get isSilentFallback => code == RailKitErrorCode.notConfiguredLocally;

  @override
  String toString() => 'RailKitException(${code.name}): $message';
}

/// Monthly usage snapshot returned alongside every response so the UI (or logs)
/// can warn before the monthly request limit is hit.
class RailKitUsage {
  final int count;
  final int limit;
  final bool warn;
  const RailKitUsage({required this.count, required this.limit, required this.warn});

  /// Fallback limit for when the server sent no usage block.
  ///
  /// Matches the Enterprise allowance and the server's own default. It was 50 —
  /// the free-tier figure — which made a healthy account look nearly exhausted in
  /// any UI reading [remaining]. The authoritative number is always the server's
  /// `limit` field; this only covers its absence.
  static const int defaultLimit = 10000;

  factory RailKitUsage.fromMap(Map<String, dynamic>? m) => RailKitUsage(
        count: (m?['count'] as num?)?.toInt() ?? 0,
        limit: (m?['limit'] as num?)?.toInt() ?? defaultLimit,
        warn: m?['warn'] == true,
      );

  int get remaining => (limit - count).clamp(0, limit);
}

/// A successful RailKit response: the RAW RailKit JSON (`data`) plus whether it
/// came from cache and the current monthly usage.
class RailKitResponse {
  /// Raw RailKit payload — a Map (pnr/track/train_info) or List/Map (search).
  final dynamic data;
  final bool cached;
  final RailKitUsage usage;

  /// Only set by `track-train`: "live" when real running status was returned,
  /// "schedule" when it fell back to static route data (train not running that
  /// date). Drives the live/OFFLINE badge.
  final String? source;

  const RailKitResponse({
    required this.data,
    required this.cached,
    required this.usage,
    this.source,
  });

  bool get isLive => source == 'live';
  bool get isScheduleOnly => source == 'schedule';
}

/// Client gateway to RailKit. Can talk directly to RailKit REST API using
/// RAILKIT_API_KEY, or through Supabase Edge Functions.
class RailKitService {
  const RailKitService();

  bool get isAvailable => SupabaseConfig.isConfigured;

  Future<RailKitResponse> _invoke(
    String function,
    Map<String, dynamic> body,
  ) async {
    if (!isAvailable) {
      throw const RailKitException(
        RailKitErrorCode.notConfiguredLocally,
        'Supabase client not configured',
      );
    }

    try {
      final res = await Supabase.instance.client.functions.invoke(
        function,
        body: body,
      );
      final payload = res.data;
      if (payload is Map && payload.containsKey('data')) {
        final inner = payload['data'];
        if (inner is Map && inner['success'] == false) {
          throw RailKitException(
            RailKitErrorCode.unknown,
            inner['error']?.toString() ?? 'RailKit returned no data',
          );
        }
        return RailKitResponse(
          data: inner,
          cached: payload['cached'] == true,
          usage: RailKitUsage.fromMap(
            (payload['usage'] as Map?)?.cast<String, dynamic>(),
          ),
          source: payload['source']?.toString(),
        );
      }
      throw const RailKitException(
        RailKitErrorCode.unknown,
        'Unexpected RailKit response shape',
      );
    } on FunctionException catch (e) {
      throw _mapFunctionException(function, e);
    }
  }

  /// Turns a Supabase [FunctionException] into a RailKitException that keeps the
  /// diagnostic detail.
  ///
  /// Our own Edge Functions answer `{error, code}`, but Supabase's own gateway
  /// answers `{code:"NOT_FOUND", message:"Requested function was not found"}`
  /// when a function isn't deployed. Reading only `error` threw that away and
  /// showed a generic "request failed", which hid the real cause.
  RailKitException _mapFunctionException(String function, FunctionException e) {
    final details = e.details;
    String? upstreamCode;
    String? upstreamMessage;
    if (details is Map) {
      upstreamCode = details['code']?.toString();
      // our functions use `error`; the Supabase gateway uses `message`
      upstreamMessage =
          (details['error'] ?? details['message'])?.toString();
    } else if (details != null) {
      upstreamMessage = details.toString();
    }

    final status = e.status;
    final mapped = switch (upstreamCode) {
      'not_configured' => RailKitErrorCode.notConfigured,
      'invalid_key' => RailKitErrorCode.invalidKey,
      'inactive_key' => RailKitErrorCode.inactiveKey,
      'quota_exceeded' => RailKitErrorCode.quotaExceeded,
      'validation' => RailKitErrorCode.validation,
      'upstream_unavailable' => RailKitErrorCode.upstreamUnavailable,
      'NOT_FOUND' => RailKitErrorCode.functionNotDeployed,
      _ => switch (status) {
          404 => RailKitErrorCode.functionNotDeployed,
          // Status-only fallback for a body we could not read a code out of.
          // 502/503/504 all mean the far end did not answer properly.
          502 || 503 || 504 => RailKitErrorCode.upstreamUnavailable,
          _ => RailKitErrorCode.unknown,
        },
    };

    final detail = [
      "function '$function'",
      'HTTP $status',
      ?upstreamCode,
      ?upstreamMessage,
    ].join(' · ');

    final message = mapped == RailKitErrorCode.functionNotDeployed
        ? "Edge Function '$function' is not deployed ($detail)"
        : detail;

    // Logged at the source so the cause is visible even if a caller only
    // surfaces its own user-facing text.
    debugPrint('[RailKit] $message');
    return RailKitException(mapped, message);
  }

  /// Trains between two station codes (e.g. KYJ → SBC). `date` = 'YYYY-MM-DD'.
  Future<RailKitResponse> searchTrains({
    required String from,
    required String to,
    String? date,
  }) =>
      _invoke('search-trains', {
        'from': from,
        'to': to,
        'date': ?date,
      });

  /// Live running status. `date` = 'YYYY-MM-DD'.
  ///
  /// The most quota-hungry method: [TrackingController] polls it every 30s while
  /// a tracking screen is open, which is ~120 requests/hour, or roughly 83 hours
  /// of tracking against the 10,000/month Enterprise allowance.
  ///
  /// NOTE ON THE CACHE. `TTL.track` is 20s while the poll interval is 30s, so a
  /// single device's polls always find the entry expired and spend a request. The
  /// cache only earns its keep when several clients track the SAME train inside
  /// one TTL window. Raising the TTL above the poll interval would cut usage at
  /// the cost of staleness; left alone deliberately, because freshness is the
  /// point of this screen.
  Future<RailKitResponse> trackTrain({
    required String trainNumber,
    required String date,
  }) =>
      _invoke('track-train', {
        'train_number': trainNumber,
        'date': date,
      });

  /// 10-digit PNR status.
  Future<RailKitResponse> checkPnr(String pnr) =>
      _invoke('pnr-status', {'pnr': pnr});

  /// Static route/schedule (+ per-station platforms) for a train number.
  Future<RailKitResponse> trainInfo(String trainNumber) =>
      _invoke('train-info', {'train_number': trainNumber});

  /// Seat availability for a train, route, date, class, and quota.
  Future<RailKitResponse> getAvailability({
    required String trainNumber,
    required String from,
    required String to,
    required String date,
    String classCode = 'SL',
    String quota = 'GN',
  }) =>
      _invoke('seat-availability', {
        'train_number': trainNumber,
        'from': from,
        'to': to,
        'date': date,
        'class_code': classCode,
        'quota': quota,
      });

  /// Live station board (arrivals/departures at a station).
  Future<RailKitResponse> liveAtStation({
    required String stationCode,
    int? hours,
  }) =>
      _invoke('live-at-station', {
        'station_code': stationCode,
        if (hours != null) 'hours': hours,
      });

  /// Fare lookup for a train between two stations.
  Future<RailKitResponse> fareLookup({
    required String trainNumber,
    required String from,
    required String to,
    String? date,
    String classCode = '3A',
    String quota = 'GN',
  }) =>
      _invoke('fare-lookup', {
        'train_number': trainNumber,
        'from': from,
        'to': to,
        if (date != null) 'date': date,
        'class_code': classCode,
        'quota': quota,
      });

  /// Train historical punctuality for a given date.
  Future<RailKitResponse> trainHistory({
    required String trainNumber,
    required String date,
  }) =>
      _invoke('train-history', {
        'train_number': trainNumber,
        'date': date,
      });

  /// List of cancelled trains for a date.
  Future<RailKitResponse> cancelList({String? date}) =>
      _invoke('cancel-list', {
        if (date != null) 'date': date,
      });
}

final railKitServiceProvider =
    Provider<RailKitService>((ref) => const RailKitService());

/// Test-only hook onto the error mapping, so the diagnostic quality of failure
/// messages can be asserted without a live backend.
@visibleForTesting
RailKitException mapFunctionExceptionForTest(
  String function,
  FunctionException e,
) =>
    const RailKitService()._mapFunctionException(function, e);
