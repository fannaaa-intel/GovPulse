import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../screen/home_screen.dart';
import '../../../core/widgets/deeplink_highlight.dart';
import '../../../core/widgets/modal/verification_required_dialog.dart';
import '../../../core/moderation/profanity_filter.dart';
import '../../../core/providers/community_posts_provider.dart';
import '../../../core/widgets/Home/Newsfeed/news_feed_helpers.dart';
import '../../../core/widgets/Home/Newsfeed/image_grid.dart';
import '../../../core/widgets/Home/Newsfeed/comment_item.dart';
import '../../../core/widgets/Home/Newsfeed/comments_sheet.dart';
import '../../../core/widgets/loading/loading_overlay.dart';
import '../../../core/widgets/app_snackbar.dart';
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

  /// When set (e.g. opened from a like/comment notification), the feed jumps to
  /// this post once loaded. [initialOpenComments] also opens its comment thread.
  final String? initialPostId;
  final bool initialOpenComments;

  /// Flash [initialPostId] on arrival. False for hearts — a reaction scrolls
  /// you to the post but doesn't warrant singling it out (see
  /// [kHeartNotifTypes]).
  final bool initialHighlightPost;

  /// The specific comment/reply a notification pointed at. When set alongside
  /// [initialOpenComments], the sheet scrolls to it and flashes it blue.
  final String? initialCommentId;

  const NewsFeedScreen({
    super.key,
    this.username = '',
    this.isVerified = false,
    this.userBarangay,
    this.isGuest = false,
    this.initialPostId,
    this.initialOpenComments = false,
    this.initialHighlightPost = false,
    this.initialCommentId,
  });

  @override
  State<NewsFeedScreen> createState() => _NewsFeedScreenState();
}

