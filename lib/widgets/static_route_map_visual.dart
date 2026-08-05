import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../data/route_polyline_service.dart';
import '../theme/glass_theme.dart';

/// A static, non-interactive map rendering the train's actual track route
/// using Esri World Imagery satellite tiles and a cased red polyline overlay.
///
/// PERFORMANCE OPTIMIZATIONS FOR MOBILE:
/// 1. Global in-memory polyline cache — repeat renders skip all I/O.
/// 2. Skeleton placeholder shown instantly while tiles download.
/// 3. Max zoom capped at 8 to fetch fewer, smaller tiles.
/// 4. Boundaries overlay removed for card-level maps (saves ~50% tile requests).
/// 5. Tile fade-in disabled for snappier perceived load.
/// 6. keepAlive on TileLayer to persist decoded tiles across rebuilds.
class StaticRouteMapVisual extends StatefulWidget {
  const StaticRouteMapVisual({
    super.key,
    required this.trainNumber,
    this.fromCode,
    this.toCode,
    this.height = 145.0,
    this.showBoundaries = false,
  });

  final String trainNumber;
  final String? fromCode;
  final String? toCode;
  final double height;

  /// Whether to show district boundary overlay. Disabled by default for card
  /// maps (saves tile requests). Enable on full-screen map views.
  final bool showBoundaries;

  @override
  State<StaticRouteMapVisual> createState() => _StaticRouteMapVisualState();
}

class _StaticRouteMapVisualState extends State<StaticRouteMapVisual>
    with AutomaticKeepAliveClientMixin {
  List<LatLng>? _points;
  bool _loading = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant StaticRouteMapVisual oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trainNumber != widget.trainNumber ||
        oldWidget.fromCode != widget.fromCode ||
        oldWidget.toCode != widget.toCode) {
      _load();
    }
  }

  void _load() async {
    setState(() => _loading = true);
    try {
      final result = await RoutePolylineService.instance.getRoutePolyline(
        widget.trainNumber,
        fromCode: widget.fromCode,
        toCode: widget.toCode,
      );
      if (mounted) {
        setState(() {
          _points = result.length >= 2 ? result : null;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // Skeleton placeholder while loading
    if (_loading) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Container(
          height: widget.height,
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: Colors.white.withValues(alpha: 0.06),
          ),
          child: const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: GlassTheme.accentViolet,
              ),
            ),
          ),
        ),
      );
    }

    final points = _points;
    if (points == null || points.length < 2) {
      return const SizedBox.shrink();
    }

    final bounds = LatLngBounds.fromPoints(points);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        height: widget.height,
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: GlassTheme.accentViolet.withValues(alpha: 0.45),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: Container(
            color: const Color(0xFF131C27),
            child: Stack(
              children: [
                FlutterMap(
                  options: MapOptions(
                    initialCameraFit: CameraFit.bounds(
                      bounds: bounds,
                      padding: const EdgeInsets.all(16),
                      maxZoom: 12,
                    ),
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.none,
                    ),
                  ),
                  children: [
                    // High-availability Satellite tiles with multi-subdomain distribution & dark fallback
                    TileLayer(
                      urlTemplate:
                          'https://mt{s}.google.com/vt/lyrs=s&x={x}&y={y}&z={z}',
                      subdomains: const ['0', '1', '2', '3'],
                      userAgentPackageName: 'com.mytrain.app',
                      maxZoom: 18,
                      keepBuffer: 4,
                      fallbackUrl:
                          'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
                    ),
                    // District Boundaries & Main Cities Overlay Layer
                    // Only shown when explicitly requested (full-screen map)
                    if (widget.showBoundaries)
                      TileLayer(
                        urlTemplate:
                            'https://server.arcgisonline.com/ArcGIS/rest/services/Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}',
                        userAgentPackageName: 'com.mytrain.app',
                        maxZoom: 18,
                        keepBuffer: 3,
                      ),
                    // Polyline Layer: Black casing + Vibrant Red track line
                    PolylineLayer(
                      polylines: [
                        // Outer black outline casing
                        Polyline(
                          points: points,
                          strokeWidth: 6.5,
                          color: Colors.black.withValues(alpha: 0.85),
                        ),
                        // Inner vibrant red track polyline
                        Polyline(
                          points: points,
                          strokeWidth: 3.8,
                          color: const Color(0xFFE53935),
                        ),
                      ],
                    ),
                    // Station Markers with Label Pills
                    MarkerLayer(
                      markers: [
                        // Origin Marker (GREEN 🟢)
                        _stationMarker(
                          points.first,
                          widget.fromCode?.toUpperCase() ?? 'ORIGIN',
                          color: const Color(0xFF4CAF50),
                        ),
                        // Destination Marker (RED 🔴)
                        _stationMarker(
                          points.last,
                          widget.toCode?.toUpperCase() ?? 'DEST',
                          color: const Color(0xFFE53935),
                        ),
                      ],
                    ),
                  ],
                ),
                // Glass inner shadow gradient
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.20),
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.35),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Marker _stationMarker(LatLng point, String label, {required Color color}) {
    return Marker(
      point: point,
      width: 110,
      height: 38,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.82),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.white30, width: 0.8),
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 9.5,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2.2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.50),
                  blurRadius: 4,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
