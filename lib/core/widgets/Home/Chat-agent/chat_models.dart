// lib/widgets/Home/Chat-agent/chat_models.dart

enum MessageStatus { sent, delivered, seen }

enum ConversationStage {
  greeting,
  awaitingCategory,
  awaitingDetails,
  submitting,
  ticketCreated,
  connectedToAgent,
  timedOut,
  followUp,
  awaitingIntent,
  askingQuestion,
  confirmingContact,
  correctingContact,
  ended,
}

enum ConcernCategory {
  roadInfrastructure,
  wasteGarbage,
  drainageFlooding,
  streetlightOutage,
  environmentPollution,
  others;

  String get label => switch (this) {
    ConcernCategory.roadInfrastructure => 'Road & Infrastructure',
    ConcernCategory.wasteGarbage => 'Waste & Garbage',
    ConcernCategory.drainageFlooding => 'Drainage & Flooding',
    ConcernCategory.streetlightOutage => 'Streetlight Outage',
    ConcernCategory.environmentPollution => 'Environment & Pollution',
    ConcernCategory.others => 'Others',
  };

  String get department => switch (this) {
    ConcernCategory.roadInfrastructure => 'Engineering Office',
    ConcernCategory.wasteGarbage => 'Sanitation Office',
    ConcernCategory.drainageFlooding => 'Engineering Office',
    ConcernCategory.streetlightOutage => 'Engineering Office',
    ConcernCategory.environmentPollution => 'Environment Office',
    ConcernCategory.others => "Mayor's Office",
  };
}

// ── ChatIntent ────────────────────────────────────────────────────────────────
// "Report Issue" is intentionally removed here.
// Citizens report issues via the Quick Action button on the Home screen.
// The chat menu only offers: Ask a question | Talk to a person.
// Free-text detection (e.g. "gusto ko mag-report") still triggers
// [ACTION:REPORT] from the AI and routes to the category picker automatically.
enum ChatIntent {
  question,
  liveAgent;

  String get label => switch (this) {
    ChatIntent.question => 'Ask a question',
    ChatIntent.liveAgent => 'Talk to a person',
  };
}

class TicketException implements Exception {
  final String message;
  const TicketException(this.message);
}

class ChatMsg {
  final String text;
  final bool isUser;
  final DateTime time;
  MessageStatus status;
  final String? attachmentPath;

  /// True when this agent reply was produced by the on-device fallback brain
  /// (AI unavailable). The bubble shows an "answered on-device" chip.
  final bool offline;

  ChatMsg({
    required this.text,
    required this.isUser,
    required this.time,
    this.status = MessageStatus.sent,
    this.attachmentPath,
    this.offline = false,
  });

  Map<String, dynamic> toJson() => {
    'text': text,
    'isUser': isUser,
    'time': time.toIso8601String(),
    'status': status.index,
    'attachmentPath': attachmentPath,
    'offline': offline,
  };

  factory ChatMsg.fromJson(Map<String, dynamic> j) => ChatMsg(
    text: j['text'] as String,
    isUser: j['isUser'] as bool,
    time: DateTime.parse(j['time'] as String),
    status: MessageStatus.values[j['status'] as int],
    attachmentPath: j['attachmentPath'] as String?,
    offline: j['offline'] as bool? ?? false,
  );
}
