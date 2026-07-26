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

  /// 400 — bad PNR / train number / date.
  validation,

  unknown,
}

class RailKitException implements Exception {
  final RailKitErrorCode code;
  final String message;
  const RailKitException(this.code, this.message);

  bool get isQuota => code == RailKitErrorCode.quotaExceeded;

  /// True when we should silently fall back to mock/local data (i.e. the
  /// backend simply isn't wired up on this build). A quota/keys/validation
  /// error is a REAL state the UI should surface, not hide behind mock data.
  bool get isSilentFallback => code == RailKitErrorCode.notConfiguredLocally;

  @override
  String toString() => 'RailKitException(${code.name}): $message';
}

/// Monthly usage snapshot returned alongside every response so the UI (or logs)
/// can warn before the 50-request free-tier limit is hit.
class RailKitUsage {
  final int count;
  final int limit;
  final bool warn;
  const RailKitUsage({required this.count, required this.limit, required this.warn});

  factory RailKitUsage.fromMap(Map<String, dynamic>? m) => RailKitUsage(
        count: (m?['count'] as num?)?.toInt() ?? 0,
        limit: (m?['limit'] as num?)?.toInt() ?? 50,
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

/// Client gateway to RailKit. Like the rest of the app, the client talks ONLY
/// to Supabase (the `railkit` Edge Function); the RailKit key never ships here.
/// Caching + usage tracking all live server-side, so calling these repeatedly
/// is safe — a warm cache costs zero RailKit quota.
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
        'Supabase not configured; live railway data unavailable',
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
        // Defence in depth: RailKit resolves with {success:false, error:...}
        // instead of throwing. The Edge Function already unwraps/rejects that,
        // but if such an envelope ever reaches here, treat it as an error —
        // never as displayable data.
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
      'NOT_FOUND' => RailKitErrorCode.functionNotDeployed,
      _ => status == 404
          ? RailKitErrorCode.functionNotDeployed
          : RailKitErrorCode.unknown,
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
  /// NOTE: live tracking is the most quota-hungry method (short 4-min cache).
  /// On the free tier prefer the existing RapidAPI + crowd layer for continuous
  /// tracking, and use this for a manual "refresh from RailKit" action only.
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
