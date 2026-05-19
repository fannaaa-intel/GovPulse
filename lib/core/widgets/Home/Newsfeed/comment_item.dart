import 'package:flutter/material.dart';
import '../../../theme/app_colors.dart';
import 'news_feed_helpers.dart';
import 'comment_options_sheet.dart';

Widget commentAction(
  double width, {
  required String label,
  required int count,
  required bool active,
  required Color activeColor,
  required String pngAsset,
  required IconData fallbackIcon,
  required VoidCallback onTap,
}) {
  final color = active ? activeColor : const Color(0xFF6B7280);
  return GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          pngAsset,
          width: width * 0.036,
          height: width * 0.036,
          color: color,
          colorBlendMode: BlendMode.srcIn,
          errorBuilder: (_, _, _) =>
              Icon(fallbackIcon, size: width * 0.036, color: color),
        ),
        SizedBox(width: width * 0.008),
        Text(
          label,
          style: TextStyle(
            fontSize: width * 0.028,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        if (count > 0) ...[
          SizedBox(width: width * 0.008),
          Text(
            '$count',
            style: TextStyle(
              fontSize: width * 0.028,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ],
    ),
  );
}

Widget buildCommentItem(
  BuildContext context,
  double width,
  Map<String, dynamic> comment, {
  required Set<String> likedComments,
  required ValueChanged<String> onToggleLike,
  required VoidCallback onReply,
  required bool showReplies,
  required Set<String> expandedReplies,
  required ValueChanged<String> onToggleExpandReplies,
  required ValueChanged<String> onReplyToReply,
  String? currentUserId,
  ValueChanged<Map<String, dynamic>>? onEdit,
  ValueChanged<Map<String, dynamic>>? onDelete,
}) {
  final id = comment['id'] as String;
  final isLiked = likedComments.contains(id);
  final baseLikes = (comment['likes'] as int?) ?? 0;
  final replies = (comment['replies'] as List<dynamic>?) ?? [];
  final isExpanded = expandedReplies.contains(id);
  final visibleReplies = isExpanded ? replies : replies.take(3).toList();
  final hiddenCount = replies.length - 3;
  final ts = comment['timestamp'] as DateTime?;
  final timeAgo = ts != null ? formatTimeAgo(ts) : '';
  final isOwner =
      currentUserId != null &&
      (comment['authorId'] as String?) == currentUserId;

  return Padding(
    padding: EdgeInsets.symmetric(vertical: width * 0.012),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            buildAvatar(width * 0.085, comment['authorPhotoUrl'] as String?),
            SizedBox(width: width * 0.025),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onLongPress: isOwner
                        ? () => showCommentOptions(
                            context,
                            width,
                            comment,
                            onEdit: onEdit,
                            onDelete: onDelete,
                          )
                        : null,
                    child: Container(
                      padding: EdgeInsets.fromLTRB(
                        width * 0.03,
                        width * 0.022,
                        width * 0.03,
                        width * 0.025,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(width * 0.04),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            comment['author'] as String? ?? '',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: width * 0.032,
                              color: const Color(0xFF1F2937),
                            ),
                          ),
                          SizedBox(height: width * 0.006),
                          Text(
                            comment['text'] as String? ?? '',
                            style: TextStyle(
                              fontSize: width * 0.033,
                              color: const Color(0xFF374151),
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      width * 0.03,
                      width * 0.012,
                      0,
                      0,
                    ),
                    child: Wrap(
                      spacing: width * 0.04,
                      runSpacing: width * 0.005,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          timeAgo,
                          style: TextStyle(
                            fontSize: width * 0.028,
                            color: const Color(0xFF6B7280),
                          ),
                        ),
                        commentAction(
                          width,
                          label: 'Like',
                          count: baseLikes,
                          active: isLiked,
                          activeColor: const Color(0xFFEF4444),
                          pngAsset: 'assets/images/heart.png',
                          fallbackIcon: Icons.favorite_border_rounded,
                          onTap: () => onToggleLike(id),
                        ),
                        commentAction(
                          width,
                          label: 'Reply',
                          count: replies.length,
                          active: false,
                          activeColor: AppColors.primaryBlue,
                          pngAsset: 'assets/images/comment.png',
                          fallbackIcon: Icons.reply_rounded,
                          onTap: onReply,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (showReplies && replies.isNotEmpty) ...[
          SizedBox(height: width * 0.015),
          ...visibleReplies.map(
            (r) => buildReplyItem(
              context,
              width,
              r as Map<String, dynamic>,
              likedComments: likedComments,
              onToggleLike: onToggleLike,
              onReply: () => onReplyToReply(r['author'] as String? ?? ''),
              currentUserId: currentUserId,
              onEdit: onEdit,
              onDelete: onDelete,
            ),
          ),
          if (replies.length > 3)
            Padding(
              padding: EdgeInsets.only(
                left: width * 0.135,
                top: width * 0.005,
                bottom: width * 0.005,
              ),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onToggleExpandReplies(id),
                child: Row(
                  children: [
                    Icon(
                      isExpanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.subdirectory_arrow_right_rounded,
                      size: width * 0.04,
                      color: AppColors.primaryBlue,
                    ),
                    SizedBox(width: width * 0.012),
                    Text(
                      isExpanded
                          ? 'Hide replies'
                          : 'View $hiddenCount more ${hiddenCount == 1 ? "reply" : "replies"}',
                      style: TextStyle(
                        fontSize: width * 0.030,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primaryBlue,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ],
    ),
  );
}

Widget buildReplyItem(
  BuildContext context,
  double width,
  Map<String, dynamic> reply, {
  required Set<String> likedComments,
  required ValueChanged<String> onToggleLike,
  required VoidCallback onReply,
  String? currentUserId,
  ValueChanged<Map<String, dynamic>>? onEdit,
  ValueChanged<Map<String, dynamic>>? onDelete,
}) {
  final id = reply['id'] as String;
  final isLiked = likedComments.contains(id);
  final baseLikes = (reply['likes'] as int?) ?? 0;
  final mentioned = reply['mentionedUser'] as String?;
  final ts = reply['timestamp'] as DateTime?;
  final timeAgo = ts != null ? formatTimeAgo(ts) : '';
  final isOwner =
      currentUserId != null && (reply['authorId'] as String?) == currentUserId;

  return Padding(
    padding: EdgeInsets.only(left: width * 0.11, top: width * 0.012),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        buildAvatar(width * 0.07, reply['authorPhotoUrl'] as String?),
        SizedBox(width: width * 0.022),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onLongPress: isOwner
                    ? () => showCommentOptions(
                        context,
                        width,
                        reply,
                        onEdit: onEdit,
                        onDelete: onDelete,
                      )
                    : null,
                child: Container(
                  padding: EdgeInsets.fromLTRB(
                    width * 0.028,
                    width * 0.020,
                    width * 0.028,
                    width * 0.022,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(width * 0.035),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        reply['author'] as String? ?? '',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: width * 0.030,
                          color: const Color(0xFF1F2937),
                        ),
                      ),
                      SizedBox(height: width * 0.005),
                      Text.rich(
                        TextSpan(
                          children: [
                            if (mentioned != null)
                              TextSpan(
                                text: '@$mentioned ',
                                style: TextStyle(
                                  fontSize: width * 0.031,
                                  color: AppColors.primaryBlue,
                                  fontWeight: FontWeight.w700,
                                  height: 1.35,
                                ),
                              ),
                            TextSpan(
                              text: reply['text'] as String? ?? '',
                              style: TextStyle(
                                fontSize: width * 0.031,
                                color: const Color(0xFF374151),
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  width * 0.025,
                  width * 0.010,
                  0,
                  0,
                ),
                child: Wrap(
                  spacing: width * 0.035,
                  runSpacing: width * 0.005,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      timeAgo,
                      style: TextStyle(
                        fontSize: width * 0.026,
                        color: const Color(0xFF6B7280),
                      ),
                    ),
                    commentAction(
                      width,
                      label: 'Like',
                      count: baseLikes,
                      active: isLiked,
                      activeColor: const Color(0xFFEF4444),
                      pngAsset: 'assets/images/heart.png',
                      fallbackIcon: Icons.favorite_border_rounded,
                      onTap: () => onToggleLike(id),
                    ),
                    commentAction(
                      width,
                      label: 'Reply',
                      count: 0,
                      active: false,
                      activeColor: AppColors.primaryBlue,
                      pngAsset: 'assets/images/comment.png',
                      fallbackIcon: Icons.reply_rounded,
                      onTap: onReply,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
