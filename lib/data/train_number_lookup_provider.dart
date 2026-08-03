import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/train_summary.dart';
import 'railradar_mappers.dart';
import 'railradar_service.dart';
import 'train_repository.dart';

/// Resolves a 5-digit train number to a [TrainSummary] for the home screen's
/// "By Train No." search.
///
/// THREE OUTCOMES, DELIBERATELY DISTINGUISHED:
///
/// * `data` non-null — found, either in the local catalog or from RailRadar.
/// * `data` null — the lookup completed and the train genuinely does not exist.
/// * `error` — the lookup could not be completed (not configured, quota, 5xx,
///   network). The caller must NOT present this as "no such train": the user's
///   next action is to retry, not to re-check the number they typed.
///
/// Collapsing the last two into one message is the bug this provider exists to
/// avoid, so the distinction is load-bearing rather than cosmetic.
///
/// QUOTA. The catalog is checked first and costs nothing, so the 26 known trains
/// never touch the network. Beyond that, RailRadar's budget is 50 requests per
/// DAY and the `train-route-detail` Edge Function caches responses for 24h, so a
/// repeated number is free. Riverpod also caches per session, so re-submitting
/// the same number does not re-request. RailKit is deliberately not consulted
/// here — it has its own separate monthly budget and adds nothing this needs.
final trainNumberLookupProvider =
    FutureProvider.family<TrainSummary?, String>((ref, trainNumber) async {
  final number = trainNumber.trim();

  // Guard rather than trust the caller: a partial number must never reach the
  // network, and this provider is the last place that can enforce it.
  if (!isValidIRTrainNumber(number)) return null;

  // 1. Local catalog — instant and free.
  final local = trainRepository.resolveNumber(number);
  if (local != null) return local;

  // 2. RailRadar.
  final railradar = ref.read(railRadarServiceProvider);
  if (!railradar.isAvailable) {
    // Not a "no such train" answer — we never got to ask.
    throw const RailRadarException(
      RailRadarErrorCode.notConfiguredLocally,
      'Supabase not configured; train lookup unavailable',
    );
  }

  try {
    final res = await railradar.trainRouteDetail(number);
    final summary = trainSummaryFromRailRadarRoute(res.data);
    if (summary == null) {
      // Responded, but with nothing identifiable. Treated as not found rather
      // than as a failure: asking again would return the same thing.
      debugPrint('[TrainLookup] $number: unmappable RailRadar payload');
    }
    return summary;
  } on RailRadarException catch (e) {
    // The one error that is genuinely an answer about the train itself.
    if (e.code == RailRadarErrorCode.notFound) {
      debugPrint('[TrainLookup] $number: not found');
      return null;
    }
    debugPrint('[TrainLookup] $number: lookup failed — $e');
    rethrow;
  }
});
