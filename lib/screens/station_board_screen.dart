import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/railkit_mappers.dart';
import '../data/railkit_service.dart';
import '../models/station_board.dart';
import '../theme/app_colors.dart';
import '../theme/glass_theme.dart';
import '../widgets/glass_container.dart';
import '../widgets/glass_surface.dart';
import '../widgets/mesh_background.dart';

class StationBoardScreen extends ConsumerStatefulWidget {
  const StationBoardScreen({super.key, this.initialStationCode});

  final String? initialStationCode;

  @override
  ConsumerState<StationBoardScreen> createState() => _StationBoardScreenState();
}

class _StationBoardScreenState extends ConsumerState<StationBoardScreen> {
  late final TextEditingController _stationController;
  bool _loading = false;
  String? _error;
  List<StationBoardEntry> _entries = [];
  String _filter = 'ALL';

  @override
  void initState() {
    super.initState();
    _stationController = TextEditingController(
      text: widget.initialStationCode ?? 'SBC',
    );
    _fetchBoard();
  }

  @override
  void dispose() {
    _stationController.dispose();
    super.dispose();
  }

  Future<void> _fetchBoard() async {
    final code = _stationController.text.trim().toUpperCase();
    if (code.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final service = ref.read(railKitServiceProvider);
      final res = await service.liveAtStation(stationCode: code);
      final list = stationBoardFromRailkit(res.data);
      if (mounted) {
        setState(() {
          _entries = list;
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

    final filtered = _entries.where((e) {
      if (_filter == 'ARRIVALS') return e.status.toUpperCase().contains('ARRIV');
      if (_filter == 'DEPARTURES') return e.status.toUpperCase().contains('DEPART');
      return true;
    }).toList();

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
                        'Station Live Board',
                        style: TextStyle(color: g.textPrimary, fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),

                // Station Search Bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: GlassSurface(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        Icon(Icons.train_rounded, color: AppColors.accent),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _stationController,
                            style: TextStyle(color: g.textPrimary, fontSize: 16),
                            textCapitalization: TextCapitalization.characters,
                            decoration: InputDecoration(
                              hintText: 'Enter Station Code (e.g. SBC, MAS, TVC)',
                              hintStyle: TextStyle(color: g.textMuted, fontSize: 14),
                              border: InputBorder.none,
                            ),
                            onSubmitted: (_) => _fetchBoard(),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.search_rounded),
                          color: AppColors.accent,
                          onPressed: _fetchBoard,
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Filter Chips
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Row(
                    children: ['ALL', 'ARRIVALS', 'DEPARTURES'].map((f) {
                      final isSel = _filter == f;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: FilterChip(
                          selected: isSel,
                          label: Text(f, style: TextStyle(color: isSel ? Colors.white : g.textSecondary)),
                          selectedColor: AppColors.accent,
                          backgroundColor: AppColors.surfaceElevated,
                          onSelected: (_) => setState(() => _filter = f),
                        ),
                      );
                    }).toList(),
                  ),
                ),

                const SizedBox(height: 12),

                // Board List
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24.0),
                                child: Text(
                                  _error!,
                                  style: TextStyle(color: AppColors.delayed),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            )
                          : filtered.isEmpty
                              ? Center(
                                  child: Text(
                                    'No trains found for station ${_stationController.text.toUpperCase()}',
                                    style: TextStyle(color: g.textSecondary),
                                  ),
                                )
                              : ListView.builder(
                                  padding: const EdgeInsets.all(16),
                                  itemCount: filtered.length,
                                  itemBuilder: (context, i) {
                                    final item = filtered[i];
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 12.0),
                                      child: GlassContainer(
                                        padding: const EdgeInsets.all(16),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: AppColors.accent.withValues(alpha: 0.15),
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: Text(
                                                    item.trainNumber,
                                                    style: TextStyle(
                                                      color: AppColors.accent,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 10),
                                                Expanded(
                                                  child: Text(
                                                    item.trainName,
                                                    style: TextStyle(
                                                      color: g.textPrimary,
                                                      fontWeight: FontWeight.w600,
                                                      fontSize: 15,
                                                    ),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: (item.isDelayed ? AppColors.delayed : AppColors.onTime)
                                                        .withValues(alpha: 0.15),
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: Text(
                                                    item.isDelayed ? '+${item.delayMinutes}m' : 'On Time',
                                                    style: TextStyle(
                                                      color: item.isDelayed ? AppColors.delayed : AppColors.onTime,
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 10),
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Text(
                                                  '${item.origin} → ${item.destination}',
                                                  style: TextStyle(color: g.textSecondary, fontSize: 13),
                                                ),
                                                Text(
                                                  'PF: ${item.platform}',
                                                  style: TextStyle(color: g.textPrimary, fontWeight: FontWeight.w500),
                                                ),
                                              ],
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
