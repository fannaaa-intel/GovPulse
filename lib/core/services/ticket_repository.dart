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

  // getCitizenContact was REMOVED in phase 2 of migration 20260722000005. It
  // read the citizen's own citizen_details row on the client to fill a ticket's
  // contact_* columns during promoteTicket. That derivation now happens inside
  // the promote_ticket() SECURITY DEFINER RPC, so the client no longer touches
  // citizen_details for this at all. If you need contact details on the client
  // again, prefer a definer RPC that returns exactly what the caller may see.

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
  /// Returns the user_id of an online staff member, or null when nobody is on
  /// duty (the bot then handles the concern).
  ///
  /// Goes through the `find_available_staff` SECURITY DEFINER RPC rather than
  /// reading `admin_profiles` directly. That table used to carry a
  /// `for select to public using (true)` policy, which made the entire officials
  /// directory — names, departments, photos, `is_online`, `last_seen_at` —
  /// readable by anyone holding the anon key shipped in the APK. This call site
  /// was that policy's only legitimate consumer, so the policy was dropped and
  /// replaced with an RPC that answers just this question and returns nothing
  /// else. Citizens have no direct read on `admin_profiles`.
  ///
  /// NOTE the failure mode: the catch below returns null, which the caller
  /// treats as "nobody on duty" and routes to the bot. So a broken read here
  /// does not surface as an error — it silently degrades ticket routing. If
  /// tickets stop reaching staff, check that migration 20260721000003 is
  /// applied before looking anywhere else.
  Future<String?> findAvailableStaffId(String department) async {
    if (department.isEmpty) return null;
    try {
      final res = await _db.rpc(
        'find_available_staff',
        params: {'p_department': department},
      );
      final id = res?.toString().trim() ?? '';
      return id.isEmpty ? null : id;
    } catch (e) {
      debugPrint('findAvailableStaffId: $e');
      return null; // no on-duty staff → treat as nobody online
    }
  }

  /// Assigns a staff member to an existing ticket, via the `assign_ticket_staff`
  /// SECURITY DEFINER RPC (migration 20260722000005). The old path was a raw
  /// UPDATE on concern_tickets under the citizen's own UPDATE policy — the
  /// policy that let a citizen write any column on their ticket and, composed
  /// with the DELETE gate, erase completed staff conversations. The RPC checks
  /// ownership inside, so that policy can be dropped in phase 3.
  Future<void> assignStaff({
    required String ticketId,
    required String staffUserId,
  }) async {
    await _db.rpc('assign_ticket_staff', params: {
      'p_ticket': ticketId,
      'p_staff': staffUserId,
    });
  }

  /// Promotes a ghost ticket to a real, assigned live-agent ticket, via the
  /// `promote_ticket` SECURITY DEFINER RPC (migration 20260722000005).
  ///
  /// Anonymity and the contact columns are now derived SERVER-SIDE. The old
  /// path read citizen_details from the client to fill contact_name/number/
  /// address and computed anonymity in Dart — a table the client should not
  /// need (locked down for staff in migration 20260722000003) and a trust
  /// boundary in the wrong place. A follow-up chat about an anonymous report
  /// still stays anonymous: the RPC checks the ticket's own flag OR the linked
  /// report's, so the client cannot override it.
  Future<void> promoteTicket({
    required String ticketId,
    required String staffUserId,
  }) async {
    await _db.rpc('promote_ticket', params: {
      'p_ticket': ticketId,
      'p_staff': staffUserId,
    });
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
  /// [senderType] is a parameter, but only 'citizen' is reachable through it.
  /// The single caller — chat_service._sendToStaff — passes that literal, and
  /// since 20260731000004 the INSERT policy pins sender_type to the caller's
  /// real role: a citizen writing anything else is rejected by RLS, and the
  /// staff path writes through staff_repository.sendMessage instead.
  ///
  /// 'bot' is NOT storable and never was. The CHECK constraint added by
  /// 20260731000002 admits only 'citizen' | 'staff', and [senderId] maps to a
  /// `uuid NOT NULL` column, so the shape this docstring used to describe —
  /// senderId: 'bot' — could not have been inserted. Bot turns live in Hive
  /// only; see the pre-ticket greeting note above.
  Future<void> saveMessage({
    required String ticketId,
    required String senderId, // the citizen's auth.users id; must equal auth.uid()
    required String senderType, // 'citizen' in practice — see above
    required String message,
  }) async {
    await _db.from('ticket_messages').insert({
      'ticket_id': ticketId,
      'sender_id': senderId,
      'sender_type': senderType,
      'text': message, // ← ticket_messages content column is `text`, not `message`
      // created_at omitted on purpose — the column defaults to now() so the
      // database is the single clock for the whole thread. See the matching
      // note in staff_repository.sendMessage: client-supplied local timestamps
      // stored 8 hours off and made ordering depend on device clock skew.
    });
  }

  /// Returns all messages for a ticket, oldest first.
  ///
  /// The column list is EXPLICIT and must stay that way. A bare `.select()`
  /// becomes `select *`, and since migration 20260731000003 the `authenticated`
  /// role holds SELECT on this table per-column rather than table-wide — with
  /// `sender_id` deliberately excluded, so that realtime.apply_rls omits it from
  /// the socket payload. Under a column-level grant, `select *` fails outright
  /// with 42501 rather than silently dropping the column. Do not "simplify" this
  /// back to `.select()`.
  ///
  /// `sender_id` is not listed because nothing reads it: threading and bubble
  /// sidedness key off `sender_type`.
  Future<List<Map<String, dynamic>>> getMessagesForTicket(
    String ticketId,
  ) async {
    final response = await _db
        .from('ticket_messages')
        .select('id, ticket_id, sender_type, text, created_at')
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

  // ── LGU facts (Kuya Gov grounding) ─────────────────────────────────────────

  /// Cached `lgu_facts` rows, and when they were fetched.
  ///
  /// These change on the order of an election, but [getLguFacts] is called on
  /// every single chat turn. Without a cache each message a citizen types costs
  /// an extra round trip before the Groq call even starts, which is latency the
  /// citizen feels directly while watching a typing indicator.
  List<Map<String, dynamic>>? _lguFactsCache;
  DateTime? _lguFactsFetchedAt;

  /// How long a fetched fact set stays good. Long enough that a normal
  /// conversation makes one request; short enough that an admin correcting the
  /// mayor's name sees it live without anyone restarting the app.
  static const Duration _lguFactsTtl = Duration(minutes: 15);

  /// Returns the published LGU facts used to ground the chat agent.
  ///
  /// Only rows with a non-empty `value` come back: an unfilled row carries no
  /// information the model can use, and shipping it would spend prompt tokens
  /// to tell the model something the prompt already says by default (that an
  /// absent fact must be answered with "confirm at the office"). The Groq free
  /// tier meters ~8K tokens/minute across this function and `recommend-actions`
  /// combined, so an empty row is not a free passenger.
  ///
  /// Never throws — grounding is an enhancement, and a citizen who cannot reach
  /// this table should still get the general civic knowledge base.
  Future<List<Map<String, dynamic>>> getLguFacts() async {
    final cached = _lguFactsCache;
    final fetchedAt = _lguFactsFetchedAt;
    if (cached != null &&
        fetchedAt != null &&
        DateTime.now().difference(fetchedAt) < _lguFactsTtl) {
      return cached;
    }

    try {
      final rows = await _db
          .from('lgu_facts')
          .select('key, label, value, category')
          .eq('is_published', true)
          .neq('value', '')
          .order('sort_order', ascending: true);

      final facts = List<Map<String, dynamic>>.from(rows);
      _lguFactsCache = facts;
      _lguFactsFetchedAt = DateTime.now();
      return facts;
    } catch (e) {
      debugPrint('getLguFacts: $e');
      // Serve a stale set over none: an old mayor's name is still better
      // grounding than a blank, and the TTL will refresh it on recovery.
      return cached ?? const [];
    }
  }

  /// Drops the cached facts so the next chat turn refetches.
  ///
  /// Call after an admin edits `lgu_facts`, so the person who just made the
  /// correction can verify it in chat immediately rather than waiting out
  /// [_lguFactsTtl] and wondering whether the save worked.
  void invalidateLguFacts() {
    _lguFactsCache = null;
    _lguFactsFetchedAt = null;
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
  ///
  /// [onJoined] fires every time the channel reaches `subscribed` — the FIRST
  /// join and every silent re-join after a dropped socket (backgrounded phone,
  /// tab sleep, network blip). Realtime replays nothing on rejoin, so a status
  /// change that happened while the socket was down is lost forever unless the
  /// caller re-reads it here. That gap is what made the rating card show up only
  /// after the citizen navigated away and back: the one-shot check on open was
  /// the only thing left that could see it. See ChatService._startAgentSub.
  RealtimeChannel subscribeToTicketStatus({
    required String ticketId,
    required void Function(String status) onStatus,
    void Function()? onJoined,
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
        .subscribe((status, error) {
          if (status == RealtimeSubscribeStatus.subscribed) {
            onJoined?.call();
          } else {
            // Never silent: a channel that errors or times out stops delivering
            // with no other symptom, and the poll backstop is what carries the
            // feature from here.
            debugPrint('ticket_status channel $status ${error ?? ''}');
          }
        });
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
