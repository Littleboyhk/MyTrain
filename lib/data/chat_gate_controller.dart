import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import 'chat_gate_service.dart';

/// What the UI is allowed to show. There is no state in which an unverified
/// user can read or post — "verifying" is the only pre-access state.
enum ChatGateStatus {
  /// Not started.
  idle,

  /// Backend not configured in this build.
  unavailable,

  /// No signed-in account. This is the CURRENT state of the app for everyone:
  /// there is no sign-in yet, so chat is off.
  needsAccount,

  /// Location services off, or permission denied. Per spec there is no
  /// fallback — denial means chat access simply does not happen.
  needsLocation,

  /// "Verifying your journey…" — sampling, no read, no post.
  verifying,

  verified,

  /// The trace contradicted the train's route. Terminal for this journey.
  rejected,

  /// Room's retention window has passed.
  expired,

  error,
}

class ChatGateState {
  final ChatGateStatus status;
  final String? trainNumber;
  final String? journeyDate;

  /// The caller's per-journey pseudonym, once joined.
  final String? displayId;
  final String? nickname;

  final int sustainedSeconds;
  final int requiredSeconds;
  final double progressKm;
  final int acceptedSamples;

  /// Server's machine-readable reason, kept for diagnostics.
  final String? reason;

  final bool canRead;
  final bool canPost;
  final DateTime? mutedUntil;
  final DateTime? expiresAt;

  /// Message safe to show the user.
  final String? message;

  const ChatGateState({
    this.status = ChatGateStatus.idle,
    this.trainNumber,
    this.journeyDate,
    this.displayId,
    this.nickname,
    this.sustainedSeconds = 0,
    this.requiredSeconds = 300,
    this.progressKm = 0,
    this.acceptedSamples = 0,
    this.reason,
    this.canRead = false,
    this.canPost = false,
    this.mutedUntil,
    this.expiresAt,
    this.message,
  });

  ChatGateState copyWith({
    ChatGateStatus? status,
    String? trainNumber,
    String? journeyDate,
    String? displayId,
    String? nickname,
    int? sustainedSeconds,
    int? requiredSeconds,
    double? progressKm,
    int? acceptedSamples,
    String? reason,
    bool? canRead,
    bool? canPost,
    DateTime? mutedUntil,
    DateTime? expiresAt,
    String? message,
  }) {
    return ChatGateState(
      status: status ?? this.status,
      trainNumber: trainNumber ?? this.trainNumber,
      journeyDate: journeyDate ?? this.journeyDate,
      displayId: displayId ?? this.displayId,
      nickname: nickname ?? this.nickname,
      sustainedSeconds: sustainedSeconds ?? this.sustainedSeconds,
      requiredSeconds: requiredSeconds ?? this.requiredSeconds,
      progressKm: progressKm ?? this.progressKm,
      acceptedSamples: acceptedSamples ?? this.acceptedSamples,
      reason: reason ?? this.reason,
      canRead: canRead ?? this.canRead,
      canPost: canPost ?? this.canPost,
      mutedUntil: mutedUntil ?? this.mutedUntil,
      expiresAt: expiresAt ?? this.expiresAt,
      message: message ?? this.message,
    );
  }

  /// 0..1 for a progress ring while verifying.
  double get fraction => requiredSeconds <= 0
      ? 0
      : (sustainedSeconds / requiredSeconds).clamp(0.0, 1.0);

  /// User-facing headline. Deliberately vague about WHY a trace was refused:
  /// a precise explanation is a tuning guide for someone faking a journey.
  String get headline => switch (status) {
        ChatGateStatus.idle => 'Co-passenger chat',
        ChatGateStatus.unavailable => 'Chat is unavailable',
        ChatGateStatus.needsAccount => 'Chat needs an account',
        ChatGateStatus.needsLocation => 'Location access needed',
        ChatGateStatus.verifying => 'Verifying your journey…',
        ChatGateStatus.verified => 'You\'re in the carriage chat',
        ChatGateStatus.rejected => 'Couldn\'t verify this journey',
        ChatGateStatus.expired => 'This journey chat has ended',
        ChatGateStatus.error => 'Chat is unavailable',
      };
}

