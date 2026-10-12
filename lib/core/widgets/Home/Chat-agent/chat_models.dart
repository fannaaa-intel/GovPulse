// lib/widgets/Home/Chat-agent/chat_models.dart

// `failed` MUST stay last so its index (3) matches chat_message.dart's enum —
// chat_agent_screen maps between them by index — and so persisted status indices
// (0..2) stay stable.
enum MessageStatus { sent, delivered, seen, failed }

// Persisted to Hive BY INDEX — never reorder or delete a value. The live-staff
// stages (awaitingCategory, awaitingDetails, submitting, ticketCreated,
// connectedToAgent, confirmingContact, correctingContact) are retired since the
// 2026-10-12 panel revision; ChatService._readStage maps a cached one out.
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

  // A cached message from the live-chat era may still carry `fromStaff`; it is
  // ignored, and the bubble renders as Kuya Gov's.
  factory ChatMsg.fromJson(Map<String, dynamic> j) => ChatMsg(
    text: j['text'] as String,
    isUser: j['isUser'] as bool,
    time: DateTime.parse(j['time'] as String),
    status: MessageStatus.values[j['status'] as int],
    attachmentPath: j['attachmentPath'] as String?,
    offline: j['offline'] as bool? ?? false,
  );
}
