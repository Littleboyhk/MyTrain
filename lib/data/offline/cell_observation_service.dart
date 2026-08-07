import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/supabase_config.dart';
import '../anon_id.dart';
import '../crowd_position_service.dart';
import 'cell_info_source.dart';
import 'offline_tracking_controller.dart';

/// PHASE 2 GROUNDWORK — building a cell-tower → position dataset.
///
/// WHAT THIS IS FOR. A future "zero-GPS" mode could place a train from cell-tower
/// identity alone, which would cost a fraction of the battery GPS does and work
/// where GPS cannot. No such database exists for this project, so it has to be
/// collected first. That is all this does: pair a cell identity with a position
/// that has already been *verified* by map-matching onto a known route, and send
/// the pair to the backend.
///
/// IT IS NOT USED FOR TRACKING. Nothing in the live position path reads any of
/// this. It is write-only, one direction, for later.
///
/// WHY IT CANNOT SLOW PHASE 1 DOWN. It never runs inside the GPS loop. It
/// observes [offlineTrackingProvider] from the outside and does its work in a
/// detached future, so the recording path shares no code and no await with the
/// path that computes the user's position. Every failure is swallowed with a log.
///
/// CONSENT. Gated on the user having crowd sharing switched on — the app's
/// existing, explicit opt-in. With it off, nothing is read and nothing is sent.
///
/// PRIVACY. The only identifier sent is a per-session random value, which the
/// `submit-cell-observation` Edge Function HMACs with a server-side salt before
/// storing. No stable device id is generated, persisted or transmitted, so an
/// observation cannot be traced to a handset — the same guarantee
/// `submit-position` already makes for crowd pings.
class CellObservationRecorder extends Notifier<int> {
  CellObservationRecorder(this.arg);

  /// The journey being observed.
  final OfflineTrackingKey arg;

  /// Don't log the same cell more often than this. A stationary train would
  /// otherwise send the same row every 20 seconds for an hour.
  static const Duration _minSpacing = Duration(minutes: 1);

  late final CellInfoSource _cellInfo = createCellInfoSource();

  /// Fresh per recorder instance, i.e. per journey. Deliberately NOT persisted:
  /// a stored UUID would be a permanent device identifier, which is exactly what
  /// this project's privacy model avoids. The server salts and hashes this, so
  /// its only purpose is letting aggregation count distinct contributors within
  /// one train-day.
  ///
  /// Generator shared with the other crowdsourced submitters — see
  /// `lib/data/anon_id.dart`.
  late final String _anonId = rotatingAnonId();

  DateTime? _lastRecordedAt;
  int? _lastCellId;
  DateTime? _lastSeenFixAt;

  /// Count of observations sent this session, exposed purely for diagnostics.
  @override
  int build() {
    // Nothing to do where cell identity is unreadable — notably iOS and web.
    if (!_cellInfo.isSupported) {
      debugPrint('[CellObs] unsupported on $defaultTargetPlatform — inert');
      return 0;
    }

    ref.listen<OfflineTrackingState>(
      offlineTrackingProvider(arg),
      (previous, next) => _onOfflineState(next),
    );

    return 0;
  }

  void _onOfflineState(OfflineTrackingState offline) {
    // Only a fix that matched the route is worth recording: an unverified point
    // would poison the dataset with positions the train was never at.
    if (offline.stage != OfflineStage.tracking) return;
    final fix = offline.lastFix;
    final fixAt = offline.lastFixAt;
    final alongKm = offline.alongKm;
    if (fix == null || fixAt == null || alongKm == null) return;

    // One record per fix, not per rebuild.
    if (_lastSeenFixAt != null && !fixAt.isAfter(_lastSeenFixAt!)) return;
    _lastSeenFixAt = fixAt;

    // Consent gate, re-read every time so switching sharing off takes effect
    // immediately rather than at the next journey.
    if (!ref.read(crowdSharingProvider).active) return;

    if (!SupabaseConfig.isConfigured) return;

    // Detached on purpose: the caller is a provider listener on the path that
    // publishes the user's position, and it must return immediately.
    unawaited(_record(
      lat: fix.latitude,
      lng: fix.longitude,
      alongKm: alongKm,
      accuracyM: offline.lastFixAccuracyM,
      fixAt: fixAt,
    ));
  }

  Future<void> _record({
    required double lat,
    required double lng,
    required double alongKm,
    required double? accuracyM,
    required DateTime fixAt,
  }) async {
    try {
      final cell = await _cellInfo.read();
      if (cell == null) return;

      // Throttle: same cell, recently logged, nothing new to learn.
      final now = DateTime.now();
      final last = _lastRecordedAt;
      if (cell.cellId == _lastCellId &&
          last != null &&
          now.difference(last) < _minSpacing) {
        return;
      }

      await Supabase.instance.client.functions
          .invoke(
            'submit-cell-observation',
            body: {
              'train_number': arg.number,
              'journey_date': arg.date,
              // radio_type / mcc / mnc / lac / cell_id / signal_dbm — the column
              // names on `cell_tower_logs` are these same keys, so the payload
              // maps one-to-one with no translation layer.
              ...cell.toJson(),
              // The matched point, not the raw one, is the value here: it is a
              // position corroborated against a known route.
              'lat': lat,
              'lng': lng,
              'along_km': alongKm,
              // Lets aggregation weight or exclude loose fixes.
              'gps_accuracy_m': accuracyM,
              'observed_at': fixAt.toUtc().toIso8601String(),
              // Hashed server-side into `device_id`; never stored as sent.
              'anon_id': _anonId,
            },
          )
          .timeout(const Duration(seconds: 10));

      _lastRecordedAt = now;
      _lastCellId = cell.cellId;
      state = state + 1;
      debugPrint('[CellObs] logged $cell at '
          '${alongKm.toStringAsFixed(1)} km (total $state)');
    } on TimeoutException {
      debugPrint('[CellObs] upload timed out');
    } on FunctionException catch (e) {
      // 404 until `supabase/functions/submit-cell-observation` is deployed, and
      // 400 for a payload the function rejects. Either way: logged and dropped.
      // This must never propagate — a dataset-collection failure is not the
      // user's problem and must not disturb the journey on screen.
      debugPrint('[CellObs] submit-cell-observation failed: '
          'status=${e.status} details=${e.details}');
    } catch (e) {
      // Catch-all by design. Every throw inside this method is swallowed here so
      // the detached future can never surface as an unhandled error.
      debugPrint('[CellObs] record failed: $e');
    }
  }
}

/// Watch this from the tracking screen to enable Phase 2 collection for a
/// journey. Watching it is the only thing that activates it; not watching it
/// means it never runs.
final cellObservationProvider =
    NotifierProvider.family<CellObservationRecorder, int, OfflineTrackingKey>(
  CellObservationRecorder.new,
);
