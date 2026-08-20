import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import 'chat_message.dart';
import 'typing_dots.dart';
import '../../../../core/theme/citizen_ui.dart';

const _kTextPri = Color(0xFF111827);

class ChatMessageBubble extends StatelessWidget {
  final double width;
  final ChatMessage message;
  final String Function(DateTime) formatTime;

  /// Wired only for the citizen's own messages so a failed send can be retried
  /// or removed. Null elsewhere (e.g. the compact floating panel).
  final VoidCallback? onResend;
  final VoidCallback? onDelete;

  /// The connected staff member's photo (for their bubbles) and the citizen's
  /// own photo (for outgoing bubbles). Null → default icon avatars.
  final String? agentPhotoUrl;
  final String? citizenPhotoUrl;

  const ChatMessageBubble({
    super.key,
    required this.width,
    required this.message,
    required this.formatTime,
    this.onResend,
    this.onDelete,
    this.agentPhotoUrl,
    this.citizenPhotoUrl,
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
          // ── Agent avatar — staff photo once connected, else the bot ─────
          if (!isUser) ...[
            _AgentAvatar(
              width: width,
              photoUrl: message.fromStaff ? agentPhotoUrl : null,
            ),
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
                        : Border.all(color: CitizenUi.sharedStroke, width: 1),
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
                      // On-device fallback marker — shown only for agent replies
                      // produced offline (AI unavailable), so it's clear this
                      // answer came from the built-in brain, not the AI.
                      if (!isUser && message.offline) ...[
                        SizedBox(width: width * 0.016),
                        Icon(
                          Icons.wifi_off_rounded,
                          size: width * 0.026,
                          color: AppColors.hint,
                        ),
                        SizedBox(width: width * 0.006),
                        Text(
                          'Offline · on-device',
                          style: TextStyle(
                            fontSize: width * 0.022,
                            color: AppColors.hint,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                      if (isUser && message.status != MessageStatus.failed) ...[
                        SizedBox(width: width * 0.010),
                        MessageStatusTicks(
                          status: message.status,
                          width: width,
                        ),
                      ],
                    ],
                  ),
                ),
                // Failed send → inline Retry / Delete (Messenger-style).
                if (isUser && message.status == MessageStatus.failed)
                  Padding(
                    padding: EdgeInsets.only(top: width * 0.008),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.error_outline_rounded,
                          size: width * 0.030,
                          color: AppColors.red,
                        ),
                        SizedBox(width: width * 0.010),
                        Text(
                          'Not sent',
                          style: TextStyle(
                            fontSize: width * 0.024,
                            color: AppColors.red,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        SizedBox(width: width * 0.02),
                        _FailAction(
                          label: 'Retry',
                          width: width,
                          onTap: onResend,
                        ),
                        SizedBox(width: width * 0.012),
                        _FailAction(
                          label: 'Delete',
                          width: width,
                          onTap: onDelete,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          // ── Citizen (self) avatar ───────────────────────────────────────
          if (isUser) ...[
            SizedBox(width: width * 0.018),
            _CitizenAvatar(width: width, photoUrl: citizenPhotoUrl),
          ],
        ],
      ),
    );
  }
}

// ── Citizen (self) avatar ─────────────────────────────────────────────────────
class _CitizenAvatar extends StatelessWidget {
  final double width;
  final String? photoUrl;
  const _CitizenAvatar({required this.width, this.photoUrl});

  @override
  Widget build(BuildContext context) {
    final size = width * 0.078;
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: AppColors.primaryBlue,
        shape: BoxShape.circle,
      ),
      clipBehavior: Clip.antiAlias,
      child: (photoUrl != null && photoUrl!.isNotEmpty)
          ? CachedNetworkImage(
              imageUrl: photoUrl!,
              fit: BoxFit.cover,
              errorWidget: (_, _, _) => _fallback(size),
            )
          : _fallback(size),
    );
  }

  Widget _fallback(double size) => Center(
    child: Icon(Icons.person_rounded, size: size * 0.6, color: Colors.white),
  );
}

// ── Failed-send action (Retry / Delete) ──────────────────────────────────────
class _FailAction extends StatelessWidget {
  final String label;
  final double width;
  final VoidCallback? onTap;
  const _FailAction({required this.label, required this.width, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(width * 0.01),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: width * 0.01,
          vertical: width * 0.004,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: width * 0.024,
            fontWeight: FontWeight.w700,
            color: AppColors.primaryBlue,
          ),
        ),
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
              border: Border.all(color: CitizenUi.sharedStroke, width: 1),
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
  // When set (a connected staff member's message), show their photo instead of
  // the bot headphone.
  final String? photoUrl;
  const _AgentAvatar({required this.width, this.photoUrl});

  @override
  Widget build(BuildContext context) {
    final size = width * 0.078;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.primaryBlue.withValues(alpha: 0.10),
        shape: BoxShape.circle,
      ),
      clipBehavior: Clip.antiAlias,
      child: (photoUrl != null && photoUrl!.isNotEmpty)
          ? CachedNetworkImage(
              imageUrl: photoUrl!,
              fit: BoxFit.cover,
              errorWidget: (_, _, _) => _bot(width),
            )
          : _bot(width),
    );
  }

  Widget _bot(double width) => Center(
    child: Image.asset(
      'assets/images/customer.webp',
      width: width * 0.042,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => Icon(
        Icons.support_agent_rounded,
        size: width * 0.042,
        color: AppColors.primaryBlue,
      ),
    ),
  );
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
