import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/station_culinary_service.dart';
import '../../data/train_platform_provider.dart';
import '../../models/station.dart';
import '../../models/station_live_status.dart';
import '../../models/tracking_state.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../theme/glass_theme.dart';
import '../../theme/motion.dart';
import '../../utils/formatters.dart';
import '../../utils/haptics.dart';
import '../glass_container.dart';
import 'rail_track_layout.dart';
import 'rail_track_painter.dart';
import 'train_marker.dart';

/// One station on the track, laid out as three columns.
///
///     scheduled arr        │●│  Station Name            scheduled dep
///     actual arr (colour)  │ │  412 km  Platform 3      actual dep (colour)
///
/// The side columns carry the timing story: scheduled on top in a neutral
/// colour, and beneath it the observed time in red when the train was at least
/// [kDelayThresholdMinutes] late, green otherwise. That is why the track bar in
/// the centre gutter is a single flat colour — it does not have to express
/// progress. See design.md section 2.
///
/// WHEN THE ACTUAL ROW IS WITHHELD. Only stations RailKit reports as `passed` or
/// `current` get a coloured actual row. For anything still ahead of the train the
/// row is omitted entirely rather than filled with an estimate, because RailKit
/// publishes no example of an upcoming stoppage and so the meaning of its
/// `actual` field before arrival is undocumented — it could be an ETA, an echo of
/// the scheduled time, or empty. Painting a station green on that basis would be
/// inventing an observation. The existing projected-time caption still covers
/// upcoming stations when a train-level delay is known.
class RailStationRow extends ConsumerStatefulWidget {
  const RailStationRow({
    super.key,
    required this.item,
    required this.rowTop,
    required this.trainNumber,
    required this.delayMinutes,
    this.markerOffset,
    this.markerStationName = '',
    this.markerArrived = false,
    this.hiddenAfterCount = 0,
    this.localsExpanded = false,
    this.onToggleLocals,
  });

  final RailStationItem item;

  /// Distance from the top of the track to this row, from
  /// [RailTrackLayout.offsetOfItem]. Lets the row decide on its own whether it
  /// holds the train marker, which is what keeps the list lazily buildable.
  final double rowTop;

  /// Needed for the platform lookup, which is keyed by train + station.
  final String trainNumber;

  /// The single train-level delay figure, used for the projected time on
  /// upcoming stations where no observed actual exists.
  final int delayMinutes;

  /// Animated marker position in track space (pixels from the top of the track).
  /// Null when no marker should be drawn.
  final Animation<double>? markerOffset;

  final String markerStationName;
  final bool markerArrived;

  /// How many collapsible stations sit in the run immediately after this one.
  /// Non-zero only for a significant station that owns a hidden run; drives the
  /// "+N" cue and makes this row's tap toggle that run instead of its own card.
  final int hiddenAfterCount;

  /// Whether this station's hidden run is currently revealed. Only meaningful
  /// when [hiddenAfterCount] > 0; rotates the chevron and flips the tap intent
  /// from "show" to "hide".
  final bool localsExpanded;

  /// Toggles this station's hidden run. The parent owns that state (and its
  /// haptics/rebuild), because revealing the run inserts rows the parent builds.
  final VoidCallback? onToggleLocals;

  @override
  ConsumerState<RailStationRow> createState() => _RailStationRowState();
}

class _RailStationRowState extends ConsumerState<RailStationRow> {
  /// Per-row and independent, so expanding one station never collapses another.
  /// Survives live rebuilds because the sliver keys rows by station code.
  bool _expanded = false;

  static const double _dotBox = 28;

  Station get _s => widget.item.station;
  StationLiveStatus? get _live => _s.live;
  bool get _isCurrent => widget.item.progress == StationProgress.current;
  bool get _isPassed => widget.item.progress == StationProgress.passed;
  bool get _isGapOrLocal => _s.isPassThrough;

  /// True when this station owns a collapsed run of local stops.
  bool get _hasLocals => widget.hiddenAfterCount > 0;

