import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';

import '../data/crowd_position_service.dart';
import '../data/tracking_controller.dart';
import '../data/train_status_service.dart';
import '../models/tracking_state.dart';
import '../models/train_summary.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/haptics.dart';
import '../widgets/bottom_action_bar.dart';
import '../widgets/empty_state.dart';
import '../widgets/inside_train_sheet.dart';
import '../widgets/journey_hero_card.dart';
import '../widgets/sharing_indicator.dart';
import '../widgets/skeleton_timeline.dart';
import '../widgets/station_timeline.dart';
import '../widgets/tracking_header.dart';
import '../widgets/train_refresh_indicator.dart';

/// The signature Live Tracking screen.
class LiveTrackingScreen extends ConsumerStatefulWidget {
  const LiveTrackingScreen({super.key, this.train});

  /// Optional train identity (from search) shown in the header. The live
  /// journey data itself is still mock until the real API is wired in.
  final TrainSummary? train;

  @override
  ConsumerState<LiveTrackingScreen> createState() => _LiveTrackingScreenState();
}

class _LiveTrackingScreenState extends ConsumerState<LiveTrackingScreen> {
  late final List<DateTime> _days = _buildDays();
  int _selectedDay = 1; // 0 = yesterday, 1 = today
  bool _promptShown = false;
  String _sourceLabel = 'Estimated';

  String get _trainNumber => widget.train?.number ?? '12951';

  String get _journeyDate {
    final n = DateTime.now();
    return '${n.year.toString().padLeft(4, '0')}-'
        '${n.month.toString().padLeft(2, '0')}-'
        '${n.day.toString().padLeft(2, '0')}';
  }

  TrainKey get _trainKey => (number: _trainNumber, date: _journeyDate);

  List<DateTime> _buildDays() {
    final now = DateTime.now();
    final base = DateTime(now.year, now.month, now.day);
    return [
      base.subtract(const Duration(days: 1)),
      base,
      base.add(const Duration(days: 1)),
      base.add(const Duration(days: 2)),
      base.add(const Duration(days: 3)),
    ];
  }

