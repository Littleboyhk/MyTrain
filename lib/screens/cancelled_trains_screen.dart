import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/railkit_mappers.dart';
import '../data/railkit_service.dart';
import '../models/cancelled_train.dart';
import '../theme/app_colors.dart';
import '../theme/glass_theme.dart';
import '../widgets/glass_container.dart';
import '../widgets/mesh_background.dart';

class CancelledTrainsScreen extends ConsumerStatefulWidget {
  const CancelledTrainsScreen({super.key});

  @override
  ConsumerState<CancelledTrainsScreen> createState() => _CancelledTrainsScreenState();
}

class _CancelledTrainsScreenState extends ConsumerState<CancelledTrainsScreen> {
  bool _loading = false;
  String? _error;
  List<CancelledTrain> _trains = [];
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final service = ref.read(railKitServiceProvider);
      final res = await service.cancelList();
      final list = cancelledTrainsFromRailkit(res.data);
      if (mounted) {
        setState(() {
          _trains = list;
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

    final filtered = _trains.where((t) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return t.trainNumber.toLowerCase().contains(q) ||
          t.trainName.toLowerCase().contains(q) ||
          t.origin.toLowerCase().contains(q) ||
          t.destination.toLowerCase().contains(q);
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
                        'Cancelled Trains',
                        style: TextStyle(color: g.textPrimary, fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.refresh_rounded),
                        color: AppColors.accent,
                        onPressed: _fetch,
                      ),
                    ],
                  ),
                ),

                // Search bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: GlassContainer(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: TextField(
                      style: TextStyle(color: g.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'Search cancelled train number or name...',
                        hintStyle: TextStyle(color: g.textMuted),
                        icon: Icon(Icons.search_rounded, color: g.textSecondary),
                        border: InputBorder.none,
                      ),
                      onChanged: (v) => setState(() => _searchQuery = v),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // List
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                          ? Center(child: Text(_error!, style: TextStyle(color: AppColors.delayed)))
                          : filtered.isEmpty
                              ? Center(
                                  child: Text('No cancelled trains listed today.', style: TextStyle(color: g.textSecondary)),
                                )
                              : ListView.builder(
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  itemCount: filtered.length,
                                  itemBuilder: (context, i) {
                                    final item = filtered[i];
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 12.0),
                                      child: GlassContainer(
                                        padding: const EdgeInsets.all(16),
                                        child: Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(10),
                                              decoration: BoxDecoration(
                                                color: AppColors.delayed.withValues(alpha: 0.15),
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: Icon(Icons.block_rounded, color: AppColors.delayed),
                                            ),
                                            const SizedBox(width: 14),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Text(
                                                        item.trainNumber,
                                                        style: TextStyle(color: AppColors.delayed, fontWeight: FontWeight.bold),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Expanded(
                                                        child: Text(
                                                          item.trainName,
                                                          style: TextStyle(color: g.textPrimary, fontWeight: FontWeight.w600),
                                                          maxLines: 1,
                                                          overflow: TextOverflow.ellipsis,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    '${item.origin} → ${item.destination}',
                                                    style: TextStyle(color: g.textSecondary, fontSize: 13),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: AppColors.delayed.withValues(alpha: 0.2),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                item.isFullyCancelled ? 'FULL' : 'PARTIAL',
                                                style: TextStyle(color: AppColors.delayed, fontSize: 11, fontWeight: FontWeight.bold),
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
