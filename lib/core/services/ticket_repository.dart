import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/Home/Chat-agent/chat_models.dart';
import 'package:flutter/foundation.dart';

/// Wraps every Supabase call related to concern tickets.
///
/// This is the **only** layer that knows about Supabase tables for tickets.
/// ChatService talks to this class, never to Supabase directly.
class TicketRepository {
  TicketRepository._();
  static final TicketRepository I = TicketRepository._();
  final _db = Supabase.instance.client;

  // ── Ticket creation ────────────────────────────────────────────────────────

  /// Creates a new concern ticket and returns the inserted row.
  Future<Map<String, dynamic>> createTicket({
    required ConcernCategory category,
    required String details,
    required String referenceCode,
    String? contactName,
    String? contactNumber,
    String? contactAddress,
    String? contactEmail,
    String? contactNote,
  }) async {
    final response = await _db
        .from('concern_tickets')
        .insert({
          'category': category.label,
          'department': category.department,
          'details': details,
          'reference_code': referenceCode,
          'user_id': _db.auth.currentUser?.id,
          'status': 'open',
          'contact_name': contactName,
          'contact_number': contactNumber,
          'contact_address': contactAddress,
          'contact_email': contactEmail,
          'contact_note': contactNote,
        })
        .select()
        .single();
    return response;
  }

  /// Creates a silent ghost ticket for live-agent sessions.
  /// User never sees this — fires in the background.
  Future<Map<String, dynamic>> createGhostTicket({
    required ConcernCategory category,
    required String referenceCode,
  }) async {
    final response = await _db
        .from('concern_tickets')
        .insert({
          'category': category.label,
          'department': category.department,
          'details': 'Live agent request',
          'reference_code': referenceCode,
          'user_id': _db.auth.currentUser?.id,
          'status': 'open',
          'is_ghost': true,
        })
        .select()
        .single();
    return response;
  }

  /// Creates a concern ticket linked to an existing report (follow-up flow).
  /// Called automatically when citizen taps "Chat with agent" from a report.
  Future<Map<String, dynamic>> createFollowUpTicket({
    required String reportId,
    required String category,
    required String department,
    required String referenceCode,
  }) async {
    final response = await _db
        .from('concern_tickets')
        .insert({
          'category': category,
          'department': department,
          'details': 'Follow-up on report $referenceCode',
          'reference_code': referenceCode,
          'user_id': _db.auth.currentUser?.id,
          'status': 'open',
          'report_id': reportId,
          'is_ghost': true,
        })
        .select()
        .single();
    return response;
  }

  /// Fetches the logged-in citizen's contact details for attaching to a ticket.
  /// Returns assembled name, number, address, and email (email from auth).
  Future<Map<String, String?>> getCitizenContact() async {
    final user = _db.auth.currentUser;
    if (user == null) return {};

    String? name, number, address;
    try {
      final row = await _db
          .from('citizen_details')
          .select(
            'first_name, middle_name, last_name, contact_number, street, barangay',
          )
          .eq('user_id', user.id)
          .maybeSingle();

      if (row != null) {
        final parts = [
          row['first_name'],
          row['middle_name'],
          row['last_name'],
        ].where((p) => p != null && (p as String).trim().isNotEmpty).join(' ');
        name = parts.isEmpty ? null : parts;

        number = (row['contact_number'] as String?)?.trim();

        final addr = [
          row['street'],
          row['barangay'],
        ].where((p) => p != null && (p as String).trim().isNotEmpty).join(', ');
        address = addr.isEmpty ? null : addr;
      }
    } catch (e) {
      debugPrint('getCitizenContact: $e');
    }

    return {
      'name': name,
      'number': number,
      'address': address,
      'email': user.email, // from the auth account
    };
  }

  /// Deletes a ghost ticket if it was never converted to a real concern.
  Future<void> deleteGhostTicketIfUnused(String ticketId) async {
    try {
      await _db
          .from('concern_tickets')
          .delete()
          .eq('id', ticketId)
          .eq('is_ghost', true);
    } catch (e) {
      debugPrint('deleteGhostTicket: $e');
    }
  }

  // ── Ticket query ───────────────────────────────────────────────────────────

  /// Returns all tickets for a citizen, newest first.
  Future<List<Map<String, dynamic>>> getTicketsForCitizen(
    String citizenId,
  ) async {
    final response = await _db
        .from('concern_tickets')
        .select()
        .eq('user_id', citizenId)
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(response);
  }

  /// Returns a single ticket by its ID.
  Future<Map<String, dynamic>?> getTicketById(String ticketId) async {
    final response = await _db
        .from('concern_tickets')
        .select()
        .eq('id', ticketId)
        .maybeSingle();

    return response;
  }

  // ── Staff assignment ───────────────────────────────────────────────────────

