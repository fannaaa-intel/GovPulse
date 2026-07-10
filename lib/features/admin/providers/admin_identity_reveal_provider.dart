import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Anonymous submitter reveal — client side of anonymous_reveal.sql
//
//  Anonymous reports/suggestions/feedback keep their real user_id server-side
//  but withhold the identity. The ONLY sanctioned way to surface it is the
//  guarded `admin_reveal_submitter` RPC: full admin (role 1) + password re-auth
//  + a reason, all audited. This file exposes:
//    • currentAdminIsFullAdminProvider — gates the "Reveal" button to role 1.
//    • revealSubmitterIdentity()       — calls the guarded RPC.
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

/// Calls the guarded `admin_reveal_submitter` RPC. The server verifies the
/// caller is a full admin, re-checks the password, requires the reason, and
/// writes the audit-log entry before returning the identity. Any failure
/// (wrong password → 28P01, not authorized → 42501, blank reason, missing row)
/// throws so the caller can surface it.
Future<RevealedIdentity> revealSubmitterIdentity({
  required RevealSource source,
  required String submissionId,
  required String password,
  required String reason,
  String? actorName,
}) async {
  final db = Supabase.instance.client;
  final res = await db.rpc('admin_reveal_submitter', params: {
    'p_source': _sourceKey(source),
    'p_id': submissionId,
    'p_password': password,
    'p_reason': reason,
    'p_actor_name': actorName,
  });
  final map = (res as Map).cast<String, dynamic>();

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
