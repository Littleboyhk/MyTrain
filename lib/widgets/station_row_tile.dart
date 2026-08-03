import 'package:flutter/material.dart';

import '../models/rail_station.dart';
import '../theme/app_theme.dart';
import '../theme/glass_theme.dart';
import 'glass_container.dart';

/// The app's one station list row: glass card, violet code badge, name, a
/// secondary line, and a trailing affordance.
///
/// EXTRACTED, NOT INVENTED. This was `_StationRow`, private to
/// `station_picker_screen.dart`. The nearby-stations sheet needs the same row
/// with a distance on the second line, and copying it would have left the app
/// with two station list styles that drift apart. So it moved here unchanged and
/// gained two optional overrides — [subtitle] and [trailing] — for callers that
/// need to say something other than the station code.
///
/// NO BACKDROP BLUR — THIS IS DELIBERATE. This row previously used
/// `blurSigma: 15`, which meant one `BackdropFilter` per visible row inside a
/// `ListView.separated`. That is the most expensive shape blur can take: the
/// filter is re-evaluated for every row on every scroll frame, and the count
/// scales with how much of the list is on screen.
///
/// The glass look now comes from the fill, rim and glow only (`blurSigma: 0`,
/// `strong: true` to compensate). Two things make that hold up rather than look
/// flat: the rows sit on the aurora, which is already a soft low-frequency
/// gradient with nothing sharp to blur away; and in the nearby-stations sheet the
/// parent sheet is itself a blurred surface, so the old per-row filter was
/// blurring an already-blurred backdrop — pure cost, no visual gain.
///
/// If a caller genuinely needs a blurred row, blur the LIST CONTAINER once
/// rather than restoring it here.
class StationRowTile extends StatelessWidget {
  const StationRowTile({
    super.key,
    required this.station,
    required this.onTap,
    this.query = '',
    this.subtitle,
    this.trailing,
  });

  final RailStation station;
  final VoidCallback onTap;

  /// Substring to highlight in the name, for search results. Empty means no
  /// highlighting.
  final String query;

  /// Replaces the default `Station code · XXX` line.
  final String? subtitle;

  /// Replaces the default north-east arrow.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final g = context.glass;
    return GlassContainer(
      radius: 20,
      // See the class doc: no per-row BackdropFilter. `strong` raises the fill
      // opacity so the row still reads as a distinct card without one.
      blurSigma: 0,
      strong: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              // Glass Station Code Badge
              GlassContainer(
                radius: 12,
                blurSigma: 0,
                strong: true,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Text(
                  station.code,
                  style: const TextStyle(
                    color: GlassTheme.accentViolet,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _highlightedName(context),
                    const SizedBox(height: 2),
                    Text(
                      subtitle ?? 'Station code · ${station.code}',
                      style: AppText.label.copyWith(
                        color: g.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              trailing ??
                  Icon(Icons.north_east_rounded, size: 16, color: g.textMuted),
            ],
          ),
        ),
      ),
    );
  }

  Widget _highlightedName(BuildContext context) {
    final g = context.glass;
    final base = AppText.stationName.copyWith(color: g.textPrimary);
    if (query.isEmpty) {
      return Text(station.name,
          maxLines: 1, overflow: TextOverflow.ellipsis, style: base);
    }
    final lower = station.name.toLowerCase();
    final q = query.toLowerCase();
    final idx = lower.indexOf(q);
    if (idx < 0) {
      return Text(station.name,
          maxLines: 1, overflow: TextOverflow.ellipsis, style: base);
    }
    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: base,
        children: [
          TextSpan(text: station.name.substring(0, idx)),
          TextSpan(
            text: station.name.substring(idx, idx + q.length),
            style: base.copyWith(
              color: GlassTheme.accentViolet,
              fontWeight: FontWeight.w800,
            ),
          ),
          TextSpan(text: station.name.substring(idx + q.length)),
        ],
      ),
    );
  }
}
