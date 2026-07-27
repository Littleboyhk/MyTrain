import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

/// Phone (SMS OTP) auth against Supabase.
///
/// ISOLATED CONNECTIVITY TEST. Nothing in the app depends on this yet; it exists
/// so phone auth can be proven end-to-end on a real device before any chat UI is
/// built on top of it. Deleting this file plus `lib/debug/phone_auth_test_screen.dart`
/// and the debug route in `main.dart` removes the feature entirely.
///
/// Every failure keeps the EXACT upstream message. Supabase forwards Twilio's
/// text verbatim — a real response looks like:
///
///   {"code":422,"error_code":"sms_send_failed",
///    "msg":"Error sending confirmation OTP to provider: Invalid 'To' Phone
///           Number: +91111111XXXX More information:
///           https://www.twilio.com/docs/errors/21211"}
///
/// so the Twilio error number is recoverable and worth surfacing.
enum PhoneAuthFailureReason {
  /// Number rejected as malformed/unroutable (Twilio 21211 and friends).
  invalidNumber,

  /// Supabase or Twilio throttled us. Project config: one SMS per 5s per
  /// number, 30 per hour per project.
  rateLimited,

  /// Wrong OTP, or the code aged out. Supabase reports BOTH as `otp_expired`,
  /// so they cannot be told apart from the response.
  invalidCode,

  /// Never reached the server.
  networkError,

  /// The provider accepted the request but refused to send. This is the bucket
  /// that DLT / sender-registration / wrong-SID problems land in, which is why
  /// it is separate from [invalidNumber] even though the brief listed five
  /// reasons: "your number is bad" and "our account can't send to India" need
  /// very different fixes.
  providerRejected,

  /// No Supabase credentials in this build.
  notConfigured,

  unknown,
}

sealed class PhoneAuthResult {
  const PhoneAuthResult({required this.elapsed});

  /// Wall-clock time for the call, so slow Twilio responses are visible.
  final Duration elapsed;
}

/// OTP dispatched. Supabase returns no body, so this only means the provider
/// accepted the request — not that the SMS arrived.
class PhoneAuthOtpSent extends PhoneAuthResult {
  const PhoneAuthOtpSent({required super.elapsed, required this.phone});

  final String phone;
}

class PhoneAuthSignedIn extends PhoneAuthResult {
  const PhoneAuthSignedIn({
    required super.elapsed,
    required this.userId,
    required this.phone,
    required this.isNewUser,
  });

  final String userId;
  final String? phone;

  /// Rough signal: the account was created by this verification.
  final bool isNewUser;
}

class PhoneAuthFailure extends PhoneAuthResult {
  const PhoneAuthFailure({
    required super.elapsed,
    required this.reason,
    required this.label,
    required this.rawMessage,
    this.errorCode,
    this.statusCode,
    this.twilioErrorCode,
  });

  final PhoneAuthFailureReason reason;

  /// Short, user-safe label.
  final String label;

  /// The untouched upstream text. Never hidden, never rewritten.
  final String rawMessage;

  /// Supabase `error_code`, e.g. `sms_send_failed`, `otp_expired`.
  final String? errorCode;
  final String? statusCode;

  /// Parsed out of the forwarded Twilio message when present, e.g. 21211.
  final int? twilioErrorCode;

  String get twilioDocsUrl => twilioErrorCode == null
      ? ''
      : 'https://www.twilio.com/docs/errors/$twilioErrorCode';

  @override
  String toString() =>
      'PhoneAuthFailure(${reason.name}, error_code=$errorCode, '
      'status=$statusCode, twilio=$twilioErrorCode): $rawMessage';
}

class PhoneAuthService {
  const PhoneAuthService();

  bool get isConfigured => SupabaseConfig.isConfigured;

  GoTrueClient get _auth => Supabase.instance.client.auth;

  Session? get currentSession => isConfigured ? _auth.currentSession : null;
  User? get currentUser => isConfigured ? _auth.currentUser : null;

  /// Compose E.164 for India from 10 local digits. Supabase does NOT validate
  /// the format: it prepends '+' and hands the string to Twilio, so a bare
  /// '9876543210' is sent as '+9876543210' and fails as an invalid number.
  static String toE164India(String localDigits) {
    final digits = localDigits.replaceAll(RegExp(r'\D'), '');
    return '+91$digits';
  }

