import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../utils/formatters.dart';
import 'nearest_station_service.dart';

/// Everything the SOS flow knows about the passenger, and how it turns that into
/// a dialer URI or a pre-filled SMS.
///
/// This file is deliberately pure logic plus two tiny session providers. Nothing
/// here touches the network, and nothing here can place a call or send a message
/// on its own — see `lib/widgets/emergency_sheet.dart`, which is the only thing
/// that launches a URI, and only from a tap.
///
/// SOURCING RULE: every field is READ from state something else already owns.
/// The SOS flow never asks the user to re-enter what the app already knows, and
/// never prompts for anything it is missing — a missing field is simply left out.

// ---------------------------------------------------------------------------
// Session state the SOS sheet reads
// ---------------------------------------------------------------------------

/// The coach the user last picked on the Coach / Berth screen, this app run.
///
/// SESSION-SCOPED ON PURPOSE, and not persisted: a coach is true for one journey
/// and wrong for the next, so remembering "B3" across restarts would put a stale
/// coach into an emergency message weeks later. That is a worse failure than an
/// empty field the user can fill in themselves.
///
/// Written by `CoachPositionScreen` on selection; read by the Emergency sheet as
/// the pre-fill for its editable coach field.
class SessionCoach extends Notifier<String?> {
  @override
  String? build() => null;

  /// [code] null clears it (the Coach screen allows deselecting).
  void set(String? code) {
    final trimmed = code?.trim();
    state = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }
}

final sessionCoachProvider =
    NotifierProvider<SessionCoach, String?>(SessionCoach.new);

/// The PNR the user last looked up successfully, this app run.
///
/// Session-scoped for the same reason as [SessionCoach], plus one specific to
/// PNRs: `SavedPnrStore` seeds a demo ticket on first read, so the saved-tickets
/// list can NOT be used as "the last PNR looked up" without risking a fabricated
/// number in a real emergency message. Only a real successful lookup writes here.
class SessionPnr extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? pnr) {
    final trimmed = pnr?.trim();
    state = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }
}

final sessionPnrProvider =
    NotifierProvider<SessionPnr, String?>(SessionPnr.new);

// ---------------------------------------------------------------------------
// Location
// ---------------------------------------------------------------------------

/// Where the passenger is, as far as the app can tell.
///
/// Four states, in descending order of usefulness, because an emergency message
/// with a rough answer beats one with no answer:
/// map-matched name → raw coordinates → still resolving → nothing.
@immutable
sealed class SosLocation {
  const SosLocation();

  /// What the sheet shows on its location line.
  String get label;

  double? get latitude => null;
  double? get longitude => null;

  /// Finite coordinates on both axes. The NaN guard is not paranoia: a named
  /// location can exist without a readable fix behind it.
  bool get hasCoordinates {
    final lat = latitude;
    final lng = longitude;
    return lat != null && lng != null && lat.isFinite && lng.isFinite;
  }

  /// The link that goes in the SMS body. Null when there are no coordinates —
  /// a maps URL with nothing in it is worse than no URL.
  String? get mapsUrl => hasCoordinates
      ? 'https://maps.google.com/?q=${_trim(latitude!)},${_trim(longitude!)}'
      : null;

  /// 5 decimal places ≈ 1 m, which is finer than any consumer GPS fix. More
  /// digits only makes the SMS longer.
  static String _trim(double v) => v.toStringAsFixed(5);
}

/// The lookup is still running. The sheet opens in this state and never waits
/// for it.
class SosLocationResolving extends SosLocation {
  const SosLocationResolving();

  @override
  String get label => 'Finding your location…';
}

/// Map-matched against the local station coordinate asset.
class SosLocationNamed extends SosLocation {
  const SosLocationNamed({
    required this.stationName,
    required this.stationCode,
    required this.distanceKm,
    this.latitude,
    this.longitude,
  });

  final String stationName;
  final String stationCode;
  final double distanceKm;

  /// Null when the ranking succeeded but the fix behind it could no longer be
  /// read. The station name is still true; only the maps link is lost.
  @override
  final double? latitude;

  @override
  final double? longitude;

  /// `Near Kalyan Jn (KYN) · 2.1 km` — the station is the part a control room can
  /// act on, the distance is the honesty about how near "near" is.
  @override
  String get label => 'Near $stationName ($stationCode) · $distanceLabel';

