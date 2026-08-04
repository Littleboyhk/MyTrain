import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';

import '../data/railkit_service.dart';
import '../data/rapidapi_service.dart';
import '../data/recent_trains_service.dart';
import '../data/train_platform_provider.dart';
import '../data/train_repository.dart';
import '../l10n/app_localizations.dart';
import '../models/rail_station.dart';
import '../models/train_summary.dart';
import '../theme/app_theme.dart';
import '../theme/glass_theme.dart';
import '../theme/motion.dart';
import '../utils/haptics.dart';
import '../widgets/glass_container.dart';
import '../widgets/glass_surface.dart';
import '../widgets/icon_action_button.dart';
import '../widgets/journey_duration_bar.dart';
import '../widgets/mesh_background.dart';
import '../widgets/running_days_row.dart';
import '../widgets/train_number_tag.dart';
import '../widgets/report_missing_train_sheet.dart';
import '../widgets/route_mini_visual.dart';
import '../widgets/static_route_map_visual.dart';
import '../widgets/split_journey_card.dart';
import '../widgets/split_journey_disclaimer.dart';
import '../data/split_journey_service.dart';
import '../models/split_journey_combo.dart';
import 'live_tracking_screen.dart';

/// Search results for a chosen route (FROM → TO).
///
/// DATA + QUOTA NOTES
/// ------------------
/// Results come from `trainRepository.betweenStations`, which goes through the
/// `search-trains` Edge Function — server-side cached under `search:FROM:TO` and
/// counted against the 50/month RailKit budget. This screen deliberately adds NO
/// direct call path.
///
/// The search is fetched ONCE and every filter/sort here is applied client-side.
/// That is not just an optimisation: the cache key intentionally omits the date
/// (RailKit's search ignores it, and a 3-argument call returns HTTP 502), so a
/// date change could not produce different results anyway. Refetching per filter
/// tap would burn quota for an identical payload.
class TrainResultsScreen extends ConsumerStatefulWidget {
  const TrainResultsScreen({
    super.key,
    required this.from,
    required this.to,
    required this.date,
  });

  final RailStation from;
  final RailStation to;
  final DateTime date;

  @override
  ConsumerState<TrainResultsScreen> createState() => _TrainResultsScreenState();
}

/// Which departure date the list is filtered to.
enum _DateFilter { allDates, today, tomorrow, calendar }

enum _SortBy { departure, arrival }

class _TrainResultsScreenState extends ConsumerState<TrainResultsScreen> {
  late Future<List<TrainSummary>> _future;

  _DateFilter _dateFilter = _DateFilter.allDates;
  DateTime? _calendarDate;
  _SortBy _sort = _SortBy.departure;
  bool _showTightConnections = false;

  @override
  void initState() {
    super.initState();
    _future = trainRepository.betweenStations(
      widget.from,
      widget.to,
      date: widget.date,
    );
  }

  /// The date the filter resolves to, or null for "All Dates".
  DateTime? get _effectiveDate {
    final now = DateTime.now();
    return switch (_dateFilter) {
      _DateFilter.allDates => null,
      _DateFilter.today => DateTime(now.year, now.month, now.day),
      _DateFilter.tomorrow =>
        DateTime(now.year, now.month, now.day).add(const Duration(days: 1)),
      _DateFilter.calendar => _calendarDate,
    };
  }

  String get _datePillLabel => switch (_dateFilter) {
        _DateFilter.allDates => 'All Dates',
        _DateFilter.today => 'Today',
        _DateFilter.tomorrow => 'Tomorrow',
        _DateFilter.calendar => _calendarDate == null
            ? 'All Dates'
            : '${_calendarDate!.day} ${_monthName(_calendarDate!.month)}',
      };

  static String _monthName(int m) => const [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ][m - 1];

  // ---------------------------------------------------------------------------
  // Filtering + sorting (all client-side, see class doc)
  // ---------------------------------------------------------------------------

