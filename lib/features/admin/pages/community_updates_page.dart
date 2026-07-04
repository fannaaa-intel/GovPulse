import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/Home/Newsfeed/image_grid.dart';
import '../../../core/widgets/Home/Newsfeed/news_feed_helpers.dart';
import '../../../core/widgets/modal/media_picker_sheet.dart';
import '../providers/admin_profile_provider.dart';
import '../providers/community_updates_provider.dart';
import '../theme/admin_ui.dart';
import '../widgets/admin_skeleton.dart';
import '../widgets/admin_snackbar.dart';

const int _kMaxImages = 6;

// ════════════════════════════════════════════════════════════════════════════
//  Community Updates page  (admin nav slot "Community")
//
//  Facebook-style: a composer bar pinned to the top, the published feed below,
//  and a separate "Requests" tab holding the pending posts staff submit for
//  approval. Lives inside the existing AdminDashboardScreen shell, which already
//  provides the responsive sidebar / drawer + topbar, so here we just centre a
//  ~720px feed column and let it go full-width on mobile.
// ════════════════════════════════════════════════════════════════════════════

class CommunityUpdatesPage extends ConsumerStatefulWidget {
  const CommunityUpdatesPage({super.key});

  @override
  ConsumerState<CommunityUpdatesPage> createState() =>
      _CommunityUpdatesPageState();
}

enum _Tab { feed, requests }

class _CommunityUpdatesPageState extends ConsumerState<CommunityUpdatesPage> {
  _Tab _tab = _Tab.feed;

