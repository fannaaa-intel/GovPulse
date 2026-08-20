import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../core/theme/citizen_ui.dart';
import '../screen/home_screen.dart';
import '../../../core/router/legacy_nav.dart';
// CitizenTab.home.path — the shell's Home location, for the web arm of the
// non-guest back handler. Already in this file's transitive graph via
// legacy_nav, so the direct import adds no weight and no new cycle.
import '../shell/citizen_shell_router.dart' show CitizenTab;
import '../../../core/widgets/deeplink_highlight.dart';
import '../../../core/widgets/modal/verification_required_dialog.dart';
import '../../../core/providers/community_posts_provider.dart';
import '../../../core/providers/user_profile_provider.dart';
import '../../../core/widgets/Home/Newsfeed/news_feed_helpers.dart';
import '../../../core/widgets/Home/Newsfeed/comments_sheet.dart';
import '../../../core/widgets/Home/Newsfeed/newsfeed_post_card.dart';
import '../../../core/widgets/Home/Newsfeed/feed_empty_state.dart';
import '../shell/citizen_shell.dart' show CitizenShell;
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

class NewsFeedScreen extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (isGuest) {
          // Web navigates, mobile pops — the feed is a top-level route on one
          // and a pushed screen on the other. See [leaveGuestFeed].
          leaveGuestFeed(context);
        } else {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!context.mounted) return;
            // On web this lands on the SHELL's Home pane, declaratively.
            //
            // This branch is reachable on web, which is not obvious: the
            // /newsfeed GoRoute hardcodes isGuest: true and the shell's Home
            // pane mounts NewsFeedBody, so neither produces a non-guest
            // NewsFeedScreen. The legacy /newsfeed route does, and it is
            // reached from the HomePage nav — which a web citizen can land on
            // by completing the verification wizard, whose final step pushes
            // HomePage with no kIsWeb guard (see the success dialog in
            // verification_face_scan_screen.dart). That upstream push is the
            // root cause and is deliberately NOT fixed here; it is its own
            // ticket, and its mobile route differs from this one.
            //
            // Pushing HomePage here would be wrong on web regardless of how we
            // arrived: it is a pageless push over go_router's stack, so the
            // address bar would stop describing the screen, and HomePage is
            // the legacy MOBILE surface — the web equivalent is the shell.
            if (kIsWeb) {
              context.go(CitizenTab.home.path);
              return;
            }
            Navigator.pushAndRemoveUntil(
              context,
              PageRouteBuilder(
                transitionDuration: Duration.zero,
                reverseTransitionDuration: Duration.zero,
                pageBuilder: (_, _, _) => HomePage(username: username),
                transitionsBuilder: (_, _, _, child) => child,
              ),
              (route) => false,
            );
          });
        }
      },
      child: ResponsiveNavScaffold(
        showNav: !isGuest,
        currentIndex: 2,
        username: username,
        isVerified: isVerified,
        userBarangay: userBarangay,
        backgroundColor: const Color(0xFFF3F4F6),
        body: SafeArea(
          child: NewsFeedBody(
            isGuest: isGuest,
            initialPostId: initialPostId,
            initialOpenComments: initialOpenComments,
            initialHighlightPost: initialHighlightPost,
            initialCommentId: initialCommentId,
          ),
        ),
      ),
    );
  }
}

/// NewsFeed content, with no chrome of its own. Rendered inside
/// [NewsFeedScreen] on mobile and directly as a centre pane by the web shell.
///
/// Takes no `username` / `isVerified` / `userBarangay`: all three come from
/// [userProfileProvider], which is the same source the caller was reading them
/// from before passing them down. [isGuest] stays a parameter because a guest
/// has no profile to read.
class NewsFeedBody extends ConsumerStatefulWidget {
  /// Rendered as the citizen shell's centre column rather than as a page.
  ///
  /// Two differences, both because the shell already provides what the
  /// standalone page had to provide for itself:
  ///   • the 300px info rail is dropped — the shell has two rails of its own,
  ///     and at 932px the feed+rail pair simply does not fit the centre column;
  ///   • the feed column flexes to the width it is given instead of being
  ///     centred at a fixed 600px inside a 1080px page.
  /// Everything else — the filter bar, the posts, the loading, error and empty
  /// states — is identical.
  final bool embedded;

  final bool isGuest;
  final String? initialPostId;
  final bool initialOpenComments;
  final bool initialHighlightPost;
  final String? initialCommentId;

  const NewsFeedBody({
    super.key,
    this.embedded = false,
    this.isGuest = false,
    this.initialPostId,
    this.initialOpenComments = false,
    this.initialHighlightPost = false,
    this.initialCommentId,
  });