  String get distanceLabel => distanceKm < 1
      ? '${(distanceKm * 1000).round()} m'
      : '${distanceKm.toStringAsFixed(distanceKm < 10 ? 1 : 0)} km';
}

/// A fix, but no station to hang it on (outside the dataset, or the asset failed
/// to load).
class SosLocationCoordinates extends SosLocation {
  const SosLocationCoordinates({
    required this.latitude,
    required this.longitude,
  });

  @override
  final double latitude;

  @override
  final double longitude;

  @override
  String get label =>
      '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}';
}

/// No location at all. Calls and the SMS still go out without it.
class SosLocationUnavailable extends SosLocation {
  const SosLocationUnavailable({this.needsPermission = false});

  /// True when the only thing in the way is an ungranted location permission, so
  /// the sheet can offer an explicit "Enable location" tap. The SOS flow never
  /// raises that prompt by itself.
  final bool needsPermission;

  @override
  String get label => 'Location unavailable';
}

/// How long the sheet will wait for a location before settling for
/// [SosLocationUnavailable]. The lookup keeps running past this: it populates
/// [NearestStationService]'s 60-second fix cache, so a retry is usually instant.
const Duration kSosLocationTimeout = Duration(seconds: 3);

/// One location read for the SOS sheet.
///
/// Reuses [NearestStationService] wholesale rather than talking to Geolocator:
/// that service already caches a fix for 60 seconds, already requests exactly one
/// one-shot fix when the cache is cold, and already does the local map-matching.
/// Duplicating any of that would mean a second permission path and a second set
/// of distances that could disagree with the ones on the home screen.
///
/// [requestPermission] defaults to false — see the note on
/// [NearestStationService.find].
Future<SosLocation> resolveSosLocation(
  NearestStationService service, {
  bool requestPermission = false,
  Duration timeout = kSosLocationTimeout,
}) async {
  try {
    final result = await service
        .find(requestPermission: requestPermission)
        // The inner future is not cancelled, so a fix that lands late still warms
        // the cache for the next attempt.
        .timeout(timeout);

    switch (result) {
      case NearestStationFound(:final nearby):
        final fix = service.lastFix;
        final best = nearby.first;
        return SosLocationNamed(
          stationName: best.station.name,
          stationCode: best.station.code,
          distanceKm: best.distanceKm,
          // Null when the fix behind the ranking is no longer readable: the
          // station name still stands, only the maps link is lost.
          latitude: fix?.lat,
          longitude: fix?.lng,
        );

      case NearestStationFailure(:final error):
        // A fix that no station could be matched to is still a location.
        final fix = service.lastFix;
        if (fix != null &&
            error != NearestStationError.permissionDenied &&
            error != NearestStationError.locationServiceOff) {
          return SosLocationCoordinates(latitude: fix.lat, longitude: fix.lng);
        }
        return SosLocationUnavailable(
          needsPermission: error == NearestStationError.permissionDenied,
        );
    }
  } on TimeoutException {
    // Out of time, but an earlier fix may still be sitting in the cache.
    final fix = service.lastFix;
    if (fix != null) {
      return SosLocationCoordinates(latitude: fix.lat, longitude: fix.lng);
    }
    return const SosLocationUnavailable();
  } catch (e) {
    debugPrint('[SOS] location lookup failed: $e');
    return const SosLocationUnavailable();
  }
}

// ---------------------------------------------------------------------------
// The context, and the message built from it
// ---------------------------------------------------------------------------

/// A snapshot of what the SOS message will say.
@immutable
class SosContext {
  const SosContext({
    this.trainNumber,
    this.trainName,
    this.coach,
    this.pnr,
    this.location = const SosLocationResolving(),
  });

  /// Null when no train is being tracked. SOS works standalone; the train and
  /// coach lines are omitted rather than shown blank.
  final String? trainNumber;
  final String? trainName;

  /// User-editable, pre-filled from [sessionCoachProvider].
  final String? coach;

  /// From [sessionPnrProvider]. Included in the SMS when present, omitted
  /// entirely when not — the SOS flow never asks for it.
  final String? pnr;

  final SosLocation location;

  bool get hasTrain => (trainNumber?.trim().isNotEmpty ?? false);

