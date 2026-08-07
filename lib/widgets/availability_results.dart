import 'package:flutter/material.dart';

import '../data/railkit_service.dart';
import '../models/seat_availability.dart';
import '../theme/app_colors.dart';
import '../theme/glass_theme.dart';
import 'glass_container.dart';

/// Shared rendering for a seat-availability result.
///
/// ONE DEFINITION, TWO CALLERS: the full screen (reached from Home, where the
/// user types a train number) and the bottom sheet (reached from a results card,
/// where train/route/date are already known). They differ only in how the query
/// is composed — the answer is displayed identically.
///
/// WHY THIS IS SHARED RATHER THAN COPIED. The status→colour mapping is the exact
/// place a silent bug lived: `'WAITLIST'` was classified by searching for the
/// substring `'WL'`, which does not occur in it, so every waitlisted date
/// rendered as "unknown" grey. A second copy of that logic is a second place for
/// it to be wrong while the first looks fine.

/// Status → colour. Green available, amber RAC, red waitlist/regret, neutral
/// unknown.
///
/// Exhaustive switch with no `default:` on purpose: a new [AvailabilityStatus]
/// becomes a compile error rather than silently rendering grey.
Color availabilityStatusColor(AvailabilityStatus type) {
  switch (type) {
    case AvailabilityStatus.available:
      return AppColors.onTime;
    case AvailabilityStatus.rac:
      return Colors.amber;
    case AvailabilityStatus.waitlist:
      return AppColors.delayed;
    case AvailabilityStatus.regret:
      return Colors.red;
    case AvailabilityStatus.unknown:
      // Deliberately not green: an unrecognised status is not good news.
      return AppColors.textMuted;
  }
}

/// User-facing text for a RailKit failure.
///
/// Shared so both callers say the same thing, and so neither falls back to
/// `e.toString()` — which used to print `RailKitException(validation):` on screen
/// and, for an IRCTC outage, told the user their input was wrong.
String availabilityErrorMessage(RailKitException e) {
  switch (e.code) {
    case RailKitErrorCode.upstreamUnavailable:
      // Not the user's fault, and retrying genuinely may work: the booking host
      // is down or inside its nightly maintenance window.
      return 'The railway booking system is not responding right now.\n'
          'Please try again in a few minutes.\n\n'
          '(${e.message})';
    case RailKitErrorCode.quotaExceeded:
      return 'The monthly request budget for live data has been reached.\n'
          'Please check back later.';
    case RailKitErrorCode.validation:
      // Actionable and specific — the upstream's own wording is the most useful
      // thing to show, e.g. "Date outside Tatkal ARP".
      return e.message;
    case RailKitErrorCode.functionNotDeployed:
    case RailKitErrorCode.notConfigured:
    case RailKitErrorCode.notConfiguredLocally:
      return 'Seat availability is not available on this build.';
    case RailKitErrorCode.invalidKey:
    case RailKitErrorCode.inactiveKey:
    case RailKitErrorCode.unknown:
      return 'Could not check availability. Please try again shortly.';
  }
}

/// One date's row: date, confirmation chance, raw booking string, status chip.
class AvailabilityDayRow extends StatelessWidget {
  const AvailabilityDayRow({super.key, required this.day, this.dense = false});

  final AvailabilityDay day;

  /// Tighter padding and type for the bottom sheet, where vertical space is
  /// scarcer than on the full screen.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final g = context.glass;
    final col = availabilityStatusColor(day.statusType);

