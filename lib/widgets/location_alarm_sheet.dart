import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/destination_alarm_service.dart';
import '../models/station.dart';
import '../theme/app_theme.dart';
import '../theme/glass_theme.dart';
import '../utils/haptics.dart';
import 'alarm_warning_dialog.dart';
import 'choose_alarm_station_sheet.dart';

/// Shows the "Location Alarms" sheet matching Screenshots 1 & 2.
Future<void> showLocationAlarmSheet({
  required BuildContext context,
  required WidgetRef ref,
  required List<Station> stations,
  required Station defaultStation,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _LocationAlarmSheet(
      ref: ref,
      stations: stations,
      defaultStation: defaultStation,
    ),
  );
}

class _LocationAlarmSheet extends StatefulWidget {
  const _LocationAlarmSheet({
    required this.ref,
    required this.stations,
    required this.defaultStation,
  });

  final WidgetRef ref;
  final List<Station> stations;
  final Station defaultStation;

  @override
  State<_LocationAlarmSheet> createState() => _LocationAlarmSheetState();
}

class _LocationAlarmSheetState extends State<_LocationAlarmSheet> {
  late Station _selectedStation;
  // Discrete time offsets in minutes: [0 (At), 5, 10, 15, 20, 30, 45, 60]
  static const List<int> _offsetValues = [0, 5, 10, 15, 20, 30, 45, 60];
  int _sliderIndex = 2; // Default to index 2 -> 10 minutes before

  @override
  void initState() {
    super.initState();
    final activeAlarm = widget.ref.read(destinationAlarmProvider);
    if (activeAlarm.state == DestinationAlarmState.armed &&
        activeAlarm.stationCode != null) {
      final match = widget.stations.firstWhere(
        (s) => s.code == activeAlarm.stationCode,
        orElse: () => widget.defaultStation,
      );
      _selectedStation = match;
      final idx = _offsetValues.indexOf(activeAlarm.minutesBefore);
      if (idx != -1) _sliderIndex = idx;
    } else {
      _selectedStation = widget.defaultStation;
    }
  }

  int get _currentMinutes => _offsetValues[_sliderIndex];

  String get _whenLabel {
    if (_currentMinutes == 0) return 'At';
    return '$_currentMinutes minutes before';
  }

  @override
  Widget build(BuildContext context) {
    final g = context.glass;

    return Container(
      margin: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: BoxDecoration(
        color: g.isDark
            ? const Color(0xFF141722).withValues(alpha: 0.97)
            : Colors.white.withValues(alpha: 0.97),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 32,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.notifications_active_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Location Alarms',
                    style: AppText.titleStrong.copyWith(
                      color: g.textPrimary,
                      fontSize: 18.5,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.more_vert_rounded, size: 20),
                  color: g.textSecondary,
                  onPressed: () {},
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  color: g.textSecondary,
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // Main Location Alarm Card
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: Container(
              decoration: BoxDecoration(
                color: g.isDark
                    ? const Color(0xFF1F2335)
                    : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: g.border.withValues(alpha: 0.20),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // WHEN SECTION
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.access_time_rounded,
                              size: 16,
                              color: g.textMuted,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'When',
                              style: TextStyle(
                                color: g.textMuted,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _whenLabel,
                          style: TextStyle(
                            color: g.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 12),
                        SliderTheme(
                          data: SliderThemeData(
                            activeTrackColor: const Color(0xFF60A5FA),
                            inactiveTrackColor: g.isDark
                                ? Colors.white.withValues(alpha: 0.15)
                                : Colors.black.withValues(alpha: 0.15),
                            thumbColor: const Color(0xFF93C5FD),
                            overlayColor: const Color(0xFF60A5FA).withValues(alpha: 0.2),
                            trackHeight: 3.5,
                            thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 8),
                          ),
                          child: Slider(
                            value: _sliderIndex.toDouble(),
                            min: 0,
                            max: (_offsetValues.length - 1).toDouble(),
                            divisions: _offsetValues.length - 1,
                            onChanged: (val) {
                              Haptics.selection();
                              setState(() => _sliderIndex = val.round());
                            },
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Dotted Divider Line
                  CustomPaint(
                    size: const Size(double.infinity, 1),
                    painter: _DottedLinePainter(
                      color: g.border.withValues(alpha: 0.30),
                    ),
                  ),

                  // WHERE SECTION
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _pickStation,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.location_on_outlined,
                                size: 16,
                                color: g.textMuted,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Where',
                                style: TextStyle(
                                  color: g.textMuted,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              // Station Code Badge Pill
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF2C4A7C),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Text(
                                  _selectedStation.code,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _selectedStation.name,
                                  style: TextStyle(
                                    color: g.textPrimary,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.cancel_outlined,
                                size: 18,
                                color: g.textMuted,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Set Destination Alarm Green Button
                  GestureDetector(
                    onTap: _onSetAlarmPressed,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: const BoxDecoration(
                        color: Color(0xFF1E8E3E), // WhereIsMyTrain Green
                        borderRadius:
                            BorderRadius.vertical(bottom: Radius.circular(16)),
                      ),
                      child: const Text(
                        'Set Destination Alarm',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickStation() async {
    Haptics.tap();
    final chosen = await showChooseAlarmStationSheet(
      context: context,
      stations: widget.stations,
      currentSelected: _selectedStation,
    );
    if (chosen != null && mounted) {
      setState(() => _selectedStation = chosen);
    }
  }

  Future<void> _onSetAlarmPressed() async {
    Haptics.tap();
    final confirmed = await showAlarmWarningDialog(context);
    if (confirmed && mounted) {
      widget.ref.read(destinationAlarmProvider.notifier).armAlarm(
            stationCode: _selectedStation.code,
            stationName: _selectedStation.name,
            latitude: _selectedStation.location?.latitude,
            longitude: _selectedStation.location?.longitude,
            proximityThresholdKm: _currentMinutes.toDouble(),
            minutesBefore: _currentMinutes,
          );
      Navigator.pop(context);
    }
  }
}

class _DottedLinePainter extends CustomPainter {
  const _DottedLinePainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    const dashWidth = 4.0;
    const dashSpace = 3.0;
    double startX = 0;
    while (startX < size.width) {
      canvas.drawLine(Offset(startX, 0), Offset(startX + dashWidth, 0), paint);
      startX += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant _DottedLinePainter oldDelegate) =>
      color != oldDelegate.color;
}
