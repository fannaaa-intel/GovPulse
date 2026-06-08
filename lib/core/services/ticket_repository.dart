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
  /// Returns null when no staff is online (Phase 1: bot handles everything).
  Future<String?> findAvailableStaffId(String department) async {
    try {
      final rows = await _db
          .from('staff') // ← adjust to your real staff table name
          .select('id')
          .eq('department', department)
          .eq('is_online', true)
          .limit(1);
      if (rows.isNotEmpty) {
        return rows.first['id']?.toString();
      }
      return null;
    } catch (e) {
      debugPrint('findAvailableStaffId: $e');
      return null; // staff table not built yet → treat as nobody online
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
  /// columns from their profile (only real tickets ever carry personal data).
  Future<void> promoteTicket({
    required String ticketId,
    required String staffUserId,
  }) async {
    final contact = await getCitizenContact();
    await _db
        .from('concern_tickets')
        .update({
          'assigned_staff_id': staffUserId,
          'is_ghost': false,
          'contact_name': contact['name'],
          'contact_number': contact['number'],
          'contact_address': contact['address'],
          'contact_email': contact['email'],
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', ticketId);
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
      'message': message,
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
}