  /// True for a plausible Indian mobile: 10 digits starting 6-9.
  static bool isValidIndianMobile(String localDigits) {
    final digits = localDigits.replaceAll(RegExp(r'\D'), '');
    return RegExp(r'^[6-9]\d{9}$').hasMatch(digits);
  }

  Future<PhoneAuthResult> sendOtp(String phoneE164) async {
    final sw = Stopwatch()..start();
    if (!isConfigured) {
      return _notConfigured(sw);
    }
    try {
      await _auth.signInWithOtp(
        phone: phoneE164,
        channel: OtpChannel.sms,
      );
      sw.stop();
      debugPrint('[PhoneAuth] OTP send accepted for $phoneE164 '
          'in ${sw.elapsedMilliseconds}ms');
      return PhoneAuthOtpSent(elapsed: sw.elapsed, phone: phoneE164);
    } catch (e) {
      return _mapError(e, sw, sending: true);
    }
  }

  Future<PhoneAuthResult> verifyOtp({
    required String phoneE164,
    required String token,
  }) async {
    final sw = Stopwatch()..start();
    if (!isConfigured) {
      return _notConfigured(sw);
    }
    try {
      final res = await _auth.verifyOTP(
        phone: phoneE164,
        token: token,
        type: OtpType.sms,
      );
      sw.stop();
      final user = res.user;
      if (user == null) {
        debugPrint('[PhoneAuth] verify returned no user');
        return PhoneAuthFailure(
          elapsed: sw.elapsed,
          reason: PhoneAuthFailureReason.unknown,
          label: 'Verified but no session returned',
          rawMessage: 'verifyOTP succeeded with a null user',
        );
      }
      // createdAt/lastSignInAt within a few seconds of each other => first login.
      final created = DateTime.tryParse(user.createdAt);
      final lastSignIn =
          user.lastSignInAt == null ? null : DateTime.tryParse(user.lastSignInAt!);
      final isNew = created != null &&
          lastSignIn != null &&
          lastSignIn.difference(created).abs() < const Duration(seconds: 5);

      debugPrint('[PhoneAuth] signed in as ${user.id} '
          'in ${sw.elapsedMilliseconds}ms (new=$isNew)');
      return PhoneAuthSignedIn(
        elapsed: sw.elapsed,
        userId: user.id,
        phone: user.phone,
        isNewUser: isNew,
      );
    } catch (e) {
      return _mapError(e, sw, sending: false);
    }
  }

  Future<void> signOut() async {
    if (!isConfigured) return;
    try {
      await _auth.signOut();
      debugPrint('[PhoneAuth] signed out');
    } catch (e) {
      debugPrint('[PhoneAuth] sign out failed: $e');
    }
  }

  PhoneAuthFailure _notConfigured(Stopwatch sw) {
    sw.stop();
    const msg = 'SUPABASE_URL / SUPABASE_ANON_KEY missing from .env and '
        '--dart-define; the app is in offline mode.';
    debugPrint('[PhoneAuth] not configured: $msg');
    return PhoneAuthFailure(
      elapsed: sw.elapsed,
      reason: PhoneAuthFailureReason.notConfigured,
      label: 'Backend not configured',
      rawMessage: msg,
    );
  }

  PhoneAuthFailure _mapError(Object e, Stopwatch sw, {required bool sending}) {
    sw.stop();

    // The real error always goes to the console, whatever the UI shows.
    debugPrint('[PhoneAuth] ${sending ? 'send' : 'verify'} FAILED '
        'after ${sw.elapsedMilliseconds}ms: ${e.runtimeType} -> $e');

    if (e is AuthException) {
      final code = e.code;
      final status = e.statusCode;
      final msg = e.message;
      final twilio = _parseTwilioCode(msg);

      if (e is AuthRetryableFetchException) {
        return PhoneAuthFailure(
          elapsed: sw.elapsed,
          reason: PhoneAuthFailureReason.networkError,
          label: 'Network error',
          rawMessage: msg,
          errorCode: code,
          statusCode: status,
        );
      }

      final reason = _reasonFor(
        code: code,
        status: status,
        message: msg,
        twilio: twilio,
        sending: sending,
      );

      return PhoneAuthFailure(
        elapsed: sw.elapsed,
        reason: reason,
        label: _labelFor(reason),
        rawMessage: msg,
        errorCode: code,
        statusCode: status,
        twilioErrorCode: twilio,
      );
    }

    if (e is SocketException || e is TimeoutException || e is HttpException) {
      return PhoneAuthFailure(
        elapsed: sw.elapsed,
        reason: PhoneAuthFailureReason.networkError,
        label: 'Network error',
        rawMessage: e.toString(),
      );
    }

    return PhoneAuthFailure(
      elapsed: sw.elapsed,
      reason: PhoneAuthFailureReason.unknown,
      label: 'Unexpected error',
      rawMessage: e.toString(),
    );
  }

