// `failed` kept last so its index matches chat_models.dart's MessageStatus
// (chat_agent_screen maps the two enums by index).
enum MessageStatus { sent, delivered, seen, failed }

class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime time;
  MessageStatus status;

  /// True when an agent reply came from the on-device fallback brain.
  final bool offline;

  /// True when this incoming message came from a live staff member (vs the bot).
  final bool fromStaff;

  ChatMessage({
    required this.text,
    required this.isUser,
    required this.time,
    this.status = MessageStatus.sent,
    this.offline = false,
    this.fromStaff = false,
  });
}