  /// True when the detail card would actually hold something: a platform lookup
  /// (platform unknown), a halt duration, or a note. Arrival and departure no
  /// longer count — those live in the side time columns — so a plain station
  /// with a known platform and no halt or note has an empty card and is not
  /// worth expanding.
  bool get _hasDetails =>
      (_staticPlatform == null && !_s.isPassThrough) ||
      _haltLabel != null ||
      _s.note != null;

  /// Whether tapping this row does anything at all.
  bool get _tappable => _hasLocals || _hasDetails;

  /// A station that owns a hidden run toggles that run on tap; otherwise the tap
  /// opens this station's own detail card — but only when that card has content
  /// (see [_hasDetails]). A run-owning station deliberately does *not* open its
  /// card, and one tap doing one thing keeps the gesture honest (design.md
  /// section 6.2).
  void _handleTap() {
    if (_hasLocals) {
      // The parent owns the run's expand state and does its own haptics/rebuild.
      widget.onToggleLocals?.call();
      return;
    }
    if (!_hasDetails) return; // nothing extra to show — no empty card
    Haptics.selection();
    setState(() => _expanded = !_expanded);
  }

  String get _localsSpeech {
    if (!_hasLocals) return '';
    final n = widget.hiddenAfterCount;
    final noun = n == 1 ? 'local station' : 'local stations';
    return widget.localsExpanded
        ? ', showing $n $noun, tap to hide'
        : ', $n $noun hidden, tap to show';
  }

