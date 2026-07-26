import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';

import '../data/railkit_service.dart';
import '../data/rapidapi_service.dart';
import '../data/train_platform_provider.dart';
import '../data/train_repository.dart';
import '../l10n/app_localizations.dart';
import '../models/rail_station.dart';
import '../models/train_summary.dart';
import '../theme/app_theme.dart';
import '../theme/glass_theme.dart';
import '../theme/motion.dart';
import '../utils/haptics.dart';
import '../widgets/glass_surface.dart';
import '../widgets/icon_action_button.dart';
import '../widgets/journey_duration_bar.dart';
import '../widgets/mesh_background.dart';
import '../widgets/running_days_row.dart';
import '../widgets/train_number_tag.dart';
import 'live_tracking_screen.dart';

/// Shows verified search results for a chosen route (FROM → TO).
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
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          const Positioned.fill(child: MeshBackground()),
          SafeArea(
            bottom: false,
            child: FutureBuilder<List<TrainSummary>>(
              future: trainRepository.betweenStations(from, to, date: date),
              builder: (context, snapshot) {
                final g = context.glass;
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Column(
                    children: [
                      _header(context, 0),
                      const Expanded(
                        child: Center(
                          child: CircularProgressIndicator(
                            color: GlassTheme.accentViolet,
                          ),
                        ),
                      ),
                    ],
                  );
                }

                if (snapshot.hasError) {
                  final err = snapshot.error;
                  final bool quota =
                      err is RailKitException && err.isQuota;
                  final String errorMsg = quota
                      ? 'Live railway data is temporarily unavailable — the monthly request limit was reached. Please check back later.'
                      : err is RapidApiException
                          ? err.message
                          : L10n.of(context).unableToFetchRoute;
                  return Column(
                    children: [
                      _header(context, 0),
                      Expanded(
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  quota
                                      ? Icons.hourglass_bottom_rounded
                                      : Icons.cloud_off_rounded,
                                  size: 48,
                                  color: quota ? g.statusPurple : g.statusRed,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  errorMsg,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: g.textPrimary,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                }

                final results = snapshot.data ?? [];
                if (results.isEmpty) {
                  return Column(
                    children: [
                      _header(context, 0),
                      Expanded(
                        child: Center(
                          child: Text(
                            'No trains found for ${from.code} → ${to.code}',
                            style: TextStyle(color: g.textSecondary, fontSize: 15),
                          ),
                        ),
                      ),
                    ],
                  );
                }

                // Group by the actual leg each train serves. Searching "SBC"
                // legitimately returns Bengaluru-cluster terminals (SMVB, YPR,
                // KJM), so each destination gets its own section header rather
                // than being silently lumped together.
                final rows = _groupByLeg(results);

                return Column(
                  children: [
                    _header(context, results.length),
                    Expanded(
                      child: AnimationLimiter(
                        child: ListView.builder(
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                          itemCount: rows.length,
                          itemBuilder: (context, i) {
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
                                      ? _LegHeader(
                                          fromName: row.fromName,
                                          toName: row.toName,
                                        )
                                      : _TrainCard(
                                          train: row.train!,
                                          onTap: () =>
                                              _track(context, row.train!),
                                          boardingCode: from.code,
                                          // Only the top few auto-load their
                                          // platform; the rest fetch on tap.
                                          autoFetchPlatform: row.cardIndex <
                                              _kAutoPlatformLookups,
                                        ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _track(BuildContext context, TrainSummary train) {
    Navigator.of(context).push(
      CupertinoPageRoute(builder: (_) => LiveTrackingScreen(train: train)),
    );
  }

  Widget _header(BuildContext context, int count) {
    final g = context.glass;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 16, 16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: g.border.withValues(alpha: 0.15)),
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
                    Text(from.code, style: AppText.titleStrong.copyWith(color: g.textPrimary)),
                    const SizedBox(width: 6),
                    Icon(Icons.arrow_forward_rounded, size: 16, color: g.textMuted),
                    const SizedBox(width: 6),
                    Text(to.code, style: AppText.titleStrong.copyWith(color: g.textPrimary)),
                  ],
                ),
              ),
              Text(
                '$count ${count == 1 ? 'train' : 'trains'}',
                style: AppText.label.copyWith(color: g.textMuted),
              ),
            ],
          ),
        ],
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

/// One flattened list entry: either a leg header ([train] == null) or a card.
class _Row {
  const _Row.header(this.fromName, this.toName)
      : train = null,
        cardIndex = -1;
  const _Row.card(
    TrainSummary this.train,
    this.fromName,
    this.toName,
    this.cardIndex,
  );

  final TrainSummary? train;
  final String fromName;
  final String toName;

  /// Position among CARDS only (headers excluded), used for the auto-fetch cap.
  final int cardIndex;
}

/// Flattens results into `[header, card, card, header, card, …]`, preserving the
/// order RailKit returned (departure time) within each leg.
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
    // Only add headers when there's more than one distinct leg — a single-leg
    // result set already has the pair in the screen header.
    if (order.length > 1) {
      rows.add(_Row.header(first.fromName, first.toName));
    }
    for (final t in group) {
      rows.add(_Row.card(t, t.fromName, t.toName, cardIndex++));
    }
  }
  return rows;
}

/// Section header: "Kayamkulam Jn  🚆  KSR Bengaluru".
class _LegHeader extends StatelessWidget {
  const _LegHeader({required this.fromName, required this.toName});

  final String fromName;
  final String toName;

  @override
  Widget build(BuildContext context) {
    final g = context.glass;
    final style = AppText.titleStrong.copyWith(
      color: GlassTheme.accentBlue,
      fontSize: 14.5,
      height: 1.25,
      fontWeight: FontWeight.w700,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: Text(fromName, style: style)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Icon(Icons.train_rounded,
                size: 20, color: g.textMuted.withValues(alpha: 0.8)),
          ),
          Expanded(
            child: Text(toName, style: style, textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }
}

class _TrainCard extends StatelessWidget {
  const _TrainCard({
    required this.train,
    required this.onTap,
    required this.boardingCode,
    this.autoFetchPlatform = false,
  });
  final TrainSummary train;
  final VoidCallback onTap;

  /// The FROM station the user picked — the platform we show is the one they
  /// actually board at, not the train's origin.
  final String boardingCode;

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
          // Soft transparent violet glow radiating around the whole card.
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
              // 1) Name on the left (wraps to 2 lines), number pill top-right.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      train.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: g.textPrimary,
                        fontSize: 15.5,
                        height: 1.25,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  TrainNumberTag(train.number, fontSize: 14),
                ],
              ),
              const SizedBox(height: 14),

              // 2) dep — [green dot · duration · red dot] — arr
              JourneyDurationBar(
                departure: train.departure,
                arrival: train.arrival,
                duration: train.duration,
                arrivalDayOffset: train.arrivalDayOffset,
              ),
              const SizedBox(height: 12),

              // 3) Real running days (green "Daily" or highlighted weekdays).
              RunningDaysRow(train: train),
              const SizedBox(height: 12),

              // Labeled chips: "Platform TBA" + "Live GPS"
              Row(
                children: [
                  _PlatformChip(
                    trainNumber: train.number,
                    stationCode: boardingCode,
                    autoFetch: autoFetchPlatform,
                  ),
                  const SizedBox(width: 8),
                  _chip(g, L10n.of(context).liveGps),
                ],
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }

  Widget _chip(GlassTheme g, String label) => _chipStatic(g, label);

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
      // Deferred: tappable, costs nothing until the user asks.
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
          // Confirmed platform: highlight it, it's the number people need.
          : _TrainCard._chipStatic(
              g,
              t.platformNumber(pf),
              accent: GlassTheme.accentBlue,
            ),
    );
  }
}
