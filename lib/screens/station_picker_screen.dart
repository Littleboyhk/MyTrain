import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/station_repository.dart';
import '../l10n/app_localizations.dart';
import '../models/rail_station.dart';
import '../theme/app_theme.dart';
import '../theme/glass_theme.dart';
import '../utils/haptics.dart';
import '../widgets/glass_container.dart';
import '../widgets/icon_action_button.dart';
import '../widgets/mesh_background.dart';

/// Full-screen searchable station picker over the ~9,000-station dataset.
class StationPickerScreen extends ConsumerStatefulWidget {
  const StationPickerScreen({
    super.key,
    required this.title,
    this.excludeCode,
  });

  final String title;
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
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          const Positioned.fill(child: MeshBackground()),
          SafeArea(
            child: Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: repoAsync.when(
                    loading: () => const _PickerLoading(),
                    error: (e, _) => Center(
                      child: Text(
                        'Could not load stations',
                        style: AppText.label.copyWith(
                          color: context.glass.textSecondary,
                        ),
                      ),
                    ),
                    data: (repo) => _buildResults(repo),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
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
              const SizedBox(width: 6),
              Text(
                widget.title,
                style: AppText.titleStrong.copyWith(
                  color: context.glass.textPrimary,
                  fontSize: 20,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildSearchField(),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    final g = context.glass;
    return GlassContainer(
      pill: true,
      blurSigma: 20,
      strong: true,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Icon(Icons.search_rounded, size: 20, color: g.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              autofocus: true,
              style: AppText.stationName.copyWith(
                fontSize: 15,
                color: g.textPrimary,
              ),
              cursorColor: GlassTheme.accentViolet,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: L10n.of(context).searchCityStationCode,
                hintStyle: AppText.label.copyWith(color: g.textMuted),
                contentPadding: const EdgeInsets.symmetric(vertical: 16),
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
                padding: const EdgeInsets.all(6),
                child: Icon(Icons.close_rounded,
                    size: 18, color: g.textSecondary),
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

    return ListView.separated(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: results.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
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
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        if (recent.isNotEmpty) ...[
          _sectionHeader(L10n.of(context).sectionRecent),
          for (final s in recent) ...[
            _StationRow(station: s, query: '', onTap: () => _select(s)),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 8),
        ],
        _sectionHeader(L10n.of(context).sectionPopular),
        for (final s in popular) ...[
          _StationRow(station: s, query: '', onTap: () => _select(s)),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _sectionHeader(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
      child: Text(
        text,
        style: AppText.overline.copyWith(color: context.glass.textMuted),
      ),
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
    final g = context.glass;
    return GlassContainer(
      radius: 20,
      blurSigma: 15,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              // Glass Station Code Badge
              GlassContainer(
                radius: 12,
                blurSigma: 0,
                strong: true,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Text(
                  station.code,
                  style: const TextStyle(
                    color: GlassTheme.accentViolet,
                    fontSize: 13,
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
                    _highlightedName(context),
                    const SizedBox(height: 2),
                    Text(
                      'Station code · ${station.code}',
                      style: AppText.label.copyWith(
                        color: g.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.north_east_rounded, size: 16, color: g.textMuted),
            ],
          ),
        ),
      ),
    );
  }

  Widget _highlightedName(BuildContext context) {
    final g = context.glass;
    final base = AppText.stationName.copyWith(color: g.textPrimary);
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
              color: GlassTheme.accentViolet,
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
          color: GlassTheme.accentViolet,
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
    final g = context.glass;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded, size: 40, color: g.textMuted),
            const SizedBox(height: 14),
            Text(
              'No stations match "$query"',
              textAlign: TextAlign.center,
              style: AppText.label.copyWith(color: g.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
