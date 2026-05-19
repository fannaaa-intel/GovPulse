import 'package:supabase_flutter/supabase_flutter.dart';

// ─── Model ────────────────────────────────────────────────────────────────────

enum EventStatus { pending, approved, rejected }

class EventModel {
  final String id;
  final String title;
  final String location;
  final DateTime eventDate;
  final String eventTime;
  final String category;
  final String categoryColor;
  final bool isFeatured;
  final String? imageUrl;
  final EventStatus status;
  final String createdBy;
  final String? reviewedBy;
  final DateTime createdAt;

  const EventModel({
    required this.id,
    required this.title,
    required this.location,
    required this.eventDate,
    required this.eventTime,
    required this.category,
    required this.categoryColor,
    required this.isFeatured,
    this.imageUrl,
    required this.status,
    required this.createdBy,
    this.reviewedBy,
    required this.createdAt,
  });

  factory EventModel.fromJson(Map<String, dynamic> json) {
    return EventModel(
      id: json['id'] as String,
      title: json['title'] as String,
      location: json['location'] as String,
      eventDate: DateTime.parse(json['event_date'] as String),
      eventTime: json['event_time'] as String,
      category: json['category'] as String,
      categoryColor: json['category_color'] as String,
      isFeatured: json['is_featured'] as bool,
      imageUrl: json['image_url'] as String?,
      status: EventStatus.values.firstWhere(
        (s) => s.name == (json['status'] as String),
        orElse: () => EventStatus.pending,
      ),
      createdBy: json['created_by'] as String,
      reviewedBy: json['reviewed_by'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toInsertJson() => {
    'title': title,
    'location': location,
    'event_date': eventDate.toIso8601String().substring(0, 10),
    'event_time': eventTime,
    'category': category,
    'category_color': categoryColor,
    'is_featured': isFeatured,
    if (imageUrl != null) 'image_url': imageUrl,
    // status defaults to 'pending' on the DB side for staff;
    // admin can pass 'approved' explicitly.
    'status': status.name,
    'created_by': createdBy,
  };
}

// ─── Service ──────────────────────────────────────────────────────────────────

class EventsService {
  EventsService._();
  static final EventsService instance = EventsService._();

  final _client = Supabase.instance.client;

  // ── READ ──────────────────────────────────────────────────────────────────

  /// Citizens & unauthenticated users: RLS already filters to approved only.
  /// Staff: sees approved + own pending (also handled by RLS).
  /// Admin: sees everything.
  Future<List<EventModel>> fetchEvents({
    String? category,
    String? searchQuery,
  }) async {
    var query = _client.from('events').select();

    if (category != null && category != 'All') {
      query = query.eq('category', category);
    }

    if (searchQuery != null && searchQuery.isNotEmpty) {
      query = query.or(
        'title.ilike.%$searchQuery%,'
        'location.ilike.%$searchQuery%,'
        'category.ilike.%$searchQuery%',
      );
    }

    final response = await query.order('event_date', ascending: true);
    return (response as List).map((e) => EventModel.fromJson(e)).toList();
  }

  /// Admin: fetch all pending events awaiting review.
  Future<List<EventModel>> fetchPendingEvents() async {
    final response = await _client
        .from('events')
        .select()
        .eq('status', 'pending')
        .order('created_at', ascending: true);

    return (response as List).map((e) => EventModel.fromJson(e)).toList();
  }

  // ── CREATE ────────────────────────────────────────────────────────────────

  /// Staff: inserts event with status = 'pending'.
  /// Admin: inserts event with status = 'approved' (published immediately).
  Future<EventModel> createEvent(EventModel event) async {
    final data = event.toInsertJson();

    final response = await _client
        .from('events')
        .insert(data)
        .select()
        .single();

    return EventModel.fromJson(response);
  }

  // ── UPDATE ────────────────────────────────────────────────────────────────

  /// Admin approves an event.
  Future<void> approveEvent(String eventId) async {
    final adminId = _client.auth.currentUser?.id;
    await _client
        .from('events')
        .update({'status': 'approved', 'reviewed_by': adminId})
        .eq('id', eventId);
  }

  /// Admin rejects an event.
  Future<void> rejectEvent(String eventId) async {
    final adminId = _client.auth.currentUser?.id;
    await _client
        .from('events')
        .update({'status': 'rejected', 'reviewed_by': adminId})
        .eq('id', eventId);
  }

  /// Admin: update any field on an event.
  /// Staff: can only update their own pending events (RLS enforces this).
  Future<EventModel> updateEvent(
    String eventId,
    Map<String, dynamic> fields,
  ) async {
    final response = await _client
        .from('events')
        .update(fields)
        .eq('id', eventId)
        .select()
        .single();

    return EventModel.fromJson(response);
  }

  // ── DELETE ────────────────────────────────────────────────────────────────

  /// Admin only. RLS blocks this for all other roles.
  Future<void> deleteEvent(String eventId) async {
    await _client.from('events').delete().eq('id', eventId);
  }

  // ── REALTIME ──────────────────────────────────────────────────────────────

  /// Subscribe to live event changes (useful for the admin review panel).
  RealtimeChannel subscribeToEvents({
    required void Function(List<EventModel> events) onUpdate,
  }) {
    return _client
        .channel('events-changes')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'events',
          callback: (_) async {
            // Re-fetch on any change; simple and safe.
            final fresh = await fetchEvents();
            onUpdate(fresh);
          },
        )
        .subscribe();
  }
}

// ─── Role helpers ─────────────────────────────────────────────────────────────

enum UserRole { admin, staff, citizen }

class UserService {
  UserService._();
  static final UserService instance = UserService._();

  final _client = Supabase.instance.client;

  Future<UserRole> currentRole() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return UserRole.citizen;

    final response = await _client
        .from('profiles')
        .select('role')
        .eq('id', uid)
        .single();

    return UserRole.values.firstWhere(
      (r) => r.name == (response['role'] as String),
      orElse: () => UserRole.citizen,
    );
  }
}
