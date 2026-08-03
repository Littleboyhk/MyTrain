import 'package:flutter/foundation.dart';

/// Where a station sits relative to the train, as reported by RailKit's
/// `trackTrain` timeline (`status: "passed" | "current" | "upcoming"`).
enum StationLiveStage {
  passed,
  current,
  upcoming,

  /// RailKit did not report this station at all — its timeline is stoppage-only
  /// while the rendered route (RailRadar) includes pass-through points.
  unreported;

  /// True when an `actual` time from this stage describes something that has
  /// already happened.
  ///
  /// THE LOAD-BEARING RULE. RailKit's documentation shows an `actual` field on
  /// every stoppage, but publishes no example of an *upcoming* stoppage, so what
  /// `actual` holds before a train arrives is undocumented — it could be an ETA,
  /// an echo of the scheduled time, or empty. Presenting an unverified ETA as an
  /// observed arrival could paint a station green ("on time") on nothing more
  /// than a guess.
  ///
  /// So actuals are trusted only once the train has reached the station. This is
  /// the same rule the spec already applies to fabricated delays (constraint
  /// D2): silence beats a confident wrong answer.
  bool get actualIsObserved =>
      this == StationLiveStage.passed || this == StationLiveStage.current;
}

/// One leg (arrival or departure) of a station's live status.
@immutable
class StationLegStatus {
  const StationLegStatus({
    this.scheduled,
    this.actual,
    this.rawDelay = '',
    this.isTerminusSentinel = false,
  });

  /// Scheduled clock time, anchored onto the journey's date. Null when RailKit
  /// gave a sentinel (`SRC`/`DSTN`) or an unparseable value.
  final DateTime? scheduled;

  /// Observed clock time. Null when unknown, unparseable, or a sentinel.
  ///
  /// Callers must still check [StationLiveStage.actualIsObserved] before showing
  /// this: a non-null value on an upcoming station is not evidence that anything
  /// happened.
  final DateTime? actual;

  /// RailKit's own delay label, verbatim — `"On Time"`, `"15 Min Late"`, or `""`.
  /// Kept as the fallback signal for when [actual] will not parse.
  final String rawDelay;

  /// The source value was `SRC` or `DSTN` rather than a time: the origin has no
  /// arrival and the terminus no departure. Distinct from "missing", because
  /// there is nothing to show rather than something we failed to read.
  final bool isTerminusSentinel;

  bool get hasScheduled => scheduled != null;
  bool get hasActual => actual != null;

  /// Minutes late, computed from the two clock times. Negative means early.
  /// Null when either side is missing.
  int? get delayMinutes {
    final s = scheduled, a = actual;
    if (s == null || a == null) return null;
    var diff = a.difference(s).inMinutes;
    // A journey's times are anchored to dates, so a legitimate overnight run
    // does not wrap. A near-24h gap is therefore a same-day comparison that
    // crossed midnight the wrong way, not a train a day late.
    if (diff < -12 * 60) diff += 24 * 60;
    if (diff > 12 * 60) diff -= 24 * 60;
    return diff;
  }

  /// Minutes late from RailKit's own label, used only when [delayMinutes] is
  /// null. `"15 Min Late"` -> 15, `"On Time"` -> 0.
  int? get delayMinutesFromLabel {
    final raw = rawDelay.trim();
    if (raw.isEmpty) return null;
    if (raw.toLowerCase().contains('on time')) return 0;
    final m = RegExp(r'(\d+)').firstMatch(raw);
    if (m == null) return null;
    return int.tryParse(m.group(1)!);
  }
}

/// Live arrival/departure status for a single station.
@immutable
class StationLiveStatus {
  const StationLiveStatus({
    required this.stationCode,
    required this.stage,
    this.arrival = const StationLegStatus(),
    this.departure = const StationLegStatus(),
    this.platform,
  });

  /// Not reported by RailKit — the caller matched nothing for this station and
  /// must render scheduled times only.
  const StationLiveStatus.unreported(this.stationCode)
      : stage = StationLiveStage.unreported,
        arrival = const StationLegStatus(),
        departure = const StationLegStatus(),
        platform = null;

  final String stationCode;
  final StationLiveStage stage;
  final StationLegStatus arrival;
  final StationLegStatus departure;

  /// Platform as reported live, which can differ from the static schedule.
  final String? platform;

  /// Whether a coloured actual-time row may be shown for this station at all.
  bool get canShowActual => stage.actualIsObserved;
}

/// How a station's timing should be coloured.
enum TimingVerdict {
  /// Ran to schedule, or early.
  onTime,

  /// Late by at least [kDelayThresholdMinutes].
  delayed,

  /// Not enough information to judge — render neutral, or nothing at all.
  unknown,
}

/// A station is called late only at or beyond this many minutes.
///
/// PRODUCT DECISION, not a derived value. Below five minutes is reporting noise:
/// station clock granularity and rounding routinely move a time by a minute or
/// two. Indian Railways' own punctuality tolerance is fifteen minutes, which was
/// rejected here as too lenient for a passenger-facing screen — showing green to
/// somebody standing on a platform beside a train fourteen minutes late would
/// read as a lie.
const int kDelayThresholdMinutes = 5;

/// Colour verdict for one leg.
///
/// Computed from the two clock times whenever both are available, so the colour
/// can never contradict the two numbers printed beside it. RailKit's own delay
/// label is consulted only when the times will not parse.
TimingVerdict verdictFor(StationLegStatus leg, {required bool actualObserved}) {
  if (!actualObserved) return TimingVerdict.unknown;

  final computed = leg.delayMinutes;
  if (computed != null) {
    return computed >= kDelayThresholdMinutes
        ? TimingVerdict.delayed
        : TimingVerdict.onTime;
  }

  final labelled = leg.delayMinutesFromLabel;
  if (labelled != null) {
    return labelled >= kDelayThresholdMinutes
        ? TimingVerdict.delayed
        : TimingVerdict.onTime;
  }

  return TimingVerdict.unknown;
}
