import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'language_controller.dart' show sharedPreferencesProvider;

// ---------------------------------------------------------------------------
// Domain types
// ---------------------------------------------------------------------------

/// The user's answer to "Is Platform X correct?"
enum PlatformVote { yes, no, notSure }

/// Unique key for one vote: which train, which station, which platform number.
@immutable
class PlatformVoteKey {
  const PlatformVoteKey({
    required this.trainNumber,
    required this.stationCode,
    required this.platform,
  });

  final String trainNumber;
  final String stationCode;
  final String platform;

  String get storageKey =>
      'pv_${trainNumber}_${stationCode}_$platform';

  @override
  bool operator ==(Object other) =>
      other is PlatformVoteKey &&
      other.trainNumber == trainNumber &&
      other.stationCode == stationCode &&
      other.platform == platform;

  @override
  int get hashCode => Object.hash(trainNumber, stationCode, platform);

  Map<String, dynamic> toJson() => {
        'train': trainNumber,
        'station': stationCode,
        'platform': platform,
      };
}

/// One persisted vote.
@immutable
class PlatformVoteRecord {
  const PlatformVoteRecord({
    required this.key,
    required this.vote,
    required this.votedAt,
  });

  final PlatformVoteKey key;
  final PlatformVote vote;
  final DateTime votedAt;

  Map<String, dynamic> toJson() => {
        ...key.toJson(),
        'vote': vote.name,
        'votedAt': votedAt.toIso8601String(),
      };

  factory PlatformVoteRecord.fromJson(Map<String, dynamic> j) {
    return PlatformVoteRecord(
      key: PlatformVoteKey(
        trainNumber: j['train'] as String,
        stationCode: j['station'] as String,
        platform: j['platform'] as String,
      ),
      vote: PlatformVote.values.firstWhere(
        (v) => v.name == j['vote'],
        orElse: () => PlatformVote.notSure,
      ),
      votedAt: DateTime.parse(j['votedAt'] as String),
    );
  }
}

// ---------------------------------------------------------------------------
// Riverpod provider
// ---------------------------------------------------------------------------

/// Per-key notifier: UI watches this to reactively show the vote state.
///
/// Follows the same `Notifier(this.arg)` + `NotifierProvider.family` pattern
/// used by [TrackingController].
final platformVoteProvider = NotifierProvider.family<
    PlatformVoteNotifier, PlatformVoteRecord?, PlatformVoteKey>(
  PlatformVoteNotifier.new,
);

class PlatformVoteNotifier extends Notifier<PlatformVoteRecord?> {
  PlatformVoteNotifier(this.key);

  final PlatformVoteKey key;

  @override
  PlatformVoteRecord? build() {
    final prefs = ref.read(sharedPreferencesProvider);
    if (prefs == null) return null;
    return _readVote(prefs, key);
  }

  /// Save a vote and update the reactive state.
  void vote(PlatformVote v) {
    final record = PlatformVoteRecord(
      key: key,
      vote: v,
      votedAt: DateTime.now(),
    );

    // Persist to SharedPreferences.
    final prefs = ref.read(sharedPreferencesProvider);
    if (prefs != null) {
      prefs.setString(key.storageKey, jsonEncode(record.toJson()));
    }

    // Update reactive state so the UI rebuilds immediately.
    state = record;
  }
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

PlatformVoteRecord? _readVote(SharedPreferences prefs, PlatformVoteKey key) {
  final raw = prefs.getString(key.storageKey);
  if (raw == null) return null;
  try {
    return PlatformVoteRecord.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
  } catch (e) {
    debugPrint('[PlatformVote] corrupt entry for ${key.storageKey}: $e');
    return null;
  }
}
