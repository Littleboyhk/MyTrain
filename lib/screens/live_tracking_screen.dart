import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';

import '../data/chat_gate_controller.dart';
import '../data/crowd_position_service.dart';
import '../data/tracking_controller.dart';
import '../data/train_status_service.dart';
import '../l10n/app_localizations.dart';
import '../models/tracking_state.dart';
import '../models/train_summary.dart';
import '../theme/app_theme.dart';
import '../theme/glass_theme.dart';
import '../utils/haptics.dart';
import '../widgets/bottom_action_bar.dart';
import '../widgets/phone_verification_sheet.dart';
import '../widgets/empty_state.dart';
import '../widgets/inside_train_sheet.dart';
import '../widgets/journey_hero_card.dart';
import '../widgets/mesh_background.dart';
import '../widgets/sharing_indicator.dart';
import '../widgets/skeleton_timeline.dart';
import '../widgets/station_timeline.dart';
import '../widgets/tracking_header.dart';
import '../widgets/train_refresh_indicator.dart';

/// The signature Live Tracking screen.
class LiveTrackingScreen extends ConsumerStatefulWidget {
  const LiveTrackingScreen({super.key, this.train});

  final TrainSummary? train;

  @override
  ConsumerState<LiveTrackingScreen> createState() => _LiveTrackingScreenState();
}

class _LiveTrackingScreenState extends ConsumerState<LiveTrackingScreen> {
  late final List<DateTime> _days = _buildDays();
  int _selectedDay = 1; // 0 = yesterday, 1 = today
  bool _promptShown = false;
  String _sourceLabel = 'Estimated';

  /// No hardcoded fallback: without a train we show an unavailable state rather
  /// than silently tracking some other train (see TrackingController).
  String get _trainNumber => widget.train?.number ?? '';

  TrackingArgs get _trackingArgs => TrackingArgs(
        trainNumber: _trainNumber,
        date: _journeyDate,
        train: widget.train,
      );

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
    // Keyed by train number + date, so one train's route can never be shown
    // under another train's name.
    final args = _trackingArgs;
    final state = ref.watch(trackingProvider(args));
    final controller = ref.read(trackingProvider(args).notifier);
    final topPadding = MediaQuery.paddingOf(context).top;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    final sharing = ref.watch(crowdSharingProvider);
    ref.watch(trainStatusStreamProvider(_trainKey));
    final verified = ref.watch(crowdVerifiedPositionProvider(_trainKey)).value;
    _sourceLabel =
        (verified != null && verified.isFresh) ? 'Crowd-verified' : 'Estimated';

    ref.listen<CrowdSharingState>(crowdSharingProvider, (prev, next) {
      final reason = next.autoOffReason;
      if (reason != null && prev?.autoOffReason != reason) {
        _toast(Icons.location_off_rounded, reason);
        ref.read(crowdSharingProvider.notifier).acknowledgeAutoOff();
      }
    });

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          const Positioned.fill(child: MeshBackground()),
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
                onChat: _onChat,
              ),
            ),
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
      // LIVE only when a real running-status fix exists; otherwise OFFLINE.
      live: state is TrackingReady && state.live,
      days: _days,
      selectedDay: _selectedDay,
      onSelectDay: (i) => setState(() => _selectedDay = i),
      onBack: () => Navigator.of(context).maybePop(),
      onAlarm: () => _onAlarm(state),
      onCoach: _onCoach,
      onShare: _onShare,
      onToggleSignal: controller.reacquire,
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

      // DATA INTEGRITY: no trustworthy route for this train, so we show an
      // honest message instead of substituting another train's timeline.
      case TrackingUnavailable(:final message, :final reason):
        assert(() {
          debugPrint('[Tracking] unavailable: $reason');
          return true;
        }());
        return [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 40, 28, 120),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.route_rounded,
                      size: 46, color: context.glass.textMuted),
                  const SizedBox(height: 18),
                  Text(
                    L10n.of(context).routeUnavailableTitle,
                    textAlign: TextAlign.center,
                    style: AppText.titleStrong.copyWith(fontSize: 19),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: AppText.label.copyWith(
                      color: context.glass.textSecondary,
                      height: 1.45,
                      fontSize: 13.5,
                    ),
                  ),
                  const SizedBox(height: 20),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: controller.reacquire,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(
                        gradient: GlassTheme.accent,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        L10n.of(context).tryAgain,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
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
    final stations = state.journey.stations;
    final passThrough = stations.where((s) => s.isPassThrough).length;
    // With RailRadar's route the list also contains pass-through points, so
    // count the actual STOPS and mention the passed stations separately —
    // "166 STATIONS" would misrepresent a 47-stop train.
    final label = passThrough > 0
        ? '${stations.length - passThrough} STOPS · $passThrough PASSED'
        : '${stations.length} STATIONS';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
      child: Text('LIVE TIMELINE · $label', style: AppText.overline),
    );
  }

  void _onAlarm(TrackingState state) {
    Haptics.tap();
    if (state is! TrackingReady) return;
    _showSheet(
      context,
      title: L10n.of(context).destinationAlarm,
      body: 'Get a wake-up vibration 10 minutes before reaching ${state.journey.destination.name}.',
      action: L10n.of(context).setAlarm,
      onAction: () => _toast(Icons.alarm_on_rounded, 'Alarm set for 10 min before destination'),
    );
  }

  void _onCoach() {
    Haptics.tap();
    _showSheet(
      context,
      title: L10n.of(context).coachPosition,
      body: 'Standard rake order: Engine → SLR → GS → S1–S8 → B1–B4 → A1 → GS → SLR',
      action: L10n.of(context).gotIt,
      onAction: () {},
    );
  }

  /// "Join chat": run the account gate (phone verification + 18+ attestation),
  /// then hand off to the journey verification sampler.
  ///
  /// [startChatJoin] does its own pre-flight, so an already-verified returning
  /// user never sees the sheet at all.
  Future<void> _onChat() async {
    Haptics.tap();
    final outcome = await startChatJoin(context, ref);
    if (!mounted) return;

    switch (outcome) {
      case ChatJoinOutcome.verified:
        // Control passes to the existing gate: GPS route-matching starts here.
        ref.read(chatGateProvider.notifier).requestAccess(
              trainNumber: _trainNumber,
              journeyDate: _journeyDate,
            );
        _toast(Icons.forum_rounded, 'Verifying your journey…');
      case ChatJoinOutcome.declined:
        _toast(
          Icons.info_outline_rounded,
          'Chat is only for passengers aged 18 and over.',
        );
      case ChatJoinOutcome.unavailable:
        _toast(Icons.cloud_off_rounded, 'Chat isn\'t available right now.');
      case ChatJoinOutcome.dismissed:
        break; // Silent: they closed the sheet on purpose.
    }
  }

  void _onShare() {
    Haptics.confirm();
    ref.read(crowdSharingProvider.notifier).start(
          trainNumber: _trainNumber,
          date: _journeyDate,
          mode: CrowdMode.gps,
        );
    _toast(Icons.sensors_rounded, 'Sharing location with fellow passengers');
  }

  void _showSheet(
    BuildContext context, {
    required String title,
    required String body,
    required String action,
    required VoidCallback onAction,
  }) {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(title),
        message: Text(body),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(ctx).pop();
              onAction();
            },
            child: Text(action),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Close'),
        ),
      ),
    );
  }

  void _toast(IconData icon, String msg) {
    final scaffold = ScaffoldMessenger.maybeOf(context);
    scaffold?.hideCurrentSnackBar();
    scaffold?.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, size: 18, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(child: Text(msg)),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 90),
      ),
    );
  }
}
