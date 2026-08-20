import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../theme/app_colors.dart';
import 'chat_bubbles_model.dart';
import '../../../../core/theme/citizen_ui.dart';

// ── Online dot ────────────────────────────────────────────────────────────────
class ChatOnlineDot extends StatelessWidget {
  final double size;
  const ChatOnlineDot({super.key, this.size = 14});

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: AppColors.green,
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: 2),
    ),
  );
}

// ── Agent avatar ──────────────────────────────────────────────────────────────
class ChatAgentAvatar extends StatelessWidget {
  final double size;
  // Connected staff's photo (their messages) → shown instead of the bot glyph.
  final String? photoUrl;
  const ChatAgentAvatar({super.key, this.size = 28, this.photoUrl});

  @override
  Widget build(BuildContext context) => Container(
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
            errorWidget: (_, _, _) => _bot(),
          )
        : _bot(),
  );

  Widget _bot() => Center(
    child: Icon(
      Icons.support_agent_rounded,
      size: size * 0.54,
      color: AppColors.primaryBlue,
    ),
  );
}

// ── Citizen (self) avatar — floating panel ────────────────────────────────────
class ChatCitizenAvatar extends StatelessWidget {
  final double size;
  final String? photoUrl;
  const ChatCitizenAvatar({super.key, this.size = 28, this.photoUrl});

  @override
  Widget build(BuildContext context) => Container(
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
            errorWidget: (_, _, _) => _icon(),
          )
        : _icon(),
  );

  Widget _icon() => Center(
    child: Icon(Icons.person_rounded, size: size * 0.6, color: Colors.white),
  );
}

// ── Unread badge ──────────────────────────────────────────────────────────────
class ChatUnreadBadge extends StatelessWidget {
  const ChatUnreadBadge({super.key});

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0.0, end: 1.0),
    duration: const Duration(milliseconds: 300),
    curve: Curves.elasticOut,
    builder: (_, v, child) => Transform.scale(scale: v, child: child),
    child: Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: Colors.red,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: const Center(
        child: Text(
          '!',
          style: TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            height: 1,
          ),
        ),
      ),
    ),
  );
}

// ── Circle icon button ────────────────────────────────────────────────────────
class ChatCircleIconButton extends StatelessWidget {
  final VoidCallback onTap;
  final IconData icon;
  final double size;
  const ChatCircleIconButton({
    super.key,
    required this.onTap,
    required this.icon,
    this.size = 32,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.inputBg,
        shape: BoxShape.circle,
        border: Border.all(color: CitizenUi.sharedStroke, width: 1),
      ),
      child: Icon(icon, size: size * 0.53, color: AppColors.hint),
    ),
  );
}

// ── Status ticks ──────────────────────────────────────────────────────────────
class ChatStatusTicks extends StatelessWidget {
  final MessageStatus status;
  const ChatStatusTicks({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case MessageStatus.sent:
        return _tick(AppColors.hint, isDouble: false);
      case MessageStatus.delivered:
        return _tick(AppColors.hint, isDouble: true);
      case MessageStatus.seen:
        return _tick(AppColors.primaryBlue, isDouble: true);
    }
  }

  Widget _tick(Color color, {required bool isDouble}) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: isDouble
          ? SizedBox(
              key: ValueKey('double-${color.toARGB32()}'),
              width: 18,
              height: 12,
              child: Stack(
                children: [
                  Positioned(
                    left: 0,
                    child: Icon(Icons.check_rounded, size: 12, color: color),
                  ),
                  Positioned(
                    left: 5,
                    child: Icon(Icons.check_rounded, size: 12, color: color),
                  ),
                ],
              ),
            )
          : Icon(
              key: const ValueKey('single'),
              Icons.check_rounded,
              size: 12,
              color: color,
            ),
    );
  }
}

// ── Typing dots ───────────────────────────────────────────────────────────────
class ChatTypingDots extends StatefulWidget {
  const ChatTypingDots({super.key});

  @override
  State<ChatTypingDots> createState() => _ChatTypingDotsState();
}

class _ChatTypingDotsState extends State<ChatTypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (_, _) => Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        final delay = i * 0.28;
        final raw = (_c.value - delay) % 1.0;
        final t = raw < 0 ? raw + 1.0 : raw;
        final opacity = 0.25 + 0.75 * (t < 0.5 ? t * 2 : (1.0 - t) * 2);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2.5),
          child: Opacity(
            opacity: opacity,
            child: Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                color: AppColors.primaryBlue,
                shape: BoxShape.circle,
              ),
            ),
          ),
        );
      }),
    ),
  );
}
