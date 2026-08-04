import 'package:flutter/material.dart';

import '../models/split_journey_combo.dart';
import '../models/train_summary.dart';
import '../theme/app_theme.dart';
import '../theme/glass_theme.dart';
import 'glass_container.dart';

/// Card rendering a 2-leg split journey option as two distinct ticket cards
/// connected by a transfer node, with layover buffer color-coding and warnings.
class SplitJourneyCard extends StatelessWidget {
  const SplitJourneyCard({
    super.key,
    required this.combo,
    required this.onTap,
  });

  final SplitJourneyCombo combo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final g = context.glass;
    final leg1 = combo.leg1;
    final leg2 = combo.leg2;

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: GestureDetector(
        onTap: onTap,
        child: GlassContainer(
          radius: 22,
          blurSigma: 20,
          strong: true,
          glow: true,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Header Row: Split Journey Badge & Color-coded Layover Buffer Pill
              Row(
                children: [
                  _headerBadge(context),
                  const Spacer(),
                  _bufferBadge(context, combo),
                ],
              ),
              const SizedBox(height: 14),

              // LEG 1 TICKET CARD
              _ticketCard(
                context,
                legNumber: 1,
                leg: leg1,
                fromCode: leg1.fromCode,
                toCode: combo.junctionCode,
                accentColor: GlassTheme.accentViolet,
              ),

              // CONNECTING TRANSFER BRIDGE (Dotted line + Junction Transfer Node)
              _connectionBridge(context, combo),

              // LEG 2 TICKET CARD
              _ticketCard(
                context,
                legNumber: 2,
                leg: leg2,
                fromCode: combo.junctionCode,
                toCode: leg2.toCode,
                accentColor: GlassTheme.accentIndigo,
              ),

              // TIGHT-LAYOVER WARNING BANNER (Only when layover < 60 min)
              if (combo.isTightLayoverWarning) ...[
                const SizedBox(height: 12),
                _tightLayoverWarning(context, combo),
              ],

              const SizedBox(height: 12),
              const Divider(height: 1, color: Colors.white12),
              const SizedBox(height: 10),

              // PER-COMBO FOOTER
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.sticky_note_2_outlined,
                    size: 13,
                    color: g.textMuted,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Book both legs as separate PNRs. Keep both tickets handy during travel. Refund/cancellation rules apply independently to each ticket.',
                      style: AppText.label.copyWith(
                        color: g.textMuted,
                        fontSize: 11,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Top Left Header Badge
  Widget _headerBadge(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: GlassTheme.accentViolet.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: GlassTheme.accentViolet.withValues(alpha: 0.40),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.alt_route_rounded,
            size: 13,
            color: GlassTheme.accentViolet,
          ),
          const SizedBox(width: 5),
          Text(
            'SPLIT JOURNEY',
            style: TextStyle(
              color: GlassTheme.accentViolet,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }

  /// Buffer Safety Color-Coded Badge
  /// - 60+ min: Green (Safe)
  /// - 30-60 min: Amber (Moderate)
  /// - <30 min: Red (Tight)
  Widget _bufferBadge(BuildContext context, SplitJourneyCombo combo) {
    final (Color bg, Color border, Color text, String iconStr, String labelText) =
        switch (combo.bufferSafety) {
      BufferSafetyLevel.safe => (
          const Color(0xFF1B5E20).withValues(alpha: 0.25),
          const Color(0xFF4CAF50),
          const Color(0xFF81C784),
          '🟢',
          '${combo.layoverFormatted} Buffer (Safe)'
        ),
      BufferSafetyLevel.moderate => (
          const Color(0xFFE65100).withValues(alpha: 0.25),
          const Color(0xFFFF9800),
          const Color(0xFFFFB74D),
          '🟠',
          '${combo.layoverFormatted} Buffer'
        ),
      BufferSafetyLevel.tight => (
          const Color(0xFFB71C1C).withValues(alpha: 0.25),
          const Color(0xFFF44336),
          const Color(0xFFE57373),
          '🔴',
          '${combo.layoverFormatted} Buffer (Tight)'
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(iconStr, style: const TextStyle(fontSize: 10)),
          const SizedBox(width: 5),
          Text(
            labelText,
            style: TextStyle(
              color: text,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  /// Ticket-style Box for Leg 1 or Leg 2
  Widget _ticketCard(
    BuildContext context, {
    required int legNumber,
    required TrainSummary leg,
    required String fromCode,
    required String toCode,
    required Color accentColor,
  }) {
    final g = context.glass;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: g.isDark
            ? Colors.white.withValues(alpha: 0.05)
            : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.35),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'LEG $legNumber',
                  style: TextStyle(
                    color: accentColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${leg.number} ${leg.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.titleStrong.copyWith(
                    color: g.textPrimary,
                    fontSize: 13.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                fromCode,
                style: TextStyle(
                  color: g.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                leg.departure ?? '--:--',
                style: TextStyle(
                  color: GlassTheme.accentViolet,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      Expanded(child: Divider(color: Colors.white24, height: 1)),
                      Icon(Icons.arrow_forward_rounded,
                          size: 13, color: Colors.white38),
                    ],
                  ),
                ),
              ),
              Text(
                toCode,
                style: TextStyle(
                  color: g.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                leg.arrival ?? '--:--',
                style: TextStyle(
                  color: GlassTheme.accentIndigo,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Transfer Bridge Connection with Junction Station Label
  Widget _connectionBridge(BuildContext context, SplitJourneyCombo combo) {
    final g = context.glass;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const SizedBox(width: 24),
          // Dotted connector
          SizedBox(
            height: 28,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(
                3,
                (_) => Container(
                  width: 3,
                  height: 3,
                  decoration: const BoxDecoration(
                    color: GlassTheme.accentIndigo,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Connection Junction Pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: g.isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : const Color(0xFFE2E8F0),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: g.border.withValues(alpha: 0.20)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.swap_horizontal_circle_rounded,
                  size: 14,
                  color: GlassTheme.accentIndigo,
                ),
                const SizedBox(width: 6),
                Text(
                  'Change trains at ${combo.junctionName} (${combo.junctionCode})',
                  style: AppText.label.copyWith(
                    color: g.textPrimary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (combo.isNextDayLeg2) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF6C00),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'Next Day',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Tight-Layover Warning Banner (< 60 min buffer)
  Widget _tightLayoverWarning(BuildContext context, SplitJourneyCombo combo) {
    final g = context.glass;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0).withValues(alpha: g.isDark ? 0.12 : 0.9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFFFB74D).withValues(alpha: 0.6),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('🕐', style: TextStyle(fontSize: 14)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Only ${combo.layoverMinutes} min to change trains at ${combo.junctionName}. Delays are common — consider a combo with more buffer if this is a busy route.',
              style: AppText.label.copyWith(
                color: g.isDark ? const Color(0xFFFFB74D) : const Color(0xFFE65100),
                fontSize: 11.5,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
