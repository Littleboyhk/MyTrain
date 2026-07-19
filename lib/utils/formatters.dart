/// Small, dependency-free formatting helpers (avoids pulling in `intl`).
class Fmt {
  const Fmt._();

  /// 24-hour clock, e.g. `17:05`.
  static String hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

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
