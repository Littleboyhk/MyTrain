import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/auth_config.dart';
import '../data/chat_account_service.dart';
import '../data/phone_auth_service.dart';
import '../theme/app_theme.dart';
import '../theme/glass_theme.dart';
import '../utils/haptics.dart';
import 'glass.dart';
import 'glass_container.dart';

/// What this sheet is being used for.
///
/// The phone + OTP steps are identical for both; only the tail differs. Chat
/// entry additionally requires the 18+ attestation, whereas signing in from
/// Settings is done as soon as the number is verified — asking someone's age to
/// change an app setting would be gratuitous.
enum PhoneVerificationPurpose {
  /// Entry to co-passenger chat: phone -> OTP -> 18+ attestation.
  chatAccess,

  /// Account sign-in from Settings: phone -> OTP.
  accountLogin,
}

/// How the join flow ended.
enum ChatJoinOutcome {
  /// Signed in AND attested 18+. The caller may start journey verification.
  verified,

  /// Sheet dismissed part-way. Progress is kept — reopening resumes.
  dismissed,

  /// User said they're under 18. Do not prompt again this session.
  declined,

  /// Backend not configured in this build.
  unavailable,
}

/// Entry point for "Join chat".
///
/// Does the pre-flight BEFORE showing anything, so a returning, fully verified
/// user never sees a sheet flash open and closed:
///   * declined earlier this session  -> returns immediately, no prompt
///   * signed in + chat_users.is_adult -> returns [ChatJoinOutcome.verified]
///   * signed in, no attestation       -> sheet opens at the AGE step
///   * not signed in                   -> sheet opens at the PHONE step
Future<ChatJoinOutcome> startChatJoin(
  BuildContext context,
  WidgetRef ref,
) async {
  if (ref.read(chatDeclinedThisSessionProvider)) {
    return ChatJoinOutcome.declined;
  }

  final phoneAuth = ref.read(phoneAuthServiceProvider);
  if (!phoneAuth.isConfigured) return ChatJoinOutcome.unavailable;

  _JoinStep initial = _JoinStep.phone;

  if (phoneAuth.currentUser != null) {
    // Already through phone verification — skip straight past step 1 and 2.
    final status = await ref.read(chatAccountServiceProvider).fetchMine();
    if (status.isEligible) return ChatJoinOutcome.verified;
    initial = _JoinStep.age;
  }

  if (!context.mounted) return ChatJoinOutcome.dismissed;

  final outcome = await showModalBottomSheet<ChatJoinOutcome>(
    context: context,
    // Transparent: the sheet's own glass surface provides the material.
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    isScrollControlled: true,
    // Dismissible at every step; progress is durable (session + attestation
    // both live server-side), so reopening resumes rather than restarts.
    isDismissible: true,
    enableDrag: true,
    builder: (_) => _ChatJoinSheet(
      initialStep: initial,
      purpose: PhoneVerificationPurpose.chatAccess,
    ),
  );

  return outcome ?? ChatJoinOutcome.dismissed;
}

/// Sign in from Settings: phone -> OTP, no age step.
///
/// Returns true once a session exists. Already-signed-in callers get true
/// straight away without a sheet, so this is safe to call unconditionally.
Future<bool> showAccountLoginSheet(
  BuildContext context,
  WidgetRef ref,
) async {
  final phoneAuth = ref.read(phoneAuthServiceProvider);
  if (!phoneAuth.isConfigured) return false;
  if (phoneAuth.currentUser != null) return true;

  final outcome = await showModalBottomSheet<ChatJoinOutcome>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    isScrollControlled: true,
    isDismissible: true,
    enableDrag: true,
    builder: (_) => _ChatJoinSheet(
      initialStep: _JoinStep.phone,
      purpose: PhoneVerificationPurpose.accountLogin,
    ),
  );

  return outcome == ChatJoinOutcome.verified;
}

enum _JoinStep { phone, otp, age }

class _ChatJoinSheet extends ConsumerStatefulWidget {
  const _ChatJoinSheet({required this.initialStep, required this.purpose});

  final _JoinStep initialStep;
  final PhoneVerificationPurpose purpose;

