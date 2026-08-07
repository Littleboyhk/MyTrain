import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/emergency_contact_store.dart';
import '../data/nearest_station_service.dart';
import '../data/sos_audit_log.dart';
import '../data/sos_context.dart';
import '../screens/settings_screen.dart' show openEmergencyContactSettings;
import '../theme/app_theme.dart';
import '../theme/glass_theme.dart';
import '../utils/haptics.dart';
import 'glass_container.dart';

/// The real launcher. `externalApplication` because `tel:` and `sms:` must leave
/// the app — the default mode can try an in-app web view for non-http schemes on
/// some platforms.
Future<bool> defaultSosUrlLauncher(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);

/// Indirection for the one external side effect this feature has.
///
/// Production never reassigns this. Tests do, so that "tap Call 139 → `tel:139`"
/// can be asserted end to end: `tel:` and `sms:` intents do not resolve on
/// Flutter Web or on emulators without a dialer, so a test that went through the
/// real plugin could only ever assert that launching failed.
///
/// Same static-mutable-with-a-reason shape as `Fmt.use12HourClock` and
/// `AppColors.palette`.
@visibleForTesting
Future<bool> Function(Uri uri) sosUrlLauncher = defaultSosUrlLauncher;

/// Opens the Emergency sheet.
///
/// NOTHING IN HERE FIRES BY ITSELF. There is no countdown, no auto-dial, no
/// background send, and no silent anything: the sheet opening is one tap, and
/// every action inside it costs another. Both call buttons hand off to the OS
/// dialer PRE-FILLED (the user presses the dialer's own call button), and the
/// text action hands off to the OS messaging app PRE-FILLED (the user presses
/// Send). That is what keeps this feature free of `CALL_PHONE` and `SEND_SMS`.
///
/// [trainNumber] / [trainName] come from the caller's tracking state. Both null
/// is a supported, tested case: SOS works standalone and simply omits the train
/// and coach lines rather than showing them blank.
Future<void> showEmergencySheet(
  BuildContext context, {
  String? trainNumber,
  String? trainName,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _EmergencySheet(
      trainNumber: trainNumber,
      trainName: trainName,
    ),
  );
}

class _EmergencySheet extends ConsumerStatefulWidget {
  const _EmergencySheet({this.trainNumber, this.trainName});

  final String? trainNumber;
  final String? trainName;

  @override
  ConsumerState<_EmergencySheet> createState() => _EmergencySheetState();
}

class _EmergencySheetState extends ConsumerState<_EmergencySheet> {
  late final TextEditingController _coach =
      TextEditingController(text: ref.read(sessionCoachProvider) ?? '');

  SosLocation _location = const SosLocationResolving();
  bool _locating = true;

  /// Inline problem report, e.g. no app on the device that can handle `tel:`.
  /// Shown in place rather than as a toast: a snackbar behind a full-height sheet
  /// would be invisible.
  String? _notice;

  @override
  void initState() {
    super.initState();
    // Fire and forget. The sheet is already on screen by the time this resolves,
    // and it settles for "Location unavailable" after kSosLocationTimeout rather
    // than making the user wait to reach a call button.
    _resolveLocation();
  }

  @override
  void dispose() {
    _coach.dispose();
    super.dispose();
  }

  Future<void> _resolveLocation({bool requestPermission = false}) async {
    if (mounted) setState(() => _locating = true);
    final result = await resolveSosLocation(
      ref.read(nearestStationServiceProvider),
      requestPermission: requestPermission,
    );
    if (!mounted) return;
    setState(() {
      _location = result;
      _locating = false;
    });
  }

  SosContext _sosContext(String? pnr) => SosContext(
        trainNumber: widget.trainNumber,
        trainName: widget.trainName,
        coach: _coach.text,
        pnr: pnr,
        location: _location,
      );

  // ---------------------------------------------------------------------------
  // Actions — each one reached only by a deliberate tap
  // ---------------------------------------------------------------------------

  Future<void> _call(SosHelpline line) async {
    Haptics.confirm();
    // Both captured BEFORE the await: `ref` is invalid once this State is
    // disposed, and the sheet can be dismissed while the dialer is opening.
    // Losing the log entry for a real emergency because the user swiped the sheet
    // away would defeat the point of having one.
    final audit = ref.read(sosAuditLogProvider.notifier);
    final snapshot = _sosContext(ref.read(sessionPnrProvider));

    final outcome = await _launch(
      sosTelUri(line.number),
      'Couldn\'t open the dialer. Dial ${line.number} directly.',
    );

    audit.record(
      action: line.number == SosHelpline.railway.number
          ? SosAuditAction.callRailwayHelpline
          : SosAuditAction.callEmergency,
      outcome: outcome,
      context: snapshot,
    );
  }

