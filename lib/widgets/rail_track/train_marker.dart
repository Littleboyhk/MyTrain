import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/glass_theme.dart';
import '../pulse_ring.dart';
import 'rail_track_layout.dart';

/// The live train riding the track.
///
/// Sits in the gutter at the train's last reported position. The idle pulse is
/// the existing [PulseRing] treatment, moved here off the current-station pip:
/// the train is now the thing on screen that is actually alive, and two
/// competing pings a row apart read as noise.
class TrainMarker extends StatelessWidget {
  const TrainMarker({
    super.key,
    required this.stationName,
    this.arrived = false,
  });

  /// The station the train is reported at, used for the semantic label.
  final String stationName;

  /// Terminal state: the train has reached its destination, so the idle
  /// animation stops and the marker reads as final rather than in transit.
  final bool arrived;

  /// Diameter of the solid core carrying the icon. Bumped from 26 in step with
  /// the larger gutter and gauge, so the train still sits astride the rails.
  static const double coreSize = 30;

  /// Diameter of the pulse field. Matches the gutter width so the ring is never
  /// clipped by the column it sits in.
  static const double ringSize = RailMetrics.gutterWidth;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      // Requirement 11.2: the marker is the one piece of track geometry that
      // carries meaning, so it is the one piece that is not excluded.
      label: arrived
          ? 'Train has arrived at $stationName'
          : 'Train currently at $stationName',
      child: SizedBox(
        width: ringSize,
        height: ringSize,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            if (!arrived)
              const PulseRing(color: AppColors.accent, size: ringSize),
            _core(),
          ],
        ),
      ),
    );
  }

  Widget _core() {
    return Container(
      width: coreSize,
      height: coreSize,
      decoration: BoxDecoration(
        gradient: GlassTheme.accent,
        shape: BoxShape.circle,
        // A solid rim on arrival, a soft translucent one in transit: the state
        // is legible without relying on the pulse having been noticed, and
        // without relying on hue (Requirement 11.5).
        border: Border.all(
          color: arrived
              ? Colors.white
              : Colors.white.withValues(alpha: 0.28),
          width: arrived ? 2.5 : 1.5,
        ),
        boxShadow: AppColors.glow(
          AppColors.accent,
          opacity: arrived ? 0.55 : 0.75,
          blur: arrived ? 10 : 16,
        ),
      ),
      child: Center(
        child: Icon(
          arrived ? Icons.flag_rounded : Icons.train_rounded,
          size: 17,
          color: Colors.white,
        ),
      ),
    );
  }
}
