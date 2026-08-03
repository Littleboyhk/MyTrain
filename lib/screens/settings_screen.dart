import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_settings_controller.dart';
import '../data/chat_gate_controller.dart';
import '../data/language_controller.dart';
import '../data/offline/route_cache_store.dart';
import '../data/phone_auth_service.dart';
import '../data/spot_notification_service.dart';
import '../data/theme_controller.dart';
import '../l10n/app_localizations.dart';
import '../services/audio_service.dart';
import '../theme/app_theme.dart';
import '../theme/glass_theme.dart';
import '../theme/motion.dart';
import '../utils/formatters.dart';
import '../utils/haptics.dart';
import '../widgets/glass_container.dart';
import '../widgets/icon_action_button.dart';
import '../widgets/language_picker_sheet.dart';
import '../widgets/mesh_background.dart';
import '../widgets/phone_verification_sheet.dart';

/// App settings — focused on appearance (light / dark / system) and language.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key, this.embedded = false});

  /// When shown as a bottom-dock tab: hide the back button, make the scaffold
  /// transparent so the home mesh shows through, and pad for the floating dock.
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final settings = ref.watch(appSettingsProvider);
    final auth = ref.watch(authUserProvider);
    final user = switch (auth) {
      AsyncData(:final value) => value,
      _ => null,
    };
    final g = context.glass;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          if (!embedded) const Positioned.fill(child: MeshBackground()),
          SafeArea(
            bottom: false,
            child: ListView(
              padding: EdgeInsets.fromLTRB(16, 8, 16, embedded ? 120 : 32),
              children: [
                _header(context),
                const SizedBox(height: 20),
                // TODO(l10n): these strings need keys in lib/l10n/*.arb like the
                // rest of this screen; English literals for now.
                _sectionLabel(context, 'ACCOUNT'),
                const SizedBox(height: 12),
                _accountCard(context, ref),
                const SizedBox(height: 28),
                _sectionLabel(context, 'TIMETABLE & DATA'),
                const SizedBox(height: 12),
                _timetableCard(context, ref),
                const SizedBox(height: 28),
                _sectionLabel(context, L10n.of(context).sectionAppearance),
                const SizedBox(height: 12),
                _themeSelector(context, ref, mode),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    L10n.of(context).appearanceHint,
                    style: AppText.label.copyWith(
                      color: g.textMuted,
                      fontSize: 12.5,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                _sectionLabel(context, L10n.of(context).sectionPersonal),
                const SizedBox(height: 12),
                _personalCard(context, ref, settings),
                const SizedBox(height: 28),
                _sectionLabel(context, L10n.of(context).sectionSpot),
                const SizedBox(height: 12),
                _spotCard(context, ref, settings),
                const SizedBox(height: 28),
                _sectionLabel(context, L10n.of(context).sectionSpeedometer),
                const SizedBox(height: 12),
                _speedometerCard(context, ref, settings),
                const SizedBox(height: 28),
                _sectionLabel(context, L10n.of(context).sectionAlarm),
                const SizedBox(height: 12),
                _alarmCard(context, ref, settings),
                const SizedBox(height: 28),
                _sectionLabel(context, L10n.of(context).sectionAbout),
                const SizedBox(height: 12),
                _aboutCard(context),
                if (user != null) ...[
                  const SizedBox(height: 28),
                  _signOutCard(context, ref),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    final g = context.glass;
    return Row(
      children: [
        if (!embedded) ...[
          IconActionButton(
            icon: Icons.arrow_back_ios_new_rounded,
            iconSize: 18,
            background: false,
            onTap: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 4),
        ],
        Text(
          L10n.of(context).settingsTitle,
          style: AppText.titleStrong.copyWith(
            color: g.textPrimary,
            fontSize: 20,
          ),
        ),
      ],
    );
  }

  Widget _sectionLabel(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Text(
        text,
        style: AppText.overline.copyWith(color: context.glass.textMuted),
      ),
    );
  }

  Widget _themeSelector(BuildContext context, WidgetRef ref, ThemeMode mode) {
    return Row(
      children: [
        _ThemeOption(
          label: L10n.of(context).themeSystem,
          icon: Icons.brightness_auto_rounded,
          selected: mode == ThemeMode.system,
          previewColors: const [Color(0xFF000000), Color(0xFFF4F4F8)],
          previewIcon: GlassTheme.accentViolet,
          onTap: () => _apply(ref, ThemeMode.system),
        ),
        const SizedBox(width: 12),
        _ThemeOption(
          label: L10n.of(context).themeLight,
          icon: Icons.light_mode_rounded,
          selected: mode == ThemeMode.light,
          previewColors: const [Color(0xFFFFFFFF), Color(0xFFEAF1FF)],
          previewIcon: const Color(0xFF14141E),
          onTap: () => _apply(ref, ThemeMode.light),
        ),
        const SizedBox(width: 12),
        _ThemeOption(
          label: L10n.of(context).themeDark,
          icon: Icons.dark_mode_rounded,
          selected: mode == ThemeMode.dark,
          previewColors: const [Color(0xFF000000), Color(0xFF000000)],
          previewIcon: Colors.white,
          onTap: () => _apply(ref, ThemeMode.dark),
        ),
      ],
    );
  }

  void _apply(WidgetRef ref, ThemeMode mode) {
    Haptics.selection();
    ref.read(themeModeProvider.notifier).set(mode);
  }

  /// Brief glass confirmation pill, floated above the dock.
  void _toast(BuildContext context, String message) {
    final g = context.glass;
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => Positioned(
        left: 24,
        right: 24,
        bottom: 130,
        child: IgnorePointer(
          child: Center(
            child: GlassContainer(
              radius: 16,
              blurSigma: 22,
              strong: true,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: AppText.label.copyWith(
                  color: g.textPrimary,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(entry);
    Future.delayed(const Duration(milliseconds: 1900), entry.remove);
  }

  /// Color-coded full-width banner toast for timetable status updates.
  void _statusToast(
    BuildContext context, {
    required String message,
    required Color backgroundColor,
    required Color textColor,
  }) {
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: Material(
          type: MaterialType.transparency,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: backgroundColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.30),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Text(
              message,
              style: TextStyle(
                color: textColor,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(entry);
    Future.delayed(const Duration(milliseconds: 2200), entry.remove);
  }

  // ---------------------------------------------------------------------------
  // Personal
  // ---------------------------------------------------------------------------

  /// Language, clock format, and the inside-train prompt.
  Widget _personalCard(
    BuildContext context,
    WidgetRef ref,
    AppSettings settings,
  ) {
    return GlassContainer(
      radius: 22,
      blurSigma: 20,
      strong: true,
      padding: const EdgeInsets.all(6),
      child: Column(
        children: [
          _languageRow(context, ref),
          _divider(context),
          _switchRow(
            context,
            icon: Icons.schedule_rounded,
            title: L10n.of(context).timeSettings,
            subtitle: L10n.of(context).timeSettingsHint,
            value: settings.use12HourClock,
            onChanged: (v) {
              Haptics.selection();
              ref.read(appSettingsProvider.notifier).setUse12HourClock(v);
            },
            // Live proof the switch did something, in the format just chosen.
            trailingNote: Fmt.hhmm(DateTime(2026, 1, 1, 16, 25)),
          ),
          _divider(context),
          _switchRow(
            context,
            icon: Icons.train_rounded,
            title: L10n.of(context).insideTrainSetting,
            subtitle: L10n.of(context).insideTrainSettingHint,
            value: settings.suggestInsideTrain,
            onChanged: (v) {
              Haptics.selection();
              ref.read(appSettingsProvider.notifier).setSuggestInsideTrain(v);
            },
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Timetable & Cache
  // ---------------------------------------------------------------------------

  static bool _isCheckingTimetable = false;

  Widget _timetableCard(BuildContext context, WidgetRef ref) {
    final g = context.glass;
    final store = ref.watch(offlineRouteStoreProvider);
    final ageLabel = store.getTimetableUpdateAge();

    return GlassContainer(
      radius: 22,
      blurSigma: 20,
      strong: true,
      padding: const EdgeInsets.all(6),
      child: _accountRow(
        context,
        icon: Icons.system_update_alt_rounded,
        title: 'Update Timetable',
        subtitle: 'Sync latest train schedules and station routes',
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              ageLabel,
              style: AppText.label.copyWith(
                color: g.textMuted,
                fontSize: 12.5,
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right_rounded, size: 20, color: g.textMuted),
          ],
        ),
        onTap: () async {
          if (_isCheckingTimetable) return;
          _isCheckingTimetable = true;
          Haptics.tap();
          _statusToast(
            context,
            message: 'Checking for new schedule...',
            backgroundColor: const Color(0xFF2E7D32),
            textColor: Colors.white,
          );

          final hasUpdates = await store.checkTimetableUpdate();
          _isCheckingTimetable = false;

          if (context.mounted) {
            ref.invalidate(offlineRouteStoreProvider);
            _statusToast(
              context,
              message: hasUpdates
                  ? 'Timetable updated successfully!'
                  : 'No new schedules available!',
              backgroundColor: hasUpdates
                  ? const Color(0xFF2E7D32)
                  : const Color(0xFFEF6C00),
              textColor: Colors.white,
            );
          }
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Spot
  // ---------------------------------------------------------------------------

  Widget _spotCard(BuildContext context, WidgetRef ref, AppSettings settings) {
    final supported = AppSettingsController.spotNotificationsSupported;
    return GlassContainer(
      radius: 22,
      blurSigma: 20,
      strong: true,
      padding: const EdgeInsets.all(6),
      child: _switchRow(
        context,
        icon: Icons.notifications_active_rounded,
        title: L10n.of(context).spotNotifications,
        subtitle: supported
            ? L10n.of(context).spotNotificationsHint
            : L10n.of(context).spotNotificationsUnsupported,
        value: supported && settings.spotNotifications,
        enabled: supported,
        onChanged: (v) async {
          Haptics.selection();
          ref.read(appSettingsProvider.notifier).setSpotNotifications(v);
          if (v) {
            final ok = await ref
                .read(spotNotificationServiceProvider)
                .requestPermission();
            if (context.mounted && ok) {
              _toast(context, 'Spot notifications enabled');
            }
          } else {
            if (context.mounted) {
              _toast(context, 'Spot notifications disabled');
            }
          }
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Speedometer
  // ---------------------------------------------------------------------------

  Widget _speedometerCard(
    BuildContext context,
    WidgetRef ref,
    AppSettings settings,
  ) {
    return GlassContainer(
      radius: 22,
      blurSigma: 20,
      strong: true,
      padding: const EdgeInsets.all(6),
      child: Column(
        children: [
          _switchRow(
            context,
            icon: Icons.speed_rounded,
            title: L10n.of(context).speedometerSetting,
            subtitle: L10n.of(context).speedometerSettingHint,
            value: settings.speedometerEnabled,
            onChanged: (v) {
              Haptics.selection();
              ref.read(appSettingsProvider.notifier).setSpeedometerEnabled(v);
            },
          ),
          if (settings.speedometerEnabled) ...[
            _divider(context),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      size: 15, color: context.glass.textMuted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      L10n.of(context).speedometerRequiresGps,
                      style: AppText.label.copyWith(
                        color: context.glass.textMuted,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Alarm
  // ---------------------------------------------------------------------------

  Widget _alarmCard(BuildContext context, WidgetRef ref, AppSettings settings) {
    final g = context.glass;
    return GlassContainer(
      radius: 22,
      blurSigma: 20,
      strong: true,
      padding: const EdgeInsets.all(6),
      child: _accountRow(
        context,
        icon: Icons.music_note_rounded,
        title: L10n.of(context).alarmTone,
        subtitle: settings.alarmTone.label,
        trailing:
            Icon(Icons.chevron_right_rounded, size: 20, color: g.textMuted),
        onTap: () async {
          Haptics.tap();
          final picked = await _pickAlarmTone(context, settings.alarmTone);
          if (picked == null || !context.mounted) return;
          ref.read(appSettingsProvider.notifier).setAlarmTone(picked);
          _toast(context, L10n.of(context).alarmToneChanged(picked.label));
        },
      ),
    );
  }

  Future<AlarmTone?> _pickAlarmTone(
    BuildContext context,
    AlarmTone current,
  ) {
    final g = context.glass;
    return showModalBottomSheet<AlarmTone>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 12,
          right: 12,
          bottom: 12 + MediaQuery.of(ctx).viewPadding.bottom,
        ),
        child: GlassContainer(
          radius: 28,
          blurSigma: 24,
          strong: true,
          glow: true,
          padding: const EdgeInsets.fromLTRB(18, 18, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                L10n.of(ctx).alarmTone,
                style: AppText.titleStrong
                    .copyWith(color: g.textPrimary, fontSize: 19),
              ),
              const SizedBox(height: 6),
              Text(
                L10n.of(ctx).alarmTonePlaybackNote,
                style: AppText.label
                    .copyWith(color: g.textMuted, fontSize: 12.5, height: 1.4),
              ),
              const SizedBox(height: 10),
              for (final tone in AlarmTone.values)
                Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () {
                      AudioService.instance.playTone(tone);
                      Navigator.of(ctx).pop(tone);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 13),
                      child: Row(
                        children: [
                          Icon(
                            tone == current
                                ? Icons.radio_button_checked_rounded
                                : Icons.radio_button_unchecked_rounded,
                            size: 20,
                            color: tone == current
                                ? GlassTheme.accentViolet
                                : g.textMuted,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            tone.label,
                            style: AppText.label.copyWith(
                              color: g.textPrimary,
                              fontSize: 14.5,
                              fontWeight: tone == current
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }



  // ---------------------------------------------------------------------------
  // Shared rows
  // ---------------------------------------------------------------------------

  /// A labelled switch row. [enabled] false greys it out and ignores taps, for
  /// settings the platform cannot honour.
  Widget _switchRow(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool enabled = true,
    String? trailingNote,
  }) {
    final g = context.glass;
    final tint = enabled ? GlassTheme.accentViolet : g.textMuted;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          GlassContainer(
            radius: 12,
            blurSigma: 0,
            strong: true,
            padding: const EdgeInsets.all(8),
            child: Icon(icon, size: 18, color: tint),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppText.label.copyWith(
                    color: enabled ? g.textPrimary : g.textMuted,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: AppText.label.copyWith(
                    color: g.textMuted,
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          if (trailingNote != null) ...[
            const SizedBox(width: 8),
            Text(
              trailingNote,
              style: AppText.label.copyWith(
                color: g.textSecondary,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(width: 6),
          Switch.adaptive(
            value: value,
            onChanged: enabled ? onChanged : null,
            activeThumbColor: Colors.white,
            activeTrackColor: g.statusGreen,
          ),
        ],
      ),
    );
  }

  /// Opens the same picker used on first launch, so the choice can be changed
  /// any time. Changing it rebuilds the whole app in the selected locale.
  Widget _languageRow(BuildContext context, WidgetRef ref) {
    final g = context.glass;
    final lang = ref.watch(languageProvider);
    return
      // Material+InkWell so the ripple is clipped to the card's rounded corners.
      Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () async {
            Haptics.tap();
            final picked = await showLanguagePickerSheet(context);
            if (picked == null || !context.mounted) return;
            // Read the message AFTER the locale switch so the confirmation
            // itself appears in the newly selected language.
            _toast(context, L10n.of(context).languageChanged(picked.endonym));
          },
          child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              GlassContainer(
                radius: 12,
                blurSigma: 0,
                strong: true,
                padding: const EdgeInsets.all(8),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: Center(
                    child: Text(
                      lang.script,
                      style: const TextStyle(
                        color: GlassTheme.accentViolet,
                        fontSize: 15,
                        height: 1.05,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      L10n.of(context).language,
                      style: AppText.label.copyWith(
                        color: g.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      lang.code == 'en'
                          ? lang.endonym
                          : '${lang.endonym} · ${lang.english}',
                      style: AppText.label.copyWith(
                        color: g.textMuted,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 20, color: g.textMuted),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Account
  // ---------------------------------------------------------------------------

  /// Sign in / sign out. Driven by [authUserProvider], so the card flips as soon
  /// as a session appears or disappears — no manual refresh.
  Widget _accountCard(BuildContext context, WidgetRef ref) {
    final g = context.glass;
    final auth = ref.watch(authUserProvider);
    final configured = ref.read(phoneAuthServiceProvider).isConfigured;

    if (!configured) {
      return GlassContainer(
        radius: 22,
        blurSigma: 20,
        strong: true,
        padding: const EdgeInsets.all(6),
        child: _accountRow(
          context,
          icon: Icons.cloud_off_rounded,
          title: 'Sign-in unavailable',
          subtitle: 'This build has no backend configured.',
        ),
      );
    }

    // Pattern match rather than `valueOrNull`, which this Riverpod version
    // doesn't expose on AsyncValue.
    final user = switch (auth) {
      AsyncData(:final value) => value,
      _ => null,
    };
    final loading = auth.isLoading;

    return GlassContainer(
      radius: 22,
      blurSigma: 20,
      strong: true,
      padding: const EdgeInsets.all(6),
      child: Column(
        children: [
          if (loading)
            _accountRow(
              context,
              icon: Icons.person_outline_rounded,
              title: 'Account',
              subtitle: 'Checking…',
            )
          else if (user == null)
            _accountRow(
              context,
              icon: Icons.login_rounded,
              title: 'Sign in',
              subtitle: 'Verify your phone to chat with co-passengers',
              trailing:
                  Icon(Icons.chevron_right_rounded, size: 20, color: g.textMuted),
              onTap: () async {
                Haptics.tap();
                final ok = await showAccountLoginSheet(context, ref);
                if (!ok || !context.mounted) return;
                _toast(context, 'Signed in');
              },
            )
          else
            _accountRow(
              context,
              icon: Icons.verified_user_rounded,
              title: _maskPhone(user.phone),
              subtitle: 'Phone verified',
            ),
        ],
      ),
    );
  }

  Widget _signOutCard(BuildContext context, WidgetRef ref) {
    return GlassContainer(
      radius: 22,
      blurSigma: 20,
      strong: true,
      padding: const EdgeInsets.all(6),
      child: _accountRow(
        context,
        icon: Icons.logout_rounded,
        title: 'Sign out',
        subtitle: 'You\'ll need to verify your number again',
        destructive: true,
        onTap: () => _signOut(context, ref),
      ),
    );
  }

  /// `+91 ••••• 6217` — enough to recognise the account, not enough to expose
  /// the number on a shared screen.
  static String _maskPhone(String? raw) {
    final digits = (raw ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.length < 4) return 'Signed in';
    final tail = digits.substring(digits.length - 4);
    return '+91 ••••• $tail';
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    Haptics.tap();
    final confirmed = await _confirmSignOut(context);
    if (confirmed != true || !context.mounted) return;

    // Stop journey verification first: it samples GPS and posts to endpoints
    // that need a session, so it must not keep running after sign-out.
    ref.read(chatGateProvider.notifier).stop();
    await ref.read(phoneAuthServiceProvider).signOut();
    if (!context.mounted) return;
    _toast(context, 'Signed out');
  }

  /// Glass confirm sheet. Both choices are the same size — cancelling is exactly
  /// as easy as confirming.
  Future<bool?> _confirmSignOut(BuildContext context) {
    final g = context.glass;
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 12,
          right: 12,
          bottom: 12 + MediaQuery.of(ctx).viewPadding.bottom,
        ),
        child: GlassContainer(
          radius: 28,
          blurSigma: 24,
          strong: true,
          glow: true,
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Sign out?',
                style: AppText.titleStrong
                    .copyWith(color: g.textPrimary, fontSize: 19),
              ),
              const SizedBox(height: 6),
              Text(
                'Your chat access ends until you verify your number again.',
                style: AppText.label.copyWith(
                  color: g.textMuted,
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _sheetButton(
                      context,
                      label: 'Cancel',
                      onTap: () => Navigator.of(ctx).pop(false),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _sheetButton(
                      context,
                      label: 'Sign out',
                      destructive: true,
                      onTap: () => Navigator.of(ctx).pop(true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sheetButton(
    BuildContext context, {
    required String label,
    required VoidCallback onTap,
    bool destructive = false,
  }) {
    final g = context.glass;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 50,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: destructive
              ? g.statusRed.withValues(alpha: 0.16)
              : g.fill,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: destructive
                ? g.statusRed.withValues(alpha: 0.5)
                : g.border.withValues(alpha: 0.3),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: destructive ? g.statusRed : g.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _accountRow(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailing,
    VoidCallback? onTap,
    bool destructive = false,
  }) {
    final g = context.glass;
    final tint = destructive ? g.statusRed : GlassTheme.accentViolet;

    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Row(
        children: [
          GlassContainer(
            radius: 12,
            blurSigma: 0,
            strong: true,
            padding: const EdgeInsets.all(8),
            child: Icon(icon, size: 18, color: tint),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppText.label.copyWith(
                    color: destructive ? g.statusRed : g.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: AppText.label
                      .copyWith(color: g.textMuted, fontSize: 12.5),
                ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );

    if (onTap == null) return row;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: row,
      ),
    );
  }

  Widget _aboutCard(BuildContext context) {
    return GlassContainer(
      radius: 22,
      blurSigma: 20,
      strong: true,
      padding: const EdgeInsets.all(6),
      child: Column(
        children: [
          _aboutRow(context, Icons.train_rounded, L10n.of(context).appName, L10n.of(context).aboutVersion('1.0.0')),
          _divider(context),
          _aboutRow(context, Icons.hub_rounded, L10n.of(context).aboutCoverage, L10n.of(context).aboutCoverageValue('8,989')),
          _divider(context),
          _aboutRow(
            context,
            Icons.dataset_rounded,
            L10n.of(context).aboutStationData,
            'DataMeet — Indian Railways (open data)',
          ),
        ],
      ),
    );
  }

  Widget _aboutRow(
    BuildContext context,
    IconData icon,
    String title,
    String value,
  ) {
    final g = context.glass;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Row(
        children: [
          GlassContainer(
            radius: 12,
            blurSigma: 0,
            strong: true,
            padding: const EdgeInsets.all(8),
            child: Icon(icon, size: 18, color: GlassTheme.accentViolet),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppText.label.copyWith(
                    color: g.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: AppText.label.copyWith(
                    color: g.textMuted,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Container(
          height: 1,
          color: context.glass.border.withValues(alpha: 0.15),
        ),
      );
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.label,
    required this.icon,
    required this.selected,
    required this.previewColors,
    required this.previewIcon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;

  final List<Color> previewColors;
  final Color previewIcon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final g = context.glass;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          children: [
            AnimatedContainer(
              duration: Motion.fast,
              curve: Motion.standard,
              height: 68,
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: previewColors,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: selected ? GlassTheme.accentViolet : g.border,
                  width: selected ? 2 : 1,
                ),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: GlassTheme.accentViolet.withValues(alpha: 0.35),
                          blurRadius: 18,
                          spreadRadius: -2,
                        ),
                      ]
                    : const [],
              ),
              child: Center(child: Icon(icon, size: 24, color: previewIcon)),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                color: selected ? g.textPrimary : g.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
