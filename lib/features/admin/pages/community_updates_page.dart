import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/deeplink_highlight.dart';
import '../../../core/widgets/Home/Newsfeed/image_grid.dart';
import '../../../core/widgets/Home/Newsfeed/comment_post_recap.dart';
import '../../../core/widgets/Home/Newsfeed/comments_sheet.dart'
    show kThreadMetrics;
import '../../../core/widgets/Home/Newsfeed/news_feed_helpers.dart';
import '../../../core/widgets/modal/media_picker_sheet.dart';
import '../providers/admin_flagged_comments_provider.dart';
import '../providers/admin_profile_provider.dart';
import '../providers/community_updates_provider.dart';
import '../theme/admin_ui.dart';
import 'admin_flagged_comments_page.dart';
import '../widgets/admin_dialog_back.dart';
import '../widgets/admin_skeleton.dart';
import '../widgets/admin_snackbar.dart';
import '../widgets/admin_user_actions.dart';
import '../../../core/widgets/app_dialog.dart';

const int _kMaxImages = 6;

class CommunityUpdatesPage extends ConsumerStatefulWidget {
  /// A POST id (or, from newer triggers, a COMMENT id — resolved after load)
  /// to scroll to and flash once, when arriving from a notification.
  /// Null for a normal open.
  final String? highlightId;

  /// True when the notification was about a comment/reply: after landing on
  /// the post, its comments panel opens — with the target comment flashed blue
  /// when the reference identified one.
  final bool openComments;

  /// Identifies the deep-link TAP, not the target. Bumped by the shell on every
  /// notification tap so two taps on the same post are two distinct events —
  /// comparing highlightId/openComments alone can't tell them apart, and the
  /// second one was being swallowed.
  final int deepLinkNonce;

  const CommunityUpdatesPage({
    super.key,
    this.highlightId,
    this.openComments = false,
    this.deepLinkNonce = 0,
  });

  @override
  ConsumerState<CommunityUpdatesPage> createState() =>
      _CommunityUpdatesPageState();
}

enum _Tab { feed, requests }