  @override
  Widget build(BuildContext context) {
    // A Stack — NOT IntrinsicHeight — so the gutter stretches to whatever height
    // the content currently has. Carried over from the widget this replaced: the
    // expand animation changes the real height every frame, and an intrinsic
    // measurement cannot see a value mid-flight, which overflowed the row by
    // exactly the height of the detail block on collapse.
    final colWidth = RailMetrics.timeColWidth(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final rowBg = _isGapOrLocal
        ? (isDark ? const Color(0xFF2D3C48) : const Color(0xFFDFE6ED))
        : Colors.transparent;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      color: rowBg,
      padding: EdgeInsets.symmetric(vertical: _isGapOrLocal ? 1.0 : 0.0),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: colWidth,
            top: 0,
            bottom: 0,
            width: RailMetrics.gutterWidth,
            child: _gutter(),
          ),
          Padding(
            padding: EdgeInsets.only(
              top: _isGapOrLocal ? 4.0 : 6.0,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: colWidth,
                  child: _timeColumn(context, isArrival: true),
                ),
                const SizedBox(width: RailMetrics.gutterWidth),
                Expanded(child: _centre(context)),
                SizedBox(
                  width: colWidth,
                  child: _timeColumn(context, isArrival: false),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Gutter: the station dot and the train marker
  // ---------------------------------------------------------------------------

  Widget _gutter() {
    final item = widget.item;
    // No track above the origin, none past the terminus — the bar stops at the
    // dot rather than running off the end of the route.
    final startY = item.isFirst ? RailMetrics.pipCenterY : 0.0;
    final endY = item.isLast ? RailMetrics.pipCenterY : null;

    final anim = widget.markerOffset;
    if (anim == null) {
      return _gutterStack(startY: startY, endY: endY, markerY: null);
    }

    // Scoped to the gutter: a poll retargets this animation and repaints the
    // bar, and the rest of the row never rebuilds.
    return AnimatedBuilder(
      animation: anim,
      builder: (context, _) {
        final localY = anim.value - widget.rowTop;
        final owns = localY >= 0 && localY < item.height;
        return _gutterStack(
          startY: startY,
          endY: endY,
          markerY: owns ? localY : null,
        );
      },
    );
  }

  Widget _gutterStack({
    required double startY,
    required double? endY,
    required double? markerY,
  }) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(child: RailTrackPaint(startY: startY, endY: endY)),
        Positioned(
          left: 0,
          right: 0,
          top: (_isGapOrLocal ? 14.0 : RailMetrics.pipCenterY) - _dotBox / 2,
          height: _dotBox,
          child: Center(child: RailStationDot(minor: widget.item.minor)),
        ),
        if (markerY != null)
          Positioned(
            left: 0,
            right: 0,
            top: markerY - TrainMarker.ringSize / 2,
            height: TrainMarker.ringSize,
            child: Center(
              child: TrainMarker(
                stationName: widget.markerStationName,
                arrived: widget.markerArrived,
              ),
            ),
          ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Side columns: scheduled over actual
  // ---------------------------------------------------------------------------

  Widget _timeColumn(BuildContext context, {required bool isArrival}) {
    final g = context.glass;
    final leg = isArrival ? _live?.arrival : _live?.departure;
    final observed = _live?.canShowActual ?? false;

    // Scheduled comes from the route (RailRadar/RailKit static), which is always
    // present, and falls back to RailKit's live copy if the route lacks it.
    final scheduled =
        (isArrival ? _s.scheduledArrival : _s.scheduledDeparture) ??
            leg?.scheduled;

    // The origin has no arrival and the terminus no departure — RailKit marks
    // these SRC/DSTN. Show nothing rather than a placeholder clock.
    final isEndpoint = (isArrival && widget.item.isFirst) ||
        (!isArrival && widget.item.isLast) ||
        (leg?.isTerminusSentinel ?? false);

    if (isEndpoint && scheduled == null) return const SizedBox.shrink();

    final second = _secondLine(context, leg, observed, scheduled, isArrival);

    return Padding(
      padding: EdgeInsets.only(
        top: 2,
        left: isArrival ? 0 : 8,
        right: isArrival ? 8 : 0,
      ),
      child: Column(
        crossAxisAlignment:
            isArrival ? CrossAxisAlignment.start : CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            scheduled == null ? '—' : Fmt.hhmm(scheduled),
            // One line, always. A wrapped '4:38 / AM' was the most visible
            // symptom of the fixed-width time column on a narrow phone, and it
            // also silently broke the row-height contract by growing the column.
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.visible,
            style: AppText.label.copyWith(
              color: _isPassed ? g.textSecondary : g.textPrimary,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (second != null) ...[
            const SizedBox(height: 4),
            // Last-resort guard: the column width already grows with the text
            // scale, but a long localised string must shrink rather than overflow.
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment:
                  isArrival ? Alignment.centerLeft : Alignment.centerRight,
              child: second,
            ),
          ],
        ],
      ),
    );
  }

  /// The lower line of a time column: an observed actual where one exists, else a
  /// clearly-captioned projection, else nothing.
  Widget? _secondLine(
    BuildContext context,
    StationLegStatus? leg,
    bool observed,
    DateTime? scheduled,
    bool isArrival,
  ) {
    // 1. Observed actual — the only case that earns a green/red verdict.
    if (observed && leg != null && leg.hasActual) {
      final verdict = verdictFor(leg, actualObserved: true);
      final colour = switch (verdict) {
        TimingVerdict.delayed => AppColors.delayed,
        TimingVerdict.onTime => AppColors.onTime,
        TimingVerdict.unknown => context.glass.textMuted,
      };
      return Text(
        Fmt.hhmm(leg.actual!),
        maxLines: 1,
        softWrap: false,
        style: AppText.label.copyWith(
          color: colour,
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
        ),
      );
    }

    // 2. Nothing observed and nothing ahead to project — stay silent.
    if (scheduled == null) return null;
    if (widget.item.progress != StationProgress.upcoming) return null;
    if (widget.delayMinutes <= 0) return null;

    // 3. Upcoming station with a known train-level delay: a projection, labelled
    // as such and only ever red. Never green — an estimate cannot certify that a
    // future station will be on time.
    final projected = scheduled.add(Duration(minutes: widget.delayMinutes));
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!isArrival) ...[
          _projLabel(context),
          const SizedBox(width: 3),
        ],
        Text(
          Fmt.hhmm(projected),
          maxLines: 1,
          softWrap: false,
          style: AppText.label.copyWith(
            color: AppColors.delayed,
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (isArrival) ...[
          const SizedBox(width: 3),
          _projLabel(context),
        ],
      ],
    );
  }

  /// Marks a value as an estimate. Never reads "actual" or "expected".
  Widget _projLabel(BuildContext context) => Text(
        '~',
        style: AppText.label.copyWith(
          color: AppColors.delayed.withValues(alpha: 0.8),
          fontSize: 12.5,
          fontWeight: FontWeight.w800,
        ),
      );

  // ---------------------------------------------------------------------------
  // Centre column
  // ---------------------------------------------------------------------------

  Widget _centre(BuildContext context) {
    final g = context.glass;
    final nameStyle = _isGapOrLocal
        ? AppText.stationName.copyWith(
            fontSize: 13.5,
            fontWeight: FontWeight.w500,
            color: g.textSecondary,
          )
        : _isCurrent
            ? AppText.stationName
                .copyWith(fontSize: 16.5, fontWeight: FontWeight.w700)
            : AppText.stationName.copyWith(
                fontSize: 15.5,
                color: _isPassed ? g.textSecondary : g.textPrimary,
              );

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                // Title Case, not the feed's raw SHOUTING. Also materially
                // narrower, which is what stops the ellipsis on a small phone.
                Fmt.stationTitle(_s.name),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: nameStyle,
              ),
            ),
            // "+N" cue: how many local stops are folded after this station. This
            // is the only hint the run exists — without it the reveal is
            // undiscoverable now the pill and the bar are both gone.
            if (_hasLocals)
              Padding(
                padding: const EdgeInsets.only(left: 6, right: 3),
                child: Text(
                  '+${widget.hiddenAfterCount}',
                  style: AppText.label.copyWith(
                    color: g.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            // No chevron when there is nothing to expand — a plain station with
            // its times already on the row is not tappable.
            if (_tappable)
              AnimatedRotation(
                // For a run-owning station the chevron tracks the run; otherwise
                // it tracks this row's own detail card.
                turns: (_hasLocals ? widget.localsExpanded : _expanded) ? 0.5 : 0,
                duration: Motion.expand,
                curve: Motion.emphasized,
                child: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: g.textMuted,
                ),
              ),
          ],
        ),
        SizedBox(height: _isGapOrLocal ? 1 : 5),
        _subtitle(context),
        AnimatedSize(
          duration: Motion.expand,
          curve: Motion.emphasized,
          alignment: Alignment.topCenter,
          child: _expanded
              ? _details(context)
              : const SizedBox(width: double.infinity, height: 0),
        ),
      ],
    );

    return Semantics(
      container: true,
      button: _tappable,
      label: '${Fmt.stationTitle(_s.name)}, $_stateWord'
          '${_delaySpeech()}$_localsSpeech',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _tappable ? _handleTap : null,
        child: Padding(
          padding: const EdgeInsets.only(left: 4, right: 4, bottom: 2),
          child: content,
        ),
      ),
    );
  }

  String get _stateWord => switch (widget.item.progress) {
        StationProgress.passed => 'passed',
        StationProgress.current => 'current station',
        StationProgress.upcoming => 'upcoming',
      };

  /// Speaks the delay, so the red/green colour is never the only carrier of it
  /// (Requirement 11.5).
  String _delaySpeech() {
    final live = _live;
    if (live == null || !live.canShowActual) return '';
    for (final leg in [live.arrival, live.departure]) {
      final v = verdictFor(leg, actualObserved: true);
      if (v == TimingVerdict.delayed) {
        final mins = leg.delayMinutes ?? leg.delayMinutesFromLabel;
        return mins == null ? ', delayed' : ', $mins minutes late';
      }
    }
    return ', on time';
  }

  /// Distance, platform, and the pass/halt qualifier.
  ///
  /// A [Wrap] rather than a [Row]: at large text scales these fragments stop
  /// fitting on one line, and wrapping beats clipping.
  Widget _subtitle(BuildContext context) {
    final g = context.glass;
    final muted = AppText.label.copyWith(color: g.textMuted, fontSize: 12);

    final platform = _staticPlatform;
    final food = StationCulinaryService.getFoodForStation(_s.code);
    final haltMin = _s.haltMinutes ?? 0;
    final isLongHalt = haltMin >= 10;

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 3,
      children: [
        Text('${Fmt.km(_s.distanceFromOriginKm)} km', style: muted),
        if (!_s.isPassThrough && platform != null)
          Text('Platform $platform', style: muted),
        if (_isGapOrLocal)
          Text(
            'Passes',
            style: AppText.label.copyWith(
              color: const Color(0xFFFBBF24),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        if (isLongHalt)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: GlassTheme.accentViolet.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '⏱️ $haltMin min halt',
              style: AppText.label.copyWith(color: GlassTheme.accentViolet, fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ),
        if (food != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.onTime.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '${food.emoji} ${food.foodName}',
              style: AppText.label.copyWith(color: AppColors.onTime, fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ),
      ],
    );
  }

  /// Platform from the route, or live if RailKit reported a different one.
  /// Null when unknown — the expanded detail then offers the lookup.
  String? get _staticPlatform {
    final live = _live?.platform?.trim();
    if (live != null && live.isNotEmpty && live != '0' && live != '—') {
      return live;
    }
    final p = _s.platform.trim();
    if (p.isEmpty || p == '0' || p == '—') return null;
    return p;
  }

  // ---------------------------------------------------------------------------
  // Expanded detail
  // ---------------------------------------------------------------------------

  Widget _details(BuildContext context) {
    final g = context.glass;

    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: GlassContainer(
        radius: 16,
        blurSigma: 14,
        strong: true,
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Arrival and Departure pills were removed: those times already sit
            // in the left and right time columns of this row, so repeating them
            // in the card was pure duplication. The card now carries only what
            // is *not* already on the row — a platform lookup when unknown, the
            // halt duration, and any note.
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (_staticPlatform == null && !_s.isPassThrough)
                  _platformPill(context),
                if (_haltLabel != null)
                  _infoPill(context, Icons.timer_outlined, 'Halt', _haltLabel!),
              ],
            ),
            if (_s.note != null) ...[
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded,
                      size: 15, color: g.textSecondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _s.note!,
                      style: AppText.label.copyWith(
                        color: g.textSecondary,
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String? get _haltLabel {
    final h = _s.haltMinutes;
    if (h == null || h <= 0) return null;
    return '$h min';
  }

  /// The platform pill, with the quota-aware fallback lookup.
  ///
  /// QUOTA: [stationPlatformProvider] is a lazy `FutureProvider.family`, so not
  /// watching it means no request is made. This method only runs from
  /// [_details], which only exists while the row is expanded — so nothing is
  /// fetched on render, and nothing for a collapsed row. `trainInfo` is cached
  /// server-side for 24h and by Riverpod for the session, so the ceiling is one
  /// request per train.
  Widget _platformPill(BuildContext context) {
    final pf = ref.watch(stationPlatformProvider(PlatformQuery(
      trainNumber: widget.trainNumber,
      stationCode: _s.code,
    )));

    return pf.when(
      loading: () =>
          _infoPill(context, Icons.tram_rounded, 'Platform', null, busy: true),
      // The provider returns null instead of throwing, so a failure and an
      // unknown platform land on the same honest treatment. No error state.
      error: (_, _) =>
          _infoPill(context, Icons.tram_rounded, 'Platform', 'Platform TBA'),
      data: (value) {
        final v = value?.trim() ?? '';
        return _infoPill(context, Icons.tram_rounded, 'Platform',
            v.isEmpty ? 'Platform TBA' : 'PF $v');
      },
    );
  }

  Widget _infoPill(
    BuildContext context,
    IconData icon,
    String label,
    String? value, {
    bool busy = false,
  }) {
    final g = context.glass;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: g.fill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: g.border.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: g.textSecondary),
          const SizedBox(width: 7),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  color: g.textMuted,
                  fontSize: 8.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.9,
                ),
              ),
              const SizedBox(height: 1),
              if (busy)
                SizedBox(
                  height: 14,
                  width: 30,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      height: 11,
                      width: 11,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.6,
                        color: g.textSecondary,
                      ),
                    ),
                  ),
                )
              else
                Text(
                  value ?? '',
                  style: TextStyle(
                    color: g.textPrimary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
