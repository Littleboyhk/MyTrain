/// Small, dependency-free formatting helpers (avoids pulling in `intl`).
class Fmt {
  const Fmt._();

  /// Render clock times as `5:05 PM` instead of `17:05`.
  ///
  /// A static mutable, set from [AppSettingsController] as the preference loads
  /// and whenever it changes. This mirrors what `main.dart` already does with
  /// `AppColors.palette`, and for the same reason: [hhmm] is called from dozens
  /// of widgets and painters that have no `BuildContext` to read a provider
  /// from, so threading it through every call site would be a large change for
  /// no benefit.
  ///
  /// Anything that renders a time and should react live must be rebuilt by
  /// watching `appSettingsProvider` — the flag alone does not trigger a rebuild.
  static bool use12HourClock = true;

  /// Clock time, honouring [use12HourClock]. `17:05` or `5:05 PM`.
  static String hhmm(DateTime t) =>
      use12HourClock ? _h12(t) : _h24(t);

  static String _h24(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static String _h12(DateTime t) {
    // Midnight and noon both map to 12, not 0.
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final suffix = t.hour < 12 ? 'AM' : 'PM';
    return '$h:${t.minute.toString().padLeft(2, '0')} $suffix';
  }

  /// Always 24-hour, regardless of the preference. For places where a fixed
  /// width matters more than the user's format choice.
  static String hhmm24(DateTime t) => _h24(t);

  /// A station name in Title Case, for display.
  ///
  /// Both upstream feeds hand back SHOUTING NAMES — `ADONI`, `WADI JN.`,
  /// `MANTHRALAYAM RD` — because that is how the railway timetable data is
  /// published. Rendered raw they are noticeably wider than the same text in
  /// mixed case (capitals have no descenders and near-uniform advance widths), so
  /// on a narrow phone they were the first thing to hit the ellipsis in the
  /// timeline's centre column.
  ///
  /// Deliberately only a case change. No abbreviation expansion — turning `JN.`
  /// into `Junction` means inventing text the feed did not send, and getting it
  /// wrong on an unfamiliar suffix is worse than a slightly terse label.
  ///
  /// A word that already contains a lowercase letter is passed through untouched,
  /// so a feed that returns properly-cased names is never mangled.
  static String stationTitle(String raw) {
    if (raw.isEmpty) return raw;

    // Split on spaces but keep them, so the original spacing survives.
    return raw.split(' ').map((word) {
      if (word.isEmpty) return word;
      // Already mixed case → the source knows what it wants.
      if (word != word.toUpperCase()) return word;
      // Title-case each run of letters, so hyphens and periods stay boundaries:
      // 'WADI JN.' -> 'Wadi Jn.', 'H-NIZAMUDDIN' -> 'H-Nizamuddin'.
      return word.replaceAllMapped(
        RegExp(r'[A-Za-z]+'),
        (m) {
          final s = m[0]!;
          return s[0].toUpperCase() + s.substring(1).toLowerCase();
        },
      );
    }).join(' ');
  }

  /// Distance with adaptive precision: one decimal under 100 km, whole
  /// numbers above (keeps the big numeral from getting too wide).
  static String km(double value) {
    if (value >= 100) return value.toStringAsFixed(0);
    return value.toStringAsFixed(1);
  }

  /// Human "updated ..." string for the live position timestamp.
  static String relativeSince(DateTime t) {
    final seconds = DateTime.now().difference(t).inSeconds;
    if (seconds < 5) return 'just now';
    if (seconds < 60) return '${seconds}s ago';
    final minutes = seconds ~/ 60;
    if (minutes < 60) return '${minutes}m ago';
    final hours = minutes ~/ 60;
    return '${hours}h ago';
  }

  /// Short weekday label, e.g. `Mon`.
  static String weekdayShort(DateTime d) {
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return names[(d.weekday - 1) % 7];
  }

  /// Short month label, e.g. `Jul`.
  static String monthShort(DateTime d) {
    const names = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return names[(d.month - 1) % 12];
  }
}
