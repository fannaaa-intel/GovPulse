import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import 'home_dots.dart';
import '../../utils/community_posts_provider.dart';

class HomeCommunitySection extends StatefulWidget {
  final double width;
  final VoidCallback onViewAll;

  const HomeCommunitySection({
    super.key,
    required this.width,
    required this.onViewAll,
    // kept for backward compat
    ScrollController? scrollController,
    int currentDot = 0,
  });

  @override
  State<HomeCommunitySection> createState() => _HomeCommunitySectionState();
}

class _HomeCommunitySectionState extends State<HomeCommunitySection> {
  final ScrollController _scrollController = ScrollController();
  int _currentDot = 0;
  static const int _cardsPerPage = 3;

  double get _cardWidth => (widget.width * 0.86 - widget.width * 0.04) / 3;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    CommunityPostsProvider.instance.addListener(_onProviderChanged);

    // Fetch on first load — no-op if already loaded
    WidgetsBinding.instance.addPostFrameCallback((_) {
      CommunityPostsProvider.instance.fetchPosts();
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    CommunityPostsProvider.instance.removeListener(_onProviderChanged);
    super.dispose();
  }

  void _onProviderChanged() {
    if (mounted) setState(() {});
  }

  void _onScroll() {
    final cardWidth = _cardWidth;
    final gap = widget.width * 0.022;
    final pageWidth = (cardWidth + gap) * _cardsPerPage;
    final posts = CommunityPostsProvider.instance.sortedPosts;
    final totalDots = (posts.length / _cardsPerPage).ceil().clamp(1, 99);
    final index = (_scrollController.offset / pageWidth).round().clamp(
      0,
      totalDots - 1,
    );
    if (_currentDot != index) setState(() => _currentDot = index);
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m Ago';
    if (diff.inHours < 24) return '${diff.inHours}h Ago';
    if (diff.inDays < 7) return '${diff.inDays}d Ago';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}w Ago';
    if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}mo Ago';
    return '${(diff.inDays / 365).floor()}y Ago';
  }

  @override
  Widget build(BuildContext context) {
    final width = widget.width;
    final provider = CommunityPostsProvider.instance;
    final posts = provider.sortedPosts;
    final totalDots = posts.isEmpty ? 1 : (posts.length / _cardsPerPage).ceil();

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: width * 0.04),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(
          width * 0.03,
          width * 0.03,
          width * 0.03,
          width * 0.025,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(width * 0.04),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Community Updates',
                  style: TextStyle(
                    fontSize: width * 0.048,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryBlue,
                  ),
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onViewAll,
                  child: Row(
                    children: [
                      Text(
                        'View All',
                        style: TextStyle(
                          fontSize: width * 0.034,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF6B7280),
                        ),
                      ),
                      SizedBox(width: width * 0.008),
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: width * 0.030,
                        color: const Color(0xFF9CA3AF),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: width * 0.03),

            // ── Content ──
            if (provider.isLoading)
              _buildSkeleton(width)
            else if (provider.error != null)
              _buildError(width, provider)
            else if (posts.isEmpty)
              _buildEmpty(width)
            else
              SizedBox(
                height: _cardWidth * 1.95,
                child: ListView.separated(
                  controller: _scrollController,
                  scrollDirection: Axis.horizontal,
                  physics: const PageScrollPhysics(),
                  itemCount: posts.length,
                  separatorBuilder: (_, _) => SizedBox(width: width * 0.022),
                  itemBuilder: (_, i) =>
                      _buildCard(width, _cardWidth, posts[i]),
                ),
              ),

            SizedBox(height: width * 0.025),

            // ── Dots ──
            if (!provider.isLoading && provider.error == null)
              HomeDots(
                width: width,
                count: totalDots,
                activeIndex: _currentDot.clamp(0, totalDots - 1),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkeleton(double width) {
    final cardWidth = _cardWidth;
    return SizedBox(
      height: cardWidth * 1.95,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 3,
        separatorBuilder: (_, _) => SizedBox(width: width * 0.022),
        itemBuilder: (_, _) => Container(
          width: cardWidth,
          decoration: BoxDecoration(
            color: const Color(0xFFE5E7EB),
            borderRadius: BorderRadius.circular(width * 0.03),
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty(double width) {
    return SizedBox(
      height: width * 0.35,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: width * 0.12,
              color: const Color(0xFFD1D5DB),
            ),
            SizedBox(height: width * 0.02),
            Text(
              'No community updates yet',
              style: TextStyle(
                fontSize: width * 0.034,
                color: const Color(0xFF9CA3AF),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError(double width, CommunityPostsProvider provider) {
    return SizedBox(
      height: width * 0.35,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.wifi_off_rounded,
              size: width * 0.12,
              color: const Color(0xFFD1D5DB),
            ),
            SizedBox(height: width * 0.02),
            Text(
              'Could not load posts',
              style: TextStyle(
                fontSize: width * 0.034,
                color: const Color(0xFF9CA3AF),
              ),
            ),
            SizedBox(height: width * 0.02),
            GestureDetector(
              onTap: provider.refresh,
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: width * 0.04,
                  vertical: width * 0.02,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(width * 0.03),
                ),
                child: Text(
                  'Retry',
                  style: TextStyle(
                    fontSize: width * 0.032,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryBlue,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(double width, double cardWidth, Map<String, dynamic> post) {
    final ts = post['timestamp'] as DateTime?;
    final timeAgo = ts != null ? _timeAgo(ts) : '';
    final comments = post['comments'] as List<dynamic>? ?? [];

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onViewAll,
      child: Container(
        width: cardWidth,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(width * 0.03),
          border: Border.all(color: const Color(0xFFE5E7EB)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(width * 0.03),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Image area ──
              SizedBox(
                height: cardWidth * 1.03,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _buildImage(post, width),
                    Container(color: Colors.black.withValues(alpha: 0.05)),
                    Positioned(
                      top: width * 0.015,
                      left: width * 0.015,
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: width * 0.014,
                          vertical: width * 0.006,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(width * 0.02),
                        ),
                        child: Text(
                          timeAgo,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: width * 0.020,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: width * 0.015,
                      left: width * 0.015,
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: width * 0.014,
                          vertical: width * 0.007,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF22C55E),
                          borderRadius: BorderRadius.circular(width * 0.03),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.location_on,
                              size: width * 0.020,
                              color: Colors.white,
                            ),
                            SizedBox(width: width * 0.004),
                            Text(
                              post['barangay'] as String? ?? '',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: width * 0.018,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // ── Text + stats ──
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    width * 0.02,
                    width * 0.018,
                    width * 0.02,
                    width * 0.015,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          post['title'] as String? ?? '',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: width * 0.031,
                            height: 1.22,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF1F2937),
                          ),
                        ),
                      ),
                      SizedBox(height: width * 0.012),
                      Row(
                        children: [
                          Image.asset(
                            'assets/images/heart.png',
                            width: width * 0.036,
                            height: width * 0.036,
                            fit: BoxFit.contain,
                            color: AppColors.primaryBlue,
                            errorBuilder: (_, _, _) => Icon(
                              Icons.favorite_rounded,
                              size: width * 0.036,
                              color: AppColors.primaryBlue,
                            ),
                          ),
                          SizedBox(width: width * 0.007),
                          Text(
                            post['likes'] as String? ?? '0',
                            style: TextStyle(
                              fontSize: width * 0.028,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primaryBlue,
                              height: 1,
                            ),
                          ),
                          SizedBox(width: width * 0.028),
                          Image.asset(
                            'assets/images/comment.png',
                            width: width * 0.040,
                            height: width * 0.040,
                            fit: BoxFit.contain,
                            color: AppColors.primaryBlue,
                            errorBuilder: (_, _, _) => Icon(
                              Icons.chat_bubble_rounded,
                              size: width * 0.040,
                              color: AppColors.primaryBlue,
                            ),
                          ),
                          SizedBox(width: width * 0.007),
                          Text(
                            '${post['commentCount'] ?? comments.length}',
                            style: TextStyle(
                              fontSize: width * 0.028,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primaryBlue,
                              height: 1,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImage(Map<String, dynamic> post, double width) {
    final urls = post['imageUrls'] as List<String>? ?? [];
    if (urls.isNotEmpty) {
      return Image.network(
        urls.first,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _placeholder(width),
      );
    }
    return _placeholder(width);
  }

  Widget _placeholder(double width) {
    return Container(
      color: const Color(0xFFE5E7EB),
      child: Center(
        child: Icon(
          Icons.image_outlined,
          size: width * 0.10,
          color: const Color(0xFF9CA3AF),
        ),
      ),
    );
  }
}