  @override
  Widget build(BuildContext context) {
    final asyncPosts = ref.watch(communityUpdatesProvider);
    final pending = ref.watch(pendingCountProvider);
    final width = MediaQuery.of(context).size.width;
    final pad = width < 600 ? 14.0 : 24.0;

    return Container(
      color: AdminUi.pageBg,
      child: RefreshIndicator(
        onRefresh: () => ref.read(communityUpdatesProvider.notifier).refresh(),
        color: AppColors.primaryBlue,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(pad, pad, pad, pad + 40),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _TabBar(
                    tab: _tab,
                    pendingCount: pending,
                    onChanged: (t) => setState(() => _tab = t),
                  ),
                  const SizedBox(height: 16),
                  if (_tab == _Tab.feed) ...[
                    _ComposerBar(
                      photoUrl:
                          ref.watch(adminProfileProvider).valueOrNull?.photoUrl,
                      onTap: () => showCommunityComposer(context, ref),
                    ),
                    const SizedBox(height: 16),
                  ],
                  asyncPosts.when(
                    loading: () => const _Loading(),
                    error: (e, _) => _ErrorState(
                      message: '$e',
                      onRetry: () =>
                          ref.read(communityUpdatesProvider.notifier).refresh(),
                    ),
                    data: (all) => _tab == _Tab.feed
                        ? _FeedList(posts: all)
                        : _RequestsList(posts: all),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Tab bar ───────────────────────────────────────────────────────────────────

class _TabBar extends StatelessWidget {
  final _Tab tab;
  final int pendingCount;
  final ValueChanged<_Tab> onChanged;
  const _TabBar({
    required this.tab,
    required this.pendingCount,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AdminUi.surface,
        borderRadius: BorderRadius.circular(AdminUi.controlRadius + 2),
        border: Border.all(color: AdminUi.border),
      ),
      child: Row(
        children: [
          _seg('Published feed', _Tab.feed, null),
          _seg('Requests', _Tab.requests, pendingCount),
        ],
      ),
    );
  }

  Widget _seg(String label, _Tab value, int? badge) {
    final selected = tab == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.primaryBlue : Colors.transparent,
            borderRadius: BorderRadius.circular(AdminUi.controlRadius),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : AdminUi.textSecondary,
                ),
              ),
              if (badge != null && badge > 0) ...[
                const SizedBox(width: 7),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: selected ? Colors.white : AppColors.red,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$badge',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: selected ? AppColors.primaryBlue : Colors.white,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Composer trigger bar (collapsed "What's on your mind") ─────────────────────

class _ComposerBar extends StatelessWidget {
  final VoidCallback onTap;
  final String? photoUrl;
  const _ComposerBar({required this.onTap, this.photoUrl});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AdminUi.surface,
        borderRadius: BorderRadius.circular(AdminUi.cardRadius),
        border: Border.all(color: AdminUi.border),
        boxShadow: AdminUi.cardShadow,
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          buildAuthorAvatar(42, photoUrl, ring: false),
          const SizedBox(width: 12),
          Expanded(
            child: Material(
              color: AdminUi.subtle,
              borderRadius: BorderRadius.circular(24),
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: onTap,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Text(
                    'Share an update with the community…',
                    style: TextStyle(fontSize: 14, color: AdminUi.textMuted),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Material(
            color: AppColors.primaryBlue,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: onTap,
              child: const Padding(
                padding: EdgeInsets.all(10),
                child: Icon(Icons.edit_rounded, color: Colors.white, size: 20),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Feed (approved posts) ─────────────────────────────────────────────────────

class _FeedList extends StatelessWidget {
  final List<CommunityUpdate> posts;
  const _FeedList({required this.posts});

  @override
  Widget build(BuildContext context) {
    final approved = posts
        .where((p) => p.status == PostStatus.approved)
        .toList();
    if (approved.isEmpty) {
      return const _EmptyState(
        icon: Icons.campaign_rounded,
        title: 'No updates yet',
        subtitle: 'Share your first community update using the box above.',
      );
    }
    return Column(
      children: [
        for (final p in approved)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _UpdateCard(post: p),
          ),
      ],
    );
  }
}

// ── Requests (pending + rejected history) ──────────────────────────────────────

class _RequestsList extends StatelessWidget {
  final List<CommunityUpdate> posts;
  const _RequestsList({required this.posts});

  @override
  Widget build(BuildContext context) {
    final pending = posts.where((p) => p.status == PostStatus.pending).toList();
    final rejected = posts
        .where((p) => p.status == PostStatus.rejected)
        .toList();

    if (pending.isEmpty && rejected.isEmpty) {
      return const _EmptyState(
        icon: Icons.inbox_rounded,
        title: 'No requests',
        subtitle: 'Posts submitted by staff for approval will appear here.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (pending.isNotEmpty) ...[
          _sectionLabel('Awaiting approval', pending.length),
          const SizedBox(height: 10),
          for (final p in pending)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _PendingCard(post: p),
            ),
        ],
        if (rejected.isNotEmpty) ...[
          const SizedBox(height: 6),
          _sectionLabel('Rejected', rejected.length),
          const SizedBox(height: 10),
          for (final p in rejected)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _UpdateCard(post: p),
            ),
        ],
      ],
    );
  }

  Widget _sectionLabel(String text, int count) => Row(
    children: [
      Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: AdminUi.textMuted,
        ),
      ),
      const SizedBox(width: 8),
      Text(
        '$count',
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: AdminUi.textMuted,
        ),
      ),
    ],
  );
}

// ── Post card (published feed + rejected history) ──────────────────────────────

class _UpdateCard extends ConsumerWidget {
  final CommunityUpdate post;
  const _UpdateCard({required this.post});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = MediaQuery.of(context).size.width.clamp(320, 720).toDouble();
    final rejected = post.status == PostStatus.rejected;

    return Container(
      decoration: BoxDecoration(
        color: AdminUi.surface,
        borderRadius: BorderRadius.circular(AdminUi.cardRadius),
        border: Border.all(
          color: post.pinned
              ? AppColors.primaryBlue.withValues(alpha: 0.35)
              : AdminUi.border,
        ),
        boxShadow: AdminUi.cardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (post.pinned) const _PinnedRibbon(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 0),
            child: Row(
              children: [
                buildAuthorAvatar(42, post.authorPhotoUrl, ring: false),
                const SizedBox(width: 10),
                Expanded(child: _authorMeta()),
                _CardMenu(post: post),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (post.title.trim().isNotEmpty) ...[
                  Text(
                    post.title,
                    style: const TextStyle(
                      fontSize: 16.5,
                      fontWeight: FontWeight.w700,
                      color: AdminUi.textPrimary,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 6),
                ],
                Text(
                  post.body,
                  style: const TextStyle(
                    fontSize: 14.5,
                    color: AdminUi.textSecondary,
                    height: 1.45,
                  ),
                ),
                if (rejected && (post.rejectedReason?.isNotEmpty ?? false)) ...[
                  const SizedBox(height: 10),
                  _ReasonBox(reason: post.rejectedReason!),
                ],
              ],
            ),
          ),
          if (post.imageUrls.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: buildImageGrid(
                width - 32,
                post.imageUrls.length,
                imageUrls: post.imageUrls,
                // Tap a photo to open the same full-screen viewer the citizen
                // newsfeed uses (swipeable, zoomable).
                onImageTap: (index) => openImageViewer(
                  context,
                  post.imageUrls.length,
                  index,
                  urls: post.imageUrls,
                ),
              ),
            ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: AdminUi.border),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                _stat(Icons.favorite_rounded, post.likesCount, AppColors.red),
                const SizedBox(width: 18),
                InkWell(
                  onTap: () => showCommentsPanel(context, ref, post),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    child: _stat(
                      Icons.mode_comment_rounded,
                      post.commentsCount,
                      AdminUi.textMuted,
                    ),
                  ),
                ),
                const Spacer(),
                if (rejected) _RejectedReapprove(post: post) else _statusPill(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _authorMeta() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                post.authorName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: AdminUi.textPrimary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            _TagChip(label: post.tag, color: post.tagColorValue),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                '${post.barangayLabel} · ${post.createdAt == null ? '' : formatTimeAgo(post.createdAt!)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AdminUi.textMuted,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _stat(IconData icon, int n, Color color) => Row(
    children: [
      Icon(icon, size: 16, color: color),
      const SizedBox(width: 5),
      Text(
        '$n',
        style: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: AdminUi.textSecondary,
        ),
      ),
    ],
  );

  Widget _statusPill() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: AppColors.green.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.public_rounded, size: 13, color: AppColors.green),
        SizedBox(width: 5),
        Text(
          'Published',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: AppColors.green,
          ),
        ),
      ],
    ),
  );
}

