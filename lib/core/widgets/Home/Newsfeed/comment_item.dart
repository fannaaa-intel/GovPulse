import 'package:flutter/material.dart';
import '../../../theme/app_colors.dart';
import '../../../moderation/profanity_filter.dart';
import 'news_feed_helpers.dart';
import 'comment_options_sheet.dart';

/// Fixed sizing base for a comment row — the bubble, the avatar, the meta line.
///
/// The ADMIN console's panel is drawn in absolute pixels — 34px avatars, 13px
/// names, 11px meta — and is the reference for all three surfaces. Every metric
/// in [buildCommentItem] / [buildReplyItem] is a `width * k` fraction, so
/// feeding them one constant reproduces those pixel sizes exactly and, more
/// importantly, keeps them identical on a 360dp phone, a tablet and a 1440px
/// desktop dialog. Scaling this off the viewport is what made the same thread
/// render at three different sizes across citizen / staff / admin.
///
/// Responsiveness lives in the SHELL (dialog vs bottom sheet, chosen by
/// `kCommentsDialogBreakpoint`) and in the Expanded/Flexible layout — not in
/// the type scale.
///
/// Lives here rather than in `comments_sheet.dart` because the sheet is no
/// longer the only surface that draws these rows: the feed card previews the
/// first few comments under every post and must size them the same way.
const double kThreadMetrics = 400.0;

