import 'dart:ui' show lerpDouble;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';

import '../data/language_controller.dart';
import '../data/nearest_station_service.dart';
import '../data/recent_trains_service.dart';
import '../data/train_repository.dart';
import '../l10n/app_localizations.dart';
import '../models/rail_station.dart';
import '../models/train_summary.dart';
import '../theme/app_colors.dart';
import '../theme/glass_theme.dart';
import '../utils/haptics.dart';
import '../widgets/glass.dart';
import '../widgets/glass_surface.dart';
import '../widgets/language_picker_sheet.dart';
import '../widgets/liquid_glass_button.dart';
import '../widgets/mesh_background.dart';
import '../widgets/train_number_tag.dart';
import 'live_tracking_screen.dart';
import 'pnr_status_screen.dart';
import 'settings_screen.dart';
import 'station_picker_screen.dart';
import 'train_results_screen.dart';

/// Which way the user is searching on the Track tab.
enum _SearchMode { route, number }

/// One spacing constant for the whole search block (toggle → FROM → TO →
/// Search → chips) so every gap is uniform.
const double _kSearchGap = 14;

/// Fixed height for the FROM/TO fields so the swap button can be centered
/// exactly on the seam between them (no guessed pixel offset).
const double _kFieldHeight = 60;

bool _isOnTime(TrainSummary t) => true;

String _tier(TrainSummary t) {
  final s = t.type.toLowerCase();
  if (['rajdhani', 'shatabdi', 'duronto', 'superfast', 'sf', 'vande']
      .any(s.contains)) {
    return 'Superfast';
  }
  if (s.contains('mail') || s.contains('express')) return 'Express';
  return 'Passenger';
}

List<String> _tags(TrainSummary t, L10n l) {
  final h = t.number.hashCode.abs();
  return [
    h % 2 == 0 ? l.acThreeTier : l.acTwoTier,
    if (h % 3 != 0) l.pantry,
    l.liveGps,
  ];
}

