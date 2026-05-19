import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import 'chat_message.dart';
import 'typing_dots.dart';

const _kTextPri = Color(0xFF111827);

class ChatMessageBubble extends StatelessWidget {
  final double width;
  final ChatMessage message;
  final String Function(DateTime) formatTime;

  const ChatMessageBubble({
    super.key,
    required this.width,
    required this.message,
    required this.formatTime,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    return Padding(
      padding: EdgeInsets.only(bottom: width * 0.024),
      child: Row(
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // ── Agent avatar ────────────────────────────────────────────────
          if (!isUser) ...[
            _AgentAvatar(width: width),
            SizedBox(width: width * 0.018),
          ],

          // ── Bubble + timestamp ──────────────────────────────────────────
          Flexible(
            child: Column(
              crossAxisAlignment: isUser
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: width * 0.038,
                    vertical: width * 0.026,
                  ),
                  constraints: BoxConstraints(maxWidth: width * 0.68),
                  decoration: BoxDecoration(
                    color: isUser ? AppColors.primaryBlue : Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(width * 0.040),
                      topRight: Radius.circular(width * 0.040),
                      bottomLeft: Radius.circular(
                        isUser ? width * 0.040 : width * 0.006,
                      ),
                      bottomRight: Radius.circular(
                        isUser ? width * 0.006 : width * 0.040,
                      ),
                    ),
                    border: isUser
                        ? null
                        : Border.all(color: AppColors.stroke, width: 1),
                  ),
                  child: Text(
                    message.text,
                    style: TextStyle(
                      fontSize: width * 0.034,
                      color: isUser ? Colors.white : _kTextPri,
                      height: 1.55,
                    ),
                  ),
                ),
                SizedBox(height: width * 0.007),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: width * 0.01),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        formatTime(message.time),
                        style: TextStyle(
                          fontSize: width * 0.023,
                          color: AppColors.hint,
                          letterSpacing: 0.1,
                        ),
                      ),
                      if (isUser) ...[
                        SizedBox(width: width * 0.010),
                        MessageStatusTicks(
                          status: message.status,
                          width: width,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          if (isUser) SizedBox(width: width * 0.014),
        ],
      ),
    );
  }
}

// ── Typing bubble ─────────────────────────────────────────────────────────────
class ChatTypingBubble extends StatelessWidget {
  final double width;
  const ChatTypingBubble({super.key, required this.width});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: width * 0.024),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _AgentAvatar(width: width),
          SizedBox(width: width * 0.018),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: width * 0.038,
              vertical: width * 0.028,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(width * 0.040),
                topRight: Radius.circular(width * 0.040),
                bottomLeft: Radius.circular(width * 0.006),
                bottomRight: Radius.circular(width * 0.040),
              ),
              border: Border.all(color: AppColors.stroke, width: 1),
            ),
            child: TypingDots(width: width),
          ),
        ],
      ),
    );
  }
}

// ── Shared agent avatar ───────────────────────────────────────────────────────
class _AgentAvatar extends StatelessWidget {
  final double width;
  const _AgentAvatar({required this.width});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width * 0.078,
      height: width * 0.078,
      decoration: BoxDecoration(
        color: AppColors.primaryBlue.withValues(alpha: 0.10),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Image.asset(
          'assets/images/customer.png',
          width: width * 0.042,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => Icon(
            Icons.support_agent_rounded,
            size: width * 0.042,
            color: AppColors.primaryBlue,
          ),
        ),
      ),
    );
  }
}

// ── Message status ticks ──────────────────────────────────────────────────────
class MessageStatusTicks extends StatelessWidget {
  final MessageStatus status;
  final double width;
  const MessageStatusTicks({
    super.key,
    required this.status,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    final color = status == MessageStatus.seen
        ? AppColors.primaryBlue
        : AppColors.hint;
    final isDouble = status != MessageStatus.sent;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: isDouble
          ? SizedBox(
              key: ValueKey('double-${color.toARGB32()}'),
              width: width * 0.042,
              height: width * 0.028,
              child: Stack(
                children: [
                  Positioned(
                    left: 0,
                    child: Icon(
                      Icons.check_rounded,
                      size: width * 0.028,
                      color: color,
                    ),
                  ),
                  Positioned(
                    left: width * 0.012,
                    child: Icon(
                      Icons.check_rounded,
                      size: width * 0.028,
                      color: color,
                    ),
                  ),
                ],
              ),
            )
          : Icon(
              key: const ValueKey('single'),
              Icons.check_rounded,
              size: width * 0.028,
              color: color,
            ),
    );
  }
}
