import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../models/train_status.dart';

/// Identifies a train run (number + 'YYYY-MM-DD').
typedef TrainKey = ({String number, String date});

/// Client-side gateway to Layer 1 (baseline status) and Layer 2 (crowd-verified
/// position). The client only ever talks to Supabase — never RapidAPI directly.
///
/// Everything degrades gracefully when Supabase isn't configured: streams emit
/// `null` and writes are no-ops, so the app keeps running on mock data.
class TrainStatusService {
  SupabaseClient? get _client =>
      SupabaseConfig.isConfigured ? Supabase.instance.client : null;

  /// Live status for a train, via Supabase realtime on `train_status`.
  Stream<TrainStatus?> statusStream(String trainNumber, String date) {
    final client = _client;
    if (client == null) return Stream<TrainStatus?>.value(null);

    // Realtime streams filter on a single column; we narrow to the train and
    // pick the matching journey_date client-side.
    return client
        .from('train_status')
        .stream(primaryKey: ['id'])
        .eq('train_number', trainNumber)
        .map((rows) {
      for (final row in rows) {
        if (row['journey_date'].toString() == date) {
          return TrainStatus.fromMap(row);
        }
      }
      return null;
    });
  }

  /// Live crowd-verified position (preferred when fresh).
  Stream<CrowdVerifiedPosition?> verifiedPositionStream(
      String trainNumber, String date) {
    final client = _client;
    if (client == null) return Stream<CrowdVerifiedPosition?>.value(null);

    return client
        .from('crowd_verified_position')
        .stream(primaryKey: ['id'])
        .eq('train_number', trainNumber)
        .map((rows) {
      for (final row in rows) {
        if (row['journey_date'].toString() == date) {
          return CrowdVerifiedPosition.fromMap(row);
        }
      }
      return null;
    });
  }

  /// Mark a train "active" so the cron refreshes it, and trigger one immediate
  /// refresh so the user sees fresh data on open. Best-effort.
  Future<void> markTracked(String trainNumber, String date) async {
    final client = _client;
    if (client == null) return;
    try {
      await client.from('tracked_trains').upsert(
        {
          'train_number': trainNumber,
          'journey_date': date,
          'active': true,
          'last_active_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'train_number,journey_date',
      );
      // Warm the cache immediately (the function upserts train_status).
      await client.functions.invoke(
        'fetch-train-status',
        body: {'train_number': trainNumber, 'journey_date': date},
      );
    } catch (_) {
      // Non-fatal: realtime + cron will catch up.
    }
  }

  /// Mark inactive when the user leaves the screen. The 2-hour TTL in
  /// `refresh-active-trains` still covers the "searched in the last 2h" rule.
  Future<void> expireTracked(String trainNumber, String date) async {
    final client = _client;
    if (client == null) return;
    try {
      await client
          .from('tracked_trains')
          .update({'active': false})
          .eq('train_number', trainNumber)
          .eq('journey_date', date);
    } catch (_) {}
  }
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------
final trainStatusServiceProvider =
    Provider<TrainStatusService>((ref) => TrainStatusService());

/// Streams live status and manages the tracked_trains lifecycle: marks the
/// train active on first listen, expires it on dispose (screen close).
final trainStatusStreamProvider =
    StreamProvider.family<TrainStatus?, TrainKey>((ref, key) {
  final svc = ref.watch(trainStatusServiceProvider);
  svc.markTracked(key.number, key.date);
  ref.onDispose(() => svc.expireTracked(key.number, key.date));
  return svc.statusStream(key.number, key.date);
});

final crowdVerifiedPositionProvider =
    StreamProvider.family<CrowdVerifiedPosition?, TrainKey>((ref, key) {
  final svc = ref.watch(trainStatusServiceProvider);
  return svc.verifiedPositionStream(key.number, key.date);
});
