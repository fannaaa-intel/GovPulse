import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../theme/app_colors.dart';
import '../../../providers/community_posts_provider.dart';
import 'news_feed_helpers.dart';
import 'image_grid.dart';
import 'comment_item.dart';
import 'edit_comment_sheet.dart';
import '../../Home/Newsfeed/rate_limit_dialogs.dart';
import 'package:cached_network_image/cached_network_image.dart';

class CommentsSheet extends StatefulWidget {
  final Map<String, dynamic> post;
  final String? initialReplyTo;
  final Set<String> likedComments;
  final ValueChanged<String> onToggleLike;
  final Set<String> likedPosts;
  final ValueChanged<String> onTogglePostLike;

  const CommentsSheet({
    super.key,
    required this.post,
    this.initialReplyTo,
    required this.likedComments,
    required this.onToggleLike,
    required this.likedPosts,
    required this.onTogglePostLike,
  });

  @override
  State<CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<CommentsSheet> {
  late final TextEditingController _inputController;
  late final FocusNode _inputFocus;

  String? _replyingTo;
  String? _replyingToParentId;
  String? _replyingToUserId;
  final Set<String> _expandedReplies = {};
  bool _sending = false;
  String? _myPhotoUrl;
  String? _myPhotoPath;
  String? _myDisplayName;

  List<Map<String, dynamic>>? _optimisticComments;

  final SupabaseClient _supabase = Supabase.instance.client;
  String? get _currentUserId => _supabase.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _inputController = TextEditingController();
    _inputFocus = FocusNode();
    _inputFocus.addListener(() {
      if (mounted) setState(() {});
    });
    if (widget.initialReplyTo != null) {
      _setReplyByAuthorName(widget.initialReplyTo!);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _inputFocus.requestFocus();
      });
    }
    _loadMyPhoto();
  }

  @override
  void dispose() {
    _inputController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  Future<void> _loadMyPhoto() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final res = await _supabase
          .from('citizen_details')
          .select('profile_photo_path')
          .eq('user_id', userId)
          .maybeSingle();
      final path = res?['profile_photo_path'] as String?;
      if (path == null || path.isEmpty) return;

      if (!mounted) return;
      final nameRes = await _supabase
          .from('public_user_profiles')
          .select('first_name, last_name')
          .eq('user_id', userId)
          .maybeSingle();
      final first = (nameRes?['first_name'] as String?) ?? '';
      final last = (nameRes?['last_name'] as String?) ?? '';
      final full = '$first $last'.trim();
      setState(() {
        _myPhotoPath = path;
        _myPhotoUrl = _supabase.storage
            .from('verification-assets')
            .getPublicUrl(path);
        _myDisplayName = full.isNotEmpty ? full : null;
      });
    } catch (_) {}
  }

  List<Map<String, dynamic>> _getComments() {
    // _optimisticComments here is only for local edit/delete patches
    if (_optimisticComments != null) return _optimisticComments!;
    final freshPost = CommunityPostsProvider.instance.sortedPosts.firstWhere(
      (p) => p['id'] == widget.post['id'],
      orElse: () => widget.post,
    );
    // sortedPosts already merges provider-level optimistic (sent comments)
    return List<Map<String, dynamic>>.from(
      (freshPost['comments'] as List<dynamic>).cast<Map<String, dynamic>>(),
    );
  }

  List<Map<String, dynamic>> _patchText(
    List<Map<String, dynamic>> comments,
    String id,
    String newText,
  ) {
    return comments.map((c) {
      if (c['id'] == id) return {...c, 'text': newText};
      final replies = (c['replies'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>();
      return {
        ...c,
        'replies': replies.map((r) {
          if (r['id'] == id) return {...r, 'text': newText};
          return r;
        }).toList(),
      };
    }).toList();
  }

  List<Map<String, dynamic>> _removeById(
    List<Map<String, dynamic>> comments,
    String id,
  ) {
    return comments.where((c) => c['id'] != id).map((c) {
      final replies = (c['replies'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>();
      return {...c, 'replies': replies.where((r) => r['id'] != id).toList()};
    }).toList();
  }

  void _setReplyByAuthorName(String authorName) {
    final currentUserId = _supabase.auth.currentUser?.id;
    final comments = _getComments();

    for (final cm in comments) {
      if (cm['author'] == authorName) {
        final isSelf = currentUserId != null && cm['authorId'] == currentUserId;
        setState(() {
          _replyingTo = isSelf ? 'yourself' : authorName;
          _replyingToParentId = cm['id'] as String;
          _replyingToUserId = isSelf ? null : cm['authorId'] as String?;
        });
        return;
      }
      final replies = (cm['replies'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>();
      for (final rm in replies) {
        if (rm['author'] == authorName) {
          final isSelf =
              currentUserId != null && rm['authorId'] == currentUserId;
          setState(() {
            _replyingTo = isSelf ? 'yourself' : authorName;
            _replyingToParentId = cm['id'] as String;
            _replyingToUserId = isSelf ? null : rm['authorId'] as String?;
          });
          return;
        }
      }
    }
    setState(() {
      _replyingTo = authorName;
      _replyingToParentId = null;
      _replyingToUserId = null;
    });
  }

  void _setReplyByCommentId(String commentId, String authorName) {
    final currentUserId = _supabase.auth.currentUser?.id;
    final comments = _getComments();

    for (final cm in comments) {
      if (cm['id'] == commentId) {
        final isSelf = currentUserId != null && cm['authorId'] == currentUserId;
        setState(() {
          _replyingTo = isSelf ? 'yourself' : authorName;
          _replyingToParentId = cm['id'] as String;
          _replyingToUserId = isSelf ? null : cm['authorId'] as String?;
        });
        return;
      }
      final replies = (cm['replies'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>();
      for (final rm in replies) {
        if (rm['id'] == commentId) {
          final isSelf =
              currentUserId != null && rm['authorId'] == currentUserId;
          setState(() {
            _replyingTo = isSelf ? 'yourself' : authorName;
            _replyingToParentId = cm['id'] as String;
            _replyingToUserId = isSelf ? null : rm['authorId'] as String?;
          });
          return;
        }
      }
    }
  }

  void _cancelReply() => setState(() {
    _replyingTo = null;
    _replyingToParentId = null;
    _replyingToUserId = null;
  });

  void _toggleExpandReplies(String id) {
    setState(
      () => _expandedReplies.contains(id)
          ? _expandedReplies.remove(id)
          : _expandedReplies.add(id),
    );
  }

  Future<void> _send() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _sending) return;

    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      showFriendlyErrorDialog(
        context,
        'Your session has expired. Please log in again.',
      );
      return;
    }

    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    final optimisticComment = <String, dynamic>{
      'id': tempId,
      'postId': widget.post['id'],
      'parentId': _replyingToParentId,
      'authorId': userId,
      'author': _myDisplayName ?? 'You',
      'authorPhotoUrl': _myPhotoUrl,
      'authorPhotoPath': _myPhotoPath,
      'mentionedUser': null,
      'mentionedUserId': _replyingToUserId,
      'text': text,
      'likes': 0,
      'timestamp': DateTime.now(),
      'replies': <Map<String, dynamic>>[],
      'isSending': true,
    };

    final postId = widget.post['id'] as String;

    // Push into provider — survives sheet close/reopen
    CommunityPostsProvider.instance.addOptimisticComment(
      postId,
      optimisticComment,
    );

    // Clear local optimistic since provider now owns it
    setState(() {
      _optimisticComments = null;
      _replyingTo = null;
      _replyingToParentId = null;
      _replyingToUserId = null;
      _sending = true;
    });
    _inputController.clear();

    try {
      await _supabase.from('community_comments').insert({
        'post_id': postId,
        'parent_comment_id': optimisticComment['parentId'],
        'author_id': userId,
        'mentioned_user_id': optimisticComment['mentionedUserId'],
        'body': text,
      });
      // DB confirmed — flip isSending flag, keep comment visible
      if (mounted) {
        CommunityPostsProvider.instance.markOptimisticSent(postId, tempId);
      }
    } catch (e) {
      // Remove optimistic on failure
      CommunityPostsProvider.instance.removeOptimisticComment(postId, tempId);
      if (mounted) {
        if (e is PostgrestException &&
            (e.hint ?? '') == 'rate_limit_exceeded') {
          showRateLimitDialog(
            context,
            'You\'re commenting too fast. You can post up to 10 comments per minute. Please wait a moment before trying again.',
          );
        } else {
          showFriendlyErrorDialog(
            context,
            'Could not send your comment. Please try again.',
          );
        }
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _handleEditComment(Map<String, dynamic> entry) async {
    final id = entry['id'] as String;
    final currentText = (entry['text'] as String?) ?? '';
    final width = MediaQuery.of(context).size.width;

    final newText = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(width * 0.06)),
      ),
      builder: (ctx) =>
          EditCommentSheet(initialText: currentText, width: width),
    );

    if (newText == null ||
        newText.trim().isEmpty ||
        newText.trim() == currentText) {
      return;
    }

    final trimmed = newText.trim();

    setState(() {
      _optimisticComments = _patchText(_getComments(), id, trimmed);
    });

    try {
      await _supabase
          .from('community_comments')
          .update({'body': trimmed})
          .eq('id', id);
      // Realtime handles sync — optimistic state stays correct
    } catch (_) {
      if (mounted) {
        if (mounted) setState(() => _optimisticComments = null);
        showFriendlyErrorDialog(
          context,
          'Could not edit your comment. Please try again.',
        );
      }
    }
  }

  Future<void> _handleDeleteComment(Map<String, dynamic> entry) async {
    final id = entry['id'] as String;
    final width = MediaQuery.of(context).size.width;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(width * 0.06)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(0, width * 0.025, 0, width * 0.04),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              dragHandle(width),
              Container(
                width: width * 0.18,
                height: width * 0.18,
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.delete_outline_rounded,
                  size: width * 0.09,
                  color: const Color(0xFFEF4444),
                ),
              ),
              SizedBox(height: width * 0.04),
              Text(
                'Delete Comment?',
                style: TextStyle(
                  fontSize: width * 0.048,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF1F2937),
                ),
              ),
              SizedBox(height: width * 0.02),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: width * 0.1),
                child: Text(
                  'This comment will be permanently removed and cannot be undone.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: width * 0.034,
                    color: const Color(0xFF6B7280),
                    height: 1.45,
                  ),
                ),
              ),
              SizedBox(height: width * 0.05),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: width * 0.05),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => Navigator.pop(ctx, false),
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            vertical: width * 0.038,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3F4F6),
                            borderRadius: BorderRadius.circular(width * 0.035),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            'Cancel',
                            style: TextStyle(
                              fontSize: width * 0.038,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF374151),
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: width * 0.03),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => Navigator.pop(ctx, true),
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            vertical: width * 0.038,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444),
                            borderRadius: BorderRadius.circular(width * 0.035),
                          ),
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.delete_rounded,
                                color: Colors.white,
                                size: width * 0.042,
                              ),
                              SizedBox(width: width * 0.015),
                              Text(
                                'Delete',
                                style: TextStyle(
                                  fontSize: width * 0.038,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed != true) return;

    final snapshot = _getComments();
    setState(() {
      _optimisticComments = _removeById(snapshot, id);
    });

    try {
      final isTopLevel = entry['parentId'] == null;
      if (isTopLevel) {
        await _supabase
            .from('community_comments')
            .delete()
            .eq('parent_comment_id', id);
      }
      await _supabase.from('community_comments').delete().eq('id', id);
      // Realtime handles sync — optimistic state stays correct
    } catch (_) {
      if (mounted) {
        if (mounted) setState(() => _optimisticComments = null);
        showFriendlyErrorDialog(
          context,
          'Could not delete your comment. Please try again.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final comments = _getComments();

    final freshPost = CommunityPostsProvider.instance.sortedPosts.firstWhere(
      (p) => p['id'] == widget.post['id'],
      orElse: () => widget.post,
    );

    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollController) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(width * 0.06),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          children: [
            dragHandle(width),
            Padding(
              padding: EdgeInsets.fromLTRB(
                width * 0.05,
                0,
                width * 0.025,
                width * 0.025,
              ),
              child: Row(
                children: [
                  Text(
                    '${freshPost['commentCount'] ?? comments.length} ${(freshPost['commentCount'] ?? comments.length) == 1 ? "Comment" : "Comments"}',
                    style: TextStyle(
                      fontSize: width * 0.045,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF1F2937),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(
                      Icons.close_rounded,
                      size: width * 0.06,
                      color: const Color(0xFF6B7280),
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Container(height: 1, color: const Color(0xFFE5E7EB)),
            Expanded(
              child: ListView(
                controller: scrollController,
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  width * 0.04,
                  width * 0.03,
                  width * 0.04,
                  width * 0.03,
                ),
                children: [
                  _buildSheetPostSummary(
                    width,
                    freshPost,
                    freshPost['commentCount'] as int? ?? comments.length,
                  ),
                  SizedBox(height: width * 0.035),
                  Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  SizedBox(height: width * 0.025),
                  ...comments.map(
                    (c) => buildCommentItem(
                      context,
                      width,
                      c,
                      likedComments: widget.likedComments,
                      onToggleLike: (id) {
                        widget.onToggleLike(id);
                        setState(() {});
                      },
                      onReply: () => _setReplyByCommentId(
                        c['id'] as String,
                        c['author'] as String? ?? '',
                      ),
                      showReplies: true,
                      expandedReplies: _expandedReplies,
                      onToggleExpandReplies: _toggleExpandReplies,
                      onReplyToReply: (authorName, commentId) =>
                          _setReplyByCommentId(commentId, authorName),
                      currentUserId: _currentUserId,
                      onEdit: _handleEditComment,
                      onDelete: _handleDeleteComment,
                    ),
                  ),
                  SizedBox(height: width * 0.04),
                ],
              ),
            ),
            _buildCommentInput(width),
          ],
        ),
      ),
    );
  }

  Widget _buildSheetPostSummary(
    double width,
    Map<String, dynamic> post,
    int commentCount,
  ) {
    final postId = post['id'] as String;
    final isPostLiked = widget.likedPosts.contains(postId);
    final ts = post['timestamp'] as DateTime?;
    final timeAgo = ts != null ? formatTimeAgo(ts) : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            buildAuthorAvatar(
              width * 0.105,
              post['authorPhotoUrl'] as String?,
              photoPath: post['authorPhotoPath'] as String?,
            ),
            SizedBox(width: width * 0.025),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    post['author'] as String? ?? '',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: width * 0.038,
                      color: const Color(0xFF1F2937),
                    ),
                  ),
                  SizedBox(height: width * 0.004),
                  Wrap(
                    spacing: width * 0.018,
                    runSpacing: width * 0.005,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        '${post['barangay']} · $timeAgo',
                        style: TextStyle(
                          fontSize: width * 0.028,
                          color: const Color(0xFF6B7280),
                        ),
                      ),
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
                              post['tag'] as String? ?? '',
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
        ),
        SizedBox(height: width * 0.03),
        Text(
          post['title'] as String? ?? '',
          style: TextStyle(
            fontSize: width * 0.045,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF1F2937),
            height: 1.25,
          ),
        ),
        SizedBox(height: width * 0.012),
        Text(
          post['body'] as String? ?? '',
          style: TextStyle(
            fontSize: width * 0.034,
            color: const Color(0xFF374151),
            height: 1.45,
          ),
        ),
        SizedBox(height: width * 0.025),
        buildImageGrid(
          width,
          post['imageCount'] as int,
          imageUrls: post['imageUrls'] as List<String>? ?? [],
          onImageTap: (index) => openImageViewer(
            context,
            post['imageCount'] as int,
            index,
            urls: post['imageUrls'] as List<String>? ?? [],
          ),
        ),
        SizedBox(height: width * 0.03),
        Row(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                widget.onTogglePostLike(postId);
                setState(() {});
              },
              child: Row(
                children: [
                  Image.asset(
                    'assets/images/heart.png',
                    width: width * 0.046,
                    height: width * 0.046,
                    color: isPostLiked
                        ? const Color(0xFFEF4444)
                        : const Color(0xFF6B7280),
                    colorBlendMode: BlendMode.srcIn,
                    errorBuilder: (_, _, _) => Icon(
                      isPostLiked
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      size: width * 0.046,
                      color: isPostLiked
                          ? const Color(0xFFEF4444)
                          : const Color(0xFF6B7280),
                    ),
                  ),
                  SizedBox(width: width * 0.012),
                  Text(
                    '${post['likes']} likes',
                    style: TextStyle(
                      fontSize: width * 0.032,
                      fontWeight: FontWeight.w600,
                      color: isPostLiked
                          ? const Color(0xFFEF4444)
                          : const Color(0xFF6B7280),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: width * 0.05),
            Image.asset(
              'assets/images/comment.png',
              width: width * 0.048,
              height: width * 0.048,
              color: AppColors.primaryBlue,
              colorBlendMode: BlendMode.srcIn,
              errorBuilder: (_, _, _) => Icon(
                Icons.chat_bubble_outline_rounded,
                size: width * 0.048,
                color: AppColors.primaryBlue,
              ),
            ),
            SizedBox(width: width * 0.012),
            Text(
              '$commentCount comments',
              style: TextStyle(
                fontSize: width * 0.032,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF6B7280),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCommentInput(double width) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: Color(0xFFE5E7EB))),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_replyingTo != null)
              Container(
                width: double.infinity,
                padding: EdgeInsets.fromLTRB(
                  width * 0.05,
                  width * 0.025,
                  width * 0.03,
                  width * 0.025,
                ),
                decoration: const BoxDecoration(
                  color: Color(0xFFEFF6FF),
                  border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.reply_rounded,
                      size: width * 0.040,
                      color: AppColors.primaryBlue,
                    ),
                    SizedBox(width: width * 0.015),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: 'Replying to ',
                              style: TextStyle(
                                fontSize: width * 0.032,
                                color: const Color(0xFF6B7280),
                              ),
                            ),
                            TextSpan(
                              text: _replyingTo,
                              style: TextStyle(
                                fontSize: width * 0.032,
                                fontWeight: FontWeight.w800,
                                color: _replyingTo == 'yourself'
                                    ? const Color(0xFF6B7280)
                                    : AppColors.primaryBlue,
                                fontStyle: _replyingTo == 'yourself'
                                    ? FontStyle.italic
                                    : FontStyle.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: _cancelReply,
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: EdgeInsets.all(width * 0.015),
                        child: Icon(
                          Icons.close_rounded,
                          size: width * 0.045,
                          color: const Color(0xFF6B7280),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                width * 0.04,
                width * 0.03,
                width * 0.04,
                width * 0.03,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: width * 0.105,
                    height: width * 0.105,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFFE5E7EB),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: (_myPhotoUrl != null && _myPhotoUrl!.isNotEmpty)
                        ? CachedNetworkImage(
                            imageUrl: _myPhotoUrl!,
                            cacheKey: _myPhotoPath ?? _myPhotoUrl!,
                            memCacheWidth: 110,
                            fit: BoxFit.cover,
                            fadeInDuration: const Duration(milliseconds: 150),
                            placeholder: (context, url) => const Icon(
                              Icons.person_rounded,
                              color: Color(0xFF9CA3AF),
                            ),
                            errorWidget: (context, url, error) => const Icon(
                              Icons.person_rounded,
                              color: Color(0xFF9CA3AF),
                            ),
                          )
                        : const Icon(
                            Icons.person_rounded,
                            color: Color(0xFF9CA3AF),
                          ),
                  ),
                  SizedBox(width: width * 0.03),
                  Expanded(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: width * 0.35),
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: width * 0.04,
                          vertical: width * 0.022,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(width * 0.06),
                          border: Border.all(
                            color: _inputFocus.hasFocus
                                ? AppColors.primaryBlue.withValues(alpha: 0.4)
                                : Colors.transparent,
                            width: 1.5,
                          ),
                        ),
                        child: TextField(
                          controller: _inputController,
                          focusNode: _inputFocus,
                          maxLines: null,
                          minLines: 1,
                          keyboardType: TextInputType.multiline,
                          textCapitalization: TextCapitalization.sentences,
                          enabled: !_sending,
                          decoration: InputDecoration(
                            hintText: _replyingTo != null
                                ? 'Write a reply...'
                                : 'Write a comment...',
                            hintStyle: TextStyle(
                              fontSize: width * 0.035,
                              color: const Color(0xFF9CA3AF),
                            ),
                            border: InputBorder.none,
                            isCollapsed: true,
                          ),
                          style: TextStyle(
                            fontSize: width * 0.035,
                            color: const Color(0xFF1F2937),
                            height: 1.4,
                          ),
                          onSubmitted: (_) => _send(),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: width * 0.025),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _sending ? null : _send,
                    child: _sending
                        ? SizedBox(
                            width: width * 0.058,
                            height: width * 0.058,
                            child: const CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : Image.asset(
                            'assets/images/send.png',
                            width: width * 0.058,
                            height: width * 0.058,
                            fit: BoxFit.contain,
                            color: AppColors.primaryBlue,
                            errorBuilder: (_, _, _) => Icon(
                              Icons.send_rounded,
                              color: AppColors.primaryBlue,
                              size: width * 0.058,
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
}
