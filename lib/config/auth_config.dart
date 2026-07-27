import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Auth-side tunables that must MIRROR the Supabase dashboard.
///
/// These are read from `.env` / `--dart-define` rather than hardcoded, because
/// they duplicate server settings that can change without a code deploy — and a
/// countdown that disagrees with the server is worse than no countdown.
///
/// Current server values (read from the project's auth config):
///   sms_otp_exp       = 60   <-- NOT 300. Raise it in the dashboard, then set
///                                SMS_OTP_EXP_SECONDS to match.
///   sms_max_frequency = 5    (minimum seconds between sends, per number)
///   sms_otp_length    = 6
class AuthConfig {
  const AuthConfig._();

  static int _intFrom(String key, int fallback) {
    const fromDefine = String.fromEnvironment('SMS_OTP_EXP_SECONDS');
    if (key == 'SMS_OTP_EXP_SECONDS' && fromDefine.isNotEmpty) {
      return int.tryParse(fromDefine) ?? fallback;
    }
    try {
      final raw = dotenv.env[key]?.trim();
      if (raw == null || raw.isEmpty) return fallback;
      return int.tryParse(raw) ?? fallback;
    } catch (_) {
      return fallback;
    }
  }

  /// How long an SMS code stays valid. Mirrors `sms_otp_exp`.
  ///
  /// Default is the project's ACTUAL current value (60s), deliberately not the
  /// intended 300s: showing a 5-minute countdown while the server expires the
  /// code after 60s would tell the user a lie.
  static int get smsOtpExpirySeconds => _intFrom('SMS_OTP_EXP_SECONDS', 60);

  /// Minimum gap between OTP sends. Mirrors `sms_max_frequency`.
  static int get smsResendCooldownSeconds =>
      _intFrom('SMS_RESEND_COOLDOWN_SECONDS', 5);

  /// Digits in the code. Mirrors `sms_otp_length`.
  static int get smsOtpLength => _intFrom('SMS_OTP_LENGTH', 6);
}