  @override
  ConsumerState<NewsFeedBody> createState() => _NewsFeedScreenState();
}

class _NewsFeedScreenState extends ConsumerState<NewsFeedBody>
    with TickerProviderStateMixin, DeepLinkHighlightMixin {
  UserProfile? get _profile => ref.read(userProfileProvider).valueOrNull;

  String get _username => _profile?.username ?? '';
  String? get _userBarangay => _profile?.barangay;
  bool get _isVerified => _profile?.isVerified ?? false;

  final SupabaseClient _supabase = Supabase.instance.client;

  /// Opacity the staggered entrance starts from ON WEB, so the first painted
  /// frame already shows content. Mobile still fades from zero. Matches the
  /// floor the auth screens use — same problem, same value.
  static const double _kWebFadeFloor = 0.35;

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

  /// Picks up a deep link that arrives while the feed is ALREADY MOUNTED.
  ///
  /// ── Web-only, and inert on mobile even unguarded ───────────────────────────
  /// On mobile the feed is pushed fresh for every deep link, so it gets a new
  /// State and the `late` initialisers above do the whole job — this would
  /// never fire. The kIsWeb guard makes that provable rather than argued, and
  /// const-folds the body away off web.
  ///
  /// On web the feed is the shell's Home pane and stays mounted for the whole
  /// session, so a second notification tap only changes this widget's
  /// parameters. Without this, `_targetPostId` keeps its first value (a `late`
  /// initialiser runs once) and `_handledInitialPost` is already true — so
  /// tapping notification A then notification B silently did nothing for B.
  ///
  /// ── Why the equality check is load-bearing ─────────────────────────────────
  /// A StatefulShellRoute branch remembers its location, so switching tabs and
  /// coming back rebuilds this with the SAME query string. Re-running the
  /// handler there would re-open a thread the user already closed. Only an
  /// actual change of target resets anything.
  @override
  void didUpdateWidget(NewsFeedBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!kIsWeb) return;

    final unchanged =
        widget.initialPostId == oldWidget.initialPostId &&
        widget.initialOpenComments == oldWidget.initialOpenComments &&
        widget.initialHighlightPost == oldWidget.initialHighlightPost &&
        widget.initialCommentId == oldWidget.initialCommentId;
    if (unchanged) return;

    // Re-arm every piece of one-shot state the first deep link consumed, so the
    // new target is treated exactly like a fresh mount would treat it.
    _targetPostId = widget.initialPostId;
    _targetCommentId = widget.initialCommentId;
    _handledInitialPost = false;
    _triedCommentResolve = false;
    // No highlight reset needed: flashHighlight has no per-id latch, and its
    // hold timer already declines to clear an accent a later deep link took
    // over (see the `_highlightId == id` guard in DeepLinkHighlightMixin).

    if (_targetPostId == null) return;
    // Deferred, not called inline: the handler flashes the highlight and can
    // setState, and didUpdateWidget runs during the parent's build. Posting it
    // matches how the handler already schedules its own scroll work.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _maybeHandleInitialPost();
    });
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
      final ub = _userBarangay?.trim().toLowerCase() ?? '';
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
    // Floored on web for the same reason the auth screens are: `go()` tears the
    // outgoing screen down, so a fade starting at 0 leaves an empty scaffold for
    // the 80ms before the entrance begins. Mobile reaches this feed by an
    // imperative push that swaps in an opaque route instantly, so nothing is
    // ever visibly blank there and it keeps fading from zero.
    //
    // The Interval stagger is untouched — items still arrive in sequence, they
    // just start faintly visible instead of invisible.
    final fade = Tween<double>(begin: kIsWeb ? _kWebFadeFloor : 0.0, end: 1.0)
        .animate(
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
                    // The pop stays FIRST and stays unguarded: it closes this
                    // nudge sheet, and it must happen before the navigation on
                    // both platforms. `context` is the State's, not the sheet
                    // builder's, so it is still valid afterwards.
                    Navigator.pop(context);
                    goToSignup(context);
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
        username: _username,
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
        username: _username,
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
              Container(height: 1, color: CitizenUi.sharedBorder),
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
        username: _username,
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
    // Embedded, the shell hands this body a column narrower than the viewport,
    // so the viewport-based `wide` test would be wrong in both directions. In
    // the shell the web layout is always the right one.
    final bool wide = widget.embedded || (kIsWeb && rawWidth >= 900);
    final double width = wide ? 480.0 : rawWidth.clamp(0.0, 480.0);
    final provider = CommunityPostsProvider.instance;
    final visiblePosts = _filteredPosts;

    return wide
        ? LoadingOverlay.bodyOrSkeleton(
            isLoading: !provider.initialLoadDone && provider.isLoading,
            layout: SkeletonLayout.newsFeed,
            // Same `wide` that chose the web body. Embedded in the shell this is
            // true and the feed skeleton is the two-column one; the standalone
            // guest route in a narrow browser is false and keeps the phone
            // skeleton, matching the phone body it is about to render.
            webWide: wide,
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
          );
  }

  // ── WEB body: centered feed column + info rail ─────────────────────────────
  Widget _buildNewsFeedWebBody(
    double w,
    CommunityPostsProvider provider,
    List<Map<String, dynamic>> visiblePosts,
  ) {
    final feed = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTopBar(w, webFilterStyle: true),
        const SizedBox(height: 20),
        if (provider.error != null)
          _buildErrorState(w, provider)
        else if (visiblePosts.isEmpty)
          _animated(1, _buildWebEmptyState())
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
            if (i < visiblePosts.length - 1) const SizedBox(height: 16),
          ],
      ],
    );

    if (widget.embedded) {
      // Centre column of the shell: the feed alone, flexing to the column and
      // capped at a readable measure.
      return SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 48),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: feed,
          ),
        ),
      );
    }

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
                SizedBox(width: 600, child: feed),
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
          title: (_userBarangay?.isNotEmpty ?? false)
              ? _userBarangay!
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
        border: Border.all(color: CitizenUi.sharedBorder),
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

  /// [webFilterStyle] renders the mockup's lighter, text-weight filter control.
  /// Defaults to false, so the mobile arm's call is unchanged and mobile keeps
  /// the filled pill exactly as it is. Everything else in this bar is shared.
  Widget _buildTopBar(double width, {bool webFilterStyle = false}) {
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
                // Leaving the feed, not dismissing anything — so it needs the
                // same web/mobile split as the PopScope above. On web the feed
                // is a top-level route with nothing beneath it, and popping
                // throws "popped the last page off the stack".
                if (mounted) leaveGuestFeed(context);
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
                child: webFilterStyle
                    ? _webFilterControl()
                    : Container(
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
                                  color: AppColors.primaryBlue.withValues(
                                    alpha: 0.4,
                                  ),
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

  /// The mockup's filter control: a funnel and a word, no fill and no border.
  /// Same tap target, same [_openFilterSheet], same [PostFilter] values — only
  /// the weight changes. Web arm only; mobile keeps the pill.
  Widget _webFilterControl() {
    final active = _currentFilter != PostFilter.latest;
    final color = active ? CitizenUi.accent : CitizenUi.textMuted;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.filter_list_rounded, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            _currentFilter.label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: active ? FontWeight.w700 : FontWeight.w600,
              color: color,
            ),
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

  /// The WEB feed's empty state.
  ///
  /// Deliberately a SEPARATE method from [_buildEmptyState], which remains the
  /// mobile arm's and is left exactly as it was: the mobile app must not change.
  Widget _buildWebEmptyState() {
    final filterActive = _currentFilter != PostFilter.latest;
    // Read-only probe of the unfiltered cache. Nothing on the shared
    // [_filteredPosts] path is touched, so mobile's behaviour is unchanged. With
    // community_posts empty this is false and every citizen gets the first-run
    // state whether or not a filter happens to be set.
    final anyPosts = CommunityPostsProvider.instance.sortedPosts.isNotEmpty;

    return FeedEmptyState(
      kind: filterActive && anyPosts
          ? FeedEmptyKind.filtered
          : FeedEmptyKind.noPostsYet,
      // Only inside the shell is there a quick-action dispatcher to reach. The
      // guest feed mounts this same body at >=900px and has none, so it gets the
      // headline and copy without a button that could not work.
      onReportIssue: widget.embedded && !widget.isGuest
          ? () => CitizenShell.runQuickAction(context, 'report')
          : null,
      onShowAll: () => setState(() => _currentFilter = PostFilter.latest),
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
  Widget _buildPostCard(double width, Map<String, dynamic> post) {
    final postId = post['id'] as String;
    return NewsfeedPostCard(
      width: width,
      post: post,
      isGuest: widget.isGuest,
      isLiked: _likedPosts.contains(postId),
      isCommented: _commentedPosts.contains(postId),
      isExpanded: _expandedPosts.contains(postId),
      likedComments: _likedComments,
      onToggleExpanded: () => setState(() {
        if (!_expandedPosts.remove(postId)) _expandedPosts.add(postId);
      }),
      onToggleLike: () => _togglePostLike(postId),
      onToggleCommentLike: _toggleLike,
      onOpenComments: ({String? initialReplyTo}) =>
          _openCommentsSheet(post, initialReplyTo: initialReplyTo),
    );
  }
}
