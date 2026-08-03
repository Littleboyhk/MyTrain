import 'package:flutter/material.dart';

import '../models/berth_bay.dart';
import '../theme/app_theme.dart';
import '../theme/glass_theme.dart';

/// Shared berth presentation: one hairline outline per group, bare text inside.
///
/// WHY THIS IS SHARED. Berths are drawn in two places — the Coach Position screen's
/// full-coach layout and the PNR bay view — and they had drifted into two different
/// visual languages. This file is the single source for both, so a change to the
/// look lands in both and neither can quietly diverge. The same reasoning already
/// applies to [BerthBay.positionOf], which both screens call rather than
/// reimplementing the mod-8 rule.

/// Short form of a berth position for a tile label.
///
/// Presentation only — [BerthPosition.label] stays the canonical wording. `Side
/// Lower` is abbreviated because the full phrase forces a second line at tile
/// width, and a wrapped label reads as two berths.
String berthLabel(BerthPosition p) => switch (p) {
      BerthPosition.lower => 'LOWER',
      BerthPosition.middle => 'MIDDLE',
      BerthPosition.upper => 'UPPER',
      BerthPosition.sideLower => 'S.LOWER',
      BerthPosition.sideUpper => 'S.UPPER',
    };

/// One outlined box holding several rows, split by full-width dividers.
///
/// The ONLY visible border in a berth group. Individual berths carry no box, border
/// or shadow of their own — they are text inside this outline, which is what stops
/// a coach reading as a wall of cards.
///
/// The divider is a child of the box rather than a margin between two boxes, so a
/// bay reads as one continuous outline split by a line. Padding sits on each row
/// instead of on the box, which is what lets the divider run edge to edge.
///
/// [rows] length is whatever the caller has: two benches for a bay, two side
/// berths for the side column, any other count renders the same way. Nothing here
/// assumes a bay size.
class BerthOutlineBox extends StatelessWidget {
  const BerthOutlineBox({super.key, required this.rows});

  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final g = context.glass;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: g.border.withValues(alpha: 0.18), width: 1),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              Container(height: 1, color: g.border.withValues(alpha: 0.14)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
              child: rows[i],
            ),
          ],
        ],
      ),
    );
  }
}

/// One berth: number and position stacked, order flipped when [mirrored].
///
/// [mirrored] puts the label on top, which is what makes the opposite bench read as
/// facing this one across the compartment.
///
/// [isPassenger] is the ONE case that gets a fill. On the PNR bay view this marks
/// which bed is actually yours, so it has to survive the otherwise fill-free
/// treatment — a berth diagram whose whole purpose is "you are here" cannot leave
/// that unmarked. It is a tint plus a rim rather than a glow, because at this size a
/// shadow offset renders as a grey bar beneath the tile rather than a soft edge.
class BerthCell extends StatelessWidget {
  const BerthCell({
    super.key,
    required this.slot,
    this.mirrored = false,
    this.isPassenger = false,
  });

  final BerthSlot slot;
  final bool mirrored;
  final bool isPassenger;

  @override
  Widget build(BuildContext context) {
    final g = context.glass;
    final mine = isPassenger;

    final number = Text(
      '${slot.number}',
      maxLines: 1,
      style: AppText.titleStrong.copyWith(
        color: g.textPrimary,
        fontSize: 16,
        fontWeight: FontWeight.w800,
      ),
    );
    final label = Text(
      berthLabel(slot.position),
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.clip,
      style: AppText.label.copyWith(
        // textSecondary on the passenger's own berth: the tint behind it lifts the
        // background, and muted grey loses too much contrast against it.
        color: mine ? g.textSecondary : g.textMuted,
        fontSize: 8.5,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
      ),
    );

    final stack = Column(
      mainAxisSize: MainAxisSize.min,
      children: mirrored
          ? [label, const SizedBox(height: 2), number]
          : [number, const SizedBox(height: 2), label],
    );

    return Semantics(
      label: mine
          ? 'Your berth, ${slot.number}, ${slot.position.label}'
          : 'Berth ${slot.number}, ${slot.position.label}',
      child: mine
          ? Container(
              decoration: BoxDecoration(
                color: GlassTheme.accentIndigo.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: GlassTheme.accentIndigo.withValues(alpha: 0.85),
                  width: 1.5,
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
              child: stack,
            )
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
              child: stack,
            ),
    );
  }
}
