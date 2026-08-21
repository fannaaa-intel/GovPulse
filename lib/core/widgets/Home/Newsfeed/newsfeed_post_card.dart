import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../../moderation/profanity_filter.dart';
import '../../../theme/app_colors.dart';
import 'comment_item.dart';
import 'image_grid.dart';
import 'news_feed_helpers.dart';
import '../../../../core/theme/citizen_ui.dart';

// ════════════════════════════════════════════════════════════════════════════
//  A single community post, as it appears in the feed.
//
//  Lifted verbatim out of `news_feed_screen.dart`, where it lived as four
//  private State methods (_buildPostCard / _buildPostHeader / _buildPostBody /
//  _buildPostFooter). Nothing about the rendering changed in the move; the
//  widget tree, the `width * 0.0xx` sizing and every colour are as they were.
//
//  It is deliberately STATELESS and fully driven by its inputs. All the mutable
//  bits the old methods read straight off the State — which posts are liked,
//  which are expanded, which comments are liked — arrive as plain values with
//  matching callbacks, so the feed screen keeps owning that state exactly as it
//  does today. That is also what makes the card reusable by the persistent web
//  shell later without dragging NewsFeedScreen's State along with it.
// ════════════════════════════════════════════════════════════════════════════

/// How many comments (top-level + replies, flattened) preview under a post.
const int kPostCardPreviewComments = 3;

/// Below this column width the post slab runs edge to edge — no side margin, no
/// rounded corners, no side border — the way Facebook's mobile feed does, and
/// the media inside it is full-bleed against the screen edge.
///
/// Above it the feed column is wider than the card's readable measure, so a
/// full-bleed slab would just be a white band floating in grey; those widths
/// keep the bordered, rounded card.
const double kPostCardFullBleedBelow = 640;

class NewsfeedPostCard extends StatelessWidget {
  /// The layout base width. Every dimension in the card is a fraction of this,
  /// which is why it is threaded through rather than read from MediaQuery — the
  /// web feed renders the card in a fixed 600px column, not at viewport width.
  final double width;

  /// The post row as the provider shaped it (already identity-resolved:
  /// citizens anonymised, officials keeping their real name and photo).
  final Map<String, dynamic> post;

  /// Guests see other citizens' comments anonymised. Officials are exempt.
  final bool isGuest;

  /// Whether the signed-in user has liked this post / commented on it.
  final bool isLiked;
  final bool isCommented;

  /// Whether the body text is showing in full ("See less" state).
  final bool isExpanded;

  /// Comment ids the user has liked — forwarded to the preview comment rows.
  final Set<String> likedComments;

  /// Toggle the "See more" / "See less" body expansion.
  final VoidCallback onToggleExpanded;

  /// Like / unlike the post itself.
  final VoidCallback onToggleLike;

  /// Like / unlike one of the preview comments.
  final ValueChanged<String> onToggleCommentLike;

  /// Open the comments sheet for this post. [initialReplyTo] pre-addresses the
  /// composer at a specific author, as tapping "Reply" on a preview row does.
  final void Function({String? initialReplyTo}) onOpenComments;

  /// Render as a full-bleed slab instead of a floating card — see
  /// [kPostCardFullBleedBelow]. The feed decides this from the width of the
  /// column it is laying the card into, not from the viewport.
  final bool edgeToEdge;

  const NewsfeedPostCard({
    super.key,
    required this.width,
    required this.post,
    required this.isGuest,
    required this.isLiked,
    required this.isCommented,
    required this.isExpanded,
    required this.likedComments,
    required this.onToggleExpanded,
    required this.onToggleLike,
    required this.onToggleCommentLike,
    required this.onOpenComments,
    this.edgeToEdge = false,
  });

  /// Guests see other citizens as "Citizen" with no avatar, matching how the
  /// provider already masks post authors. Officials (if the comment carries
  /// that flag) keep their real identity.
  Map<String, dynamic> _maskCommentForGuest(Map<String, dynamic> c) {
    if (!isGuest) return c;
    if (c['isOfficial'] == true) return c;
    return {
      ...c,
      'author': 'Citizen',
      'authorPhotoUrl': null,
      'authorPhotoPath': null,
      if (c['mentionedUser'] != null) 'mentionedUser': 'Citizen',
    };
  }

