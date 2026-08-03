import 'package:flutter/material.dart';

import '../models/berth_bay.dart';
import '../models/pnr_status.dart';
import '../theme/app_theme.dart';
import '../theme/glass_theme.dart';
import 'berth_layout.dart';

/// Shows where a confirmed passenger's berth sits within its bay.
///
/// TWO TIERS, BOTH HONESTLY SOURCED.
///
/// The bay diagram is drawn for SL and 3A only, and only when the modulo-8
/// derivation agrees with the berth type the provider actually sent.
/// [BerthBay.tryDerive] owns that decision and documents each reason; this widget
/// just renders whichever branch it returns.
///
/// Everything else — 2A, 1A, 3E, a contradicting berth type, a missing berth —
/// falls back to [SeatAllocation.berthLine], which restates the coach, berth and
/// berth type exactly as received and invents nothing. That fallback is not a
/// degraded mode; for classes whose numbering we could not source it is the most
/// this data honestly supports.
///
/// There is no full-coach grid for any class. A grid needs the coach's berth
/// total, which needs the rake generation, which no provider field states.
class BerthBayView extends StatelessWidget {
  const BerthBayView({
    super.key,
    this.travelClass,
    required this.allocation,
  });

  /// Null when the provider did not state the class — gated off, same as any
  /// unsupported class.
  final String? travelClass;
  final SeatAllocation allocation;

  @override
  Widget build(BuildContext context) {
    if (allocation.status != PassengerStatus.confirmed) {
      return const SizedBox.shrink();
    }

    final bay = BerthBay.tryDerive(
      travelClass: travelClass,
      allocation: allocation,
    );

    return bay == null
        ? _BerthText(allocation: allocation)
        : _BayGrid(bay: bay);
  }
}

/// The tier-1 card: every value the ticket states, and nothing else.
///
/// Used for every class the bay rule does not cover, and whenever it does cover
/// the class but the derivation disagreed with the ticket.
class _BerthText extends StatelessWidget {
  const _BerthText({required this.allocation});

  final SeatAllocation allocation;

  @override
  Widget build(BuildContext context) {
    final g = context.glass;

    return Row(
      children: [
        Icon(Icons.event_seat_rounded, size: 15, color: g.textMuted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            allocation.berthLine,
            style: AppText.label.copyWith(color: g.textSecondary, fontSize: 12.5),
          ),
        ),
      ],
    );
  }
}

/// The bay: two facing benches in one outline, then the side pair in its own.
///
/// SHARED LOOK. Uses [BerthOutlineBox] and [BerthCell], the same widgets the Coach
/// Position screen draws with, so the two berth views cannot drift into different
/// visual languages — they previously had.
///
/// The passenger's own berth is the one thing that still carries a fill, because
/// marking which bed is theirs is this diagram's entire purpose.
class _BayGrid extends StatelessWidget {
  const _BayGrid({required this.bay});

  final BerthBay bay;

  @override
  Widget build(BuildContext context) {
    final side = bay.slots
        .where((s) =>
            s.position == BerthPosition.sideLower ||
            s.position == BerthPosition.sideUpper)
        .toList();
    final main = bay.slots.where((s) => !side.contains(s)).toList();
    final per = (main.length / 2).ceil();
    final benches = <List<BerthSlot>>[
      if (per > 0) main.take(per).toList(),
      if (main.length > per) main.skip(per).toList(),
    ];

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: BerthOutlineBox(
              rows: [
                for (var b = 0; b < benches.length; b++)
                  Row(
                    children: [
                      for (final slot in benches[b])
                        Expanded(
                          child: BerthCell(
                            slot: slot,
                            mirrored: b.isOdd,
                            isPassenger: slot.isPassenger,
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
          if (side.isNotEmpty) ...[
            const SizedBox(width: 9),
            SizedBox(
              width: 78,
              child: BerthOutlineBox(
                rows: [
                  for (var i = 0; i < side.length; i++)
                    BerthCell(
                      slot: side[i],
                      mirrored: i.isOdd,
                      isPassenger: side[i].isPassenger,
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
