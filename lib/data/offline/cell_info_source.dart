import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Identity of the cell the handset is currently registered to.
///
/// Field names follow GSM/LTE conventions because that is what the dataset needs
/// to be joinable later: [mcc]+[mnc] identify the operator, [lac] (or TAC on LTE)
/// the tracking area, and [cellId] the cell itself.
@immutable
class CellIdentity {
  const CellIdentity({
    this.cellId,
    this.lac,
    this.mcc,
    this.mnc,
    this.radioType,
    this.signalDbm,
  });

  /// CID on GSM/WCDMA, CI on LTE, NCI on NR.
  final int? cellId;

  /// Location Area Code on GSM/WCDMA, Tracking Area Code on LTE/NR.
  final int? lac;

  final int? mcc;
  final int? mnc;

  /// 'gsm' | 'wcdma' | 'lte' | 'nr' | 'cdma'.
  final String? radioType;

  /// Received signal strength in dBm, when the platform reports it.
  final int? signalDbm;

  /// A record with no cell identity is worthless for building a lookup table.
  bool get isUsable => cellId != null && mcc != null && mnc != null;

  Map<String, dynamic> toJson() => {
        if (cellId != null) 'cell_id': cellId,
        if (lac != null) 'lac': lac,
        if (mcc != null) 'mcc': mcc,
        if (mnc != null) 'mnc': mnc,
        if (radioType != null) 'radio_type': radioType,
        if (signalDbm != null) 'signal_dbm': signalDbm,
      };

  static CellIdentity? fromMap(dynamic raw) {
    if (raw is! Map) return null;
    int? i(String key) {
      final v = raw[key];
      if (v is int) return v;
      if (v is num && v.isFinite) return v.toInt();
      return int.tryParse(v?.toString() ?? '');
    }

    // Android reports Integer.MAX_VALUE for "unavailable" on several fields.
    int? sane(int? v) =>
        (v == null || v == 2147483647 || v == -1) ? null : v;

    final identity = CellIdentity(
      cellId: sane(i('cellId')),
      lac: sane(i('lac')),
      mcc: sane(i('mcc')),
      mnc: sane(i('mnc')),
      radioType: raw['radioType']?.toString(),
      signalDbm: sane(i('signalDbm')),
    );
    return identity.isUsable ? identity : null;
  }

  @override
  String toString() => 'CellIdentity($radioType $mcc-$mnc lac=$lac cid=$cellId)';
}

/// Reads the serving cell's identity.
abstract interface class CellInfoSource {
  /// False on every platform that cannot answer, so callers can skip the work
  /// entirely rather than discovering it per call.
  bool get isSupported;

  /// The serving cell, or null when unavailable for any reason. Never throws.
  Future<CellIdentity?> read();
}

/// Android implementation, over a platform channel to `TelephonyManager`.
///
/// WHY A PLATFORM CHANNEL AND NOT A PLUGIN. The brief asked for a maintained
/// plugin to be preferred, and this niche did not offer one: `telephony` states
/// in its own README that it is no longer actively maintained, `flutter_cell_info`
/// has had no recent activity, and `carrier_info` exposes operator identity
/// rather than serving-cell identity. Rather than take a dependency that would
/// rot, the fallback the brief named is used directly — the surface needed here is
/// one method returning a flat map.
///
/// ANDROID ONLY BY DESIGN. iOS has not exposed serving or neighbour cell
/// information to third-party apps since iOS 13, so there is nothing to read; the
/// factory below returns [UnsupportedCellInfoSource] everywhere except Android.
class MethodChannelCellInfoSource implements CellInfoSource {
  const MethodChannelCellInfoSource();

  static const MethodChannel _channel =
      MethodChannel('com.mytrain.my_train/cell_info');

  /// Bounded: this runs inside a best-effort background record, and a platform
  /// call that never returns must not leave a pending future behind.
  static const Duration _timeout = Duration(seconds: 4);

  @override
  bool get isSupported => defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<CellIdentity?> read() async {
    if (!isSupported) return null;
    try {
      final result =
          await _channel.invokeMethod<dynamic>('getServingCell').timeout(
                _timeout,
              );
      return CellIdentity.fromMap(result);
    } on MissingPluginException {
      // The native handler isn't present in this build. Expected and harmless:
      // Phase 2 simply records nothing, and Phase 1 is unaffected.
      debugPrint('[CellInfo] native handler not registered — skipping');
      return null;
    } on PlatformException catch (e) {
      debugPrint('[CellInfo] platform error: ${e.code} ${e.message}');
      return null;
    } on TimeoutException {
      debugPrint('[CellInfo] read timed out');
      return null;
    } catch (e) {
      debugPrint('[CellInfo] read failed: $e');
      return null;
    }
  }
}

/// Every non-Android platform.
class UnsupportedCellInfoSource implements CellInfoSource {
  const UnsupportedCellInfoSource();

  @override
  bool get isSupported => false;

  @override
  Future<CellIdentity?> read() async => null;
}

CellInfoSource createCellInfoSource() =>
    defaultTargetPlatform == TargetPlatform.android
        ? const MethodChannelCellInfoSource()
        : const UnsupportedCellInfoSource();
