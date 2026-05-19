// ── Message delivery status ──────────────────────────────────────────────────
enum MessageStatus { sent, delivered, seen }

enum ConversationStage {
  greeting, // bot is introducing itself
  awaitingCategory, // waiting for user to pick a concern category
  awaitingDetails, // waiting for user to describe the concern
  submitting, // creating the ticket in Supabase
  ticketCreated, // ticket saved; no live agent available
  connectedToAgent, // (Phase 2) handed off to live staff
  timedOut, // 15-min idle reset
}

// ── Concern categories ───────────────────────────────────────────────────────
enum ConcernCategory {
  roadInfrastructure,
  wasteGarbage,
  drainageFlooding,
  streetlightOutage,
  environmentPollution,
  others,
}

extension ConcernCategoryX on ConcernCategory {
  String get label => switch (this) {
    ConcernCategory.roadInfrastructure => 'Road & Infrastructure',
    ConcernCategory.wasteGarbage => 'Waste & Garbage',
    ConcernCategory.drainageFlooding => 'Drainage & Flooding',
    ConcernCategory.streetlightOutage => 'Streetlight Outage',
    ConcernCategory.environmentPollution => 'Environment & Pollution',
    ConcernCategory.others => 'Others',
  };

  /// Which LGU office handles this category — used for routing.
  String get department => switch (this) {
    ConcernCategory.roadInfrastructure => 'Engineering Office',
    ConcernCategory.wasteGarbage => 'Sanitation & Waste Management',
    ConcernCategory.drainageFlooding => 'Public Works Department',
    ConcernCategory.streetlightOutage => 'Electrical Division',
    ConcernCategory.environmentPollution => 'ENRO',
    ConcernCategory.others => "Mayor's Action Center",
  };
}

// ── Chat message model ───────────────────────────────────────────────────────
class ChatMsg {
  final String text;
  final bool isUser;
  final DateTime time;
  MessageStatus status;

  ChatMsg({
    required this.text,
    required this.isUser,
    required this.time,
    this.status = MessageStatus.sent,
  });

  Map<String, dynamic> toJson() => {
    'text': text,
    'isUser': isUser,
    'time': time.toIso8601String(),
    'status': status.index,
  };

  factory ChatMsg.fromJson(Map<String, dynamic> j) => ChatMsg(
    text: j['text'] as String,
    isUser: j['isUser'] as bool,
    time: DateTime.parse(j['time'] as String),
    status: MessageStatus.values[j['status'] as int],
  );
}
