import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../screen/home_screen.dart';

// ── Post filter options ────────────────────────────────────────────────
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
  const NewsFeedScreen({super.key, this.username = ''});

  @override
  State<NewsFeedScreen> createState() => _NewsFeedScreenState();
}

// ── Changed to TickerProviderStateMixin to support _entryCtrl ────────────────
class _NewsFeedScreenState extends State<NewsFeedScreen>
    with TickerProviderStateMixin {
  static const int _navIndex = 2;

  // ── Entry animation controller ────────────────────────────────────────────
  late final AnimationController _entryCtrl;

  PostFilter _currentFilter = PostFilter.latest;
  final Set<String> _likedComments = {};
  final Set<String> _likedPosts = {};
  late final List<Map<String, dynamic>> _posts;

  @override
  void initState() {
    super.initState();

    // ── Init entry animation — slides UP like Emergency screen ────────────
    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 80), () {
        if (mounted) _entryCtrl.forward();
      });
    });

    final now = DateTime.now();
    _posts = [
      {
        'id': 'p0',
        'author': 'LGU Aparri',
        'barangay': 'Brgy.Maura',
        'timestamp': now.subtract(const Duration(hours: 13)),
        'tag': 'DPWH Region 2',
        'tagColor': const Color(0xFF22C55E),
        'title': 'New Brgy. Health Center Inauguration',
        'body':
            'The newly inaugurated Maura Health Center will provide better and more accessible medical services',
        'imageCount': 7,
        'likes': '55',
        'comments': [
          {
            'id': 'p0_c0',
            'author': 'Maria Santos',
            'text':
                'Finally! Thank you LGU for this great development. Maraming salamat sa lahat!',
            'timestamp': now.subtract(const Duration(hours: 2)),
            'likes': 12,
            'replies': [
              {
                'id': 'p0_c0_r0',
                'author': 'Juan Dela Cruz',
                'mentionedUser': null,
                'text': "I agree! Tagal na natin hinihintay 'to.",
                'timestamp': now.subtract(
                  const Duration(hours: 1, minutes: 30),
                ),
                'likes': 4,
              },
              {
                'id': 'p0_c0_r1',
                'author': 'Maria Santos',
                'mentionedUser': 'Juan Dela Cruz',
                'text': 'Tama ka diyan! Worth the wait.',
                'timestamp': now.subtract(const Duration(hours: 1)),
                'likes': 2,
              },
              {
                'id': 'p0_c0_r2',
                'author': 'Ana Lopez',
                'mentionedUser': null,
                'text': 'Sana magkaroon ng dental services din.',
                'timestamp': now.subtract(const Duration(minutes: 50)),
                'likes': 3,
              },
              {
                'id': 'p0_c0_r3',
                'author': 'Pedro Reyes',
                'mentionedUser': 'Ana Lopez',
                'text': 'Sang-ayon ako, importante yan!',
                'timestamp': now.subtract(const Duration(minutes: 35)),
                'likes': 1,
              },
              {
                'id': 'p0_c0_r4',
                'author': 'Carlos Mendoza',
                'mentionedUser': null,
                'text': 'Magandang balita talaga ito.',
                'timestamp': now.subtract(const Duration(minutes: 20)),
                'likes': 2,
              },
            ],
          },
          {
            'id': 'p0_c1',
            'author': 'Juan Dela Cruz',
            'text': 'When will this be officially open for the public?',
            'timestamp': now.subtract(const Duration(hours: 5)),
            'likes': 8,
            'replies': [
              {
                'id': 'p0_c1_r0',
                'author': 'LGU Aparri',
                'mentionedUser': null,
                'text': 'Officially opening next Monday at 8AM!',
                'timestamp': now.subtract(const Duration(hours: 4)),
                'likes': 15,
              },
              {
                'id': 'p0_c1_r1',
                'author': 'Juan Dela Cruz',
                'mentionedUser': 'LGU Aparri',
                'text': 'Salamat sa quick response!',
                'timestamp': now.subtract(const Duration(hours: 3)),
                'likes': 3,
              },
            ],
          },
          {
            'id': 'p0_c2',
            'author': 'Pedro Reyes',
            'text': 'Sana may complete medical equipment na agad. 🙏',
            'timestamp': now.subtract(const Duration(hours: 8)),
            'likes': 5,
            'replies': [],
          },
          {
            'id': 'p0_c3',
            'author': 'Ana Lopez',
            'text': 'Magandang balita ito para sa Brgy. Maura!',
            'timestamp': now.subtract(const Duration(hours: 10)),
            'likes': 3,
            'replies': [],
          },
          {
            'id': 'p0_c4',
            'author': 'Carlos Mendoza',
            'text': 'Will this offer free check-ups for senior citizens?',
            'timestamp': now.subtract(const Duration(hours: 11)),
            'likes': 7,
            'replies': [
              {
                'id': 'p0_c4_r0',
                'author': 'LGU Aparri',
                'mentionedUser': null,
                'text': 'Yes po, free check-ups for seniors every Wednesday.',
                'timestamp': now.subtract(const Duration(hours: 10)),
                'likes': 8,
              },
            ],
          },
        ],
      },
      {
        'id': 'p1',
        'author': 'LGU Aparri',
        'barangay': 'Brgy.Macanaya',
        'timestamp': now.subtract(const Duration(hours: 20)),
        'tag': 'BFP Aparri',
        'tagColor': const Color(0xFFEF4444),
        'title': 'Fire Out beside Florida Terminal',
        'body':
            'A fire occured beside Florida Terminal last night, but it was quickly extinguished by BFP Aparri.',
        'imageCount': 4,
        'likes': '42',
        'comments': [
          {
            'id': 'p1_c0',
            'author': 'Roberto Cruz',
            'text': 'Salamat BFP Aparri sa mabilis na response!',
            'timestamp': now.subtract(const Duration(hours: 20)),
            'likes': 15,
            'replies': [
              {
                'id': 'p1_c0_r0',
                'author': 'BFP Aparri',
                'mentionedUser': null,
                'text': 'Salamat din po sa community na tumulong!',
                'timestamp': now.subtract(const Duration(hours: 19)),
                'likes': 9,
              },
            ],
          },
          {
            'id': 'p1_c1',
            'author': 'Liza Garcia',
            'text': 'Anong sanhi ng sunog?',
            'timestamp': now.subtract(const Duration(hours: 22)),
            'likes': 4,
            'replies': [],
          },
          {
            'id': 'p1_c2',
            'author': 'Mark Tan',
            'text': 'Buti walang tao na nasaktan.',
            'timestamp': now.subtract(const Duration(hours: 23)),
            'likes': 9,
            'replies': [],
          },
        ],
      },
      {
        'id': 'p2',
        'author': 'LGU Aparri',
        'barangay': 'Brgy.Centro',
        'timestamp': now.subtract(const Duration(days: 2)),
        'tag': 'LGU Aparri',
        'tagColor': const Color(0xFF3B82F6),
        'title': 'Assembly Meeting for Public Market',
        'body':
            'A general assembly meeting will be conducted on Saturday at the public market plaza for all stallholders and vendors.',
        'imageCount': 2,
        'likes': '64',
        'comments': [
          {
            'id': 'p2_c0',
            'author': 'Vendor Association',
            'text': 'Anong oras po sisimulan ang meeting?',
            'timestamp': now.subtract(const Duration(days: 1, hours: 12)),
            'likes': 6,
            'replies': [
              {
                'id': 'p2_c0_r0',
                'author': 'LGU Aparri',
                'mentionedUser': null,
                'text': 'Saturday 9AM po, please be on time.',
                'timestamp': now.subtract(const Duration(days: 1)),
                'likes': 4,
              },
            ],
          },
          {
            'id': 'p2_c1',
            'author': 'Linda Ramos',
            'text': 'Importante itong pulong, sana lahat dumalo.',
            'timestamp': now.subtract(const Duration(days: 1)),
            'likes': 11,
            'replies': [],
          },
        ],
      },
      {
        'id': 'p3',
        'author': 'LGU Aparri',
        'barangay': 'Brgy.Punta',
        'timestamp': now.subtract(const Duration(days: 15)),
        'tag': 'LGU Aparri',
        'tagColor': const Color(0xFF3B82F6),
        'title': 'Road Repair Completed',
        'body':
            'The major road repair on Brgy. Punta has been completed ahead of schedule. Thank you for your patience!',
        'imageCount': 3,
        'likes': '128',
        'comments': [],
      },
      {
        'id': 'p4',
        'author': 'LGU Aparri',
        'barangay': 'Brgy.Centro',
        'timestamp': now.subtract(const Duration(days: 200)),
        'tag': 'LGU Aparri',
        'tagColor': const Color(0xFF3B82F6),
        'title': 'Town Fiesta 2024 Highlights',
        'body':
            'A look back at the wonderful celebrations during our 2024 town fiesta!',
        'imageCount': 6,
        'likes': '342',
        'comments': [],
      },
    ];
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    super.dispose();
  }

  // ── Staggered upward entry animation helper (same as Emergency) ───────────
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
        Tween<Offset>(
          begin: const Offset(0.0, 0.30), // ← slides UP like Emergency cards
          end: Offset.zero,
        ).animate(
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

  // ── Filter logic ──────────────────────────────────────────────────────
  List<Map<String, dynamic>> get _filteredPosts {
    final sorted = List.of(_posts)
      ..sort((a, b) {
        final tsA = a['timestamp'] as DateTime?;
        final tsB = b['timestamp'] as DateTime?;
        if (tsA == null && tsB == null) return 0;
        if (tsA == null) return 1;
        if (tsB == null) return -1;
        return tsB.compareTo(tsA);
      });

    if (_currentFilter == PostFilter.latest) return sorted;

    final cutoff = DateTime.now().subtract(_currentFilter.duration!);
    return sorted.where((p) {
      final ts = p['timestamp'] as DateTime?;
      if (ts == null) return false;
      return ts.isAfter(cutoff);
    }).toList();
  }

  void _goToHome() {
    Navigator.pushAndRemoveUntil(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (context, animation, secondaryAnimation) =>
            HomePage(username: widget.username),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final slide = Tween(begin: const Offset(-1, 0), end: Offset.zero)
              .animate(
                CurvedAnimation(parent: animation, curve: Curves.easeInOut),
              );
          return SlideTransition(position: slide, child: child);
        },
      ),
      (route) => false,
    );
  }

  void _toggleLike(String id) {
    setState(() {
      if (_likedComments.contains(id)) {
        _likedComments.remove(id);
      } else {
        _likedComments.add(id);
      }
    });
  }

  void _togglePostLike(String postId) {
    setState(() {
      if (_likedPosts.contains(postId)) {
        _likedPosts.remove(postId);
      } else {
        _likedPosts.add(postId);
      }
    });
  }

  void _openFilterSheet() {
    final width = MediaQuery.of(context).size.width;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(width * 0.06)),
      ),
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(0, width * 0.025, 0, width * 0.03),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  margin: EdgeInsets.only(bottom: width * 0.025),
                  width: width * 0.12,
                  height: width * 0.012,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD1D5DB),
                    borderRadius: BorderRadius.circular(width * 0.006),
                  ),
                ),
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
                  String subtitle = '';
                  switch (filter) {
                    case PostFilter.latest:
                      subtitle = 'Show all posts';
                      break;
                    case PostFilter.day:
                      subtitle = 'Posts from the last 24 hours';
                      break;
                    case PostFilter.week:
                      subtitle = 'Posts from the last 7 days';
                      break;
                    case PostFilter.month:
                      subtitle = 'Posts from the last 30 days';
                      break;
                    case PostFilter.year:
                      subtitle = 'Posts from the last 365 days';
                      break;
                  }
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
                                  subtitle,
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
        );
      },
    );
  }

  void _openCommentsSheet(Map<String, dynamic> post, {String? initialReplyTo}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (sheetCtx) => _CommentsSheet(
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
    final visiblePosts = _filteredPosts;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _goToHome();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF3F4F6),
        body: SafeArea(
          child: Column(
            children: [
              // Top bar slides up first (index 0)
              _animated(0, _buildTopBar(width)),
              Expanded(
                child: visiblePosts.isEmpty
                    ? _animated(1, _buildEmptyState(width))
                    : ListView.separated(
                        physics: const BouncingScrollPhysics(),
                        padding: EdgeInsets.fromLTRB(
                          width * 0.04,
                          width * 0.035,
                          width * 0.04,
                          width * 0.04,
                        ),
                        itemCount: visiblePosts.length,
                        separatorBuilder: (context, index) =>
                            SizedBox(height: width * 0.035),
                        // Each post card gets its own staggered index (1, 2, 3…)
                        itemBuilder: (context, index) => _animated(
                          index + 1,
                          _buildPostCard(width, visiblePosts[index]),
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

  Widget _buildEmptyState(double width) {
    String filterDesc = '';
    switch (_currentFilter) {
      case PostFilter.latest:
        filterDesc = 'any time';
        break;
      case PostFilter.day:
        filterDesc = 'the last 24 hours';
        break;
      case PostFilter.week:
        filterDesc = 'the last 7 days';
        break;
      case PostFilter.month:
        filterDesc = 'the last 30 days';
        break;
      case PostFilter.year:
        filterDesc = 'the last 365 days';
        break;
    }
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
              'There are no posts from $filterDesc.\nTry a wider time range.',
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
            height: width * 0.10,
            fit: BoxFit.contain,
            alignment: Alignment.centerLeft,
            errorBuilder: (context, error, stackTrace) => Icon(
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

  Widget _buildPostCard(double width, Map<String, dynamic> post) {
    final comments = post['comments'] as List<dynamic>;
    final commentCount = comments.length;
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
              onImageTap: (index) =>
                  openImageViewer(context, post['imageCount'] as int, index),
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
        Container(
          width: width * 0.105,
          height: width * 0.105,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.green.withValues(alpha: 0.12),
            border: Border.all(color: AppColors.green, width: 1.5),
          ),
          child: Icon(
            Icons.account_balance_rounded,
            size: width * 0.055,
            color: AppColors.green,
          ),
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

    Widget buildIcon(String path, bool isActive) {
      return SizedBox(
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
    }

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
          } else if (index == 3) {
            Navigator.pushNamed(
              context,
              '/emergency',
              arguments: widget.username,
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

// ════════════════════════════════════════════════════════════════════════
// ══ TOP-LEVEL HELPERS ═══════════════════════════════════════════════════
// ════════════════════════════════════════════════════════════════════════

String formatTimeAgo(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inSeconds < 60) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m Ago';
  if (diff.inHours < 24) return '${diff.inHours}h Ago';
  if (diff.inDays < 7) return '${diff.inDays}d Ago';
  if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}w Ago';
  if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}mo Ago';
  return '${(diff.inDays / 365).floor()}y Ago';
}

Widget buildImagePlaceholder(double width) {
  return Container(
    color: const Color(0xFFE5E7EB),
    alignment: Alignment.center,
    child: Icon(
      Icons.image_outlined,
      size: width * 0.08,
      color: const Color(0xFF9CA3AF),
    ),
  );
}

Widget buildImageGrid(
  double width,
  int imageCount, {
  ValueChanged<int>? onImageTap,
}) {
  if (imageCount <= 0) return const SizedBox.shrink();

  final extraCount = imageCount - 4;
  final gap = width * 0.015;
  final radius = width * 0.025;

  Widget tappable(Widget child, int index) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onImageTap == null ? null : () => onImageTap(index),
      child: child,
    );
  }

  Widget cell(int index, {bool overlay = false}) {
    return Expanded(
      child: AspectRatio(
        aspectRatio: 1,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: tappable(
            Stack(
              fit: StackFit.expand,
              children: [
                buildImagePlaceholder(width),
                if (overlay)
                  Container(
                    color: Colors.black.withValues(alpha: 0.55),
                    alignment: Alignment.center,
                    child: Text(
                      '+$extraCount',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: width * 0.075,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
              ],
            ),
            index,
          ),
        ),
      ),
    );
  }

  if (imageCount == 1) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: tappable(
        AspectRatio(aspectRatio: 16 / 9, child: buildImagePlaceholder(width)),
        0,
      ),
    );
  }
  if (imageCount == 2) {
    return Row(
      children: [
        cell(0),
        SizedBox(width: gap),
        cell(1),
      ],
    );
  }
  if (imageCount == 3) {
    return Row(
      children: [
        cell(0),
        SizedBox(width: gap),
        cell(1),
        SizedBox(width: gap),
        cell(2),
      ],
    );
  }
  return Column(
    children: [
      Row(
        children: [
          cell(0),
          SizedBox(width: gap),
          cell(1),
        ],
      ),
      SizedBox(height: gap),
      Row(
        children: [
          cell(2),
          SizedBox(width: gap),
          cell(3, overlay: extraCount > 0),
        ],
      ),
    ],
  );
}

void openImageViewer(BuildContext context, int imageCount, int initialIndex) {
  Navigator.of(context).push(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black.withValues(alpha: 0.92),
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (_, _, _) =>
          _ImageViewer(imageCount: imageCount, initialIndex: initialIndex),
      transitionsBuilder: (_, anim, _, child) =>
          FadeTransition(opacity: anim, child: child),
    ),
  );
}

class _ImageViewer extends StatefulWidget {
  final int imageCount;
  final int initialIndex;
  const _ImageViewer({required this.imageCount, required this.initialIndex});

  @override
  State<_ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<_ImageViewer> {
  late final PageController _pageController;
  late int _current;

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(),
            ),
          ),
          PageView.builder(
            controller: _pageController,
            itemCount: widget.imageCount,
            onPageChanged: (i) => setState(() => _current = i),
            itemBuilder: (_, index) {
              return InteractiveViewer(
                minScale: 1.0,
                maxScale: 4.0,
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: Container(
                      margin: EdgeInsets.all(width * 0.04),
                      decoration: BoxDecoration(
                        color: const Color(0xFF374151),
                        borderRadius: BorderRadius.circular(width * 0.02),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.image_outlined,
                        size: width * 0.25,
                        color: const Color(0xFF9CA3AF),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  width * 0.04,
                  width * 0.025,
                  width * 0.025,
                  0,
                ),
                child: Row(
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: width * 0.035,
                        vertical: width * 0.015,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(width * 0.04),
                      ),
                      child: Text(
                        '${_current + 1} / ${widget.imageCount}',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: width * 0.034,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        padding: EdgeInsets.all(width * 0.022),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                          size: width * 0.06,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Widget _commentAction(
  double width, {
  required String label,
  required int count,
  required bool active,
  required Color activeColor,
  required String pngAsset,
  required IconData fallbackIcon,
  required VoidCallback onTap,
}) {
  final iconColor = active ? activeColor : const Color(0xFF6B7280);
  final textColor = active ? activeColor : const Color(0xFF6B7280);

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
          color: iconColor,
          colorBlendMode: BlendMode.srcIn,
          errorBuilder: (_, _, _) =>
              Icon(fallbackIcon, size: width * 0.036, color: iconColor),
        ),
        SizedBox(width: width * 0.008),
        Text(
          label,
          style: TextStyle(
            fontSize: width * 0.028,
            fontWeight: FontWeight.w700,
            color: textColor,
          ),
        ),
        if (count > 0) ...[
          SizedBox(width: width * 0.008),
          Text(
            '$count',
            style: TextStyle(
              fontSize: width * 0.028,
              fontWeight: FontWeight.w700,
              color: textColor,
            ),
          ),
        ],
      ],
    ),
  );
}

Widget buildCommentItem(
  double width,
  Map<String, dynamic> comment, {
  required Set<String> likedComments,
  required ValueChanged<String> onToggleLike,
  required VoidCallback onReply,
  required bool showReplies,
  required Set<String> expandedReplies,
  required ValueChanged<String> onToggleExpandReplies,
  required ValueChanged<String> onReplyToReply,
}) {
  final id = comment['id'] as String;
  final isLiked = likedComments.contains(id);
  final baseLikes = comment['likes'] as int;
  final displayLikes = baseLikes + (isLiked ? 1 : 0);
  final replies = (comment['replies'] as List<dynamic>?) ?? const [];
  final isExpanded = expandedReplies.contains(id);
  final visibleReplies = isExpanded ? replies : replies.take(3).toList();
  final hiddenCount = replies.length - 3;
  final ts = comment['timestamp'] as DateTime?;
  final timeAgo = ts != null ? formatTimeAgo(ts) : '';

  return Padding(
    padding: EdgeInsets.symmetric(vertical: width * 0.012),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: width * 0.085,
              height: width * 0.085,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFE5E7EB),
              ),
              child: Icon(
                Icons.person_rounded,
                size: width * 0.05,
                color: const Color(0xFF9CA3AF),
              ),
            ),
            SizedBox(width: width * 0.025),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
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
                          comment['author'] as String,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: width * 0.032,
                            color: const Color(0xFF1F2937),
                          ),
                        ),
                        SizedBox(height: width * 0.006),
                        Text(
                          comment['text'] as String,
                          style: TextStyle(
                            fontSize: width * 0.033,
                            color: const Color(0xFF374151),
                            height: 1.35,
                          ),
                        ),
                      ],
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
                        _commentAction(
                          width,
                          label: 'Like',
                          count: displayLikes,
                          active: isLiked,
                          activeColor: const Color(0xFFEF4444),
                          pngAsset: 'assets/images/heart.png',
                          fallbackIcon: Icons.favorite_border_rounded,
                          onTap: () => onToggleLike(id),
                        ),
                        _commentAction(
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
              width,
              r as Map<String, dynamic>,
              likedComments: likedComments,
              onToggleLike: onToggleLike,
              onReply: () => onReplyToReply(r['author'] as String),
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
  double width,
  Map<String, dynamic> reply, {
  required Set<String> likedComments,
  required ValueChanged<String> onToggleLike,
  required VoidCallback onReply,
}) {
  final id = reply['id'] as String;
  final isLiked = likedComments.contains(id);
  final baseLikes = reply['likes'] as int;
  final displayLikes = baseLikes + (isLiked ? 1 : 0);
  final mentioned = reply['mentionedUser'] as String?;
  final ts = reply['timestamp'] as DateTime?;
  final timeAgo = ts != null ? formatTimeAgo(ts) : '';

  return Padding(
    padding: EdgeInsets.only(left: width * 0.11, top: width * 0.012),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: width * 0.07,
          height: width * 0.07,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFFE5E7EB),
          ),
          child: Icon(
            Icons.person_rounded,
            size: width * 0.042,
            color: const Color(0xFF9CA3AF),
          ),
        ),
        SizedBox(width: width * 0.022),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
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
                      reply['author'] as String,
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
                            text: reply['text'] as String,
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
                    _commentAction(
                      width,
                      label: 'Like',
                      count: displayLikes,
                      active: isLiked,
                      activeColor: const Color(0xFFEF4444),
                      pngAsset: 'assets/images/heart.png',
                      fallbackIcon: Icons.favorite_border_rounded,
                      onTap: () => onToggleLike(id),
                    ),
                    _commentAction(
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

// ════════════════════════════════════════════════════════════════════════
// ══ COMMENTS BOTTOM SHEET ═══════════════════════════════════════════════
// ════════════════════════════════════════════════════════════════════════

class _CommentsSheet extends StatefulWidget {
  final Map<String, dynamic> post;
  final String? initialReplyTo;
  final Set<String> likedComments;
  final ValueChanged<String> onToggleLike;
  final Set<String> likedPosts;
  final ValueChanged<String> onTogglePostLike;

  const _CommentsSheet({
    required this.post,
    this.initialReplyTo,
    required this.likedComments,
    required this.onToggleLike,
    required this.likedPosts,
    required this.onTogglePostLike,
  });

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  late final TextEditingController _inputController;
  late final FocusNode _inputFocus;
  String? _replyingTo;
  final Set<String> _expandedReplies = {};

  @override
  void initState() {
    super.initState();
    _inputController = TextEditingController();
    _inputFocus = FocusNode();
    _inputFocus.addListener(_onFocusChange);
    _replyingTo = widget.initialReplyTo;
    if (_replyingTo != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _inputFocus.requestFocus();
      });
    }
  }

  void _onFocusChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _inputFocus.removeListener(_onFocusChange);
    _inputController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _localToggleLike(String id) {
    widget.onToggleLike(id);
    setState(() {});
  }

  void _setReply(String author) {
    setState(() => _replyingTo = author);
    _inputFocus.requestFocus();
  }

  void _cancelReply() => setState(() => _replyingTo = null);

  void _toggleExpandReplies(String commentId) {
    setState(() {
      if (_expandedReplies.contains(commentId)) {
        _expandedReplies.remove(commentId);
      } else {
        _expandedReplies.add(commentId);
      }
    });
  }

  void _send() {
    _inputController.clear();
    setState(() => _replyingTo = null);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final comments = widget.post['comments'] as List<dynamic>;

    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollController) {
        return Container(
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
              Container(
                margin: EdgeInsets.symmetric(vertical: width * 0.025),
                width: width * 0.12,
                height: width * 0.012,
                decoration: BoxDecoration(
                  color: const Color(0xFFD1D5DB),
                  borderRadius: BorderRadius.circular(width * 0.006),
                ),
              ),
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
                      '${comments.length} ${comments.length == 1 ? "Comment" : "Comments"}',
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
                    _buildSheetPostSummary(width),
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
                        width,
                        c as Map<String, dynamic>,
                        likedComments: widget.likedComments,
                        onToggleLike: _localToggleLike,
                        onReply: () => _setReply(c['author'] as String),
                        showReplies: true,
                        expandedReplies: _expandedReplies,
                        onToggleExpandReplies: _toggleExpandReplies,
                        onReplyToReply: _setReply,
                      ),
                    ),
                    SizedBox(height: width * 0.04),
                  ],
                ),
              ),
              _buildCommentInput(width),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSheetPostSummary(double width) {
    final post = widget.post;
    final postId = post['id'] as String;
    final isPostLiked = widget.likedPosts.contains(postId);
    final ts = post['timestamp'] as DateTime?;
    final timeAgo = ts != null ? formatTimeAgo(ts) : '';
    final commentCount = (post['comments'] as List).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: width * 0.105,
              height: width * 0.105,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.green.withValues(alpha: 0.12),
                border: Border.all(color: AppColors.green, width: 1.5),
              ),
              child: Icon(
                Icons.account_balance_rounded,
                size: width * 0.055,
                color: AppColors.green,
              ),
            ),
            SizedBox(width: width * 0.025),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    post['author'] as String,
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
        ),
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
        Text(
          post['body'] as String,
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
          onImageTap: (index) =>
              openImageViewer(context, post['imageCount'] as int, index),
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
                                color: AppColors.primaryBlue,
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
                    child: Icon(
                      Icons.person_rounded,
                      size: width * 0.06,
                      color: const Color(0xFF9CA3AF),
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
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: width * 0.025),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _send,
                    child: Image.asset(
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