  /// Finds an available staff member for the given department.
  /// Reads `admin_profiles` (staff rows carry department + is_online), returning
  /// the user_id of an online staff member, or null when nobody is on duty (the
  /// bot then handles the concern).
  Future<String?> findAvailableStaffId(String department) async {
    if (department.isEmpty) return null;
    try {
      final rows = await _db
          .from('admin_profiles')
          .select('user_id')
          .eq('department', department)
          .eq('is_online', true)
          .limit(1);
      if (rows.isNotEmpty) {
        return rows.first['user_id']?.toString();
      }
      return null;
    } catch (e) {
      debugPrint('findAvailableStaffId: $e');
      return null; // no on-duty staff → treat as nobody online
    }
  }

  /// Assigns a staff member to an existing ticket.
  Future<void> assignStaff({
    required String ticketId,
    required String staffUserId,
  }) async {
    await _db
        .from('concern_tickets')
        .update({'assigned_staff_id': staffUserId})
        .eq('id', ticketId);
  }

  /// Promotes a ghost ticket to a real, assigned live-agent ticket.
  /// Flips is_ghost → false, assigns staff, and fills the citizen's contact
  /// columns from their profile — UNLESS the chat is anonymous.
  ///
  /// A follow-up chat about an anonymous report stays anonymous: the citizen
  /// chose to withhold their identity, so the staff member must never see it.
  /// Anonymity is derived from the linked report (not trusted from the client),
  /// so it holds even if the caller doesn't flag it.
  Future<void> promoteTicket({
    required String ticketId,
    required String staffUserId,
  }) async {
    final anonymous = await _isTicketAnonymous(ticketId);

    final update = <String, dynamic>{
      'assigned_staff_id': staffUserId,
      'is_ghost': false,
      'updated_at': DateTime.now().toIso8601String(),
    };

    if (anonymous) {
      // Never attach personal data to an anonymous chat; strip any that leaked.
      update['is_anonymous'] = true;
      update['contact_name'] = null;
      update['contact_number'] = null;
      update['contact_address'] = null;
      update['contact_email'] = null;
    } else {
      final contact = await getCitizenContact();
      update['contact_name'] = contact['name'];
      update['contact_number'] = contact['number'];
      update['contact_address'] = contact['address'];
      update['contact_email'] = contact['email'];
    }

    await _db.from('concern_tickets').update(update).eq('id', ticketId);
  }

  /// True when a ticket must stay anonymous — either already flagged, or linked
  /// to an anonymous report. Read failures fail safe (treated as NOT anonymous
  /// only when we truly can't tell — here we default false but the report check
  /// is best-effort so a linked anonymous report still wins).
  Future<bool> _isTicketAnonymous(String ticketId) async {
    try {
      final t = await _db
          .from('concern_tickets')
          .select('is_anonymous, report_id')
          .eq('id', ticketId)
          .maybeSingle();
      if (t == null) return false;
      if (t['is_anonymous'] == true) return true;
      final reportId = t['report_id']?.toString();
      if (reportId == null) return false;
      final r = await _db
          .from('reports')
          .select('is_anonymous')
          .eq('id', reportId)
          .maybeSingle();
      return (r?['is_anonymous'] as bool?) ?? false;
    } catch (e) {
      debugPrint('_isTicketAnonymous: $e');
      return false;
    }
  }

  /// Live "agent rating" for the citizen chat header: the average of every
  /// citizen's post-chat star rating + how many ratings it's based on. Reads a
  /// SECURITY DEFINER RPC (`agent_avg_rating`) because RLS otherwise hides other
  /// citizens' tickets — the RPC returns only the aggregate, never any rows.
  /// Returns null on any error / before the RPC is deployed, so the header can
  /// fall back gracefully.
  Future<({double avg, int count})?> fetchAgentRating() async {
    try {
      final res = await _db.rpc('agent_avg_rating');
      final row = (res is List && res.isNotEmpty)
          ? res.first as Map<String, dynamic>
          : (res is Map<String, dynamic> ? res : null);
      if (row == null) return null;
      final avg = (row['avg'] as num?)?.toDouble() ?? 0;
      final count = (row['cnt'] as num?)?.toInt() ?? 0;
      return (avg: avg, count: count);
    } catch (e) {
      debugPrint('fetchAgentRating: $e');
      return null;
    }
  }

  /// The assigned staff member's public identity (name + photo + department) for
  /// a ticket the citizen owns — used to show the real person in the chat header
  /// once connected. Reads the `ticket_agent` SECURITY DEFINER RPC (citizens
  /// can't read admin_profiles directly). Null before the RPC is deployed, when
  /// nobody's assigned, or on any error.
  Future<({String? name, String? photoUrl, String? department})?>
      fetchTicketAgent(String ticketId) async {
    try {
      final res = await _db.rpc('ticket_agent', params: {'p_ticket': ticketId});
      final row = (res is List && res.isNotEmpty)
          ? res.first as Map<String, dynamic>
          : (res is Map<String, dynamic> ? res : null);
      if (row == null) return null;
      return (
        name: (row['full_name'] as String?)?.trim(),
        photoUrl: (row['photo_url'] as String?)?.trim(),
        department: (row['department'] as String?)?.trim(),
      );
    } catch (e) {
      debugPrint('fetchTicketAgent: $e');
      return null;
    }
  }

