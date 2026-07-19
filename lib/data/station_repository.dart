import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/rail_station.dart';

/// Loads the bundled Indian Railways station dataset once and provides fast,
/// ranked search over ~9,000 stations by name or code.
///
/// Station data source: DataMeet — Indian Railways (community open data),
/// normalized to `{code, name}`. Content was reformatted for the app.
class StationRepository {
  StationRepository(this._entries);

  final List<_Entry> _entries;

  int get count => _entries.length;

  static Future<StationRepository> load() async {
    final raw = await rootBundle.loadString('assets/data/stations.json');
    final decoded = jsonDecode(raw) as List<dynamic>;
    final entries = <_Entry>[];
    for (final item in decoded) {
      final station = RailStation.fromJson(item as Map<String, dynamic>);
      if (station.code.isEmpty || station.name.isEmpty) continue;
      entries.add(_Entry(
        station: station,
        codeLower: station.code.toLowerCase(),
        nameLower: station.name.toLowerCase(),
      ));
    }
    entries.sort((a, b) => a.nameLower.compareTo(b.nameLower));
    return StationRepository(entries);
  }

  RailStation? byCode(String code) {
    final target = code.toLowerCase();
    for (final e in _entries) {
      if (e.codeLower == target) return e.station;
    }
    return null;
  }

  /// Ranked search: exact code > code prefix > name prefix > word prefix >
  /// substring. Empty query returns the popular set.
  List<RailStation> search(String query, {int limit = 60}) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return popular;

    final scored = <_Scored>[];
    for (final e in _entries) {
      final score = _score(e, q);
      if (score > 0) scored.add(_Scored(e.station, score));
    }
    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      return byScore != 0 ? byScore : a.station.name.compareTo(b.station.name);
    });
    return [for (final s in scored.take(limit)) s.station];
  }

  int _score(_Entry e, String q) {
    var score = 0;
    if (e.codeLower == q) {
      score = 1000;
    } else if (e.codeLower.startsWith(q)) {
      score = 820;
    } else if (e.nameLower.startsWith(q)) {
      score = 720;
    } else if (_wordStartsWith(e.nameLower, q)) {
      score = 620;
    } else if (e.nameLower.contains(q)) {
      score = 420;
    } else if (e.codeLower.contains(q)) {
      score = 300;
    }
    if (score == 0) return 0;
    // Nudge shorter, "major"-looking names up within the same tier.
    return score - (e.nameLower.length ~/ 10);
  }

  bool _wordStartsWith(String name, String q) {
    for (final word in name.split(' ')) {
      if (word.startsWith(q)) return true;
    }
    return false;
  }

  /// A curated set of major stations shown before the user types.
  List<RailStation> get popular {
    const codes = [
      'NDLS', 'BCT', 'CSTM', 'MAS', 'HWH', 'SBC', 'SC', 'PUNE',
      'ADI', 'JP', 'LKO', 'CNB', 'PNBE', 'BBS', 'ERS', 'CBE',
      'NGP', 'BPL', 'ASR', 'GHY', 'YPR', 'BZA', 'JAT', 'TVC',
    ];
    final byCodeMap = {for (final e in _entries) e.codeLower: e.station};
    return [
      for (final c in codes)
        if (byCodeMap[c.toLowerCase()] != null) byCodeMap[c.toLowerCase()]!,
    ];
  }
}

class _Entry {
  _Entry({
    required this.station,
    required this.codeLower,
    required this.nameLower,
  });

  final RailStation station;
  final String codeLower;
  final String nameLower;
}

class _Scored {
  _Scored(this.station, this.score);
  final RailStation station;
  final int score;
}

/// Loads the station repository once (cached for the app's lifetime).
final stationRepositoryProvider = FutureProvider<StationRepository>((ref) {
  return StationRepository.load();
});

/// In-memory recently selected stations (most recent first, max 6).
final recentStationsProvider =
    NotifierProvider<RecentStationsNotifier, List<RailStation>>(
  RecentStationsNotifier.new,
);

class RecentStationsNotifier extends Notifier<List<RailStation>> {
  @override
  List<RailStation> build() => const [];

  void add(RailStation station) {
    final next = [station, ...state.where((s) => s.code != station.code)];
    state = next.take(6).toList();
  }
}
