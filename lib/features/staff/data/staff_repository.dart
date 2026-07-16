import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  final String? reportId;
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
    required this.reportId,
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
      reportId: r['report_id']?.toString(),
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
  });

  bool get isPending => status == 'pending_approval';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';

  factory StaffCommunityPost.fromRow(Map<String, dynamic> r) =>
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
      );
}

DateTime? _ts(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v.toLocal();
  if (v is String) return DateTime.tryParse(v)?.toLocal();
  return null;
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
    final safe = ext.toLowerCase();
    final path = '$uid/${DateTime.now().millisecondsSinceEpoch}.$safe';
    final mime = switch (safe) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      'heic' => 'image/heic',
      _ => 'image/jpeg',
    };
    await _db.storage.from(_avatarBucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: mime, upsert: true),
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
    final rows = await _db
        .from('concern_tickets')
        .select(
          'id, reference_code, category, department, status, assigned_staff_id, '
          'contact_name, contact_number, report_id, is_anonymous, rating, '
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

  Future<List<StaffMessage>> fetchMessages(String ticketId) async {
    final rows = await _db
        .from('ticket_messages')
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
          'created_at': DateTime.now().toIso8601String(),
        })
        .select('id, sender_type, text, created_at')
        .single();
    // Bump the ticket so it floats to the top of the inbox.
    await _db.from('concern_tickets').update({
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', ticketId);
    return StaffMessage.fromRow(row);
  }

  /// Claims an unassigned ticket for the signed-in staff member.
  Future<void> claimConversation(String ticketId) async {
    final uid = _uid;
    if (uid == null) return;
    await _db.from('concern_tickets').update({
      'assigned_staff_id': uid,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', ticketId);
  }

  Future<void> setConversationStatus(String ticketId, String status) async {
    await _db.from('concern_tickets').update({
      'status': status,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', ticketId);
  }

  /// Fires whenever a ticket in [department] changes (new waiting chat, an
  /// assignment, a status flip) so the inbox can refresh itself live.
  RealtimeChannel subscribeDepartmentTickets(
    String department,
    void Function() onChange,
  ) {
    return _db
        .channel('staff_dept_tickets:$department')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'concern_tickets',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'department',
            value: department,
          ),
          callback: (_) => onChange(),
        )
        .subscribe();
  }

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
  Future<List<StaffReport>> fetchDepartmentReports(String department) async {
    if (department.isEmpty) return const [];
    final rows = await _db
        .from('reports')
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
        .from('reports')
        .select(_reportCols)
        .eq('endorsed_to_department', department)
        .order('created_at', ascending: false)
        .limit(200);
    return List<Map<String, dynamic>>.from(rows)
        .map(StaffReport.fromRow)
        .toList();
  }

  Future<void> setReportStatus(String id, ReportStatus status) async {
    await _db
        .from('reports')
        .update({'status': reportStatusToDb(status)}).eq('id', id);
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
    } catch (_) {
      // Non-fatal — proceed with the bounce even if the note write fails.
    }
    await _db.from('reports').update({
      'status': reportStatusToDb(ReportStatus.pending),
      'assigned_to_department': null,
      'endorsed_to_department': null,
    }).eq('id', id);
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
    return List<Map<String, dynamic>>.from(rows)
        .map(StaffCommunityPost.fromRow)
        .toList();
  }

  /// Submits a community update as the staff member. It is inserted as
  /// `pending_approval` — the admin console picks it up in its review queue.
  Future<void> submitCommunityPost({
    required String title,
    required String body,
    required String barangay,
    required String tag,
    required String tagColorHex,
  }) async {
    final uid = _uid;
    if (uid == null) throw 'Your session has expired. Please log in again.';
    await _db.from('community_posts').insert({
      'author_id': uid,
      'title': title.trim(),
      'body': body.trim(),
      'barangay': barangay,
      'tag': tag,
      'tag_color': tagColorHex,
      'status': 'pending_approval',
    });
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
