import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/train_repository.dart';
import '../models/rail_station.dart';
import '../models/train_summary.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../utils/haptics.dart';
import '../widgets/icon_action_button.dart';
import '../widgets/liquid_glass.dart';
import '../widgets/liquid_glass_button.dart';
import '../widgets/pressable.dart';
import 'live_tracking_screen.dart';
import 'pnr_status_screen.dart';
import 'settings_screen.dart';
import 'station_picker_screen.dart';
import 'train_results_screen.dart';

/// The app's home: find trains by route (FROM/TO over the full station list)
/// or by train number.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _mode = 0; // 0 = route, 1 = train number
  RailStation? _from;
  RailStation? _to;
  int _dateIndex = 0;
  bool _swapTurned = false;

  final TextEditingController _trainController = TextEditingController();
  String _trainQuery = '';

  late final List<DateTime> _dates = List.generate(
    5,
    (i) => DateTime.now().add(Duration(days: i)),
  );

  @override
  void initState() {
    super.initState();
    _trainController.addListener(() {
      if (_trainController.text != _trainQuery) {
        setState(() => _trainQuery = _trainController.text);
      }
    });
  }

  @override
  void dispose() {
    _trainController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Navigation / actions
  // ---------------------------------------------------------------------------
  Future<void> _openPicker({required bool isFrom}) async {
    final result = await Navigator.of(context).push<RailStation>(
      CupertinoPageRoute(
        builder: (_) => StationPickerScreen(
          title: isFrom ? 'Select origin' : 'Select destination',
          excludeCode: isFrom ? _to?.code : _from?.code,
        ),
      ),
    );
    if (result != null) {
      setState(() {
        if (isFrom) {
          _from = result;
        } else {
          _to = result;
        }
      });
    }
  }

  void _swap() {
    if (_from == null && _to == null) return;
    Haptics.tap();
    setState(() {
      final tmp = _from;
      _from = _to;
      _to = tmp;
      _swapTurned = !_swapTurned;
    });
  }

  void _searchRoute() {
    if (_from == null || _to == null) {
      Haptics.tap();
      _toast('Select both origin and destination');
      return;
    }
    Haptics.confirm();
    Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (_) => TrainResultsScreen(
          from: _from!,
          to: _to!,
          date: _dates[_dateIndex],
        ),
      ),
    );
  }

  void _trackNumber() {
    final number = _trainController.text.trim();
    if (number.isEmpty) {
      Haptics.tap();
      _toast('Enter a train number to track');
      return;
    }
    Haptics.confirm();
    _openTracking(trainRepository.resolveNumber(number));
  }

  void _openTracking(TrainSummary train) {
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (_) => LiveTrackingScreen(train: train),
      ),
    );
  }

  void _toast(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.surfaceElevated,
        elevation: 0,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppColors.lineMuted),
        ),
        content: Text(
          message,
          style: AppText.label.copyWith(color: AppColors.textPrimary),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: [
            _greeting(),
            const SizedBox(height: 22),
            _searchCard(),
            const SizedBox(height: 28),
            _popularRoutes(),
            const SizedBox(height: 24),
            _liveDemoBanner(),
          ],
        ),
      ),
    );
  }

  Widget _greeting() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('WELCOME BACK', style: AppText.overline),
              const SizedBox(height: 6),
              ShaderMask(
                shaderCallback: (rect) =>
                    AppColors.accentGradient.createShader(rect),
                child: const Text(
                  'My Train',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
        IconActionButton(
          icon: Icons.confirmation_number_rounded,
          size: 46,
          iconSize: 22,
          onTap: () => Navigator.of(context).push(
            CupertinoPageRoute(builder: (_) => const PnrStatusScreen()),
          ),
        ),
        const SizedBox(width: 10),
        IconActionButton(
          icon: Icons.tune_rounded,
          size: 46,
          iconSize: 22,
          onTap: () => Navigator.of(context).push(
            CupertinoPageRoute(builder: (_) => const SettingsScreen()),
          ),
        ),
      ],
    );
  }

  Widget _searchCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.lineMuted),
        boxShadow: AppColors.floatingShadow(),
      ),
      child: Column(
        children: [
          _segmentedTabs(),
          const SizedBox(height: 18),
          AnimatedSize(
            duration: Motion.medium,
            curve: Motion.emphasized,
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              duration: Motion.fast,
              switchInCurve: Motion.standard,
              switchOutCurve: Motion.standard,
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: child,
              ),
              child: _mode == 0
                  ? _routeForm(key: const ValueKey('route'))
                  : _trainForm(key: const ValueKey('train')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _segmentedTabs() {
    // Variant 3: glass pill with a sliding glass thumb.
    return LiquidGlassSegmented(
      labels: const ['By Route', 'By Train No.'],
      selectedIndex: _mode,
      onChanged: (i) {
        if (_mode == i) return;
        FocusManager.instance.primaryFocus?.unfocus();
        setState(() => _mode = i);
      },
    );
  }

  // -------- Route form --------
  Widget _routeForm({required Key key}) {
    return Column(
      key: key,
      children: [
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.lineMuted),
          ),
          child: Stack(
            children: [
              Column(
                children: [
                  _stationField(isFrom: true),
                  Padding(
                    padding: const EdgeInsets.only(left: 56, right: 16),
                    child: Divider(height: 1, color: AppColors.lineMuted),
                  ),
                  _stationField(isFrom: false),
                ],
              ),
              Positioned(
                right: 12,
                top: 0,
                bottom: 0,
                child: Center(child: _swapButton()),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _dateSelector(),
        const SizedBox(height: 18),
        _cta(
          label: 'Search Trains',
          icon: Icons.search_rounded,
          enabled: _from != null && _to != null,
          onTap: _searchRoute,
        ),
      ],
    );
  }

  Widget _stationField({required bool isFrom}) {
    final station = isFrom ? _from : _to;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openPicker(isFrom: isFrom),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 60, 14),
        child: Row(
          children: [
            Icon(
              isFrom ? Icons.trip_origin_rounded : Icons.place_rounded,
              size: 20,
              color: isFrom ? AppColors.accent : AppColors.accentViolet,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(isFrom ? 'FROM' : 'TO',
                      style: AppText.overline.copyWith(fontSize: 9.5)),
                  const SizedBox(height: 3),
                  Text(
                    station?.name ??
                        (isFrom ? 'Select origin' : 'Select destination'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.stationName.copyWith(
                      color: station == null
                          ? AppColors.textMuted
                          : AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (station != null)
                    Text(
                      'Station code · ${station.code}',
                      style: AppText.label.copyWith(
                        color: AppColors.textMuted,
                        fontSize: 11.5,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _swapButton() {
    return Pressable(
      onTap: _swap,
      pressedScale: Motion.pressScaleIcon,
      borderRadius: BorderRadius.circular(999),
      child: LiquidGlass(
        borderRadius: BorderRadius.circular(999),
        blurSigma: 16,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: AnimatedRotation(
              turns: _swapTurned ? 0.5 : 0,
              duration: Motion.medium,
              curve: Motion.spring,
              child: const Icon(Icons.swap_vert_rounded,
                  size: 22, color: AppColors.accent),
            ),
          ),
        ),
      ),
    );
  }

  Widget _dateSelector() {
    return Row(
      children: [
        for (int i = 0; i < 4; i++) ...[
          Expanded(child: _dateChip(i)),
          if (i < 3) const SizedBox(width: 8),
        ],
      ],
    );
  }

  Widget _dateChip(int i) {
    final selected = _dateIndex == i;
    final date = _dates[i];
    final label = i == 0
        ? 'Today'
        : i == 1
            ? 'Tomorrow'
            : _weekday(date);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (_dateIndex == i) return;
        Haptics.selection();
        setState(() => _dateIndex = i);
      },
      child: AnimatedContainer(
        duration: Motion.fast,
        curve: Motion.standard,
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: selected ? AppColors.accentGradient : null,
          color: selected ? null : AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? Colors.transparent : AppColors.lineMuted,
          ),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              '${date.day} ${_month(date)}',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: selected
                    ? Colors.white.withValues(alpha: 0.85)
                    : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -------- Train number form --------
  Widget _trainForm({required Key key}) {
    final suggestions =
        trainRepository.searchByNumberOrName(_trainQuery).take(5).toList();

    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.lineMuted),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              const Icon(Icons.confirmation_number_outlined,
                  size: 20, color: AppColors.accent),
              const SizedBox(width: 14),
              Expanded(
                child: TextField(
                  controller: _trainController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  style: AppText.stationName.copyWith(
                    fontSize: 16,
                    letterSpacing: 1.0,
                  ),
                  cursorColor: AppColors.accent,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Enter train number',
                    hintStyle:
                        AppText.label.copyWith(color: AppColors.textMuted),
                    contentPadding: const EdgeInsets.symmetric(vertical: 18),
                  ),
                  onSubmitted: (_) => _trackNumber(),
                ),
              ),
              if (_trainQuery.isNotEmpty)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _trainController.clear(),
                  child: Icon(Icons.close_rounded,
                      size: 18, color: AppColors.textSecondary),
                ),
            ],
          ),
        ),
        if (suggestions.isNotEmpty) ...[
          const SizedBox(height: 10),
          ...suggestions.map(_suggestionRow),
        ],
        const SizedBox(height: 16),
        _cta(
          label: 'Track Train',
          icon: Icons.my_location_rounded,
          enabled: _trainQuery.trim().isNotEmpty,
          onTap: _trackNumber,
        ),
      ],
    );
  }

  Widget _suggestionRow(TrainSummary t) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openTracking(t),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.lineMuted),
        ),
        child: Row(
          children: [
            Text(
              t.number,
              style: const TextStyle(
                color: AppColors.accent,
                fontSize: 14,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.label.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    '${t.fromCode} → ${t.toCode} · ${t.daysLabel}',
                    style: AppText.label
                        .copyWith(color: AppColors.textMuted, fontSize: 11.5),
                  ),
                ],
              ),
            ),
            Icon(Icons.north_east_rounded,
                size: 15, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }

  // -------- Shared --------
  Widget _cta({
    required String label,
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    // Variant 1: primary action. Indigo-tinted glass when the form is ready;
    // neutral glass when incomplete (still tappable to surface a hint).
    return LiquidGlassButton(
      onPressed: onTap,
      expand: true,
      cornerRadius: 22,
      tint: enabled ? AppColors.accent : null,
      glowColor: AppColors.accent,
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 20,
            color: enabled ? Colors.white : AppColors.textMuted,
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
              color: enabled ? Colors.white : AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _popularRoutes() {
    const routes = <_Route>[
      _Route('NDLS', 'New Delhi', 'BCT', 'Mumbai Central'),
      _Route('MAS', 'Chennai Central', 'SBC', 'Bangalore City Jn'),
      _Route('HWH', 'Howrah Jn', 'NDLS', 'New Delhi'),
      _Route('MMCT', 'Mumbai Central', 'ADI', 'Ahmedabad Jn'),
      _Route('SC', 'Secunderabad Jn', 'NDLS', 'New Delhi'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('POPULAR ROUTES', style: AppText.overline),
        const SizedBox(height: 12),
        SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: routes.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, i) => _routeCard(routes[i]),
          ),
        ),
      ],
    );
  }

  Widget _routeCard(_Route r) {
    return Pressable(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        setState(() {
          _mode = 0;
          _from = RailStation(code: r.fromCode, name: r.fromName);
          _to = RailStation(code: r.toCode, name: r.toName);
        });
        _searchRoute();
      },
      child: Container(
        width: 210,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.lineMuted),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Text(r.fromCode,
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 15)),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(Icons.arrow_right_alt_rounded,
                      size: 18, color: AppColors.accent),
                ),
                Text(r.toCode,
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 15)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${r.fromName}  →  ${r.toName}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppText.label
                  .copyWith(color: AppColors.textSecondary, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _liveDemoBanner() {
    const demo = TrainSummary(
      number: '12951',
      name: 'Mumbai Rajdhani Express',
      fromCode: 'BCT',
      fromName: 'Mumbai Central',
      toCode: 'NDLS',
      toName: 'New Delhi',
      departure: '17:00',
      arrival: '08:35',
      duration: '15h 35m',
      daysLabel: 'Daily',
      type: 'Rajdhani',
      arrivalDayOffset: 1,
    );

    return Pressable(
      borderRadius: BorderRadius.circular(20),
      onTap: () => _openTracking(demo),
      child: LiquidGlass(
        borderRadius: BorderRadius.circular(20),
        blurSigma: 18,
        padding: const EdgeInsets.all(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.accent.withValues(alpha: 0.30),
            AppColors.accentViolet.withValues(alpha: 0.16),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: AppColors.accentGradient,
                shape: BoxShape.circle,
                boxShadow: AppColors.glow(AppColors.accent, opacity: 0.4),
              ),
              child: const Icon(Icons.sensors_rounded,
                  size: 24, color: Colors.white),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('See live tracking in action',
                      style: AppText.titleStrong.copyWith(fontSize: 15.5)),
                  const SizedBox(height: 3),
                  Text(
                    '12951 · Mumbai Rajdhani Express',
                    style: AppText.label.copyWith(
                        color: AppColors.textSecondary, fontSize: 12.5),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded,
                size: 16, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }

  String _weekday(DateTime d) {
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return names[(d.weekday - 1) % 7];
  }

  String _month(DateTime d) {
    const names = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return names[(d.month - 1) % 12];
  }
}

class _Route {
  const _Route(this.fromCode, this.fromName, this.toCode, this.toName);
  final String fromCode;
  final String fromName;
  final String toCode;
  final String toName;
}
