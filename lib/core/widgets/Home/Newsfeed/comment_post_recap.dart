import 'package:flutter/material.dart';
import '../../../theme/app_colors.dart';
import '../../../moderation/profanity_filter.dart';
import 'news_feed_helpers.dart';
import 'image_grid.dart';

/// The post a comment thread belongs to, drawn at the top of the WIDE-SCREEN
/// comments dialog.
///
/// On web the thread opens in a centred dialog that covers the feed, so without
/// this the reader loses the very post they clicked on — a bare list of replies
/// to something no longer on screen.
///
/// Placed two ways, both by the caller, never pinned:
///  - tall dialogs stack it as the first item of the comment ListView, so it
///    scrolls away as you move down the thread;
///  - wide-but-short dialogs give it its own scrolling left column beside the
///    thread. See `commentsUseSplitLayout`.
///
/// Phone / narrow viewports never show it: there the thread opens as a bottom
/// sheet over a feed that is still visible behind it, and the post is one
/// dismiss away.
///
/// Fed the normalized post map from `CommunityPostsProvider._mapPostRow`, so
/// the citizen feed and the staff console pass their posts straight through.
/// The admin console maps its `CommunityUpdate` onto the same keys.
///
/// Read-only by design: the counts are text, not buttons. Liking and commenting
/// belong to the feed card and the composer below — a second set of actions
/// here would need post-like state threaded through all three call sites for no
/// gain.
class CommentPostRecap extends StatefulWidget {
  /// Normalized post map. Keys read: author, authorDept, authorPhotoUrl,
  /// authorPhotoPath, blankAvatar, isOfficial, tag, tagColor, barangay,
  /// timestamp, title, body, imageCount, imageUrls, likes, commentCount.
  final Map<String, dynamic> post;

  /// Fixed metrics base — pass [kThreadMetrics], the same constant the thread
  /// below uses, NOT the viewport width. See its doc in comments_sheet.dart:
  /// scaling the type off the display is what made one thread render at three
  /// different sizes across citizen / staff / admin.
  final double width;

  const CommentPostRecap({super.key, required this.post, required this.width});

  @override
  State<CommentPostRecap> createState() => _CommentPostRecapState();
}

