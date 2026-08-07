import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'language_controller.dart' show sharedPreferencesProvider;

/// The user's personal emergency contacts, for the SOS flow's "text my
/// emergency contact" action.
///
/// 100% LOCAL. These numbers are the most sensitive thing the app stores, and
/// they never leave the device: no Supabase table, no edge function, no sync, no
/// auth. Storage is the same [SharedPreferences] instance every other preference
/// uses (injected via `sharedPreferencesProvider`), so a reinstall clears them
/// along with everything else.
///
/// The list is capped at [kMaxEmergencyContacts]. That is a usability cap, not a
/// technical one — under stress, a wall of numbers to choose between is worse
/// than two or three.
const int kMaxEmergencyContacts = 3;

/// Storage key. Versioned so a future schema change can migrate rather than
/// silently reinterpret old rows.
const String kEmergencyContactsKey = 'emergency_contacts_v1';

/// A single stored contact.
@immutable
class EmergencyContact {
  const EmergencyContact({required this.number, this.label = ''});

  /// The number as the user typed it, e.g. `+91 98765 43210`. Kept verbatim so
  /// the Settings list shows it back the way they wrote it; [dialNumber] is the
  /// machine-readable form.
  final String number;

  /// Optional human label ("Mum", "Ravi"). May be empty.
  final String label;

  /// `+`/digits only — what goes into a `tel:` or `sms:` URI.
  ///
  /// A dialer will happily accept spaces and dashes, but stripping them here
  /// means the value can never break URI parsing and that duplicate detection
  /// compares like with like.
  String get dialNumber => sanitizeNumber(number);

  /// What to call this contact in UI when it has no label.
  String get displayLabel => label.trim().isEmpty ? 'Emergency contact' : label.trim();

  /// `+91 ••••• 3210` — enough to recognise, not enough to read off a screen
  /// someone else is looking at. Mirrors `SettingsScreen._maskPhone`.
  String get maskedNumber {
    final digits = dialNumber.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 4) return dialNumber;
    final tail = digits.substring(digits.length - 4);
    final prefix = dialNumber.startsWith('+') && digits.length > 10
        ? '+${digits.substring(0, digits.length - 10)} '
        : '';
    return '$prefix••••• $tail';
  }

  EmergencyContact copyWith({String? number, String? label}) => EmergencyContact(
        number: number ?? this.number,
        label: label ?? this.label,
      );

  Map<String, dynamic> toJson() => {'number': number, 'label': label};

  static EmergencyContact? fromJson(Map<String, dynamic> map) {
    final number = map['number']?.toString() ?? '';
    if (sanitizeNumber(number).isEmpty) return null;
    return EmergencyContact(number: number, label: map['label']?.toString() ?? '');
  }

  /// Keeps digits, plus a single leading `+`.
  static String sanitizeNumber(String raw) {
    final trimmed = raw.trim();
    final digits = trimmed.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return '';
    return trimmed.startsWith('+') ? '+$digits' : digits;
  }

  @override
  bool operator ==(Object other) =>
      other is EmergencyContact && other.number == number && other.label == label;

  @override
  int get hashCode => Object.hash(number, label);

  @override
  String toString() => 'EmergencyContact($displayLabel, $maskedNumber)';
}

/// Why a contact was rejected. `null` from a mutator means it was accepted.
enum EmergencyContactError {
  /// Nothing dialable was typed.
  empty,

  /// Fewer digits than any real number or short code.
  tooShort,

  /// More digits than E.164 allows.
  tooLong,

  /// The same number is already in the list.
  duplicate,

  /// Already holding [kMaxEmergencyContacts].
  full;

  String get message => switch (this) {
        EmergencyContactError.empty => 'Enter a phone number.',
        EmergencyContactError.tooShort => 'That number looks too short.',
        EmergencyContactError.tooLong => 'That number looks too long.',
        EmergencyContactError.duplicate => 'That number is already saved.',
        EmergencyContactError.full =>
          'You can save up to $kMaxEmergencyContacts contacts.',
      };
}

final emergencyContactsProvider =
    NotifierProvider<EmergencyContactsController, List<EmergencyContact>>(
  EmergencyContactsController.new,
);

class EmergencyContactsController extends Notifier<List<EmergencyContact>> {
  SharedPreferences? get _prefs => ref.read(sharedPreferencesProvider);

  @override
  List<EmergencyContact> build() {
    final raw = _prefs?.getStringList(kEmergencyContactsKey);
    if (raw == null || raw.isEmpty) return const [];

    final out = <EmergencyContact>[];
    for (final entry in raw) {
      try {
        final decoded = jsonDecode(entry);
        if (decoded is Map) {
          final parsed = EmergencyContact.fromJson(decoded.cast<String, dynamic>());
          if (parsed != null) out.add(parsed);
        }
      } catch (e) {
        // A single corrupt row must not cost the user their other contacts —
        // this list is the thing an emergency depends on.
        debugPrint('[EmergencyContacts] skipping unreadable entry: $e');
      }
    }
    return List.unmodifiable(out.take(kMaxEmergencyContacts));
  }

  /// Appends a contact. Returns null on success, or why it was rejected.
  EmergencyContactError? add(String number, {String label = ''}) {
    if (state.length >= kMaxEmergencyContacts) return EmergencyContactError.full;
    final problem = validate(number);
    if (problem != null) return problem;

    final candidate = EmergencyContact(number: number.trim(), label: label.trim());
    if (state.any((c) => c.dialNumber == candidate.dialNumber)) {
      return EmergencyContactError.duplicate;
    }

    _commit([...state, candidate]);
    return null;
  }

  /// Replaces the contact at [index]. Returns null on success.
  EmergencyContactError? replaceAt(int index, String number, {String label = ''}) {
    if (index < 0 || index >= state.length) return EmergencyContactError.empty;
    final problem = validate(number);
    if (problem != null) return problem;

    final candidate = EmergencyContact(number: number.trim(), label: label.trim());
    for (int i = 0; i < state.length; i++) {
      if (i != index && state[i].dialNumber == candidate.dialNumber) {
        return EmergencyContactError.duplicate;
      }
    }

    final next = [...state]..[index] = candidate;
    _commit(next);
    return null;
  }

  void removeAt(int index) {
    if (index < 0 || index >= state.length) return;
    _commit([...state]..removeAt(index));
  }

  /// Digit-count sanity only. Deliberately NOT a country-specific format check:
  /// rejecting a number the dialer would have accepted is the worse failure for
  /// this feature.
  static EmergencyContactError? validate(String raw) {
    final sanitized = EmergencyContact.sanitizeNumber(raw);
    final digits = sanitized.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return EmergencyContactError.empty;
    // 3 covers short codes (100, 112, 139); 15 is the E.164 maximum.
    if (digits.length < 3) return EmergencyContactError.tooShort;
    if (digits.length > 15) return EmergencyContactError.tooLong;
    return null;
  }

  void _commit(List<EmergencyContact> next) {
    state = List.unmodifiable(next);
    _prefs?.setStringList(
      kEmergencyContactsKey,
      next.map((c) => jsonEncode(c.toJson())).toList(),
    );
  }
}
