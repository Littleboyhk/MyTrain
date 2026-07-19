import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/station_repository.dart';
import '../models/rail_station.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/haptics.dart';
import '../widgets/icon_action_button.dart';

/// Full-screen searchable station picker over the ~9,000-station dataset.
///
/// Returns the selected [RailStation] via [Navigator.pop]. Shows recent +
/// popular stations before the user types, then live-filters as they type.
class StationPickerScreen extends ConsumerStatefulWidget {
  const StationPickerScreen({
    super.key,
    required this.title,
    this.excludeCode,
  });

  /// e.g. "Select origin" / "Select destination".
  final String title;

  /// A station code to hide from results (so FROM and TO can't be identical).
  final String? excludeCode;

  @override
  ConsumerState<StationPickerScreen> createState() =>
      _StationPickerScreenState();
}

class _StationPickerScreenState extends ConsumerState<StationPickerScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      if (_controller.text != _query) {
        setState(() => _query = _controller.text);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _select(RailStation station) {
    Haptics.selection();
    ref.read(recentStationsProvider.notifier).add(station);
    Navigator.of(context).pop(station);
  }

  @override
  Widget build(BuildContext context) {
    final repoAsync = ref.watch(stationRepositoryProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: repoAsync.when(
                loading: () => const _PickerLoading(),
                error: (e, _) => Center(
                  child: Text(
                    'Could not load stations',
                    style: AppText.label,
                  ),
                ),
                data: (repo) => _buildResults(repo),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconActionButton(
                icon: Icons.arrow_back_ios_new_rounded,
                iconSize: 18,
                background: false,
                onTap: () => Navigator.of(context).maybePop(),
              ),
              const SizedBox(width: 4),
              Text(widget.title, style: AppText.titleStrong),
            ],
          ),
          const SizedBox(height: 12),
          _buildSearchField(),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.lineMuted),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Icon(Icons.search_rounded, size: 20, color: AppColors.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              autofocus: true,
              style: AppText.stationName.copyWith(fontSize: 15),
              cursorColor: AppColors.accent,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: 'Search city, station or code',
                hintStyle: AppText.label.copyWith(color: AppColors.textMuted),
                contentPadding: const EdgeInsets.symmetric(vertical: 15),
              ),
            ),
          ),
          if (_query.isNotEmpty)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                _controller.clear();
                _focusNode.requestFocus();
              },
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(Icons.close_rounded,
                    size: 18, color: AppColors.textSecondary),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildResults(StationRepository repo) {
    final trimmed = _query.trim();

    if (trimmed.isEmpty) {
      return _buildIdle(repo);
    }

    final results = repo
        .search(trimmed)
        .where((s) => s.code != widget.excludeCode)
        .toList();

    if (results.isEmpty) {
      return _EmptyResults(query: trimmed);
    }

    return ListView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: results.length,
      itemBuilder: (context, i) => _StationRow(
        station: results[i],
        query: trimmed,
        onTap: () => _select(results[i]),
      ),
    );
  }

  Widget _buildIdle(StationRepository repo) {
    final recent = ref
        .watch(recentStationsProvider)
        .where((s) => s.code != widget.excludeCode)
        .toList();
    final popular =
        repo.popular.where((s) => s.code != widget.excludeCode).toList();

    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (recent.isNotEmpty) ...[
          _sectionHeader('RECENT'),
          for (final s in recent)
            _StationRow(station: s, query: '', onTap: () => _select(s)),
          const SizedBox(height: 8),
        ],
        _sectionHeader('POPULAR STATIONS'),
        for (final s in popular)
          _StationRow(station: s, query: '', onTap: () => _select(s)),
      ],
    );
  }

  Widget _sectionHeader(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      child: Text(text, style: AppText.overline),
    );
  }
}

class _StationRow extends StatelessWidget {
  const _StationRow({
    required this.station,
    required this.query,
    required this.onTap,
  });

  final RailStation station;
  final String query;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.lineMuted),
              ),
              child: Text(
                station.code,
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: const TextStyle(
                  color: AppColors.accent,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _highlightedName(),
                  const SizedBox(height: 2),
                  Text(
                    'Station code · ${station.code}',
                    style: AppText.label
                        .copyWith(color: AppColors.textMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(Icons.north_east_rounded,
                size: 16, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }

  Widget _highlightedName() {
    final base = AppText.stationName;
    if (query.isEmpty) {
      return Text(station.name,
          maxLines: 1, overflow: TextOverflow.ellipsis, style: base);
    }
    final lower = station.name.toLowerCase();
    final q = query.toLowerCase();
    final idx = lower.indexOf(q);
    if (idx < 0) {
      return Text(station.name,
          maxLines: 1, overflow: TextOverflow.ellipsis, style: base);
    }
    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: base,
        children: [
          TextSpan(text: station.name.substring(0, idx)),
          TextSpan(
            text: station.name.substring(idx, idx + q.length),
            style: base.copyWith(
              color: AppColors.accent,
              fontWeight: FontWeight.w800,
            ),
          ),
          TextSpan(text: station.name.substring(idx + q.length)),
        ],
      ),
    );
  }
}

class _PickerLoading extends StatelessWidget {
  const _PickerLoading();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SizedBox(
        width: 26,
        height: 26,
        child: CircularProgressIndicator(
          strokeWidth: 2.4,
          color: AppColors.accent,
        ),
      ),
    );
  }
}

class _EmptyResults extends StatelessWidget {
  const _EmptyResults({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded,
                size: 40, color: AppColors.textMuted),
            const SizedBox(height: 14),
            Text(
              'No stations match "$query"',
              textAlign: TextAlign.center,
              style: AppText.label.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
