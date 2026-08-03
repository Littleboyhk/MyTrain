import 'dart:math' as math;

/// A WGS84 latitude/longitude pair.
///
/// Deliberately a plain value type with no Flutter or plugin dependency: it is
/// consumed by the offline map-matching code, which is pure Dart precisely so it
/// can be unit tested without a device, a GPS fix, or a widget tree.
class GeoPoint {
  const GeoPoint(this.latitude, this.longitude);

  final double latitude;
  final double longitude;

  /// Mean earth radius, matching the value already used by
  /// `NearestStationService._haversineKm` so distances agree across the app.
  static const double earthRadiusKm = 6371.0088;

  static const double _deg = math.pi / 180;

  /// True when both components are finite and inside the valid coordinate
  /// range. `(0, 0)` is treated as valid here — it is a real point in the Gulf
  /// of Guinea — but callers building a route reject it separately, because in
  /// railway payloads it means "field present, value missing".
  bool get isValid =>
      latitude.isFinite &&
      longitude.isFinite &&
      latitude.abs() <= 90 &&
      longitude.abs() <= 180;

  /// The null-island sentinel that upstream payloads use for "no coordinate".
  ///
  /// No Indian railway station sits within ~1000 km of (0, 0), so rejecting it
  /// cannot discard a real station.
  bool get isNullIsland => latitude.abs() < 0.01 && longitude.abs() < 0.01;

  bool get isUsable => isValid && !isNullIsland;

  /// Great-circle distance in kilometres.
  double distanceKmTo(GeoPoint other) {
    final dLat = (other.latitude - latitude) * _deg;
    final dLng = (other.longitude - longitude) * _deg;
    final s1 = math.sin(dLat / 2);
    final s2 = math.sin(dLng / 2);
    final h = s1 * s1 +
        math.cos(latitude * _deg) * math.cos(other.latitude * _deg) * s2 * s2;
    return 2 * earthRadiusKm * math.asin(math.min(1, math.sqrt(h)));
  }

  /// Parses a coordinate pair that may be missing, malformed, or a sentinel.
  ///
  /// Returns null rather than a guess: an invented coordinate would silently
  /// corrupt map-matching, which is worse than having no geometry for a station
  /// (the matcher simply skips those).
  static GeoPoint? tryParse(dynamic lat, dynamic lng) {
    final la = _asDouble(lat);
    final ln = _asDouble(lng);
    if (la == null || ln == null) return null;
    final p = GeoPoint(la, ln);
    return p.isUsable ? p : null;
  }

  static double? _asDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.isFinite ? v.toDouble() : null;
    final parsed = double.tryParse(v.toString().trim());
    return (parsed != null && parsed.isFinite) ? parsed : null;
  }

  @override
  bool operator ==(Object other) =>
      other is GeoPoint &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);

  @override
  String toString() =>
      'GeoPoint(${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)})';
}