final chatGateProvider =
    NotifierProvider<ChatGateController, ChatGateState>(ChatGateController.new);

/// Drives the access gate: join, then sample GPS until the server grants or
/// refuses access.
///
/// WHY THIS DOES NOT SHARE THE CROWD-POSITION STREAM
/// -------------------------------------------------
/// `CrowdSharingController` pings every 90s under a ROTATING anonymous id, and
/// the server stores only a non-reversible hash — location there can't be tied
/// to a person. Verification is the opposite by necessity: it must be attributed
/// to the account being granted access, and it needs a 30s cadence to build a
/// 5-minute run. Feeding one stream to both would either starve the gate or make
/// the anonymous crowd data identity-linked. They stay separate on purpose.
class ChatGateController extends Notifier<ChatGateState> {
  /// Fast enough to accumulate ~10 samples inside the 5-minute window.
  static const Duration _sampleInterval = Duration(seconds: 30);

  /// Send after every 2 samples: small and current, because the server discards
  /// samples older than ~2 minutes as replays.
  static const int _batchSize = 2;

  /// Stop sampling if the gate hasn't opened by then, rather than tracking a
  /// user's location indefinitely.
  static const Duration _maxSamplingWindow = Duration(minutes: 15);

  static const Duration _serviceCheckTimeout = Duration(seconds: 6);
  static const Duration _permissionTimeout = Duration(seconds: 20);
  static const Duration _positionTimeout = Duration(seconds: 12);

  Timer? _timer;
  DateTime? _samplingStartedAt;
  final List<ChatGateSample> _buffer = [];

  ChatGateService get _service => ref.read(chatGateServiceProvider);

  @override
  ChatGateState build() {
    ref.onDispose(_cancel);
    return const ChatGateState();
  }

  void _cancel() {
    _timer?.cancel();
    _timer = null;
  }

  /// Leaves the room's sampling loop. Does NOT revoke access already granted.
  void stop() {
    _cancel();
    _buffer.clear();
  }

  /// Ask to enter a journey's chat. Requests location permission only at this
  /// point — never on app launch.
  Future<void> requestAccess({
    required String trainNumber,
    required String journeyDate,
  }) async {
    _cancel();
    _buffer.clear();

    if (!_service.isConfigured) {
      state = state.copyWith(
        status: ChatGateStatus.unavailable,
        message: 'Chat needs the backend to be configured.',
      );
      return;
    }
    if (!_service.hasSession) {
      // Today's reality for every user: no sign-in exists in this build.
      state = state.copyWith(
        status: ChatGateStatus.needsAccount,
        message: 'Journey chat needs a signed-in account. Sign-in isn\'t '
            'available in this build yet.',
      );
      return;
    }

    state = ChatGateState(
      status: ChatGateStatus.verifying,
      trainNumber: trainNumber,
      journeyDate: journeyDate,
    );

    // 1) Claim a pseudonym.
    try {
      final joined = await _service.join(
        trainNumber: trainNumber,
        journeyDate: journeyDate,
      );
      state = state.copyWith(
        displayId: joined.me.displayId,
        nickname: joined.me.nickname,
        canRead: joined.me.canRead,
        canPost: joined.me.canPost,
        mutedUntil: joined.me.mutedUntil,
        expiresAt: joined.room.expiresAt,
        sustainedSeconds: joined.verification.sustainedSeconds,
        requiredSeconds: joined.verification.requiredSeconds,
        progressKm: joined.verification.progressKm,
        acceptedSamples: joined.verification.acceptedSamples,
        reason: joined.verification.reason,
        status: joined.me.canRead
            ? ChatGateStatus.verified
            : ChatGateStatus.verifying,
      );
      if (joined.me.canRead) return; // already verified earlier this journey
    } on ChatGateException catch (e) {
      _applyError(e);
      return;
    }

    // 2) Location permission — only now.
    final located = await _ensureLocation();
    if (!located) return;

    // 3) Sample until the server decides.
    _samplingStartedAt = DateTime.now();
    await _tick();
    _timer = Timer.periodic(_sampleInterval, (_) => _tick());
  }