  @override
  Widget build(BuildContext context) {
    final comments = post['comments'] as List<dynamic>;
    final commentCount = post['commentCount'] as int? ?? comments.length;

    // Flatten top-level comments + replies into one activity list
    // Sort top-level newest first, then keep each reply directly under its
    // parent so a reply never appears above the comment it answers.
    final topLevel = comments.cast<Map<String, dynamic>>().toList()
      ..sort((a, b) {
        final ta = a['timestamp'] as DateTime?;
        final tb = b['timestamp'] as DateTime?;
        if (ta == null || tb == null) return 0;
        return tb.compareTo(ta);
      });
    final allActivity = <Map<String, dynamic>>[];
    for (final comment in topLevel) {
      allActivity.add(comment);
      final replies = (comment['replies'] as List<dynamic>?) ?? [];
      allActivity.addAll(replies.cast<Map<String, dynamic>>());
    }
    final previewComments = allActivity.take(kPostCardPreviewComments).toList();

    final double gutter = width * 0.035;

    // Full bleed keeps the SAME gutter on the text rows and simply stops
    // applying it to the media, so the only thing that changes shape is the
    // slab and the photos in it — every type size, weight and rhythm inside the
    // card is untouched.
    Widget inGutter(Widget child) => edgeToEdge
        ? Padding(
            padding: EdgeInsets.symmetric(horizontal: gutter),
            child: child,
          )
        : child;

    return Container(
      decoration: edgeToEdge
          // No side border and no shadow: against the screen edge there is no
          // side left to draw, and a drop shadow on a band that spans the
          // viewport reads as a seam rather than a lifted card. The two
          // hairlines plus the grey gap between posts do all the separating.
          ? const BoxDecoration(
              color: Colors.white,
              border: Border(
                top: BorderSide(color: CitizenUi.sharedBorder),
                bottom: BorderSide(color: CitizenUi.sharedBorder),
              ),
            )
          : BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(width * 0.035),
              border: Border.all(color: CitizenUi.sharedBorder),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .04),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
      child: Padding(
        padding: edgeToEdge
            ? EdgeInsets.symmetric(vertical: gutter)
            : EdgeInsets.all(gutter),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (post['pinned'] == true) ...[
              inGutter(
                Row(
                  children: [
                    Icon(
                      Icons.push_pin_rounded,
                      size: width * 0.035,
                      color: const Color(0xFF0D47A1),
                    ),
                    SizedBox(width: width * 0.012),
                    Text(
                      'Pinned',
                      style: TextStyle(
                        fontSize: width * 0.03,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF0D47A1),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: width * 0.02),
            ],
            inGutter(_buildPostHeader()),
            SizedBox(height: width * 0.03),
            inGutter(
              Text(
                ProfanityFilter.maskForDisplay(post['title'] as String),
                style: TextStyle(
                  fontSize: width * 0.045,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF1F2937),
                  height: 1.25,
                ),
              ),
            ),
            SizedBox(height: width * 0.012),
            inGutter(_buildPostBody(post['body'] as String)),
            SizedBox(height: width * 0.025),
            buildImageGrid(
              width,
              post['imageCount'] as int,
              imageUrls: post['imageUrls'] as List<String>? ?? [],
              // Squared off when the media touches the screen edge; rounded
              // corners only make sense inside a rounded card.
              cornerRadius: edgeToEdge ? 0 : null,
              onImageTap: (index) => openImageViewer(
                context,
                post['imageCount'] as int,
                index,
                urls: post['imageUrls'] as List<String>? ?? [],
                // On WEB this card renders inside the shell's centre column,
                // whose branch navigator would bound the viewer's barrier to
                // that column — rails and top nav stayed bright. The root
                // navigator is the whole window.
                //
                // kIsWeb rather than a bare `true` so MOBILE takes exactly the
                // path it takes today. On the web guest feed it is a no-op:
                // /newsfeed is already a top-level route, so root IS nearest.
                useRootNavigator: kIsWeb,
              ),
            ),
            SizedBox(height: width * 0.03),
            inGutter(
              _buildPostFooter(
                post['likes'] as String,
                commentCount.toString(),
                () => onOpenComments(),
                liked: isLiked,
                commented: isCommented,
                onLikeTap: onToggleLike,
              ),
            ),
            // One gutter for the whole comment block rather than one per row,
            // so the divider keeps lining up with the rows under it.
            if (commentCount > 0)
              inGutter(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: width * 0.025),
                      child: Container(
                        height: 1,
                        color: CitizenUi.sharedBorder,
                      ),
                    ),
                    ...previewComments.map((rawComment) {
                      final comment = _maskCommentForGuest(rawComment);
                      final isReply = comment['parentId'] != null;
                      if (isReply) {
                        return buildReplyItem(
                          context,
                          width,
                          comment,
                          likedComments: likedComments,
                          onToggleLike: onToggleCommentLike,
                          onReply: () => onOpenComments(
                            initialReplyTo: comment['author'] as String,
                          ),
                        );
                      }
                      return buildCommentItem(
                        context,
                        width,
                        comment,
                        likedComments: likedComments,
                        onToggleLike: onToggleCommentLike,
                        onReply: () => onOpenComments(
                          initialReplyTo: comment['author'] as String,
                        ),
                        showReplies: false,
                        expandedReplies: const {},
                        onToggleExpandReplies: (_) {},
                        onReplyToReply: (_, _) {},
                      );
                    }),
                    if (commentCount > kPostCardPreviewComments)
                      Padding(
                        padding: EdgeInsets.only(top: width * 0.015),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => onOpenComments(),
                          child: Row(
                            children: [
                              Text(
                                'View all $commentCount comments',
                                style: TextStyle(
                                  fontSize: width * 0.034,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primaryBlue,
                                ),
                              ),
                              SizedBox(width: width * 0.008),
                              Icon(
                                Icons.arrow_forward_ios_rounded,
                                size: width * 0.030,
                                color: AppColors.primaryBlue,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPostHeader() {
    final ts = post['timestamp'] as DateTime?;
    final timeAgo = ts != null ? formatTimeAgo(ts) : '';

    // Identity is already resolved in the provider: citizens are anonymised
    // ("Citizen" + default avatar) and officials keep their real name + photo.
    final bool blankAvatar = post['blankAvatar'] == true;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        buildAuthorAvatar(
          width * 0.105,
          post['authorPhotoUrl'] as String?,
          photoPath: post['authorPhotoPath'] as String?,
          blank: blankAvatar,
          // Official "LGU Aparri" avatar has no green ring (matches admin side).
          ring: post['isOfficial'] != true,
        ),
        SizedBox(width: width * 0.025),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                // Official posts read "LGU Aparri with <office>" when tagged to
                // a specific entity; the default "LGU Aparri" tag just shows
                // "LGU Aparri". Citizen authors are unchanged.
                () {
                  final author = post['author'] as String;
                  final tag = (post['tag'] as String?)?.trim() ?? '';
                  final official = post['isOfficial'] == true;
                  return (official && tag.isNotEmpty && tag != 'LGU Aparri')
                      ? '$author with $tag'
                      : author;
                }(),
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
                    () {
                      // Staff authors carry their office (Engineering Office,
                      // Sanitation Office, …) resolved from the official
                      // directory — lead the meta line with it.
                      final dept =
                          (post['authorDept'] as String?)?.trim() ?? '';
                      final b = (post['barangay'] as String?)?.trim() ?? '';
                      final parts = [
                        if (dept.isNotEmpty) dept,
                        if (b.isNotEmpty) b,
                        timeAgo,
                      ];
                      return parts.join(' · ');
                    }(),
                    style: TextStyle(
                      fontSize: width * 0.028,
                      color: const Color(0xFF6B7280),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  // The tag pill is redundant for official posts now that the
                  // "with <office>" is in the author line — keep it only for
                  // non-official (citizen) authors.
                  if (post['isOfficial'] != true)
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: width * 0.018,
                        vertical: width * 0.005,
                      ),
                      decoration: BoxDecoration(
                        color: post['tagColor'] as Color,
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
                            post['tag'] as String,
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

  Widget _buildPostBody(String rawBody) {
    // Mask any profanity for display — citizens never see it, even if the row
    // slipped past the client (the original text is untouched in the DB).
    final body = ProfanityFilter.maskForDisplay(rawBody);
    final textStyle = TextStyle(
      fontSize: width * 0.034,
      color: const Color(0xFF374151),
      height: 1.45,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // Measure whether the body actually needs more than 2 lines.
        final tp = TextPainter(
          text: TextSpan(text: body, style: textStyle),
          maxLines: 2,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: constraints.maxWidth);
        final isOverflowing = tp.didExceedMaxLines;

        // Short post — no toggle needed at all.
        if (!isOverflowing) {
          return Text(body, style: textStyle);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              body,
              style: textStyle,
              maxLines: isExpanded ? null : 2,
              overflow: isExpanded ? TextOverflow.clip : TextOverflow.ellipsis,
            ),
            SizedBox(height: width * 0.008),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onToggleExpanded,
              child: Text(
                isExpanded ? 'See less' : 'See more',
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

  Widget _buildPostFooter(
    String likes,
    String comments,
    VoidCallback onCommentsTap, {
    bool liked = false,
    bool commented = false,
    VoidCallback? onLikeTap,
  }) {
    const commentActive = Color(0xFF0D47A1); // AppColors.primaryBlue
    const commentIdle = Color(0xFF6B7280);
    final commentColor = commented ? commentActive : commentIdle;
    return Row(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onLikeTap,
          child: Row(
            children: [
              // Use Material heart icons so the liked state is a genuinely
              // filled heart — tinting the outline heart.webp red only ever
              // produces a red outline (never a fill).
              Icon(
                liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                size: width * 0.046,
                color: liked
                    ? const Color(0xFFEF4444)
                    : const Color(0xFF6B7280),
              ),
              SizedBox(width: width * 0.012),
              Text(
                likes,
                style: TextStyle(
                  fontSize: width * 0.034,
                  fontWeight: FontWeight.w600,
                  color: liked
                      ? const Color(0xFFEF4444)
                      : const Color(0xFF374151),
                ),
              ),
            ],
          ),
        ),
        SizedBox(width: width * 0.05),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onCommentsTap,
          child: Row(
            children: [
              Image.asset(
                'assets/images/comment.webp',
                width: width * 0.048,
                height: width * 0.048,
                color: commentColor,
                colorBlendMode: BlendMode.srcIn,
                errorBuilder: (_, _, _) => Icon(
                  commented
                      ? Icons.mode_comment_rounded
                      : Icons.chat_bubble_outline_rounded,
                  size: width * 0.048,
                  color: commentColor,
                ),
              ),
              SizedBox(width: width * 0.012),
              Text(
                comments,
                style: TextStyle(
                  fontSize: width * 0.034,
                  fontWeight: FontWeight.w600,
                  color: commented ? commentActive : const Color(0xFF374151),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