class _CommunityUpdatesPageState extends ConsumerState<CommunityUpdatesPage>
    with DeepLinkHighlightMixin {
  _Tab _tab = _Tab.feed;

  /// The last target we switched tabs for. Keyed on the id (not a bool) for the
  /// same reason as [flashHighlightOnce]: this page stays mounted when a second
  /// notification arrives while it's already open, so a latch would swallow it.
  /// Keyed on target id AND whether the thread was asked for — a heart and a
  /// reply on the SAME post share an id, so an id-only latch let the heart tap
  /// consume the reply tap and the comments panel never opened.
  String? _tabSwitchedFor;

  /// The reference may be a comment id rather than a post id — resolved once
  /// against community_comments when no post matches.
  late String? _targetId = widget.highlightId;
  String? _targetCommentId;
  bool _triedCommentResolve = false;

  @override
  void didUpdateWidget(covariant CommunityUpdatesPage old) {
    super.didUpdateWidget(old);
    // `_targetId` is a `late` initialiser, so it only ever read highlightId at
    // initState. When the admin is ALREADY on Community — the common case for a
    // "post awaiting review" ping, since that is where they work — the shell
    // rebuilds this page with a new highlightId but the State survives, so the
    // target was silently dropped and the tap appeared to do nothing. Re-arm
    // here, exactly as the staff feed tab does.
    final newTap =
        widget.highlightId != null && widget.deepLinkNonce != old.deepLinkNonce;
    if (newTap) {
      // Clear BOTH latches, not just the target. `_tabSwitchedFor` and the
      // mixin's own latch each key on the post id, so tapping the same heart
      // notification twice was swallowed by whichever one the first tap set.
      _tabSwitchedFor = null;
      rearmHighlight();
      setState(() {
        _targetId = widget.highlightId;
        _targetCommentId = null;
        _triedCommentResolve = false;
      });
    }
  }

  Future<void> _tryResolveCommentRef(String ref) async {
    if (_triedCommentResolve) return;
    _triedCommentResolve = true;
    try {
      final row = await Supabase.instance.client
          .from('community_comments')
          .select('id, post_id')
          .eq('id', ref)
          .maybeSingle();
      final postId = row?['post_id'] as String?;
      if (postId == null || !mounted) return;
      setState(() {
        _targetId = postId;
        _targetCommentId = ref;
      });
    } catch (_) {
      /* unresolved — the page just opens normally */
    }
  }

  /// Flashes the target once posts have loaded, first switching to the tab that
  /// actually contains it — a pending/rejected post lives on Requests, and
  /// flashing a row on a tab the admin isn't looking at accomplishes nothing.
  /// Comment notifications then open the post's comments panel on top.
  void _flashOnce(List<CommunityUpdate> all) {
    final id = _targetId;
    if (id == null || id.isEmpty) return;
    final latchKey = '$id|${widget.openComments}';
    if (_tabSwitchedFor == latchKey) return;

    CommunityUpdate? target;
    for (final p in all) {
      if (p.id == id) {
        target = p;
        break;
      }
    }
    if (target == null) {
      // Not a post we know — the reference may be a comment id.
      _tryResolveCommentRef(id);
      return;
    }
    _tabSwitchedFor = latchKey;

    final wanted = target.status == PostStatus.approved
        ? _Tab.feed
        : _Tab.requests;
    final panelTarget = target;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_tab != wanted) setState(() => _tab = wanted);
      // Reactions flash; comments open the thread instead. Ringing the post as
      // well would leave it still lit once the panel is closed.
      if (!widget.openComments) flashHighlightOnce(id);
      if (widget.openComments) {
        showCommentsPanel(
          context,
          ref,
          panelTarget,
          highlightCommentId: _targetCommentId,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final asyncPosts = ref.watch(communityUpdatesProvider);
    final pending = ref.watch(pendingCountProvider);
    final width = MediaQuery.of(context).size.width;
    final pad = width < 600 ? 14.0 : 24.0;

    // Rows exist only once the fetch resolves — flash the deep-link target then.
    final loaded = asyncPosts.valueOrNull;
    if (loaded != null) _flashOnce(loaded);

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
                  const _FlaggedCommentsBanner(),
                  if (_tab == _Tab.feed) ...[
                    _ComposerBar(
                      photoUrl: ref
                          .watch(adminProfileProvider)
                          .valueOrNull
                          ?.photoUrl,
                      onTap: () => showCommunityComposer(context, ref),
                      onBroadcast: () => showBroadcastFlow(context, ref),
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
                        ? _FeedList(
                            posts: all,
                            keyFor: highlightKey,
                            isHighlighted: isHighlighted,
                          )
                        : _RequestsList(
                            posts: all,
                            keyFor: highlightKey,
                            isHighlighted: isHighlighted,
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
}

// ── Flagged comments review banner ───────────────────────────────────────────

/// Only appears when comments are awaiting review; tapping opens the queue.
class _FlaggedCommentsBanner extends ConsumerWidget {
  const _FlaggedCommentsBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count =
        ref.watch(adminFlaggedCommentsProvider).valueOrNull?.length ?? 0;
    if (count == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: AppColors.orange.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AdminUi.controlRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(AdminUi.controlRadius),
          onTap: () => showFlaggedCommentsReview(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AdminUi.controlRadius),
              border: Border.all(
                color: AppColors.orange.withValues(alpha: 0.45),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.flag_rounded,
                  size: 18,
                  color: AppColors.orange,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '$count comment${count == 1 ? '' : 's'} flagged for review',
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFB45309),
                    ),
                  ),
                ),
                const Text(
                  'Review',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryBlue,
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: AppColors.primaryBlue,
                ),
              ],
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
  final VoidCallback onBroadcast;
  final String? photoUrl;
  const _ComposerBar({
    required this.onTap,
    required this.onBroadcast,
    this.photoUrl,
  });

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
          // Broadcast a push notification to every citizen — distinct from a
          // feed post, so it gets its own clearly-labelled action here.
          Tooltip(
            message: 'Broadcast to all citizens',
            child: Material(
              color: AppColors.primaryBlue.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: onBroadcast,
                child: const Padding(
                  padding: EdgeInsets.all(10),
                  child: Icon(
                    Icons.campaign_rounded,
                    color: AppColors.primaryBlue,
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
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

  /// Deep-link plumbing: the page owns the highlight state (via
  /// [DeepLinkHighlightMixin]) and hands down a key + flag per post.
  final GlobalKey Function(String id) keyFor;
  final bool Function(String id) isHighlighted;
  const _FeedList({
    required this.posts,
    required this.keyFor,
    required this.isHighlighted,
  });

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
            key: keyFor(p.id),
            padding: const EdgeInsets.only(bottom: 16),
            child: highlightRing(
              highlighted: isHighlighted(p.id),
              radius: AdminUi.cardRadius,
              accent: AppColors.primaryBlue,
              child: _UpdateCard(post: p),
            ),
          ),
      ],
    );
  }
}

// ── Requests (pending + rejected history) ──────────────────────────────────────

class _RequestsList extends StatelessWidget {
  final List<CommunityUpdate> posts;

  /// Deep-link plumbing — see [_FeedList].
  final GlobalKey Function(String id) keyFor;
  final bool Function(String id) isHighlighted;
  const _RequestsList({
    required this.posts,
    required this.keyFor,
    required this.isHighlighted,
  });

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
              key: keyFor(p.id),
              padding: const EdgeInsets.only(bottom: 14),
              child: highlightRing(
                highlighted: isHighlighted(p.id),
                radius: AdminUi.cardRadius,
                accent: AppColors.primaryBlue,
                child: _PendingCard(post: p),
              ),
            ),
        ],
        if (rejected.isNotEmpty) ...[
          const SizedBox(height: 6),
          _sectionLabel('Rejected', rejected.length),
          const SizedBox(height: 10),
          for (final p in rejected)
            Padding(
              key: keyFor(p.id),
              padding: const EdgeInsets.only(bottom: 14),
              child: highlightRing(
                highlighted: isHighlighted(p.id),
                radius: AdminUi.cardRadius,
                accent: AppColors.primaryBlue,
                child: _UpdateCard(post: p),
              ),
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
                // A temp card can't be edited/pinned/deleted yet (its row isn't
                // saved) — hide the menu until the real post lands.
                if (!post.isOptimistic) _CardMenu(post: post),
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
                if (post.flagged) ...[
                  const SizedBox(height: 10),
                  _FlagBanner(reason: post.flagReason),
                ],
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
                if (post.isOptimistic)
                  _postingPill()
                else if (rejected)
                  _RejectedReapprove(post: post)
                else
                  _statusPill(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _authorMeta() {
    // Official posts read "LGU Aparri with <office>" when tagged to a specific
    // entity; the default "LGU Aparri" tag just shows "LGU Aparri". The tag pill
    // is then redundant, so it's dropped for official posts.
    final tag = post.tag.trim();
    final tagged = post.isOfficial && tag.isNotEmpty && tag != 'LGU Aparri';
    final authorLabel = tagged
        ? '${post.authorName} with $tag'
        : post.authorName;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                authorLabel,
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
            if (!post.isOfficial) ...[
              _TagChip(label: post.tag, color: post.tagColorValue),
              const SizedBox(width: 8),
            ],
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

  /// Shown on the optimistic stand-in card while the real post uploads in the
  /// background — a tiny spinner so the instant card still reads as "in flight".
  Widget _postingPill() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: AppColors.primaryBlue.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(20),
    ),
    child: const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 11,
          height: 11,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.primaryBlue,
          ),
        ),
        SizedBox(width: 6),
        Text(
          'Posting…',
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
        // Re-approving moves this rejected card to the feed, unmounting it —
        // capture the root overlay first so the toast still shows.
        final overlay = Overlay.of(context, rootOverlay: true);
        try {
          await ref.read(communityUpdatesProvider.notifier).approve(post.id);
          _toast(null, 'Approved and published.', overlay: overlay);
        } catch (e) {
          _toast(null, 'Could not approve: $e', error: true, overlay: overlay);
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
            try {
              await notifier.togglePin(post);
              if (context.mounted) {
                _toast(context, post.pinned ? 'Unpinned.' : 'Pinned to top.');
              }
            } catch (e) {
              if (context.mounted) {
                _toast(context, 'Could not update: $e', error: true);
              }
            }
            break;
          case 'delete':
            // Deleting removes this card — and this context — from the tree,
            // so `context.mounted` is false by the time the delete resolves and
            // the success toast was silently skipped. Capture the root overlay
            // up front and toast into it directly.
            final overlay = Overlay.of(context, rootOverlay: true);
            final ok = await _confirmDelete(context);
            if (ok == true) {
              try {
                await notifier.delete(post);
                _toast(null, 'Post deleted.', overlay: overlay);
              } catch (e) {
                _toast(
                  null,
                  'Could not delete: $e',
                  error: true,
                  overlay: overlay,
                );
              }
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
    // Approving moves the post off the Requests tab, so this card (and its
    // context) unmounts before the write resolves. Capture the root overlay
    // now, while mounted, and toast into it directly — a root-navigator context
    // can't find the overlay (it's the navigator's descendant, not ancestor).
    final overlay = Overlay.of(context, rootOverlay: true);
    setState(() => _busy = true);
    try {
      await ref.read(communityUpdatesProvider.notifier).approve(widget.post.id);
      _toast(null, 'Approved and published.', overlay: overlay);
    } catch (e) {
      _toast(null, 'Could not approve: $e', error: true, overlay: overlay);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    final reason = await _askReason(context);
    if (reason == null || !mounted) return;
    // Rejecting likewise removes this pending card from the tree — capture the
    // root overlay while mounted so the confirmation toast still shows.
    final overlay = Overlay.of(context, rootOverlay: true);
    setState(() => _busy = true);
    try {
      await ref
          .read(communityUpdatesProvider.notifier)
          .reject(widget.post.id, reason);
      _toast(null, 'Post rejected.', overlay: overlay);
    } catch (e) {
      _toast(null, 'Could not reject: $e', error: true, overlay: overlay);
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

/// Amber "possible profanity" banner set by the server moderation trigger.
/// Admins see the real (unmasked) text; this just prompts a review.
class _FlagBanner extends StatelessWidget {
  final String? reason;
  const _FlagBanner({required this.reason});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.orange.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.orange.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.flag_rounded, size: 15, color: AppColors.orange),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              (reason?.isNotEmpty ?? false)
                  ? '$reason — review before publishing'
                  : 'Possible profanity — review before publishing',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFFB45309),
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

void _toast(
  BuildContext? context,
  String msg, {
  bool error = false,
  OverlayState? overlay,
}) {
  showAdminSnackBar(
    context,
    msg,
    type: error ? AdminSnackType.error : AdminSnackType.success,
    overlay: overlay,
  );
}

Future<bool?> _confirmDelete(BuildContext context) {
  return showAppDialog<bool>(
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
          style: TextButton.styleFrom(foregroundColor: AppColors.primaryBlue),
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
  return showAppDialog<String>(
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
          style: TextButton.styleFrom(foregroundColor: AppColors.primaryBlue),
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
    showAppDialog(
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
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              // Live preview of how the post will be attributed:
                              // "LGU Aparri with <office>" when tagged to a
                              // specific entity, else just "LGU Aparri".
                              _category.label == 'LGU Aparri'
                                  ? 'LGU Aparri'
                                  : 'LGU Aparri with ${_category.label}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AdminUi.textPrimary,
                              ),
                            ),
                            const Text(
                              'Official update',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: AdminUi.textMuted,
                              ),
                            ),
                          ],
                        ),
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
                  _label('Tag'),
                  const SizedBox(height: 8),
                  _categorySelector(),
                  const SizedBox(height: 18),
                  _label('Audience'),
                  const SizedBox(height: 8),
                  _audienceSelector(),
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

  // Web/tablet shows this as a floating dialog → X (exit); phones show it
  // full-screen → back chevron, matching the events composer + citizen sub-screens.
  Widget _header() {
    final wide = MediaQuery.of(context).size.width >= 900;
    return Padding(
      padding: EdgeInsets.fromLTRB(wide ? 18 : 12, 12, 8, 12),
      child: Row(
        children: [
          if (!wide) ...[
            AdminDialogBack(onTap: () => Navigator.of(context).pop()),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Text(
              _isEdit ? 'Edit update' : 'Create update',
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AdminUi.textPrimary,
              ),
            ),
          ),
          if (wide)
            IconButton(
              icon: const Icon(Icons.close_rounded, color: AdminUi.textMuted),
              onPressed: () => Navigator.of(context).pop(),
            ),
        ],
      ),
    );
  }

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

  /// The selected category, shown as a tappable field (color dot + label) that
  /// opens the searchable entity picker. Replaces the flat chip Wrap — 13
  /// entities are too many for chips.
  Widget _categorySelector() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _openCategoryPicker,
        borderRadius: BorderRadius.circular(AdminUi.controlRadius),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
          decoration: BoxDecoration(
            color: AdminUi.subtle,
            borderRadius: BorderRadius.circular(AdminUi.controlRadius),
            border: Border.all(color: AdminUi.border),
          ),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: _category.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _category.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AdminUi.textPrimary,
                  ),
                ),
              ),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: AdminUi.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openCategoryPicker() async {
    final picked = await _pickCategory();
    if (picked != null && mounted) setState(() => _category = picked);
  }

  // Non-async so `context` is used synchronously (no async-gap lint). Dialog on
  // web, slide-up sheet on phones — matching the composer itself.
  Future<UpdateCategory?> _pickCategory() {
    final wide = MediaQuery.of(context).size.width >= 900;
    if (wide) {
      return showAppDialog<UpdateCategory>(
        context: context,
        builder: (_) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460, maxHeight: 560),
            child: _CategoryPicker(current: _category),
          ),
        ),
      );
    }
    return showModalBottomSheet<UpdateCategory>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: _CategoryPicker(current: _category),
      ),
    );
  }

  String get _barangayLabel =>
      _barangay.isEmpty ? 'All barangays (city-wide)' : _barangay;

  /// Audience field — a tappable selector opening the same slide-up/dialog
  /// searchable picker as the Tag field, so both are consistent (no native
  /// dropdown menu).
  Widget _audienceSelector() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _openBarangayPicker,
        borderRadius: BorderRadius.circular(AdminUi.controlRadius),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
          decoration: BoxDecoration(
            color: AdminUi.subtle,
            borderRadius: BorderRadius.circular(AdminUi.controlRadius),
            border: Border.all(color: AdminUi.border),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.groups_rounded,
                size: 18,
                color: AdminUi.textMuted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _barangayLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AdminUi.textPrimary,
                  ),
                ),
              ),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: AdminUi.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openBarangayPicker() async {
    final picked = await _pickBarangay();
    if (picked != null && mounted) setState(() => _barangay = picked);
  }

  Future<String?> _pickBarangay() {
    final wide = MediaQuery.of(context).size.width >= 900;
    if (wide) {
      return showAppDialog<String>(
        context: context,
        builder: (_) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460, maxHeight: 560),
            child: _BarangayPicker(current: _barangay),
          ),
        ),
      );
    }
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: _BarangayPicker(current: _barangay),
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
          onPressed: _submit,
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
          child: Row(
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

    final notifier = ref.read(communityUpdatesProvider.notifier);
    // The composer is about to close, so its own context won't survive to show
    // the background success/failure toast — use the root navigator's context,
    // which outlives this dialog/page.
    final rootContext = Navigator.of(context, rootNavigator: true).context;

    // Kick off the write (the notifier updates the feed optimistically the
    // instant it's called) and close immediately — the post already shows.
    final Future<void> op;
    if (_isEdit) {
      final kept = _images.where((i) => !i.isNew).length;
      final added = _images.where((i) => i.isNew).map((i) => i.file!).toList();
      op = notifier.updatePost(
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
      op = notifier.createPost(
        title: title,
        body: body,
        barangay: _barangay,
        category: _category,
        images: files,
        optimistic: _buildOptimisticPost(title, body),
      );
    }

    unawaited(
      _reportSave(
        op,
        rootContext,
        _isEdit ? 'Update saved.' : 'Update published.',
      ),
    );
    Navigator.of(context).pop();
  }

  /// The stand-in card shown in the feed the moment the admin hits post, before
  /// the row + images finish uploading. It carries a `temp_` id so the notifier
  /// can swap it for the real post once the reload lands. Photos are omitted —
  /// they appear when the background upload completes and the feed reloads.
  CommunityUpdate _buildOptimisticPost(String title, String body) {
    return CommunityUpdate(
      id: 'temp_${DateTime.now().microsecondsSinceEpoch}',
      authorId: '',
      authorName: 'LGU Aparri',
      authorPhotoUrl: ref.read(adminProfileProvider).valueOrNull?.photoUrl,
      authorRole: 'admin',
      title: title,
      body: body,
      barangay: _barangay,
      tag: _category.label,
      tagColor: _category.hex,
      status: PostStatus.approved,
      rejectedReason: null,
      pinned: false,
      likesCount: 0,
      commentsCount: 0,
      createdAt: DateTime.now(),
      images: const [],
    );
  }
}