  /// Drops trains that don't run on the selected date.
  ///
  /// Uses RailKit's real `running_days` mask. A train whose mask is unknown is
  /// KEPT — hiding a service because we lack data would be worse than showing it.
  List<TrainSummary> _applyFilters(List<TrainSummary> trains) {
    final date = _effectiveDate;
    var out = trains;
    if (date != null) {
      out = trains.where((t) {
        final runs = t.runsOnWeekday(date.weekday);
        return runs ?? true;
      }).toList();
    }

    out = [...out]..sort((a, b) {
      final av = _minutes(_sort == _SortBy.departure ? a.departure : a.arrival);
      final bv = _minutes(_sort == _SortBy.departure ? b.departure : b.arrival);
      if (av == null || bv == null) return 0;
      return av.compareTo(bv);
    });
    return out;
  }

  /// Null for an unknown or unparseable time. The sort already treats null as
  /// "leave the order alone", so a train with no schedule does not jump to the
  /// top.
  static int? _minutes(String? hhmm) {
    if (hhmm == null) return null;
    final m = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(hhmm.trim());
    if (m == null) return null;
    return int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!);
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  void _track(TrainSummary train) {
    Haptics.tap();
    // Feeds the home screen's RECENT list — this is the main path by which a
    // train becomes "recently searched".
    ref.read(recentTrainsProvider.notifier).add(train);
    Navigator.of(context).push(
      CupertinoPageRoute(builder: (_) => LiveTrackingScreen(train: train)),
    );
  }

  Future<void> _openDateSheet() async {
    Haptics.tap();
    final picked = await _showDateFilterSheet(
      context,
      originName: widget.from.name,
      current: _dateFilter,
    );
    if (picked == null || !mounted) return;

    if (picked == _DateFilter.calendar) {
      final now = DateTime.now();
      final day = await showDatePicker(
        context: context,
        initialDate: _calendarDate ?? now,
        firstDate: DateTime(now.year, now.month, now.day),
        lastDate: now.add(const Duration(days: 120)),
      );
      if (day == null || !mounted) return;
      setState(() {
        _dateFilter = _DateFilter.calendar;
        _calendarDate = day;
      });
      return;
    }
    setState(() => _dateFilter = picked);
  }

  void _toggleSort() {
    Haptics.selection();
    setState(() {
      _sort = _sort == _SortBy.departure ? _SortBy.arrival : _SortBy.departure;
    });
  }