Widget commentAction(
  double width, {
  required String label,
  required int count,
  required bool active,
  required Color activeColor,
  required String pngAsset,
  required IconData fallbackIcon,
  IconData? activeIcon,
  required VoidCallback onTap,
}) {
  final color = active ? activeColor : const Color(0xFF6B7280);
  // When [activeIcon] is supplied (e.g. the Like heart) render Material icons
  // directly so the active state is a genuinely filled shape — tinting the
  // outline PNG red only ever produces a red outline, never a fill.
  final Widget leading = activeIcon != null
      ? Icon(
          active ? activeIcon : fallbackIcon,
          size: width * 0.036,
          color: color,
        )
      : Image.asset(
          pngAsset,
          width: width * 0.036,
          height: width * 0.036,
          color: color,
          colorBlendMode: BlendMode.srcIn,
          errorBuilder: (_, _, _) =>
              Icon(fallbackIcon, size: width * 0.036, color: color),
        );
  return GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        leading,
        // Official mode passes an empty label to get the admin panel's
        // icon-only heart; skip the gap and the empty Text entirely.
        if (label.isNotEmpty) ...[
          SizedBox(width: width * 0.008),
          Text(
            label,
            style: TextStyle(
              fontSize: width * 0.028,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
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

/// The small "LGU" chip beside an official author's name in official mode.
/// Same treatment as the admin console's comments panel.
Widget officialChip(double width) => Container(
  padding: EdgeInsets.symmetric(
    horizontal: width * 0.014,
    vertical: width * 0.002,
  ),
  decoration: BoxDecoration(
    color: AppColors.primaryBlue.withValues(alpha: 0.12),
    borderRadius: BorderRadius.circular(width * 0.01),
  ),
  child: Text(
    'LGU',
    style: TextStyle(
      fontSize: width * 0.023,
      fontWeight: FontWeight.w800,
      color: AppColors.primaryBlue,
    ),
  ),
);

/// A plain text action ("Reply" / "Edit" / "Delete") for official mode.
Widget commentTextAction(
  double width, {
  required String label,
  required VoidCallback onTap,
  Color color = const Color(0xFF6B7280),
}) => GestureDetector(
  behavior: HitTestBehavior.opaque,
  onTap: onTap,
  child: Text(
    label,
    style: TextStyle(
      fontSize: width * 0.028,
      fontWeight: FontWeight.w700,
      color: color,
    ),
  ),
);

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
  required void Function(String authorName, String commentId) onReplyToReply,
  String? currentUserId,
  ValueChanged<Map<String, dynamic>>? onEdit,
  ValueChanged<Map<String, dynamic>>? onDelete,

  /// Official (admin / staff) presentation: the bubble spans the column, an
  /// LGU chip sits beside an official author's name, and Edit / Delete appear
  /// as text actions instead of hiding behind a long-press. Mirrors the admin
  /// console's comments panel so the two consoles read identically. Off for the
  /// citizen feed, whose long-press sheet is the right affordance on a phone.
  bool official = false,
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
            buildAvatar(
              width * 0.085,
              comment['authorPhotoUrl'] as String?,
              photoPath: comment['authorPhotoPath'] as String?,
            ),
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
                          // In official mode the name sits in a Row, which
                          // takes the full width and so stretches the bubble
                          // to match the admin panel. The citizen bubble keeps
                          // hugging its text.
                          if (official)
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    comment['author'] as String? ?? '',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: width * 0.032,
                                      color: const Color(0xFF1F2937),
                                    ),
                                  ),
                                ),
                                if (comment['isOfficial'] == true) ...[
                                  SizedBox(width: width * 0.012),
                                  officialChip(width),
                                ],
                              ],
                            )
                          else
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
                            ProfanityFilter.maskForDisplay(
                              comment['text'] as String? ?? '',
                            ),
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
                    child: comment['isSending'] == true
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: width * 0.030,
                                height: width * 0.030,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                  color: const Color(0xFF9CA3AF),
                                ),
                              ),
                              SizedBox(width: width * 0.015),
                              Text(
                                'Sending...',
                                style: TextStyle(
                                  fontSize: width * 0.028,
                                  color: const Color(0xFF9CA3AF),
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          )
                        : Wrap(
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
                                // Admin shows a bare heart; the citizen feed
                                // labels it, which is clearer on a phone.
                                label: official ? '' : 'Like',
                                count: baseLikes,
                                active: isLiked,
                                activeColor: const Color(0xFFEF4444),
                                pngAsset: 'assets/images/heart.webp',
                                fallbackIcon: Icons.favorite_border_rounded,
                                activeIcon: Icons.favorite_rounded,
                                onTap: () => onToggleLike(id),
                              ),
                              if (official)
                                commentTextAction(
                                  width,
                                  label: 'Reply',
                                  onTap: onReply,
                                )
                              else
                                commentAction(
                                  width,
                                  label: 'Reply',
                                  count: replies.length,
                                  active: false,
                                  activeColor: AppColors.primaryBlue,
                                  pngAsset: 'assets/images/comment.webp',
                                  fallbackIcon: Icons.reply_rounded,
                                  onTap: onReply,
                                ),
                              // Own comment: surfaced as text actions rather
                              // than a long-press sheet, matching admin. A
                              // console is mouse-first — long-press is a phone
                              // gesture and effectively hidden there.
                              if (official && isOwner && onEdit != null)
                                commentTextAction(
                                  width,
                                  label: 'Edit',
                                  onTap: () => onEdit(comment),
                                ),
                              if (official && isOwner && onDelete != null)
                                commentTextAction(
                                  width,
                                  label: 'Delete',
                                  color: const Color(0xFFDC2626),
                                  onTap: () => onDelete(comment),
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
              onReply: () => onReplyToReply(
                r['author'] as String? ?? '',
                r['id'] as String,
              ),
              currentUserId: currentUserId,
              onEdit: onEdit,
              onDelete: onDelete,
              official: official,
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

  /// Official presentation — see [buildCommentItem]. A reply must honour the
  /// same flag as its parent: styling only the top-level comments left nested
  /// replies drawing the phone treatment inside an otherwise admin-style
  /// thread, which is exactly where the two designs visibly disagreed.
  bool official = false,
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
        buildAvatar(
          width * 0.07,
          reply['authorPhotoUrl'] as String?,
          photoPath: reply['authorPhotoPath'] as String?,
        ),
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
                      // Row (not bare Text) so the bubble takes the full width
                      // and the LGU chip has somewhere to sit — same as the
                      // parent comment in official mode.
                      if (official)
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                reply['author'] as String? ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: width * 0.030,
                                  color: const Color(0xFF1F2937),
                                ),
                              ),
                            ),
                            if (reply['isOfficial'] == true) ...[
                              SizedBox(width: width * 0.012),
                              officialChip(width),
                            ],
                          ],
                        )
                      else
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
                              text: ProfanityFilter.maskForDisplay(
                                reply['text'] as String? ?? '',
                              ),
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
                child: reply['isSending'] == true
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: width * 0.028,
                            height: width * 0.028,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: const Color(0xFF9CA3AF),
                            ),
                          ),
                          SizedBox(width: width * 0.015),
                          Text(
                            'Sending...',
                            style: TextStyle(
                              fontSize: width * 0.026,
                              color: const Color(0xFF9CA3AF),
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      )
                    : Wrap(
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
                            label: official ? '' : 'Like',
                            count: baseLikes,
                            active: isLiked,
                            activeColor: const Color(0xFFEF4444),
                            pngAsset: 'assets/images/heart.webp',
                            fallbackIcon: Icons.favorite_border_rounded,
                            activeIcon: Icons.favorite_rounded,
                            onTap: () => onToggleLike(id),
                          ),
                          if (official)
                            commentTextAction(
                              width,
                              label: 'Reply',
                              onTap: onReply,
                            )
                          else
                            commentAction(
                              width,
                              label: 'Reply',
                              count: 0,
                              active: false,
                              activeColor: AppColors.primaryBlue,
                              pngAsset: 'assets/images/comment.webp',
                              fallbackIcon: Icons.reply_rounded,
                              onTap: onReply,
                            ),
                          if (official && isOwner && onEdit != null)
                            commentTextAction(
                              width,
                              label: 'Edit',
                              onTap: () => onEdit(reply),
                            ),
                          if (official && isOwner && onDelete != null)
                            commentTextAction(
                              width,
                              label: 'Delete',
                              color: const Color(0xFFDC2626),
                              onTap: () => onDelete(reply),
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