    return Padding(
      padding: EdgeInsets.only(bottom: dense ? 8 : 12),
      child: GlassContainer(
        padding: EdgeInsets.all(dense ? 12 : 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    day.date,
                    style: TextStyle(
                      color: g.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: dense ? 14 : 15,
                    ),
                  ),
                  // NO PER-DAY FARE. Fare is one breakdown for the whole query
                  // (see [AvailabilityFare]); printing it on every row implied it
                  // varied by date, and the old code read a field that does not
                  // exist, so it always showed ₹0.
                  if (day.prediction.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      day.prediction,
                      style: TextStyle(
                        color: g.textSecondary,
                        fontSize: dense ? 12 : 13,
                      ),
                    ),
                  ],
                  if (day.rawStatus.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      day.rawStatus,
                      style: TextStyle(
                        color: g.textMuted,
                        fontSize: dense ? 10.5 : 11.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: dense ? 10 : 12,
                vertical: dense ? 5 : 6,
              ),
              decoration: BoxDecoration(
                color: col.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: col.withValues(alpha: 0.4)),
              ),
              child: Text(
                // "WL 15" beats "WAITLIST": the queue position is the fact the
                // user came for.
                day.displayStatus,
                style: TextStyle(
                  color: col,
                  fontWeight: FontWeight.bold,
                  fontSize: dense ? 13 : 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The single fare breakdown for the query.
///
/// Rendered once, above the dates, because that is what the payload actually
/// describes — `data.fare` is not per date.
class AvailabilityFareSummary extends StatelessWidget {
  const AvailabilityFareSummary({super.key, required this.fare});

  final AvailabilityFare fare;

  @override
  Widget build(BuildContext context) {
    final g = context.glass;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassContainer(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(Icons.confirmation_number_outlined,
                size: 16, color: g.textSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Fare for this class',
                style: TextStyle(color: g.textSecondary, fontSize: 12.5),
              ),
            ),
            Text(
              '₹${fare.totalFare}',
              style: TextStyle(
                color: g.textPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Loading / error / not-yet-asked / nothing-published / results.
///
/// The four non-result states are distinct on purpose. "Tap Check" and "nothing
/// published" were one message before, so a screen that had never fetched looked
/// identical to a train with no availability.
class AvailabilityResultsBody extends StatelessWidget {
  const AvailabilityResultsBody({
    super.key,
    required this.loading,
    required this.error,
    required this.availability,
    this.dense = false,
    this.shrinkWrap = false,
  });

  final bool loading;
  final String? error;
  final SeatAvailability? availability;
  final bool dense;

  /// True inside a bottom sheet, where the list sits in a Column rather than
  /// filling a Scaffold.
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) {
    final g = context.glass;

    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
        child: Center(
          child: Text(
            error!,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.delayed, fontSize: 13.5),
          ),
        ),
      );
    }

    final a = availability;
    if (a == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 26),
        child: Center(
          child: Text(
            'Pick a class and quota, then tap Check.',
            textAlign: TextAlign.center,
            style: TextStyle(color: g.textSecondary, fontSize: 13.5),
          ),
        ),
      );
    }

    if (a.days.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 26),
        child: Center(
          child: Text(
            'No availability published for this train, class and quota.',
            textAlign: TextAlign.center,
            style: TextStyle(color: g.textSecondary, fontSize: 13.5),
          ),
        ),
      );
    }

    final rows = <Widget>[
      if (a.fare != null) AvailabilityFareSummary(fare: a.fare!),
      for (final day in a.days) AvailabilityDayRow(day: day, dense: dense),
      // The upstream is a booking system, not a guarantee, and the prediction is
      // explicitly a chance. Saying so once beats implying certainty per row.
      Padding(
        padding: const EdgeInsets.only(top: 2, bottom: 6),
        child: Text(
          'Live from the railway booking system · predictions are estimates',
          textAlign: TextAlign.center,
          style: TextStyle(color: g.textMuted, fontSize: 10.5),
        ),
      ),
    ];

    if (shrinkWrap) {
      return Column(mainAxisSize: MainAxisSize.min, children: rows);
    }
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: rows,
    );
  }
}

/// Header line naming what was queried, so a result can never be read against
/// the wrong train.
class AvailabilityQueryHeader extends StatelessWidget {
  const AvailabilityQueryHeader({super.key, required this.availability});

  final SeatAvailability availability;

  @override
  Widget build(BuildContext context) {
    final g = context.glass;
    final a = availability;
    final name = a.trainName.isEmpty ? '' : ' · ${a.trainName}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        '${a.trainNumber}$name\n'
        '${a.fromCode} → ${a.toCode} · ${a.classCode} · ${a.quota}',
        style: TextStyle(
          color: g.textSecondary,
          fontSize: 11.5,
          height: 1.4,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