class _NewsFeedScreenState extends State<NewsFeedScreen>
    with TickerProviderStateMixin, DeepLinkHighlightMixin {
  static const int _navIndex = 2;

  bool get _isVerified => widget.isVerified;

  final SupabaseClient _supabase = Supabase.instance.client;
  late final AnimationController _entryCtrl;

  PostFilter _currentFilter = PostFilter.latest;
  final Set<String> _likedComments = {};
  final Set<String> _likedPosts = {};
  final Set<String> _commentedPosts = {};
  final Set<String> _expandedPosts = {};

  // Deep-link support: jump to the post a notification pointed at, once loaded.
  // Scroll + flash come from DeepLinkHighlightMixin (shared with My Submissions
  // and the admin/staff consoles), so every deep-link lands the same way.
  bool _handledInitialPost = false;

  // The reference a notification carried can be a POST id or (from the comment
  // triggers) a COMMENT id — resolved lazily: when no post matches, one lookup
  // against community_comments maps it to its post + the comment to highlight.
  late String? _targetPostId = widget.initialPostId;
  late String? _targetCommentId = widget.initialCommentId;
  bool _triedCommentResolve = false;

  Future<void> _tryResolveCommentRef(String ref) async {
    if (_triedCommentResolve) return;
    _triedCommentResolve = true;
    try {
      final row = await _supabase
          .from('community_comments')
          .select('id, post_id')
          .eq('id', ref)
          .maybeSingle();
      final postId = row?['post_id'] as String?;
      if (postId == null || !mounted) return;
      setState(() {
        _targetPostId = postId;
        _targetCommentId = ref;
      });
      _maybeHandleInitialPost();
    } catch (_) {
      /* ref stays unresolved — the feed just opens normally */
    }
  }

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
    _maybeHandleInitialPost();
  }

  /// Once posts are loaded, jump to the post a notification pointed at. Opens
  /// its comment thread for comment/reply taps; best-effort scrolls it into
  /// view for like taps. Runs at most once.
  void _maybeHandleInitialPost() {
    if (_handledInitialPost) return;
    final targetId = _targetPostId;
    if (targetId == null) return;

    Map<String, dynamic>? post;
    for (final p in _filteredPosts) {
      if (p['id'] == targetId) {
        post = p;
        break;
      }
    }
    if (post == null) {
      // Not a post we can see — the reference may be a comment id (the live
      // comment triggers stamp those). One-shot resolve, then this runs again.
      if (CommunityPostsProvider.instance.initialLoadDone) {
        _tryResolveCommentRef(targetId);
      }
      return;
    }
    _handledInitialPost = true;

    final target = post;
    // Scrolls into view, and flashes only when the notification was real
    // content (a comment/reply) rather than a heart.
    flashHighlight(widget.initialHighlightPost ? targetId : null);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!widget.initialHighlightPost) {
        // Hearts don't flash, but must still be scrolled to.
        final ctx = highlightKey(targetId).currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(
            ctx,
            duration: kHighlightScroll,
            curve: Curves.easeOutCubic,
            alignment: kHighlightAlignment,
          );
        }
      }
      if (widget.initialOpenComments) {
        _openCommentsSheet(target, highlightCommentId: _targetCommentId);
      }
    });
  }

  /// Draws the deep-link flash as a ring around a post card. The card owns its
  /// own surface, so the accent goes outside it rather than replacing it.
  Widget _highlightWrap(String postId, double width, Widget card) =>
      highlightRing(
        highlighted: isHighlighted(postId),
        radius: width * 0.05,
        accent: AppColors.primaryBlue,
        child: card,
      );

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
      // Posts this user has commented on → drives the blue "commented" state.
      List<dynamic> myComments = const [];
      try {
        myComments = await _supabase
            .from('community_comments')
            .select('post_id')
            .eq('author_id', userId);
      } catch (_) {
        /* read may be restricted; blue state just won't show */
      }
      if (!mounted) return;
      setState(() {
        _likedPosts
          ..clear()
          ..addAll(postLikes.map((r) => r['post_id'] as String));
        _likedComments
          ..clear()
          ..addAll(commentLikes.map((r) => r['comment_id'] as String));
        _commentedPosts
          ..clear()
          ..addAll(myComments.map((r) => r['post_id'] as String));
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
        username: widget.username,
        message:
            'Only verified citizens can like. Please complete identity verification first.',
      );
      return;
    }
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      showAppSnackBar(
        context,
        "Your session has expired. Please log in again.",
        type: AppSnackType.error,
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
          showAppSnackBar(
            context,
            "You've liked too many comments. Please wait a moment before trying again.",
            type: AppSnackType.error,
          );
        } else {
          showAppSnackBar(
            context,
            "Unable to process your like. Please try again.",
            type: AppSnackType.error,
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
        username: widget.username,
        message:
            'Only verified citizens can like posts. Please complete identity verification first.',
      );
      return;
    }
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      showAppSnackBar(
        context,
        "Your session has expired. Please log in again.",
        type: AppSnackType.error,
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
          showAppSnackBar(
            context,
            "You've liked too many posts. Please wait a moment before trying again.",
            type: AppSnackType.error,
          );
        } else {
          showAppSnackBar(
            context,
            "Unable to process your like. Please try again.",
            type: AppSnackType.error,
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

  void _openCommentsSheet(
    Map<String, dynamic> post, {
    String? initialReplyTo,
    String? highlightCommentId,
  }) {
    if (widget.isGuest) {
      _showGuestSignupNudge();
      return;
    }
    if (!_isVerified) {
      showVerificationRequiredDialog(
        context,
        isVerified: _isVerified,
        username: widget.username,
        message:
            'Only verified citizens can view and post comments. Please complete identity verification first.',
      );
      return;
    }
    showCommentsSheet(
      context,
      post: post,
      initialReplyTo: initialReplyTo,
      likedComments: _likedComments,
      onToggleLike: _toggleLike,
      highlightCommentId: highlightCommentId,
    ).whenComplete(_loadMyInteractions);
  }

  @override
  Widget build(BuildContext context) {
    final rawWidth = MediaQuery.of(context).size.width;
    // WEB / large screens: feed column + info rail that fills the width, instead
    // of a stranded 480px phone column. Phones & narrow web keep the original
    // body (design width capped at 480), byte-for-byte unchanged.
    final bool wide = kIsWeb && rawWidth >= 900;
    final double width = wide ? 480.0 : rawWidth.clamp(0.0, 480.0);
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
          child: wide
              ? LoadingOverlay.bodyOrSkeleton(
                  isLoading: !provider.initialLoadDone && provider.isLoading,
                  layout: SkeletonLayout.newsFeed,
                  child: _buildNewsFeedWebBody(width, provider, visiblePosts),
                )
              : Center(
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
                                      await CommunityPostsProvider.instance
                                          .refresh();
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
                                      itemBuilder: (_, i) {
                                        final post = visiblePosts[i];
                                        final pid = post['id'] as String;
                                        return KeyedSubtree(
                                          key: highlightKey(pid),
                                          child: _animated(
                                            i + 1,
                                            _highlightWrap(
                                              pid,
                                              width,
                                              _buildPostCard(width, post),
                                            ),
                                          ),
                                        );
                                      },
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

  // ── WEB body: centered feed column + info rail ─────────────────────────────
  Widget _buildNewsFeedWebBody(
    double w,
    CommunityPostsProvider provider,
    List<Map<String, dynamic>> visiblePosts,
  ) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 56),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Feed column
                SizedBox(
                  width: 600,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildTopBar(w),
                      const SizedBox(height: 20),
                      if (provider.error != null)
                        _buildErrorState(w, provider)
                      else if (visiblePosts.isEmpty)
                        _animated(1, _buildEmptyState(w))
                      else
                        for (int i = 0; i < visiblePosts.length; i++) ...[
                          KeyedSubtree(
                            key: highlightKey(visiblePosts[i]['id'] as String),
                            child: _animated(
                              i + 1,
                              _highlightWrap(
                                visiblePosts[i]['id'] as String,
                                w,
                                _buildPostCard(w, visiblePosts[i]),
                              ),
                            ),
                          ),
                          if (i < visiblePosts.length - 1)
                            const SizedBox(height: 16),
                        ],
                    ],
                  ),
                ),
                const SizedBox(width: 32),
                // Info rail
                SizedBox(width: 300, child: _buildNewsFeedRail()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNewsFeedRail() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _railCard(
          icon: Icons.campaign_rounded,
          color: AppColors.primaryBlue,
          title: 'Community Updates',
          body:
              'Official posts and announcements from LGU Aparri and your '
              'barangay. Use the filter to narrow updates by time.',
        ),
        const SizedBox(height: 16),
        _railCard(
          icon: Icons.place_rounded,
          color: const Color(0xFF059669),
          title: (widget.userBarangay?.isNotEmpty ?? false)
              ? widget.userBarangay!
              : 'Your Area',
          body:
              "You're seeing updates for your barangay along with city-wide "
              'announcements from the municipal government.',
        ),
        const SizedBox(height: 16),
        _railCard(
          icon: Icons.verified_user_rounded,
          color: const Color(0xFFD97706),
          title: 'Stay Informed',
          body:
              'Interactions and comments are moderated. Please keep posts '
              'respectful and relevant to the Aparri community.',
        ),
      ],
    );
  }

  Widget _railCard({
    required IconData icon,
    required Color color,
    required String title,
    required String body,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 19, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF111827),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            body,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.5,
              color: Color(0xFF6B7280),
            ),
          ),
        ],
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
            if (post['pinned'] == true) ...[
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
              SizedBox(height: width * 0.02),
            ],
            _buildPostHeader(width, post),
            SizedBox(height: width * 0.03),
            Text(
              ProfanityFilter.maskForDisplay(post['title'] as String),
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
              commented: _commentedPosts.contains(postId),
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

  Widget _buildPostBody(double width, String rawBody, String postId) {
    // Mask any profanity for display — citizens never see it, even if the row
    // slipped past the client (the original text is untouched in the DB).
    final body = ProfanityFilter.maskForDisplay(rawBody);
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
