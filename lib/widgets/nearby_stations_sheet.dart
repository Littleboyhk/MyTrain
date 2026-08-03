import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/nearest_station_service.dart';
import '../data/station_repository.dart';
import '../models/rail_station.dart';
import '../theme/app_theme.dart';
import '../theme/glass_theme.dart';
import '../utils/haptics.dart';
import 'glass_container.dart';
import 'station_row_tile.dart';

/// Nearby railway stations, nearest first.
///
/// Returns the station the user picked, or null if they dismissed the sheet —
/// the same contract as [StationPickerScreen], so callers handle both the same
/// way and there is only one station-selection pattern in the app.
///
/// [initial] lets the caller hand over a fix it has already taken, which is what
/// stops a tap followed by a hold from asking the device for two positions in a
/// row. Pass null and the sheet acquires one itself, showing a loading state
/// while it does.
Future<RailStation?> showNearbyStationsSheet(
  BuildContext context, {
  NearestStationFound? initial,
}) {
  return showModalBottomSheet<RailStation>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    isScrollControlled: true,
    builder: (ctx) => _NearbyStationsSheet(initial: initial),
  );
}

class _NearbyStationsSheet extends ConsumerStatefulWidget {
  const _NearbyStationsSheet({this.initial});

  final NearestStationFound? initial;

  @override
  ConsumerState<_NearbyStationsSheet> createState() =>
      _NearbyStationsSheetState();
}

class _NearbyStationsSheetState extends ConsumerState<_NearbyStationsSheet> {
  NearestStationFound? _found;
  NearestStationFailure? _failure;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _found = widget.initial;
    // Only reach for a fix when the caller had none. Opening the sheet off the
    // back of a tap that already located the user must not re-request.
    if (_found == null) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failure = null;
    });

    final result = await ref.read(nearestStationServiceProvider).find();
    if (!mounted) return;

    setState(() {
      _loading = false;
      switch (result) {
        case NearestStationFound():
          _found = result;
          _failure = null;
        case NearestStationFailure():
          _failure = result;
      }
    });
  }

  /// Mirrors `StationPickerScreen._select`: record it as recent, then hand it
  /// back. Anything the app already does with a picked station happens for free.
  void _select(RailStation station) {
    Haptics.selection();
    ref.read(recentStationsProvider.notifier).add(station);
    Navigator.of(context).pop(station);
  }

  @override
  Widget build(BuildContext context) {
    final g = context.glass;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(left: 12, right: 12, bottom: 12 + bottomInset),
      child: GlassContainer(
        radius: 28,
        blurSigma: 24,
        strong: true,
        glow: true,
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
        child: ConstrainedBox(
          // Tall enough for a useful list, short enough that the sheet still
          // reads as a sheet rather than a page.
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.62,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(g),
              const SizedBox(height: 12),
              Flexible(child: _body(g)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(GlassTheme g) {
    final found = _found;
    final accuracy = found?.accuracyM;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.near_me_rounded, size: 18, color: GlassTheme.accentViolet),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Nearby stations',
                style: AppText.titleStrong
                    .copyWith(color: g.textPrimary, fontSize: 18),
              ),
              const SizedBox(height: 3),
              Text(
                // States the precision rather than implying the distances are
                // exact — a 40 m fix and a 4 m fix are not the same claim.
                accuracy != null
                    ? 'Sorted by distance · fix accurate to ${accuracy.round()} m'
                    : 'Sorted by distance from you',
                style: AppText.label.copyWith(color: g.textMuted, fontSize: 11.5),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _body(GlassTheme g) {
    if (_loading) return _Loading(g: g);

    final failure = _failure;
    if (failure != null) {
      return _Message(
        g: g,
        icon: failure.error == NearestStationError.permissionDenied ||
                failure.error == NearestStationError.locationServiceOff
            ? Icons.location_disabled_rounded
            : Icons.location_searching_rounded,
        message: failure.message,
        actionLabel: 'Try again',
        onAction: _load,
      );
    }

    final found = _found;
    // Defensive: the service never returns an empty list — an empty result is a
    // failure with noStationNearby — but a broken page here would be worse than
    // a redundant branch.
    if (found == null || found.nearby.isEmpty) {
      return _Message(
        g: g,
        icon: Icons.explore_off_rounded,
        message: 'No railway stations found near you.',
        actionLabel: 'Try again',
        onAction: _load,
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.only(bottom: 6),
      itemCount: found.nearby.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final entry = found.nearby[i];
        return StationRowTile(
          station: entry.station,
          subtitle: '${entry.station.code} · ${entry.distanceLabel} away',
          onTap: () => _select(entry.station),
        );
      },
    );
  }
}

/// Body height reserved while the sheet has no list to show.
///
/// WHY IT IS RESERVED RATHER THAN INTRINSIC. The sheet sizes to its content
/// (`MainAxisSize.min`) and a modal bottom sheet is anchored to the bottom of the
/// screen, so a bare spinner collapsed the whole thing into a thin strip sitting
/// low — everything above it was the barrier, not sheet interior. Holding a block
/// of height open gives the sheet real presence and gives the spinner somewhere to
/// be centred, directly under the pinned header.
///
/// Deliberately smaller than the populated list, so results arriving grow the
/// sheet rather than shrink it.
const double _transientBodyHeight = 180;

class _Loading extends StatelessWidget {
  const _Loading({required this.g});

  final GlassTheme g;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      // Full width because the enclosing Column aligns children to the start,
      // which would otherwise leave this hugging the left edge.
      width: double.infinity,
      height: _transientBodyHeight,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: GlassTheme.accentViolet,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Finding stations near you…',
              style: AppText.label.copyWith(color: g.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.g,
    required this.icon,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final GlassTheme g;
  final IconData icon;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      // Same treatment as the loading state: these are the other two bodies with
      // nothing to scroll, and they sat equally low. Only the populated list is
      // top-aligned.
      width: double.infinity,
      height: _transientBodyHeight,
      child: Center(
        child: Padding(
          // Keeps a long failure message off the sheet's rounded edges.
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 34, color: g.textMuted),
              const SizedBox(height: 14),
              Text(
                message,
                textAlign: TextAlign.center,
                style: AppText.label.copyWith(
                  color: g.textSecondary,
                  height: 1.4,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 18),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onAction,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 11),
                  decoration: BoxDecoration(
                    gradient: GlassTheme.accent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    actionLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
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
}
