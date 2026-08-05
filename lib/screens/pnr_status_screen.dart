import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';

import '../data/pnr_service.dart';
import '../data/railkit_service.dart';
import '../data/saved_pnr_store.dart';
import '../l10n/app_localizations.dart';
import '../models/pnr_status.dart';
import '../models/train_summary.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/glass_theme.dart';
import '../theme/motion.dart';
import '../utils/haptics.dart';
import '../utils/train_name.dart';
import '../widgets/berth_bay_view.dart';
import '../widgets/glass_surface.dart';
import '../widgets/icon_action_button.dart';
import '../widgets/liquid_glass_button.dart';
import '../widgets/mesh_background.dart';
import '../widgets/train_number_tag.dart';
import 'coach_position_screen.dart';

/// PNR status: enter a 10-digit PNR, then see the train/route header, chart
/// status, and a per-passenger booking → current comparison. Backed by the
/// mock [PnrService]; result cards fade + slide in with a stagger.
class PnrStatusScreen extends ConsumerStatefulWidget {
  const PnrStatusScreen({super.key, this.embedded = false});

  /// When shown as a bottom-dock tab (not a pushed route): hide the back
  /// button, make the scaffold transparent so the home mesh shows through,
  /// and pad the bottom so content clears the floating dock.
  final bool embedded;

  @override
  ConsumerState<PnrStatusScreen> createState() => _PnrStatusScreenState();
}

enum _Phase { idle, loading, result, notFound, quota }

class _PnrStatusScreenState extends ConsumerState<PnrStatusScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();

  String _pnr = '';
  _Phase _phase = _Phase.idle;
  PnrResult? _result;
  String _submittedPnr = '';

  bool get _isValid => _pnr.length == 10;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      if (_controller.text != _pnr) {
        setState(() => _pnr = _controller.text);
      }
    });
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_isValid) return;
    _focus.unfocus();
    Haptics.confirm();
    final pnr = _pnr;
    setState(() {
      _submittedPnr = pnr;
      _phase = _Phase.loading;
      _result = null;
    });

    PnrResult? result;
    try {
      result = await ref.read(pnrServiceProvider).lookup(pnr);
    } on RailKitException catch (e) {
      if (!mounted || _submittedPnr != pnr) return;
      // Quota is the only RailKit error that escapes lookup(); everything else
      // falls back internally. Show "check back later", never mock data.
      setState(() => _phase = e.isQuota ? _Phase.quota : _Phase.notFound);
      return;
    }
    if (!mounted || _submittedPnr != pnr) return; // superseded by a newer query
    setState(() {
      _result = result;
      _phase = result == null ? _Phase.notFound : _Phase.result;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          if (!widget.embedded) const Positioned.fill(child: MeshBackground()),
          SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(context),
            Expanded(
              child: ListView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                physics: const BouncingScrollPhysics(),
                padding:
                    EdgeInsets.fromLTRB(16, 8, 16, widget.embedded ? 120 : 40),
                children: [
                  _InputCard(
                    controller: _controller,
                    focusNode: _focus,
                    isValid: _isValid,
                    length: _pnr.length,
                    onSubmit: _submit,
                  ),
                  const SizedBox(height: 16),
                  _SavedTicketsSection(
                    onSelectPnr: (savedPnr) {
                      Haptics.selection();
                      _controller.text = savedPnr.pnr;
                      _pnr = savedPnr.pnr;
                      setState(() {
                        _submittedPnr = savedPnr.pnr;
                        _result = savedPnr;
                        _phase = _Phase.result;
                      });
                      _submit();
                    },
                  ),
                  const SizedBox(height: 16),
                  AnimatedSwitcher(
                    duration: Motion.medium,
                    switchInCurve: Motion.standard,
                    switchOutCurve: Motion.standard,
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: child,
                    ),
                    layoutBuilder: (current, previous) => Stack(
                      alignment: Alignment.topCenter,
                      children: [
                        ...previous,
                        ?current,
                      ],
                    ),
                    child: _stateChild(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
        ],
      ),
    );
  }

  Widget _stateChild() {
    return switch (_phase) {
      _Phase.idle => const _IdleHint(key: ValueKey('idle')),
      _Phase.loading =>
        _LoadingCard(pnr: _submittedPnr, key: const ValueKey('loading')),
      _Phase.notFound =>
        _NotFoundState(pnr: _submittedPnr, key: const ValueKey('notfound')),
      _Phase.quota => const _QuotaState(key: ValueKey('quota')),
      _Phase.result => _PnrResultView(
          result: _result!,
          key: ValueKey('result-${_result!.pnr}'),
        ),
    };
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(widget.embedded ? 20 : 12, 8, 16, 8),
      child: Row(
        children: [
          if (!widget.embedded) ...[
            IconActionButton(
              icon: Icons.arrow_back_ios_new_rounded,
              iconSize: 18,
              background: false,
              onTap: () => Navigator.of(context).maybePop(),
            ),
            const SizedBox(width: 4),
          ],
          Text('PNR Status', style: AppText.titleStrong.copyWith(fontSize: 20)),
        ],
      ),
    );
  }
}

