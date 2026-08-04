import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/glass_theme.dart';
import 'glass_container.dart';

/// Main disclaimer banner & expandable info for Split Journey Finder results.
class SplitJourneyDisclaimer extends StatefulWidget {
  const SplitJourneyDisclaimer({
    super.key,
    required this.tightCount,
    required this.showTightConnections,
    required this.onToggleTightConnections,
  });

  final int tightCount;
  final bool showTightConnections;
  final ValueChanged<bool> onToggleTightConnections;

  @override
  State<SplitJourneyDisclaimer> createState() => _SplitJourneyDisclaimerState();
}

class _SplitJourneyDisclaimerState extends State<SplitJourneyDisclaimer> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final g = context.glass;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Main Warning Banner
          GlassContainer(
            radius: 18,
            blurSigma: 16,
            strong: true,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '⚠️',
                      style: TextStyle(fontSize: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        "This is 2 separate tickets, not one journey — You'll book each leg separately and must get off, collect your luggage, and board the next train yourself. Railways does not guarantee your connection — if Leg 1 is late, you may miss Leg 2 with no refund protection on that ticket.",
                        style: AppText.label.copyWith(
                          color: g.isDark ? const Color(0xFFFFD54F) : const Color(0xFFB78103),
                          fontSize: 12.5,
                          height: 1.45,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(height: 1, color: Colors.white12),
                const SizedBox(height: 8),

                // Expandable "Why two tickets?" Section
                InkWell(
                  onTap: () => setState(() => _isExpanded = !_isExpanded),
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                    child: Row(
                      children: [
                        Icon(
                          Icons.help_outline_rounded,
                          size: 15,
                          color: GlassTheme.accentIndigo,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Why two tickets?',
                          style: AppText.label.copyWith(
                            color: GlassTheme.accentIndigo,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        Icon(
                          _isExpanded
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          size: 18,
                          color: GlassTheme.accentIndigo,
                        ),
                      ],
                    ),
                  ),
                ),
                AnimatedCrossFade(
                  firstChild: const SizedBox.shrink(),
                  secondChild: Padding(
                    padding: const EdgeInsets.only(top: 8, left: 4, right: 4),
                    child: Text(
                      "Indian Railways allows 'break journey' bookings as separate tickets when no single ticket is available for your full route. This is a common workaround — just remember each leg is booked and cancelled independently.",
                      style: AppText.label.copyWith(
                        color: g.textSecondary,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ),
                  crossFadeState: _isExpanded
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  duration: const Duration(milliseconds: 250),
                ),
              ],
            ),
          ),

          if (widget.tightCount > 0) ...[
            const SizedBox(height: 10),
            // Tight Connections Toggle Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: g.isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: g.border.withValues(alpha: 0.20),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.timer_outlined,
                    size: 16,
                    color: widget.showTightConnections
                        ? const Color(0xFFEF5350)
                        : g.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.showTightConnections
                          ? 'Showing tight connections (< 20 min)'
                          : 'Hide tight connections (${widget.tightCount} combo${widget.tightCount > 1 ? 's' : ''} < 20 min)',
                      style: AppText.label.copyWith(
                        color: g.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Transform.scale(
                    scale: 0.8,
                    child: Switch.adaptive(
                      value: widget.showTightConnections,
                      activeColor: const Color(0xFFEF5350),
                      onChanged: widget.onToggleTightConnections,
                    ),
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
