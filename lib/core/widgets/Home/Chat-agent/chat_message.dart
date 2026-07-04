enum MessageStatus { sent, delivered, seen }

class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime time;
  MessageStatus status;

  /// True when an agent reply came from the on-device fallback brain.
  final bool offline;

  ChatMessage({
    required this.text,
    required this.isUser,
    required this.time,
    this.status = MessageStatus.sent,
    this.offline = false,
  });
}