  SosContext copyWith({
    String? trainNumber,
    String? trainName,
    String? coach,
    String? pnr,
    SosLocation? location,
  }) {
    return SosContext(
      trainNumber: trainNumber ?? this.trainNumber,
      trainName: trainName ?? this.trainName,
      coach: coach ?? this.coach,
      pnr: pnr ?? this.pnr,
      location: location ?? this.location,
    );
  }

  /// `12951 Mumbai Rajdhani Express`, or null with no train.
  String? get trainLine {
    if (!hasTrain) return null;
    final number = trainNumber!.trim();
    final name = trainName?.trim();
    return (name == null || name.isEmpty) ? number : '$number $name';
  }
}

/// Railway helplines offered by the sheet.
///
/// Two, both nationally valid, both explained in plain words. 182 is
/// deliberately absent: it was merged into 139 by the Railway Board, and a button
/// that may reach nobody is worse than no button in an emergency.
class SosHelpline {
  const SosHelpline({
    required this.number,
    required this.title,
    required this.subtitle,
  });

  final String number;
  final String title;
  final String subtitle;

  static const SosHelpline railway = SosHelpline(
    number: '139',
    title: 'Call 139 – Railway Helpline',
    subtitle: 'Security · Medical · On-board complaints',
  );

  static const SosHelpline emergency = SosHelpline(
    number: '112',
    title: 'Call 112 – Emergency',
    subtitle: 'Police · Fire · Ambulance',
  );
}

/// Builds the SMS body from [context].
///
/// Field rules, all of them "omit rather than pad":
/// * no train tracked → no train and no coach clause
/// * no coach entered → no coach clause, even with a train
/// * no PNR looked up this session → no PNR clause
/// * no location → no "near ..." clause and no maps link
///
/// [at] is injectable so the output is testable; it is the send time otherwise.
/// The clock format follows the user's 12/24-hour preference via [Fmt.hhmm].
String composeSosMessage(SosContext context, {DateTime? at}) {
  final now = at ?? DateTime.now();
  final parts = <String>[];

  final train = context.trainLine;
  if (train != null) parts.add('Train $train');

  final coach = context.coach?.trim();
  if (train != null && coach != null && coach.isNotEmpty) {
    parts.add('Coach $coach');
  }

  final pnr = context.pnr?.trim();
  if (pnr != null && pnr.isNotEmpty) parts.add('PNR $pnr');

  final location = context.location;
  if (location is SosLocationNamed) {
    parts.add('near ${location.stationName} (${location.stationCode})');
  } else if (location is SosLocationCoordinates) {
    parts.add('near ${location.label}');
  }

  final buffer = StringBuffer('SOS - need help.');
  if (parts.isNotEmpty) buffer.write(' ${parts.join(', ')}.');

  final maps = location.mapsUrl;
  if (maps != null) buffer.write(' $maps');

  buffer.write(' Sent via My Train app, ${_timestamp(now)}.');
  return buffer.toString();
}

/// `7 Aug, 3:52 AM` — short, unambiguous, and in the format the user already
/// reads times in everywhere else in the app.
String _timestamp(DateTime t) =>
    '${t.day} ${Fmt.monthShort(t)}, ${Fmt.hhmm(t)}';

/// `tel:` URI for [number]. Opens the dialer PRE-FILLED — the user still taps
/// the dialer's own call button, which is why no `CALL_PHONE` permission is
/// needed and why nothing here can dial by itself.
Uri sosTelUri(String number) => Uri(scheme: 'tel', path: _digits(number));

/// `sms:` URI for [number] with [body] pre-filled.
///
/// Built by hand rather than with `Uri(queryParameters:)`, which form-encodes and
/// would turn every space in the body into a literal `+` in the SMS composer.
///
/// Opens the composer only. No `SEND_SMS`, no background send: Play Store treats
/// SMS as a restricted permission needing a declaration exception, and one tap on
/// Send is the accepted tradeoff.
Uri sosSmsUri(String number, String body) =>
    Uri.parse('sms:${_digits(number)}?body=${Uri.encodeComponent(body)}');

/// Digits plus an optional single leading `+`, so a number typed with spaces or
/// dashes can never break URI parsing.
String _digits(String raw) {
  final trimmed = raw.trim();
  final digits = trimmed.replaceAll(RegExp(r'\D'), '');
  return trimmed.startsWith('+') ? '+$digits' : digits;
}