/// Awaits a background post save and toasts the outcome on a context that
/// outlives the (already-closed) composer. Top-level so it never touches the
/// disposed composer State.
Future<void> _reportSave(
  Future<void> op,
  BuildContext ctx,
  String successMsg,
) async {
  try {
    await op;
    if (ctx.mounted) _toast(ctx, successMsg);
  } catch (e) {
    if (ctx.mounted) _toast(ctx, 'Could not save: $e', error: true);
  }
}

/// Renders a freshly-picked (not-yet-uploaded) image from its bytes.
// ── Searchable entity picker for the composer's Category field ────────────────
// A bottom sheet on phones, a centred card on web (matches the composer). Lists
// the 13 offices/agencies with their colour dot; typing filters by label.
class _CategoryPicker extends StatefulWidget {
  final UpdateCategory current;
  const _CategoryPicker({required this.current});
  @override
  State<_CategoryPicker> createState() => _CategoryPickerState();
}

class _CategoryPickerState extends State<_CategoryPicker> {
  final TextEditingController _search = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final narrow = size.width < 900;
    final q = _q.trim().toLowerCase();
    final items = q.isEmpty
        ? UpdateCategory.all
        : UpdateCategory.all
              .where((c) => c.label.toLowerCase().contains(q))
              .toList();

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (narrow)
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 2),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AdminUi.borderStrong,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 10, 10),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Select entity',
                  style: TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w700,
                    color: AdminUi.textPrimary,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: AdminUi.textMuted),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
          child: TextField(
            controller: _search,
            autofocus: !narrow,
            onChanged: (v) => setState(() => _q = v),
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search offices and agencies…',
              hintStyle: const TextStyle(
                fontSize: 13.5,
                color: AdminUi.textMuted,
              ),
              prefixIcon: const Icon(
                Icons.search_rounded,
                size: 18,
                color: AdminUi.textMuted,
              ),
              filled: true,
              fillColor: AdminUi.subtle,
              contentPadding: const EdgeInsets.symmetric(vertical: 11),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AdminUi.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AdminUi.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(
                  color: AppColors.primaryBlue,
                  width: 1.4,
                ),
              ),
            ),
          ),
        ),
        const Divider(height: 1, color: AdminUi.border),
        Flexible(
          child: items.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Text(
                    'No matches',
                    style: TextStyle(color: AdminUi.textMuted, fontSize: 13),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  shrinkWrap: true,
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const Divider(
                    height: 1,
                    color: AdminUi.subtle,
                    indent: 44,
                  ),
                  itemBuilder: (_, i) {
                    final c = items[i];
                    final selected = c.label == widget.current.label;
                    return InkWell(
                      onTap: () => Navigator.of(context).pop(c),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 13,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 11,
                              height: 11,
                              decoration: BoxDecoration(
                                color: c.color,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                c.label,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: selected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: selected
                                      ? c.color
                                      : AdminUi.textPrimary,
                                ),
                              ),
                            ),
                            if (selected)
                              Icon(
                                Icons.check_rounded,
                                size: 18,
                                color: c.color,
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );

    return Material(
      color: AdminUi.surface,
      borderRadius: narrow
          ? const BorderRadius.vertical(top: Radius.circular(22))
          : BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: narrow
          ? SafeArea(
              top: false,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: size.height * 0.8),
                child: content,
              ),
            )
          : content,
    );
  }
}

