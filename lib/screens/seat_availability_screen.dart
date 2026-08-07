import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/railkit_mappers.dart';
import '../data/railkit_service.dart';
import '../models/seat_availability.dart';
import '../theme/app_colors.dart';
import '../theme/glass_theme.dart';
import '../widgets/availability_results.dart';
import '../widgets/glass_surface.dart';
import '../widgets/mesh_background.dart';

class SeatAvailabilityScreen extends ConsumerStatefulWidget {
  const SeatAvailabilityScreen({
    super.key,
    this.initialTrainNumber,
    this.initialFrom,
    this.initialTo,
    this.initialDate,
  });

  /// Train to check, when the caller already knows it — e.g. opened from a
  /// results card. Null leaves the field empty for the user to fill; it is NOT
  /// defaulted to a real train number, because a wrong-but-plausible answer is
  /// worse than an empty field.
  final String? initialTrainNumber;

  final String? initialFrom;
  final String? initialTo;
  final String? initialDate;

  @override
  ConsumerState<SeatAvailabilityScreen> createState() => _SeatAvailabilityScreenState();
}

class _SeatAvailabilityScreenState extends ConsumerState<SeatAvailabilityScreen> {
  late final TextEditingController _trainCtrl;
  late final TextEditingController _fromCtrl;
  late final TextEditingController _toCtrl;
  late String _date;
  String _classCode = 'SL';
  String _quota = 'GN';
  bool _loading = false;
  String? _error;
  SeatAvailability? _availability;

  final _classes = ['SL', '3A', '2A', '1A', '3E', 'CC', '2S'];
  final _quotas = ['GN', 'TQ', 'PT', 'LD', 'SS'];

  @override
  void initState() {
    super.initState();
    // No hardcoded '12496'. That default meant opening this screen without a
    // train silently queried a real, unrelated service and presented the result
    // as the user's.
    _trainCtrl = TextEditingController(text: widget.initialTrainNumber ?? '');
    _fromCtrl = TextEditingController(text: widget.initialFrom ?? '');
    _toCtrl = TextEditingController(text: widget.initialTo ?? '');
    final now = DateTime.now();
    _date = widget.initialDate ??
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    // DELIBERATELY NO _fetch() HERE. Availability is fetched only when the user
    // taps Check: every call is a real RailKit request, and opening a screen is
    // not a request to spend one. Previously this fetched on open AND again on
    // every class/quota dropdown change, so browsing four classes cost five
    // requests before the user had asked for anything.
  }

  @override
  void dispose() {
    _trainCtrl.dispose();
    _fromCtrl.dispose();
    _toCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    final train = _trainCtrl.text.trim();
    final from = _fromCtrl.text.trim().toUpperCase();
    final to = _toCtrl.text.trim().toUpperCase();

    // Tell the user what is missing rather than returning silently, which left
    // the Check button looking broken.
    if (train.isEmpty || from.isEmpty || to.isEmpty) {
      setState(() => _error = 'Enter a train number and both station codes.');
      return;
    }
    // Mirrors the server's TRAIN_NO check, so an obviously bad number costs no
    // request at all.
    if (!RegExp(r'^\d{3,6}$').hasMatch(train)) {
      setState(() => _error = 'A train number is 3–6 digits.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final service = ref.read(railKitServiceProvider);
      final res = await service.getAvailability(
        trainNumber: train,
        from: from,
        to: to,
        date: _date,
        classCode: _classCode,
        quota: _quota,
      );
      final data = availabilityFromRailkit(res.data, from, to, _classCode, _quota);
      if (mounted) {
        setState(() {
          _availability = data;
          _loading = false;
        });
      }
    } on RailKitException catch (e) {
      if (mounted) {
        setState(() {
          _error = availabilityErrorMessage(e);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not check availability. Please try again.';
          _loading = false;
        });
      }
      debugPrint('[SeatAvailability] unexpected: $e');
    }
  }

  // _statusColor and the error-message mapping now live in
  // widgets/availability_results.dart, shared with the bottom sheet. Keeping
  // private copies here is what let the 'WAITLIST' colour bug exist in one place
  // while the other looked correct.

  @override
  Widget build(BuildContext context) {
    final g = context.glass;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          const Positioned.fill(child: MeshBackground()),
          SafeArea(
            child: Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(Icons.arrow_back_ios_new_rounded, color: g.textPrimary),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Seat Availability',
                        style: TextStyle(color: g.textPrimary, fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),

                // Inputs
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: GlassSurface(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        TextField(
                          controller: _trainCtrl,
                          style: TextStyle(color: g.textPrimary),
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Train Number (e.g. 12496, 16332)',
                            labelStyle: TextStyle(color: g.textSecondary),
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _fromCtrl,
                                style: TextStyle(color: g.textPrimary),
                                textCapitalization: TextCapitalization.characters,
                                decoration: InputDecoration(
                                  labelText: 'From Station',
                                  labelStyle: TextStyle(color: g.textSecondary),
                                  border: const OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Icon(Icons.swap_horiz_rounded, color: AppColors.accent),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _toCtrl,
                                style: TextStyle(color: g.textPrimary),
                                textCapitalization: TextCapitalization.characters,
                                decoration: InputDecoration(
                                  labelText: 'To Station',
                                  labelStyle: TextStyle(color: g.textSecondary),
                                  border: const OutlineInputBorder(),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: _classCode,
                                dropdownColor: AppColors.surfaceElevated,
                                style: TextStyle(color: g.textPrimary),
                                decoration: InputDecoration(
                                  labelText: 'Class',
                                  labelStyle: TextStyle(color: g.textSecondary),
                                  border: const OutlineInputBorder(),
                                ),
                                items: _classes.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                                onChanged: (v) {
                                  // Selection only — the request waits for Check.
                                  if (v != null) setState(() => _classCode = v);
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: _quota,
                                dropdownColor: AppColors.surfaceElevated,
                                style: TextStyle(color: g.textPrimary),
                                decoration: InputDecoration(
                                  labelText: 'Quota',
                                  labelStyle: TextStyle(color: g.textSecondary),
                                  border: const OutlineInputBorder(),
                                ),
                                items: _quotas.map((q) => DropdownMenuItem(value: q, child: Text(q))).toList(),
                                onChanged: (v) {
                                  // Selection only — the request waits for Check.
                                  if (v != null) setState(() => _quota = v);
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 14),

                // Explicit fetch. The only thing in this screen that spends a
                // RailKit request.
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _loading ? null : _fetch,
                    child: Container(
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        gradient: _loading ? null : GlassTheme.accent,
                        color: _loading ? g.fillStrong : null,
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: _loading
                            ? null
                            : [
                                BoxShadow(
                                  color: GlassTheme.accentIndigo
                                      .withValues(alpha: 0.34),
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
                            size: 18,
                            color: _loading ? g.textSecondary : Colors.white,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _loading ? 'Checking…' : 'Check availability',
                            style: TextStyle(
                              color: _loading ? g.textSecondary : Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Results — rendered by the SHARED body, so the screen and the
                // bottom sheet cannot drift. See AvailabilityResultsBody.
                Expanded(
                  child: AvailabilityResultsBody(
                    loading: _loading,
                    error: _error,
                    availability: _availability,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