class _CommentPostRecapState extends State<CommentPostRecap> {
  /// Local to this dialog. The feed's own `_expandedPosts` set is deliberately
  /// not consulted — expanding the body here should not silently expand the
  /// card behind the dialog too.
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final width = widget.width;
    final post = widget.post;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            width * 0.015,
            width * 0.01,
            width * 0.015,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(width, post),
              SizedBox(height: width * 0.03),
              Text(
                ProfanityFilter.maskForDisplay(
                  (post['title'] as String?) ?? '',
                ),
                style: TextStyle(
                  fontSize: width * 0.045,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF1F2937),
                  height: 1.25,
                ),
              ),
              SizedBox(height: width * 0.012),
              _body(width, (post['body'] as String?) ?? ''),
              SizedBox(height: width * 0.025),
              // The grid is the one metric that follows the DIALOG, not
              // [kThreadMetrics] — images should fill the width they are given.
              // Sizing it off the fixed base leaves a gutter on a wide dialog;
              // sizing it off MediaQuery overflows it.
              LayoutBuilder(
                builder: (context, constraints) => buildImageGrid(
                  constraints.maxWidth,
                  (post['imageCount'] as int?) ?? 0,
                  imageUrls: (post['imageUrls'] as List<String>?) ?? const [],
                  onImageTap: (index) => openImageViewer(
                    context,
                    (post['imageCount'] as int?) ?? 0,
                    index,
                    urls: (post['imageUrls'] as List<String>?) ?? const [],
                  ),
                ),
              ),
              SizedBox(height: width * 0.03),
              _counts(width, post),
              SizedBox(height: width * 0.03),
            ],
          ),
        ),
        Container(height: 1, color: const Color(0xFFE5E7EB)),
        SizedBox(height: width * 0.02),
      ],
    );
  }

  /// Author row. Mirrors the feed card's header so the post reads the same
  /// inside the dialog as it does in the feed behind it.
  Widget _header(double width, Map<String, dynamic> post) {
    final ts = post['timestamp'] as DateTime?;
    final timeAgo = ts != null ? formatTimeAgo(ts) : '';
    final official = post['isOfficial'] == true;
    final tag = (post['tag'] as String?)?.trim() ?? '';

    // Official posts read "LGU Aparri with <office>" when tagged to a specific
    // entity; the default "LGU Aparri" tag just shows the author.
    final author = (post['author'] as String?) ?? '';
    final authorLine = (official && tag.isNotEmpty && tag != 'LGU Aparri')
        ? '$author with $tag'
        : author;

    final dept = (post['authorDept'] as String?)?.trim() ?? '';
    final barangay = (post['barangay'] as String?)?.trim() ?? '';
    final meta = [
      if (dept.isNotEmpty) dept,
      if (barangay.isNotEmpty) barangay,
      timeAgo,
    ].join(' · ');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        buildAuthorAvatar(
          width * 0.105,
          post['authorPhotoUrl'] as String?,
          photoPath: post['authorPhotoPath'] as String?,
          blank: post['blankAvatar'] == true,
          // Official avatars carry no green ring — matches the admin side.
          ring: !official,
        ),
        SizedBox(width: width * 0.025),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                authorLine,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: width * 0.038,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF1F2937),
                ),
              ),
              SizedBox(height: width * 0.006),
              Wrap(
                spacing: width * 0.018,
                runSpacing: width * 0.005,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    meta,
                    style: TextStyle(
                      fontSize: width * 0.028,
                      color: const Color(0xFF6B7280),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  // Redundant for official posts, whose office is already in
                  // the author line — kept for citizen authors only.
                  if (!official && tag.isNotEmpty)
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: width * 0.018,
                        vertical: width * 0.005,
                      ),
                      decoration: BoxDecoration(
                        color:
                            (post['tagColor'] as Color?) ??
                            AppColors.primaryBlue,
                        borderRadius: BorderRadius.circular(width * 0.025),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.location_on_rounded,
                            size: width * 0.028,
                            color: Colors.white,
                          ),
                          SizedBox(width: width * 0.005),
                          Text(
                            tag,
                            style: TextStyle(
                              fontSize: width * 0.026,
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Post body, clamped to 6 lines with an in-place See more / See less.
  ///
  /// The feed card clamps to 2 — the dialog has the room, and a thread you
  /// opened to read deserves more of the post than a scanning feed does.
  Widget _body(double width, String rawBody) {
    final body = ProfanityFilter.maskForDisplay(rawBody);
    if (body.isEmpty) return const SizedBox.shrink();

    final textStyle = TextStyle(
      fontSize: width * 0.034,
      color: const Color(0xFF374151),
      height: 1.45,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final tp = TextPainter(
          text: TextSpan(text: body, style: textStyle),
          maxLines: 6,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: constraints.maxWidth);

        // Short post — no toggle needed at all.
        if (!tp.didExceedMaxLines) return Text(body, style: textStyle);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              body,
              style: textStyle,
              maxLines: _expanded ? null : 6,
              overflow: _expanded ? TextOverflow.clip : TextOverflow.ellipsis,
            ),
            SizedBox(height: width * 0.008),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _expanded = !_expanded),
              child: Text(
                _expanded ? 'See less' : 'See more',
                style: TextStyle(
                  fontSize: width * 0.034,
                  color: AppColors.primaryBlue,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Engagement counts as plain text. `likes` arrives pre-formatted from the
  /// provider (a String, e.g. "1.2K"); `commentCount` is a raw int.
  Widget _counts(double width, Map<String, dynamic> post) {
    final likes = (post['likes'] as String?)?.trim() ?? '';
    final comments = (post['commentCount'] as int?) ?? 0;

    final style = TextStyle(
      fontSize: width * 0.030,
      color: const Color(0xFF6B7280),
      fontWeight: FontWeight.w600,
    );

    return Row(
      children: [
        Icon(
          Icons.favorite_rounded,
          size: width * 0.034,
          color: const Color(0xFFEF4444),
        ),
        SizedBox(width: width * 0.012),
        Text(likes.isEmpty ? '0' : likes, style: style),
        const Spacer(),
        Text(
          '$comments ${comments == 1 ? 'comment' : 'comments'}',
          style: style,
        ),
      ],
    );
  }
}
