import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../screen/home_screen.dart';
import '../../../core/widgets/modal/verification_required_dialog.dart';
import '../../../core/utils/community_posts_provider.dart';
import '../../../core/widgets/Home/Newsfeed/news_feed_helpers.dart';
import '../../../core/widgets/Home/Newsfeed/image_grid.dart';
import '../../../core/widgets/Home/Newsfeed/comment_item.dart';
import '../../../core/widgets/Home/Newsfeed/comments_sheet.dart';

enum PostFilter {
  latest('Latest', null),
  day('Last Day', Duration(days: 1)),
  week('Last Week', Duration(days: 7)),
  month('Last Month', Duration(days: 30)),
  year('Last Year', Duration(days: 365));

  final String label;
  final Duration? duration;
  const PostFilter(this.label, this.duration);
}

class NewsFeedScreen extends StatefulWidget {
  final String username;
  final bool isVerified;

  const NewsFeedScreen({
    super.key,
    this.username = '',
    this.isVerified = false,
  });

  @override
  State<NewsFeedScreen> createState() => _NewsFeedScreenState();
}

class _NewsFeedScreenState extends State<NewsFeedScreen>
    with TickerProviderStateMixin {
  static const int _navIndex = 2;

  bool get _isVerified => widget.isVerified;

  final SupabaseClient _supabase = Supabase.instance.client;
  late final AnimationController _entryCtrl;

  PostFilter _currentFilter = PostFilter.latest;
  final Set<String> _likedComments = {};
  final Set<String> _likedPosts = {};

  @override
  void initState() {
    super.initState();
    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 80), () {
        if (mounted) _entryCtrl.forward();
      });
    });
    CommunityPostsProvider.instance.addListener(_onPostsChanged);
    CommunityPostsProvider.instance.refresh();
    _loadMyInteractions();
  }

  @override
  void dispose() {
    CommunityPostsProvider.instance.removeListener(_onPostsChanged);
    _entryCtrl.dispose();
    super.dispose();
  }

  void _onPostsChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadMyInteractions() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final postLikes = await _supabase
          .from('community_post_likes')
          .select('post_id')
          .eq('user_id', userId);
      final commentLikes = await _supabase
          .from('community_comment_likes')
          .select('comment_id')
          .eq('user_id', userId);
      if (!mounted) return;
      setState(() {
        _likedPosts
          ..clear()
          ..addAll(postLikes.map((r) => r['post_id'] as String));
        _likedComments
          ..clear()
          ..addAll(commentLikes.map((r) => r['comment_id'] as String));
      });
    } catch (_) {}
  }

  List<Map<String, dynamic>> get _filteredPosts {
    final posts = CommunityPostsProvider.instance.sortedPosts;
    if (_currentFilter == PostFilter.latest) return posts;
    final cutoff = DateTime.now().subtract(_currentFilter.duration!);
    return posts.where((p) {
      final ts = p['timestamp'] as DateTime?;
      return ts != null && ts.isAfter(cutoff);
    }).toList();
  }

  String _friendlyError(Object e) {
    final msg = e.toString();
    if (msg.contains('rate_limit') ||
        msg.contains('Rate limit') ||
        msg.contains('slow down') ||
        msg.contains('Slow down')) {
      return 'Slow down — too many actions in a short time.';
    }
    if (msg.contains('row-level security') ||
        msg.contains('violates row-level')) {
      return 'You don\'t have permission for that action.';
    }
    return 'Something went wrong. Try again.';
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  Widget _animated(int i, Widget child) {
    final start = (i * 0.12).clamp(0.0, 1.0);
    final end = (start + 0.50).clamp(0.0, 1.0);
    final fade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entryCtrl,
        curve: Interval(start, end, curve: Curves.easeOut),
      ),
    );
    final slide =
        Tween<Offset>(begin: const Offset(0.0, 0.30), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _entryCtrl,
            curve: Interval(start, end, curve: Curves.easeOutCubic),
          ),
        );
    return FadeTransition(
      opacity: fade,
      child: SlideTransition(position: slide, child: child),
    );
  }

  void _goToHome() {
    Navigator.pushAndRemoveUntil(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (_, _, _) => HomePage(username: widget.username),
        transitionsBuilder: (_, animation, _, child) => SlideTransition(
          position: Tween(begin: const Offset(-1, 0), end: Offset.zero).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeInOut),
          ),
          child: child,
        ),
      ),
      (route) => false,
    );
  }

  Future<void> _toggleLike(String commentId) async {
    if (!_isVerified) {
      showVerificationRequiredDialog(
        context,
        message:
            'Only verified citizens can like. Please complete identity verification first.',
      );
      return;
    }
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      _showSnack('Please log in again.');
      return;
    }
    final wasLiked = _likedComments.contains(commentId);
    setState(
      () => wasLiked
          ? _likedComments.remove(commentId)
          : _likedComments.add(commentId),
    );
    try {
      if (wasLiked) {
        await _supabase
            .from('community_comment_likes')
            .delete()
            .eq('comment_id', commentId)
            .eq('user_id', userId);
      } else {
        await _supabase.from('community_comment_likes').insert({
          'comment_id': commentId,
          'user_id': userId,
        });
      }
      await CommunityPostsProvider.instance.refresh();
    } catch (e) {
      if (mounted) {
        setState(
          () => wasLiked
              ? _likedComments.add(commentId)
              : _likedComments.remove(commentId),
        );
      }
      _showSnack(_friendlyError(e));
    }
  }

  Future<void> _togglePostLike(String postId) async {
    if (!_isVerified) {
      showVerificationRequiredDialog(
        context,
        message:
            'Only verified citizens can like posts. Please complete identity verification first.',
      );
      return;
    }
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      _showSnack('Please log in again.');
      return;
    }
    final wasLiked = _likedPosts.contains(postId);
    setState(
      () => wasLiked ? _likedPosts.remove(postId) : _likedPosts.add(postId),
    );
    try {
      if (wasLiked) {
        await _supabase
            .from('community_post_likes')
            .delete()
            .eq('post_id', postId)
            .eq('user_id', userId);
      } else {
        await _supabase.from('community_post_likes').insert({
          'post_id': postId,
          'user_id': userId,
        });
      }
      await CommunityPostsProvider.instance.refresh();
    } catch (e) {
      if (mounted) {
        setState(
          () => wasLiked ? _likedPosts.add(postId) : _likedPosts.remove(postId),
        );
      }
      _showSnack(_friendlyError(e));
    }
  }

  void _openFilterSheet() {
    final width = MediaQuery.of(context).size.width;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(width * 0.06)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(0, width * 0.025, 0, width * 0.03),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              dragHandle(width),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  width * 0.05,
                  width * 0.015,
                  width * 0.05,
                  width * 0.025,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.tune_rounded,
                      size: width * 0.05,
                      color: AppColors.primaryBlue,
                    ),
                    SizedBox(width: width * 0.02),
                    Text(
                      'Filter by Date',
                      style: TextStyle(
                        fontSize: width * 0.045,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF1F2937),
                      ),
                    ),
                  ],
                ),
              ),
              Container(height: 1, color: const Color(0xFFE5E7EB)),
              ...PostFilter.values.map((filter) {
                final isSelected = filter == _currentFilter;
                const subtitles = {
                  PostFilter.latest: 'Show all posts',
                  PostFilter.day: 'Posts from the last 24 hours',
                  PostFilter.week: 'Posts from the last 7 days',
                  PostFilter.month: 'Posts from the last 30 days',
                  PostFilter.year: 'Posts from the last 365 days',
                };
                return InkWell(
                  onTap: () {
                    setState(() => _currentFilter = filter);
                    Navigator.pop(ctx);
                  },
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: width * 0.05,
                      vertical: width * 0.032,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                filter.label,
                                style: TextStyle(
                                  fontSize: width * 0.04,
                                  fontWeight: isSelected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: isSelected
                                      ? AppColors.primaryBlue
                                      : const Color(0xFF374151),
                                ),
                              ),
                              SizedBox(height: width * 0.005),
                              Text(
                                subtitles[filter] ?? '',
                                style: TextStyle(
                                  fontSize: width * 0.030,
                                  color: const Color(0xFF9CA3AF),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isSelected)
                          Icon(
                            Icons.check_rounded,
                            size: width * 0.06,
                            color: AppColors.primaryBlue,
                          ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  void _openCommentsSheet(Map<String, dynamic> post, {String? initialReplyTo}) {
    if (!_isVerified) {
      showVerificationRequiredDialog(
        context,
        message:
            'Only verified citizens can view and post comments. Please complete identity verification first.',
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (sheetCtx) => CommentsSheet(
        post: post,
        initialReplyTo: initialReplyTo,
        likedComments: _likedComments,
        onToggleLike: _toggleLike,
        likedPosts: _likedPosts,
        onTogglePostLike: _togglePostLike,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final provider = CommunityPostsProvider.instance;
    final visiblePosts = _filteredPosts;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goToHome();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF3F4F6),
        body: SafeArea(
          child: Column(
            children: [
              _animated(0, _buildTopBar(width)),
              Expanded(
                child: provider.isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : provider.error != null
                    ? _buildErrorState(width, provider)
                    : visiblePosts.isEmpty
                    ? _animated(1, _buildEmptyState(width))
                    : RefreshIndicator(
                        onRefresh: () async {
                          await CommunityPostsProvider.instance.refresh();
                          await _loadMyInteractions();
                        },
                        child: ListView.separated(
                          physics: const BouncingScrollPhysics(),
                          padding: EdgeInsets.fromLTRB(
                            width * 0.04,
                            width * 0.035,
                            width * 0.04,
                            width * 0.04,
                          ),
                          itemCount: visiblePosts.length,
                          separatorBuilder: (_, _) =>
                              SizedBox(height: width * 0.035),
                          itemBuilder: (_, i) => _animated(
                            i + 1,
                            _buildPostCard(width, visiblePosts[i]),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: _buildBottomNav(width),
      ),
    );
  }

  Widget _buildTopBar(double width) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
        width * 0.04,
        width * 0.025,
        width * 0.04,
        width * 0.035,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Image.asset(
            'assets/images/newslogo.png',
            height: width * 0.075,
            fit: BoxFit.contain,
            alignment: Alignment.centerLeft,
            errorBuilder: (_, _, _) => Icon(
              Icons.broken_image_rounded,
              size: width * 0.10,
              color: const Color(0xFF9CA3AF),
            ),
          ),
          SizedBox(height: width * 0.045),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Community Updates',
                style: TextStyle(
                  fontSize: width * 0.052,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primaryBlue,
                ),
              ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _openFilterSheet,
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: width * 0.025,
                    vertical: width * 0.012,
                  ),
                  decoration: BoxDecoration(
                    color: _currentFilter != PostFilter.latest
                        ? AppColors.primaryBlue.withValues(alpha: 0.15)
                        : AppColors.primaryBlue.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(width * 0.04),
                    border: _currentFilter != PostFilter.latest
                        ? Border.all(
                            color: AppColors.primaryBlue.withValues(alpha: 0.4),
                            width: 1.2,
                          )
                        : null,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.tune_rounded,
                        size: width * 0.044,
                        color: AppColors.primaryBlue,
                      ),
                      SizedBox(width: width * 0.012),
                      Text(
                        _currentFilter.label,
                        style: TextStyle(
                          fontSize: width * 0.034,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primaryBlue,
                        ),
                      ),
                      SizedBox(width: width * 0.005),
                      Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: width * 0.045,
                        color: AppColors.primaryBlue,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(double width, CommunityPostsProvider provider) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.wifi_off_rounded,
            size: width * 0.18,
            color: const Color(0xFFD1D5DB),
          ),
          SizedBox(height: width * 0.04),
          Text(
            'Could not load posts',
            style: TextStyle(
              fontSize: width * 0.042,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF6B7280),
            ),
          ),
          SizedBox(height: width * 0.03),
          GestureDetector(
            onTap: provider.refresh,
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: width * 0.06,
                vertical: width * 0.03,
              ),
              decoration: BoxDecoration(
                color: AppColors.primaryBlue,
                borderRadius: BorderRadius.circular(width * 0.03),
              ),
              child: Text(
                'Retry',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: width * 0.038,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(double width) {
    const descMap = {
      PostFilter.latest: 'any time',
      PostFilter.day: 'the last 24 hours',
      PostFilter.week: 'the last 7 days',
      PostFilter.month: 'the last 30 days',
      PostFilter.year: 'the last 365 days',
    };
    return Center(
      child: Padding(
        padding: EdgeInsets.all(width * 0.08),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: width * 0.18,
              color: const Color(0xFFD1D5DB),
            ),
            SizedBox(height: width * 0.04),
            Text(
              'No posts found',
              style: TextStyle(
                fontSize: width * 0.042,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF6B7280),
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: width * 0.015),
            Text(
              'There are no posts from ${descMap[_currentFilter]}.\nTry a wider time range.',
              style: TextStyle(
                fontSize: width * 0.034,
                color: const Color(0xFF9CA3AF),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPostCard(double width, Map<String, dynamic> post) {
    final comments = post['comments'] as List<dynamic>;
    final commentCount = post['commentCount'] as int? ?? comments.length;
    final previewComments = comments.take(3).toList();
    final postId = post['id'] as String;
    final isPostLiked = _likedPosts.contains(postId);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(width * 0.035),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(width * 0.035),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPostHeader(width, post),
            SizedBox(height: width * 0.03),
            Text(
              post['title'] as String,
              style: TextStyle(
                fontSize: width * 0.045,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF1F2937),
                height: 1.25,
              ),
            ),
            SizedBox(height: width * 0.012),
            _buildPostBody(width, post['body'] as String),
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
            _buildPostFooter(
              width,
              post['likes'] as String,
              commentCount.toString(),
              () => _openCommentsSheet(post),
              liked: isPostLiked,
              onLikeTap: () => _togglePostLike(postId),
            ),
            if (commentCount > 0) ...[
              Padding(
                padding: EdgeInsets.symmetric(vertical: width * 0.025),
                child: Container(height: 1, color: const Color(0xFFE5E7EB)),
              ),
              ...previewComments.map(
                (c) => buildCommentItem(
                  context,
                  width,
                  c as Map<String, dynamic>,
                  likedComments: _likedComments,
                  onToggleLike: _toggleLike,
                  onReply: () => _openCommentsSheet(
                    post,
                    initialReplyTo: c['author'] as String,
                  ),
                  showReplies: false,
                  expandedReplies: const {},
                  onToggleExpandReplies: (_) {},
                  onReplyToReply: (_) {},
                ),
              ),
              if (commentCount > 3)
                Padding(
                  padding: EdgeInsets.only(top: width * 0.015),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _openCommentsSheet(post),
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
          ],
        ),
      ),
    );
  }

  Widget _buildPostHeader(double width, Map<String, dynamic> post) {
    final ts = post['timestamp'] as DateTime?;
    final timeAgo = ts != null ? formatTimeAgo(ts) : '';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        buildAuthorAvatar(width * 0.105, post['authorPhotoUrl'] as String?),
        SizedBox(width: width * 0.025),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                post['author'] as String,
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
                    '${post['barangay']} · $timeAgo',
                    style: TextStyle(
                      fontSize: width * 0.028,
                      color: const Color(0xFF6B7280),
                      fontWeight: FontWeight.w500,
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
        GestureDetector(
          onTap: () {},
          child: Padding(
            padding: EdgeInsets.only(left: width * 0.02, top: width * 0.005),
            child: Icon(
              Icons.more_horiz_rounded,
              size: width * 0.055,
              color: const Color(0xFF9CA3AF),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPostBody(double width, String body) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: body,
            style: TextStyle(
              fontSize: width * 0.034,
              color: const Color(0xFF374151),
              height: 1.45,
            ),
          ),
          TextSpan(
            text: '  See more...',
            style: TextStyle(
              fontSize: width * 0.034,
              color: const Color(0xFF9CA3AF),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _buildPostFooter(
    double width,
    String likes,
    String comments,
    VoidCallback onCommentsTap, {
    bool liked = false,
    VoidCallback? onLikeTap,
  }) {
    return Row(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onLikeTap,
          child: Row(
            children: [
              Image.asset(
                'assets/images/heart.png',
                width: width * 0.046,
                height: width * 0.046,
                color: liked
                    ? const Color(0xFFEF4444)
                    : const Color(0xFF6B7280),
                colorBlendMode: BlendMode.srcIn,
                errorBuilder: (_, _, _) => Icon(
                  liked
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  size: width * 0.046,
                  color: liked
                      ? const Color(0xFFEF4444)
                      : const Color(0xFF6B7280),
                ),
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
                'assets/images/comment.png',
                width: width * 0.048,
                height: width * 0.048,
                color: const Color(0xFF6B7280),
                colorBlendMode: BlendMode.srcIn,
                errorBuilder: (_, _, _) => Icon(
                  Icons.chat_bubble_outline_rounded,
                  size: width * 0.048,
                  color: const Color(0xFF6B7280),
                ),
              ),
              SizedBox(width: width * 0.012),
              Text(
                comments,
                style: TextStyle(
                  fontSize: width * 0.034,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF374151),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBottomNav(double width) {
    final iconSize = width * 0.065;
    const activeColor = Color(0xFF60A5FA);
    const inactiveColor = Color(0xFF9CA3AF);

    Widget buildIcon(String path, bool isActive) => SizedBox(
      width: iconSize,
      height: iconSize,
      child: ColorFiltered(
        colorFilter: ColorFilter.mode(
          isActive ? activeColor : inactiveColor,
          BlendMode.srcIn,
        ),
        child: Image.asset(path),
      ),
    );

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .06),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        elevation: 0,
        currentIndex: _navIndex,
        selectedItemColor: activeColor,
        unselectedItemColor: inactiveColor,
        selectedFontSize: width * 0.028,
        unselectedFontSize: width * 0.028,
        onTap: (index) {
          if (index == _navIndex) return;
          if (index == 0) {
            _goToHome();
          } else if (index == 1) {
            if (!_isVerified) {
              showVerificationRequiredDialog(
                context,
                message: 'Only verified citizens can access My Reports.',
              );
              return;
            }
            Navigator.pushNamed(
              context,
              '/my_reports',
              arguments: widget.username,
            );
          } else if (index == 3) {
            Navigator.pushNamed(
              context,
              '/emergency',
              arguments: {
                'username': widget.username,
                'isVerified': _isVerified,
              },
            );
          } else if (index == 4) {
            Navigator.pushNamed(
              context,
              '/settings',
              arguments: widget.username,
            );
          }
        },
        items: [
          BottomNavigationBarItem(
            icon: buildIcon('assets/images/home.png', _navIndex == 0),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: buildIcon('assets/images/my_reports.png', _navIndex == 1),
            label: 'My Reports',
          ),
          BottomNavigationBarItem(
            icon: buildIcon('assets/images/news_feed.png', _navIndex == 2),
            label: 'NewsFeed',
          ),
          BottomNavigationBarItem(
            icon: buildIcon('assets/images/emergency.png', _navIndex == 3),
            label: 'Emergency',
          ),
          BottomNavigationBarItem(
            icon: buildIcon('assets/images/settings.png', _navIndex == 4),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