  @override
  void initState() {
    super.initState();
    // Non-blocking "Are you on this train?" prompt shortly after opening,
    // once per screen. (In production, gate this on the train being in transit.)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 1200), () {
        if (!mounted || _promptShown) return;
        if (ref.read(crowdSharingProvider).active) return;
        _promptShown = true;
        showInsideTrainSheet(context,
            trainNumber: _trainNumber, date: _journeyDate);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(trackingProvider);
    final controller = ref.read(trackingProvider.notifier);
    final topPadding = MediaQuery.paddingOf(context).top;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    // Layer 1 + Layer 2 (null in mock mode). Watching the status stream also
    // drives the tracked_trains lifecycle (mark active / expire on leave).
    final sharing = ref.watch(crowdSharingProvider);
    ref.watch(trainStatusStreamProvider(_trainKey));
    final verified = ref.watch(crowdVerifiedPositionProvider(_trainKey)).value;
    _sourceLabel =
        (verified != null && verified.isFresh) ? 'Crowd-verified' : 'Estimated';

    // Auto-off notification (e.g. user left the train).
    ref.listen<CrowdSharingState>(crowdSharingProvider, (prev, next) {
      final reason = next.autoOffReason;
      if (reason != null && prev?.autoOffReason != reason) {
        _toast(Icons.location_off_rounded, reason);
        ref.read(crowdSharingProvider.notifier).acknowledgeAutoOff();
      }
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          AnimationLimiter(
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              slivers: [
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _headerDelegate(state, controller, topPadding),
                ),
                ..._bodySlivers(state, controller, bottomInset),
              ],
            ),
          ),
          if (state is! TrackingLoading)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: BottomActionBar(
                onAlarm: () => _onAlarm(state),
                onCoach: _onCoach,
                onShare: _onShare,
              ),
            ),
          // Persistent, unmissable location-sharing indicator.
          if (sharing.active)
            Positioned(
              top: topPadding + 62,
              left: 0,
              right: 0,
              child: Center(
                child: SharingIndicator(
                  label: sharing.mode == CrowdMode.gps
                      ? 'Sharing · GPS'
                          '${sharing.speedKmh != null ? ' · ${sharing.speedKmh!.round()} km/h' : ''}'
                      : 'Sharing location',
                  onTap: () => ref.read(crowdSharingProvider.notifier).stop(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  TrackingHeaderDelegate _headerDelegate(
    TrackingState state,
    TrackingController controller,
    double topPadding,
  ) {
    final journey = switch (state) {
      TrackingReady(:final journey) => journey,
      TrackingNoSignal(:final journey) => journey,
      _ => null,
    };

    final train = widget.train;

    return TrackingHeaderDelegate(
      topPadding: topPadding,
      trainNumber: train?.number ?? journey?.trainNumber ?? '—',
      trainName: train?.name ?? journey?.trainName ?? 'Fetching live status…',
      originName: train?.fromName ?? journey?.origin.name ?? '',
      destinationName: train?.toName ?? journey?.destination.name ?? '',
      live: state is TrackingReady,
      days: _days,
      selectedDay: _selectedDay,
      onSelectDay: (i) => setState(() => _selectedDay = i),
      onBack: () => Navigator.of(context).maybePop(),
      onAlarm: () => _onAlarm(state),
      onCoach: _onCoach,
      onShare: _onShare,
      onToggleSignal: controller.toggleSignalForDemo,
    );
  }

  List<Widget> _bodySlivers(
    TrackingState state,
    TrackingController controller,
    double bottomInset,
  ) {
    switch (state) {
      case TrackingLoading():
        return const [
          SliverToBoxAdapter(child: SkeletonTimeline()),
        ];

      case TrackingNoSignal(:final since):
        return [
          CupertinoSliverRefreshControl(
            refreshTriggerPullDistance: 110,
            refreshIndicatorExtent: 90,
            onRefresh: controller.refresh,
            builder: _refreshBuilder,
          ),
          SliverFillRemaining(
            hasScrollBody: false,
            child: SignalLostState(
              since: since,
              onRetry: controller.reacquire,
            ),
          ),
        ];

      case TrackingReady():
        return [
          CupertinoSliverRefreshControl(
            refreshTriggerPullDistance: 110,
            refreshIndicatorExtent: 90,
            onRefresh: controller.refresh,
            builder: _refreshBuilder,
          ),
          SliverToBoxAdapter(
            child: JourneyHeroCard(state: state, sourceLabel: _sourceLabel),
          ),
          SliverToBoxAdapter(child: _sectionLabel(state)),
          SliverPadding(
            padding: const EdgeInsets.only(left: 10, right: 6),
            sliver: StationTimelineSliver(state: state),
          ),
          SliverToBoxAdapter(
            child: SizedBox(height: 104 + bottomInset),
          ),
        ];
    }
  }

  Widget _refreshBuilder(
    BuildContext context,
    RefreshIndicatorMode refreshState,
    double pulledExtent,
    double refreshTriggerPullDistance,
    double refreshIndicatorExtent,
  ) {
    return TrainRefreshIndicator(
      refreshState: refreshState,
      pulledExtent: pulledExtent,
      triggerPullDistance: refreshTriggerPullDistance,
      indicatorExtent: refreshIndicatorExtent,
    );
  }

  Widget _sectionLabel(TrackingReady state) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 6),
      child: Row(
        children: [
          Text('STATIONS', style: AppText.overline),
          const Spacer(),
          Text(
            '${state.stations.length} stops',
            style: AppText.label.copyWith(
              color: AppColors.textMuted,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------
  void _onAlarm(TrackingState state) {
    Haptics.confirm();
    final target = state is TrackingReady ? state.currentStation.name : null;
    _toast(
      Icons.notifications_active_rounded,
      target == null
          ? 'Arrival alarm set'
          : 'Arrival alarm set for $target',
    );
  }

  void _onCoach() {
    Haptics.tap();
    _toast(Icons.event_seat_rounded, 'Coach position — opening layout');
  }

  void _onShare() {
    Haptics.tap();
    _toast(Icons.ios_share_rounded, 'Live status link copied to clipboard');
  }

  void _toast(IconData icon, String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.surfaceElevated,
        elevation: 0,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 96),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppColors.lineMuted),
        ),
        duration: const Duration(milliseconds: 1800),
        content: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.accent),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: AppText.label.copyWith(color: AppColors.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
