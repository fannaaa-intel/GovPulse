enum MessageStatus { sent, delivered, seen }

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
}