class _PinnedRibbon extends StatelessWidget {
  const _PinnedRibbon();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.primaryBlue.withValues(alpha: 0.07),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: const Row(
        children: [
          Icon(Icons.push_pin_rounded, size: 13, color: AppColors.primaryBlue),
          SizedBox(width: 6),
          Text(
            'Pinned to top',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: AppColors.primaryBlue,
            ),
          ),
        ],
      ),
    );
  }
}

class _RejectedReapprove extends ConsumerWidget {
  final CommunityUpdate post;
  const _RejectedReapprove({required this.post});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TextButton.icon(
      onPressed: () async {
        await ref.read(communityUpdatesProvider.notifier).approve(post.id);
        if (context.mounted) {
          _toast(context, 'Post approved and published.');
        }
      },
      icon: const Icon(Icons.check_circle_rounded, size: 16),
      label: const Text('Approve anyway'),
      style: TextButton.styleFrom(foregroundColor: AppColors.green),
    );
  }
}

// ── Card overflow menu: Edit / Pin / Delete ────────────────────────────────────

class _CardMenu extends ConsumerWidget {
  final CommunityUpdate post;
  const _CardMenu({required this.post});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(communityUpdatesProvider.notifier);
    final published = post.status == PostStatus.approved;

    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_horiz_rounded, color: AdminUi.textMuted),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (v) async {
        switch (v) {
          case 'edit':
            showCommunityComposer(context, ref, existing: post);
            break;
          case 'pin':
            await notifier.togglePin(post);
            if (context.mounted) {
              _toast(context, post.pinned ? 'Unpinned.' : 'Pinned to top.');
            }
            break;
          case 'delete':
            final ok = await _confirmDelete(context);
            if (ok == true) {
              await notifier.delete(post);
              if (context.mounted) _toast(context, 'Post deleted.');
            }
            break;
        }
      },
      itemBuilder: (_) => [
        _item('edit', Icons.edit_rounded, 'Edit'),
        if (published)
          _item(
            'pin',
            post.pinned ? Icons.push_pin_outlined : Icons.push_pin_rounded,
            post.pinned ? 'Unpin' : 'Pin to top',
          ),
        _item('delete', Icons.delete_outline_rounded, 'Delete', danger: true),
      ],
    );
  }

  PopupMenuItem<String> _item(
    String v,
    IconData icon,
    String label, {
    bool danger = false,
  }) {
    final c = danger ? AppColors.red : AdminUi.textSecondary;
    return PopupMenuItem<String>(
      value: v,
      height: 42,
      child: Row(
        children: [
          Icon(icon, size: 18, color: c),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: c,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Pending request card with Approve / Reject ─────────────────────────────────

class _PendingCard extends ConsumerStatefulWidget {
  final CommunityUpdate post;
  const _PendingCard({required this.post});
  @override
  ConsumerState<_PendingCard> createState() => _PendingCardState();
}

class _PendingCardState extends ConsumerState<_PendingCard> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final width = MediaQuery.of(context).size.width.clamp(320, 720).toDouble();

    return Container(
      decoration: BoxDecoration(
        color: AdminUi.surface,
        borderRadius: BorderRadius.circular(AdminUi.cardRadius),
        border: Border.all(color: AppColors.orange.withValues(alpha: 0.45)),
        boxShadow: AdminUi.cardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            color: AppColors.orange.withValues(alpha: 0.10),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            child: Row(
              children: [
                const Icon(
                  Icons.hourglass_top_rounded,
                  size: 14,
                  color: AppColors.orange,
                ),
                const SizedBox(width: 6),
                Text(
                  'Submitted by ${post.authorName} · ${post.createdAt == null ? '' : formatTimeAgo(post.createdAt!)}',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.orange,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _TagChip(label: post.tag, color: post.tagColorValue),
                    const SizedBox(width: 8),
                    Text(
                      post.barangayLabel,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AdminUi.textMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (post.title.trim().isNotEmpty)
                  Text(
                    post.title,
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                      color: AdminUi.textPrimary,
                    ),
                  ),
                const SizedBox(height: 4),
                Text(
                  post.body,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AdminUi.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          if (post.imageUrls.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: buildImageGrid(
                width - 28,
                post.imageUrls.length,
                imageUrls: post.imageUrls,
                onImageTap: (index) => openImageViewer(
                  context,
                  post.imageUrls.length,
                  index,
                  urls: post.imageUrls,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _reject,
                    icon: const Icon(Icons.close_rounded, size: 18),
                    label: const Text('Reject'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.red,
                      side: const BorderSide(color: AppColors.red),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _approve,
                    icon: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Approve'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.green,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _approve() async {
    setState(() => _busy = true);
    try {
      await ref.read(communityUpdatesProvider.notifier).approve(widget.post.id);
      if (mounted) _toast(context, 'Approved and published.');
    } catch (e) {
      if (mounted) _toast(context, 'Could not approve: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    final reason = await _askReason(context);
    if (reason == null) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(communityUpdatesProvider.notifier)
          .reject(widget.post.id, reason);
      if (mounted) _toast(context, 'Post rejected.');
    } catch (e) {
      if (mounted) _toast(context, 'Could not reject: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

// ── Shared small widgets ────────────────────────────────────────────────────────

class _TagChip extends StatelessWidget {
  final String label;
  final Color color;
  const _TagChip({required this.label, required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _ReasonBox extends StatelessWidget {
  final String reason;
  const _ReasonBox({required this.reason});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.red.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.red.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 15,
            color: AppColors.red,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Rejected: $reason',
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.red,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      decoration: BoxDecoration(
        color: AdminUi.surface,
        borderRadius: BorderRadius.circular(AdminUi.cardRadius),
        border: Border.all(color: AdminUi.border),
      ),
      child: Column(
        children: [
          Icon(icon, size: 40, color: AdminUi.textMuted),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AdminUi.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: AdminUi.textMuted),
          ),
        ],
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) => const AdminShimmer(
    child: Column(
      children: [
        _PostSkeleton(),
        SizedBox(height: 16),
        _PostSkeleton(),
        SizedBox(height: 16),
        _PostSkeleton(),
      ],
    ),
  );
}

/// Post-card-shaped placeholder for the community feed (fills the column width,
/// so it stays responsive between the 720px desktop column and full-width phone).
class _PostSkeleton extends StatelessWidget {
  const _PostSkeleton();
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AdminUi.surface,
        borderRadius: BorderRadius.circular(AdminUi.cardRadius),
        border: Border.all(color: AdminUi.border),
      ),
      padding: const EdgeInsets.all(16),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SkeletonCircle(size: 42),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(width: 150, height: 13),
                    SizedBox(height: 8),
                    SkeletonBox(width: 90, height: 11),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          SkeletonBox(width: double.infinity, height: 12),
          SizedBox(height: 9),
          SkeletonBox(width: double.infinity, height: 12),
          SizedBox(height: 9),
          SkeletonBox(width: 220, height: 12),
          SizedBox(height: 16),
          SkeletonBox(width: double.infinity, height: 170, radius: 10),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: AdminUi.surface,
        borderRadius: BorderRadius.circular(AdminUi.cardRadius),
        border: Border.all(color: AdminUi.border),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.cloud_off_rounded,
            size: 36,
            color: AdminUi.textMuted,
          ),
          const SizedBox(height: 10),
          const Text(
            "Couldn't load updates",
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AdminUi.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5, color: AdminUi.textMuted),
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: onRetry,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryBlue,
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

// ── Toast / dialogs ─────────────────────────────────────────────────────────────

void _toast(BuildContext context, String msg, {bool error = false}) {
  showAdminSnackBar(
    context,
    msg,
    type: error ? AdminSnackType.error : AdminSnackType.success,
  );
}

Future<bool?> _confirmDelete(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Delete this post?'),
      content: const Text(
        'This permanently removes the update and its photos for everyone.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(backgroundColor: AppColors.red),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
}

Future<String?> _askReason(BuildContext context) {
  final ctrl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Reject post'),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        maxLines: 3,
        decoration: InputDecoration(
          hintText: 'Reason for rejection (shared with the author)…',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
          style: FilledButton.styleFrom(backgroundColor: AppColors.red),
          child: const Text('Reject'),
        ),
      ],
    ),
  );
}

// ════════════════════════════════════════════════════════════════════════════
//  Composer — responsive: modal dialog on wide screens, full-screen on mobile.
// ════════════════════════════════════════════════════════════════════════════

void showCommunityComposer(
  BuildContext context,
  WidgetRef ref, {
  CommunityUpdate? existing,
}) {
  final wide = MediaQuery.of(context).size.width >= 900;
  if (wide) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
          child: _ComposerForm(existing: existing),
        ),
      ),
    );
  } else {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => Scaffold(
          backgroundColor: AdminUi.surface,
          body: SafeArea(child: _ComposerForm(existing: existing)),
        ),
      ),
    );
  }
}

class _ComposerForm extends ConsumerStatefulWidget {
  final CommunityUpdate? existing;
  const _ComposerForm({this.existing});
  @override
  ConsumerState<_ComposerForm> createState() => _ComposerFormState();
}

class _ComposerFormState extends ConsumerState<_ComposerForm> {
  late final TextEditingController _title;
  late final TextEditingController _body;
  late UpdateCategory _category;
  late String _barangay;
  final ImagePicker _picker = ImagePicker();

  final List<ComposerImage> _images = [];
  final List<PostImage> _removed = [];
  final Map<String, Uint8List> _thumbCache = {};
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _title = TextEditingController(text: e?.title ?? '');
    _body = TextEditingController(text: e?.body ?? '');
    _category = e == null
        ? UpdateCategory.all.first
        : UpdateCategory.byLabel(e.tag);
    _barangay = e?.barangay ?? kAllBarangays;
    if (e != null) {
      _images.addAll(e.images.map((img) => ComposerImage.remote(img)));
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AdminUi.surface,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _header(),
          const Divider(height: 1, color: AdminUi.border),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      buildAuthorAvatar(
                        40,
                        ref.watch(adminProfileProvider).valueOrNull?.photoUrl,
                        ring: false,
                      ),
                      const SizedBox(width: 10),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'LGU Aparri',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AdminUi.textPrimary,
                            ),
                          ),
                          Text(
                            'Official update',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: AdminUi.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _field(_title, 'Title', maxLines: 1),
                  const SizedBox(height: 12),
                  _field(
                    _body,
                    'Share an update with the community…',
                    maxLines: 6,
                  ),
                  const SizedBox(height: 18),
                  _label('Category'),
                  const SizedBox(height: 8),
                  _categoryChips(),
                  const SizedBox(height: 18),
                  _label('Audience'),
                  const SizedBox(height: 8),
                  _barangayDropdown(),
                  const SizedBox(height: 18),
                  _label('Photos'),
                  const SizedBox(height: 8),
                  _imagePicker(),
                ],
              ),
            ),
          ),
          const Divider(height: 1, color: AdminUi.border),
          _footer(),
        ],
      ),
    );
  }

  Widget _header() => Padding(
    padding: const EdgeInsets.fromLTRB(18, 14, 10, 14),
    child: Row(
      children: [
        Text(
          _isEdit ? 'Edit update' : 'Create update',
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AdminUi.textPrimary,
          ),
        ),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.close_rounded, color: AdminUi.textMuted),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    ),
  );

  Widget _label(String t) => Text(
    t,
    style: const TextStyle(
      fontSize: 12.5,
      fontWeight: FontWeight.w700,
      color: AdminUi.textSecondary,
    ),
  );

  Widget _field(TextEditingController c, String hint, {required int maxLines}) {
    return TextField(
      controller: c,
      maxLines: maxLines,
      style: const TextStyle(fontSize: 15, color: AdminUi.textPrimary),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AdminUi.textMuted),
        filled: true,
        fillColor: AdminUi.subtle,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AdminUi.controlRadius),
          borderSide: const BorderSide(color: AdminUi.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AdminUi.controlRadius),
          borderSide: const BorderSide(color: AdminUi.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AdminUi.controlRadius),
          borderSide: const BorderSide(
            color: AppColors.primaryBlue,
            width: 1.4,
          ),
        ),
      ),
    );
  }

  Widget _categoryChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: UpdateCategory.all.map((c) {
        final sel = c.label == _category.label;
        return GestureDetector(
          onTap: () => setState(() => _category = c),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 130),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: sel ? c.color.withValues(alpha: 0.14) : AdminUi.subtle,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: sel ? c.color : AdminUi.border,
                width: sel ? 1.4 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: c.color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  c.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                    color: sel ? c.color : AdminUi.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _barangayDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AdminUi.subtle,
        borderRadius: BorderRadius.circular(AdminUi.controlRadius),
        border: Border.all(color: AdminUi.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: _barangay,
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: AdminUi.textMuted,
          ),
          borderRadius: BorderRadius.circular(12),
          items: [
            const DropdownMenuItem(
              value: kAllBarangays,
              child: Text('All barangays (city-wide)'),
            ),
            ...kBarangayOptions.map(
              (b) => DropdownMenuItem(value: b, child: Text(b)),
            ),
          ],
          onChanged: (v) => setState(() => _barangay = v ?? kAllBarangays),
          style: const TextStyle(fontSize: 14, color: AdminUi.textPrimary),
        ),
      ),
    );
  }

  Widget _imagePicker() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (var i = 0; i < _images.length; i++) _thumb(_images[i], i),
        if (_images.length < _kMaxImages) _addTile(),
      ],
    );
  }

  Widget _addTile() => GestureDetector(
    onTap: _pickImages,
    child: Container(
      width: 84,
      height: 84,
      decoration: BoxDecoration(
        color: AdminUi.subtle,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AdminUi.borderStrong),
      ),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.add_a_photo_rounded, color: AdminUi.textMuted, size: 22),
          SizedBox(height: 4),
          Text('Add', style: TextStyle(fontSize: 11, color: AdminUi.textMuted)),
        ],
      ),
    ),
  );

  Widget _thumb(ComposerImage img, int index) {
    return SizedBox(
      width: 84,
      height: 84,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: img.isNew
                ? _LocalThumb(file: img.file!, cache: _thumbCache)
                : Image.network(
                    img.existing!.url,
                    width: 84,
                    height: 84,
                    fit: BoxFit.cover,
                  ),
          ),
          Positioned(
            top: 3,
            right: 3,
            child: GestureDetector(
              onTap: () => setState(() {
                if (!img.isNew) _removed.add(img.existing!);
                _images.removeAt(index);
              }),
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close_rounded,
                  size: 14,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _footer() {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 14, 16, 14 + bottomInset),
      child: SizedBox(
        width: double.infinity,
        height: 54,
        child: FilledButton(
          onPressed: _saving ? null : _submit,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primaryBlue,
            disabledBackgroundColor: AppColors.primaryBlue.withValues(
              alpha: 0.55,
            ),
            foregroundColor: Colors.white,
            elevation: 2,
            shadowColor: AppColors.primaryBlue.withValues(alpha: 0.40),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: _saving
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.6,
                    color: Colors.white,
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _isEdit ? Icons.check_rounded : Icons.publish_rounded,
                      size: 19,
                    ),
                    const SizedBox(width: 9),
                    Text(
                      _isEdit ? 'Save changes' : 'Post update',
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  static const Set<String> _imageExts = {
    'jpg',
    'jpeg',
    'jfif',
    'pjpeg',
    'pjp',
    'png',
    'gif',
    'webp',
    'heic',
    'heif',
    'bmp',
  };
  static const int _maxImageBytes = 10 * 1024 * 1024; // 10 MB (matches app)

  Future<void> _pickImages() async {
    final remaining = _kMaxImages - _images.length;
    if (remaining <= 0) return;

    // The composer is a floating dialog at >=900px and a full-screen page below
    // that. A slide-up sheet only belongs to the full-screen case (it would
    // detach from a floating card), so match the two.
    final floating = MediaQuery.of(context).size.width >= 900;
    try {
      if (floating) {
        await _addValidated(await _picker.pickMultiImage(limit: remaining));
      } else {
        final mode = await showMediaPickerSheet(context, allowVideo: false);
        if (mode == null) return;
        if (mode == 'camera') {
          final shot = await _picker.pickImage(source: ImageSource.camera);
          await _addValidated(shot == null ? const [] : [shot]);
        } else {
          await _addValidated(await _picker.pickMultiImage(limit: remaining));
        }
      }
    } catch (e) {
      if (mounted) _toast(context, 'Could not add photo: $e', error: true);
    }
  }

  /// Accepts image files only. Rejects videos / other file types (which a user
  /// can still slip through the web "All files" option) and anything over the
  /// size cap, telling the user what was skipped.
  Future<void> _addValidated(List<XFile> picked) async {
    if (picked.isEmpty) return;
    final remaining = _kMaxImages - _images.length;
    final accepted = <XFile>[];
    var rejectedType = false;
    var rejectedSize = false;

    for (final f in picked) {
      if (accepted.length >= remaining) break;
      final name = f.name.toLowerCase();
      final dot = name.lastIndexOf('.');
      final ext = dot == -1 ? '' : name.substring(dot + 1);
      if (!_imageExts.contains(ext)) {
        rejectedType = true;
        continue;
      }
      final size = await f.length();
      if (size > _maxImageBytes) {
        rejectedSize = true;
        continue;
      }
      accepted.add(f);
    }

    if (accepted.isNotEmpty) {
      setState(
        () => _images.addAll(accepted.map((f) => ComposerImage.local(f))),
      );
    }
    if (!mounted) return;
    if (rejectedType) {
      _toast(
        context,
        'Only photos can be added — videos and other files aren\'t supported.',
        error: true,
      );
    } else if (rejectedSize) {
      _toast(
        context,
        'Some photos were over 10 MB and were skipped.',
        error: true,
      );
    }
  }

  Future<void> _submit() async {
    final title = _title.text.trim();
    final body = _body.text.trim();
    if (title.isEmpty) {
      _toast(context, 'Please add a title.', error: true);
      return;
    }
    if (body.isEmpty) {
      _toast(context, 'Please write the update.', error: true);
      return;
    }

    setState(() => _saving = true);
    final notifier = ref.read(communityUpdatesProvider.notifier);
    try {
      if (_isEdit) {
        final kept = _images.where((i) => !i.isNew).length;
        final added = _images
            .where((i) => i.isNew)
            .map((i) => i.file!)
            .toList();
        await notifier.updatePost(
          id: widget.existing!.id,
          title: title,
          body: body,
          barangay: _barangay,
          category: _category,
          removed: _removed,
          added: added,
          keptCount: kept,
        );
      } else {
        final files = _images.map((i) => i.file!).toList();
        await notifier.createPost(
          title: title,
          body: body,
          barangay: _barangay,
          category: _category,
          images: files,
        );
      }
      if (mounted) {
        Navigator.of(context).pop();
        _toast(context, _isEdit ? 'Update saved.' : 'Update published.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _toast(context, 'Could not save: $e', error: true);
      }
    }
  }
}

/// Renders a freshly-picked (not-yet-uploaded) image from its bytes.
class _LocalThumb extends StatelessWidget {
  final XFile file;
  final Map<String, Uint8List> cache;
  const _LocalThumb({required this.file, required this.cache});

  @override
  Widget build(BuildContext context) {
    final cached = cache[file.path];
    if (cached != null) {
      return Image.memory(cached, width: 84, height: 84, fit: BoxFit.cover);
    }
    return FutureBuilder<Uint8List>(
      future: file.readAsBytes(),
      builder: (_, snap) {
        if (snap.hasData) {
          cache[file.path] = snap.data!;
          return Image.memory(
            snap.data!,
            width: 84,
            height: 84,
            fit: BoxFit.cover,
          );
        }
        return Container(
          width: 84,
          height: 84,
          color: AdminUi.subtle,
          child: const Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  Comments panel — view / delete / reply as the official account.
//  Dialog on wide screens, full-screen page on mobile (matches the composer).
// ════════════════════════════════════════════════════════════════════════════

void showCommentsPanel(
  BuildContext context,
  WidgetRef ref,
  CommunityUpdate post,
) {
  final wide = MediaQuery.of(context).size.width >= 900;
  if (wide) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
          child: _CommentsPanel(post: post),
        ),
      ),
    );
  } else {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => Scaffold(
          backgroundColor: AdminUi.surface,
          body: SafeArea(child: _CommentsPanel(post: post)),
        ),
      ),
    );
  }
}

class _CommentsPanel extends ConsumerStatefulWidget {
  final CommunityUpdate post;
  const _CommentsPanel({required this.post});
  @override
  ConsumerState<_CommentsPanel> createState() => _CommentsPanelState();
}

class _CommentsPanelState extends ConsumerState<_CommentsPanel> {
  final TextEditingController _input = TextEditingController();
  late Future<List<CommunityComment>> _future;
  String? _replyToId;
  String? _replyToName;
  bool _sending = false;

  CommunityUpdatesRepository get _repo =>
      ref.read(communityUpdatesRepoProvider);

  @override
  void initState() {
    super.initState();
    _future = _repo.fetchComments(widget.post.id);
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _reload() {
    // Block body (not an arrow) so the setState callback returns void — an
    // arrow `() => _future = ...` returns the assigned Future, which trips
    // Flutter's "setState() callback returned a Future" assertion.
    setState(() {
      _future = _repo.fetchComments(widget.post.id);
    });
    // Keep the feed's comment counts in sync.
    ref.read(communityUpdatesProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AdminUi.surface,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _header(),
          const Divider(height: 1, color: AdminUi.border),
          Flexible(
            child: FutureBuilder<List<CommunityComment>>(
              future: _future,
              builder: (_, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const AdminShimmer(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      child: Column(
                        children: [
                          _CommentSkeletonRow(),
                          _CommentSkeletonRow(),
                          _CommentSkeletonRow(),
                          _CommentSkeletonRow(),
                        ],
                      ),
                    ),
                  );
                }
                if (snap.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Could not load comments: ${snap.error}',
                      style: const TextStyle(color: AdminUi.textMuted),
                    ),
                  );
                }
                final all = snap.data ?? const [];
                if (all.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 48, horizontal: 24),
                    child: Center(
                      child: Text(
                        'No comments yet.',
                        style: TextStyle(color: AdminUi.textMuted),
                      ),
                    ),
                  );
                }
                final tops = all.where((c) => !c.isReply).toList();
                final repliesByParent = <String, List<CommunityComment>>{};
                for (final c in all.where((c) => c.isReply)) {
                  (repliesByParent[c.parentId!] ??= []).add(c);
                }
                return ListView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  children: [
                    for (final c in tops) ...[
                      _CommentTile(
                        comment: c,
                        onDelete: () => _delete(c),
                        onReply: () => setState(() {
                          _replyToId = c.id;
                          _replyToName = c.authorName;
                        }),
                      ),
                      for (final r in (repliesByParent[c.id] ?? const []))
                        Padding(
                          padding: const EdgeInsets.only(left: 40),
                          child: _CommentTile(
                            comment: r,
                            onDelete: () => _delete(r),
                            onReply: () => setState(() {
                              _replyToId =
                                  c.id; // replies attach to the top-level
                              _replyToName = r.authorName;
                            }),
                          ),
                        ),
                    ],
                  ],
                );
              },
            ),
          ),
          const Divider(height: 1, color: AdminUi.border),
          _composer(),
        ],
      ),
    );
  }

  Widget _header() => Padding(
    padding: const EdgeInsets.fromLTRB(18, 14, 10, 14),
    child: Row(
      children: [
        const Text(
          'Comments',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AdminUi.textPrimary,
          ),
        ),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.close_rounded, color: AdminUi.textMuted),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    ),
  );

  Widget _composer() {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        12,
        8,
        12,
        10 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_replyToName != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Icon(
                    Icons.reply_rounded,
                    size: 15,
                    color: AppColors.primaryBlue,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Replying to $_replyToName',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AdminUi.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => setState(() {
                      _replyToId = null;
                      _replyToName = null;
                    }),
                    child: const Icon(
                      Icons.close_rounded,
                      size: 15,
                      color: AdminUi.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              buildAvatar(
                34,
                ref.watch(adminProfileProvider).valueOrNull?.photoUrl,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _input,
                  minLines: 1,
                  maxLines: 4,
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Write a comment as LGU Aparri…',
                    hintStyle: const TextStyle(color: AdminUi.textMuted),
                    filled: true,
                    fillColor: AdminUi.subtle,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: const BorderSide(color: AdminUi.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: const BorderSide(color: AdminUi.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: const BorderSide(
                        color: AppColors.primaryBlue,
                        width: 1.4,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Material(
                color: AppColors.primaryBlue,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _sending ? null : _send,
                  child: Padding(
                    padding: const EdgeInsets.all(11),
                    child: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(
                            Icons.send_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      await _repo.addComment(widget.post.id, text, parentId: _replyToId);
      _input.clear();
      _replyToId = null;
      _replyToName = null;
      _reload();
    } catch (e) {
      if (mounted) _toast(context, 'Could not post comment: $e', error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _delete(CommunityComment c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete comment?'),
        content: const Text('This removes the comment for everyone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _repo.deleteComment(c.id);
      _reload();
      if (mounted) _toast(context, 'Comment deleted.');
    } catch (e) {
      if (mounted) _toast(context, 'Could not delete: $e', error: true);
    }
  }
}

class _CommentSkeletonRow extends StatelessWidget {
  const _CommentSkeletonRow();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonCircle(size: 34),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: double.infinity, height: 46, radius: 14),
                SizedBox(height: 6),
                SkeletonBox(width: 120, height: 10),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  final CommunityComment comment;
  final VoidCallback onDelete;
  final VoidCallback onReply;
  const _CommentTile({
    required this.comment,
    required this.onDelete,
    required this.onReply,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          buildAvatar(34, comment.authorPhotoUrl),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AdminUi.subtle,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              comment.authorName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AdminUi.textPrimary,
                              ),
                            ),
                          ),
                          if (comment.isOfficial) ...[
                            const SizedBox(width: 5),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primaryBlue.withValues(
                                  alpha: 0.12,
                                ),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'LGU',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.primaryBlue,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        comment.body,
                        style: const TextStyle(
                          fontSize: 13.5,
                          color: AdminUi.textSecondary,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: 6),
                  child: Row(
                    children: [
                      if (comment.createdAt != null)
                        Text(
                          formatTimeAgo(comment.createdAt!),
                          style: const TextStyle(
                            fontSize: 11,
                            color: AdminUi.textMuted,
                          ),
                        ),
                      const SizedBox(width: 14),
                      GestureDetector(
                        onTap: onReply,
                        child: const Text(
                          'Reply',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: AdminUi.textMuted,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      GestureDetector(
                        onTap: onDelete,
                        child: const Text(
                          'Delete',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.red,
                          ),
                        ),
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
}
