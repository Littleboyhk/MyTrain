import 'package:flutter/material.dart';

/// Installs a sane app-wide [DefaultTextStyle], replacing the one `MaterialApp`
/// provides by default.
///
/// WHY THIS EXISTS
/// ---------------
/// `MaterialApp` deliberately installs an ugly fallback as the root
/// `DefaultTextStyle` to nudge developers into putting text inside a `Material`
/// (Flutter's own comment: "consider putting your text in a Material"):
///
/// ```dart
/// const TextStyle _errorTextStyle = TextStyle(
///   color: Color(0xD0FF0000), fontFamily: 'monospace', fontSize: 48.0,
///   fontWeight: FontWeight.w900,
///   decoration: TextDecoration.underline,
///   decorationColor: Color(0xFFFFFF00),
///   decorationStyle: TextDecorationStyle.double,
/// );
/// ```
///
/// Text that sets its own colour/size/weight — which is most of this app —
/// overrides those three fields but NOT `decoration`, so the yellow double
/// underline survives the merge and shows up as a highlighter-pen line under
/// otherwise perfectly styled text. It is not an error state, just an
/// inherited decoration.
///
/// It bites wherever text renders outside a `Material`, which in this app means:
///   * `showCupertinoModalPopup` sheets (unlike `showModalBottomSheet`,
///     Cupertino popups insert no Material) — the "Are you on this train?"
///     prompt, the coach/alarm sheets, the home menu
///   * `OverlayEntry` toasts
///   * any custom glass surface used without a Material ancestor
///
/// Placed ABOVE the app's Navigator (from `MaterialApp.builder`), so every
/// route, popup and overlay inherits it. `Material` still installs its own
/// `DefaultTextStyle` further down, so normal screens are unaffected.
class AppTextDefaults extends StatelessWidget {
  const AppTextDefaults({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).textTheme.bodyMedium ?? const TextStyle();
    return DefaultTextStyle(
      style: base.copyWith(
        // The theme's bodyMedium carries no explicit size in this app; pin one
        // so inherited text is 14px rather than the fallback's 48px.
        fontSize: base.fontSize ?? 14,
        // The actual fix.
        decoration: TextDecoration.none,
      ),
      child: child,
    );
  }
}
