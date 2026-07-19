import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';

import '../data/pnr_service.dart';
import '../models/pnr_status.dart';
import '../models/train_summary.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../utils/haptics.dart';
import '../widgets/icon_action_button.dart';
import '../widgets/liquid_glass_button.dart';

/// PNR status: enter a 10-digit PNR, then see the train/route header, chart
/// status, and a per-passenger booking → current comparison. Backed by the
/// mock [PnrService]; result cards fade + slide in with a stagger.
class PnrStatusScreen extends ConsumerStatefulWidget {
  const PnrStatusScreen({super.key});

  @override
  ConsumerState<PnrStatusScreen> createState() => _PnrStatusScreenState();
}

enum _Phase { idle, loading, result, notFound }

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

    final result = await ref.read(pnrServiceProvider).lookup(pnr);
    if (!mounted || _submittedPnr != pnr) return; // superseded by a newer query
    setState(() {
      _result = result;
      _phase = result == null ? _Phase.notFound : _Phase.result;
    });
  }

  void _fillSample(String pnr) {
    Haptics.selection();
    _controller.text = pnr;
    _controller.selection = TextSelection.collapsed(offset: pnr.length);
    _submit();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(context),
            Expanded(
              child: ListView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                children: [
                  _InputCard(
                    controller: _controller,
                    focusNode: _focus,
                    isValid: _isValid,
                    length: _pnr.length,
                    onSubmit: _submit,
                    onSample: _fillSample,
                  ),
                  const SizedBox(height: 20),
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
    );
  }

  Widget _stateChild() {
    return switch (_phase) {
      _Phase.idle => const _IdleHint(key: ValueKey('idle')),
      _Phase.loading =>
        _LoadingCard(pnr: _submittedPnr, key: const ValueKey('loading')),
      _Phase.notFound =>
        _NotFoundState(pnr: _submittedPnr, key: const ValueKey('notfound')),
      _Phase.result => _PnrResultView(
          result: _result!,
          key: ValueKey('result-${_result!.pnr}'),
        ),
    };
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 16, 8),
      child: Row(
        children: [
          IconActionButton(
            icon: Icons.arrow_back_ios_new_rounded,
            iconSize: 18,
            background: false,
            onTap: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 4),
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
    required this.onSample,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isValid;
  final int length;
  final VoidCallback onSubmit;
  final ValueChanged<String> onSample;

  @override
  Widget build(BuildContext context) {
    final focused = focusNode.hasFocus;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.lineMuted),
        boxShadow: AppColors.floatingShadow(),
      ),
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
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: focused ? AppColors.accent : AppColors.lineMuted,
                width: focused ? 1.5 : 1,
              ),
            ),
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
                      hintText: '10-digit PNR',
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
          const SizedBox(height: 16),
          LiquidGlassButton(
            onPressed: isValid ? onSubmit : null,
            enabled: isValid,
            expand: true,
            cornerRadius: 18,
            tint: isValid ? AppColors.accent : null,
            glowColor: AppColors.accent,
            padding: const EdgeInsets.symmetric(vertical: 15),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.search_rounded,
                  size: 20,
                  color: isValid ? Colors.white : AppColors.textMuted,
                ),
                const SizedBox(width: 10),
                Text(
                  'Check PNR Status',
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                    color: isValid ? Colors.white : AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text('TRY A SAMPLE', style: AppText.overline.copyWith(fontSize: 9.5)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in PnrService.samples)
                _SampleChip(
                  label: s.label,
                  color: _sampleColor(s.label),
                  onTap: () => onSample(s.pnr),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Color _sampleColor(String label) => switch (label) {
        'Confirmed' => AppColors.onTime,
        'Waitlisted' => AppColors.cancelled,
        _ => AppColors.accentViolet,
      };
}

class _SampleChip extends StatelessWidget {
  const _SampleChip({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.lineMuted),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: AppText.label.copyWith(
                color: AppColors.textPrimary,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
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
      _ChartStatusCard(status: result.chartStatus),
      _PassengersHeader(
        total: result.passengers.length,
        confirmed: result.confirmedCount,
      ),
      for (final p in result.passengers) _PassengerCard(passenger: p),
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
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.lineMuted),
        boxShadow: AppColors.floatingShadow(blur: 22, y: 10, opacity: 0.3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
              const SizedBox(width: 10),
              _TypeBadge(type: t.type),
              const Spacer(),
              _pnrChip(),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            t.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.titleStrong.copyWith(fontSize: 16),
          ),
          const SizedBox(height: 18),
          _routeRow(t),
          const SizedBox(height: 16),
          Container(height: 1, color: AppColors.lineMuted),
          const SizedBox(height: 14),
          Row(
            children: [
              _metaChip(Icons.event_rounded, result.dateLabel),
              const SizedBox(width: 10),
              _metaChip(
                  Icons.airline_seat_recline_normal_rounded, result.classLabel),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pnrChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.lineMuted),
      ),
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
        _endpoint(t.departure, t.fromCode, t.fromName, false, 0),
        Expanded(child: _connector(t.duration)),
        _endpoint(t.arrival, t.toCode, t.toName, true, t.arrivalDayOffset),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.lineMuted),
      ),
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.lineMuted),
      ),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
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
  const _PassengerCard({required this.passenger});

  final PnrPassenger passenger;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.lineMuted),
      ),
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
          _comparison(),
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

  Widget _comparison() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.lineMuted),
      ),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
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
            'PNR not found',
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
    Widget disc = Container(
      width: 88,
      height: 88,
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.lineMuted),
        boxShadow: AppColors.floatingShadow(blur: 24, y: 8, opacity: 0.4),
      ),
      child: Icon(icon, size: 38, color: color),
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
