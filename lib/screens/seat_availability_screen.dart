import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/railkit_mappers.dart';
import '../data/railkit_service.dart';
import '../models/seat_availability.dart';
import '../theme/app_colors.dart';
import '../theme/glass_theme.dart';
import '../widgets/glass_container.dart';
import '../widgets/glass_surface.dart';
import '../widgets/mesh_background.dart';

class SeatAvailabilityScreen extends ConsumerStatefulWidget {
  const SeatAvailabilityScreen({
    super.key,
    this.initialFrom,
    this.initialTo,
    this.initialDate,
  });

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
    _trainCtrl = TextEditingController(text: '12496');
    _fromCtrl = TextEditingController(text: widget.initialFrom ?? 'ASN');
    _toCtrl = TextEditingController(text: widget.initialTo ?? 'DDU');
    final now = DateTime.now();
    _date = widget.initialDate ?? '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    _fetch();
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
    if (train.isEmpty || from.isEmpty || to.isEmpty) return;

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
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Color _statusColor(String type) {
    switch (type) {
      case 'AVL':
        return AppColors.onTime;
      case 'RAC':
        return Colors.amber;
      case 'WL':
        return AppColors.delayed;
      case 'REGRET':
        return Colors.red;
      default:
        return AppColors.textMuted;
    }
  }

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
                                  if (v != null) {
                                    setState(() => _classCode = v);
                                    _fetch();
                                  }
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
                                  if (v != null) {
                                    setState(() => _quota = v);
                                    _fetch();
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Results
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                          ? Center(
                              child: Text(_error!, style: TextStyle(color: AppColors.delayed)),
                            )
                          : _availability == null || _availability!.days.isEmpty
                              ? Center(
                                  child: Text('No availability data available.', style: TextStyle(color: g.textSecondary)),
                                )
                              : ListView.builder(
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  itemCount: _availability!.days.length,
                                  itemBuilder: (context, i) {
                                    final day = _availability!.days[i];
                                    final col = _statusColor(day.statusType);
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 12.0),
                                      child: GlassContainer(
                                        padding: const EdgeInsets.all(16),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  day.date,
                                                  style: TextStyle(
                                                    color: g.textPrimary,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 15,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  'Fare: ₹${day.fare}',
                                                  style: TextStyle(color: g.textSecondary, fontSize: 13),
                                                ),
                                              ],
                                            ),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                              decoration: BoxDecoration(
                                                color: col.withValues(alpha: 0.15),
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border.all(color: col.withValues(alpha: 0.4)),
                                              ),
                                              child: Text(
                                                day.status,
                                                style: TextStyle(
                                                  color: col,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
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
