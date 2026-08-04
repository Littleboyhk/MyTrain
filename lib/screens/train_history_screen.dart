import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/railkit_mappers.dart';
import '../data/railkit_service.dart';
import '../models/train_history_entry.dart';
import '../theme/app_colors.dart';
import '../theme/glass_theme.dart';
import '../widgets/glass_container.dart';
import '../widgets/glass_surface.dart';
import '../widgets/mesh_background.dart';

class TrainHistoryScreen extends ConsumerStatefulWidget {
  const TrainHistoryScreen({
    super.key,
    this.initialTrainNumber,
    this.initialDate,
  });

  final String? initialTrainNumber;
  final String? initialDate;

  @override
  ConsumerState<TrainHistoryScreen> createState() => _TrainHistoryScreenState();
}

class _TrainHistoryScreenState extends ConsumerState<TrainHistoryScreen> {
  late final TextEditingController _trainCtrl;
  late String _date;
  bool _loading = false;
  String? _error;
  TrainHistoryEntry? _history;

  @override
  void initState() {
    super.initState();
    _trainCtrl = TextEditingController(text: widget.initialTrainNumber ?? '16332');
    final now = DateTime.now().subtract(const Duration(days: 1));
    _date = widget.initialDate ?? '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    _fetch();
  }

  @override
  void dispose() {
    _trainCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    final train = _trainCtrl.text.trim();
    if (train.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final service = ref.read(railKitServiceProvider);
      final res = await service.trainHistory(trainNumber: train, date: _date);
      final data = trainHistoryFromRailkit(res.data, train, _date);
      if (mounted) {
        setState(() {
          _history = data;
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
                        'Run Punctuality History',
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
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _trainCtrl,
                            style: TextStyle(color: g.textPrimary),
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Train Number',
                              labelStyle: TextStyle(color: g.textSecondary),
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.accent,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                          ),
                          onPressed: _fetch,
                          child: const Text('Fetch History', style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Content
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                          ? Center(child: Text(_error!, style: TextStyle(color: AppColors.delayed)))
                          : _history == null
                              ? Center(child: Text('No history found for train ${_trainCtrl.text}', style: TextStyle(color: g.textSecondary)))
                              : ListView(
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  children: [
                                    GlassContainer(
                                      padding: const EdgeInsets.all(16),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Date: ${_history!.date}',
                                                style: TextStyle(color: g.textPrimary, fontWeight: FontWeight.bold, fontSize: 15),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                _history!.statusNote.isEmpty ? 'Completed' : _history!.statusNote,
                                                style: TextStyle(color: g.textSecondary, fontSize: 13),
                                              ),
                                            ],
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: (_history!.isOnTime ? AppColors.onTime : AppColors.delayed).withValues(alpha: 0.15),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              _history!.isOnTime ? 'ON TIME' : '+${_history!.totalDelayMinutes}m LATE',
                                              style: TextStyle(
                                                color: _history!.isOnTime ? AppColors.onTime : AppColors.delayed,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    ..._history!.stops.map((s) {
                                      return Padding(
                                        padding: const EdgeInsets.only(bottom: 8.0),
                                        child: GlassContainer(
                                          padding: const EdgeInsets.all(12),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    '${s.stationName} (${s.stationCode})',
                                                    style: TextStyle(color: g.textPrimary, fontWeight: FontWeight.w600),
                                                  ),
                                                  Text(
                                                    'Sch: ${s.scheduledArrival} → Act: ${s.actualArrival}',
                                                    style: TextStyle(color: g.textSecondary, fontSize: 12),
                                                  ),
                                                ],
                                              ),
                                              Text(
                                                s.delayMinutes > 0 ? '+${s.delayMinutes}m' : 'On Time',
                                                style: TextStyle(
                                                  color: s.delayMinutes > 0 ? AppColors.delayed : AppColors.onTime,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    }),
                                  ],
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
