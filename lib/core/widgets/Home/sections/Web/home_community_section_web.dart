// lib/core/widgets/Home/sections/Web/home_community_section_web.dart

import 'package:flutter/material.dart';
import '../../../../theme/app_colors.dart';
import '../../../../providers/community_posts_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

class HomeCommunitySectionWeb extends StatefulWidget {
  final VoidCallback onViewAll;
  final double? height;
  final String? barangay;

  const HomeCommunitySectionWeb({
    super.key,
    required this.onViewAll,
    this.height,
    this.barangay,
  });

  @override
  State<HomeCommunitySectionWeb> createState() =>
      _HomeCommunitySectionWebState();
}

class _HomeCommunitySectionWebState extends State<HomeCommunitySectionWeb> {
  @override
  void initState() {
    super.initState();
    CommunityPostsProvider.instance.addListener(_onChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      CommunityPostsProvider.instance.setBarangay(widget.barangay);
      CommunityPostsProvider.instance.fetchPosts();
    });
  }

  final ScrollController _scrollController = ScrollController();

  @override
  void didUpdateWidget(covariant HomeCommunitySectionWeb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.barangay != widget.barangay) {
      CommunityPostsProvider.instance.setBarangay(widget.barangay);
      CommunityPostsProvider.instance.fetchPosts(force: true);
    }
  }

  @override
  void dispose() {
    CommunityPostsProvider.instance.removeListener(_onChange);
    _scrollController.dispose();
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}w ago';
    if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}mo ago';
    return '${(diff.inDays / 365).floor()}y ago';
  }

  @override
  Widget build(BuildContext context) {
    final provider = CommunityPostsProvider.instance;
    final posts = provider.sortedPosts;

    final panel = WebGlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _SectionHeader(
            title: 'Latest Updates',
            subtitle: 'News and updates from Aparri',
            icon: Icons.campaign_rounded,
            iconGradient: const [Color(0xFF1A4DB8), Color(0xFF2D9CDB)],
            count: posts.length,
            onViewAll: widget.onViewAll,
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            height: 1.5,
            color: const Color(0xFFC9D2E0),
          ),
          const SizedBox(height: 18),

          // Flexible lets the list fill whatever height the panel is given and
          // scroll past it — no extra height added when there are many posts.
          Flexible(
            child: provider.isLoading
                ? _buildSkeleton()
                : provider.error != null
                ? _buildError(provider)
                : posts.isEmpty
                ? _buildEmpty()
                : Scrollbar(
                    controller: _scrollController,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      physics: const BouncingScrollPhysics(),
                      child: _buildPostList(posts),
                    ),
                  ),
          ),
        ],
      ),
    );

    // Two-column mode hands us an exact height to match Quick Actions.
    // Single-column mode falls back to a sensible bounded, scrollable range.
    if (widget.height != null) {
      return SizedBox(height: widget.height, child: panel);
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 320, maxHeight: 520),
      child: panel,
    );
  }

  Widget _buildPostList(List<Map<String, dynamic>> posts) {
    return Column(
      children: [
        for (int i = 0; i < posts.length; i++) ...[
          _PostRow(
            post: posts[i],
            timeAgo: posts[i]['timestamp'] is DateTime
                ? _timeAgo(posts[i]['timestamp'] as DateTime)
                : '',
            onTap: widget.onViewAll,
          ),
          if (i < posts.length - 1)
            const Divider(height: 1, thickness: 1, color: Color(0xFFF3F4F6)),
        ],
      ],
    );
  }

  // Skeleton is wrapped in a scroll view so it can never overflow the
  // matched (Quick-Actions-driven) height — it just clips gracefully while
  // loading instead of throwing a RenderFlex overflow.
  Widget _buildSkeleton() {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(
          3,
          (i) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            height: 13,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF3F4F6),
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            height: 11,
                            width: 180,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF3F4F6),
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (i < 2)
                const Divider(
                  height: 1,
                  thickness: 1,
                  color: Color(0xFFF3F4F6),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return SizedBox(
      height: 160,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.primaryBlue.withOpacity(0.06),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.inbox_outlined,
                size: 24,
                color: AppColors.primaryBlue,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'No updates yet',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF374151),
              ),
            ),
            const SizedBox(height: 3),
            const Text(
              'Check back later for posts from your area',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError(CommunityPostsProvider provider) {
    return SizedBox(
      height: 160,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                color: Color(0xFFFEF2F2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.wifi_off_rounded,
                size: 22,
                color: Color(0xFFEF4444),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Could not load posts',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF374151),
              ),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: provider.refresh,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Retry',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
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
}

// ── Shared glass panel ────────────────────────────────────────────────────────
class WebGlassPanel extends StatelessWidget {
  final Widget child;
  const WebGlassPanel({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final pad = c.maxWidth < 380 ? 16.0 : 24.0;
        return Container(
          width: double.infinity,
          padding: EdgeInsets.all(pad),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE8EEF8), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF1A4DB8).withOpacity(0.10),
                blurRadius: 24,
                spreadRadius: 0,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: const Color(0xFF1A4DB8).withOpacity(0.06),
                blurRadius: 48,
                spreadRadius: -4,
                offset: const Offset(0, 20),
              ),
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 6,
                spreadRadius: 0,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: child,
        );
      },
    );
  }
}

