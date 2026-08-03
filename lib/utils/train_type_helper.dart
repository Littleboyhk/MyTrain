/// Shared helper for consistent train-type inference across data providers.
class TrainTypeHelper {
  TrainTypeHelper._();

  /// Infer standardized train type name from train [name] and optional [rawType].
  static String inferType(String name, [String? rawType]) {
    final lowerName = name.toLowerCase();
    final lowerType = (rawType ?? '').toLowerCase();
    final combined = '$lowerName $lowerType';

    if (combined.contains('rajdhani')) return 'Rajdhani';
    if (combined.contains('shatabdi') && !combined.contains('jan shatabdi')) {
      return 'Shatabdi';
    }
    if (combined.contains('vande bharat')) return 'Vande Bharat';
    if (combined.contains('duronto')) return 'Duronto';
    if (combined.contains('humsafar')) return 'Humsafar';
    if (combined.contains('garib rath')) return 'Garib Rath';
    if (combined.contains('jan shatabdi')) return 'Jan Shatabdi';
    if (combined.contains('tejas')) return 'Tejas';
    if (combined.contains('intercity')) return 'Intercity';
    if (combined.contains('superfast') ||
        lowerName.contains(' sf ') ||
        lowerName.endsWith(' sf') ||
        lowerType.contains('superfast') ||
        lowerType.contains('sf')) {
      return 'Superfast';
    }
    if (combined.contains('mail')) return 'Mail';
    if (combined.contains('express') || combined.contains('exp')) {
      return 'Express';
    }
    if (combined.contains('memu')) return 'MEMU';
    if (combined.contains('emu')) return 'EMU';
    if (combined.contains('passenger') || combined.contains('pass')) {
      return 'Passenger';
    }

    if (rawType != null && rawType.trim().isNotEmpty) {
      return rawType.trim();
    }

    return 'Express';
  }
}