  /// Glass toast, matching the pattern used on the settings screen.
  void _toast(String message) {
    final g = context.glass;
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => Positioned(
        left: 24,
        right: 24,
        bottom: 140,
        child: IgnorePointer(
          child: Center(
            child: GlassContainer(
              radius: 16,
              blurSigma: 22,
              strong: true,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: AppText.label.copyWith(
                  color: g.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(entry);
    Future.delayed(const Duration(milliseconds: 2600), entry.remove);
  }

  // These three actions have NO data source behind them yet. They are wired to
  // an honest explanation rather than a fake result — see the report.
  void _notAvailable(String what) {
    Haptics.tap();
    _toast(what);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          const Positioned.fill(child: MeshBackground()),
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                _appBar(),
                _filterRow(),
                Expanded(child: _results()),
              ],
            ),
          ),
          Positioned(left: 0, right: 0, bottom: 0, child: _bottomBar()),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 1) App bar
  // ---------------------------------------------------------------------------
  Widget _appBar() {
    final g = context.glass;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 8, 10),
      child: Row(
        children: [
          IconActionButton(
            icon: Icons.arrow_back_ios_new_rounded,
            iconSize: 18,
            background: false,
            onTap: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              'Search Results',
              style: AppText.titleStrong
                  .copyWith(color: g.textPrimary, fontSize: 19),
            ),
          ),
          IconActionButton(
            icon: Icons.ios_share_rounded,
            iconSize: 18,
            background: false,
            onTap: () => _notAvailable(
              'Sharing a result list isn\'t built yet.',
            ),
          ),
          _overflowMenu(g),
        ],
      ),
    );
  }

  Widget _overflowMenu(GlassTheme g) {
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert_rounded, size: 20, color: g.textSecondary),
      color: g.isDark ? const Color(0xFF16161C) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      onSelected: (value) {
        switch (value) {
          case 'refresh':
            Haptics.tap();
            // Goes back through the cached path, so this is quota-safe until the
            // server-side cache entry expires.
            setState(() {
              _future = trainRepository.betweenStations(
                widget.from,
                widget.to,
                date: widget.date,
              );
            });
          case 'report':
            _reportMissing();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'refresh',
          child: Text('Refresh results',
              style: AppText.label.copyWith(color: g.textPrimary)),
        ),
        PopupMenuItem(
          value: 'report',
          child: Text('Report missing train',
              style: AppText.label.copyWith(color: g.textPrimary)),
        ),
      ],
    );
  }

  void _reportMissing() {
    Haptics.tap();
    showReportMissingTrainSheet(
      context,
      from: widget.from,
      to: widget.to,
    );
  }

  // ---------------------------------------------------------------------------
  // 2) Filter row
  // ---------------------------------------------------------------------------
  Widget _filterRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: _FilterPill(
              label: _datePillLabel,
              icon: Icons.calendar_today_rounded,
              trailingChevron: true,
              active: _dateFilter != _DateFilter.allDates,
              onTap: _openDateSheet,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _FilterPill(
              label: 'Show fares',
              icon: Icons.currency_rupee_rounded,
              // RailKit's search payload carries no fare/class/availability
              // fields at all, so this cannot be a working toggle. Rendered
              // unavailable rather than faked.
              unavailable: true,
              onTap: () => _notAvailable(
                'Fares aren\'t in our rail data source yet.',
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _FilterPill(
              label: _sort == _SortBy.departure ? 'Departure' : 'Arrival',
              icon: _sort == _SortBy.departure
                  ? Icons.north_east_rounded
                  : Icons.south_west_rounded,
              active: true,
              onTap: _toggleSort,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Results list
  // ---------------------------------------------------------------------------
  Widget _results() {
    return FutureBuilder<List<TrainSummary>>(
      future: _future,
      builder: (context, snapshot) {
        final g = context.glass;

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: GlassTheme.accentViolet),
          );
        }
        if (snapshot.hasError) return _errorState(snapshot.error);

        final all = snapshot.data ?? const <TrainSummary>[];
        if (all.isEmpty) {
          return _buildSplitJourneyFallback(context, g);
        }

        final filtered = _applyFilters(all);
        if (filtered.isEmpty) {
          return _buildSplitJourneyFallback(context, g);
        }

        final rows = _groupByLeg(filtered);

        return AnimationLimiter(
          child: ListView.builder(
            physics: const BouncingScrollPhysics(),
            // Bottom padding clears the sticky action bar.
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 130),
            itemCount: rows.length + 1,
            itemBuilder: (context, i) {
              if (i == rows.length) return _reportMissingLink();
              final row = rows[i];
              return AnimationConfiguration.staggeredList(
                position: i,
                duration: Motion.listItem,
                delay: Motion.listStagger,
                child: SlideAnimation(
                  verticalOffset: 26,
                  curve: Motion.standard,
                  child: FadeInAnimation(
                    curve: Motion.standard,
                    child: row.train == null
                        // 3) Route band, repeated as a section divider whenever
                        // results span more than one origin/destination pair.
                        ? RouteHeaderBand(
                            fromCode: row.fromCode,
                            fromName: row.fromName,
                            toCode: row.toCode,
                            toName: row.toName,
                          )
                        : _TrainCard(
                            train: row.train!,
                            onTap: () => _track(row.train!),
                            boardingCode: widget.from.code,
                            highlightDate: _effectiveDate,
                            autoFetchPlatform:
                                row.cardIndex < _kAutoPlatformLookups,
                          ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildSplitJourneyFallback(BuildContext context, GlassTheme g) {
    return FutureBuilder<List<SplitJourneyCombo>>(
      future: ref.read(splitJourneyServiceProvider).findSplitJourneys(
            from: widget.from,
            to: widget.to,
            date: _effectiveDate,
          ),
      builder: (ctx, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: GlassTheme.accentViolet),
                const SizedBox(height: 16),
                Text(
                  'No direct tickets — searching split journeys via junctions…',
                  textAlign: TextAlign.center,
                  style: AppText.label.copyWith(
                    color: g.textSecondary,
                    fontSize: 13.5,
                  ),
                ),
              ],
            ),
          );
        }

        final combos = snapshot.data ?? const <SplitJourneyCombo>[];
        if (combos.isEmpty) {
          return _message(
            Icons.search_off_rounded,
            'No direct trains or split routes found for ${widget.from.code} → ${widget.to.code}',
            g.textSecondary,
          );
        }

        final tightCount = combos.where((c) => c.isTightConnection).length;
        final visibleCombos = _showTightConnections
            ? combos
            : combos.where((c) => !c.isTightConnection).toList();

        return ListView.builder(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 130),
          itemCount: visibleCombos.length + 1,
          itemBuilder: (ctx, idx) {
            if (idx == 0) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      'NO DIRECT TICKETS — TRY A SPLIT JOURNEY',
                      style: AppText.overline.copyWith(color: GlassTheme.accentViolet),
                    ),
                  ),
                  SplitJourneyDisclaimer(
                    tightCount: tightCount,
                    showTightConnections: _showTightConnections,
                    onToggleTightConnections: (val) {
                      setState(() => _showTightConnections = val);
                    },
                  ),
                ],
              );
            }
            final combo = visibleCombos[idx - 1];
            return SplitJourneyCard(
              combo: combo,
              onTap: () {
                Haptics.tap();
                Navigator.of(context).push(
                  CupertinoPageRoute(
                    builder: (_) => LiveTrackingScreen(train: combo.leg1),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _errorState(Object? err) {
    final g = context.glass;
    final quota = err is RailKitException && err.isQuota;
    final message = quota
        ? 'Live railway data is temporarily unavailable — the monthly request '
            'limit was reached. Please check back later.'
        : err is RapidApiException
            ? err.message
            : L10n.of(context).unableToFetchRoute;
    return _message(
      quota ? Icons.hourglass_bottom_rounded : Icons.cloud_off_rounded,
      message,
      quota ? g.statusPurple : g.statusRed,
    );
  }

  Widget _message(IconData icon, String text, Color tint) {
    final g = context.glass;
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 120),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: tint),
            const SizedBox(height: 14),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: g.textPrimary,
                fontSize: 14.5,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 5) Report missing train link
  // ---------------------------------------------------------------------------
  Widget _reportMissingLink() {
    final g = context.glass;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Column(
        children: [
          Text(
            'Cannot find the train you are looking for?',
            textAlign: TextAlign.center,
            style: AppText.label.copyWith(color: g.textMuted, fontSize: 12.5),
          ),
          const SizedBox(height: 4),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _reportMissing,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
              child: Text(
                'Report missing train',
                style: TextStyle(
                  color: GlassTheme.accentIndigo,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 6) Sticky bottom bar
  // ---------------------------------------------------------------------------
  Widget _bottomBar() {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 12 + bottomInset),
      child: GlassContainer(
        radius: 26,
        blurSigma: 22,
        strong: true,
        glow: true,
        padding: const EdgeInsets.all(8),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          // No seat/availability data exists in the current source — see report.
          onTap: () => _notAvailable(
            'Seat availability needs a booking data source we don\'t have yet.',
          ),
          child: Container(
            height: 50,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: GlassTheme.accent,
              borderRadius: BorderRadius.circular(999),
              boxShadow: [
                BoxShadow(
                  color: GlassTheme.accentIndigo.withValues(alpha: 0.40),
                  blurRadius: 18,
                  spreadRadius: -3,
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.event_seat_rounded,
                    size: 18, color: Colors.white),
                const SizedBox(width: 8),
                Text(
                  'Check seat availability',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// How many cards fetch their platform automatically.
///
/// QUOTA: each platform lookup is one `getTrainInfo` request (cached 24h after
/// the first). A 9-train result set fetching all of them would spend 9 of the
/// 50 free-tier requests per month on a single search. So only the top few
/// auto-load; the rest fetch on tap.
const int _kAutoPlatformLookups = 2;

/// One flattened list entry: either a route band ([train] == null) or a card.
class _Row {
  const _Row.header(this.fromCode, this.fromName, this.toCode, this.toName)
      : train = null,
        cardIndex = -1;
  const _Row.card(
    TrainSummary this.train,
    this.fromCode,
    this.fromName,
    this.toCode,
    this.toName,
    this.cardIndex,
  );

  final TrainSummary? train;
  final String fromCode;
  final String fromName;
  final String toCode;
  final String toName;

  /// Position among CARDS only (headers excluded), used for the auto-fetch cap.
  final int cardIndex;
}

/// Flattens results into `[band, card, card, band, card, …]`.
///
/// Searching for "SBC" legitimately returns the whole Bengaluru terminal cluster
/// (SMVB, YPR, KJM) — confirmed in the live payload — so each distinct
/// origin/destination pair gets its own band instead of being silently merged.
List<_Row> _groupByLeg(List<TrainSummary> trains) {
  final order = <String>[];
  final byLeg = <String, List<TrainSummary>>{};
  for (final t in trains) {
    final key = '${t.fromCode}|${t.toCode}';
    if (!byLeg.containsKey(key)) {
      byLeg[key] = [];
      order.add(key);
    }
    byLeg[key]!.add(t);
  }

  final rows = <_Row>[];
  var cardIndex = 0;
  for (final key in order) {
    final group = byLeg[key]!;
    final first = group.first;
    rows.add(_Row.header(
      first.fromCode,
      first.fromName,
      first.toCode,
      first.toName,
    ));
    for (final t in group) {
      rows.add(_Row.card(
        t,
        t.fromCode,
        t.fromName,
        t.toCode,
        t.toName,
        cardIndex++,
      ));
    }
  }
  return rows;
}

/// 3) Route band: `KYJ Kayankulam  →  SBC Ksr Bengaluru`.
class RouteHeaderBand extends StatelessWidget {
  const RouteHeaderBand({
    super.key,
    required this.fromCode,
    required this.fromName,
    required this.toCode,
    required this.toName,
  });

  final String fromCode;
  final String fromName;
  final String toCode;
  final String toName;

  @override
  Widget build(BuildContext context) {
    final g = context.glass;
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 12),
      child: GlassContainer(
        radius: 16,
        // Nested inside a scrolling list: glass-lite avoids stacking a
        // BackdropFilter per band.
        blurSigma: 0,
        strong: true,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Expanded(child: _end(g, fromCode, fromName, TextAlign.left)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Icon(Icons.arrow_forward_rounded,
                  size: 16, color: GlassTheme.accentIndigo),
            ),
            Expanded(child: _end(g, toCode, toName, TextAlign.right)),
          ],
        ),
      ),
    );
  }

  Widget _end(GlassTheme g, String code, String name, TextAlign align) {
    final right = align == TextAlign.right;
    return Column(
      crossAxisAlignment:
          right ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          code,
          style: AppText.titleStrong.copyWith(
            color: g.textPrimary,
            fontSize: 15,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: align,
          style: AppText.label.copyWith(color: g.textMuted, fontSize: 11.5),
        ),
      ],
    );
  }
}

/// 2) Pill-shaped filter control.
class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.icon,
    required this.onTap,
    this.active = false,
    this.unavailable = false,
    this.trailingChevron = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  /// Filter is doing something (accent tint).
  final bool active;

  /// No data source behind it — dimmed with an info marker, never a dead
  /// control that silently does nothing.
  final bool unavailable;

  final bool trailingChevron;

  @override
  Widget build(BuildContext context) {
    final g = context.glass;
    final tint = active && !unavailable
        ? GlassTheme.accentIndigo
        : g.textSecondary;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Opacity(
        opacity: unavailable ? 0.55 : 1,
        child: GlassContainer(
          pill: true,
          blurSigma: 0,
          strong: active && !unavailable,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: tint),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: active && !unavailable ? g.textPrimary : tint,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (unavailable) ...[
                const SizedBox(width: 3),
                Icon(Icons.info_outline_rounded, size: 11, color: tint),
              ] else if (trailingChevron) ...[
                const SizedBox(width: 2),
                Icon(Icons.expand_more_rounded, size: 14, color: tint),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 4) Result card.
class _TrainCard extends StatelessWidget {
  const _TrainCard({
    required this.train,
    required this.onTap,
    required this.boardingCode,
    this.highlightDate,
    this.autoFetchPlatform = false,
  });

  final TrainSummary train;
  final VoidCallback onTap;

  /// The FROM station the user picked — the platform shown is the one they
  /// actually board at, not the train's origin.
  final String boardingCode;

  /// Which day the running-days row should mark as selected.
  final DateTime? highlightDate;

  /// Whether to look the platform up immediately (see [_kAutoPlatformLookups]).
  final bool autoFetchPlatform;

  @override
  Widget build(BuildContext context) {
    final g = context.glass;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: GlassTheme.accentViolet
                    .withValues(alpha: g.isDark ? 0.30 : 0.18),
                blurRadius: 44,
                spreadRadius: -6,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: GlassSurface(
            radius: 20,
            blur: 20,
            strong: true,
            glow: true,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StaticRouteMapVisual(
                  trainNumber: train.number,
                  fromCode: train.fromCode,
                  toCode: train.toCode,
                  height: 130,
                ),
                // Train number badge, left-aligned.
                Row(
                  children: [
                    TrainNumberTag(train.number, fontSize: 13),
                    const Spacer(),
                    Text(
                      train.type,
                      style: AppText.label
                          .copyWith(color: g.textMuted, fontSize: 11.5),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Departure → duration → arrival, one row.
                JourneyDurationBar(
                  departure: train.departure,
                  arrival: train.arrival,
                  duration: train.duration,
                  arrivalDayOffset: train.arrivalDayOffset,
                ),
                const SizedBox(height: 12),

                // Train name below the times.
                Text(
                  train.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: g.textPrimary,
                    fontSize: 15,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),

                // "Runs Daily", or the S M T W T F S row from RailKit's real
                // running_days mask.
                RunningDaysRow(train: train, highlightDate: highlightDate),
                const SizedBox(height: 12),

                Row(
                  children: [
                    _PlatformChip(
                      trainNumber: train.number,
                      stationCode: boardingCode,
                      autoFetch: autoFetchPlatform,
                    ),
                    const SizedBox(width: 8),
                    _chipStatic(g, L10n.of(context).liveGps),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Widget _chipStatic(
    GlassTheme g,
    String label, {
    Color? accent,
    Widget? trailing,
  }) {
    final on = accent ?? g.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: accent == null
            ? g.fillStrong
            : accent.withValues(alpha: g.isDark ? 0.18 : 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: accent == null
              ? g.border.withValues(alpha: 0.15)
              : accent.withValues(alpha: 0.40),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: on,
              fontSize: 11,
              fontWeight: accent == null ? FontWeight.w600 : FontWeight.w700,
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 5),
            trailing,
          ],
        ],
      ),
    );
  }
}

/// Shows the REAL boarding platform for this train at the user's FROM station.
///
/// Falls back to "Platform TBA" whenever the number genuinely isn't known
/// (no backend configured, request failed, or the railway publishes none) —
/// it never guesses a number.
///
/// QUOTA: when [autoFetch] is false the lookup is deferred until the user taps
/// the chip, so a long result list doesn't spend one RailKit request per card.
class _PlatformChip extends ConsumerStatefulWidget {
  const _PlatformChip({
    required this.trainNumber,
    required this.stationCode,
    required this.autoFetch,
  });

  final String trainNumber;
  final String stationCode;
  final bool autoFetch;

  @override
  ConsumerState<_PlatformChip> createState() => _PlatformChipState();
}

class _PlatformChipState extends ConsumerState<_PlatformChip> {
  bool _requested = false;

  bool get _active => widget.autoFetch || _requested;

  @override
  Widget build(BuildContext context) {
    final g = context.glass;
    final t = L10n.of(context);

    if (!_active) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          Haptics.tap();
          setState(() => _requested = true);
        },
        child: _TrainCard._chipStatic(
          g,
          t.platformTba,
          trailing: Icon(Icons.touch_app_rounded, size: 12, color: g.textMuted),
        ),
      );
    }

    final async = ref.watch(stationPlatformProvider(
      PlatformQuery(
        trainNumber: widget.trainNumber,
        stationCode: widget.stationCode,
      ),
    ));

    return async.when(
      loading: () => _TrainCard._chipStatic(g, '${t.platformTba}…'),
      error: (_, _) => _TrainCard._chipStatic(g, t.platformTba),
      data: (pf) => pf == null
          ? _TrainCard._chipStatic(g, t.platformTba)
          : _TrainCard._chipStatic(
              g,
              t.platformNumber(pf),
              accent: GlassTheme.accentBlue,
            ),
    );
  }
}

// ===========================================================================
// Date filter bottom sheet
// ===========================================================================

/// Radio-style date filter, in the established glass sheet pattern (grab handle,
/// radius 28, blur 24, strong + glow) used by the language picker and the phone
/// verification sheet.
Future<_DateFilter?> _showDateFilterSheet(
  BuildContext context, {
  required String originName,
  required _DateFilter current,
}) {
  return showModalBottomSheet<_DateFilter>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    isScrollControlled: true,
    builder: (ctx) => _DateFilterSheet(originName: originName, current: current),
  );
}

class _DateFilterSheet extends StatefulWidget {
  const _DateFilterSheet({required this.originName, required this.current});

  final String originName;
  final _DateFilter current;

  @override
  State<_DateFilterSheet> createState() => _DateFilterSheetState();
}

class _DateFilterSheetState extends State<_DateFilterSheet> {
  late _DateFilter _selected = widget.current;

  @override
  Widget build(BuildContext context) {
    final g = context.glass;
    final media = MediaQuery.of(context);

    return Padding
      (padding: EdgeInsets.only(
        left: 12,
        right: 12,
        bottom: 12 + media.viewPadding.bottom,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: media.size.height * 0.86),
        child: GlassContainer(
          radius: 28,
          blurSigma: 24,
          strong: true,
          glow: true,
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: g.textMuted.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Choose the date when the train starts from '
                '${widget.originName}',
                style: AppText.titleStrong.copyWith(
                  color: g.textPrimary,
                  fontSize: 17,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 16),
              _option(g, _DateFilter.allDates, 'All Dates'),
              _option(g, _DateFilter.today, 'Today'),
              _option(g, _DateFilter.tomorrow, 'Tomorrow'),
              _option(g, _DateFilter.calendar, 'Choose from Calendar'),
              const SizedBox(height: 14),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  height: 50,
                  width: double.infinity,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: g.fill,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: g.border.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      color: g.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _option(GlassTheme g, _DateFilter value, String label) {
    final selected = _selected == value;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Haptics.selection();
        setState(() => _selected = value);
        // Single select: choosing an option IS the action.
        Navigator.of(context).pop(value);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 21,
              height: 21,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected
                      ? GlassTheme.accentIndigo
                      : g.textMuted.withValues(alpha: 0.7),
                  width: 2,
                ),
              ),
              child: selected
                  ? Center(
                      child: Container(
                        width: 11,
                        height: 11,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: GlassTheme.accent,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: g.textPrimary,
                  fontSize: 15,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ),
            if (value == _DateFilter.calendar)
              Icon(Icons.calendar_month_rounded,
                  size: 18, color: g.textMuted),
          ],
        ),
      ),
    );
  }
}