// ===========================================================================
// Input card
// ===========================================================================
class _InputCard extends StatelessWidget {
  const _InputCard({
    required this.controller,
    required this.focusNode,
    required this.isValid,
    required this.length,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isValid;
  final int length;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final focused = focusNode.hasFocus;

    return GlassSurface(
      radius: 22,
      strong: true,
      glow: true,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('ENTER PNR', style: AppText.overline),
              const Spacer(),
              Text(
                '$length/10',
                style: AppText.label.copyWith(
                  color: isValid ? AppColors.onTime : AppColors.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          AnimatedContainer(
            duration: Motion.fast,
            curve: Motion.standard,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: focused
                  ? [
                      BoxShadow(
                        color: AppColors.accent.withValues(alpha: 0.30),
                        blurRadius: 20,
                        spreadRadius: -4,
                      ),
                    ]
                  : const [],
            ),
            // Glass-lite well: shared gradient rim instead of a flat border.
            child: GlassSurface(
              radius: 16,
              blur: 0,
              strong: focused,
              compact: true,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
              children: [
                const Icon(Icons.confirmation_number_outlined,
                    size: 20, color: AppColors.accent),
                const SizedBox(width: 14),
                Expanded(
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(10),
                    ],
                    style: AppText.stationName.copyWith(
                      fontSize: 18,
                      letterSpacing: 2.0,
                      fontWeight: FontWeight.w700,
                    ),
                    cursorColor: AppColors.accent,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: L10n.of(context).pnrHint,
                      hintStyle: AppText.label.copyWith(
                        color: AppColors.textMuted,
                        letterSpacing: 0.5,
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 18),
                    ),
                    onSubmitted: (_) => onSubmit(),
                  ),
                ),
                if (length > 0)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => controller.clear(),
                    child: Icon(Icons.close_rounded,
                        size: 18, color: AppColors.textSecondary),
                  ),
              ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          GlassSurface(
            radius: 999,
            blur: 16,
            padding: const EdgeInsets.all(3.5),
            child: LiquidGlassButton(
              onPressed: isValid ? onSubmit : null,
              enabled: isValid,
              expand: true,
              cornerRadius: 999,
              gradient: isValid
                  ? const LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Color(0xFF8B5CF6), // Vibrant Violet
                        Color(0xFF6366F1), // Electric Indigo
                      ],
                    )
                  : null,
              glowColor: const Color(0xFF8B5CF6),
              padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 16),
              semanticLabel: L10n.of(context).pnrCheckCta,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.search_rounded,
                    size: 19,
                    color: isValid ? Colors.white : AppColors.textMuted,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    L10n.of(context).pnrCheckCta,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                      color: isValid ? Colors.white : AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Result view (staggered)
// ===========================================================================
class _PnrResultView extends StatelessWidget {
  const _PnrResultView({super.key, required this.result});

  final PnrResult result;

  @override
  Widget build(BuildContext context) {
    final sections = <Widget>[
      _HeaderCard(result: result),
      // Omitted when the provider did not state it. "Chart prepared" is a claim
      // a passenger acts on, so silence beats a default.
      if (result.chartStatus != null)
        _ChartStatusCard(status: result.chartStatus!),
      _PassengersHeader(
        total: result.passengers.length,
        confirmed: result.confirmedCount,
      ),
      for (final p in result.passengers)
        _PassengerCard(
          passenger: p,
          travelClass: result.travelClass,
          trainNumber: result.train.number,
          trainName: result.train.name,
        ),
      const _FooterNote(),
    ];

    return AnimationLimiter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: AnimationConfiguration.toStaggeredList(
          duration: Motion.listItem,
          delay: Motion.listStagger,
          childAnimationBuilder: (child) => SlideAnimation(
            verticalOffset: 26,
            curve: Motion.standard,
            child: FadeInAnimation(curve: Motion.standard, child: child),
          ),
          children: [
            for (final section in sections)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: section,
              ),
          ],
        ),
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.result});

  final PnrResult result;

  @override
  Widget build(BuildContext context) {
    final t = result.train;
    return GlassSurface(
      radius: 20,
      strong: true,
      glow: true,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _TypeBadge(type: t.type),
              const Spacer(),
              _pnrChip(),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              TrainNumberTag(t.number, fontSize: 14),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // The provider's own name stays primary. `YPR TVCN GR EXP` is
                    // what RailKit sends and what is printed on the ticket.
                    Text(
                      t.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.titleStrong.copyWith(fontSize: 16),
                    ),
                    // The readable long form, DERIVED. Secondary and muted because
                    // it is ours, not the railway's — see expandTrainName. Omitted
                    // entirely when nothing could be expanded, rather than
                    // repeating the line above.
                    if (expandTrainName(t.name) case final String long)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          long,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.label.copyWith(
                            color: AppColors.textMuted,
                            fontSize: 11.5,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _routeRow(t),
          const SizedBox(height: 16),
          Container(height: 1, color: AppColors.lineMuted),
          const SizedBox(height: 14),
          // Each chip is omitted rather than dashed when unknown: an empty chip
          // is noise, and a guessed date or class is worse.
          Row(
            children: [
              if (result.dateLabel != null)
                _metaChip(Icons.event_rounded, result.dateLabel!),
              if (result.dateLabel != null && result.classLabel != null)
                const SizedBox(width: 10),
              if (result.classLabel != null)
                _metaChip(Icons.airline_seat_recline_normal_rounded,
                    result.classLabel!),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pnrChip() {
    return GlassSurface(
      radius: 999,
      blur: 0,
      pill: true,
      compact: true,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.confirmation_number_outlined,
              size: 13, color: AppColors.textMuted),
          const SizedBox(width: 6),
          Text(
            result.pnr,
            style: AppText.label.copyWith(
              color: AppColors.textSecondary,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _routeRow(TrainSummary t) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // A PNR response carries no timetable, so these are routinely null here.
        // An em dash is the honest render; this used to show 17:00 / 08:35.
        _endpoint(t.departure ?? '—', t.fromCode, t.fromName, false, 0),
        Expanded(child: _connector(t.duration ?? '—')),
        _endpoint(t.arrival ?? '—', t.toCode, t.toName, true, t.arrivalDayOffset),
      ],
    );
  }

  Widget _endpoint(
    String time,
    String code,
    String name,
    bool alignEnd,
    int dayOffset,
  ) {
    final cross = alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    return SizedBox(
      width: 96,
      child: Column(
        crossAxisAlignment: cross,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                time,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              if (alignEnd && dayOffset > 0)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Text(
                    '+${dayOffset}d',
                    style: const TextStyle(
                      color: AppColors.delayed,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            code,
            style: AppText.label.copyWith(
              color: AppColors.textSecondary,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: alignEnd ? TextAlign.end : TextAlign.start,
            style: AppText.label.copyWith(
              color: AppColors.textMuted,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _connector(String duration) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        children: [
          Text(
            duration,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.label.copyWith(
              color: AppColors.textSecondary,
              fontSize: 11.5,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              _dot(),
              Expanded(
                child: Container(
                  height: 1.5,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  color: AppColors.lineSolid,
                ),
              ),
              Icon(Icons.train_rounded,
                  size: 14, color: AppColors.textSecondary),
              Expanded(
                child: Container(
                  height: 1.5,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  color: AppColors.lineSolid,
                ),
              ),
              _dot(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dot() => Container(
        width: 6,
        height: 6,
        decoration: const BoxDecoration(
          color: AppColors.accent,
          shape: BoxShape.circle,
        ),
      );

  Widget _metaChip(IconData icon, String text) {
    return GlassSurface(
      radius: 10,
      blur: 0,
      compact: true,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.accent),
          const SizedBox(width: 7),
          Text(
            text,
            style: AppText.label.copyWith(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.type});

  final String type;

  Color get _color => switch (type.toLowerCase()) {
        'rajdhani' || 'shatabdi' || 'duronto' || 'vande bharat' =>
          AppColors.accentViolet,
        'superfast' || 'sf' => AppColors.accent,
        _ => AppColors.textSecondary,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        type.toUpperCase(),
        style: TextStyle(
          color: _color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _ChartStatusCard extends StatelessWidget {
  const _ChartStatusCard({required this.status});

  final ChartStatus status;

  @override
  Widget build(BuildContext context) {
    final color = status.color;
    return GlassSurface(
      radius: 18,
      strong: true,
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              shape: BoxShape.circle,
              border: Border.all(color: color.withValues(alpha: 0.4)),
            ),
            child: Icon(status.icon, size: 20, color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('CHART STATUS', style: AppText.overline),
                    const Spacer(),
                    _pill(color),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  status.detail,
                  style: AppText.label.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pill(Color color) {
    return GlassSurface(
      radius: 999,
      blur: 0,
      pill: true,
      compact: true,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Text(
        status.short,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _PassengersHeader extends StatelessWidget {
  const _PassengersHeader({required this.total, required this.confirmed});

  final int total;
  final int confirmed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 0),
      child: Row(
        children: [
          Text('PASSENGERS', style: AppText.overline),
          const Spacer(),
          Text(
            '$confirmed of $total confirmed',
            style: AppText.label.copyWith(
              color: AppColors.textMuted,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _PassengerCard extends StatelessWidget {
  const _PassengerCard({
    required this.passenger,
    required this.travelClass,
    required this.trainNumber,
    required this.trainName,
  });

  final PnrPassenger passenger;
  final String? travelClass;
  final String trainNumber;
  final String trainName;

  @override
  Widget build(BuildContext context) {
    final g = context.glass;
    return GlassSurface(
      radius: 18,
      strong: true,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              _indexBadge(),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Passenger ${passenger.index}',
                      style: AppText.label.copyWith(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      passenger.current.detail ?? passenger.current.status.label,
                      style: AppText.label.copyWith(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              _StatusPill(status: passenger.current.status),
            ],
          ),
          const SizedBox(height: 14),
          _comparison(g),
          if (passenger.current.status == PassengerStatus.confirmed) ...[
            const SizedBox(height: 14),
            BerthBayView(
              travelClass: travelClass,
              allocation: passenger.current,
            ),
            if (passenger.current.coach != null) ...[
              const SizedBox(height: 12),
              InkWell(
                onTap: () {
                  Haptics.selection();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => CoachPositionScreen(
                        trainNumber: trainNumber,
                        trainName: trainName,
                        initialCoach: passenger.current.coach,
                        initialBerth: int.tryParse(passenger.current.berth ?? ''),
                      ),
                    ),
                  );
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xFF6366F1), // Electric Indigo
                        Color(0xFF8B5CF6), // Vibrant Violet
                      ],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF6366F1).withValues(alpha: 0.45),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.pin_drop_rounded, size: 17, color: Colors.white),
                      const SizedBox(width: 8),
                      Text(
                        'Locate Coach ${passenger.current.coach}${passenger.current.berth != null ? ' · Berth #${passenger.current.berth}' : ''} ➔',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _indexBadge() {
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.12),
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
      ),
      child: Text(
        '${passenger.index}',
        style: const TextStyle(
          color: AppColors.accent,
          fontSize: 14,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _comparison(GlassTheme g) {
    return GlassSurface(
      radius: 14,
      blur: 0,
      compact: true,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Expanded(child: _allocation('BOOKING', passenger.booking, false)),
          _arrow(),
          Expanded(child: _allocation('CURRENT', passenger.current, true)),
        ],
      ),
    );
  }

  Widget _allocation(String label, SeatAllocation alloc, bool emphasized) {
    final cross = emphasized ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final valueColor =
        emphasized ? alloc.status.color : AppColors.textSecondary;
    return Column(
      crossAxisAlignment: cross,
      children: [
        Text(label, style: AppText.overline.copyWith(fontSize: 9.5)),
        const SizedBox(height: 6),
        Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment:
              emphasized ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            if (!emphasized)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Icon(alloc.status.icon,
                    size: 15, color: AppColors.textMuted),
              ),
            Flexible(
              child: Text(
                alloc.display,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: valueColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                ),
              ),
            ),
            if (emphasized)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Icon(alloc.status.icon, size: 15, color: valueColor),
              ),
          ],
        ),
        if (alloc.detail != null) ...[
          const SizedBox(height: 2),
          Text(
            alloc.detail!,
            style: AppText.label.copyWith(
              color: AppColors.textMuted,
              fontSize: 11,
            ),
          ),
        ],
      ],
    );
  }

  Widget _arrow() {
    final improved = passenger.improved;
    final worsened = passenger.worsened;
    final color = improved
        ? AppColors.onTime
        : worsened
            ? AppColors.cancelled
            : AppColors.textMuted;
    final icon = improved
        ? Icons.trending_up_rounded
        : worsened
            ? Icons.trending_down_rounded
            : Icons.arrow_forward_rounded;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          if (improved || worsened)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                improved ? 'Upgraded' : 'Dropped',
                style: TextStyle(
                  color: color,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final PassengerStatus status;

  @override
  Widget build(BuildContext context) {
    final color = status.color;
    return GlassSurface(
      radius: 999,
      blur: 0,
      pill: true,
      compact: true,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(status.icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            status.code,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _FooterNote extends StatelessWidget {
  const _FooterNote();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.info_outline_rounded,
              size: 13, color: AppColors.textMuted),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              'Demo data — live PNR needs a backend connection.',
              style: AppText.label.copyWith(
                color: AppColors.textMuted,
                fontSize: 11.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Idle / loading / not-found states
// ===========================================================================
class _IdleHint extends StatelessWidget {
  const _IdleHint({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
      child: Column(
        children: [
          _GlassDisc(
            icon: Icons.confirmation_number_rounded,
            color: AppColors.accent,
          ),
          const SizedBox(height: 24),
          Text(
            'Check your PNR status',
            textAlign: TextAlign.center,
            style: AppText.titleStrong.copyWith(fontSize: 18),
          ),
          const SizedBox(height: 10),
          Text(
            'Enter the 10-digit PNR from your ticket to see coach, berth and '
            'confirmation status for every passenger.',
            textAlign: TextAlign.center,
            style: AppText.label.copyWith(
              color: AppColors.textSecondary,
              height: 1.45,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard({super.key, required this.pnr});

  final String pnr;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
      child: Column(
        children: [
          _GlassDisc(
            icon: Icons.travel_explore_rounded,
            color: AppColors.accent,
            pulse: true,
          ),
          const SizedBox(height: 24),
          Text(
            'Fetching PNR status',
            textAlign: TextAlign.center,
            style: AppText.titleStrong.copyWith(fontSize: 17),
          )
              .animate(onPlay: (c) => c.repeat())
              .shimmer(
                duration: const Duration(milliseconds: 1200),
                color: AppColors.accent.withValues(alpha: 0.5),
              ),
          const SizedBox(height: 8),
          Text(
            'PNR $pnr',
            style: AppText.label.copyWith(
              color: AppColors.textMuted,
              fontSize: 12.5,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _NotFoundState extends StatelessWidget {
  const _NotFoundState({super.key, required this.pnr});

  final String pnr;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
      child: Column(
        children: [
          _GlassDisc(
            icon: Icons.search_off_rounded,
            color: AppColors.delayed,
            float: true,
          ),
          const SizedBox(height: 24),
          Text(
            L10n.of(context).pnrNotFoundTitle,
            textAlign: TextAlign.center,
            style: AppText.titleStrong.copyWith(fontSize: 20),
          ),
          const SizedBox(height: 10),
          Text(
            "We couldn't find PNR $pnr. Double-check the 10-digit number on "
            'your ticket and try again.',
            textAlign: TextAlign.center,
            style: AppText.label.copyWith(
              color: AppColors.textSecondary,
              height: 1.45,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Tip: tap a sample above to see a live example.',
            textAlign: TextAlign.center,
            style: AppText.label.copyWith(
              color: AppColors.textMuted,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown when RailKit's monthly/burst request budget is reached (429). We do
/// NOT fall back to sample data here — the user should know it's temporary.
class _QuotaState extends StatelessWidget {
  const _QuotaState({super.key});

  @override
  Widget build(BuildContext context) {
    final g = context.glass;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
      child: Column(
        children: [
          _GlassDisc(
            icon: Icons.hourglass_bottom_rounded,
            color: g.statusPurple,
            float: true,
          ),
          const SizedBox(height: 24),
          Text(
            L10n.of(context).checkBackLaterTitle,
            textAlign: TextAlign.center,
            style: AppText.titleStrong.copyWith(fontSize: 20),
          ),
          const SizedBox(height: 10),
          Text(
            'Live PNR lookups are temporarily unavailable because the monthly '
            'request limit was reached. Please try again later.',
            textAlign: TextAlign.center,
            style: AppText.label.copyWith(
              color: AppColors.textSecondary,
              height: 1.45,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

/// Soft glassy disc holding an icon, used by the idle / loading / not-found
/// states. Optionally pulses (loading) or gently floats (empty states).
class _GlassDisc extends StatelessWidget {
  const _GlassDisc({
    required this.icon,
    required this.color,
    this.pulse = false,
    this.float = false,
  });

  final IconData icon;
  final Color color;
  final bool pulse;
  final bool float;

  @override
  Widget build(BuildContext context) {
    Widget disc = SizedBox(
      width: 88,
      height: 88,
      child: GlassSurface(
        radius: 44,
        strong: true,
        glow: true,
        child: Center(child: Icon(icon, size: 38, color: color)),
      ),
    );

    if (pulse) {
      disc = disc
          .animate(onPlay: (c) => c.repeat(reverse: true))
          .scaleXY(
            begin: 0.94,
            end: 1.05,
            duration: const Duration(milliseconds: 900),
            curve: Motion.pulse,
          );
    } else if (float) {
      disc = disc
          .animate(onPlay: (c) => c.repeat(reverse: true))
          .moveY(
            begin: -5,
            end: 5,
            duration: Motion.emptyFloat,
            curve: Motion.pulse,
          );
    }

    return disc;
  }
}

// ===========================================================================
// Saved Tickets Section
// ===========================================================================
class _SavedTicketsSection extends StatefulWidget {
  const _SavedTicketsSection({required this.onSelectPnr});
  final ValueChanged<PnrResult> onSelectPnr;

  @override
  State<_SavedTicketsSection> createState() => _SavedTicketsSectionState();
}

class _SavedTicketsSectionState extends State<_SavedTicketsSection> {
  List<PnrResult> _pnrs = [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() async {
    final list = await SavedPnrStore.instance.getSavedPnrs();
    if (mounted) setState(() => _pnrs = list);
  }

  @override
  Widget build(BuildContext context) {
    if (_pnrs.isEmpty) return const SizedBox.shrink();
    final g = context.glass;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.confirmation_number_rounded,
                size: 16, color: GlassTheme.accentIndigo),
            const SizedBox(width: 6),
            Text(
              'My Saved Tickets (${_pnrs.length})',
              style: TextStyle(
                color: g.textPrimary,
                fontSize: 14.5,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Column(
          children: [
            for (final p in _pnrs) ...[
              _SavedTicketCard(
                result: p,
                onTap: () => widget.onSelectPnr(p),
                onDelete: () async {
                  await SavedPnrStore.instance.removePnr(p.pnr);
                  _reload();
                },
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ],
    );
  }
}

class _SavedTicketCard extends StatelessWidget {
  const _SavedTicketCard({
    required this.result,
    required this.onTap,
    required this.onDelete,
  });

  final PnrResult result;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final g = context.glass;
    final firstPassenger = result.passengers.first;
    final status = firstPassenger.current.status;
    final pillText = firstPassenger.current.display;

    return Dismissible(
      key: Key('saved_pnr_${result.pnr}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDelete(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.redAccent.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 22),
      ),
      child: GestureDetector(
        onTap: onTap,
        child: GlassSurface(
          radius: 16,
          strong: true,
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'PNR ${result.pnr}',
                    style: TextStyle(
                      color: g.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: status.color.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: status.color.withValues(alpha: 0.6),
                        width: 1.2,
                      ),
                    ),
                    child: Text(
                      pillText,
                      style: TextStyle(
                        color: status.color,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onDelete,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.delete_outline_rounded,
                        size: 18,
                        color: g.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                '${result.train.number} · ${result.train.name}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: g.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    '${result.train.fromCode} ➔ ${result.train.toCode}',
                    style: TextStyle(
                      color: g.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  if (result.travelClass != null)
                    Text(
                      result.travelClass!,
                      style: const TextStyle(
                        color: GlassTheme.accentBlue,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
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
}
