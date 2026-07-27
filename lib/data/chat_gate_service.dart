import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

/// Transport for the co-passenger chat ACCESS GATE.
///
/// This talks to `chat-join` and `chat-verify` only. It cannot read or post
/// messages — that is deliberately a later phase, gated behind this one.
///
/// Two properties worth preserving if you edit this file:
///   * The client never decides whether verification passed. It uploads raw
///     GPS samples and reads back a server verdict.
///   * Every call requires a signed-in user. There is no anonymous fallback,
///     because a granted seat in a private room has to be attributable to an
///     account that a mute can be applied to.
enum ChatGateErrorCode {
  /// Supabase isn't configured in this build.
  notConfigured,

  /// Nobody is signed in. Today this is the normal case: the app has no
  /// sign-in yet, so chat is simply unavailable.
  authRequired,

  /// chat-verify called before chat-join.
  notJoined,

  /// The room's retention window has passed. Everything in it is gone.
  expired,

  /// Operator closed this room.
  locked,

  /// Route geometry unavailable, so no verification is possible.
  routeUnavailable,

  functionNotDeployed,
  validation,
  unknown,
}

class ChatGateException implements Exception {
  final ChatGateErrorCode code;
  final String message;
  const ChatGateException(this.code, this.message);

  @override
  String toString() => 'ChatGateException(${code.name}): $message';
}

/// A single GPS reading on its way to the gate.
class ChatGateSample {
  final double lat;
  final double lng;
  final double? accuracyM;
  final double? speedKmh;
  final DateTime takenAt;

  const ChatGateSample({
    required this.lat,
    required this.lng,
    required this.takenAt,
    this.accuracyM,
    this.speedKmh,
  });

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lng': lng,
        'accuracy': accuracyM,
        'speed_kmh': speedKmh,
        'ts': takenAt.millisecondsSinceEpoch,
      };
}

/// Server-side verification progress. Note what is absent: no chainage, no
/// corridor offset, no implied delay. Handing those back would let someone tune
/// a fake track against our own scoring.
class ChatVerification {
  final String status; // pending | verified | rejected
  final int sustainedSeconds;
  final int requiredSeconds;
  final double progressKm;
  final int acceptedSamples;
  final String reason;

  const ChatVerification({
    required this.status,
    required this.sustainedSeconds,
    required this.requiredSeconds,
    required this.progressKm,
    required this.acceptedSamples,
    required this.reason,
  });

  factory ChatVerification.fromMap(Map<String, dynamic>? m) => ChatVerification(
        status: m?['status']?.toString() ?? 'pending',
        sustainedSeconds: (m?['sustained_seconds'] as num?)?.toInt() ?? 0,
        requiredSeconds: (m?['required_seconds'] as num?)?.toInt() ?? 300,
        progressKm: (m?['progress_km'] as num?)?.toDouble() ?? 0,
        acceptedSamples: (m?['accepted_samples'] as num?)?.toInt() ?? 0,
        reason: m?['reason']?.toString() ?? 'collecting_samples',
      );

  bool get isVerified => status == 'verified';
  bool get isRejected => status == 'rejected';

  /// 0..1 for a progress indicator.
  double get fraction => requiredSeconds <= 0
      ? 0
      : (sustainedSeconds / requiredSeconds).clamp(0.0, 1.0);
}

/// The caller's own membership. Contains a pseudonym and nothing else — the
/// server never returns a user id, not even the caller's own.
class ChatMembership {
  final String displayId;
  final String? nickname;
  final String verificationStatus;
  final bool canRead;
  final bool canPost;
  final DateTime? mutedUntil;

  const ChatMembership({
    required this.displayId,
    required this.nickname,
    required this.verificationStatus,
    required this.canRead,
    required this.canPost,
    required this.mutedUntil,
  });

  factory ChatMembership.fromMap(Map<String, dynamic> m) => ChatMembership(
        displayId: m['display_id']?.toString() ?? '',
        nickname: m['nickname']?.toString(),
        verificationStatus: m['verification_status']?.toString() ?? 'pending',
        canRead: m['can_read'] == true,
        canPost: m['can_post'] == true,
        mutedUntil: m['muted_until'] == null
            ? null
            : DateTime.tryParse(m['muted_until'].toString()),
      );
}

class ChatRoomInfo {
  final String id;
  final String trainNumber;
  final String journeyDate;
  final String? trainName;
  final DateTime? expiresAt;

  const ChatRoomInfo({
    required this.id,
    required this.trainNumber,
    required this.journeyDate,
    required this.trainName,
    required this.expiresAt,
  });

  factory ChatRoomInfo.fromMap(Map<String, dynamic> m) => ChatRoomInfo(
        id: m['id']?.toString() ?? '',
        trainNumber: m['train_number']?.toString() ?? '',
        journeyDate: m['journey_date']?.toString() ?? '',
        trainName: m['train_name']?.toString(),
        expiresAt: m['expires_at'] == null
            ? null
            : DateTime.tryParse(m['expires_at'].toString()),
      );
}

