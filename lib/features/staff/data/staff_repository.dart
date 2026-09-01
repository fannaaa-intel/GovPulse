import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/image_compressor.dart';

import '../../admin/providers/admin_reports_provider.dart'
    show ReportStatus, reportStatusFromDb, reportStatusToDb, reportCategoryLabel;

// ════════════════════════════════════════════════════════════════════════════
//  Staff data layer — the ONLY place the staff console touches Supabase.
//
//  Reuses the citizen-side tables (concern_tickets, ticket_messages, reports)
//  that already exist; the staff RLS in supabase/legacy/staff_portal.sql scopes every
//  read/write to the signed-in staff member's department.
// ════════════════════════════════════════════════════════════════════════════

// ── Models ───────────────────────────────────────────────────────────────────

class StaffIdentity {
  final String userId;
  final String email;
  final String? fullName;
  final String title;
  final String department;
  final bool isExternal;
  final bool isOnline;
  final String? photoUrl;

  const StaffIdentity({
    required this.userId,
    required this.email,
    required this.fullName,
    required this.title,
    required this.department,
    required this.isExternal,
    required this.isOnline,
    required this.photoUrl,
  });

  String get displayName {
    final n = fullName?.trim() ?? '';
    return n.isNotEmpty ? n : (email.isNotEmpty ? email.split('@').first : title);
  }