  Future<bool> _ensureLocation() async {
    try {
      final on = await Geolocator.isLocationServiceEnabled()
          .timeout(_serviceCheckTimeout);
      if (!on) {
        state = state.copyWith(
          status: ChatGateStatus.needsLocation,
          message: 'Turn on location services to join the chat for this train.',
        );
        return false;
      }

      var permission =
          await Geolocator.checkPermission().timeout(_permissionTimeout);
      if (permission == LocationPermission.denied) {
        permission =
            await Geolocator.requestPermission().timeout(_permissionTimeout);
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        // Per spec: denial means no chat. There is no unverified path.
        state = state.copyWith(
          status: ChatGateStatus.needsLocation,
          message: 'Chat is only open to passengers on this train, which needs '
              'location access to confirm.',
        );
        return false;
      }
      return true;
    } on TimeoutException {
      state = state.copyWith(
        status: ChatGateStatus.needsLocation,
        message: 'Couldn\'t check location access. Try again.',
      );
      return false;
    } catch (e) {
      debugPrint('[ChatGate] location setup failed: $e');
      state = state.copyWith(
        status: ChatGateStatus.needsLocation,
        message: 'Location isn\'t available on this device.',
      );
      return false;
    }
  }

  Future<void> _tick() async {
    final train = state.trainNumber;
    final date = state.journeyDate;
    if (train == null || date == null) return;
    if (state.status != ChatGateStatus.verifying) {
      _cancel();
      return;
    }

    // Bound how long we track someone who never verifies.
    final started = _samplingStartedAt;
    if (started != null &&
        DateTime.now().difference(started) > _maxSamplingWindow) {
      _cancel();
      state = state.copyWith(
        message: 'Couldn\'t confirm this journey. You can try again from the '
            'train.',
      );
      return;
    }

    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: _positionTimeout,
        ),
      ).timeout(_positionTimeout);

      _buffer.add(ChatGateSample(
        lat: pos.latitude,
        lng: pos.longitude,
        accuracyM: pos.accuracy.isFinite ? pos.accuracy : null,
        speedKmh: pos.speed.isFinite ? pos.speed * 3.6 : null,
        takenAt: DateTime.now(),
      ));
    } on TimeoutException {
      debugPrint('[ChatGate] no location fix within $_positionTimeout');
      return;
    } catch (e) {
      debugPrint('[ChatGate] sample failed: $e');
      return;
    }

    if (_buffer.length < _batchSize) return;

    final batch = List<ChatGateSample>.from(_buffer);
    _buffer.clear();

    try {
      final v = await _service.submitSamples(
        trainNumber: train,
        journeyDate: date,
        samples: batch,
      );
      final status = v.isVerified
          ? ChatGateStatus.verified
          : (v.isRejected ? ChatGateStatus.rejected : ChatGateStatus.verifying);
      if (status != ChatGateStatus.verifying) _cancel();

      state = state.copyWith(
        status: status,
        sustainedSeconds: v.sustainedSeconds,
        requiredSeconds: v.requiredSeconds,
        progressKm: v.progressKm,
        acceptedSamples: v.acceptedSamples,
        reason: v.reason,
        canRead: v.isVerified,
        canPost: v.isVerified,
      );
      debugPrint('[ChatGate] ${v.status} ${v.sustainedSeconds}/'
          '${v.requiredSeconds}s progress=${v.progressKm}km (${v.reason})');
    } on ChatGateException catch (e) {
      _applyError(e);
    }
  }

  void _applyError(ChatGateException e) {
    _cancel();
    final status = switch (e.code) {
      ChatGateErrorCode.authRequired => ChatGateStatus.needsAccount,
      ChatGateErrorCode.expired => ChatGateStatus.expired,
      ChatGateErrorCode.notConfigured ||
      ChatGateErrorCode.functionNotDeployed =>
        ChatGateStatus.unavailable,
      _ => ChatGateStatus.error,
    };
    state = state.copyWith(status: status, message: e.message);
    debugPrint('[ChatGate] $e');
  }
}
