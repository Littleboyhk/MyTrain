import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';

import '../data/app_settings_controller.dart';
import '../data/crowd_position_service.dart';
import '../data/destination_alarm_service.dart';
import '../data/offline/cell_observation_service.dart';
import '../data/offline/offline_tracking_controller.dart';
import '../data/speedometer_service.dart';
import '../data/tracking_controller.dart';
import '../data/train_status_service.dart';
import '../l10n/app_localizations.dart';
import '../models/tracking_state.dart';
import '../models/train_summary.dart';
import '../theme/app_theme.dart';
import '../theme/glass_theme.dart';
import '../theme/motion.dart';
import '../utils/haptics.dart';
import '../widgets/bottom_action_bar.dart';
import '../widgets/phone_verification_sheet.dart';
import '../widgets/empty_state.dart';
import '../widgets/inside_train_sheet.dart';
import '../widgets/glass_container.dart';
import '../widgets/journey_hero_card.dart';
import '../widgets/mesh_background.dart';
import '../widgets/offline_status.dart';
import '../widgets/rail_track/rail_track_timeline.dart';
import '../widgets/rail_track/train_locator_pill.dart';
import '../widgets/sharing_indicator.dart';
import '../widgets/skeleton_timeline.dart';
import '../widgets/speedometer_gauge.dart';
import '../widgets/tracking_header.dart';
import '../widgets/train_refresh_indicator.dart';
import '../data/offline/dead_reckoning_service.dart';
import '../widgets/destination_alarm_dialog.dart';
import '../widgets/location_alarm_sheet.dart';
import '../widgets/journey_chat_sheet.dart';
import '../widgets/next_mile_transit_card.dart';
import 'coach_position_screen.dart';

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

  /// The screen owns the scroll position so the track can be brought to the
  /// train, and so the locator pill knows when the train is off screen.
  final ScrollController _scrollController = ScrollController();

  /// Where the train marker sits, in this scroll view's own offset space.
  /// Published by [RailTrackTimelineSliver]; null when there is no marker.
  final ValueNotifier<double?> _trainOffset = ValueNotifier<double?>(null);

  /// Auto-scroll happens exactly once per screen, so a background poll can
  /// never yank the list out from under the user.
  bool _didAutoScroll = false;

  /// No hardcoded fallback: without a train we show an unavailable state rather
  /// than silently tracking some other train (see TrackingController).
  String get _trainNumber => widget.train?.number ?? '';

  TrackingArgs get _trackingArgs => TrackingArgs(
        trainNumber: _trainNumber,
        date: _journeyDate,
        train: widget.train,
      );

  String get _journeyDate {
    final d = (_selectedDay >= 0 && _selectedDay < _days.length)
        ? _days[_selectedDay]
        : DateTime.now();
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
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
    ];
  }

  @override
  void initState() {
    super.initState();
    // The sliver publishes the marker offset after the frame it first lays out
    // in, which is later than this screen's own post-frame callback. Listening
    // here means the one-shot scroll fires whichever arrives first.
    _trainOffset.addListener(_maybeAutoScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 1200), () {
        if (!mounted || _promptShown) return;
        if (ref.read(crowdSharingProvider).active) return;
        // Settings → Personal → "Are you inside train option". Off means never
        // auto-prompt; sharing is still available from the action bar.
        if (!ref.read(appSettingsProvider).suggestInsideTrain) return;
        _promptShown = true;
        showInsideTrainSheet(context,
            trainNumber: _trainNumber, date: _journeyDate);
      });
    });
  }

  @override
  void dispose() {
    _trainOffset.removeListener(_maybeAutoScroll);
    _trainOffset.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Landing on the train
  // ---------------------------------------------------------------------------

  /// Scroll offset that puts the marker in clear view.
  ///
  /// The header stays pinned at its compact height, so the raw marker offset
  /// would park the train underneath it.
  double _scrollTargetFor(double markerOffset, ScrollPosition position) {
    final leadIn = MediaQuery.paddingOf(context).top + 56 + 24;
    return (markerOffset - leadIn)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
  }

  /// One-shot: bring the train into view on the first live build.
  ///
  /// Idempotent, because it is reached from both the marker-offset listener and
  /// a post-frame callback and only the first of the two should act.
  void _maybeAutoScroll() {
    if (_didAutoScroll || !mounted) return;
    final target = _trainOffset.value;
    if (target == null || !_scrollController.hasClients) return;

    final position = _scrollController.position;
    _didAutoScroll = true;

    // The user already moved: their position wins, and we never ask again.
    if (position.pixels > 0) return;

    // jumpTo rather than animateTo: animating would drag the entire track past
    // them, and on a three-day route that is a long, pointless journey.
    _scrollController.jumpTo(_scrollTargetFor(target, position));
  }

  void _scrollToTrain() {
    final target = _trainOffset.value;
    if (target == null || !_scrollController.hasClients) return;
    Haptics.tap();
    _scrollController.animateTo(
      _scrollTargetFor(target, _scrollController.position),
      duration: Motion.trainGlide,
      curve: Motion.glide,
    );
  }

  /// The way back to the train, offered once it is more than a full screen from
  /// where the user is looking.
  ///
  /// Rebuilds on scroll, but only this pill does: the offset comes from the
  /// layout model, so nothing off-screen has to have been built to know where
  /// the train is.
  Widget _locatorPill() {
    return ValueListenableBuilder<double?>(
      valueListenable: _trainOffset,
      builder: (context, target, _) {
        if (target == null) return const SizedBox.shrink();
        return AnimatedBuilder(
          animation: _scrollController,
          builder: (context, _) {
            if (!_scrollController.hasClients) return const SizedBox.shrink();
            final position = _scrollController.position;
            final viewport = position.viewportDimension;
            final delta = target - position.pixels;
            final visible = viewport > 0 && delta.abs() > viewport;

            return IgnorePointer(
              ignoring: !visible,
              child: AnimatedOpacity(
                opacity: visible ? 1 : 0,
                duration: Motion.fast,
                curve: Motion.standard,
                child: AnimatedScale(
                  scale: visible ? 1 : 0.85,
                  duration: Motion.fast,
                  curve: Motion.standard,
                  child: TrainLocatorPill(
                    above: delta < 0,
                    onTap: _scrollToTrain,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
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
    final settings = ref.watch(appSettingsProvider);
    ref.watch(trainStatusStreamProvider(_trainKey));
    // PHASE 2 GROUNDWORK. Watching this is what enables cell-tower collection for
    // this journey; the recorder is inert unless crowd sharing is switched on,
    // and it is Android-only. It contributes nothing to the position on screen —
    // see CellObservationRecorder for why it cannot slow tracking down.
    ref.watch(cellObservationProvider(_trainKey));
    final verified = ref.watch(crowdVerifiedPositionProvider(_trainKey)).value;
    _sourceLabel = (state is TrackingReady && state.isOfflinePosition)
        ? 'Offline · GPS'
        : (verified != null && verified.isFresh)
            ? 'Crowd-verified'
            : (state is TrackingReady && state.live)
                ? 'Real-Time API'
                : 'Timetable Schedule';

    ref.listen<CrowdSharingState>(crowdSharingProvider, (prev, next) {
      final reason = next.autoOffReason;
      if (reason != null && prev?.autoOffReason != reason) {
        _toast(Icons.location_off_rounded, reason);
        ref.read(crowdSharingProvider.notifier).acknowledgeAutoOff();
      }
    });

    ref.listen<DestinationAlarmData>(destinationAlarmProvider, (prev, next) {
      if (next.state == DestinationAlarmState.ringing &&
          prev?.state != DestinationAlarmState.ringing) {
        showDestinationAlarmSheet(context, ref);
      }
    });

    if (state is TrackingReady && !_didAutoScroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoScroll());
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          const Positioned.fill(child: MeshBackground()),
          AnimationLimiter(
            child: CustomScrollView(
              controller: _scrollController,
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              slivers: [
                SliverPersistentHeader(
                  pinned: false,
                  delegate: _headerDelegate(state, controller, topPadding),
                ),
                ..._bodySlivers(state, controller, bottomInset),
              ],
            ),
          ),
          if (state is TrackingReady)
            Positioned(
              left: 0,
              right: 0,
              bottom: 112 + bottomInset,
              child: Center(child: _locatorPill()),
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
          // Speedometer: only while a GPS session is actually running, which is
          // where the speed comes from. Gating it this way means enabling the
          // setting can never trigger a location prompt on its own.
          if (settings.speedometerEnabled &&
              sharing.active &&
              sharing.mode == CrowdMode.gps)
            Positioned(
              right: 14,
              bottom: 118 + bottomInset,
              child: const _SpeedometerOverlay(),
            ),
          // Offline indicator. Sits below the sharing chip when both are up, so
          // neither is obscured.
          if (state is TrackingReady)
            Positioned(
              top: topPadding + (sharing.active ? 106 : 62),
              left: 0,
              right: 0,
              child: Center(child: _OfflineOverlay(trainKey: _trainKey)),
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
      // LIVE badge active whenever tracking state is ready.
      live: state is TrackingReady,
      days: _days,
      selectedDay: _selectedDay,
      onSelectDay: (i) => setState(() => _selectedDay = i),
      onCustomDateSelected: _onCustomDateSelected,
      onBack: () => Navigator.of(context).maybePop(),
      onAlarm: () => _onAlarm(state),
      onCoach: _onCoach,
      onShare: _onShare,
      onToggleSignal: controller.reacquire,
    );
  }

  void _onCustomDateSelected(DateTime picked) {
    final pickedDate = DateTime(picked.year, picked.month, picked.day);
    int idx = -1;
    for (int i = 0; i < _days.length; i++) {
      final d = _days[i];
      if (d.year == pickedDate.year && d.month == pickedDate.month && d.day == pickedDate.day) {
        idx = i;
        break;
      }
    }
    if (idx != -1) {
      setState(() => _selectedDay = idx);
    } else {
      setState(() {
        _days.add(pickedDate);
        _days.sort((a, b) => a.compareTo(b));
        _selectedDay = _days.indexOf(pickedDate);
      });
    }
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
          SliverToBoxAdapter(child: _OfflineNotice(trainKey: _trainKey)),
          SliverToBoxAdapter(child: _sectionLabel(state)),
          SliverPadding(
            padding: const EdgeInsets.only(left: 10, right: 6),
            sliver: RailTrackTimelineSliver(
              state: state,
              scrollController: _scrollController,
              trainOffsetNotifier: _trainOffset,
            ),
          ),
          SliverToBoxAdapter(
            child: NextMileTransitCard(
              destinationStationName: state.journey.destination.name,
              destinationStationCode: state.journey.destination.code,
            ),
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
    showLocationAlarmSheet(
      context: context,
      ref: ref,
      stations: state.journey.stations,
      defaultStation: state.journey.destination,
    );
  }

  /// Opens the real coach-sequence screen.
  ///
  /// The generic rake-order literal this used to show now lives in
  /// [kTypicalRakeOrder] and is only reached when the train has no published
  /// composition — the screen decides, because it is the thing that knows whether
  /// the sequence parsed.
  ///
  /// `journey.coachPosition` is already in hand from the route fetch, so opening
  /// this costs no network request.
  void _onCoach() {
    Haptics.tap();
    final journey = switch (ref.read(trackingProvider(_trackingArgs))) {
      TrackingReady(:final journey) => journey,
      TrackingNoSignal(:final journey) => journey,
      _ => null,
    };

    Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (_) => CoachPositionScreen(
          trainNumber: journey?.trainNumber ?? _trainNumber,
          trainName: journey?.trainName ?? widget.train?.name ?? 'Train',
          coachPosition: journey?.coachPosition,
        ),
      ),
    );
  }

  /// "Join chat": run the account gate (phone verification + 18+ attestation),
  /// then hand off to the journey verification sampler.
  ///
  /// [startChatJoin] does its own pre-flight, so an already-verified returning
  /// user never sees the sheet at all.
  Future<void> _onChat() async {
    Haptics.tap();
    showJourneyChatSheet(
      context,
      trainNumber: _trainNumber,
      trainName: widget.train?.name ?? 'Express',
    );
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

/// The live speedometer, floated over the tracking screen.
///
/// Its own [ConsumerWidget] on purpose: the GPS stream ticks roughly every
/// second, and watching it here keeps those rebuilds inside the gauge instead of
/// re-running the whole tracking screen — which would rebuild the entire track
/// timeline once a second.
class _SpeedometerOverlay extends ConsumerStatefulWidget {
  const _SpeedometerOverlay();

  @override
  ConsumerState<_SpeedometerOverlay> createState() => _SpeedometerOverlayState();
}

class _SpeedometerOverlayState extends ConsumerState<_SpeedometerOverlay> {
  bool _isHidden = false;

  void _toggleHidden() {
    Haptics.selection();
    setState(() {
      _isHidden = !_isHidden;
    });
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(speedStreamProvider);

    final sample = switch (async) {
      AsyncData(:final value) => value,
      _ => null,
    };
    final stale = async.hasError ||
        (sample != null &&
            DateTime.now().difference(sample.at) >
                const Duration(seconds: 12));

    final kmhText = sample?.kmh != null ? '${sample!.kmh.round()} km/h' : '0 km/h';

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: _isHidden
          ? GestureDetector(
              key: const ValueKey('speedometer_hidden'),
              onTap: _toggleHidden,
              child: GlassContainer(
                radius: 16,
                blurSigma: 18,
                strong: true,
                glow: true,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.speed_rounded,
                      size: 14,
                      color: GlassTheme.railAmber,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      kmhText,
                      style: TextStyle(
                        color: context.glass.textPrimary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.unfold_more_rounded,
                      size: 13,
                      color: context.glass.textMuted,
                    ),
                  ],
                ),
              ),
            )
          : Stack(
              key: const ValueKey('speedometer_visible'),
              clipBehavior: Clip.none,
              children: [
                GlassContainer(
                  radius: 18,
                  blurSigma: 18,
                  strong: true,
                  glow: true,
                  padding: const EdgeInsets.all(6),
                  child: SpeedometerGauge(
                    size: 94,
                    kmh: sample?.kmh,
                    stale: stale,
                  ),
                ),
                Positioned(
                  top: -4,
                  right: -4,
                  child: GestureDetector(
                    onTap: _toggleHidden,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: context.glass.textMuted.withValues(alpha: 0.4),
                          width: 1,
                        ),
                      ),
                      child: Icon(
                        Icons.close_rounded,
                        size: 12,
                        color: context.glass.textPrimary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

/// The offline indicator, floated over the tracking screen.
///
/// Its own [ConsumerWidget] for the same reason as [_SpeedometerOverlay]: the
/// offline tracker republishes on every processed fix and on every stage change,
/// and watching that in the screen's own build would rebuild the entire rail
/// timeline each time the label changed from "Acquiring signal…" to "Offline ·
/// GPS".
class _OfflineOverlay extends ConsumerWidget {
  const _OfflineOverlay({required this.trainKey});

  final OfflineTrackingKey trainKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offline = ref.watch(offlineTrackingProvider(trainKey));

    // Nothing to say while the network is doing its job. The states that need
    // words from the user get the inline card instead, which can explain and
    // offer an action; a pill cannot.
    const quiet = <OfflineStage>{
      OfflineStage.idle,
      OfflineStage.noCachedRoute,
      OfflineStage.noGeometry,
      OfflineStage.permissionDenied,
      OfflineStage.permissionDeniedForever,
      OfflineStage.locationServiceOff,
      OfflineStage.unsupported,
    };
    if (quiet.contains(offline.stage)) return const SizedBox.shrink();

    return OfflineStatusPill(
      stage: offline.stage,
      lastSyncedAt: offline.lastSyncedAt,
      speedKmh: offline.speedKmh,
    );
  }
}

/// The actionable half of offline status: permission, location services, or the
/// "you need one online sync first" case.
///
/// Renders nothing at all in the normal case, so it costs a zero-height box on a
/// healthy connection.
class _OfflineNotice extends ConsumerWidget {
  const _OfflineNotice({required this.trainKey});

  final OfflineTrackingKey trainKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offline = ref.watch(offlineTrackingProvider(trainKey));
    final controller = ref.read(offlineTrackingProvider(trainKey).notifier);
    final deadReckoning = ref.watch(deadReckoningProvider);
    final message = offline.message;

    if (deadReckoning.isActive) {
      return OfflineNoticeCard(
        icon: Icons.navigation_rounded,
        message: 'Dead-Reckoning Active · ~${deadReckoning.distanceGainedKm.toStringAsFixed(1)} km extrapolated offline',
        actionLabel: 'Stop',
        onAction: () => ref.read(deadReckoningProvider.notifier).stopDeadReckoning(),
      );
    }

    if (message == null) return const SizedBox.shrink();

    switch (offline.stage) {
      case OfflineStage.permissionDenied:
        return OfflineNoticeCard(
          icon: Icons.my_location_rounded,
          message: message,
          actionLabel: 'Allow location',
          // The one place a permission prompt is raised: a deliberate tap.
          onAction: () {
            Haptics.tap();
            controller.start();
          },
        );

      case OfflineStage.permissionDeniedForever:
        return OfflineNoticeCard(
          icon: Icons.settings_rounded,
          message: message,
          actionLabel: 'Open settings',
          onAction: () {
            Haptics.tap();
            controller.openAppSettings();
          },
        );

      case OfflineStage.locationServiceOff:
        return OfflineNoticeCard(
          icon: Icons.location_disabled_rounded,
          message: message,
          actionLabel: 'Location settings',
          onAction: () {
            Haptics.tap();
            controller.openLocationSettings();
          },
        );

      case OfflineStage.noCachedRoute:
      case OfflineStage.noGeometry:
        // No action offered: only a network connection can resolve these, and
        // offering a dead button would be worse than saying so plainly.
        return OfflineNoticeCard(
          icon: Icons.cloud_download_rounded,
          message: message,
        );

      case OfflineStage.offRoute:
        return OfflineNoticeCard(
          icon: Icons.wrong_location_rounded,
          message: message,
        );

      case OfflineStage.arrived:
        return OfflineNoticeCard(
          icon: Icons.flag_rounded,
          message: message,
        );

      // Running states speak through the pill, not a card.
      case OfflineStage.idle:
      case OfflineStage.acquiring:
      case OfflineStage.tracking:
      case OfflineStage.unsupported:
        return const SizedBox.shrink();
    }
  }
}
