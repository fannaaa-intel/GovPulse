import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/widgets/Home/Chat-agent/chat_models.dart';

/// Wraps every Supabase call related to concern tickets.
///
/// This is the **only** layer that knows about Supabase tables for tickets.
/// ChatService talks to this class, never directly to Supabase. That way,
/// when we add live agent routing in Phase 2, we only edit this file —
/// the chat logic stays untouched.
class TicketRepository {
  TicketRepository._();
  static final TicketRepository I = TicketRepository._();

  SupabaseClient get _sb => Supabase.instance.client;

  // ── CREATE ───────────────────────────────────────────────────────────────

  /// Insert a new ticket. Returns the created row's data including the
  /// server-side `id` and timestamps.
  ///
  /// Throws on failure — caller should catch and surface a friendly error.
  Future<TicketRecord> createTicket({
    required ConcernCategory category,
    required String details,
    required String referenceCode,
  }) async {
    final user = _sb.auth.currentUser;
    if (user == null) {
      throw const TicketException('You must be signed in to submit a concern.');
    }

    final row = await _sb
        .from('concern_tickets')
        .insert({
          'reference_code': referenceCode,
          'user_id': user.id,
          'category': category.name, // enum name, e.g. 'wasteGarbage'
          'department': category.department,
          'details': details,
          'status': 'open',
        })
        .select()
        .single();

    return TicketRecord.fromJson(row);
  }

  // ── READ ─────────────────────────────────────────────────────────────────

  /// Fetch a single ticket by its id. Returns null if not found.
  Future<TicketRecord?> getTicket(String id) async {
    final row = await _sb
        .from('concern_tickets')
        .select()
        .eq('id', id)
        .maybeSingle();
    return row == null ? null : TicketRecord.fromJson(row);
  }

  /// Fetch all tickets for the current user, newest first.
  /// Use this later for a "My Submissions" screen.
  Future<List<TicketRecord>> listMyTickets() async {
    final user = _sb.auth.currentUser;
    if (user == null) return const [];

    final rows = await _sb
        .from('concern_tickets')
        .select()
        .eq('user_id', user.id)
        .order('created_at', ascending: false);

    return (rows as List)
        .map((r) => TicketRecord.fromJson(Map<String, dynamic>.from(r)))
        .toList();
  }

  // ── STAFF ROUTING (Phase 2 — currently always returns null) ─────────────

  /// Returns the id of an available staff member for this category's
  /// department, or null if nobody is online and free.
  ///
  /// In Phase 1 this just returns null because no staff are onboarded yet.
  /// In Phase 2 you build a staff app that flips `is_online` and increments
  /// `active_conversations` — this query will start returning rows naturally.
  Future<String?> findAvailableStaffId(ConcernCategory category) async {
    try {
      final row = await _sb
          .from('lgu_staff')
          .select('user_id')
          .eq('department', category.department)
          .eq('is_online', true)
          .eq('is_available', true)
          .lt('active_conversations', 3) // simple capacity check
          .order('active_conversations', ascending: true)
          .limit(1)
          .maybeSingle();

      return row?['user_id'] as String?;
    } catch (_) {
      // Routing failure should never block ticket creation.
      return null;
    }
  }

  // ── UPDATE (used by Phase 2 staff app — included for symmetry) ──────────

  Future<void> assignStaff({
    required String ticketId,
    required String staffUserId,
  }) async {
    await _sb
        .from('concern_tickets')
        .update({'assigned_staff_id': staffUserId, 'status': 'in_progress'})
        .eq('id', ticketId);
  }
}

// ── Models ──────────────────────────────────────────────────────────────────

/// A persisted ticket as it lives in Supabase.
class TicketRecord {
  final String id;
  final String referenceCode;
  final String userId;
  final String category; // enum name string
  final String department;
  final String details;
  final String status; // 'open' | 'in_progress' | 'resolved' | 'closed'
  final String? assignedStaffId;
  final DateTime createdAt;

  TicketRecord({
    required this.id,
    required this.referenceCode,
    required this.userId,
    required this.category,
    required this.department,
    required this.details,
    required this.status,
    required this.assignedStaffId,
    required this.createdAt,
  });

  factory TicketRecord.fromJson(Map<String, dynamic> j) => TicketRecord(
    id: j['id'] as String,
    referenceCode: j['reference_code'] as String,
    userId: j['user_id'] as String,
    category: j['category'] as String,
    department: j['department'] as String,
    details: j['details'] as String,
    status: j['status'] as String,
    assignedStaffId: j['assigned_staff_id'] as String?,
    createdAt: DateTime.parse(j['created_at'] as String),
  );
}

/// Friendly exception so ChatService can show a nice error to the user.
class TicketException implements Exception {
  final String message;
  const TicketException(this.message);
  @override
  String toString() => message;
}
