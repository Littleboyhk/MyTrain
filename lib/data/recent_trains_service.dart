import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/train_summary.dart';
import 'language_controller.dart' show sharedPreferencesProvider;

/// Trains the user has actually opened, most recent first.
///
/// Persisted with `shared_preferences` (unlike [recentStationsProvider], which
/// is in-memory) because a "recent" list that empties on every app launch is
/// useless — the point is to get straight back to the train you were following.
///
/// Stores a snapshot of the [TrainSummary] rather than just the number, so the
/// card renders instantly offline with no API call. Times/running-days in an old
/// entry are whatever the source said when it was viewed; opening the train
/// re-fetches live data, so nothing stale is ever presented as live.
final recentTrainsProvider =
    NotifierProvider<RecentTrainsNotifier, List<TrainSummary>>(
  RecentTrainsNotifier.new,
);

class RecentTrainsNotifier extends Notifier<List<TrainSummary>> {
  static const String _key = 'recent_trains_v1';

  /// Matches the 6-item cap used for recent stations.
  static const int maxEntries = 6;

  SharedPreferences? get _prefs => ref.read(sharedPreferencesProvider);

  @override
  List<TrainSummary> build() => _load();

  List<TrainSummary> _load() {
    final raw = _prefs?.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final out = <TrainSummary>[];
      for (final entry in decoded) {
        if (entry is! Map) continue;
        final t = _fromMap(entry.cast<String, dynamic>());
        if (t != null) out.add(t);
      }
      return out.take(maxEntries).toList();
    } catch (e) {
      // Corrupt/legacy payload: start clean rather than crash the home screen.
      debugPrint('[RecentTrains] could not read stored list: $e');
      return const [];
    }
  }

  /// Records a train as recently viewed. Re-viewing moves it to the front
  /// instead of duplicating it.
  void add(TrainSummary train) {
    if (train.number.trim().isEmpty) return;
    final next = <TrainSummary>[
      train,
      ...state.where((t) => t.number != train.number),
    ].take(maxEntries).toList();
    state = next;
    _persist(next);
  }

  void remove(String trainNumber) {
    final next = state.where((t) => t.number != trainNumber).toList();
    state = next;
    _persist(next);
  }

  void clear() {
    state = const [];
    _persist(const []);
  }

  Future<void> _persist(List<TrainSummary> list) async {
    final prefs = _prefs;
    if (prefs == null) {
      debugPrint('[RecentTrains] prefs unavailable — not persisted');
      return;
    }
    try {
      await prefs.setString(
        _key,
        jsonEncode(list.map(_toMap).toList()),
      );
    } catch (e) {
      debugPrint('[RecentTrains] persist failed: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Serialisation. Kept local to this file: TrainSummary is a plain view model
  // and shouldn't grow storage concerns.
  // ---------------------------------------------------------------------------
  static Map<String, dynamic> _toMap(TrainSummary t) => {
        'number': t.number,
        'name': t.name,
        'fromCode': t.fromCode,
        'fromName': t.fromName,
        'toCode': t.toCode,
        'toName': t.toName,
        'departure': t.departure,
        'arrival': t.arrival,
        'duration': t.duration,
        'daysLabel': t.daysLabel,
        'type': t.type,
        'arrivalDayOffset': t.arrivalDayOffset,
        'runningDaysMask': t.runningDaysMask,
        'runsUntilLabel': t.runsUntilLabel,
      };

  static TrainSummary? _fromMap(Map<String, dynamic> m) {
    final number = m['number']?.toString() ?? '';
    if (number.isEmpty) return null;
    String s(String key, [String fallback = '']) =>
        m[key]?.toString() ?? fallback;
    return TrainSummary(
      number: number,
      name: s('name', 'Train $number'),
      fromCode: s('fromCode'),
      fromName: s('fromName'),
      toCode: s('toCode'),
      toName: s('toName'),
      departure: s('departure', '--:--'),
      arrival: s('arrival', '--:--'),
      duration: s('duration'),
      daysLabel: s('daysLabel'),
      type: s('type', 'Express'),
      arrivalDayOffset: (m['arrivalDayOffset'] as num?)?.toInt() ?? 0,
      runningDaysMask: m['runningDaysMask']?.toString(),
      runsUntilLabel: m['runsUntilLabel']?.toString(),
    );
  }
}