  PhoneAuthFailureReason _reasonFor({
    required String? code,
    required String? status,
    required String message,
    required int? twilio,
    required bool sending,
  }) {
    final m = message.toLowerCase();

    // Rate limiting comes back on several codes plus HTTP 429.
    if (status == '429' ||
        code == 'over_sms_send_rate_limit' ||
        code == 'over_request_rate_limit' ||
        code == 'over_email_send_rate_limit' ||
        m.contains('rate limit') ||
        m.contains('for security purposes') ||
        twilio == 60203 || // Verify: max send attempts
        twilio == 60202) {
      // Verify: max check attempts
      return PhoneAuthFailureReason.rateLimited;
    }

    // Wrong OR expired code — Supabase does not distinguish them.
    if (code == 'otp_expired' ||
        code == 'otp_disabled' ||
        m.contains('token has expired or is invalid') ||
        twilio == 60022) {
      return PhoneAuthFailureReason.invalidCode;
    }

    // Malformed / unroutable destination number.
    if (twilio == 21211 ||
        twilio == 21214 ||
        twilio == 60200 ||
        code == 'validation_failed' ||
        m.contains("invalid 'to' phone number") ||
        m.contains('invalid phone')) {
      return PhoneAuthFailureReason.invalidNumber;
    }

    // Provider took the request but would not send it: sender/DLT registration,
    // region permissions, wrong service SID, unverified trial recipient.
    if (code == 'sms_send_failed' ||
        m.contains('error sending confirmation otp to provider')) {
      return PhoneAuthFailureReason.providerRejected;
    }

    return PhoneAuthFailureReason.unknown;
  }

  String _labelFor(PhoneAuthFailureReason r) => switch (r) {
        PhoneAuthFailureReason.invalidNumber => 'Invalid phone number',
        PhoneAuthFailureReason.rateLimited => 'Too many attempts',
        PhoneAuthFailureReason.invalidCode => 'Wrong or expired code',
        PhoneAuthFailureReason.networkError => 'Network error',
        PhoneAuthFailureReason.providerRejected => 'SMS provider refused to send',
        PhoneAuthFailureReason.notConfigured => 'Backend not configured',
        PhoneAuthFailureReason.unknown => 'Unexpected error',
      };

  /// Pulls the Twilio error number out of the forwarded message. Supabase
  /// includes the docs link, e.g. `.../docs/errors/21211`.
  static int? _parseTwilioCode(String message) {
    final url = RegExp(r'twilio\.com/docs/errors/(\d{4,6})').firstMatch(message);
    if (url != null) return int.tryParse(url.group(1)!);
    final bare = RegExp(r'\b(?:error|code)\s*:?\s*(\d{5})\b', caseSensitive: false)
        .firstMatch(message);
    if (bare != null) return int.tryParse(bare.group(1)!);
    return null;
  }
}

final phoneAuthServiceProvider =
    Provider<PhoneAuthService>((ref) => const PhoneAuthService());

/// The signed-in user, or null. Emits immediately, then on every auth change.
///
/// `onAuthStateChange` alone is not enough for a screen that can be opened at
/// any time: it only fires on subsequent events, so the current user is yielded
/// first. Yields null forever when Supabase isn't configured, which keeps the
/// UI honest in offline builds instead of throwing.
final authUserProvider = StreamProvider<User?>((ref) async* {
  if (!SupabaseConfig.isConfigured) {
    yield null;
    return;
  }
  final auth = Supabase.instance.client.auth;
  yield auth.currentUser;
  yield* auth.onAuthStateChange.map((event) => event.session?.user);
});
