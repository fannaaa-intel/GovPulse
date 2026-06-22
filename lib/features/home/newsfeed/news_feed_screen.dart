import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../screen/home_screen.dart';
import '../../../core/widgets/modal/verification_required_dialog.dart';
import '../../../core/providers/community_posts_provider.dart';
import '../../../core/widgets/Home/Newsfeed/news_feed_helpers.dart';
import '../../../core/widgets/Home/Newsfeed/image_grid.dart';
import '../../../core/widgets/Home/Newsfeed/comment_item.dart';
import '../../../core/widgets/Home/Newsfeed/comments_sheet.dart';
import '../../../core/widgets/loading/loading_overlay.dart';
import '../../../core/widgets/Home/Newsfeed/rate_limit_dialogs.dart';
import '../../../core/widgets/Home/nav/responsive_nav_scaffold.dart';

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
  final String? userBarangay;
  final bool isGuest;

  const NewsFeedScreen({
    super.key,
    this.username = '',
    this.isVerified = false,
    this.userBarangay,
    this.isGuest = false,
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
  final Set<String> _expandedPosts = {};

  @override
  void initState() {
    super.initState();
    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    CommunityPostsProvider.instance.setGuestMode(widget.isGuest);
    CommunityPostsProvider.instance.addListener(_onPostsChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 80), () {
        if (mounted) _entryCtrl.forward();
      });
      CommunityPostsProvider.instance.refresh();
      _loadMyInteractions();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Decode the header logo before the first paint so it doesn't pop in a
    // frame or two after the rest of the app bar. (Running this inside a
    // post-frame callback, as before, was the cause of the visible delay.)
    precacheImage(const AssetImage('assets/images/newslogo.webp'), context);
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
    var posts = CommunityPostsProvider.instance.sortedPosts;

    // Barangay targeting (logged-in users only — guests see everything):
    //   • city-wide / LGU broadcasts (empty barangay) → always shown
    //   • user has a barangay  → also show posts for that barangay
    //   • user has NO barangay yet (e.g. signed up but not verified) →
    //     city-wide / LGU broadcasts only, never other barangays' posts
    if (!widget.isGuest) {
      final ub = widget.userBarangay?.trim().toLowerCase() ?? '';
      posts = posts.where((p) {
        final pb = (p['barangay'] as String?)?.trim().toLowerCase() ?? '';
        if (pb.isEmpty) return true; // city-wide / LGU broadcast
        if (ub.isEmpty) return false; // no barangay yet → city-wide only
        return pb == ub; // otherwise must match the user's barangay
      }).toList();
    }

    // ── Date filter (existing) ───────────────────────────────────────────
    if (_currentFilter == PostFilter.latest) return posts;
    final cutoff = DateTime.now().subtract(_currentFilter.duration!);
    return posts.where((p) {
      final ts = p['timestamp'] as DateTime?;
      return ts != null && ts.isAfter(cutoff);
    }).toList();
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
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      PageRouteBuilder(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, _, _) => HomePage(username: widget.username),
        transitionsBuilder: (_, _, _, child) => child,
      ),
      (route) => false,
    );
  }

  void _showGuestSignupNudge() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true, // ← add this
      useRootNavigator: true, // ← add this
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        // ← wrap with SafeArea
        top: false, // ← only pad bottom
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.lock_outline_rounded,
                size: 40,
                color: AppColors.primaryBlue,
              ),
              const SizedBox(height: 12),
              const Text(
                'Create an account',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              const Text(
                'Sign up to like, comment, and report issues.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF6B7280)),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/signup');
                  },
                  child: const Text(
                    'Create Account',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _toggleLike(String commentId) async {
    if (widget.isGuest) {
      _showGuestSignupNudge();
      return;
    }
    if (!_isVerified) {
      showVerificationRequiredDialog(
        context,
        isVerified: _isVerified,
        message:
            'Only verified citizens can like. Please complete identity verification first.',
      );
      return;
    }
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      showFriendlyErrorDialog(
        context,
        'Your session has expired. Please log in again.',
      );
      return;
    }
    final wasLiked = _likedComments.contains(commentId);
    setState(
      () => wasLiked
          ? _likedComments.remove(commentId)
          : _likedComments.add(commentId),
    );
    CommunityPostsProvider.instance.bumpCommentLike(
      commentId,
      wasLiked ? -1 : 1,
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
    } catch (e) {
      if (mounted) {
        setState(
          () => wasLiked
              ? _likedComments.add(commentId)
              : _likedComments.remove(commentId),
        );
        CommunityPostsProvider.instance.bumpCommentLike(
          commentId,
          wasLiked ? 1 : -1,
        );
        if (e is PostgrestException &&
            (e.hint ?? '') == 'rate_limit_exceeded') {
          showRateLimitDialog(
            context,
            'You\'ve liked too many comments. You can like up to 60 comments per minute. Please wait a moment before trying again.',
          );
        } else {
          showFriendlyErrorDialog(
            context,
            'Unable to process your like. Please try again.',
          );
        }
      }
    }
  }

  Future<void> _togglePostLike(String postId) async {
    if (widget.isGuest) {
      _showGuestSignupNudge();
      return;
    }
    if (!_isVerified) {
      showVerificationRequiredDialog(
        context,
        isVerified: _isVerified,
        message:
            'Only verified citizens can like posts. Please complete identity verification first.',
      );
      return;
    }
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      showFriendlyErrorDialog(
        context,
        'Your session has expired. Please log in again.',
      );
      return;
    }
    final wasLiked = _likedPosts.contains(postId);
    setState(
      () => wasLiked ? _likedPosts.remove(postId) : _likedPosts.add(postId),
    );
    CommunityPostsProvider.instance.bumpPostLike(postId, wasLiked ? -1 : 1);
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
    } catch (e) {
      if (mounted) {
        setState(
          () => wasLiked ? _likedPosts.add(postId) : _likedPosts.remove(postId),
        );
        CommunityPostsProvider.instance.bumpPostLike(postId, wasLiked ? 1 : -1);
        if (e is PostgrestException &&
            (e.hint ?? '') == 'rate_limit_exceeded') {
          showRateLimitDialog(
            context,
            'You\'ve liked too many posts. You can like up to 60 posts per minute. Please wait a moment before trying again.',
          );
        } else {
          showFriendlyErrorDialog(
            context,
            'Unable to process your like. Please try again.',
          );
        }
      }
    }
  }

  void _openFilterSheet() {
    final width = MediaQuery.of(context).size.width.clamp(0.0, 480.0);
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
    if (widget.isGuest) {
      _showGuestSignupNudge();
      return;
    }
    if (!_isVerified) {
      showVerificationRequiredDialog(
        context,
        isVerified: _isVerified,
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
    final width = MediaQuery.of(context).size.width.clamp(0.0, 480.0);
    final provider = CommunityPostsProvider.instance;
    final visiblePosts = _filteredPosts;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (!mounted) return;
        if (widget.isGuest) {
          Navigator.of(context).pop(); // go back to /guest
        } else {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _goToHome();
          });
        }
      },
      child: ResponsiveNavScaffold(
        showNav: !widget.isGuest,
        currentIndex: _navIndex,
        username: widget.username,
        isVerified: _isVerified,
        userBarangay: widget.userBarangay,
        backgroundColor: const Color(0xFFF3F4F6),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                children: [
                  _buildTopBar(width),
                  Expanded(
                    child: LoadingOverlay.bodyOrSkeleton(
                      isLoading:
                          !provider.initialLoadDone && provider.isLoading,
                      layout: SkeletonLayout.newsFeed,
                      child: provider.error != null
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
                  ),
                ],
              ),
            ),
          ),
        ),
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
          if (widget.isGuest)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                if (mounted) Navigator.of(context).pop();
              },
              child: Padding(
                padding: EdgeInsets.only(bottom: width * 0.02),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: width * 0.045,
                      color: AppColors.primaryBlue,
                    ),
                    SizedBox(width: width * 0.015),
                    Text(
                      'Back',
                      style: TextStyle(
                        fontSize: width * 0.038,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primaryBlue,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Image.asset(
            'assets/images/newslogo.webp',
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

  /// On the guest feed, comment authors are anonymised the same way post
  /// authors are: "Citizen" + default avatar, with any @mention masked too.
  /// Officials (if the comment carries that flag) keep their real identity.
  Map<String, dynamic> _maskCommentForGuest(Map<String, dynamic> c) {
    if (!widget.isGuest) return c;
    if (c['isOfficial'] == true) return c;
    return {
      ...c,
      'author': 'Citizen',
      'authorPhotoUrl': null,
      'authorPhotoPath': null,
      if (c['mentionedUser'] != null) 'mentionedUser': 'Citizen',
    };
  }

  Widget _buildPostCard(double width, Map<String, dynamic> post) {
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
    final previewComments = allActivity.take(3).toList();
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
            _buildPostBody(width, post['body'] as String, post['id'] as String),
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
              ...previewComments.map((rawComment) {
                final comment = _maskCommentForGuest(rawComment);
                final isReply = comment['parentId'] != null;
                if (isReply) {
                  return buildReplyItem(
                    context,
                    width,
                    comment,
                    likedComments: _likedComments,
                    onToggleLike: _toggleLike,
                    onReply: () => _openCommentsSheet(
                      post,
                      initialReplyTo: comment['author'] as String,
                    ),
                  );
                }
                return buildCommentItem(
                  context,
                  width,
                  comment,
                  likedComments: _likedComments,
                  onToggleLike: _toggleLike,
                  onReply: () => _openCommentsSheet(
                    post,
                    initialReplyTo: comment['author'] as String,
                  ),
                  showReplies: false,
                  expandedReplies: const {},
                  onToggleExpandReplies: (_) {},
                  onReplyToReply: (_, _) {},
                );
              }),
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
        ),
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
                    () {
                      final b = (post['barangay'] as String?)?.trim() ?? '';
                      return b.isEmpty ? timeAgo : '$b · $timeAgo';
                    }(),
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
      ],
    );
  }

  Widget _buildPostBody(double width, String body, String postId) {
    final isExpanded = _expandedPosts.contains(postId);
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
              onTap: () => setState(() {
                if (isExpanded) {
                  _expandedPosts.remove(postId);
                } else {
                  _expandedPosts.add(postId);
                }
              }),
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
                'assets/images/heart.webp',
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
                'assets/images/comment.webp',
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
}
