import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The project's ONE anonymous-contributor identifier scheme.
///
/// 16 cryptographically-random bytes as hex, generated fresh and never persisted.
/// A stored UUID would be a permanent device identifier, which is exactly what
/// this app's privacy model refuses to keep next to location data.
///
/// The server never stores what the client sends: `submit-position`,
/// `submit-cell-observation` and `submit-coach-report` all HMAC it as
/// `${anon_id}:${train_number}:${journey_date}` with a salt the client never
/// holds. So the digest can count distinct contributors and catch one device
/// spamming a coach, and cannot be linked across train-days or back to a person.
///
/// This lived as a private copy in both `crowd_position_service.dart` and
/// `offline/cell_observation_service.dart`. Two identical copies of a privacy
/// primitive is one too many — if the scheme ever needs to change it has to
/// change in one place.
String rotatingAnonId() {
  final rng = Random.secure();
  return List<int>.generate(16, (_) => rng.nextInt(256))
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
}

/// One anonymous id for the whole app run.
///
/// SESSION-SCOPED, not per-submission and not persisted. Both bounds matter:
///
/// * A fresh id per submission would make the server's duplicate and rate-limit
///   checks useless — every spam report would look like a new contributor.
/// * A persisted id would be a permanent device identifier.
///
/// Per-journey rotation (what [CellObservationRecorder] does) is not available to
/// coach reports, which are one-off taps with no journey-scoped object to hang a
/// lifetime on. The server's per-train-day hashing means a session-lifetime id is
/// still unlinkable across journeys.
final sessionAnonIdProvider = Provider<String>((ref) => rotatingAnonId());