// ── Section header ────────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> iconGradient;
  final int count;
  final VoidCallback onViewAll;

  const _SectionHeader({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconGradient,
    required this.count,
    required this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 3,
          height: 36,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: iconGradient,
            ),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                  letterSpacing: -0.4,
                ),
              ),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF9CA3AF),
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _ViewAllButton(onTap: onViewAll),
      ],
    );
  }
}

// ── View all button ───────────────────────────────────────────────────────────
class _ViewAllButton extends StatefulWidget {
  final VoidCallback onTap;
  const _ViewAllButton({required this.onTap});

  @override
  State<_ViewAllButton> createState() => _ViewAllButtonState();
}

class _ViewAllButtonState extends State<_ViewAllButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: AppColors.primaryBlue.withOpacity(_hover ? 0.25 : 0.0),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: _hover
                      ? AppColors.primaryBlue
                      : const Color(0xFF6B7280),
                ),
                child: const Text('View All'),
              ),
              const SizedBox(width: 4),
              AnimatedSlide(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                offset: Offset(_hover ? 0.15 : 0, 0),
                child: Icon(
                  Icons.arrow_forward_rounded,
                  size: 13,
                  color: _hover
                      ? AppColors.primaryBlue
                      : const Color(0xFF9CA3AF),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Post row ──────────────────────────────────────────────────────────────────
class _PostRow extends StatefulWidget {
  final Map<String, dynamic> post;
  final String timeAgo;
  final VoidCallback onTap;

  const _PostRow({
    required this.post,
    required this.timeAgo,
    required this.onTap,
  });

  @override
  State<_PostRow> createState() => _PostRowState();
}

class _PostRowState extends State<_PostRow> {
  bool _hover = false;

  static const Map<String, _BadgeStyle> _badges = {
    'news': _BadgeStyle(
      bg: Color(0xFFEFF6FF),
      fg: Color(0xFF1D4ED8),
      label: 'News',
    ),
    'event': _BadgeStyle(
      bg: Color(0xFFF0FDF4),
      fg: Color(0xFF15803D),
      label: 'Event',
    ),
    'announcement': _BadgeStyle(
      bg: Color(0xFFFFF7ED),
      fg: Color(0xFFB45309),
      label: 'Announcement',
    ),
  };

  _BadgeStyle _badgeFor(Map<String, dynamic> post) {
    final type = (post['type'] as String? ?? '').toLowerCase();
    final category = (post['category'] as String? ?? '').toLowerCase();
    final key = _badges.containsKey(type)
        ? type
        : _badges.containsKey(category)
        ? category
        : null;
    return key != null
        ? _badges[key]!
        : const _BadgeStyle(
            bg: Color(0xFFF3F4F6),
            fg: Color(0xFF6B7280),
            label: 'Post',
          );
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final urls = post['imageUrls'] as List<String>? ?? [];
    final hasImage = urls.isNotEmpty;
    final title = post['title'] as String? ?? '';
    final body = post['body'] as String? ?? post['content'] as String? ?? '';
    final rawBarangay = (post['barangay'] as String?)?.trim() ?? '';
    final source = rawBarangay.isNotEmpty ? rawBarangay : 'LGU Aparri';
    final badge = _badgeFor(post);
    final likes = post['likes'] as String? ?? '0';
    final commentCount =
        post['commentCount'] ??
        (post['comments'] as List<dynamic>? ?? []).length;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          decoration: BoxDecoration(
            color: _hover ? const Color(0xFFF8FAFF) : const Color(0x00F8FAFF),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: AppColors.primaryBlue.withOpacity(_hover ? 0.25 : 0.0),
              width: 1.2,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: hasImage
                      ? CachedNetworkImage(
                          imageUrl: urls.first,
                          fit: BoxFit.cover,
                          fadeInDuration: const Duration(milliseconds: 300),
                          fadeOutDuration: const Duration(milliseconds: 100),
                          placeholder: (context, url) => _placeholder(),
                          errorWidget: (context, url, error) => _placeholder(),
                        )
                      : _placeholder(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _Badge(style: badge),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            widget.timeAgo,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFFB0B6BE),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            source,
                            textAlign: TextAlign.right,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF9CA3AF),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeInOut,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: _hover
                            ? AppColors.primaryBlue
                            : const Color(0xFF111827),
                        height: 1.35,
                      ),
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (body.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        body,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: Color(0xFF9CA3AF),
                          height: 1.3,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(
                          Icons.favorite_rounded,
                          size: 11,
                          color: Color(0xFFF87171),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          likes,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF9CA3AF),
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Icon(
                          Icons.chat_bubble_rounded,
                          size: 11,
                          color: Color(0xFF9CA3AF),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$commentCount',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF9CA3AF),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFEFF6FF), Color(0xFFDBEAFE)],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.photo_outlined,
          size: 22,
          color: AppColors.primaryBlue.withOpacity(0.30),
        ),
      ),
    );
  }
}

class _BadgeStyle {
  final Color bg;
  final Color fg;
  final String label;
  const _BadgeStyle({required this.bg, required this.fg, required this.label});
}

class _Badge extends StatelessWidget {
  final _BadgeStyle style;
  const _Badge({required this.style});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: style.bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        style.label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: style.fg,
        ),
      ),
    );
  }
}
