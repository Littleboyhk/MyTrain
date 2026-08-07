import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'language_controller.dart' show sharedPreferencesProvider;
import 'sos_context.dart';

/// A local record of every SOS action the user has taken.
///
/// WHY THIS EXISTS: someone recounting an incident afterwards — to railway staff,
/// to police, to an insurer — needs to say *when* they raised the alarm and *what
/// the app told them at the time*. Memory under stress is unreliable and the
/// dialer's own call log does not carry the train, coach or position.
///
/// 100% LOCAL, like [EmergencyContactsController]: same [SharedPreferences]
/// instance, no Supabase table, no edge function, no sync, no auth. Capped at
/// [kMaxSosAuditEntries] newest-first so it can never grow without bound.
///
/// HONESTY IS THE WHOLE POINT of this file. A log that overstates what happened
/// is worse than no log, so [SosAuditOutcome] never claims a call connected or a
/// message was delivered — the app cannot know either. It records only what it
/// actually observed: that the user tapped, and whether the OS accepted the
/// handoff.
const int kMaxSosAuditEntries = 20;

/// Storage key. Versioned so a schema change can migrate rather than
/// misinterpret old rows.
const String kSosAuditLogKey = 'sos_audit_log_v1';

/// Which control the user tapped.
enum SosAuditAction {
  callRailwayHelpline,
  callEmergency,
  textContact;

  /// Short label for the log list.
  String get label => switch (this) {
        SosAuditAction.callRailwayHelpline => 'Called 139 · Railway Helpline',
        SosAuditAction.callEmergency => 'Called 112 · Police/Fire/Ambulance',
        SosAuditAction.textContact => 'Texted emergency contact',
      };

  static SosAuditAction? fromName(String? name) {
    for (final a in SosAuditAction.values) {
      if (a.name == name) return a;
    }
    return null;
  }
}

/// How far the action actually got.
///
/// Deliberately three states rather than a success boolean. "Tapped" and
/// "connected" are different facts and this log must not conflate them — see the
/// note on each value.
enum SosAuditOutcome {
  /// The OS accepted the `tel:`/`sms:` intent and the dialer or messaging app
  /// opened, pre-filled.
  ///
  /// THIS IS NOT "the call connected" or "the message was sent". Both still
  /// required the user to press the dialer's call button or the composer's Send,
  /// and the app has no way to observe either. The strongest true statement is
  /// "handed off to the phone".
  handedOff,

  /// Nothing on the device could handle the URI, or the launch threw. The tap
  /// happened and is worth recording; the handoff did not.
  launchFailed,

  /// No URI was attempted at all — the "no emergency contact configured" path,
  /// which routes to Settings instead of composing a message.
  notAttempted;

  String get label => switch (this) {
        SosAuditOutcome.handedOff => 'Opened on your phone',
        SosAuditOutcome.launchFailed => 'Could not open — tap recorded only',
        SosAuditOutcome.notAttempted => 'No contact was configured',
      };

  static SosAuditOutcome? fromName(String? name) {
    for (final o in SosAuditOutcome.values) {
      if (o.name == name) return o;
    }
    return null;
  }
}

/// One logged action, with the context snapshot as it stood at that moment.
///
/// The snapshot is stored flat rather than as a live reference: the point is what
/// the app believed *then*, not what it believes now.
@immutable
class SosAuditEntry {
  const SosAuditEntry({
    required this.at,
    required this.action,
    required this.outcome,
    this.noContactFallback = false,
    this.trainNumber,
    this.trainName,
    this.coach,
    this.pnr,
    this.locationLabel,
    this.latitude,
    this.longitude,
    this.contactLabel,
    this.contactMasked,
  });

  /// Local wall-clock time of the tap.
  final DateTime at;

  final SosAuditAction action;
  final SosAuditOutcome outcome;

  /// True when the text action was tapped with no contact saved, so it routed to
  /// Settings instead. Kept as its own field rather than inferred from
  /// [outcome]: they are different questions, and a future outcome value must not
  /// silently change the answer to this one.
  final bool noContactFallback;

  /// Snapshot fields. Each is null when it was genuinely unknown at the time —
  /// never a placeholder, so a blank field in the log means "the app did not have
  /// this", which is itself information.
  final String? trainNumber;
  final String? trainName;
  final String? coach;
  final String? pnr;

  /// The location line exactly as the sheet displayed it, e.g.
  /// `Near Kalyan Jn (KYN) · 2.1 km` or `Location unavailable`.
  final String? locationLabel;
  final double? latitude;
  final double? longitude;

  /// Which contact was texted. The number is stored MASKED only: the full number
  /// already lives in the contacts list, and a log is the last place to duplicate
  /// it in the clear.
  final String? contactLabel;
  final String? contactMasked;

  bool get hasCoordinates =>
      latitude != null &&
      longitude != null &&
      latitude!.isFinite &&
      longitude!.isFinite;

  /// `12951 Mumbai Rajdhani Express`, or null if no train was being tracked.
  String? get trainLine {
    final number = trainNumber?.trim();
    if (number == null || number.isEmpty) return null;
    final name = trainName?.trim();
    return (name == null || name.isEmpty) ? number : '$number $name';
  }