/// The app's home: a glassmorphic browse-and-track surface with a floating
/// glass dock. Tabs swap via [IndexedStack] (iOS-style, no page slide); every
/// color reads from [GlassTheme] so it renders in both light and dark.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  // Dual-mode search state.
  _SearchMode _mode = _SearchMode.route;
  RailStation? _fromStation = const RailStation(code: 'KYJ', name: 'Kayankulam Jn');
  RailStation? _toStation = const RailStation(code: 'SBC', name: 'KSR Bengaluru');
  final TextEditingController _numberCtrl = TextEditingController();

  /// Nearest-station pill state. Null until the user taps it.
  RailStation? _nearestStation;
  String? _nearestDistance;
  bool _locatingNearest = false;
  String _numberQuery = '';

  int _row1 = 0; // All Trains
  String? _row2; // no type filter
  int _navIndex = 0;

  /// Row-2 filter keys. Labels are localized at build time; the KEY stays
  /// English so the filtering logic never depends on the display language.
  static const _row2Keys = [
    'Express',
    'Superfast',
    'Passenger',
    'On Time',
    'Delayed',
  ];

  List<String> _row1Labels(L10n t) => [
        t.filterAllTrains,
        t.filterNearby,
        t.filterRunningStatus,
        t.filterPnrStatus,
        t.filterLiveMap,
      ];

  String _row2Label(L10n t, String key) => switch (key) {
        'Express' => t.filterExpress,
        'Superfast' => t.filterSuperfast,
        'Passenger' => t.filterPassenger,
        'On Time' => t.filterOnTime,
        'Delayed' => t.filterDelayed,
        _ => key,
      };

  @override
  void initState() {
    super.initState();
    // Train-number mode filters the list live as digits are typed.
    _numberCtrl.addListener(() {
      if (_numberCtrl.text != _numberQuery) {
        setState(() => _numberQuery = _numberCtrl.text);
      }
    });
    _maybeAskLanguage();
  }

  /// First launch only: ask for a language once, then never again (the choice
  /// is persisted; it can be changed later in Settings → Language).
  void _maybeAskLanguage() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (ref.read(languageProvider.notifier).hasChosen) return;
      await showLanguagePickerSheet(context, firstLaunch: true);
    });
  }

  @override
  void dispose() {
    _numberCtrl.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Data
  // -------------------------------------------------------------------------
  /// Trains the user has opened before, newest first.
  List<TrainSummary> get _recentTrains => ref.watch(recentTrainsProvider);

  bool get _hasSearched {
    if (_mode == _SearchMode.number) {
      return _numberQuery.trim().isNotEmpty;
    }
    // Route mode now lists RECENT trains, so the section appears whenever there
    // is history — not only after a search. Full results live on the dedicated
    // results screen that "Search Trains" pushes.
    return _recentTrains.isNotEmpty;
  }

  List<TrainSummary> get _visible {
    List<TrainSummary> list;
    if (_mode == _SearchMode.number) {
      final q = _numberQuery.trim().toLowerCase();
      list = q.isEmpty
          ? const []
          : trainRepository.searchByNumberOrName(q);
    } else {
      list = _recentTrains;
    }

    // Category chips (Express/Superfast/…) refine whichever mode is active.
    switch (_row2) {
      case 'Express':
        list = list.where((t) => _tier(t) == 'Express').toList();
      case 'Superfast':
        list = list.where((t) => _tier(t) == 'Superfast').toList();
      case 'Passenger':
        list = list.where((t) => _tier(t) == 'Passenger').toList();
      case 'On Time':
        list = list.where(_isOnTime).toList();
      case 'Delayed':
        list = list.where((t) => !_isOnTime(t)).toList();
    }
    return list;
  }

  String _listHeaderText(L10n t, int count) {
    if (_mode == _SearchMode.route) {
      // Reuses the existing `sectionRecent` key, already translated into all 13
      // locales, so this adds no untranslated string.
      return '${t.sectionRecent} · $count';
    }
    if (_mode == _SearchMode.number && _numberQuery.trim().isNotEmpty) {
      return t.countMatching(count, _numberQuery.trim());
    }
    switch (_row1) {
      case 1:
        return t.countNearYou(count);
      case 2:
        return t.countRunning(count);
      default:
        return t.countDepartures(count);
    }
  }

  // -------------------------------------------------------------------------
  // Actions
  // -------------------------------------------------------------------------
  void _openTracking(TrainSummary t) {
    FocusManager.instance.primaryFocus?.unfocus();
    // Opening a train is what makes it "recent".
    ref.read(recentTrainsProvider.notifier).add(t);
    Navigator.of(context).push(
      CupertinoPageRoute(builder: (_) => LiveTrackingScreen(train: t)),
    );
  }

  // -------- Dual-mode search actions --------
  void _setMode(_SearchMode m) {
    if (m == _mode) return;
    Haptics.selection();
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _mode = m);
  }

  Future<void> _pickStation(bool isFrom) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final result = await Navigator.of(context).push<RailStation>(
      CupertinoPageRoute(
        builder: (_) => StationPickerScreen(
          title: isFrom ? 'Select origin' : 'Select destination',
          excludeCode: isFrom ? _toStation?.code : _fromStation?.code,
        ),
      ),
    );
    if (result == null) return;
    setState(() {
      if (isFrom) {
        _fromStation = result;
      } else {
        _toStation = result;
      }
    });
  }

  void _swapStations() {
    setState(() {
      final tmp = _fromStation;
      _fromStation = _toStation;
      _toStation = tmp;
    });
  }

  void _runRouteSearch() {
    debugPrint('[HomeScreen] _runRouteSearch FIRED! from=$_fromStation to=$_toStation');
    Haptics.tap();
    FocusManager.instance.primaryFocus?.unfocus();

    final from = _fromStation;
    final to = _toStation;

    if (from == null || to == null) {
      debugPrint('[HomeScreen] Aborted: from=$from to=$to');
      return;
    }

    debugPrint('[HomeScreen] Navigating to TrainResultsScreen: ${from.code} → ${to.code}');

    Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (_) => TrainResultsScreen(
          from: from,
          to: to,
          date: DateTime.now(),
        ),
      ),
    );

    // No fetch here any more. The home list shows RECENT trains, and the
    // results screen we just pushed does its own (cached, quota-counted) fetch.
    // This used to duplicate that call, costing 2 of the 50 monthly RailKit
    // requests per search until the in-flight de-dupe collapsed them into 1;
    // now it costs exactly 1.
  }

  void _onRow1(int i) {
    Haptics.selection();
    if (i == 3) {
      setState(() => _navIndex = 1); // switch to PNR tab (no page slide)
      return;
    }
    if (i == 4) {
      _openTracking(TrainRepository.catalog.first); // Live map = detail push
      return;
    }
    setState(() => _row1 = i);
  }

  void _onRow2(String label) {
    Haptics.selection();
    setState(() => _row2 = _row2 == label ? null : label);
  }

  // Dock tab switch: swap content in place (IndexedStack), never push a route.
  void _onNav(int i) {
    if (i == _navIndex) return;
    Haptics.tap();
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _navIndex = i);
  }

  void _openBookingSheet() {
    Haptics.tap();
    showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(L10n.of(ctx).bookSheetTitle),
        message: const Text(
          'Ticket booking happens on the official IRCTC portal.',
        ),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(ctx).pop();
              _showToast(L10n.of(context).bookOpening);
            },
            child: const Text('Continue to IRCTC'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(L10n.of(ctx).cancel),
        ),
      ),
    );
  }

  /// Brief slide-up + fade toast (not Material's slide-from-bottom SnackBar).
  void _showToast(String message) {
    final overlay = Overlay.of(context);
    final g = context.glass;
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _Toast(
        message: message,
        glass: g,
        onDone: entry.remove,
      ),
    );
    overlay.insert(entry);
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final g = context.glass;

    return Scaffold(
      extendBody: true,
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          const Positioned.fill(child: MeshBackground()),
          Positioned.fill(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 240),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeInOut,
                  ),
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.97, end: 1.0).animate(
                      CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeOutCubic,
                      ),
                    ),
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.015),
                        end: Offset.zero,
                      ).animate(
                        CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeOutCubic,
                        ),
                      ),
                      child: child,
                    ),
                  ),
                );
              },
              child: KeyedSubtree(
                key: ValueKey<int>(_navIndex),
                child: switch (_navIndex) {
                  0 => _trackTab(g),
                  1 => const PnrStatusScreen(embedded: true),
                  2 => _bookTab(g),
                  _ => const SettingsScreen(embedded: true),
                },
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(top: false, child: _dock(g)),
          ),
        ],
      ),
    );
  }

  // -------- Track tab (browse + search + filters + list) --------
  Widget _trackTab(GlassTheme g) {
    final trains = _visible;
    final searched = _hasSearched;

    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 0),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _topBar(g),
                  const SizedBox(height: 22),
                  _hero(g),
                  const SizedBox(height: 20),
                  _buildSearch(g),
                  const SizedBox(height: _kSearchGap),
                  _chipRow(_row1Labels(L10n.of(context)), isRow1: true),
                  const SizedBox(height: 10),
                  _chipRow(
                    [
                      for (final k in _row2Keys)
                        _row2Label(L10n.of(context), k),
                    ],
                    isRow1: false,
                    keys: _row2Keys,
                  ),
                  if (searched && trains.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _listHeader(g, trains.length),
                    const SizedBox(height: 14),
                  ],
                ],
              ),
            ),
          ),
          if (searched && trains.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 120),
              sliver: SliverToBoxAdapter(child: _results(g, trains)),
            )
          else if (searched && trains.isEmpty)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 20, 18, 120),
              sliver: SliverToBoxAdapter(child: _emptyState(g)),
            )
          else
            const SliverPadding(
              padding: EdgeInsets.only(bottom: 120),
              sliver: SliverToBoxAdapter(child: SizedBox.shrink()),
            ),
        ],
      ),
    );
  }

  // List reflows smoothly (fade + height) when filters/tabs change rather than
  // snapping to a new list. Live search updates in place (stays responsive).
  Widget _results(GlassTheme g, List<TrainSummary> trains) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.02),
              end: Offset.zero,
            ).animate(anim),
            child: child,
          ),
        ),
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.topCenter,
          children: [
            ...previous,
            ?current,
          ],
        ),
        child: KeyedSubtree(
          // Keyed on the list identity so the stagger replays when the recents
          // change (a newly opened train jumps to the front).
          key: ValueKey('$_mode|$_row1|${_row2 ?? '-'}|'
              '${trains.length}|${trains.isEmpty ? '' : trains.first.number}'),
          child: trains.isEmpty
              ? _emptyState(g)
              : AnimationLimiter(
                  child: Column(
                    children: AnimationConfiguration.toStaggeredList(
                      duration: const Duration(milliseconds: 380),
                      delay: const Duration(milliseconds: 50),
                      childAnimationBuilder: (child) => SlideAnimation(
                        verticalOffset: 26,
                        curve: Curves.easeOutCubic,
                        child: FadeInAnimation(child: child),
                      ),
                      children: [
                        for (final t in trains)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: _TrainCard(
                              train: t,
                              onTap: () => _openTracking(t),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  // -------- Book tab --------
  Widget _bookTab(GlassTheme g) {
    return SafeArea(
      bottom: false,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 120),
          child: GlassSurface(
            radius: 26,
            blur: 22,
            glow: true,
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 66,
                  height: 66,
                  decoration: BoxDecoration(
                    gradient: GlassTheme.accent,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: GlassTheme.accentIndigo.withValues(alpha: 0.5),
                        blurRadius: 20,
                        spreadRadius: -2,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.book_online_rounded,
                      size: 30, color: Colors.white),
                ),
                const SizedBox(height: 18),
                Text(
                  L10n.of(context).bookTitle,
                  style: TextStyle(
                    color: g.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  L10n.of(context).bookBody,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: g.textSecondary,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 22),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _openBookingSheet,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 22, vertical: 14),
                    decoration: BoxDecoration(
                      gradient: GlassTheme.accent,
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: [
                        BoxShadow(
                          color: GlassTheme.accentIndigo.withValues(alpha: 0.5),
                          blurRadius: 18,
                          spreadRadius: -3,
                        ),
                      ],
                    ),
                    child: Text(
                      L10n.of(context).bookCta,
                      style: const TextStyle(
                        color: Colors.white,
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
      ),
    );
  }

  // -------- Top bar --------
  /// Resolves the user's nearest station and shows it in the top-right pill.
  ///
  /// Location is requested here and nowhere else, so the prompt always follows
  /// an explicit tap. Lookup is fully local (bundled coordinates) — no API call,
  /// no quota.
  Future<void> _findNearestStation() async {
    if (_locatingNearest) return;
    Haptics.tap();
    setState(() => _locatingNearest = true);

    final result = await ref.read(nearestStationServiceProvider).find();
    if (!mounted) return;

    switch (result) {
      case NearestStationFound(:final station, :final distanceLabel):
        setState(() {
          _locatingNearest = false;
          _nearestStation = station;
          _nearestDistance = distanceLabel;
        });
        _showToast('Nearest station: ${station.name} '
            '(${station.code}) · $distanceLabel away');
      case NearestStationFailure(:final message):
        setState(() => _locatingNearest = false);
        _showToast(message);
    }
  }

  Widget _topBar(GlassTheme g) {
    return Row(
      children: [
        GlassSurface(
          radius: 15,
          blur: 18,
          compact: true,
          padding: const EdgeInsets.all(9),
          child: ShaderMask(
            shaderCallback: (r) => const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [GlassTheme.accentViolet, GlassTheme.accentBlue],
            ).createShader(r),
            child: const Icon(Icons.train_rounded, size: 26, color: Colors.white),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          'My Train',
          style: TextStyle(
            color: g.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
          ),
        ),
        const Spacer(),
        // Constrained so a long station name can't shove the title off-screen.
        Flexible(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _findNearestStation,
            child: GlassSurface(
              radius: 999,
              blur: 18,
              pill: true,
              compact: true,
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_locatingNearest)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation(GlassTheme.accentViolet),
                      ),
                    )
                  else
                    const Icon(Icons.location_on_rounded,
                        size: 15, color: GlassTheme.accentViolet),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      _locatingNearest
                          ? 'Locating…'
                          // Once resolved, the pill becomes the answer.
                          : (_nearestStation?.name ??
                              L10n.of(context).nearestStation),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: g.textPrimary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (!_locatingNearest && _nearestDistance != null) ...[
                    const SizedBox(width: 5),
                    Text(
                      _nearestDistance!,
                      style: TextStyle(
                        color: g.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // -------- Hero --------
  Widget _hero(GlassTheme g) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          L10n.of(context).heroTitle,
          style: TextStyle(
            color: g.textPrimary,
            fontSize: 30,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
            height: 1.08,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          L10n.of(context).heroSubtitle,
          style: TextStyle(
            color: g.textSecondary,
            fontSize: 14.5,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  // -------- Dual-mode search (toggle + route / number inputs) --------
  Widget _buildSearch(GlassTheme g) {
    return Column(
      children: [
        _SearchModeToggle(mode: _mode, onChanged: _setMode),
        const SizedBox(height: _kSearchGap),
        // Height + opacity ease between the two modes (no instant swap).
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, anim) =>
                FadeTransition(opacity: anim, child: child),
            // Route mode shows station fields; number mode shows text input.
            // The Search button is OUTSIDE this switcher so it's never blocked.
            child: _mode == _SearchMode.route
                ? _routeFields(g)
                : _SearchBar(
                    key: const ValueKey('number'),
                    controller: _numberCtrl,
                    icon: Icons.train_rounded,
                    hint: L10n.of(context).hintTrainNumber,
                    keyboardType: TextInputType.number,
                  ),
          ),
        ),
        // Search button is ALWAYS outside the AnimatedSwitcher so it can
        // never be blocked by the fading-out old child's hit-test area.
        if (_mode == _SearchMode.route) ...[
          const SizedBox(height: _kSearchGap),
          _searchTrainsButton(g),
        ],
      ],
    );
  }

  /// Just the FROM/TO station fields + swap button (no search button).
  Widget _routeFields(GlassTheme g) {
    return Stack(
      key: const ValueKey('route'),
      children: [
        Column(
          children: [
            _stationField(g, isFrom: true),
            const SizedBox(height: _kSearchGap),
            _stationField(g, isFrom: false),
          ],
        ),
        Positioned.fill(
          child: Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _SwapButton(onTap: _swapStations),
            ),
          ),
        ),
      ],
    );
  }

  Widget _stationField(GlassTheme g, {required bool isFrom}) {
    final t = L10n.of(context);
    final station = isFrom ? _fromStation : _toStation;
    final label = isFrom ? t.fieldFrom : t.fieldTo;
    final icon = isFrom ? Icons.trip_origin_rounded : Icons.place_rounded;
    final iconColor =
        isFrom ? GlassTheme.accentViolet : GlassTheme.accentBlue;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _pickStation(isFrom),
      child: GlassSurface(
        radius: 18,
        blur: 20,
        strong: true,
        compact: true,
        padding: const EdgeInsets.fromLTRB(16, 0, 54, 0),
        child: SizedBox(
          height: _kFieldHeight,
          child: Row(
            children: [
              Icon(icon, size: 18, color: iconColor),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: g.textMuted,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.9,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      station == null
                          ? t.selectStation
                          : '${station.name} (${station.code})',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: station == null ? g.textMuted : g.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Primary CTA, on the shared Liquid Glass button.
  ///
  /// Was a hand-rolled `Ink` + flat gradient + Material ripple, which read as a
  /// solid plastic pill rather than glass. [LiquidGlassButton] brings the real
  /// recipe the rest of the app uses: backdrop blur with vibrancy, a specular
  /// top-edge rim, a squircle (continuous-corner) shape, a scale-down on press
  /// and a glow radiating from the tap point — plus the [GlassQuality] fallback
  /// that drops blur automatically on devices that can't keep up.
  Widget _searchTrainsButton(GlassTheme g) {
    return LiquidGlassButton(
      onPressed: _runRouteSearch,
      expand: true,
      // Pill, matching the shape it replaces. The squircle is applied inside.
      cornerRadius: 999,
      tint: AppColors.accent,
      // Indigo, matching the glow the old flat pill cast — AppColors.accent and
      // accentViolet are the same 0xFF8B5CF6, so tinting the glow with either
      // would be invisible against the fill.
      glowColor: GlassTheme.accentIndigo,
      padding: const EdgeInsets.symmetric(vertical: 16),
      semanticLabel: L10n.of(context).searchTrains,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.search_rounded, size: 19, color: Colors.white),
          const SizedBox(width: 9),
          Text(
            L10n.of(context).searchTrains,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  // -------- Filter chip row --------
  //
  // [keys] are stable English identifiers used by the filter logic; [labels]
  // are what the user sees in their language. Keeping them separate means
  // switching language never breaks filtering.
  Widget _chipRow(
    List<String> labels, {
    required bool isRow1,
    List<String>? keys,
  }) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: labels.length,
        separatorBuilder: (_, _) => const SizedBox(width: 9),
        itemBuilder: (context, i) {
          final label = labels[i];
          final key = keys == null ? label : keys[i];
          final active = isRow1 ? _row1 == i : _row2 == key;
          return _GlassChip(
            label: label,
            active: active,
            onTap: () => isRow1 ? _onRow1(i) : _onRow2(key),
          );
        },
      ),
    );
  }

  // -------- List header --------
  Widget _listHeader(GlassTheme g, int count) {
    final t = L10n.of(context);
    return Row(
      children: [
        // Count morphs smoothly rather than snapping.
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          transitionBuilder: (child, anim) =>
              FadeTransition(opacity: anim, child: child),
          child: Text(
            _listHeaderText(t, count),
            key: ValueKey(_listHeaderText(t, count)),
            style: TextStyle(
              color: g.textPrimary,
              fontSize: 16.5,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
        ),
        const Spacer(),
        Icon(Icons.tune_rounded, size: 18, color: g.textMuted),
      ],
    );
  }

  Widget _emptyState(GlassTheme g) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Icon(Icons.search_off_rounded, size: 40, color: g.textMuted),
          const SizedBox(height: 12),
          Text(
            L10n.of(context).noTrainsMatch,
            style: TextStyle(color: g.textSecondary, fontSize: 14),
          ),
        ],
      ),
    );
  }

  // -------- Floating glass dock --------
  Widget _dock(GlassTheme g) {
    final t = L10n.of(context);
    final items = [
      (Icons.my_location_rounded, t.navTrack),
      (Icons.confirmation_number_rounded, t.navPnr),
      (Icons.book_online_rounded, t.navBook),
      (Icons.person_rounded, t.navProfile),
    ];
    const n = 4;

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 12),
      child: GlassSurface(
        radius: 999,
        blur: 24,
        strong: true,
        glow: true,
        pill: true,
        compact: true,
        padding: const EdgeInsets.all(6),
        child: SizedBox(
          height: 58,
          child: Stack(
            children: [
              // Sliding active pill (iOS spring feel).
              AnimatedAlign(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                alignment: Alignment(-1 + 2 * (_navIndex / (n - 1)), 0),
                child: FractionallySizedBox(
                  widthFactor: 1 / n,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: GlassTheme.accent,
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: [
                        BoxShadow(
                          color: GlassTheme.accentIndigo.withValues(alpha: 0.5),
                          blurRadius: 16,
                          spreadRadius: -2,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Row(
                children: [
                  for (int i = 0; i < n; i++)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _onNav(i),
                        child: _dockItem(
                          g,
                          items[i].$1,
                          items[i].$2,
                          _navIndex == i,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dockItem(GlassTheme g, IconData icon, String label, bool active) {
    final color = active ? Colors.white : g.textSecondary;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Icon color eases between states rather than snapping.
        AnimatedScale(
          scale: active ? 1.08 : 1.0,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutBack,
          child: Icon(icon, size: 20, color: color),
        ),
        const SizedBox(height: 3),
        AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 220),
          style: TextStyle(
            color: color,
            fontSize: 10.5,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          ),
          child: Text(label),
        ),
      ],
    );
  }
}

// ===========================================================================
// Slide-up + fade toast (overlay), replacing Material's SnackBar
// ===========================================================================
class _Toast extends StatefulWidget {
  const _Toast({
    required this.message,
    required this.glass,
    required this.onDone,
  });

  final String message;
  final GlassTheme glass;
  final VoidCallback onDone;

  @override
  State<_Toast> createState() => _ToastState();
}

class _ToastState extends State<_Toast> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );

  @override
  void initState() {
    super.initState();
    _c.forward();
    _run();
  }

  Future<void> _run() async {
    await Future.delayed(const Duration(milliseconds: 2000));
    if (!mounted) return;
    await _c.reverse();
    widget.onDone();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 24,
      right: 24,
      bottom: 108,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final t = Curves.easeOutCubic.transform(_c.value);
            return Opacity(
              opacity: t,
              child: Transform.translate(
                offset: Offset(0, (1 - t) * 18),
                child: Center(
                  child: GlassSurface(
                    radius: 16,
                    blur: 22,
                    strong: true,
                    compact: true,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Text(
                      widget.message,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: widget.glass.textPrimary,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ===========================================================================
// Search bar (glass pill, subtly scales + glows on focus)
// ===========================================================================
class _SearchBar extends StatefulWidget {
  const _SearchBar({
    super.key,
    required this.controller,
    this.icon = Icons.search_rounded,
    this.hint = '',
    this.keyboardType,
  });
  final TextEditingController controller;
  final IconData icon;
  final String hint;
  final TextInputType? keyboardType;

  @override
  State<_SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends State<_SearchBar> {
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final g = context.glass;
    final focused = _focus.hasFocus;
    return AnimatedScale(
      scale: focused ? 1.015 : 1.0,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          boxShadow: focused
              ? [
                  BoxShadow(
                    color: GlassTheme.accentViolet.withValues(alpha: 0.42),
                    blurRadius: 26,
                    spreadRadius: -4,
                  ),
                ]
              : const [],
        ),
        child: GlassSurface(
          radius: 999,
          blur: 22,
          strong: focused,
          pill: true,
          compact: true,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            children: [
              Icon(widget.icon, size: 21, color: g.textSecondary),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  focusNode: _focus,
                  keyboardType: widget.keyboardType,
                  cursorColor: GlassTheme.accentViolet,
                  style: TextStyle(
                    color: g.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    // Empty hint => fall back to the generic localized hint.
                    hintText: widget.hint.isEmpty
                        ? L10n.of(context).hintSearchAny
                        : widget.hint,
                    hintStyle: TextStyle(
                      color: g.textMuted,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w500,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
              if (widget.controller.text.isNotEmpty)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => widget.controller.clear(),
                  child: Icon(Icons.close_rounded, size: 18, color: g.textSecondary),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// Search-mode segmented toggle (By Route | By Train No.) — a glass pill with
// a sliding violet gradient indicator, matching the dock's active pill.
// ===========================================================================
class _SearchModeToggle extends StatelessWidget {
  const _SearchModeToggle({required this.mode, required this.onChanged});

  final _SearchMode mode;
  final ValueChanged<_SearchMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final g = context.glass;
    final t = L10n.of(context);
    return GlassSurface(
      radius: 999,
      blur: 20,
      strong: true,
      pill: true,
      compact: true,
      padding: const EdgeInsets.all(4),
      child: SizedBox(
        height: 44,
        child: Stack(
          children: [
            // Sliding active indicator — sized to exactly half the width, with
            // an even 2px inset on ALL four sides so it reads as a symmetric
            // floating capsule (same radius every corner).
            AnimatedAlign(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              alignment: mode == _SearchMode.route
                  ? Alignment.centerLeft
                  : Alignment.centerRight,
              child: FractionallySizedBox(
                widthFactor: 0.5,
                heightFactor: 1.0,
                child: Container(
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    gradient: GlassTheme.accent,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [
                      BoxShadow(
                        color: GlassTheme.accentIndigo.withValues(alpha: 0.45),
                        blurRadius: 14,
                        spreadRadius: -3,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Row(
              children: [
                _segment(g, t.searchByRoute, Icons.alt_route_rounded,
                    _SearchMode.route),
                _segment(g, t.searchByTrainNo, Icons.confirmation_number_rounded,
                    _SearchMode.number),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _segment(GlassTheme g, String label, IconData icon, _SearchMode m) {
    final active = mode == m;
    final color = active
        ? Colors.white
        : (g.isDark
            ? Colors.white.withValues(alpha: 0.82)
            : g.textPrimary.withValues(alpha: 0.75));
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(m),
        child: Container(
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(icon, size: 17, color: color),
              const SizedBox(width: 8),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 220),
                style: TextStyle(
                  color: color,
                  fontSize: 13.5,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                  letterSpacing: -0.1,
                ),
                child: Text(label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// Circular glass swap button — rotates a half-turn on tap, then swaps From/To.
// ===========================================================================
class _SwapButton extends StatefulWidget {
  const _SwapButton({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_SwapButton> createState() => _SwapButtonState();
}

class _SwapButtonState extends State<_SwapButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _handle() {
    Haptics.selection();
    _c.forward(from: 0);
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _handle,
      child: RotationTransition(
        turns: Tween<double>(begin: 0, end: 0.5)
            .animate(CurvedAnimation(parent: _c, curve: Curves.easeOutBack)),
        child: GlassSurface(
          radius: 999,
          blur: 18,
          strong: true,
          pill: true,
          compact: true,
          padding: const EdgeInsets.all(9),
          child: const Icon(Icons.swap_vert_rounded,
              size: 20, color: GlassTheme.accentViolet),
        ),
      ),
    );
  }
}

// ===========================================================================
// Filter chip — animated color morph + spring scale (no instant rebuild)
// ===========================================================================
class _GlassChip extends StatelessWidget {
  const _GlassChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final g = context.glass;
    // Both states use a gradient so AnimatedContainer lerps smoothly between
    // the neutral translucent fill and the accent gradient.
    final inactiveFill = LinearGradient(colors: [g.fill, g.fill]);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedScale(
        scale: active ? 1.0 : 0.97,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutBack,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            gradient: active ? GlassTheme.accent : inactiveFill,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: active ? Colors.transparent : g.border,
            ),
            boxShadow: [
              BoxShadow(
                color: active
                    ? GlassTheme.accentIndigo.withValues(alpha: 0.5)
                    : Colors.transparent,
                blurRadius: 16,
                spreadRadius: -3,
              ),
            ],
          ),
          // Domed-glass sheen: bright specular at the top edge fading down to
          // a faint bottom inner shadow — baked into one gradient so it stays
          // clipped to the capsule and adds no widget nesting.
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white.withValues(alpha: g.isDark ? 0.12 : 0.18),
                Colors.white.withValues(alpha: 0.0),
                Colors.black.withValues(alpha: g.isDark ? 0.08 : 0.04),
              ],
              stops: const [0.0, 0.08, 1.0],
            ),
          ),
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 260),
            style: TextStyle(
              color: active ? Colors.white : g.textPrimary,
              fontSize: 13,
              fontWeight: active ? FontWeight.w700 : FontWeight.w600,
            ),
            child: Text(label),
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// Train card
// ===========================================================================
class _TrainCard extends StatelessWidget {
  const _TrainCard({required this.train, required this.onTap});
  final TrainSummary train;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final g = context.glass;
    final onTime = _isOnTime(train);
    final tags = _tags(train, L10n.of(context));

    return GlassCard(
      onTap: onTap,
      radius: 26,
      blur: 20,
      strong: true,
      glow: true,
      padding: EdgeInsets.zero,
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _RouteBanner(train: train, onTime: onTime),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      TrainNumberTag(train.number, fontSize: 14),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          train.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: g.textPrimary,
                            fontSize: 16.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _routeLine(g),
                  const SizedBox(height: 14),
                  Row(
                    children: [for (final t in tags) _tagChip(g, t)],
                  ),
                ],
              ),
            ),
          ],
        ),
    );
  }

  Widget _routeLine(GlassTheme g) {
    return Row(
      children: [
        const Icon(Icons.trip_origin_rounded, size: 13, color: GlassTheme.accentViolet),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            train.fromName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: g.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Icon(Icons.arrow_right_alt_rounded, size: 16, color: g.textMuted),
        ),
        const Icon(Icons.place_rounded, size: 13, color: GlassTheme.accentBlue),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            train.toName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: g.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _tagChip(GlassTheme g, String label) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      // Glass-lite (blur: 0) so it inherits the shared gradient rim without a
      // nested BackdropFilter inside the card's own blur.
      child: GlassSurface(
        radius: 999,
        blur: 0,
        strong: true,
        pill: true,
        compact: true,
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        child: Text(
          label,
          style: TextStyle(
            color: g.textPrimary,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// Animated route banner — colored gradient in BOTH modes, with a train icon
// gliding along a dotted line once on appear.
// ===========================================================================
const BorderRadius _bannerRadius =
    BorderRadius.vertical(top: Radius.circular(26));

class _RouteBanner extends StatefulWidget {
  const _RouteBanner({required this.train, required this.onTime});
  final TrainSummary train;
  final bool onTime;

  @override
  State<_RouteBanner> createState() => _RouteBannerState();
}

class _RouteBannerState extends State<_RouteBanner>
    with SingleTickerProviderStateMixin {
  // One-shot glide on appear (keeps the list light — no perpetual repaint).
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final g = context.glass;
    final t = L10n.of(context);
    final statusColor = AppColors.onTime;
    final statusText = t.scheduledDays(widget.train.daysLabel);
    final platformText = t.platformTba;

    return ClipRRect(
      borderRadius: _bannerRadius,
      child: BackdropFilter(
        filter: glassFilter(18, g.isDark),
        child: SizedBox(
          height: 104,
          child: Stack(
            children: [
              // Brand-tinted TRANSLUCENT glass (was a solid gradient): the
              // blurred backdrop shows through so it reads as tinted glass.
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        g.bannerColors.first.withValues(alpha: 0.60),
                        g.bannerColors.last.withValues(alpha: 0.52),
                      ],
                    ),
                  ),
                ),
              ),
              // Bottom inner shadow — glass thickness at the banner base.
              glassBottomInnerShadow(_bannerRadius, g.isDark),
              // Tight, bright specular streak on the top rim.
              glassSpecular(_bannerRadius, g.isDark),
              // Gradient rim light (bright top, faint bottom).
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: GlassRimPainter(
                      borderRadius: _bannerRadius,
                      dark: g.isDark,
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: LayoutBuilder(
                builder: (context, c) {
                  const padL = 26.0, padR = 26.0;
                  final y = c.maxHeight * 0.52;
                  return AnimatedBuilder(
                    animation: _c,
                    builder: (context, _) {
                      final p = Curves.easeInOut.transform(_c.value);
                      final x = lerpDouble(padL, c.maxWidth - padR, p * 0.72)!;
                      return Stack(
                        children: [
                          CustomPaint(
                            size: Size(c.maxWidth, c.maxHeight),
                            painter: _RoutePainter(padL: padL, padR: padR, y: y),
                          ),
                          Positioned(
                            left: x - 13,
                            top: y - 13,
                            child: Container(
                              width: 26,
                              height: 26,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.3),
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                              child: const Icon(Icons.train_rounded,
                                  size: 15, color: GlassTheme.accentIndigo),
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
            Positioned(
              top: 12,
              left: 12,
              child: _bannerPill(
                child: Text(
                  widget.train.type.toUpperCase(),
                  style: const TextStyle(
                    color: GlassTheme.onBanner,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: _bannerPill(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                          color: statusColor, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      statusText,
                      style: const TextStyle(
                        color: GlassTheme.onBanner,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              bottom: 12,
              left: 12,
              child: _bannerPill(
                child: Text(
                  platformText,
                  style: const TextStyle(
                    color: GlassTheme.onBanner,
                    fontSize: 11,
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

  // Frosted translucent pill sitting on the banner's glass (the banner's
  // BackdropFilter shows through the low-opacity fill), so it reads as glass,
  // not solid paint. Text stays white → a dark-tinted glass chip for contrast.
  Widget _bannerPill({required Widget child}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.34)),
      ),
      child: child,
    );
  }
}

class _RoutePainter extends CustomPainter {
  _RoutePainter({required this.padL, required this.padR, required this.y});
  final double padL;
  final double padR;
  final double y;

  @override
  void paint(Canvas canvas, Size size) {
    final end = size.width - padR;

    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    const dash = 6.0, gap = 6.0;
    double x = padL;
    while (x < end) {
      canvas.drawLine(Offset(x, y), Offset((x + dash).clamp(padL, end), y), line);
      x += dash + gap;
    }

    canvas.drawCircle(Offset(padL, y), 5, Paint()..color = Colors.white);
    canvas.drawCircle(
        Offset(end, y), 5, Paint()..color = const Color(0xFFB9C6FF));
  }

  @override
  bool shouldRepaint(_RoutePainter old) =>
      old.padL != padL || old.padR != padR || old.y != y;
}