  Future<void> _text(EmergencyContact contact, String? pnr) async {
    Haptics.confirm();
    final audit = ref.read(sosAuditLogProvider.notifier);
    final snapshot = _sosContext(pnr);
    final body = composeSosMessage(snapshot);

    final outcome = await _launch(
      sosSmsUri(contact.dialNumber, body),
      'Couldn\'t open your messaging app. The message was copied instead — '
      'paste it into any app.',
      clipboardOnFailure: body,
    );

    audit.record(
      action: SosAuditAction.textContact,
      outcome: outcome,
      context: snapshot,
      contactLabel: contact.displayLabel,
      // Masked only. The full number is already in the contacts list and a log
      // is the last place to duplicate it in the clear.
      contactMasked: contact.maskedNumber,
    );
  }

  /// The gated path: no contact saved yet, so send them to the setting rather
  /// than to a dead button.
  ///
  /// Settings is PUSHED OVER this sheet instead of replacing it, so returning
  /// lands back here with the context (and the typed coach) intact and the text
  /// action now live.
  Future<void> _addContact() async {
    Haptics.tap();

    // Logged BEFORE navigating, and logged as its own distinct shape: the user
    // reached for help and the app had nothing to reach with. That is exactly the
    // kind of gap worth seeing afterwards.
    ref.read(sosAuditLogProvider.notifier).record(
          action: SosAuditAction.textContact,
          outcome: SosAuditOutcome.notAttempted,
          context: _sosContext(ref.read(sessionPnrProvider)),
          noContactFallback: true,
        );

    await openEmergencyContactSettings(context);
  }

  /// Hands [uri] to the OS. Returns what actually happened, so the audit log can
  /// record the difference between "opened on your phone" and "tap only".
  Future<SosAuditOutcome> _launch(
    Uri uri,
    String fallbackMessage, {
    String? clipboardOnFailure,
  }) async {
    bool ok = false;
    try {
      ok = await sosUrlLauncher(uri);
    } catch (e) {
      // Web and most emulators have no dialer or SMS app to hand off to, and
      // throw here. A real device is the only place this path is meaningful.
      debugPrint('[SOS] launch failed for ${uri.scheme}: $e');
    }
    if (ok) return SosAuditOutcome.handedOff;

    if (clipboardOnFailure != null) {
      await Clipboard.setData(ClipboardData(text: clipboardOnFailure));
    }
    if (mounted) setState(() => _notice = fallbackMessage);
    return SosAuditOutcome.launchFailed;
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final g = context.glass;
    final contacts = ref.watch(emergencyContactsProvider);
    final pnr = ref.watch(sessionPnrProvider);

    return Padding(
      // Lift clear of the keyboard when the coach field is being edited.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: GlassContainer(
        radius: 30,
        blurSigma: 26,
        strong: true,
        glow: true,
        glowColor: g.statusRed,
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _handle(g),
              _header(g),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _contextCard(g, pnr),
                      const SizedBox(height: 18),
                      _callButton(g, SosHelpline.railway),
                      const SizedBox(height: 12),
                      _callButton(g, SosHelpline.emergency),
                      const SizedBox(height: 18),
                      ..._textActions(g, contacts, pnr),
                      if (_notice != null) ...[
                        const SizedBox(height: 16),
                        _noticeRow(g),
                      ],
                      const SizedBox(height: 10),
                      Text(
                        'Nothing is sent or dialled automatically. Each action '
                        'opens your phone\'s own dialer or messaging app, '
                        'pre-filled, for you to confirm.',
                        textAlign: TextAlign.center,
                        style: AppText.label.copyWith(
                          color: g.textMuted,
                          fontSize: 11.5,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _handle(GlassTheme g) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Center(
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: g.textMuted.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ),
    );
  }

  Widget _header(GlassTheme g) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 10, 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: g.statusRed.withValues(alpha: 0.18),
              shape: BoxShape.circle,
              border: Border.all(color: g.statusRed.withValues(alpha: 0.45)),
            ),
            child: Icon(Icons.sos_rounded, size: 20, color: g.statusRed),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Emergency',
                  style: AppText.titleStrong
                      .copyWith(color: g.textPrimary, fontSize: 21),
                ),
                const SizedBox(height: 2),
                Text(
                  'Your details are already filled in below',
                  style:
                      AppText.label.copyWith(color: g.textMuted, fontSize: 12.5),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 20),
            color: g.textSecondary,
            onPressed: () {
              Haptics.tap();
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }

