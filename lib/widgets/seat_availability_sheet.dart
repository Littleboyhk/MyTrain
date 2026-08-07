import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/railkit_mappers.dart';
import '../data/railkit_service.dart';
import '../models/seat_availability.dart';
import '../theme/glass_theme.dart';
import '../utils/haptics.dart';
import 'availability_results.dart';
import 'glass_container.dart';

/// Opens the seat-availability sheet for a train whose route and date are already
/// known — i.e. from a search result rather than from a blank lookup.
///
/// The full [SeatAvailabilityScreen] stays for the Home entry point, where the
/// user has no context and types a train number. This is the contextual form: the
/// query is already composed, so only class and quota need choosing.
///
/// Both render the same answer through [AvailabilityResultsBody].
Future<void> showSeatAvailabilitySheet(
  BuildContext context, {
  required String trainNumber,
  required String fromCode,
  required String toCode,
  required String date,
  String? trainName,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.60),
    builder: (_) => _SeatAvailabilitySheet(
      trainNumber: trainNumber,
      fromCode: fromCode,
      toCode: toCode,
      date: date,
      trainName: trainName,
    ),
  );
}

class _SeatAvailabilitySheet extends ConsumerStatefulWidget {
  const _SeatAvailabilitySheet({
    required this.trainNumber,
    required this.fromCode,
    required this.toCode,
    required this.date,
    this.trainName,
  });

  final String trainNumber;
  final String fromCode;
  final String toCode;

  /// ISO `YYYY-MM-DD`.
  final String date;
  final String? trainName;

  @override
  ConsumerState<_SeatAvailabilitySheet> createState() =>
      _SeatAvailabilitySheetState();
}

class _SeatAvailabilitySheetState
    extends ConsumerState<_SeatAvailabilitySheet> {
  /// Same option lists as the full screen, so the two cannot drift.
  static const _classes = ['SL', '3A', '2A', '1A', '3E', 'CC', '2S'];
  static const _quotas = ['GN', 'TQ', 'PT', 'LD', 'SS'];

  String _classCode = 'SL';
  String _quota = 'GN';
  late String _date;

  bool _loading = false;
  String? _error;
  SeatAvailability? _availability;

  @override
  void initState() {
    super.initState();
    _date = widget.date;
    // NO FETCH HERE. Opening the sheet is not a request to spend a RailKit call;
    // only the Check button is.
  }

  /// Changing a chip clears a stale answer rather than silently leaving the
  /// previous class's numbers on screen under the new chip.
  void _select(void Function() apply) {
    Haptics.selection();
    setState(() {
      apply();
      _availability = null;
      _error = null;
    });
  }

  Future<void> _check() async {
    Haptics.selection();
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await ref.read(railKitServiceProvider).getAvailability(
            trainNumber: widget.trainNumber,
            from: widget.fromCode,
            to: widget.toCode,
            date: _date,
            classCode: _classCode,
            quota: _quota,
          );
      final mapped = availabilityFromRailkit(
        res.data,
        widget.fromCode,
        widget.toCode,
        _classCode,
        _quota,
      );
      if (!mounted) return;
      setState(() {
        _availability = mapped;
        _loading = false;
        // A null map means the payload did not match the verified shape. Say that
        // rather than showing an empty list as though nothing were available.
        _error = mapped == null
            ? 'Could not read the availability response.'
            : null;
      });
    } on RailKitException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = availabilityErrorMessage(e);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not check availability. Please try again.';
        _loading = false;
      });
      debugPrint('[SeatAvailabilitySheet] unexpected: $e');
    }
  }

  Future<void> _pickDate() async {
    final parsed = DateTime.tryParse(_date) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: parsed,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      // Indian Railways' advance reservation period is 60 days for most quotas.
      lastDate: DateTime.now().add(const Duration(days: 120)),
    );
    if (picked == null) return;
    _select(() {
      _date = '${picked.year}-${picked.month.toString().padLeft(2, '0')}'
          '-${picked.day.toString().padLeft(2, '0')}';
    });
  }

  @override
  Widget build(BuildContext context) {
    final g = context.glass;

    return Padding(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 12,
        bottom: 12 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: GlassContainer(
        radius: 28,
        blurSigma: 24,
        strong: true,
        glow: true,
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: ConstrainedBox(
          // Caps the sheet so a six-date result scrolls inside it instead of
          // pushing the Check button off-screen.
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.82,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(g),
              const SizedBox(height: 14),
              _chipRow('Class', _classes, _classCode,
                  (v) => _select(() => _classCode = v)),
              const SizedBox(height: 10),
              _chipRow('Quota', _quotas, _quota,
                  (v) => _select(() => _quota = v)),
              const SizedBox(height: 12),
              _dateRow(g),
              const SizedBox(height: 14),
              _checkButton(g),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(top: 12),
                  child: AvailabilityResultsBody(
                    loading: _loading,
                    error: _error,
                    availability: _availability,
                    dense: true,
                    shrinkWrap: true,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(GlassTheme g) {
    final name = widget.trainName;
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: GlassTheme.accentViolet.withValues(alpha: 0.20),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.event_seat_rounded,
              size: 20, color: Colors.white),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Seat availability',
                style: TextStyle(
                  color: g.textPrimary,
                  fontSize: 16.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                // Names the exact query, so a result can never be read against
                // the wrong train.
                '${widget.trainNumber}${name == null || name.isEmpty ? '' : ' · $name'}'
                '\n${widget.fromCode} → ${widget.toCode}',
                style: TextStyle(
                    color: g.textSecondary, fontSize: 11.5, height: 1.35),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _chipRow(
    String label,
    List<String> options,
    String selected,
    void Function(String) onPick,
  ) {
    final g = context.glass;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: g.textMuted,
            fontSize: 9.5,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final o in options)
              _chip(o, o == selected, () => onPick(o)),
          ],
        ),
      ],
    );
  }

  Widget _chip(String text, bool active, VoidCallback onTap) {
    final g = context.glass;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          gradient: active ? GlassTheme.accent : null,
          color: active ? null : g.fill,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active
                ? Colors.white.withValues(alpha: 0.28)
                : g.border.withValues(alpha: 0.5),
          ),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: active ? Colors.white : g.textSecondary,
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _dateRow(GlassTheme g) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _pickDate,
      child: GlassContainer(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(Icons.calendar_today_rounded, size: 15, color: g.textSecondary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _date,
                style: TextStyle(
                  color: g.textPrimary,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text('Change',
                style: TextStyle(
                    color: GlassTheme.accentIndigo,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  Widget _checkButton(GlassTheme g) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _loading ? null : _check,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: _loading ? null : GlassTheme.accent,
          color: _loading ? g.fillStrong : null,
          borderRadius: BorderRadius.circular(999),
          boxShadow: _loading
              ? null
              : [
                  BoxShadow(
                    color: GlassTheme.accentIndigo.withValues(alpha: 0.34),
                    blurRadius: 16,
                    spreadRadius: -3,
                  ),
                ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _loading
                  ? Icons.hourglass_top_rounded
                  : Icons.event_seat_rounded,
              size: 17,
              color: _loading ? g.textSecondary : Colors.white,
            ),
            const SizedBox(width: 8),
            Text(
              _loading ? 'Checking…' : 'Check availability',
              style: TextStyle(
                color: _loading ? g.textSecondary : Colors.white,
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
