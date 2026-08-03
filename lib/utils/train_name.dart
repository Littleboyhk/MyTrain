/// Expanding Indian Railways' abbreviated train names into readable ones.
///
/// WHAT THIS IS, PRECISELY. Providers send names like `YPR TVCN GR EXP`. That is
/// the whole value RailKit returns and the whole value on the ticket — there is no
/// longer form to fetch. This module produces a DERIVED long form. It is not the
/// railway's name for the train, and callers must not present it as one; the
/// provider's own string stays the primary label.
///
/// WHY IT IS SAFE TO DERIVE AT ALL. Only two things happen here, and both are
/// closed substitutions rather than inference:
///
///  1. A fixed table of standard suffix abbreviations — `EXP` -> `Express`,
///     `GR` -> `Garib Rath`, and so on. These are conventional and unambiguous.
///  2. Leading station codes, and ONLY when every one of them resolves through the
///     caller's own station catalog.
///
/// Rule 2 is all-or-nothing on purpose. `YPR` resolves to Yesvantpur Jn but `TVCN`
/// is absent from the catalog, and expanding one but not the other produces
/// "Yesvantpur Jn TVCN Garib Rath Express" — worse than leaving both alone,
/// because it reads as a name someone typed badly rather than as a code.
library;

/// Standard suffix abbreviations, longest key first at match time.
///
/// Deliberately conservative. Anything not listed is left exactly as received,
/// because a wrong expansion is worse than none — this is a train someone is
/// trying to board.
const Map<String, String> kTrainNameAbbreviations = {
  'GR': 'Garib Rath',
  'SF': 'Superfast',
  'EXP': 'Express',
  'EXPRESS': 'Express',
  'SPL': 'Special',
  'SPECIAL': 'Special',
  'PASS': 'Passenger',
  'MEMU': 'MEMU',
  'DEMU': 'DEMU',
  'JANSHATABDI': 'Jan Shatabdi',
  'RAJ': 'Rajdhani',
  'RAJDHANI': 'Rajdhani',
  'SHTBDI': 'Shatabdi',
  'DURONTO': 'Duronto',
  'HUMSAFAR': 'Humsafar',
  'ANTYODAYA': 'Antyodaya',
  'TEJAS': 'Tejas',
  'VANDE': 'Vande Bharat',
  'INTERCITY': 'Intercity',
  'MAIL': 'Mail',
  'DD': 'Double Decker',
};

/// True when [token] looks like a station code rather than a word.
///
/// Station codes are 2–5 uppercase letters. Requiring that shape keeps real words
/// in the name from being fed to the catalog, where a coincidental hit would
/// rewrite part of a name that was already readable.
bool _looksLikeStationCode(String token) =>
    RegExp(r'^[A-Z]{2,5}$').hasMatch(token) &&
    !kTrainNameAbbreviations.containsKey(token);

/// A readable long form of [raw], or null when nothing could be expanded.
///
/// Returning null rather than the input lets callers omit the secondary line
/// entirely instead of printing the same string twice.
///
/// [station] resolves a code to a name and should return null for unknown codes.
/// Omit it to expand abbreviations only.
String? expandTrainName(String raw, {String? Function(String code)? station}) {
  final tokens = raw
      .trim()
      .split(RegExp(r'\s+'))
      .where((t) => t.isNotEmpty)
      .toList();
  if (tokens.isEmpty) return null;

  // The leading run of station-code-shaped tokens. `YPR TVCN GR EXP` -> [YPR,
  // TVCN]; a name that starts with a word has an empty run and is left alone.
  final codeRun = <String>[];
  for (final t in tokens) {
    if (!_looksLikeStationCode(t.toUpperCase())) break;
    codeRun.add(t.toUpperCase());
  }

  // All-or-nothing, per the note above.
  var names = <String>[];
  if (station != null && codeRun.isNotEmpty) {
    final resolved = <String>[];
    for (final c in codeRun) {
      final n = station(c);
      if (n == null || n.trim().isEmpty) {
        resolved.clear();
        break;
      }
      resolved.add(n.trim());
    }
    names = resolved;
  }

  final out = <String>[];
  if (names.isNotEmpty) {
    // An en dash reads as "between these two places", which is what the code pair
    // means, and distinguishes the derived form at a glance.
    out.add(names.join(' – '));
  } else {
    out.addAll(codeRun);
  }

  var changed = names.isNotEmpty;
  for (final t in tokens.skip(codeRun.length)) {
    final expanded = kTrainNameAbbreviations[t.toUpperCase()];
    if (expanded != null && expanded.toUpperCase() != t.toUpperCase()) {
      changed = true;
      out.add(expanded);
    } else {
      out.add(expanded ?? t);
    }
  }

  if (!changed) return null;
  final joined = out.join(' ').replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  return joined.isEmpty || joined.toUpperCase() == raw.trim().toUpperCase()
      ? null
      : joined;
}
