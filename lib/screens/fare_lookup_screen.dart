import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/railkit_mappers.dart';
import '../data/railkit_service.dart';
import '../models/fare_info.dart';
import '../theme/app_colors.dart';
import '../theme/glass_theme.dart';
import '../widgets/glass_container.dart';
import '../widgets/glass_surface.dart';
import '../widgets/mesh_background.dart';

class FareLookupScreen extends ConsumerStatefulWidget {
  const FareLookupScreen({
    super.key,
    this.initialFrom,
    this.initialTo,
    this.initialTrainNumber,
  });

  final String? initialFrom;
  final String? initialTo;
  final String? initialTrainNumber;

  @override
  ConsumerState<FareLookupScreen> createState() => _FareLookupScreenState();
}

class _FareLookupScreenState extends ConsumerState<FareLookupScreen> {
  late final TextEditingController _fromCtrl;
  late final TextEditingController _toCtrl;
  late final TextEditingController _trainCtrl;
  bool _loading = false;
  String? _error;
  FareBreakdown? _fare;

  @override
  void initState() {
    super.initState();
    _fromCtrl = TextEditingController(text: widget.initialFrom ?? 'ASN');
    _toCtrl = TextEditingController(text: widget.initialTo ?? 'NDLS');
    _trainCtrl = TextEditingController(text: widget.initialTrainNumber ?? '12313');
    _fetch();
  }

  @override
  void dispose() {
    _fromCtrl.dispose();
    _toCtrl.dispose();
    _trainCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    final from = _fromCtrl.text.trim().toUpperCase();
    final to = _toCtrl.text.trim().toUpperCase();
    final train = _trainCtrl.text.trim();
    if (from.isEmpty || to.isEmpty || train.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final service = ref.read(railKitServiceProvider);
      final res = await service.fareLookup(
        trainNumber: train,
        from: from,
        to: to,
      );
      final data = fareFromRailkit(res.data, from, to, train);
      if (mounted) {
        setState(() {
          _fare = data;
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
                        'Fare Lookup',
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
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _fromCtrl,
                                style: TextStyle(color: g.textPrimary),
                                textCapitalization: TextCapitalization.characters,
                                decoration: InputDecoration(
                                  labelText: 'From',
                                  labelStyle: TextStyle(color: g.textSecondary),
                                  border: const OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Icon(Icons.arrow_forward_rounded, color: AppColors.accent),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _toCtrl,
                                style: TextStyle(color: g.textPrimary),
                                textCapitalization: TextCapitalization.characters,
                                decoration: InputDecoration(
                                  labelText: 'To',
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
                              child: TextField(
                                controller: _trainCtrl,
                                style: TextStyle(color: g.textPrimary),
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  labelText: 'Train No (Optional)',
                                  labelStyle: TextStyle(color: g.textSecondary),
                                  border: const OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.accent,
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                              ),
                              icon: const Icon(Icons.search_rounded, color: Colors.white),
                              label: const Text('Lookup', style: TextStyle(color: Colors.white)),
                              onPressed: _fetch,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Fares list
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                          ? Center(child: Text(_error!, style: TextStyle(color: AppColors.delayed)))
                          : _fare == null || _fare!.fares.isEmpty
                              ? Center(child: Text('No fare breakdown available.', style: TextStyle(color: g.textSecondary)))
                              : ListView.builder(
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  itemCount: _fare!.fares.length,
                                  itemBuilder: (context, i) {
                                    final item = _fare!.fares[i];
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 12.0),
                                      child: GlassContainer(
                                        padding: const EdgeInsets.all(16),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Row(
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.all(10),
                                                  decoration: BoxDecoration(
                                                    color: AppColors.accent.withValues(alpha: 0.15),
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                  child: Text(
                                                    item.classCode,
                                                    style: TextStyle(
                                                      color: AppColors.accent,
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 16,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                Text(
                                                  item.className.isEmpty ? 'Class ${item.classCode}' : item.className,
                                                  style: TextStyle(color: g.textPrimary, fontSize: 15),
                                                ),
                                              ],
                                            ),
                                            Text(
                                              '₹${item.totalFare.toStringAsFixed(0)}',
                                              style: TextStyle(
                                                color: g.textPrimary,
                                                fontSize: 22,
                                                fontWeight: FontWeight.bold,
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
