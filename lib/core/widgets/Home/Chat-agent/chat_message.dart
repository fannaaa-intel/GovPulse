enum MessageStatus { sent, delivered, seen }

class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime time;
  MessageStatus status;

  ChatMessage({
    required this.text,
    required this.isUser,
    required this.time,
    this.status = MessageStatus.sent,
  });
}
