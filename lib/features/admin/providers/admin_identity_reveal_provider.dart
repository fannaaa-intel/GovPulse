import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Anonymous submitter reveal — client side of anonymous_reveal.sql
//
//  Anonymous reports/suggestions/feedback keep their real user_id server-side
//  but withhold the identity. The ONLY sanctioned way to surface it is the
//  `reveal-identity` edge function: full admin (role 1) + password + a code
//  emailed to the admin + a reason, all audited, locked after 5 failures.
//  This file exposes:
//    • currentAdminIsFullAdminProvider — gates the "Reveal" button to role 1.
//    • sendRevealCode()                — step 1: password → emailed code.
//    • revealSubmitterIdentity()       — step 2: code → identity.
// ════════════════════════════════════════════════════════════════════════════

/// True only when the signed-in console user is a FULL admin (role_id = 1) —
/// the single tier permitted to reveal an anonymous submitter. Staff (role 2)
/// resolve to false and never see the reveal affordance. The server RPC enforces
/// this again; this is just so staff aren't shown a button they can't use.
final currentAdminIsFullAdminProvider = FutureProvider<bool>((ref) async {
  final db = Supabase.instance.client;
  final uid = db.auth.currentUser?.id;
  if (uid == null) return false;
  final row = await db
      .from('user_roles')
      .select('role_id')
      .eq('user_id', uid)
      .maybeSingle();
  return (row?['role_id'] as int?) == 1;
});

/// Which submission kind an anonymous identity is being revealed for.
enum RevealSource { report, suggestion, feedback }

String _sourceKey(RevealSource s) => switch (s) {
  RevealSource.report => 'report',
  RevealSource.suggestion => 'suggestion',
  RevealSource.feedback => 'feedback',
};

/// The identity returned by a successful reveal. Held only in ephemeral UI state
/// — never cached or persisted, so each viewing is a fresh, audited action.
class RevealedIdentity {
  final String userId;
  final String name;
  final String? photoUrl;
  final String? phone;
  const RevealedIdentity({
    required this.userId,
    required this.name,
    this.photoUrl,
    this.phone,
  });
}

/// A refusal from the `reveal-identity` edge function, already worded for the
/// admin. [code] is the server's machine code (bad_password, bad_code, locked,
/// …) so the form can decide which step to show.
class RevealException implements Exception {
  final String code;
  final String message;
  const RevealException(this.code, this.message);
  @override
  String toString() => message;
}

Future<Map<String, dynamic>> _invokeReveal(Map<String, dynamic> body) async {
  try {
    final res = await Supabase.instance.client.functions.invoke(
      'reveal-identity',
      body: body,
    );
    return (res.data as Map).cast<String, dynamic>();
  } on FunctionException catch (e) {
    final d = e.details;
    if (d is Map && d['message'] is String) {
      throw RevealException(
        (d['code'] as String?) ?? 'error',
        d['message'] as String,
      );
    }
    throw const RevealException(
      'error',
      'Could not reveal identity. Please try again.',
    );
  } on RevealException {
    rethrow;
  } catch (_) {
    throw const RevealException(
      'network',
      'Unable to connect. Check your internet and try again.',
    );
  }
}

/// Step one: checks the admin's password and emails them a one-time code.
/// Returns the masked address the code went to (e.g. "r•••@gmail.com").
Future<String> sendRevealCode({
  required String password,
  String? actorName,
}) async {
  final res = await _invokeReveal({
    'action': 'send',
    'password': password,
    'actorName': actorName,
  });
  return (res['email'] as String?) ?? 'your email';
}

/// Step two: verifies the emailed [code] and reveals the identity. All checks
/// (full admin, password, code, reason, 5-failure lockout, audit row) run
/// server-side in the `reveal-identity` edge function; the reveal RPC itself is
/// not callable from the app. Throws [RevealException] on any refusal.
Future<RevealedIdentity> revealSubmitterIdentity({
  required RevealSource source,
  required String submissionId,
  required String password,
  required String reason,
  required String code,
  String? actorName,
}) async {
  final db = Supabase.instance.client;
  final res = await _invokeReveal({
    'action': 'reveal',
    'source': _sourceKey(source),
    'id': submissionId,
    'password': password,
    'reason': reason,
    'code': code,
    'actorName': actorName,
  });
  final map = (res['identity'] as Map).cast<String, dynamic>();

  final path = map['photo_path'] as String?;
  String? photoUrl;
  if (path != null && path.isNotEmpty) {
    photoUrl = db.storage.from('profile-photos').getPublicUrl(path);
  }
  final name = (map['name'] as String?)?.trim();
  final phone = (map['phone'] as String?)?.trim();
  return RevealedIdentity(
    userId: map['user_id'] as String,
    name: (name == null || name.isEmpty) ? 'Resident' : name,
    photoUrl: photoUrl,
    phone: (phone == null || phone.isEmpty) ? null : phone,
  );
}

/// The two reveal calls, behind a provider so widget tests can drive the form
/// through every server answer (wrong password, wrong code, lockout, success)
/// without a live backend. The app always uses the real functions above.
class RevealApi {
  final Future<String> Function({required String password, String? actorName})
  sendCode;
  final Future<RevealedIdentity> Function({
    required RevealSource source,
    required String submissionId,
    required String password,
    required String reason,
    required String code,
    String? actorName,
  })
  reveal;
  const RevealApi({required this.sendCode, required this.reveal});
}

final revealApiProvider = Provider<RevealApi>(
  (ref) => const RevealApi(
    sendCode: sendRevealCode,
    reveal: revealSubmitterIdentity,
  ),
);
