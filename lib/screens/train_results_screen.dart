import 'package:flutter/material.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';

import '../data/train_repository.dart';
import '../models/rail_station.dart';
import '../models/train_summary.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../widgets/icon_action_button.dart';
import '../widgets/pressable.dart';
import 'live_tracking_screen.dart';

/// Mock list of trains for a chosen route. Each row navigates into live
/// tracking. Rows animate in with a staggered fade + slide-up.
class TrainResultsScreen extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final results = trainRepository.betweenStations(from, to);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _header(context, results.length),
            Expanded(
              child: AnimationLimiter(
                child: ListView.builder(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  itemCount: results.length,
                  itemBuilder: (context, i) => AnimationConfiguration.staggeredList(
                    position: i,
                    duration: Motion.listItem,
                    delay: Motion.listStagger,
                    child: SlideAnimation(
                      verticalOffset: 26,
                      curve: Motion.standard,
                      child: FadeInAnimation(
                        curve: Motion.standard,
                        child: _TrainCard(
                          train: results[i],
                          onTap: () => _track(context, results[i]),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _track(BuildContext context, TrainSummary train) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => LiveTrackingScreen(train: train)),
    );
  }

  Widget _header(BuildContext context, int count) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 16, 16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.lineMuted),
        ),
      ),
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
              const SizedBox(width: 4),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(from.code,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.titleStrong),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(Icons.arrow_right_alt_rounded,
                          size: 20, color: AppColors.accent),
                    ),
                    Flexible(
                      child: Text(to.code,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.titleStrong),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Text(
              '${from.name} → ${to.name}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.label
                  .copyWith(color: AppColors.textSecondary, fontSize: 12.5),
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Text(
              '${_dateLabel(date)} · $count trains',
              style: AppText.overline.copyWith(fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }

  String _dateLabel(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${days[(d.weekday - 1) % 7]}, ${d.day} ${months[(d.month - 1) % 12]}';
  }
}

class _TrainCard extends StatelessWidget {
  const _TrainCard({required this.train, required this.onTap});

  final TrainSummary train;
  final VoidCallback onTap;

  Color get _typeColor {
    switch (train.type.toLowerCase()) {
      case 'rajdhani':
      case 'shatabdi':
      case 'duronto':
      case 'vande bharat':
        return AppColors.accentViolet;
      case 'superfast':
      case 'sf':
        return AppColors.accent;
      default:
        return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Pressable(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.lineMuted),
            boxShadow: AppColors.floatingShadow(blur: 20, y: 8, opacity: 0.28),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Text(
                    train.number,
                    style: const TextStyle(
                      color: AppColors.accent,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(width: 10),
                  _typeBadge(),
                  const Spacer(),
                  Text(
                    train.daysLabel,
                    style: AppText.label
                        .copyWith(color: AppColors.textMuted, fontSize: 11.5),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  train.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.titleStrong.copyWith(fontSize: 15.5),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  _timeBlock(train.departure, train.fromCode, false),
                  Expanded(child: _durationConnector()),
                  _timeBlock(train.arrival, train.toCode, true),
                ],
              ),
              const SizedBox(height: 12),
              Container(height: 1, color: AppColors.lineMuted),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.sensors_rounded,
                      size: 15, color: AppColors.accent),
                  const SizedBox(width: 8),
                  Text(
                    'Tap to track live',
                    style: AppText.label.copyWith(
                        color: AppColors.textSecondary, fontSize: 12.5),
                  ),
                  const Spacer(),
                  Icon(Icons.arrow_forward_ios_rounded,
                      size: 14, color: AppColors.textMuted),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _typeBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _typeColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        train.type.toUpperCase(),
        style: TextStyle(
          color: _typeColor,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }

  Widget _timeBlock(String time, String code, bool alignEnd) {
    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          time,
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            Text(code,
                style: AppText.label
                    .copyWith(color: AppColors.textMuted, fontSize: 12)),
            if (alignEnd && train.arrivalDayOffset > 0)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text('+${train.arrivalDayOffset}d',
                    style: const TextStyle(
                        color: AppColors.delayed,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700)),
              ),
          ],
        ),
      ],
    );
  }

  Widget _durationConnector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: [
          Text(
            train.duration,
            style: AppText.label.copyWith(
                color: AppColors.textSecondary, fontSize: 11.5),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const _Dot(),
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
              const _Dot(),
            ],
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        color: AppColors.accent,
        shape: BoxShape.circle,
      ),
    );
  }
}