  String get initials {
    final src = (fullName?.trim().isNotEmpty ?? false) ? fullName!.trim() : email;
    final parts =
        src.split(RegExp(r'[\s@._-]+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return 'S';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
  }

  StaffIdentity copyWith({bool? isOnline, String? photoUrl}) => StaffIdentity(
        userId: userId,
        email: email,
        fullName: fullName,
        title: title,
        department: department,
        isExternal: isExternal,
        isOnline: isOnline ?? this.isOnline,
        photoUrl: photoUrl ?? this.photoUrl,
      );

  // Value equality is load-bearing, not a nicety. Every list notifier watches
  // this object; without ==, two identical refetches compare unequal, Riverpod
  // reports a state change, and every dependent notifier REBUILDS. That tears
  // down and re-arms their interval timers, restarting the 30s countdown from
  // zero each time — so a burst of identity emissions can prevent a poll from
  // ever firing. Diagnosed 2026-07-22 from a log showing three ARMs and two
  // teardowns in 3.4s, where the first tick survived only by luck.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StaffIdentity &&
          runtimeType == other.runtimeType &&
          userId == other.userId &&
          email == other.email &&
          fullName == other.fullName &&
          title == other.title &&
          department == other.department &&
          isExternal == other.isExternal &&
          isOnline == other.isOnline &&
          photoUrl == other.photoUrl;

  @override
  int get hashCode => Object.hash(userId, email, fullName, title, department,
      isExternal, isOnline, photoUrl);
}

class StaffConversation {
  final String id;
  final String? referenceCode;
  final String category;
  final String department;
  final String status; // open | resolved | closed
  final String? assignedStaffId;
  final String? contactName;
  final String? contactNumber;
  final bool isAnonymous;
  final int? rating; // 1–5, set after the citizen rates a resolved chat
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// The citizen's profile photo URL, attached after fetch (non-anonymous only).
  /// Mutable so the batch photo lookup can fill it without rebuilding the row.
  String? photoUrl;

  StaffConversation({
    required this.id,
    required this.referenceCode,
    required this.category,
    required this.department,
    required this.status,
    required this.assignedStaffId,
    required this.contactName,
    required this.contactNumber,
    required this.isAnonymous,
    required this.rating,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isResolved => status == 'resolved' || status == 'closed';
  bool assignedTo(String uid) => assignedStaffId == uid;
  bool get isWaiting => assignedStaffId == null && !isResolved;

  /// The citizen's name is NEVER shown for an anonymous chat.
  String get citizenLabel {
    if (isAnonymous) return 'Anonymous citizen';
    final n = contactName?.trim();
    if (n != null && n.isNotEmpty) return n;
    return 'Citizen · ${referenceCode ?? id.substring(0, 6)}';
  }

  /// Contact number, hidden for anonymous chats.
  String? get shownNumber => isAnonymous ? null : contactNumber;

  factory StaffConversation.fromRow(Map<String, dynamic> r) {
    final anon = (r['is_anonymous'] as bool?) ?? false;
    return StaffConversation(
      id: r['id'].toString(),
      referenceCode: r['reference_code'] as String?,
      category: (r['category'] as String?) ?? 'Concern',
      department: (r['department'] as String?) ?? '',
      status: (r['status'] as String?) ?? 'open',
      assignedStaffId: r['assigned_staff_id']?.toString(),
      // Defensively drop identity fields for anonymous rows even if present.
      contactName: anon ? null : r['contact_name'] as String?,
      contactNumber: anon ? null : r['contact_number'] as String?,
      isAnonymous: anon,
      rating: (r['rating'] as num?)?.toInt(),
      createdAt: _ts(r['created_at']),
      updatedAt: _ts(r['updated_at']),
    );
  }
}

/// Delivery state for an outgoing staff message — drives the optimistic UI:
/// [sending] shows the moment it's typed, [sent] once the DB write lands,
/// [failed] if the write errors (offering resend/delete).
enum StaffMsgSend { sending, sent, failed }

class StaffMessage {
  final String id;
  final String senderType; // citizen | bot | staff
  final String message;
  final DateTime? createdAt;

  /// Mutable so an optimistic bubble can transition sending → sent/failed in
  /// place. Rows loaded from the DB are always [StaffMsgSend.sent].
  StaffMsgSend sendState;

  StaffMessage({
    required this.id,
    required this.senderType,
    required this.message,
    required this.createdAt,
    this.sendState = StaffMsgSend.sent,
  });

  bool get isStaff => senderType == 'staff';
  bool get isBot => senderType == 'bot';

  factory StaffMessage.fromRow(Map<String, dynamic> r) => StaffMessage(
        id: r['id'].toString(),
        senderType: (r['sender_type'] as String?) ?? 'citizen',
        // ticket_messages content column is `text` (not `message`).
        message: (r['text'] as String?) ?? '',
        createdAt: _ts(r['created_at']),
      );
}

class StaffReport {
  final String id;
  final String shortId;
  final String categoryKey;
  final String category;
  final String? barangay;
  final String? address;
  final String remarks;
  final ReportStatus status;
  final bool isAnonymous;
  final int mediaCount;
  final DateTime? createdAt;
  final String? endorsedToDepartment;
  final String? assignedToDepartment;
  final DateTime? assignedAt;

  const StaffReport({
    required this.id,
    required this.shortId,
    required this.categoryKey,
    required this.category,
    required this.barangay,
    required this.address,
    required this.remarks,
    required this.status,
    required this.isAnonymous,
    required this.mediaCount,
    required this.createdAt,
    required this.endorsedToDepartment,
    this.assignedToDepartment,
    this.assignedAt,
  });

  /// Working clock: when the office took ownership (fell back to filing time).
  DateTime? get _clock => assignedAt ?? createdAt;

  /// Flags a report the office has been sitting on too long without resolving.
  /// under_review/in_progress older than 7 days = overdue.
  bool get isOverdue {
    if (status != ReportStatus.underReview &&
        status != ReportStatus.inProgress) {
      return false;
    }
    final c = _clock;
    return c != null && DateTime.now().difference(c).inDays >= 7;
  }

  int get ageDays {
    final c = _clock;
    return c == null ? 0 : DateTime.now().difference(c).inDays;
  }

  factory StaffReport.fromRow(Map<String, dynamic> r) {
    final id = r['id'].toString();
    final key = (r['category'] as String?) ?? 'others';
    final media = r['report_media'];
    return StaffReport(
      id: id,
      shortId: id.length >= 8 ? id.substring(0, 8).toUpperCase() : id.toUpperCase(),
      categoryKey: key,
      category: reportCategoryLabel(key, r['category_other'] as String?),
      barangay: r['barangay'] as String?,
      address: r['address'] as String?,
      remarks: (r['remarks'] as String?) ?? '',
      status: reportStatusFromDb(r['status'] as String?),
      isAnonymous: (r['is_anonymous'] as bool?) ?? false,
      mediaCount: media is List ? media.length : 0,
      createdAt: _ts(r['created_at']),
      endorsedToDepartment: r['endorsed_to_department'] as String?,
      assignedToDepartment: r['assigned_to_department'] as String?,
      assignedAt: _ts(r['assigned_at']),
    );
  }
}

class StaffReportMedia {
  final String url;
  final String? mimeType;

  /// 'camera' = live GPS-stamped capture; 'upload'/null = unverified upload.
  final String? source;
  const StaffReportMedia({
    required this.url,
    required this.mimeType,
    this.source,
  });
  bool get isVideo => (mimeType ?? '').toLowerCase().startsWith('video/');
  bool get isGpsVerified => source == 'camera';
}

/// A community update the staff member submitted, with its approval status.
/// Staff posts are ALWAYS queued (status `pending_approval`) for an admin to
/// review before they reach the citizen feed.
class StaffCommunityPost {
  final String id;
  final String title;
  final String body;
  final String tag;
  final String tagColor; // hex
  final String status; // pending_approval | approved | rejected
  final String? rejectedReason;
  final String barangay; // '' == city-wide
  final DateTime? createdAt;
  final List<String> imageUrls;

  /// Freshly-picked photos carried ONLY on an optimistic stand-in, so its card
  /// can preview them from local bytes before the upload finishes and the
  /// refetch swaps in the real network [imageUrls]. Always empty on a DB row.
  final List<XFile> localImages;

  const StaffCommunityPost({
    required this.id,
    required this.title,
    required this.body,
    required this.tag,
    required this.tagColor,
    required this.status,
    required this.rejectedReason,
    required this.barangay,
    required this.createdAt,
    this.imageUrls = const [],
    this.localImages = const [],
  });

  bool get isPending => status == 'pending_approval';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';

  /// An optimistic stand-in inserted the instant the composer closes, before
  /// the server row exists — carries a `temp_` id so the list can show it in a
  /// subtle "posting…" state and the notifier can swap it for the real row on
  /// the refetch.
  bool get isOptimistic => id.startsWith('temp_');

  factory StaffCommunityPost.fromRow(
    Map<String, dynamic> r, {
    List<String> imageUrls = const [],
  }) =>
      StaffCommunityPost(
        id: r['id'].toString(),
        title: (r['title'] as String?) ?? '',
        body: (r['body'] as String?) ?? '',
        tag: (r['tag'] as String?) ?? 'Announcement',
        tagColor: (r['tag_color'] as String?) ?? '#2563EB',
        status: (r['status'] as String?) ?? 'pending_approval',
        rejectedReason: r['rejected_reason'] as String?,
        barangay: (r['barangay'] as String?) ?? '',
        createdAt: _ts(r['created_at']),
        imageUrls: imageUrls,
      );
}

DateTime? _ts(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v.toLocal();
  if (v is String) return DateTime.tryParse(v)?.toLocal();
  return null;
}

/// A refusal from `staff_resolve_report` that the officer can do something
/// about, as opposed to a thrown Postgres error.
///
/// The RPC returns `{ok: false, error: ...}` for the cases that are a race or
/// an omission rather than a fault — the note was blank, someone else resolved
/// it first, the admin rejected it meanwhile. Each has its own sentence,
/// because "could not resolve" tells an officer nothing about whether to
/// retype, reload, or stop.
class StaffResolveFailure implements Exception {
  final String code;
  const StaffResolveFailure(this.code);

  @override
  String toString() => switch (code) {
        'body_required' =>
          'Describe what was done before marking this resolved.',
        'already_resolved' => 'This report has already been resolved.',
        'report_rejected' =>
          'The Municipality rejected this report, so it cannot be resolved.',
        'already_advanced' =>
          'The report changed while you were writing. Reload and try again.',
        'not_found' => 'This report no longer exists.',
        _ => 'Could not resolve the report. Try again.',
      };
}

// ── Repository ───────────────────────────────────────────────────────────────

class StaffRepository {
  StaffRepository._();
  static final StaffRepository I = StaffRepository._();
  SupabaseClient get _db => Supabase.instance.client;

  static const String _reportBucket = 'report-media';
  // Staff identity is stored in admin_profiles, so the avatar lives in the same
  // public bucket the admin console uses (owner-scoped folder per storage RLS).
  static const String _avatarBucket = 'admin-avatars';

  String? get _uid => _db.auth.currentUser?.id;

  // ── Identity + presence ────────────────────────────────────────────────────
  Future<StaffIdentity> fetchIdentity() async {
    final user = _db.auth.currentUser;
    final uid = user?.id ?? '';
    final email = user?.email ?? '';

    Map<String, dynamic>? row;
    if (uid.isNotEmpty) {
      try {
        row = await _db
            .from('admin_profiles')
            .select(
              'full_name, title, department, is_external, is_online, photo_url',
            )
            .eq('user_id', uid)
            .maybeSingle();
      } catch (e) {
        debugPrint('fetchIdentity: $e');
      }
    }

    return StaffIdentity(
      userId: uid,
      email: email,
      fullName: (row?['full_name'] as String?)?.trim(),
      title: ((row?['title'] as String?)?.trim().isNotEmpty ?? false)
          ? (row!['title'] as String).trim()
          : 'Staff',
      department: (row?['department'] as String?)?.trim() ?? '',
      isExternal: (row?['is_external'] as bool?) ?? false,
      isOnline: (row?['is_online'] as bool?) ?? false,
      photoUrl: row?['photo_url'] as String?,
    );
  }

  Future<void> setOnline(bool online) async {
    final uid = _uid;
    if (uid == null) return;
    await _db.from('admin_profiles').update({
      'is_online': online,
      'last_seen_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('user_id', uid);
  }

  /// Uploads a new avatar to the public `admin-avatars` bucket (keyed under the
  /// staff member's own folder), persists its URL on `admin_profiles`, and
  /// returns the URL. A timestamped path busts any cached image.
  Future<String> updatePhoto(Uint8List bytes, String ext) async {
    final uid = _uid;
    if (uid == null) throw 'Your session has expired. Please log in again.';

    // Capped here rather than at the picker: this takes a plain Uint8List, so
    // the picker's maxWidth never reaches it. Matches the admin console's
    // avatar tier (admin/providers/admin_profile_provider.dart) — both render
    // through the same AdminAvatar widget at the same sizes.
    final out = await ImageCompressor.compressBytes(
      bytes,
      purpose: ImagePurpose.avatar,
      sourceMime: ImageCompressor.mimeForExtension(ext),
      sourceExt: ext.toLowerCase(),
    );

    final path = '$uid/${DateTime.now().millisecondsSinceEpoch}.${out.ext}';
    await _db.storage.from(_avatarBucket).uploadBinary(
          path,
          out.bytes,
          fileOptions: FileOptions(contentType: out.mime, upsert: true),
        );
    final url = _db.storage.from(_avatarBucket).getPublicUrl(path);
    await _db.from('admin_profiles').update({
      'photo_url': url,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('user_id', uid);
    return url;
  }

  // ── Conversations (concern_tickets) ─────────────────────────────────────────
  Future<List<StaffConversation>> fetchConversations(String department) async {
    if (department.isEmpty) return const [];
    // Reads through `staff_tickets_view`, NOT `concern_tickets` directly. The
    // base table exposes five raw contact columns on every row; the view nulls
    // all of them (and user_id) for anonymous tickets in the database, so the
    // citizen's number never leaves Postgres for an anonymous chat. Staff have
    // no SELECT policy on concern_tickets itself any more — see migration
    // 20260721000007. The view is department-self-scoping, but the .eq() is
    // kept as defence in depth and to match the ghost filter.
    final rows = await _db
        .from('staff_tickets_view')
        .select(
          'id, reference_code, category, department, status, assigned_staff_id, '
          'contact_name, contact_number, is_anonymous, rating, '
          'created_at, updated_at',
        )
        .eq('department', department)
        .eq('is_ghost', false)
        .order('updated_at', ascending: false)
        .limit(200);
    final convos = List<Map<String, dynamic>>.from(rows)
        .map(StaffConversation.fromRow)
        .toList();
    // Attach citizen photos in one batch call (non-anonymous tickets only).
    try {
      final photoRows = await _db.rpc('department_ticket_citizens');
      if (photoRows is List) {
        final byId = <String, String>{};
        for (final r in photoRows) {
          final id = r['ticket_id']?.toString();
          final path = (r['photo_path'] as String?)?.trim() ?? '';
          if (id != null && path.isNotEmpty) {
            byId[id] =
                _db.storage.from('profile-photos').getPublicUrl(path);
          }
        }
        for (final c in convos) {
          if (!c.isAnonymous) c.photoUrl = byId[c.id];
        }
      }
    } catch (_) {/* list keeps initial/default avatars */}
    return convos;
  }

  /// ONE ticket's live row, for the open thread's targeted refresh.
  ///
  /// Same view and same column list as [fetchConversations] — a second reader of
  /// `concern_tickets` would need a base-table SELECT policy that deliberately
  /// does not exist (20260721000007 §4).
  ///
  /// WHY THIS EXISTS: the citizen's star rating lands minutes after the staff
  /// ends the chat, and staff cannot subscribe to `concern_tickets` at all —
  /// realtime authorises delivery through SELECT policies, so a subscription
  /// would connect, report success and deliver nothing forever (see the long
  /// note below `setConversationStatus`). The 30s inbox poll is therefore the
  /// only thing that can notice a rating, and 30s of nothing on the screen you
  /// are looking at reads as broken. The thread polls this instead while it is
  /// waiting on a rating. Returns null if the ticket is outside the caller's
  /// department, which the view enforces rather than this query.
  Future<StaffConversation?> fetchConversation(String ticketId) async {
    final row = await _db
        .from('staff_tickets_view')
        .select(
          'id, reference_code, category, department, status, assigned_staff_id, '
          'contact_name, contact_number, is_anonymous, rating, '
          'created_at, updated_at',
        )
        .eq('id', ticketId)
        .maybeSingle();
    if (row == null) return null;
    return StaffConversation.fromRow(row);
  }

  /// The ticket's citizen photo URL (public `profile-photos` bucket), for the
  /// chat header + bubbles. Reads the `ticket_citizen` SECURITY DEFINER RPC
  /// (staff can't read citizen_details directly). Returns null for anonymous
  /// chats, when there's no photo, or on any error — the UI then shows a default
  /// / initial avatar.
  Future<String?> fetchCitizenPhoto(String ticketId) async {
    try {
      final res =
          await _db.rpc('ticket_citizen', params: {'p_ticket': ticketId});
      final row = (res is List && res.isNotEmpty)
          ? res.first as Map<String, dynamic>
          : (res is Map<String, dynamic> ? res : null);
      final path = (row?['photo_path'] as String?)?.trim() ?? '';
      if (path.isEmpty) return null;
      return _db.storage.from('profile-photos').getPublicUrl(path);
    } catch (e) {
      return null;
    }
  }

  /// Reads through `staff_messages_view`, NOT `ticket_messages` directly.
  ///
  /// The base table exposes `sender_id` on every row — the citizen's auth.users
  /// id — including on tickets the citizen marked anonymous, which handed the
  /// assigned officer the reporter's identity. The view is a definer view that
  /// nulls `sender_id` when the PARENT ticket is anonymous and scopes itself to
  /// the caller's department. Same discipline as `staff_tickets_view` /
  /// `staff_reports_view`. See migration 20260731000003.
  ///
  /// Staff can no longer select `sender_id` from the base table at all (the
  /// column was removed from the `authenticated` grant), so this cannot silently
  /// regress to reading identity — it would 42501 instead.
  Future<List<StaffMessage>> fetchMessages(String ticketId) async {
    final rows = await _db
        .from('staff_messages_view')
        .select('id, sender_type, text, created_at')
        .eq('ticket_id', ticketId)
        .order('created_at', ascending: true);
    return List<Map<String, dynamic>>.from(rows)
        .map(StaffMessage.fromRow)
        .toList();
  }

  /// Sends a staff reply and returns the inserted row so the thread can show it
  /// immediately and de-dupe it against the realtime echo (matched by id).
  Future<StaffMessage> sendMessage(String ticketId, String text) async {
    final uid = _uid;
    if (uid == null) throw 'Your session has expired. Please log in again.';
    final row = await _db
        .from('ticket_messages')
        .insert({
          'ticket_id': ticketId,
          'sender_id': uid,
          'sender_type': 'staff',
          'text': text, // content column is `text`, not `message`
          // created_at is deliberately NOT sent. The column defaults to now(),
          // so every message in a thread is stamped by ONE clock — the
          // database's. Sending DateTime.now().toIso8601String() from the client
          // (as this did) is wrong twice over: it is local time with no offset,
          // which Postgres reads as UTC and stores 8 hours off, and it makes
          // message ORDER depend on whether the staff PC and the citizen's phone
          // agree on the time. They did not, which is why the staff thread
          // rendered all staff messages before all citizen replies while the
          // citizen's Hive-backed view showed the true interleaving.
        })
        .select('id, sender_type, text, created_at')
        .single();
    // Bump the ticket so it floats to the top of the inbox — via RPC, because
    // staff no longer hold a direct UPDATE policy on concern_tickets. A raw
    // update here would silently affect 0 rows. Fire-and-forget: the reply is
    // already sent, so a failed re-sort must not fail the send.
    try {
      await _db.rpc('staff_touch_ticket', params: {'p_ticket': ticketId});
    } catch (_) {/* inbox ordering only — never block a sent message */}
    return StaffMessage.fromRow(row);
  }

  /// Claims an unassigned ticket for the signed-in staff member.
  ///
  /// Goes through the `staff_claim_ticket` RPC rather than an UPDATE on
  /// concern_tickets. Staff no longer hold an UPDATE (or SELECT) policy on that
  /// table, and a WHERE-scoped UPDATE without a SELECT policy affects zero rows
  /// and returns SUCCESS — the silent no-op this whole remediation kept finding.
  /// The RPC re-checks department ownership and RAISES on denial, so a failed
  /// claim throws here instead of pretending to work.
  Future<void> claimConversation(String ticketId) async {
    final uid = _uid;
    if (uid == null) return;
    await _db.rpc('staff_claim_ticket', params: {'p_ticket': ticketId});
  }

  Future<void> setConversationStatus(String ticketId, String status) async {
    // See claimConversation: definer RPC, raises on denial, never a silent
    // no-op. resolved_at is stamped server-side for terminal statuses.
    await _db.rpc('staff_set_ticket_status',
        params: {'p_ticket': ticketId, 'p_status': status});
  }

  // subscribeDepartmentTickets was REMOVED in migration 20260721000007. It
  // subscribed to postgres_changes on concern_tickets, which shipped the raw
  // row — five citizen contact columns — over the socket, defeating ticket
  // anonymity.
  //
  // concern_tickets IS in the realtime publication again as of migration
  // 20260722000004 (its removal broke the citizen's rating card and protected
  // nothing). What keeps staff from receiving these rows is that staff hold no
  // SELECT policy on concern_tickets: realtime authorizes every change against
  // the subscriber's own SELECT policies — confirmed empirically on 2026-07-30
  // with two live accounts, not inferred. So re-adding this subscription would
  // not leak today — but it would the instant anyone grants staff a read
  // policy. Do not reintroduce it.
  //
  // That assertion is checked by
  // supabase/diagnostics/verify_20260722000004_ticket_realtime.sql AS OF THE
  // COMMIT THAT ADDED THAT FILE (2026-07-30). This comment previously claimed
  // the check already enforced it; it did not — the file did not exist, and
  // for eight days the rule lived in this comment and the migration header and
  // nothing verified either. Run the diagnostic before trusting the invariant,
  // and do not restore a past-tense claim here.
  //
  // The staff inbox polls instead (see staff_conversations_page). Live push
  // returns in 7c via Broadcast with a non-identifying payload.
  //
  // ── ticket_messages IS DIFFERENT, AND STAYS SUBSCRIBED DELIBERATELY ───────
  // The subscription below is NOT an oversight and must not be "cleaned up" to
  // match the concern_tickets treatment above. Removing ticket_messages from the
  // publication would stop new messages appearing in the staff thread without a
  // manual refresh — a feature outage, which the finding's acceptance criterion
  // rejects by name (condition 4, "a regression wearing a fix's clothes").
  //
  // The row this subscription delivers no longer carries the citizen's identity.
  // Migration 20260731000003 removed `sender_id` from the `authenticated` column
  // grant, and realtime.apply_rls builds each payload only from columns the
  // subscriber's role can SELECT — so the column is absent from the wire rather
  // than merely unread. Measured on this project, not inferred: the delivered
  // record's keys are exactly id, ticket_id, sender_type, text, created_at.
  //
  // Two consequences worth knowing before changing anything here:
  //   * The masking is by GRANT, not by policy, and it is blanket — `sender_id`
  //     is absent for attributed tickets too, and for the citizen's own
  //     subscription. That is an accepted deviation (nothing reads the value),
  //     recorded in the migration header.
  //   * `p.newRecord` therefore has no `sender_id` key at all. StaffMessage
  //     .fromRow already ignores it and threads on `sender_type`. Do not add a
  //     dependency on `sender_id` to this callback — it would read as null in
  //     production and there is no server-side path to get it back.

  RealtimeChannel subscribeMessages(
    String ticketId,
    void Function(StaffMessage) onInsert,
  ) {
    return _db
        .channel('staff_ticket_msgs:$ticketId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'ticket_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'ticket_id',
            value: ticketId,
          ),
          callback: (p) => onInsert(StaffMessage.fromRow(p.newRecord)),
        )
        .subscribe();
  }

  // ── Reports (department-scoped) ─────────────────────────────────────────────
  static const String _reportCols =
      'id, category, category_other, barangay, address, remarks, status, '
      'is_anonymous, created_at, endorsed_to_department, '
      'assigned_to_department, assigned_at, report_media(id)';

  /// Reports the ADMIN has accepted INTO this office. A report is only visible
  /// here once triaged (assigned_to_department set) — pending reports stay on
  /// the admin's desk. Anonymous reports ARE shown (the reporter's identity is
  /// never exposed in the staff view — only the issue itself).
  /// Reads through `staff_reports_view`, NOT `reports` directly. The base table
  /// exposes `user_id` on every row including anonymous ones; the view nulls it
  /// in the database when `is_anonymous`, so an anonymous reporter's identity
  /// never leaves Postgres. Staff have no SELECT policy on `reports` any more —
  /// see migration 20260722000000. The view is department-self-scoping (its
  /// WHERE calls `staff_can_see_report`), but the .eq() is kept as defence in
  /// depth and to separate assigned from endorsed.
  Future<List<StaffReport>> fetchDepartmentReports(String department) async {
    if (department.isEmpty) return const [];
    final rows = await _db
        .from('staff_reports_view')
        .select(_reportCols)
        .eq('assigned_to_department', department)
        .order('created_at', ascending: false)
        .limit(200);
    return List<Map<String, dynamic>>.from(rows)
        .map(StaffReport.fromRow)
        .toList();
  }

  Future<List<StaffReport>> fetchEndorsedReports(String department) async {
    if (department.isEmpty) return const [];
    final rows = await _db
        .from('staff_reports_view')
        .select(_reportCols)
        .eq('endorsed_to_department', department)
        .order('created_at', ascending: false)
        .limit(200);
    return List<Map<String, dynamic>>.from(rows)
        .map(StaffReport.fromRow)
        .toList();
  }

  /// Goes through the `staff_set_report_status` RPC rather than an UPDATE on
  /// `reports`. Staff no longer hold an UPDATE (or SELECT) policy on that table,
  /// and a WHERE-scoped UPDATE without a SELECT policy affects zero rows and
  /// returns SUCCESS — the silent no-op this remediation kept finding. The RPC
  /// re-checks department ownership and RAISES on denial, so a failed status
  /// change throws here instead of pretending to work.
  Future<void> setReportStatus(String id, ReportStatus status) async {
    await _db.rpc('staff_set_report_status',
        params: {'p_report': id, 'p_status': reportStatusToDb(status)});
  }

  /// Resolve a report AND write its completion update, in one transaction.
  ///
  /// Not [setReportStatus] with `resolved`: that path is now refused by the
  /// database (migration 20260901000001). Resolving is the moment the citizen
  /// is told the work is finished, and a closed report with no account of what
  /// was done — and so no completion gallery, which §11 of 20260829000001 keys
  /// on an approved completion update existing — is the failure that split
  /// the two halves apart in the first place.
  ///
  /// Returns the new update's id so the caller can attach photos to it, the
  /// same shape `advance_endorsement` returns to the agency scan page.
  /// Throws [StaffResolveFailure] on a refusal the officer can act on.
  Future<String> resolveReportWithCompletion(String id, String body) async {
    final res = await _db.rpc('staff_resolve_report',
        params: {'p_report': id, 'p_body': body});
    final map = Map<String, dynamic>.from(res as Map);
    if (map['ok'] != true) {
      throw StaffResolveFailure(map['error']?.toString() ?? 'unknown');
    }
    return map['update_id'].toString();
  }

  /// Bounce a mis-routed report back to the admin's triage desk. Leaves an audit
  /// note FIRST (while still assigned, so RLS allows it — and the note pings the
  /// admins), then clears ownership + returns the status to pending.
  Future<void> returnToTriage(String id, String reason, String office) async {
    final note = reason.trim().isEmpty
        ? 'Returned to triage (not this office\'s scope).'
        : 'Returned to triage — ${reason.trim()}';
    try {
      await _db.from('report_notes').insert({
        'report_id': id,
        'author_id': _uid,
        'author_role': 'staff',
        'author_name': office,
        'body': note,
      });
    } catch (e) {
      // Non-fatal — proceed with the bounce even if the note write fails.
      // Logged rather than discarded: this is the bounce AUDIT TRAIL, and a
      // write failure that produces no error, no log and no row is
      // indistinguishable from success. See the findings report.
      debugPrint('returnToTriage: audit note insert failed: $e');
    }
    // Via RPC — staff no longer hold a direct UPDATE policy on reports, so a
    // raw update here would silently affect 0 rows. Note the ORDER: the audit
    // note above must be inserted BEFORE this call, because report_notes_staff_insert
    // resolves through staff_can_see_report(), which stops matching the instant
    // this RPC nulls both department columns. Do not reorder.
    await _db.rpc('staff_return_to_triage', params: {'p_report': id});
  }

  // ── Community updates (staff submit → admin approves) ───────────────────────
  Future<List<StaffCommunityPost>> fetchMyCommunityPosts() async {
    final uid = _uid;
    if (uid == null) return const [];
    final rows = await _db
        .from('community_posts')
        .select('id, title, body, tag, tag_color, status, rejected_reason, '
            'barangay, created_at')
        .eq('author_id', uid)
        .order('created_at', ascending: false)
        .limit(100);
    final list = List<Map<String, dynamic>>.from(rows);
    final imagesByPost =
        await _fetchMyPostImages([for (final r in list) r['id'].toString()]);
    return list
        .map((r) => StaffCommunityPost.fromRow(
              r,
              imageUrls: imagesByPost[r['id'].toString()] ?? const [],
            ))
        .toList();
  }

  /// Public thumbnail URLs for the staff member's own posts, keyed by post id.
  /// Guarded: until the 20260719000002 read policy is applied the table read
  /// 42501s — the list then just renders without thumbnails.
  Future<Map<String, List<String>>> _fetchMyPostImages(
    List<String> postIds,
  ) async {
    if (postIds.isEmpty) return const {};
    try {
      final rows = await _db
          .from('community_post_images')
          .select('post_id, storage_path, display_order')
          .inFilter('post_id', postIds)
          .order('display_order', ascending: true);
      final map = <String, List<String>>{};
      for (final r in List<Map<String, dynamic>>.from(rows)) {
        final url = _db.storage
            .from('community-posts')
            .getPublicUrl(r['storage_path'] as String);
        (map[r['post_id'].toString()] ??= []).add(url);
      }
      return map;
    } catch (_) {
      return const {};
    }
  }

  /// Submits a community update as the staff member. It is inserted as
  /// `pending_approval` — the admin console picks it up in its review queue.
  ///
  /// [images] are uploaded to the same `community-posts` bucket +
  /// `community_post_images` table the admin composer uses, so an approved
  /// staff post renders photos on the citizen feed identically. Returns the
  /// number of photos that FAILED to upload (0 = all good) — the post itself
  /// is already saved by then, so a photo failure is a warning, not an error.
  Future<int> submitCommunityPost({
    required String title,
    required String body,
    required String barangay,
    required String tag,
    required String tagColorHex,
    List<XFile> images = const [],
  }) async {
    final uid = _uid;
    if (uid == null) throw 'Your session has expired. Please log in again.';
    final row = {
      'author_id': uid,
      'title': title.trim(),
      'body': body.trim(),
      'barangay': barangay,
      'tag': tag,
      'tag_color': tagColorHex,
      'status': 'pending_approval',
    };

    // The insert and the read-back are separately permissioned, and the submit
    // must not fail just because the read half is refused.
    //
    // `.insert().select().single()` throws PGRST116 when the row comes back
    // empty — which is what happens if the INSERT policy from
    // 20260719000001 §1 is applied but the `posts_read_own` SELECT policy from
    // §2 is not. The post IS saved; only reading it back fails. That surfaced
    // as staffFriendlyError's generic "The server rejected the request", so a
    // successful submission looked like a total failure and staff re-posted.
    //
    // So: write first, then try to learn the id. If the id can't be read the
    // submission still counts — only the photos, which need it, are lost.
    String? postId;
    try {
      final inserted =
          await _db.from('community_posts').insert(row).select('id').single();
      postId = inserted['id'] as String?;
    } on PostgrestException catch (e) {
      // ONLY PGRST116 means "the write went through but the row could not be
      // read back". Everything else is a genuine failure of the WRITE and must
      // surface — the earlier version of this catch rethrew just 42501 and
      // treated every other code as a benign read-back miss, which silently
      // swallowed the BEFORE INSERT triggers on community_posts:
      //   trg_rl_community_posts    → P0001, hint rate_limit_exceeded
      //   trg_restrict_community_posts → P0001, hint user_restricted
      // Both raise, so nothing was ever inserted — yet submit() resolved
      // "successfully" with postId null, so the photos were skipped and the
      // staff member was told "the update was still submitted". It never was.
      // staffFriendlyError() already renders both hints; it just never ran.
      if (e.code != 'PGRST116') rethrow;
      debugPrint('submitCommunityPost: insert read-back failed (${e.code}) — '
          'post is saved; recovering id');
      // Best-effort recovery so photos can still attach.
      try {
        final found = await _db
            .from('community_posts')
            .select('id')
            .eq('author_id', uid)
            .eq('status', 'pending_approval')
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();
        postId = found?['id'] as String?;
      } catch (_) {
        // Reads are blocked too — nothing more to do. The post stands.
      }
    }

    // No id and nothing to attach: the submission succeeded outright.
    if (postId == null) {
      if (images.isEmpty) return 0;
      debugPrint('submitCommunityPost: no post id — skipping ${images.length} '
          'photo(s); the update itself was submitted');
      return images.length;
    }

    var failed = 0;
    for (var i = 0; i < images.length; i++) {
      try {
        // Same pass the admin composer runs (admin/providers/
        // community_updates_provider.dart) — the two write into the SAME
        // bucket and the same feed, so they must not disagree on size.
        final out = await ImageCompressor.compressPicked(
          images[i],
          purpose: ImagePurpose.content,
        );
        final stamp = DateTime.now().millisecondsSinceEpoch;
        final path = 'posts/$uid/${stamp}_$i.${out.ext}';
        // Two separately-permissioned steps. Reported apart, because "a photo
        // failed" does not say WHICH grant is missing — the storage bucket
        // policy (20260719000001 §4) and the community_post_images INSERT
        // policy (§3) fail identically from the caller's point of view.
        try {
          await _db.storage.from('community-posts').uploadBinary(
                path,
                out.bytes,
                fileOptions:
                    FileOptions(contentType: out.mime, upsert: false),
              );
        } catch (e) {
          debugPrint('community post photo STORAGE upload failed for $path: $e '
              '— check the community-posts bucket INSERT policy '
              '(20260719000001 §4)');
          rethrow;
        }
        try {
          await _db.from('community_post_images').insert({
            'post_id': postId,
            'storage_path': path,
            'display_order': i,
          });
        } catch (e) {
          debugPrint('community post photo ROW insert failed for $path: $e '
              '— the file uploaded but community_post_images refused the row; '
              'check its INSERT policy (20260719000001 §3)');
          rethrow;
        }
      } catch (e) {
        failed++;
      }
    }
    return failed;
  }

  /// Retract (hard-delete) one of the staff member's OWN community submissions
  /// — used from "My submissions" while a post is still awaiting review.
  /// Removes the image rows + their storage objects first, then the post row.
  /// Author-scoped delete relies on the `authors_delete_own_pending_posts` RLS
  /// policy (migration 20260719000003); until that's applied the delete 42501s,
  /// surfaced to the user as a friendly "not allowed yet" message.
  Future<void> deleteMyCommunityPost(String postId) async {
    final uid = _uid;
    if (uid == null) throw 'Your session has expired. Please log in again.';

    // Collect storage paths up front so we can purge the objects after the rows.
    List<String> paths = const [];
    try {
      final rows = await _db
          .from('community_post_images')
          .select('storage_path')
          .eq('post_id', postId);
      paths = [
        for (final r in List<Map<String, dynamic>>.from(rows))
          r['storage_path'] as String,
      ];
    } catch (_) {/* best-effort — a read hiccup just skips storage cleanup */}

    // Remove child image rows first in case the FK isn't ON DELETE CASCADE,
    // then the storage objects, then the post itself (author-scoped).
    try {
      await _db.from('community_post_images').delete().eq('post_id', postId);
    } catch (_) {}
    if (paths.isNotEmpty) {
      try {
        await _db.storage.from('community-posts').remove(paths);
      } catch (_) {/* object may already be gone — non-fatal */}
    }
    await _db
        .from('community_posts')
        .delete()
        .eq('id', postId)
        .eq('author_id', uid);
  }

  Future<List<StaffReportMedia>> fetchReportMedia(String reportId) async {
    // `source` was added by media_source_column.sql — retry without it if the
    // migration hasn't been applied yet so media viewing never breaks.
    List<Map<String, dynamic>> rows;
    try {
      rows = List<Map<String, dynamic>>.from(
        await _db
            .from('report_media')
            .select('storage_path, mime_type, display_order, source')
            .eq('report_id', reportId)
            .order('display_order', ascending: true),
      );
    } catch (_) {
      rows = List<Map<String, dynamic>>.from(
        await _db
            .from('report_media')
            .select('storage_path, mime_type, display_order')
            .eq('report_id', reportId)
            .order('display_order', ascending: true),
      );
    }
    final out = <StaffReportMedia>[];
    for (final r in rows) {
      final path = r['storage_path'] as String;
      String url;
      try {
        url = await _db.storage.from(_reportBucket).createSignedUrl(path, 3600);
      } catch (_) {
        url = _db.storage.from(_reportBucket).getPublicUrl(path);
      }
      out.add(
        StaffReportMedia(
          url: url,
          mimeType: r['mime_type'] as String?,
          source: r['source'] as String?,
        ),
      );
    }
    return out;
  }
}

/// Turns a raw Supabase/network failure into a sentence a staff member can act
/// on — a PostgrestException dump ("42501 … row-level security") means nothing
/// to them. Strings thrown by the repo itself (already friendly) pass through.
String staffFriendlyError(Object e) {
  if (e is String) return e;
  if (e is PostgrestException) {
    // 42501 = RLS refusal — the account genuinely isn't allowed to do this.
    if (e.code == '42501' ||
        e.message.toLowerCase().contains('row-level security')) {
      return "Your account isn't allowed to do this yet. "
          'Please ask an LGU admin to check your staff access.';
    }

    // Triggers signal intent through `hint`, not through the error code — they
    // all raise P0001, so matching on the code alone cannot tell a moderation
    // block from a genuine fault. These two were being swallowed by the
    // catch-all below and reported as "the server rejected the request", which
    // told a restricted or rate-limited staff member nothing about why, and
    // invited them to retry something that could never succeed.
    final hint = (e.hint ?? '').trim();
    if (hint == 'user_restricted') {
      // check_user_restriction() puts the admin's reason in `details`.
      final reason = (e.details ?? '').toString().trim();
      return reason.isNotEmpty
          ? reason
          : 'This feature is currently unavailable for your account. '
              'Please contact an LGU admin.';
    }
    if (hint == 'rate_limit_exceeded') {
      // enforce_rate_limit() is called with a caller-supplied sentence naming
      // the actual cap and window ("You can only create 10 posts per day."),
      // and that is far more use than a generic one — the community_posts
      // limit resets tomorrow, not "in a moment", so the generic text told
      // people to retry immediately when they could not possibly succeed.
      final msg = e.message.trim();
      return msg.isNotEmpty
          ? msg
          : "You're doing that too quickly. "
              'Please wait a moment and try again.';
    }

    // PGRST116 = the write went through but the row could not be read back
    // (INSERT permitted, SELECT not). Saying "rejected" here is simply untrue,
    // and it makes people submit again — creating duplicates of something that
    // already saved.
    if (e.code == 'PGRST116') {
      return 'Saved, but it could not be loaded back. '
          'Refresh to confirm before submitting again.';
    }

    // Anything else: name the code. Without it every distinct server fault
    // looks identical on screen, and diagnosing one means guessing at which
    // constraint or trigger fired. The code is what makes the next report
    // actionable.
    final code = (e.code ?? '').trim();
    debugPrint('staffFriendlyError: PostgrestException '
        'code=${e.code} message=${e.message} '
        'details=${e.details} hint=${e.hint}');
    return code.isEmpty
        ? 'The server rejected the request. Please try again in a moment.'
        : 'The server rejected the request ($code). '
            'Please try again in a moment.';
  }
  if (e is StorageException) {
    return "A photo couldn't be uploaded. Please try again.";
  }
  if (e is AuthException) {
    return 'Your session has expired. Please log in again.';
  }
  final s = e.toString().toLowerCase();
  if (s.contains('socket') ||
      s.contains('failed host lookup') ||
      s.contains('connection') ||
      s.contains('timeout') ||
      s.contains('network')) {
    return 'No internet connection. Check your network and try again.';
  }
  return 'Something went wrong. Please try again.';
}