class ChatJoinResult {
  final ChatRoomInfo room;
  final ChatMembership me;
  final ChatVerification verification;

  const ChatJoinResult({
    required this.room,
    required this.me,
    required this.verification,
  });
}

class ChatGateService {
  const ChatGateService();

  bool get isConfigured => SupabaseConfig.isConfigured;

  /// True only when a real user session exists. The app currently has no
  /// sign-in at all, so this is false everywhere — which is why chat reports
  /// itself as unavailable rather than falling back to an anonymous identity.
  bool get hasSession =>
      isConfigured && Supabase.instance.client.auth.currentSession != null;

  Future<ChatJoinResult> join({
    required String trainNumber,
    required String journeyDate,
  }) async {
    _requireSession();
    final payload = await _invoke('chat-join', {
      'train_number': trainNumber,
      'journey_date': journeyDate,
    });
    final chat = (payload['chat'] as Map?)?.cast<String, dynamic>();
    final me = (payload['me'] as Map?)?.cast<String, dynamic>();
    if (chat == null || me == null) {
      throw const ChatGateException(
        ChatGateErrorCode.unknown,
        'Unexpected chat-join response shape',
      );
    }
    return ChatJoinResult(
      room: ChatRoomInfo.fromMap(chat),
      me: ChatMembership.fromMap(me),
      verification: ChatVerification.fromMap(
        (payload['verification'] as Map?)?.cast<String, dynamic>(),
      ),
    );
  }

  /// Upload a batch of fresh samples and read back the server's verdict.
  ///
  /// Batches must be SMALL and CURRENT: the server rejects samples whose
  /// timestamps are more than ~2 minutes from its own clock, so buffering to
  /// save requests would get the batch discarded as a replay.
  Future<ChatVerification> submitSamples({
    required String trainNumber,
    required String journeyDate,
    required List<ChatGateSample> samples,
  }) async {
    _requireSession();
    if (samples.isEmpty) {
      throw const ChatGateException(
        ChatGateErrorCode.validation,
        'no samples to submit',
      );
    }
    final payload = await _invoke('chat-verify', {
      'train_number': trainNumber,
      'journey_date': journeyDate,
      'samples': samples.map((s) => s.toJson()).toList(),
    });
    return ChatVerification.fromMap(
      (payload['verification'] as Map?)?.cast<String, dynamic>(),
    );
  }

  void _requireSession() {
    if (!isConfigured) {
      throw const ChatGateException(
        ChatGateErrorCode.notConfigured,
        'Supabase is not configured in this build',
      );
    }
    if (!hasSession) {
      throw const ChatGateException(
        ChatGateErrorCode.authRequired,
        'Journey chat needs a signed-in account.',
      );
    }
  }

  Future<Map<String, dynamic>> _invoke(
    String fn,
    Map<String, dynamic> body,
  ) async {
    try {
      final res = await Supabase.instance.client.functions
          .invoke(fn, body: body)
          .timeout(const Duration(seconds: 15));
      final data = res.data;
      if (data is Map) return data.cast<String, dynamic>();
      throw ChatGateException(
        ChatGateErrorCode.unknown,
        'Unexpected $fn response',
      );
    } on TimeoutException {
      throw ChatGateException(
        ChatGateErrorCode.unknown,
        '$fn timed out',
      );
    } on FunctionException catch (e) {
      throw _mapFunctionException(fn, e);
    }
  }

  ChatGateException _mapFunctionException(String fn, FunctionException e) {
    final details = e.details;
    String? code;
    String? message;
    if (details is Map) {
      code = details['code']?.toString();
      message = (details['error'] ?? details['message'])?.toString();
    } else if (details != null) {
      message = details.toString();
    }

    final mapped = switch (code) {
      'auth_required' || 'UNAUTHORIZED_INVALID_JWT_FORMAT' =>
        ChatGateErrorCode.authRequired,
      'not_joined' => ChatGateErrorCode.notJoined,
      'expired' => ChatGateErrorCode.expired,
      'locked' => ChatGateErrorCode.locked,
      'route_unavailable' => ChatGateErrorCode.routeUnavailable,
      'validation' => ChatGateErrorCode.validation,
      'NOT_FOUND' => ChatGateErrorCode.functionNotDeployed,
      _ => switch (e.status) {
          401 => ChatGateErrorCode.authRequired,
          404 => ChatGateErrorCode.functionNotDeployed,
          410 => ChatGateErrorCode.expired,
          _ => ChatGateErrorCode.unknown,
        },
    };

    debugPrint('[ChatGate] $fn HTTP ${e.status} ${code ?? ''} ${message ?? ''}');
    return ChatGateException(
      mapped,
      message ?? 'Chat is unavailable right now.',
    );
  }
}

final chatGateServiceProvider =
    Provider<ChatGateService>((ref) => const ChatGateService());
