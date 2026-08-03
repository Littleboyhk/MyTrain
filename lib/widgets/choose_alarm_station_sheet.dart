import 'package:flutter/material.dart';

import '../models/station.dart';
import '../theme/app_theme.dart';
import '../theme/glass_theme.dart';
import '../utils/formatters.dart';
import '../utils/haptics.dart';

/// Shows the "Choose Alarm Station" bottom sheet list matching Screenshot 3.
/// Returns the selected [Station], or null if cancelled.
Future<Station?> showChooseAlarmStationSheet({
  required BuildContext context,
  required List<Station> stations,
  Station? currentSelected,
}) {
  return showModalBottomSheet<Station>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _ChooseAlarmStationSheet(
      stations: stations,
      currentSelected: currentSelected,
    ),
  );
}

class _ChooseAlarmStationSheet extends StatefulWidget {
  const _ChooseAlarmStationSheet({
    required this.stations,
    this.currentSelected,
  });

  final List<Station> stations;
  final Station? currentSelected;

  @override
  State<_ChooseAlarmStationSheet> createState() =>
      _ChooseAlarmStationSheetState();
}

class _ChooseAlarmStationSheetState extends State<_ChooseAlarmStationSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _filter = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final g = context.glass;
    final maxH = MediaQuery.of(context).size.height * 0.75;

    final filtered = widget.stations.where((s) {
      if (_filter.isEmpty) return true;
      final q = _filter.toLowerCase();
      return s.name.toLowerCase().contains(q) ||
          s.code.toLowerCase().contains(q);
    }).toList();

    return Container(
      constraints: BoxConstraints(maxHeight: maxH),
      decoration: BoxDecoration(
        color: g.isDark
            ? const Color(0xFF151824).withValues(alpha: 0.96)
            : Colors.white.withValues(alpha: 0.96),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.40),
            blurRadius: 30,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          const SizedBox(height: 10),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: g.border.withValues(alpha: 0.30),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: [
                const Icon(
                  Icons.notifications_active_outlined,
                  color: Colors.white,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Choose Alarm Station',
                    style: AppText.titleStrong.copyWith(
                      color: g.textPrimary,
                      fontSize: 18,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  color: g.textSecondary,
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // Search Box
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _filter = v),
              style: TextStyle(color: g.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search station name or code...',
                hintStyle: TextStyle(color: g.textMuted, fontSize: 14),
                prefixIcon: Icon(Icons.search_rounded,
                    color: g.textMuted, size: 20),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                filled: true,
                fillColor: g.isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.black.withValues(alpha: 0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          const SizedBox(height: 8),
          const Divider(height: 1),

          // Station List
          Expanded(
            child: ListView.separated(
              itemCount: filtered.length,
              separatorBuilder: (_, index) =>
                  Divider(height: 1, color: g.border.withValues(alpha: 0.12)),
              itemBuilder: (context, index) {
                final st = filtered[index];
                final isSelected = widget.currentSelected?.code == st.code;
                final arrTime = st.scheduledArrival ?? st.scheduledDeparture;

                return ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                  leading: const Icon(
                    Icons.location_on_outlined,
                    size: 20,
                    color: Colors.white70,
                  ),
                  title: Row(
                    children: [
                      // Station Code Badge Pill
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2C4A7C),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          st.code,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          st.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isSelected
                                ? const Color(0xFF4ADE80)
                                : g.textPrimary,
                            fontSize: 15,
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (arrTime != null)
                        Text(
                          Fmt.hhmm(arrTime),
                          style: TextStyle(
                            color: g.textSecondary,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 20,
                        color: g.textMuted,
                      ),
                    ],
                  ),
                  onTap: () {
                    Haptics.selection();
                    Navigator.pop(context, st);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