// ── Searchable barangay/audience picker (matches the Tag picker) ─────────────
class _BarangayPicker extends StatefulWidget {
  final String current;
  const _BarangayPicker({required this.current});
  @override
  State<_BarangayPicker> createState() => _BarangayPickerState();
}

class _BarangayPickerState extends State<_BarangayPicker> {
  final TextEditingController _search = TextEditingController();
  String _q = '';

  // (label, value) — "All barangays" first, then the barangay options.
  static const _all = <(String, String)>[
    ('All barangays (city-wide)', kAllBarangays),
  ];
  List<(String, String)> get _options => [
    ..._all,
    for (final b in kBarangayOptions) (b, b),
  ];

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final narrow = size.width < 900;
    final q = _q.trim().toLowerCase();
    final items = q.isEmpty
        ? _options
        : _options.where((o) => o.$1.toLowerCase().contains(q)).toList();

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (narrow)
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 2),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AdminUi.borderStrong,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 10, 10),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Select audience',
                  style: TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w700,
                    color: AdminUi.textPrimary,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: AdminUi.textMuted),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
          child: TextField(
            controller: _search,
            autofocus: !narrow,
            onChanged: (v) => setState(() => _q = v),
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search barangay…',
              hintStyle: const TextStyle(
                fontSize: 13.5,
                color: AdminUi.textMuted,
              ),
              prefixIcon: const Icon(
                Icons.search_rounded,
                size: 18,
                color: AdminUi.textMuted,
              ),
              filled: true,
              fillColor: AdminUi.subtle,
              contentPadding: const EdgeInsets.symmetric(vertical: 11),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AdminUi.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AdminUi.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(
                  color: AppColors.primaryBlue,
                  width: 1.4,
                ),
              ),
            ),
          ),
        ),
        const Divider(height: 1, color: AdminUi.border),
        Flexible(
          child: items.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Text(
                    'No matches',
                    style: TextStyle(color: AdminUi.textMuted, fontSize: 13),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  shrinkWrap: true,
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const Divider(
                    height: 1,
                    color: AdminUi.subtle,
                    indent: 16,
                  ),
                  itemBuilder: (_, i) {
                    final (label, value) = items[i];
                    final selected = value == widget.current;
                    return InkWell(
                      onTap: () => Navigator.of(context).pop(value),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 13,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                label,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: selected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: selected
                                      ? AppColors.primaryBlue
                                      : AdminUi.textPrimary,
                                ),
                              ),
                            ),
                            if (selected)
                              const Icon(
                                Icons.check_rounded,
                                size: 18,
                                color: AppColors.primaryBlue,
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );

    return Material(
      color: AdminUi.surface,
      borderRadius: narrow
          ? const BorderRadius.vertical(top: Radius.circular(22))
          : BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: narrow
          ? SafeArea(
              top: false,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: size.height * 0.8),
                child: content,
              ),
            )
          : content,
    );
  }
}

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
  CommunityUpdate post, {
  String? highlightCommentId,
}) {
  final size = MediaQuery.of(context).size;
  final wide = size.width >= kCommentsDialogBreakpoint;
  if (wide) {
    showAppDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.symmetric(
          horizontal: 24,
          // Short viewports claw back the vertical inset: on a 390dp-tall
          // landscape phone, 24 top and bottom is an eighth of the screen.
          vertical: size.height < 560 ? 10.0 : 24.0,
        ),
        child: ConstrainedBox(
          // Clamped to the viewport — a fixed 720 inside a 24px inset needs a
          // 768px-tall display just to draw, and clipped the composer on the
          // 1366x768 laptops this console runs on. The cap widens when the
          // panel splits into two columns.
          constraints: BoxConstraints(
            maxWidth: size.width - 48 < commentsDialogMaxWidth(size)
                ? size.width - 48
                : commentsDialogMaxWidth(size),
            maxHeight: size.height < 560
                ? size.height - 20
                : (size.height - 48 < 720 ? size.height - 48 : 720),
          ),
          child: _CommentsPanel(
            post: post,
            highlightCommentId: highlightCommentId,
            asDialog: true,
          ),
        ),
      ),
    );
  } else {
    // Phone: a rounded bottom sheet, matching the staff console and the citizen
    // feed. This used to push a full-screen route, which read as leaving the
    // Community page rather than opening a thread on top of it — the one place
    // the three surfaces disagreed on mobile.
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (ctx) => Padding(
        // No Scaffold here to resize for us, so the sheet yields to the keyboard
        // itself — otherwise the composer sits underneath it.
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: FractionallySizedBox(
          heightFactor: 0.92,
          child: Container(
            decoration: const BoxDecoration(
              color: AdminUi.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            clipBehavior: Clip.antiAlias,
            child: SafeArea(
              top: false,
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 6),
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD1D5DB),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Expanded(
                    child: _CommentsPanel(
                      post: post,
                      highlightCommentId: highlightCommentId,
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
}

/// Adapts a [CommunityUpdate] onto the normalized post-map shape that
/// [CommentPostRecap] reads, so the admin console renders the exact same recap
/// as the citizen feed and staff console instead of a fourth lookalike.
///
/// Every key it needs already exists on the model; the three that don't apply
/// here are stubbed. `authorDept` is empty because admin resolves the office
/// into the tag, and `blankAvatar` is false because a console is never in the
/// guest view that anonymises citizen authors.
Map<String, dynamic> _recapMap(CommunityUpdate p) => {
  'author': p.authorName,
  'authorDept': '',
  'authorPhotoUrl': p.authorPhotoUrl,
  'authorPhotoPath': null,
  'blankAvatar': false,
  'isOfficial': p.isOfficial,
  'tag': p.tag,
  'tagColor': p.tagColorValue,
  'barangay': p.barangayLabel,
  'timestamp': p.createdAt,
  'title': p.title,
  'body': p.body,
  'imageCount': p.images.length,
  'imageUrls': p.imageUrls,
  // The recap expects the citizen provider's pre-formatted String here.
  'likes': '${p.likesCount}',
  'commentCount': p.commentsCount,
};

class _CommentsPanel extends ConsumerStatefulWidget {
  final CommunityUpdate post;

  /// Comment/reply to scroll to and flash blue when opened from a notification.
  final String? highlightCommentId;

  /// Wide-screen dialog rather than the phone bottom sheet. Set from the same
  /// breakpoint [showCommentsPanel] already tests. Only the dialog shows the
  /// post recap and the post-titled header — see [CommentPostRecap].
  final bool asDialog;

  const _CommentsPanel({
    required this.post,
    this.highlightCommentId,
    this.asDialog = false,
  });
  @override
  ConsumerState<_CommentsPanel> createState() => _CommentsPanelState();
}

class _CommentsPanelState extends ConsumerState<_CommentsPanel> {
  final TextEditingController _input = TextEditingController();

  // Locally-held comment list. Every action (add / reply / edit / delete /
  // react) mutates this in place so the panel reflects INSTANTLY — no
  // FutureBuilder re-fetch skeleton, and the feed behind never reloads. The
  // first load and the post-write reconcile both happen silently.
  List<CommunityComment>? _comments; // null until the first load resolves
  Object? _loadError;

  String? _replyToId;
  String? _replyToName;

  // Notification deep-link: flash the target comment blue, once, after load.
  final GlobalKey _highlightKey = GlobalKey();
  bool _highlightFlash = false;
  bool _highlightConsumed = false;

  CommunityUpdatesRepository get _repo =>
      ref.read(communityUpdatesRepoProvider);
  CommunityUpdatesNotifier get _feed =>
      ref.read(communityUpdatesProvider.notifier);

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _maybeFlashTarget() {
    final target = widget.highlightCommentId;
    if (target == null || _highlightConsumed) return;
    final all = _comments;
    if (all == null || !all.any((c) => c.id == target)) return;
    _highlightConsumed = true;
    setState(() => _highlightFlash = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _highlightKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
          alignment: 0.2,
        );
      }
      Future.delayed(const Duration(milliseconds: 2600), () {
        if (mounted) setState(() => _highlightFlash = false);
      });
    });
  }

  /// Wraps [tile] in the blue deep-link wash when it is the notification's
  /// target comment.
  Widget _withHighlight(CommunityComment c, Widget tile) {
    if (c.id != widget.highlightCommentId) return tile;
    return AnimatedContainer(
      key: _highlightKey,
      duration: const Duration(milliseconds: 450),
      decoration: BoxDecoration(
        color: _highlightFlash
            ? AppColors.primaryBlue.withValues(alpha: 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: tile,
    );
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await _repo.fetchComments(widget.post.id);
      if (mounted) {
        setState(() {
          _comments = list;
          _loadError = null;
        });
        _maybeFlashTarget();
      }
    } catch (e) {
      if (mounted) setState(() => _loadError = e);
    }
  }

  /// Refetch and replace the list WITHOUT dropping back to the skeleton, so a
  /// post-write reconcile (e.g. swapping a temp comment for the real row) never
  /// flashes the panel. A failure just keeps the optimistic list.
  Future<void> _silentSync() async {
    try {
      final list = await _repo.fetchComments(widget.post.id);
      if (mounted) setState(() => _comments = list);
    } catch (_) {
      /* keep what's on screen */
    }
  }

  void _startReply(String topLevelId, String name) {
    setState(() {
      _replyToId = topLevelId;
      _replyToName = name;
    });
  }

  /// True when the panel lays the post out beside the thread instead of above
  /// it — wide-but-short viewports. Mirrors the citizen/staff sheet exactly.
  bool get _split =>
      widget.asDialog && commentsUseSplitLayout(MediaQuery.of(context).size);

  @override
  Widget build(BuildContext context) {
    final body = _split
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The post scrolls independently, so a long body or a tall photo
              // can never push the thread out of reach on a short screen.
              Expanded(
                flex: 5,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: CommentPostRecap(
                    post: _recapMap(widget.post),
                    width: kThreadMetrics,
                  ),
                ),
              ),
              const VerticalDivider(width: 1, color: AdminUi.border),
              Expanded(
                flex: 6,
                child: Column(
                  children: [
                    Expanded(child: _buildList()),
                    const Divider(height: 1, color: AdminUi.border),
                    _composer(),
                  ],
                ),
              ),
            ],
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: _buildList()),
              const Divider(height: 1, color: AdminUi.border),
              _composer(),
            ],
          );

    return Material(
      color: AdminUi.surface,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _header(),
          const Divider(height: 1, color: AdminUi.border),
          _split ? Expanded(child: body) : Flexible(child: body),
        ],
      ),
    );
  }

  Widget _buildList() {
    // Stacked dialog only. The recap rides INSIDE the scroll view rather than
    // above it so a long post scrolls away instead of permanently eating the
    // thread's height — and it shows in every state, because "no comments yet"
    // on a post you can no longer see is the least useful screen in the
    // console. When split, the post already has its own column.
    final recap = widget.asDialog && !_split
        ? CommentPostRecap(post: _recapMap(widget.post), width: kThreadMetrics)
        : null;

    /// Wraps a non-scrolling load/empty/error state so it can sit under the
    /// recap. Without a recap the state is returned exactly as it was before.
    Widget withRecap(Widget state) => recap == null
        ? state
        : ListView(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            children: [recap, state],
          );

    if (_loadError != null) {
      return withRecap(
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Could not load comments: $_loadError',
            style: const TextStyle(color: AdminUi.textMuted),
          ),
        ),
      );
    }
    final all = _comments;
    if (all == null) {
      return withRecap(
        const AdminShimmer(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Column(
              children: [
                _CommentSkeletonRow(),
                _CommentSkeletonRow(),
                _CommentSkeletonRow(),
                _CommentSkeletonRow(),
              ],
            ),
          ),
        ),
      );
    }
    if (all.isEmpty) {
      return withRecap(
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 48, horizontal: 24),
          child: Center(
            child: Text(
              'No comments yet.',
              style: TextStyle(color: AdminUi.textMuted),
            ),
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      children: [
        ?recap,
        for (final c in tops) ...[
          _withHighlight(
            c,
            _CommentTile(
              comment: c,
              onDelete: () => _delete(c),
              onReply: () => _startReply(c.id, c.authorName),
              onReact: () => _react(c),
              onEdit: c.isOfficial ? () => _edit(c) : null,
            ),
          ),
          for (final r in (repliesByParent[c.id] ?? const []))
            Padding(
              padding: const EdgeInsets.only(left: 40),
              child: _withHighlight(
                r,
                _CommentTile(
                  comment: r,
                  onDelete: () => _delete(r),
                  // Replies always attach to the top-level parent.
                  onReply: () => _startReply(c.id, r.authorName),
                  onReact: () => _react(r),
                  onEdit: r.isOfficial ? () => _edit(r) : null,
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _header() => Padding(
    padding: const EdgeInsets.fromLTRB(18, 14, 10, 14),
    child: Row(
      children: [
        // Dialog: names the post, centred, since the modal covers the feed.
        // Bottom sheet: the plain label — the post is right behind it.
        if (widget.asDialog)
          Expanded(
            // Left pad balances the close button so the title lands optically
            // centred rather than centred-then-shoved-left.
            child: Padding(
              padding: const EdgeInsets.only(left: 38),
              child: Text(
                "${widget.post.authorName}'s Post",
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AdminUi.textPrimary,
                ),
              ),
            ),
          )
        else ...[
          const Text(
            'Comments',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AdminUi.textPrimary,
            ),
          ),
          const Spacer(),
        ],
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
                  // Enter sends; Shift+Enter inserts a newline.
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
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
                  onTap: _send,
                  child: const Padding(
                    padding: EdgeInsets.all(11),
                    child: Icon(
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

  /// Post a comment/reply. The comment appears in the list and the card's
  /// count ticks up the instant Send is tapped; the write + reconcile happen in
  /// the background, and a failure pulls the optimistic comment back out.
  Future<void> _send() async {
    final text = _input.text.trim();
    final current = _comments;
    if (text.isEmpty || current == null) return;

    final parentId = _replyToId;
    final temp = CommunityComment(
      id: 'temp_${DateTime.now().microsecondsSinceEpoch}',
      authorId: '',
      authorName: 'LGU Aparri',
      authorPhotoUrl: ref.read(adminProfileProvider).valueOrNull?.photoUrl,
      authorRole: 'admin',
      body: text,
      parentId: parentId,
      likesCount: 0,
      likedByMe: false,
      createdAt: DateTime.now(),
    );

    setState(() {
      _comments = [...current, temp];
      _input.clear();
      _replyToId = null;
      _replyToName = null;
    });
    _feed.bumpCommentCount(widget.post.id, 1);

    try {
      await _repo.addComment(widget.post.id, text, parentId: parentId);
      await _silentSync(); // swap the temp comment for the real row
    } catch (e) {
      if (mounted) {
        setState(
          () => _comments = _comments?.where((c) => c.id != temp.id).toList(),
        );
      }
      _feed.bumpCommentCount(widget.post.id, -1);
      if (mounted) _toast(context, 'Could not post comment: $e', error: true);
    }
  }

  Future<void> _delete(CommunityComment c) async {
    if (c.isOptimistic) return; // still saving; ignore
    final ok = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete comment?'),
        content: const Text('This removes the comment for everyone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(foregroundColor: AppColors.primaryBlue),
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
    final current = _comments;
    if (ok != true || current == null) return;

    // Remove instantly (and hide any replies whose parent just vanished).
    setState(() {
      _comments = current.where((x) => x.id != c.id).toList();
    });
    _feed.bumpCommentCount(widget.post.id, -1);

    try {
      await _repo.deleteComment(c.id);
      if (mounted) _toast(context, 'Comment deleted.');
    } catch (e) {
      if (mounted) setState(() => _comments = current);
      _feed.bumpCommentCount(widget.post.id, 1);
      if (mounted) _toast(context, 'Could not delete: $e', error: true);
    }
  }

  /// Edit one of the LGU's own comments — the new text shows immediately.
  Future<void> _edit(CommunityComment c) async {
    if (c.isOptimistic) return; // not saved yet
    final current = _comments;
    if (current == null) return;
    final text = await _askEditComment(context, c.body);
    final newBody = text?.trim() ?? '';
    if (newBody.isEmpty || newBody == c.body) return;

    setState(() {
      _comments = [
        for (final x in current)
          if (x.id == c.id) x.copyWith(body: newBody) else x,
      ];
    });

    try {
      await _repo.editComment(c.id, newBody);
      if (mounted) _toast(context, 'Comment updated.');
    } catch (e) {
      if (mounted) setState(() => _comments = current);
      if (mounted) _toast(context, 'Could not edit: $e', error: true);
    }
  }

  /// Like / unlike a comment — the heart + count flip on the spot.
  Future<void> _react(CommunityComment c) async {
    if (c.isOptimistic) return; // can't like an unsaved comment
    final current = _comments;
    if (current == null) return;
    final nowLiked = !c.likedByMe;

    setState(() {
      _comments = [
        for (final x in current)
          if (x.id == c.id)
            x.copyWith(
              likedByMe: nowLiked,
              likesCount: (x.likesCount + (nowLiked ? 1 : -1)).clamp(
                0,
                1 << 31,
              ),
            )
          else
            x,
      ];
    });

    try {
      await _repo.setCommentLike(c.id, nowLiked);
    } catch (e) {
      if (mounted) setState(() => _comments = current);
      if (mounted) _toast(context, 'Could not react: $e', error: true);
    }
  }
}

/// Prompt to edit a comment's text, prefilled with [initial]. Returns the new
/// text, or null if cancelled.
Future<String?> _askEditComment(BuildContext context, String initial) {
  final ctrl = TextEditingController(text: initial);
  return showAppDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Edit comment'),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        maxLines: 4,
        minLines: 1,
        decoration: InputDecoration(
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
          style: FilledButton.styleFrom(backgroundColor: AppColors.primaryBlue),
          child: const Text('Save'),
        ),
      ],
    ),
  );
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
  final VoidCallback onReact;

  /// Null when the comment isn't the LGU's own (only official comments are
  /// editable); otherwise opens the edit prompt.
  final VoidCallback? onEdit;
  const _CommentTile({
    required this.comment,
    required this.onDelete,
    required this.onReply,
    required this.onReact,
    this.onEdit,
  });

  Widget _textAction(
    String label,
    VoidCallback onTap, {
    Color color = AdminUi.textMuted,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Widget _likeAction() {
    final liked = comment.likedByMe;
    final color = liked ? AppColors.red : AdminUi.textMuted;
    return GestureDetector(
      onTap: onReact,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            size: 14,
            color: color,
          ),
          if (comment.likesCount > 0) ...[
            const SizedBox(width: 4),
            Text(
              '${comment.likesCount}',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ],
      ),
    );
  }

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
                  child: Wrap(
                    spacing: 14,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (comment.createdAt != null)
                        Text(
                          formatTimeAgo(comment.createdAt!),
                          style: const TextStyle(
                            fontSize: 11,
                            color: AdminUi.textMuted,
                          ),
                        ),
                      _likeAction(),
                      _textAction('Reply', onReply),
                      if (onEdit != null) _textAction('Edit', onEdit!),
                      _textAction('Delete', onDelete, color: AppColors.red),
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
