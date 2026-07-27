import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

/// Per-account chat eligibility: the 18+ self-attestation.
///
/// Reads come straight from `chat_users` (RLS restricts the caller to their own
/// row). Writes go through the `chat_attest_age` RPC — the client cannot choose
/// the user id or the timestamp.
class ChatUserStatus {
  const ChatUserStatus({
    required this.exists,
    required this.isAdult,
    this.attestedAt,
  });

  /// A row exists for this account.
  final bool exists;

  /// They attested to being 18 or older. Only `exists && isAdult` opens chat.
  final bool isAdult;

  final DateTime? attestedAt;

  /// Nothing on record — the age step still needs to be shown.
  const ChatUserStatus.absent()
      : exists = false,
        isAdult = false,
        attestedAt = null;

  bool get isEligible => exists && isAdult;

  @override
  String toString() =>
      'ChatUserStatus(exists: $exists, isAdult: $isAdult, at: $attestedAt)';
}

class ChatAccountException implements Exception {
  const ChatAccountException(this.message);
  final String message;

  @override
  String toString() => 'ChatAccountException: $message';
}

class ChatAccountService {
  const ChatAccountService();

  bool get _ready =>
      SupabaseConfig.isConfigured &&
      Supabase.instance.client.auth.currentSession != null;

  /// The caller's attestation record.
  ///
  /// Returns [ChatUserStatus.absent] when there is no session or no row. On a
  /// network/RLS error it also returns absent, which means the age step is shown
  /// again — re-attesting is harmless (the RPC upserts), whereas assuming
  /// eligibility on an error would skip a safety gate.
  Future<ChatUserStatus> fetchMine() async {
    if (!_ready) return const ChatUserStatus.absent();
    try {
      final uid = Supabase.instance.client.auth.currentUser!.id;
      final row = await Supabase.instance.client
          .from('chat_users')
          .select('is_adult, attested_at')
          .eq('user_id', uid)
          .maybeSingle()
          .timeout(const Duration(seconds: 10));

      if (row == null) return const ChatUserStatus.absent();
      return ChatUserStatus(
        exists: true,
        isAdult: row['is_adult'] == true,
        attestedAt: row['attested_at'] == null
            ? null
            : DateTime.tryParse(row['attested_at'].toString()),
      );
    } on TimeoutException {
      debugPrint('[ChatAccount] fetchMine timed out — treating as absent');
      return const ChatUserStatus.absent();
    } catch (e) {
      debugPrint('[ChatAccount] fetchMine failed: $e — treating as absent');
      return const ChatUserStatus.absent();
    }
  }

  /// Record the attestation. Throws on failure so the UI never shows a false
  /// confirmation.
  Future<ChatUserStatus> attestAge({required bool isAdult}) async {
    if (!_ready) {
      throw const ChatAccountException('You need to be signed in first.');
    }
    try {
      final res = await Supabase.instance.client
          .rpc('chat_attest_age', params: {'p_is_adult': isAdult})
          .timeout(const Duration(seconds: 12));

      // The RPC returns a single-row table.
      Map<String, dynamic>? row;
      if (res is List && res.isNotEmpty && res.first is Map) {
        row = (res.first as Map).cast<String, dynamic>();
      } else if (res is Map) {
        row = res.cast<String, dynamic>();
      }

      debugPrint('[ChatAccount] attestation recorded: isAdult=$isAdult');
      return ChatUserStatus(
        exists: true,
        isAdult: row?['is_adult'] == true,
        attestedAt: row?['attested_at'] == null
            ? null
            : DateTime.tryParse(row!['attested_at'].toString()),
      );
    } on TimeoutException {
      throw const ChatAccountException(
        'That took too long. Check your connection and try again.',
      );
    } on PostgrestException catch (e) {
      debugPrint('[ChatAccount] attestAge failed: ${e.code} ${e.message}');
      throw const ChatAccountException(
        'Couldn\'t save that just now. Please try again.',
      );
    } catch (e) {
      debugPrint('[ChatAccount] attestAge failed: $e');
      throw const ChatAccountException(
        'Couldn\'t save that just now. Please try again.',
      );
    }
  }
}

final chatAccountServiceProvider =
    Provider<ChatAccountService>((ref) => const ChatAccountService());

/// True once the user has said they're under 18 during this app run.
///
/// Session-scoped ON PURPOSE: declining must not trigger another prompt the next
/// time they tap "Join chat" in the same session. It resets on app restart, so a
/// mistaken tap isn't permanent.
class ChatDeclinedThisSession extends Notifier<bool> {
  @override
  bool build() => false;

  void markDeclined() => state = true;
}

final chatDeclinedThisSessionProvider =
    NotifierProvider<ChatDeclinedThisSession, bool>(
  ChatDeclinedThisSession.new,
);