  String? get mapsUrl => hasCoordinates
      ? 'https://maps.google.com/?q='
          '${latitude!.toStringAsFixed(5)},${longitude!.toStringAsFixed(5)}'
      : null;

  Map<String, dynamic> toJson() => {
        'at': at.toIso8601String(),
        'action': action.name,
        'outcome': outcome.name,
        if (noContactFallback) 'noContactFallback': true,
        if (trainNumber != null) 'trainNumber': trainNumber,
        if (trainName != null) 'trainName': trainName,
        if (coach != null) 'coach': coach,
        if (pnr != null) 'pnr': pnr,
        if (locationLabel != null) 'locationLabel': locationLabel,
        if (latitude != null) 'lat': latitude,
        if (longitude != null) 'lng': longitude,
        if (contactLabel != null) 'contactLabel': contactLabel,
        if (contactMasked != null) 'contactMasked': contactMasked,
      };

  /// Null for a row that cannot be trusted — an entry with no timestamp or an
  /// unrecognised action says nothing useful and is dropped rather than guessed at.
  static SosAuditEntry? fromJson(Map<String, dynamic> map) {
    final at = DateTime.tryParse(map['at']?.toString() ?? '');
    final action = SosAuditAction.fromName(map['action']?.toString());
    if (at == null || action == null) return null;

    double? asDouble(Object? v) => v is num ? v.toDouble() : null;
    String? asText(Object? v) {
      final s = v?.toString().trim();
      return (s == null || s.isEmpty) ? null : s;
    }

    return SosAuditEntry(
      at: at,
      action: action,
      // An outcome written by a newer version falls back to the weakest claim
      // rather than to "it worked".
      outcome: SosAuditOutcome.fromName(map['outcome']?.toString()) ??
          SosAuditOutcome.launchFailed,
      noContactFallback: map['noContactFallback'] == true,
      trainNumber: asText(map['trainNumber']),
      trainName: asText(map['trainName']),
      coach: asText(map['coach']),
      pnr: asText(map['pnr']),
      locationLabel: asText(map['locationLabel']),
      latitude: asDouble(map['lat']),
      longitude: asDouble(map['lng']),
      contactLabel: asText(map['contactLabel']),
      contactMasked: asText(map['contactMasked']),
    );
  }
}

final sosAuditLogProvider =
    NotifierProvider<SosAuditLog, List<SosAuditEntry>>(SosAuditLog.new);

/// Newest first, capped, persisted.
class SosAuditLog extends Notifier<List<SosAuditEntry>> {
  SharedPreferences? get _prefs => ref.read(sharedPreferencesProvider);

  @override
  List<SosAuditEntry> build() {
    final raw = _prefs?.getStringList(kSosAuditLogKey);
    if (raw == null || raw.isEmpty) return const [];

    final out = <SosAuditEntry>[];
    for (final row in raw) {
      try {
        final decoded = jsonDecode(row);
        if (decoded is Map) {
          final parsed = SosAuditEntry.fromJson(decoded.cast<String, dynamic>());
          if (parsed != null) out.add(parsed);
        }
      } catch (e) {
        // One bad row must not erase the rest of someone's incident history.
        debugPrint('[SosAuditLog] skipping unreadable entry: $e');
      }
    }

    // Sort defensively: the stored order should already be newest-first, but a
    // log that reads out of order is misleading in exactly the situation it
    // exists for.
    out.sort((a, b) => b.at.compareTo(a.at));
    return List.unmodifiable(out.take(kMaxSosAuditEntries));
  }

  /// Records one action.
  ///
  /// Fire-and-forget from the caller's point of view: this must never be able to
  /// delay or block an emergency action, so it does no async work before updating
  /// state and never throws outward.
  void record({
    required SosAuditAction action,
    required SosAuditOutcome outcome,
    SosContext? context,
    bool noContactFallback = false,
    String? contactLabel,
    String? contactMasked,
    DateTime? at,
  }) {
    try {
      final location = context?.location;
      final coach = context?.coach?.trim();
      final pnr = context?.pnr?.trim();

      final entry = SosAuditEntry(
        at: at ?? DateTime.now(),
        action: action,
        outcome: outcome,
        noContactFallback: noContactFallback,
        trainNumber: context?.trainNumber,
        trainName: context?.trainName,
        coach: (coach == null || coach.isEmpty) ? null : coach,
        pnr: (pnr == null || pnr.isEmpty) ? null : pnr,
        // A location still resolving had nothing to show, so nothing is recorded
        // — as opposed to "Location unavailable", which is a real answer.
        locationLabel: location is SosLocationResolving ? null : location?.label,
        latitude: location?.latitude,
        longitude: location?.longitude,
        contactLabel: contactLabel,
        contactMasked: contactMasked,
      );

      _commit([entry, ...state]);
    } catch (e) {
      debugPrint('[SosAuditLog] failed to record $action: $e');
    }
  }

  void clear() => _commit(const []);

  void _commit(List<SosAuditEntry> next) {
    // Newest first, so the cap drops the OLDEST entries.
    final capped = next.take(kMaxSosAuditEntries).toList(growable: false);
    state = List.unmodifiable(capped);
    _prefs?.setStringList(
      kSosAuditLogKey,
      capped.map((e) => jsonEncode(e.toJson())).toList(),
    );
  }
}