  /// Train / coach / location — the three things the passenger would otherwise
  /// have to recite under stress.
  Widget _contextCard(GlassTheme g, String? pnr) {
    final trainLine = _sosContext(pnr).trainLine;

    return GlassContainer(
      radius: 20,
      blurSigma: 0,
      strong: true,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          // Omitted entirely with no train tracked, rather than shown blank.
          if (trainLine != null) ...[
            _infoRow(
              g,
              icon: Icons.train_rounded,
              label: 'TRAIN',
              child: Text(
                trainLine,
                style: AppText.label.copyWith(
                  color: g.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            _divider(g),
            _infoRow(
              g,
              icon: Icons.event_seat_rounded,
              label: 'COACH',
              child: TextField(
                controller: _coach,
                textCapitalization: TextCapitalization.characters,
                maxLength: 8,
                // Kept in session state so closing and reopening the sheet — or
                // a trip to Settings and back — never loses what was typed.
                onChanged: (v) => ref.read(sessionCoachProvider.notifier).set(v),
                style: AppText.label.copyWith(
                  color: g.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
                decoration: InputDecoration(
                  counterText: '',
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  hintText: 'Add your coach',
                  hintStyle:
                      AppText.label.copyWith(color: g.textMuted, fontSize: 15),
                ),
              ),
            ),
            _divider(g),
          ],
          if (pnr != null && pnr.isNotEmpty) ...[
            _infoRow(
              g,
              icon: Icons.confirmation_number_rounded,
              label: 'PNR',
              child: Text(
                pnr,
                style: AppText.label.copyWith(
                  color: g.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            _divider(g),
          ],
          _infoRow(
            g,
            icon: Icons.location_on_rounded,
            label: 'LOCATION',
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _location.label,
                    style: AppText.label.copyWith(
                      color: _location is SosLocationUnavailable
                          ? g.textMuted
                          : g.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (_locating)
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.8,
                      color: g.textMuted,
                    ),
                  )
                else
                  _locationAction(g),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Retry, or the one place location permission is asked for in this flow —
  /// and only ever from a tap. The sheet never raises the OS prompt on open.
  Widget _locationAction(GlassTheme g) {
    final location = _location;
    final needsPermission =
        location is SosLocationUnavailable && location.needsPermission;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Haptics.tap();
        _resolveLocation(requestPermission: needsPermission);
      },
      child: Padding(
        padding: const EdgeInsets.only(left: 8),
        child: Text(
          needsPermission ? 'Enable' : 'Refresh',
          style: AppText.label.copyWith(
            color: GlassTheme.accentViolet,
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _infoRow(
    GlassTheme g, {
    required IconData icon,
    required String label,
    required Widget child,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 17, color: g.textMuted),
          const SizedBox(width: 12),
          SizedBox(
            width: 66,
            child: Text(
              label,
              style: AppText.overline.copyWith(
                color: g.textMuted,
                fontSize: 9.5,
                letterSpacing: 1.4,
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }

  Widget _divider(GlassTheme g) => Divider(
        height: 1,
        thickness: 1,
        indent: 14,
        endIndent: 14,
        color: g.border.withValues(alpha: 0.18),
      );

  /// A deliberately large, unmistakable tap target. 78dp tall against the 48dp
  /// minimum: this is the control someone reaches for while a train is moving.
  Widget _callButton(GlassTheme g, SosHelpline line) {
    return Semantics(
      button: true,
      label: '${line.title}. ${line.subtitle}. Opens your dialer.',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _call(line),
        child: Container(
          height: 78,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            color: g.statusRed,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: g.statusRed.withValues(alpha: 0.34),
                blurRadius: 20,
                spreadRadius: -4,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.call_rounded,
                    size: 20, color: Colors.white),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      line.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.1,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      line.subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.88),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The text action, sized down from the call buttons because reaching a human
  /// on a helpline is the more useful thing in an actual emergency.
  ///
  /// One row per saved contact. With a single contact — the common case — that is
  /// exactly the "Text my emergency contact" button asked for; with two or three
  /// it stays one tap each instead of adding a picker in front of them.
  List<Widget> _textActions(
    GlassTheme g,
    List<EmergencyContact> contacts,
    String? pnr,
  ) {
    if (contacts.isEmpty) {
      return [
        _secondaryButton(
          g,
          icon: Icons.person_add_alt_rounded,
          title: 'Add an emergency contact',
          subtitle: 'Settings › Emergency Contact · stored on this device',
          onTap: _addContact,
        ),
      ];
    }

    final single = contacts.length == 1;
    return [
      for (int i = 0; i < contacts.length; i++) ...[
        if (i > 0) const SizedBox(height: 10),
        _secondaryButton(
          g,
          icon: Icons.sms_rounded,
          title: single
              ? 'Text my emergency contact'
              : 'Text ${contacts[i].displayLabel}',
          subtitle: single
              ? '${contacts[i].displayLabel} · ${contacts[i].maskedNumber}'
              : contacts[i].maskedNumber,
          onTap: () => _text(contacts[i], pnr),
        ),
      ],
    ];
  }

  Widget _secondaryButton(
    GlassTheme g, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      label: '$title. $subtitle',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: g.fill,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: g.border.withValues(alpha: 0.28)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: g.textSecondary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppText.label.copyWith(
                        color: g.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          AppText.label.copyWith(color: g.textMuted, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 18, color: g.textMuted),
            ],
          ),
        ),
      ),
    );
  }

  Widget _noticeRow(GlassTheme g) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline_rounded, size: 15, color: g.statusRed),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _notice!,
            style: AppText.label
                .copyWith(color: g.statusRed, fontSize: 12, height: 1.4),
          ),
        ),
      ],
    );
  }
}