  @override
  ConsumerState<_ChatJoinSheet> createState() => _ChatJoinSheetState();
}

class _ChatJoinSheetState extends ConsumerState<_ChatJoinSheet> {
  late _JoinStep _step;

  final _phoneCtrl = TextEditingController();
  late final List<TextEditingController> _otpCtrls;
  late final List<FocusNode> _otpNodes;
  final _phoneFocus = FocusNode();

  bool _busy = false;
  String? _error;

  String _phoneE164 = '';

  /// Seconds left before the code expires. Drives the resend affordance too.
  int _secondsLeft = 0;
  Timer? _ticker;

  int get _otpLength => AuthConfig.smsOtpLength;

  @override
  void initState() {
    super.initState();
    _step = widget.initialStep;
    _otpCtrls = List.generate(_otpLength, (_) => TextEditingController());
    _otpNodes = List.generate(_otpLength, (_) => FocusNode());
    _phoneCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _phoneCtrl.dispose();
    _phoneFocus.dispose();
    for (final c in _otpCtrls) {
      c.dispose();
    }
    for (final n in _otpNodes) {
      n.dispose();
    }
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Copy mapping: failure reasons -> short human text. Raw exception text stays
  // in the console (phone_auth_service already logs it) and never reaches the UI.
  // ---------------------------------------------------------------------------
  String _copyFor(PhoneAuthFailureReason reason) => switch (reason) {
        PhoneAuthFailureReason.invalidNumber =>
          'That number doesn\'t look right. Check the 10 digits and try again.',
        PhoneAuthFailureReason.rateLimited =>
          'Too many attempts. Wait a moment before trying again.',
        PhoneAuthFailureReason.providerRejected =>
          'We couldn\'t send a code right now. Please try again shortly.',
        PhoneAuthFailureReason.networkError =>
          'No connection. Check your internet and try again.',
        PhoneAuthFailureReason.notConfigured =>
          'Chat isn\'t available in this build.',
        PhoneAuthFailureReason.invalidCode =>
          'That code isn\'t right, or it has expired.',
        PhoneAuthFailureReason.unknown =>
          'Something went wrong. Please try again.',
      };

  // ---------------------------------------------------------------------------
  // Step 1 — phone
  // ---------------------------------------------------------------------------
  bool get _phoneValid =>
      PhoneAuthService.isValidIndianMobile(_phoneCtrl.text.trim());

  Future<void> _sendCode({bool resend = false}) async {
    if (!_phoneValid || _busy) return;
    FocusScope.of(context).unfocus();
    Haptics.tap();

    setState(() {
      _busy = true;
      _error = null;
    });

    final e164 = PhoneAuthService.toE164India(_phoneCtrl.text.trim());
    final result = await ref.read(phoneAuthServiceProvider).sendOtp(e164);
    if (!mounted) return;

    switch (result) {
      case PhoneAuthOtpSent():
        setState(() {
          _busy = false;
          _phoneE164 = e164;
          _step = _JoinStep.otp;
          if (resend) {
            for (final c in _otpCtrls) {
              c.clear();
            }
          }
        });
        _startCountdown();
        // Land the caret in the first box.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _otpNodes.first.requestFocus();
        });
      case PhoneAuthFailure(:final reason):
        setState(() {
          _busy = false;
          _error = _copyFor(reason);
        });
      case PhoneAuthSignedIn():
        setState(() => _busy = false);
    }
  }

  void _startCountdown() {
    _ticker?.cancel();
    setState(() => _secondsLeft = AuthConfig.smsOtpExpirySeconds);
    _ticker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _secondsLeft = _secondsLeft > 0 ? _secondsLeft - 1 : 0);
      if (_secondsLeft == 0) t.cancel();
    });
  }

  // ---------------------------------------------------------------------------
  // Step 2 — OTP
  // ---------------------------------------------------------------------------
  String get _otpValue => _otpCtrls.map((c) => c.text).join();

  void _onOtpChanged(int index, String value) {
    // Autofill / paste can drop the whole code into one box: spread it out.
    if (value.length > 1) {
      final digits = value.replaceAll(RegExp(r'\D'), '');
      for (var i = 0; i < _otpLength; i++) {
        final pos = index + i;
        if (pos >= _otpLength || i >= digits.length) break;
        _otpCtrls[pos].text = digits[i];
      }
      final next = (index + digits.length).clamp(0, _otpLength - 1);
      _otpNodes[next].requestFocus();
      setState(() {});
      _maybeAutoSubmit();
      return;
    }

    if (value.isNotEmpty && index < _otpLength - 1) {
      _otpNodes[index + 1].requestFocus();
    } else if (value.isEmpty && index > 0) {
      _otpNodes[index - 1].requestFocus();
    }
    setState(() {});
    _maybeAutoSubmit();
  }

  void _maybeAutoSubmit() {
    if (_otpValue.length == _otpLength && !_busy) {
      // Auto-submit on the last digit — no extra button press.
      _verify();
    }
  }

  Future<void> _verify() async {
    if (_busy) return;
    final token = _otpValue;
    if (token.length != _otpLength) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });

    final result = await ref
        .read(phoneAuthServiceProvider)
        .verifyOtp(phoneE164: _phoneE164, token: token);
    if (!mounted) return;

    switch (result) {
      case PhoneAuthSignedIn():
        _ticker?.cancel();
        Haptics.confirm();
        // Settings sign-in is finished the moment the number is verified.
        if (widget.purpose == PhoneVerificationPurpose.accountLogin) {
          Navigator.of(context).pop(ChatJoinOutcome.verified);
          return;
        }
        // Chat entry — does this account already have an attestation?
        final status = await ref.read(chatAccountServiceProvider).fetchMine();
        if (!mounted) return;
        if (status.isEligible) {
          Navigator.of(context).pop(ChatJoinOutcome.verified);
          return;
        }
        setState(() {
          _busy = false;
          _step = _JoinStep.age;
        });
      case PhoneAuthFailure(:final reason):
        setState(() {
          _busy = false;
          _error = _copyFor(reason);
          for (final c in _otpCtrls) {
            c.clear();
          }
        });
        _otpNodes.first.requestFocus();
      case PhoneAuthOtpSent():
        setState(() => _busy = false);
    }
  }

  void _changeNumber() {
    Haptics.tap();
    _ticker?.cancel();
    setState(() {
      _step = _JoinStep.phone;
      _error = null;
      _secondsLeft = 0;
      for (final c in _otpCtrls) {
        c.clear();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _phoneFocus.requestFocus();
    });
  }

  // ---------------------------------------------------------------------------
  // Step 3 — age attestation
  // ---------------------------------------------------------------------------
  Future<void> _confirmAdult() async {
    if (_busy) return;
    Haptics.confirm();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final status =
          await ref.read(chatAccountServiceProvider).attestAge(isAdult: true);
      if (!mounted) return;
      if (!status.isEligible) {
        setState(() {
          _busy = false;
          _error = 'Couldn\'t save that just now. Please try again.';
        });
        return;
      }
      Navigator.of(context).pop(ChatJoinOutcome.verified);
    } on ChatAccountException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }

  Future<void> _declineAdult() async {
    if (_busy) return;
    Haptics.tap();
    setState(() => _busy = true);

    // Recorded server-side for audit; the session flag is what stops re-prompting.
    try {
      await ref.read(chatAccountServiceProvider).attestAge(isAdult: false);
    } on ChatAccountException catch (_) {
      // Not worth blocking the exit on — the user said no either way.
    }
    if (!mounted) return;
    ref.read(chatDeclinedThisSessionProvider.notifier).markDeclined();
    Navigator.of(context).pop(ChatJoinOutcome.declined);
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final g = context.glass;
    final media = MediaQuery.of(context);

    return Padding(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        // Lift above the keyboard as well as the gesture area.
        bottom: 12 + media.viewInsets.bottom + media.viewPadding.bottom,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: media.size.height * 0.86),
        child: GlassContainer(
          radius: 28,
          blurSigma: 24,
          strong: true,
          glow: true,
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: g.textMuted.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _header(g),
                const SizedBox(height: 18),
                // Swapped content, no navigation.
                AnimatedSize(
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: KeyedSubtree(
                      key: ValueKey(_step),
                      child: switch (_step) {
                        _JoinStep.phone => _phoneStep(g),
                        _JoinStep.otp => _otpStep(g),
                        _JoinStep.age => _ageStep(g),
                      },
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

  Widget _header(GlassTheme g) {
    final bool login = widget.purpose == PhoneVerificationPurpose.accountLogin;

    final (title, subtitle) = switch (_step) {
      _JoinStep.phone => (
          login ? 'Sign in' : 'Join the chat',
          login
              ? 'We\'ll text you a one-time code. Your number is only used to '
                  'sign in and is never shown to other passengers.'
              : 'Verify your number so co-passengers know you\'re a real '
                  'traveller. Your number is never shown to anyone.',
        ),
      _JoinStep.otp => (
          'Enter the code',
          'Sent to $_phoneE164',
        ),
      _JoinStep.age => (
          'One last thing',
          'Chat connects you with strangers on this train.',
        ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: AppText.titleStrong
                    .copyWith(color: g.textPrimary, fontSize: 21),
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () =>
                  Navigator.of(context).pop(ChatJoinOutcome.dismissed),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(Icons.close_rounded,
                    size: 22, color: g.textSecondary),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: AppText.label
              .copyWith(color: g.textMuted, fontSize: 12.5, height: 1.4),
        ),
      ],
    );
  }

  // ---- step 1 ---------------------------------------------------------------
  Widget _phoneStep(GlassTheme g) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
              decoration: BoxDecoration(
                color: glassFill(context, strong: true),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: glassStroke(context).withValues(alpha: 0.25),
                ),
              ),
              child: Text(
                '+91',
                style: TextStyle(
                  color: g.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: glassFill(context),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: glassStroke(context).withValues(alpha: 0.25),
                  ),
                ),
                child: TextField(
                  controller: _phoneCtrl,
                  focusNode: _phoneFocus,
                  autofocus: true,
                  keyboardType: TextInputType.phone,
                  maxLength: 10,
                  enabled: !_busy,
                  style: TextStyle(
                    color: g.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                  ),
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    counterText: '',
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 16),
                    hintText: '10-digit mobile',
                    hintStyle: TextStyle(
                      color: g.textMuted.withValues(alpha: 0.7),
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0,
                    ),
                  ),
                  onSubmitted: (_) => _sendCode(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Exactly what will be sent — no surprises.
        Text(
          _phoneCtrl.text.isEmpty
              ? 'We\'ll send a one-time code by SMS.'
              : 'Code goes to ${PhoneAuthService.toE164India(_phoneCtrl.text)}',
          style: AppText.label.copyWith(color: g.textMuted, fontSize: 11.5),
        ),
        if (_error != null) _errorText(g, _error!),
        const SizedBox(height: 16),
        _primaryButton(
          g,
          label: 'Send code',
          enabled: _phoneValid,
          onTap: _sendCode,
        ),
      ],
    );
  }

  // ---- step 2 ---------------------------------------------------------------
  Widget _otpStep(GlassTheme g) {
    final expired = _secondsLeft == 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var i = 0; i < _otpLength; i++) _otpBox(g, i),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Icon(
              expired ? Icons.timer_off_rounded : Icons.timer_outlined,
              size: 14,
              color: expired ? g.statusRed : g.textMuted,
            ),
            const SizedBox(width: 6),
            Text(
              expired
                  ? 'Code expired'
                  : 'Expires in ${_secondsLeft ~/ 60}:'
                      '${(_secondsLeft % 60).toString().padLeft(2, '0')}',
              style: AppText.label.copyWith(
                color: expired ? g.statusRed : g.textMuted,
                fontSize: 12,
              ),
            ),
          ],
        ),
        if (_error != null) _errorText(g, _error!),
        const SizedBox(height: 16),
        _primaryButton(
          g,
          label: 'Verify',
          enabled: _otpValue.length == _otpLength,
          onTap: _verify,
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            _linkButton(
              g,
              label: 'Resend code',
              // Enabled only once the previous code is dead, which also
              // satisfies the provider's minimum gap between sends.
              enabled: expired && !_busy,
              onTap: () => _sendCode(resend: true),
            ),
            const Spacer(),
            _linkButton(
              g,
              label: 'Change number',
              enabled: !_busy,
              onTap: _changeNumber,
            ),
          ],
        ),
      ],
    );
  }

  Widget _otpBox(GlassTheme g, int i) {
    final filled = _otpCtrls[i].text.isNotEmpty;
    final focused = _otpNodes[i].hasFocus;
    return SizedBox(
      width: 46,
      height: 56,
      child: Container(
        decoration: BoxDecoration(
          color: glassFill(context, strong: filled),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: focused
                ? GlassTheme.accentIndigo
                : glassStroke(context).withValues(alpha: 0.25),
            width: focused ? 1.6 : 1,
          ),
          boxShadow: focused
              ? [
                  BoxShadow(
                    color: GlassTheme.accentIndigo.withValues(alpha: 0.28),
                    blurRadius: 12,
                    spreadRadius: -3,
                  ),
                ]
              : const [],
        ),
        child: TextField(
          controller: _otpCtrls[i],
          focusNode: _otpNodes[i],
          enabled: !_busy,
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          // Lets Android drop the SMS code straight in.
          autofillHints: i == 0 ? const [AutofillHints.oneTimeCode] : null,
          style: TextStyle(
            color: g.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            counterText: '',
            border: InputBorder.none,
            contentPadding: EdgeInsets.zero,
          ),
          onChanged: (v) => _onOtpChanged(i, v),
        ),
      ),
    );
  }

  // ---- step 3 ---------------------------------------------------------------
  Widget _ageStep(GlassTheme g) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: glassFill(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: glassStroke(context).withValues(alpha: 0.25),
            ),
          ),
          child: Text(
            'You must be 18 or older to use chat with other passengers.',
            style: TextStyle(
              color: g.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              height: 1.45,
            ),
          ),
        ),
        if (_error != null) _errorText(g, _error!),
        const SizedBox(height: 16),
        // Both options are full width and the same height: declining is exactly
        // as easy as confirming.
        _primaryButton(
          g,
          label: 'I confirm I am 18 or older',
          enabled: true,
          onTap: _confirmAdult,
        ),
        const SizedBox(height: 10),
        _secondaryButton(
          g,
          label: 'I\'m under 18',
          enabled: !_busy,
          onTap: _declineAdult,
        ),
      ],
    );
  }

  // ---- shared bits ----------------------------------------------------------
  Widget _errorText(GlassTheme g, String message) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, size: 15, color: g.statusRed),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: g.statusRed,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Primary action — mirrors the submit button in the language picker sheet.
  Widget _primaryButton(
    GlassTheme g, {
    required String label,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    final active = enabled && !_busy;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: active ? onTap : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: active ? 1 : 0.45,
        child: Container(
          height: 52,
          width: double.infinity,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: active
                ? GlassTheme.accent
                : LinearGradient(colors: [g.fill, g.fill]),
            borderRadius: BorderRadius.circular(999),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: GlassTheme.accentIndigo.withValues(alpha: 0.45),
                      blurRadius: 18,
                      spreadRadius: -3,
                    ),
                  ]
                : const [],
          ),
          child: _busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                )
              : Text(
                  label,
                  style: TextStyle(
                    color: active ? Colors.white : g.textMuted,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
      ),
    );
  }

  /// Same footprint as [_primaryButton], glass instead of accent fill.
  Widget _secondaryButton(
    GlassTheme g, {
    required String label,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: enabled ? 1 : 0.45,
        child: Container(
          height: 52,
          width: double.infinity,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: glassFill(context, strong: true),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: glassStroke(context).withValues(alpha: 0.35),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: g.textPrimary,
              fontSize: 15.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  Widget _linkButton(
    GlassTheme g, {
    required String label,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          label,
          style: TextStyle(
            color: enabled ? GlassTheme.accentIndigo : g.textMuted,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