  /// The current status of a ticket — used to catch a chat that the staff ended
  /// while the citizen's app was closed (the realtime status channel only sees
  /// live changes, so a one-shot read on reconnect fills the gap).
  Future<String?> fetchTicketStatus(String ticketId) async {
    try {
      final r = await _db
          .from('concern_tickets')
          .select('status')
          .eq('id', ticketId)
          .maybeSingle();
      return r?['status'] as String?;
    } catch (e) {
      debugPrint('fetchTicketStatus: $e');
      return null;
    }
  }

  // ── Ticket messages ────────────────────────────────────────────────────────

  /// Saves a single chat message to the ticket_messages table.
  ///
  /// Call this **only after a ticket has been created** so every row has a
  /// valid ticket_id FK. Pre-ticket greeting messages stay in Hive only.
  ///
  /// [senderType] must be one of: 'citizen' | 'bot' | 'staff'
  Future<void> saveMessage({
    required String ticketId,
    required String senderId, // citizen's user id OR 'bot'
    required String senderType, // 'citizen' | 'bot' | 'staff'
    required String message,
  }) async {
    await _db.from('ticket_messages').insert({
      'ticket_id': ticketId,
      'sender_id': senderId,
      'sender_type': senderType,
      'text': message, // ← ticket_messages content column is `text`, not `message`
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// Returns all messages for a ticket, oldest first.
  Future<List<Map<String, dynamic>>> getMessagesForTicket(
    String ticketId,
  ) async {
    final response = await _db
        .from('ticket_messages')
        .select()
        .eq('ticket_id', ticketId)
        .order('created_at', ascending: true);

    return List<Map<String, dynamic>>.from(response);
  }

  /// Returns upcoming Aparri events, soonest first.
  Future<List<Map<String, dynamic>>> getLatestEvents({int limit = 5}) async {
    try {
      final today = DateTime.now().toIso8601String().split('T').first;
      final rows = await _db
          .from('events')
          .select(
            'title, event_date, event_time, location, category, description',
          )
          .gte('event_date', today)
          .order('event_date', ascending: true)
          .limit(limit);
      return List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      debugPrint('getLatestEvents: $e');
      return [];
    }
  }

  // ── Ticket attachments ─────────────────────────────────────────────────────

  /// Uploads a photo to Supabase Storage and inserts a row in
  /// ticket_attachments. Returns the public URL of the uploaded file.
  ///
  /// Bucket name: ticket-attachments (10 MB limit, jpeg/png/webp/heic)
  Future<String> saveAttachment({
    required String ticketId,
    required String uploaderId, // citizen's user id
    required File file,
    required String mimeType, // e.g. 'image/jpeg'
  }) async {
    // Build a unique storage path: ticketId/timestamp_filename
    final fileName = file.path.split('/').last;
    final storagePath =
        '$ticketId/${DateTime.now().millisecondsSinceEpoch}_$fileName';

    // 1. Upload to Storage
    await _db.storage
        .from('ticket-attachments')
        .upload(
          storagePath,
          file,
          fileOptions: FileOptions(contentType: mimeType, upsert: false),
        );

    // 2. Get public URL
    final publicUrl = _db.storage
        .from('ticket-attachments')
        .getPublicUrl(storagePath);

    // 3. Insert metadata row in ticket_attachments
    await _db.from('ticket_attachments').insert({
      'ticket_id': ticketId,
      'uploader_id': uploaderId,
      'storage_path': storagePath,
      'public_url': publicUrl,
      'mime_type': mimeType,
      'created_at': DateTime.now().toIso8601String(),
    });

    return publicUrl;
  }

  RealtimeChannel subscribeToTicketMessages({
    required String ticketId,
    required void Function(Map<String, dynamic> row) onInsert,
  }) {
    return _db
        .channel('ticket_messages:$ticketId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'ticket_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'ticket_id',
            value: ticketId,
          ),
          callback: (payload) => onInsert(payload.newRecord),
        )
        .subscribe();
  }

  /// Watches a ticket's row for status changes so the citizen chat learns when
  /// a staff member ends the conversation (status → resolved / ended / closed).
  RealtimeChannel subscribeToTicketStatus({
    required String ticketId,
    required void Function(String status) onStatus,
  }) {
    return _db
        .channel('ticket_status:$ticketId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'concern_tickets',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: ticketId,
          ),
          callback: (payload) {
            final s = payload.newRecord['status'] as String?;
            if (s != null) onStatus(s);
          },
        )
        .subscribe();
  }

  /// Records the citizen's post-chat rating (1–5) for a ticket they own, via a
  /// SECURITY DEFINER RPC (rate_ticket) so no broad update policy is needed.
  Future<void> rateTicket(
    String ticketId,
    int rating, {
    String? comment,
  }) async {
    await _db.rpc(
      'rate_ticket',
      params: {
        'p_ticket_id': ticketId,
        'p_rating': rating,
        'p_comment': comment,
      },
    );
  }
}
