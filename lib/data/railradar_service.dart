import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

/// RailRadar — a deliberately NARROW second data source.
///
/// It is used for ONE thing: full train route detail including pass-through
/// stations, which RailKit's `getTrainInfo` does not return (verified on 16525:
/// RailKit gives 46 halt-only entries, RailRadar gives 166 = 47 halts + 119
/// pass-through). Search, PNR and live tracking stay on RailKit.
///
/// Quota differs from RailKit: 50 requests per DAY, resetting daily. The key
/// lives only as an Edge Function secret; the client only ever calls our own
/// `train-route-detail` function, which caches route data for 24h.
enum RailRadarErrorCode {
  /// Supabase isn't configured on this build.
  notConfiguredLocally,

  /// Server has no RAILRADAR_API_KEY secret, or the cache schema is missing.
  notConfigured,

  invalidKey,

  /// Daily (not monthly) budget reached.
  quotaExceeded,

  /// RailRadar has no such train.
  notFound,

  /// The Edge Function itself isn't deployed.
  functionNotDeployed,

  validation,

  unknown,
}

class RailRadarException implements Exception {
  final RailRadarErrorCode code;
  final String message;
  const RailRadarException(this.code, this.message);

  bool get isQuota => code == RailRadarErrorCode.quotaExceeded;

  @override
  String toString() => 'RailRadarException(${code.name}): $message';
}

/// Daily usage snapshot returned with every response.
class RailRadarUsage {
  /// 'YYYY-MM-DD' (UTC) the count belongs to.
  final String day;
  final int count;
  final int limit;
  final bool warn;

  const RailRadarUsage({
    required this.day,
    required this.count,
    required this.limit,
    required this.warn,
  });

  factory RailRadarUsage.fromMap(Map<String, dynamic>? m) => RailRadarUsage(
        day: m?['day']?.toString() ?? '',
        count: (m?['count'] as num?)?.toInt() ?? 0,
        limit: (m?['limit'] as num?)?.toInt() ?? 50,
        warn: m?['warn'] == true,
      );

  int get remaining => (limit - count).clamp(0, limit);
}

class RailRadarResponse {
  /// Raw RailRadar `data`: `{ train: {...}, route: [...] }`.
  final dynamic data;
  final bool cached;
  final RailRadarUsage usage;

  const RailRadarResponse({
    required this.data,
    required this.cached,
    required this.usage,
  });
}

class RailRadarService {
  const RailRadarService();

  bool get isAvailable => SupabaseConfig.isConfigured;

  /// Full route for [trainNumber] INCLUDING pass-through stations.
  Future<RailRadarResponse> trainRouteDetail(String trainNumber) async {
    if (!isAvailable) {
      throw const RailRadarException(
        RailRadarErrorCode.notConfiguredLocally,
        'Supabase not configured; RailRadar route detail unavailable',
      );
    }
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'train-route-detail',
        body: {'train_number': trainNumber},
      );
      final payload = res.data;
      if (payload is Map && payload.containsKey('data')) {
        final inner = payload['data'];
        // Defence in depth: RailRadar signals data failures with
        // {success:false, error:{...}} at HTTP 200. The Edge Function already
        // rejects those, but if one ever reaches here it is an error, never
        // displayable data.
        if (inner is Map && inner['success'] == false) {
          throw RailRadarException(
            RailRadarErrorCode.unknown,
            inner['error']?.toString() ?? 'RailRadar returned no data',
          );
        }
        return RailRadarResponse(
          data: inner,
          cached: payload['cached'] == true,
          usage: RailRadarUsage.fromMap(
            (payload['usage'] as Map?)?.cast<String, dynamic>(),
          ),
        );
      }
      throw const RailRadarException(
        RailRadarErrorCode.unknown,
        'Unexpected RailRadar response shape',
      );
    } on FunctionException catch (e) {
      throw _mapFunctionException(e);
    }
  }

  RailRadarException _mapFunctionException(FunctionException e) {
    final details = e.details;
    String? upstreamCode;
    String? upstreamMessage;
    if (details is Map) {
      upstreamCode = details['code']?.toString();
      // our function uses `error`; the Supabase gateway uses `message`
      upstreamMessage = (details['error'] ?? details['message'])?.toString();
    } else if (details != null) {
      upstreamMessage = details.toString();
    }

    final mapped = switch (upstreamCode) {
      'not_configured' => RailRadarErrorCode.notConfigured,
      'invalid_key' => RailRadarErrorCode.invalidKey,
      'quota_exceeded' => RailRadarErrorCode.quotaExceeded,
      'not_found' => RailRadarErrorCode.notFound,
      'validation' => RailRadarErrorCode.validation,
      'NOT_FOUND' => RailRadarErrorCode.functionNotDeployed,
      _ => e.status == 404
          ? RailRadarErrorCode.functionNotDeployed
          : RailRadarErrorCode.unknown,
    };

    final detail = [
      "function 'train-route-detail'",
      'HTTP ${e.status}',
      ?upstreamCode,
      ?upstreamMessage,
    ].join(' · ');

    debugPrint('[RailRadar] $detail');
    return RailRadarException(mapped, detail);
  }
}

final railRadarServiceProvider =
    Provider<RailRadarService>((ref) => const RailRadarService());
