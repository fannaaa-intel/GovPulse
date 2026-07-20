import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/community_posts_provider.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/deeplink_highlight.dart';
import '../../../core/widgets/modal/media_picker_sheet.dart';
import '../../../core/widgets/Home/Newsfeed/comments_sheet.dart';
import '../../../core/identity/official_display_name.dart';
import '../../../core/widgets/Home/Newsfeed/image_grid.dart';
import '../../../core/widgets/Home/Newsfeed/news_feed_helpers.dart'
    show buildAuthorAvatar, formatTimeAgo;
import '../../admin/providers/community_updates_provider.dart'
    show UpdateCategory, kBarangayOptions;
import '../data/staff_repository.dart';
import '../providers/staff_providers.dart';
import '../theme/staff_ui.dart';
import '../widgets/staff_common.dart';
import '../../../core/widgets/app_dialog.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Community — staff compose updates that are QUEUED for admin approval before
//  they reach the citizen feed (they never publish directly).
// ════════════════════════════════════════════════════════════════════════════

class StaffCommunityPage extends ConsumerStatefulWidget {
  /// A post (or comment) id to land on, when arriving from a notification.
  /// Null for a normal open.
  final String? highlightId;

  /// Which tab to open on: 'feed' (Community updates) or 'submissions'.
  /// Notifications pick the tab that owns their target; a plain nav tap opens
  /// the feed, mirroring the admin console.
  final String? initialTab;

  /// True when the notification was about a comment/reply — the feed opens the
  /// post's comment thread and flashes the target comment blue.
  final bool openComments;

  /// Identifies the deep-link TAP, not the target. Bumped by the console on
  /// every notification tap so two taps on the same post are two distinct
  /// events — comparing highlightId/openComments alone can't tell them apart.
  final int deepLinkNonce;

  const StaffCommunityPage({
    super.key,
    this.highlightId,
    this.initialTab,
    this.openComments = false,
    this.deepLinkNonce = 0,
  });

  @override
  ConsumerState<StaffCommunityPage> createState() => _StaffCommunityPageState();
}

class _StaffCommunityPageState extends ConsumerState<StaffCommunityPage>
    with DeepLinkHighlightMixin {
  // 0 = Community updates (published feed) · 1 = My submissions. Notifications
  // pick the tab that owns their target; a plain nav tap opens the feed —
  // unless a highlight was passed with no tab (legacy), which is a submission.
  late int _tab = widget.initialTab == 'submissions'
      ? 1
      : widget.initialTab == 'feed'
      ? 0
      : (widget.highlightId != null ? 1 : 0);

  @override
  void didUpdateWidget(covariant StaffCommunityPage old) {
    super.didUpdateWidget(old);
    // A notification arriving while this page is ALREADY mounted delivers its
    // target through a widget update, not initState — so honour the requested
    // tab here too, otherwise a heart/comment tap lands on whichever tab the
    // staff last left open and the flash has nothing to show. Trigger on a new
    // highlight target as well, so a second notification onto the SAME tab
    // (whose initialTab value is unchanged) still snaps the tab back if the
    // staff had navigated away in the meantime.
    final want = widget.initialTab;
    final newTap =
        widget.highlightId != null && widget.deepLinkNonce != old.deepLinkNonce;
    if (want != null && (want != old.initialTab || newTap)) {
      final next = want == 'submissions' ? 1 : 0;
      if (next != _tab) setState(() => _tab = next);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(staffCommunityProvider);

    // Rows exist only once the fetch resolves — flash the deep-link target then.
    if (_tab == 1 && async.hasValue) flashHighlightOnce(widget.highlightId);

    return Stack(
      children: [
        StaffPageBody(
          // 720, not the 1080 default the other staff sections use: this screen
          // is a feed, and admin's Community caps at 720 for the same reason —
          // full-bleed cards on a desktop pane blow the images and type up out
          // of proportion. Inert below 720, so phones are unaffected.
          maxWidth: 720,
          onRefresh: () async {
            if (_tab == 0) {
              await CommunityPostsProvider.instance.refresh();
            } else {
              await ref.read(staffCommunityProvider.notifier).refresh();
            }
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TabSwitcher(
                index: _tab,
                pendingCount:
                    async.valueOrNull?.where((p) => p.isPending).length ?? 0,
                onChanged: (i) => setState(() => _tab = i),
              ),
              const SizedBox(height: 16),
              // Mirrors the admin console's composer bar, which sits above both
              // tabs rather than hiding behind a FAB. The copy says "for review"
              // because staff submit into pending_approval — they never publish
              // straight to the citizen feed the way an admin does.
              _StaffComposerBar(
                photoUrl: ref
                    .watch(staffIdentityProvider)
                    .valueOrNull
                    ?.photoUrl,
                onTap: () => _openComposer(context, ref),
              ),
              const SizedBox(height: 16),
              if (_tab == 0)
                _StaffFeedTab(
                  highlightId: widget.highlightId,
                  openComments: widget.openComments,
                  deepLinkNonce: widget.deepLinkNonce,
                  // Who a comment from this console is posted AS. Puts the
                  // shared sheet into official mode so it matches admin — and
                  // names the OFFICE, not the person, so the composer's "as …"
                  // matches the byline the comment will actually carry.
                  officialName: officialDisplayName(
                    role: 'staff',
                    department: ref
                        .watch(staffIdentityProvider)
                        .valueOrNull
                        ?.department,
                  ),
                ),
              if (_tab == 1) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: StaffUi.accentWash,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: StaffUi.accent.withValues(alpha: 0.25),
                    ),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 18,
                        color: StaffUi.accent,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Posts you submit are reviewed by an LGU admin before they '
                          'appear on the citizen feed.',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: StaffUi.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'My submissions',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: StaffUi.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                async.when(
                  loading: () => const _SubmissionsSkeleton(),
                  error: (e, _) => Padding(
                    padding: const EdgeInsets.only(top: 30),
                    child: StaffErrorState(
                      message: "Couldn't load your submissions.",
                      onRetry: () =>
                          ref.read(staffCommunityProvider.notifier).refresh(),
                    ),
                  ),
                  data: (items) {
                    if (items.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.only(top: 30),
                        child: StaffEmptyState(
                          icon: Icons.campaign_outlined,
                          title: 'No submissions yet',
                          subtitle:
                              'Tap "New update" to submit one for approval.',
                        ),
                      );
                    }
                    final pending = items.where((p) => p.isPending).length;
                    final approved = items.where((p) => p.isApproved).length;
                    final rejected = items.where((p) => p.isRejected).length;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // KPI summary — same tile language as the staff
                        // dashboard. Always 3-across (no orphan tile on its own
                        // row); tiles compact themselves on narrow phones.
                        LayoutBuilder(
                          builder: (context, c) {
                            final compact = c.maxWidth < 520;
                            final tiles = <Widget>[
                              _KpiTile(
                                icon: Icons.hourglass_top_rounded,
                                label: 'Pending',
                                count: pending,
                                color: StaffUi.warn,
                                compact: compact,
                              ),
                              _KpiTile(
                                icon: Icons.check_circle_rounded,
                                label: 'Approved',
                                count: approved,
                                color: StaffUi.online,
                                compact: compact,
                              ),
                              _KpiTile(
                                icon: Icons.cancel_rounded,
                                label: 'Rejected',
                                count: rejected,
                                color: StaffUi.danger,
                                compact: compact,
                              ),
                            ];
                            return _kpiGrid(tiles, 3);
                          },
                        ),
                        const SizedBox(height: 14),
                        for (final p in items)
                          Padding(
                            key: highlightKey(p.id),
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _PostRow(
                              post: p,
                              highlighted: isHighlighted(p.id),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  void _openComposer(BuildContext context, WidgetRef ref) {
    final narrow = MediaQuery.of(context).size.width < 600;
    // On submit, jump to "My submissions" so the just-added optimistic card is
    // visible no matter which tab the composer was opened from.
    final sheet = _ComposerSheet(
      onSubmitted: () {
        if (mounted && _tab != 1) setState(() => _tab = 1);
      },
    );
    if (narrow) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: sheet,
        ),
      );
    } else {
      showAppDialog(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.45),
        builder: (_) => Center(
          child: Padding(padding: const EdgeInsets.all(24), child: sheet),
        ),
      );
    }
  }
}

/// A submissions KPI tile — same visual language as the staff dashboard's
/// stat tiles (icon chip, big count, muted label) so the console reads as one
/// system. Content-sized; the grid wraps rows in IntrinsicHeight so tiles in a
/// row match heights without ever bottom-overflowing.
class _KpiTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  final Color color;

  /// Tightens paddings and type so three tiles share a narrow phone row.
  final bool compact;
  const _KpiTile({
    required this.icon,
    required this.label,
    required this.count,
    required this.color,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return StaffCard(
      padding: EdgeInsets.all(compact ? 11 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: EdgeInsets.all(compact ? 6 : 8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: color, size: compact ? 15 : 18),
          ),
          SizedBox(height: compact ? 9 : 14),
          Text(
            '$count',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: compact ? 19 : 24,
              fontWeight: FontWeight.w800,
              color: StaffUi.textPrimary,
            ),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: compact ? 11 : 12.5,
              color: StaffUi.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// Lays [tiles] out [cols]-across in IntrinsicHeight rows (mirrors the staff
/// dashboard grid) so every width — web, app, small screens — gets equal-width,
/// equal-height tiles with no overflow.
Widget _kpiGrid(List<Widget> tiles, int cols) {
  const gap = 12.0;
  final rows = <Widget>[];
  for (var i = 0; i < tiles.length; i += cols) {
    final end = (i + cols) > tiles.length ? tiles.length : i + cols;
    final slice = tiles.sublist(i, end);
    final children = <Widget>[];
    for (var j = 0; j < cols; j++) {
      children.add(
        Expanded(child: j < slice.length ? slice[j] : const SizedBox()),
      );
      if (j < cols - 1) children.add(const SizedBox(width: gap));
    }
    if (rows.isNotEmpty) rows.add(const SizedBox(height: gap));
    rows.add(
      IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
  return Column(children: rows);
}

class _PostRow extends StatelessWidget {
  final StaffCommunityPost post;

  /// Set when this row is the deep-link target: it flashes, then fades back.
  /// Drawn as a ring around StaffCard so the card keeps its own surface.
  final bool highlighted;
  const _PostRow({required this.post, this.highlighted = false});

  @override
  Widget build(BuildContext context) {
    final p = post;
    final (label, color, statusIcon) = p.isOptimistic
        ? ('Posting…', StaffUi.accent, Icons.cloud_upload_rounded)
        : p.isApproved
        ? ('Approved', StaffUi.online, Icons.check_circle_rounded)
        : p.isRejected
        ? ('Rejected', StaffUi.danger, Icons.cancel_rounded)
        : ('Pending review', StaffUi.warn, Icons.hourglass_top_rounded);
    return highlightRing(
      highlighted: highlighted,
      radius: 14,
      accent: StaffUi.accent,
      child: StaffCard(
        padding: EdgeInsets.zero,
        onTap: () => _showPostDetail(context, p),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Status accent bar — readable at a glance while scrolling.
              Container(width: 4, color: color),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              p.title.isEmpty ? '(untitled)' : p.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                                color: StaffUi.textPrimary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          StaffPill(
                            label: label,
                            color: color,
                            icon: statusIcon,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        p.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: StaffUi.textSecondary,
                        ),
                      ),
                      if (p.isOptimistic && p.localImages.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        _LocalThumbStrip(files: p.localImages),
                      ] else if (p.imageUrls.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        _ThumbStrip(urls: p.imageUrls),
                      ],
                      const SizedBox(height: 10),
                      // Audience pills on the left, timestamp pinned bottom-right
                      // and baseline-aligned with the pills' last row — so the
                      // "just now" no longer floats mid-card when the pills wrap
                      // on a narrow phone.
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                StaffPill(label: p.tag, color: StaffUi.accent),
                                StaffPill(
                                  label: p.barangay.isEmpty
                                      ? 'City-wide'
                                      : p.barangay,
                                  color: StaffUi.textMuted,
                                  icon: Icons.location_on_rounded,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Text(
                              staffAgo(p.createdAt),
                              style: const TextStyle(
                                fontSize: 11,
                                color: StaffUi.textMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (p.isRejected &&
                          (p.rejectedReason ?? '').isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: StaffUi.danger.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: StaffUi.danger.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.info_outline_rounded,
                                size: 15,
                                color: StaffUi.danger,
                              ),
                              const SizedBox(width: 7),
                              Expanded(
                                child: Text(
                                  'Reason: ${p.rejectedReason}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    height: 1.35,
                                    color: StaffUi.danger,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
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
}

/// Opens the full detail of a submission — bottom sheet on phones, centered
/// frosted dialog on web/desktop, the same split the composer makes.
void _showPostDetail(BuildContext context, StaffCommunityPost post) {
  final narrow = MediaQuery.of(context).size.width < 600;
  final sheet = _PostDetailSheet(post: post);
  if (narrow) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => sheet,
    );
  } else {
    showAppDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (_) => Center(
        child: Padding(padding: const EdgeInsets.all(24), child: sheet),
      ),
    );
  }
}

/// Detail of one submission: status, full text, photos, audience, the
/// rejection reason when there is one, and — while it's still pending — a
/// "Retract submission" action to pull it back out of the review queue.
class _PostDetailSheet extends ConsumerWidget {
  final StaffCommunityPost post;
  const _PostDetailSheet({required this.post});

  Future<void> _retract(BuildContext context, WidgetRef ref) async {
    final overlay = Overlay.of(context, rootOverlay: true);
    final ok = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Retract this submission?'),
        content: const Text(
          'It will be pulled out of the review queue and permanently deleted. '
          'You can submit it again later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(foregroundColor: StaffUi.textSecondary),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: StaffUi.danger),
            child: const Text('Retract'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    // Capture the notifier before popping — `ref` is defunct once this sheet's
    // element is gone. The notifier drops the card optimistically.
    final notifier = ref.read(staffCommunityProvider.notifier);
    Navigator.pop(context);
    try {
      await notifier.retract(post.id);
      showAppSnackBar(
        null,
        'Submission retracted.',
        type: AppSnackType.success,
        overlay: overlay,
      );
    } catch (e) {
      showAppSnackBar(
        null,
        staffFriendlyError(e),
        type: AppSnackType.error,
        overlay: overlay,
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final narrow = MediaQuery.of(context).size.width < 600;
    final p = post;
    final (label, color, statusIcon) = p.isApproved
        ? ('Approved', StaffUi.online, Icons.check_circle_rounded)
        : p.isRejected
        ? ('Rejected', StaffUi.danger, Icons.cancel_rounded)
        : ('Pending review', StaffUi.warn, Icons.hourglass_top_rounded);

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (narrow)
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 4),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: StaffUi.borderStrong,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 8, 6),
          child: Row(
            children: [
              StaffPill(label: label, color: color, icon: statusIcon),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: StaffUi.textMuted),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: StaffUi.border),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.title.isEmpty ? '(untitled)' : p.title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: StaffUi.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    StaffPill(label: p.tag, color: StaffUi.accent),
                    StaffPill(
                      label: p.barangay.isEmpty ? 'City-wide' : p.barangay,
                      color: StaffUi.textMuted,
                      icon: Icons.location_on_rounded,
                    ),
                    Text(
                      'Submitted ${staffAgo(p.createdAt)}',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: StaffUi.textMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  p.body,
                  style: const TextStyle(
                    fontSize: 13.5,
                    height: 1.5,
                    color: StaffUi.textSecondary,
                  ),
                ),
                if (p.imageUrls.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Photos (${p.imageUrls.length})',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: StaffUi.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _ThumbStrip(
                    urls: p.imageUrls,
                    size: 110,
                    onTap: (i) => openImageViewer(
                      context,
                      p.imageUrls.length,
                      i,
                      urls: p.imageUrls,
                    ),
                  ),
                ],
                if (p.isRejected && (p.rejectedReason ?? '').isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: StaffUi.danger.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: StaffUi.danger.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              size: 15,
                              color: StaffUi.danger,
                            ),
                            SizedBox(width: 7),
                            Text(
                              'Rejection reason',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: StaffUi.danger,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          p.rejectedReason!,
                          style: const TextStyle(
                            fontSize: 12.5,
                            height: 1.4,
                            color: StaffUi.danger,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        // While it's still awaiting review the author can pull it back out.
        if (p.isPending && !p.isOptimistic) ...[
          const Divider(height: 1, color: StaffUi.border),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: OutlinedButton.icon(
              onPressed: () => _retract(context, ref),
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: const Text('Retract submission'),
              style: OutlinedButton.styleFrom(
                foregroundColor: StaffUi.danger,
                side: BorderSide(color: StaffUi.danger.withValues(alpha: 0.5)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ],
    );

    return Material(
      color: StaffUi.surface,
      borderRadius: narrow
          ? const BorderRadius.vertical(top: Radius.circular(22))
          : BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: narrow
          ? SafeArea(
              top: false,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.9,
                ),
                child: content,
              ),
            )
          : ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
              child: content,
            ),
    );
  }
}

/// Horizontal strip of photo thumbnails on a submission card. Scrolls sideways
/// on narrow screens instead of squeezing or overflowing. When [onTap] is set,
/// tapping a thumbnail opens the full-screen viewer.
class _ThumbStrip extends StatelessWidget {
  final List<String> urls;
  final double size;
  final void Function(int index)? onTap;
  const _ThumbStrip({required this.urls, this.size = 64, this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: size,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: urls.length,
        separatorBuilder: (_, i) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final thumb = ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              urls[i],
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, e, s) => Container(
                width: size,
                height: size,
                color: StaffUi.subtle,
                child: const Icon(
                  Icons.broken_image_outlined,
                  size: 20,
                  color: StaffUi.textMuted,
                ),
              ),
            ),
          );
          if (onTap == null) return thumb;
          return GestureDetector(
            onTap: () => onTap!(i),
            child: Stack(
              children: [
                thumb,
                Positioned(
                  right: 5,
                  bottom: 5,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(
                      Icons.zoom_out_map_rounded,
                      size: 13,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Horizontal strip of freshly-picked photos on an optimistic submission card,
/// rendered from local bytes (works on web too) so the preview shows instantly
/// — before the upload finishes and the real network thumbnails take over.
class _LocalThumbStrip extends StatelessWidget {
  final List<XFile> files;
  const _LocalThumbStrip({required this.files});

  static const double size = 64;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: size,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: files.length,
        separatorBuilder: (_, i) => const SizedBox(width: 8),
        itemBuilder: (context, i) => ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: FutureBuilder<Uint8List>(
            future: files[i].readAsBytes(),
            builder: (context, snap) => snap.hasData
                ? Image.memory(
                    snap.data!,
                    width: size,
                    height: size,
                    fit: BoxFit.cover,
                  )
                : Container(width: size, height: size, color: StaffUi.subtle),
          ),
        ),
      ),
    );
  }
}

// Placeholder cards shown while the submissions list loads, mirroring
// _PostRow so the layout stays put once real posts arrive.
class _SubmissionsSkeleton extends StatelessWidget {
  const _SubmissionsSkeleton();

  @override
  Widget build(BuildContext context) {
    return const StaffShimmer(
      child: Column(
        children: [
          _SubmissionSkeletonCard(),
          SizedBox(height: 10),
          _SubmissionSkeletonCard(),
          SizedBox(height: 10),
          _SubmissionSkeletonCard(),
        ],
      ),
    );
  }
}

class _SubmissionSkeletonCard extends StatelessWidget {
  const _SubmissionSkeletonCard();

  @override
  Widget build(BuildContext context) {
    return StaffCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Row(
            children: [
              Expanded(child: StaffSkeletonBox(width: 160, height: 14)),
              SizedBox(width: 8),
              StaffSkeletonBox(width: 70, height: 18, radius: 6),
            ],
          ),
          SizedBox(height: 10),
          StaffSkeletonBox(width: double.infinity, height: 11),
          SizedBox(height: 6),
          StaffSkeletonBox(width: double.infinity, height: 11),
          SizedBox(height: 12),
          Row(
            children: [
              StaffSkeletonBox(width: 60, height: 18, radius: 6),
              Spacer(),
              StaffSkeletonBox(width: 48, height: 10),
            ],
          ),
        ],
      ),
    );
  }
}

class _ComposerSheet extends ConsumerStatefulWidget {
  /// Called the instant the submission is fired (the optimistic card is already
  /// in the list) so the page can switch to the "My submissions" tab.
  final VoidCallback? onSubmitted;
  const _ComposerSheet({this.onSubmitted});
  @override
  ConsumerState<_ComposerSheet> createState() => _ComposerSheetState();
}

class _ComposerSheetState extends ConsumerState<_ComposerSheet> {
  static const int _maxImages = 6;
  static const int _maxImageBytes = 10 * 1024 * 1024; // 10 MB, matches admin
  static const Set<String> _imageExts = {
    'jpg', 'jpeg', 'jfif', 'pjpeg', 'pjp', // JPEG family
    'png', 'gif', 'webp', 'heic', 'heif', 'bmp',
  };

  final _title = TextEditingController();
  final _body = TextEditingController();
  final _picker = ImagePicker();
  final List<XFile> _images = [];
  final Map<String, Uint8List> _thumbCache = {};
  UpdateCategory _category = UpdateCategory.all.first;
  String _barangay = ''; // '' == city-wide
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    final remaining = _maxImages - _images.length;
    if (remaining <= 0) return;
    // Narrow (phone) gets the camera/gallery sheet; wide (web/desktop) goes
    // straight to the file picker, same split the admin composer makes.
    final narrow = MediaQuery.of(context).size.width < 600;
    try {
      if (!narrow) {
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
    } catch (_) {
      if (mounted) {
        showAppSnackBar(
          context,
          "Couldn't add that photo. Please try again.",
          type: AppSnackType.error,
        );
      }
    }
  }

  /// Photos only, capped at 10 MB each — tells the user what got skipped
  /// instead of failing the whole pick.
  Future<void> _addValidated(List<XFile> picked) async {
    if (picked.isEmpty) return;
    final remaining = _maxImages - _images.length;
    final accepted = <XFile>[];
    var rejectedType = false, rejectedSize = false;
    for (final f in picked) {
      if (accepted.length >= remaining) break;
      final name = f.name.toLowerCase();
      final dot = name.lastIndexOf('.');
      final ext = dot == -1 ? '' : name.substring(dot + 1);
      if (!_imageExts.contains(ext)) {
        rejectedType = true;
        continue;
      }
      if (await f.length() > _maxImageBytes) {
        rejectedSize = true;
        continue;
      }
      accepted.add(f);
    }
    if (!mounted) return;
    if (accepted.isNotEmpty) setState(() => _images.addAll(accepted));
    if (rejectedType) {
      showAppSnackBar(
        context,
        "Only photos can be added — videos and other files aren't supported.",
        type: AppSnackType.error,
      );
    } else if (rejectedSize) {
      showAppSnackBar(
        context,
        'Some photos were over 10 MB and were skipped.',
        type: AppSnackType.error,
      );
    }
  }

  Future<void> _submit() async {
    final t = _title.text.trim();
    final b = _body.text.trim();
    if (t.isEmpty || b.isEmpty) {
      setState(() => _error = 'A title and message are required.');
      return;
    }
    // The notifier inserts an optimistic stand-in synchronously, so the pending
    // card is already in "My submissions" the moment we close — no waiting on
    // the upload. Capture the root overlay while mounted so the reconcile toasts
    // still show after this sheet closes (a root-navigator context can't find
    // the overlay — it's that navigator's descendant, not an ancestor).
    final overlay = Overlay.of(context, rootOverlay: true);
    final future = ref
        .read(staffCommunityProvider.notifier)
        .submit(
          title: t,
          body: b,
          barangay: _barangay,
          tag: _category.label,
          tagColorHex: _category.hex,
          images: List.of(_images),
        );
    widget.onSubmitted?.call();
    Navigator.pop(context);
    showAppSnackBar(
      null,
      'Submitted for admin approval.',
      type: AppSnackType.success,
      overlay: overlay,
    );
    // Reconcile in the background: warn only if some photos couldn't upload, or
    // if the whole submission failed (the notifier rolls the stand-in back).
    future
        .then((failedPhotos) {
          if (failedPhotos > 0) {
            showAppSnackBar(
              null,
              '$failedPhotos photo${failedPhotos == 1 ? '' : 's'} '
              "couldn't be uploaded — the update was still submitted.",
              type: AppSnackType.info,
              overlay: overlay,
            );
          }
        })
        .catchError((Object e) {
          showAppSnackBar(
            null,
            staffFriendlyError(e),
            type: AppSnackType.error,
            overlay: overlay,
          );
        });
  }

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.of(context).size.width < 600;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (narrow)
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 4),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: StaffUi.borderStrong,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 8, 6),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'New community update',
                  style: TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w800,
                    color: StaffUi.textPrimary,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: StaffUi.textMuted),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: StaffUi.border),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _field('Title'),
                _input(_title, 'Short headline'),
                const SizedBox(height: 12),
                _field('Message'),
                _input(_body, 'What do you want to share?', maxLines: 4),
                const SizedBox(height: 12),
                _field('Posting as / tag'),
                _dropdown<UpdateCategory>(
                  value: _category,
                  items: [
                    for (final c in UpdateCategory.all)
                      DropdownMenuItem(value: c, child: Text(c.label)),
                  ],
                  onChanged: (v) => setState(() => _category = v!),
                ),
                const SizedBox(height: 12),
                _field('Audience'),
                _dropdown<String>(
                  value: _barangay,
                  items: [
                    const DropdownMenuItem(value: '', child: Text('City-wide')),
                    for (final b in kBarangayOptions)
                      DropdownMenuItem(value: b, child: Text(b)),
                  ],
                  onChanged: (v) => setState(() => _barangay = v ?? ''),
                ),
                const SizedBox(height: 12),
                _field('Photos (optional)'),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (var i = 0; i < _images.length; i++) _thumb(i),
                    if (_images.length < _maxImages) _addPhotoTile(),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: StaffUi.danger.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: StaffUi.danger.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          size: 17,
                          color: StaffUi.danger,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _error!,
                            style: const TextStyle(
                              fontSize: 12.5,
                              height: 1.35,
                              color: StaffUi.danger,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const Divider(height: 1, color: StaffUi.border),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  foregroundColor: StaffUi.textSecondary,
                ),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: StaffUi.accent),
                onPressed: _submit,
                child: const Text('Submit for approval'),
              ),
            ],
          ),
        ),
      ],
    );

    return Material(
      color: StaffUi.surface,
      borderRadius: narrow
          ? const BorderRadius.vertical(top: Radius.circular(22))
          : BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: narrow
          ? SafeArea(
              top: false,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.9,
                ),
                child: content,
              ),
            )
          : ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500, maxHeight: 680),
              child: content,
            ),
    );
  }

  Widget _addPhotoTile() => GestureDetector(
    onTap: _pickImages,
    child: Container(
      width: 76,
      height: 76,
      decoration: BoxDecoration(
        color: StaffUi.subtle,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: StaffUi.borderStrong),
      ),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.add_a_photo_rounded, color: StaffUi.textMuted, size: 20),
          SizedBox(height: 4),
          Text('Add', style: TextStyle(fontSize: 11, color: StaffUi.textMuted)),
        ],
      ),
    ),
  );

  Widget _thumb(int index) {
    final f = _images[index];
    return SizedBox(
      width: 76,
      height: 76,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: _LocalThumb(file: f, cache: _thumbCache),
          ),
          Positioned(
            top: 3,
            right: 3,
            child: GestureDetector(
              onTap: () => setState(() => _images.removeAt(index)),
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

  Widget _field(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      t,
      style: const TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
        color: StaffUi.textSecondary,
      ),
    ),
  );

  Widget _input(TextEditingController c, String hint, {int maxLines = 1}) {
    return TextField(
      controller: c,
      maxLines: maxLines,
      style: const TextStyle(fontSize: 14, color: StaffUi.textPrimary),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: StaffUi.textMuted, fontSize: 13.5),
        isDense: true,
        filled: true,
        fillColor: StaffUi.subtle,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        border: _border(StaffUi.border),
        enabledBorder: _border(StaffUi.border),
        focusedBorder: _border(StaffUi.accent, 1.4),
      ),
    );
  }

  Widget _dropdown<T>({
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: StaffUi.subtle,
        borderRadius: BorderRadius.circular(StaffUi.controlRadius),
        border: Border.all(color: StaffUi.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: StaffUi.textMuted,
          ),
          borderRadius: BorderRadius.circular(12),
          style: const TextStyle(fontSize: 14, color: StaffUi.textPrimary),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }

  OutlineInputBorder _border(Color c, [double w = 1]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(StaffUi.controlRadius),
    borderSide: BorderSide(color: c, width: w),
  );
}

/// Renders a freshly picked photo, memoising its bytes so the tile doesn't
/// re-read the file on every rebuild (works on web too, where a file path
/// isn't usable and only bytes are).
class _LocalThumb extends StatelessWidget {
  final XFile file;
  final Map<String, Uint8List> cache;
  const _LocalThumb({required this.file, required this.cache});

  @override
  Widget build(BuildContext context) {
    final cached = cache[file.path];
    if (cached != null) {
      return Image.memory(cached, width: 76, height: 76, fit: BoxFit.cover);
    }
    return FutureBuilder<Uint8List>(
      future: file.readAsBytes().then((b) => cache[file.path] = b),
      builder: (context, snap) {
        if (!snap.hasData) {
          return Container(
            width: 76,
            height: 76,
            color: StaffUi.subtle,
            child: const Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        return Image.memory(
          snap.data!,
          width: 76,
          height: 76,
          fit: BoxFit.cover,
        );
      },
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Community updates | My submissions — segmented switcher, mirroring the
//  admin console's "Published feed | Requests" pill pair.
// ═════════════════════════════════════════════════════════════════════════════
/// Staff mirror of the admin console's `_ComposerBar`: avatar, a tappable
/// "write something" pill, and a solid compose button. No broadcast action —
/// that is an admin-only power. Replaces the floating "New update" FAB, which
/// was the one piece of Community chrome the two consoles didn't share.
class _StaffComposerBar extends StatelessWidget {
  final VoidCallback onTap;
  final String? photoUrl;
  const _StaffComposerBar({required this.onTap, this.photoUrl});

  @override
  Widget build(BuildContext context) {
    // Below this the pill's placeholder is the first thing to get crushed, so
    // the label shortens rather than ellipsing mid-sentence.
    final compact = MediaQuery.of(context).size.width < 520;
    return Container(
      decoration: BoxDecoration(
        color: StaffUi.surface,
        borderRadius: BorderRadius.circular(StaffUi.cardRadius),
        border: Border.all(color: StaffUi.border),
        boxShadow: StaffUi.cardShadow,
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          buildAuthorAvatar(compact ? 36 : 42, photoUrl, ring: false),
          const SizedBox(width: 12),
          Expanded(
            child: Material(
              color: StaffUi.pageBg,
              borderRadius: BorderRadius.circular(24),
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Text(
                    compact
                        ? 'Submit an update…'
                        : 'Submit an update for review…',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      color: StaffUi.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Tooltip(
            message: 'New community update',
            child: Material(
              color: StaffUi.accent,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: onTap,
                child: const Padding(
                  padding: EdgeInsets.all(10),
                  child: Icon(
                    Icons.edit_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Mirrors the admin console's `_TabBar` exactly — same radii, type ramp,
/// animation and count badge — so the two Community screens read as one design.
class _TabSwitcher extends StatelessWidget {
  final int index;

  /// Submissions still awaiting an admin decision. Badged on the second tab the
  /// way admin badges its Requests tab; hidden at zero.
  final int pendingCount;
  final ValueChanged<int> onChanged;
  const _TabSwitcher({
    required this.index,
    required this.onChanged,
    this.pendingCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: StaffUi.surface,
        borderRadius: BorderRadius.circular(StaffUi.controlRadius + 2),
        border: Border.all(color: StaffUi.border),
      ),
      child: Row(
        children: [
          _seg('Community updates', 0, null),
          _seg('My submissions', 1, pendingCount),
        ],
      ),
    );
  }

  Widget _seg(String label, int i, int? badge) {
    final selected = index == i;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(i),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? StaffUi.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(StaffUi.controlRadius),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : StaffUi.textSecondary,
                  ),
                ),
              ),
              if (badge != null && badge > 0) ...[
                const SizedBox(width: 7),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: selected ? Colors.white24 : StaffUi.accentWash,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(
                    '$badge',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: selected ? Colors.white : StaffUi.accent,
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

// ═════════════════════════════════════════════════════════════════════════════
//  Published feed for staff — the same approved posts citizens see (via
//  CommunityPostsProvider, which resolves official identities), with hearts +
//  the shared comments sheet so staff can interact with citizen replies.
// ═════════════════════════════════════════════════════════════════════════════
class _StaffFeedTab extends StatefulWidget {
  /// Post OR comment id from a notification; resolved after load.
  final String? highlightId;

  /// Open the target post's comment thread (comment/reply notifications) and
  /// flash the target comment blue inside it.
  final bool openComments;

  /// Identifies the deep-link TAP — see [StaffCommunityPage.deepLinkNonce].
  final int deepLinkNonce;

  /// The identity comments are posted under. Non-null puts the shared comments
  /// sheet into official mode (admin-style bubbles, LGU chip, Edit/Delete).
  final String? officialName;

  const _StaffFeedTab({
    this.highlightId,
    this.openComments = false,
    this.deepLinkNonce = 0,
    this.officialName,
  });

  @override
  State<_StaffFeedTab> createState() => _StaffFeedTabState();
}

class _StaffFeedTabState extends State<_StaffFeedTab>
    with TickerProviderStateMixin, DeepLinkHighlightMixin {
  final SupabaseClient _supabase = Supabase.instance.client;
  final Set<String> _likedPosts = {};
  final Set<String> _likedComments = {};

  bool _handledTarget = false;
  bool _triedCommentResolve = false;
  late String? _targetPostId = widget.highlightId;
  String? _targetCommentId;

  @override
  void initState() {
    super.initState();
    CommunityPostsProvider.instance.addListener(_onPostsChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Always refetch on entry. An approval that landed while the staff was on
      // another tab — or on web, where the realtime event can be missed — must
      // not leave the feed stuck on a stale "No community updates yet" while the
      // app shows the post. initialLoadDone stays true after the first load, so
      // this refresh never re-flashes the skeleton or clears the visible list.
      final provider = CommunityPostsProvider.instance;
      if (provider.initialLoadDone) {
        provider.refresh();
      } else {
        provider.fetchPosts();
      }
      _loadMyInteractions();
      _maybeHandleTarget();
    });
  }

  @override
  void didUpdateWidget(covariant _StaffFeedTab old) {
    super.didUpdateWidget(old);
    // Re-arm for a fresh notification tap delivered while the feed tab is
    // already mounted. initState won't re-run, and the _handledTarget latch
    // would otherwise swallow every later heart/comment tap — the same trap
    // DeepLinkHighlightMixin.flashHighlightOnce documents.
    //
    // Keyed on the NONCE, not on highlightId/openComments. Two heart taps on
    // the same post deliver byte-identical values, so a value comparison sees
    // "nothing changed" and drops the second tap; only an intervening comment
    // tap (which flips openComments) made the next heart tap get through. The
    // nonce makes every tap distinct regardless of what it points at.
    final newTap =
        widget.highlightId != null && widget.deepLinkNonce != old.deepLinkNonce;
    if (newTap) {
      _handledTarget = false;
      _triedCommentResolve = false;
      // The mixin latches on the id too, so a repeat tap on the same heart
      // notification needs it re-armed or the flash is dropped.
      rearmHighlight();
      _targetPostId = widget.highlightId;
      _targetCommentId = null;
      _maybeHandleTarget();
    }
  }

  @override
  void dispose() {
    CommunityPostsProvider.instance.removeListener(_onPostsChanged);
    super.dispose();
  }

  void _onPostsChanged() {
    if (!mounted) return;
    setState(() {});
    _maybeHandleTarget();
  }

  Future<void> _loadMyInteractions() async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final postLikes = await _supabase
          .from('community_post_likes')
          .select('post_id')
          .eq('user_id', uid);
      final commentLikes = await _supabase
          .from('community_comment_likes')
          .select('comment_id')
          .eq('user_id', uid);
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

  // ── Notification target: post id, or a comment id that maps to one ─────────
  void _maybeHandleTarget() {
    if (_handledTarget) return;
    final targetId = _targetPostId;
    if (targetId == null) return;
    final posts = CommunityPostsProvider.instance.sortedPosts;
    Map<String, dynamic>? post;
    for (final p in posts) {
      if (p['id'] == targetId) {
        post = p;
        break;
      }
    }
    if (post == null) {
      if (CommunityPostsProvider.instance.initialLoadDone) {
        _tryResolveCommentRef(targetId);
      }
      return;
    }
    _handledTarget = true;
    final target = post;
    // Reactions flash; comments open the thread instead. Ringing the post as
    // well would leave it still lit once the sheet is closed.
    if (!widget.openComments) flashHighlightOnce(targetId);
    if (widget.openComments) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _openComments(target, highlightCommentId: _targetCommentId);
        }
      });
    }
  }

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
      _maybeHandleTarget();
    } catch (_) {
      /* unresolved — the feed just shows normally */
    }
  }

  // ── Hearts (posts + comments), optimistic with revert ──────────────────────
  Future<void> _togglePostLike(String postId) async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return;
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
            .eq('user_id', uid);
      } else {
        await _supabase.from('community_post_likes').insert({
          'post_id': postId,
          'user_id': uid,
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(
        () => wasLiked ? _likedPosts.add(postId) : _likedPosts.remove(postId),
      );
      CommunityPostsProvider.instance.bumpPostLike(postId, wasLiked ? 1 : -1);
      showAppSnackBar(
        context,
        'Unable to process your like. Please try again.',
        type: AppSnackType.error,
      );
    }
  }

  Future<void> _toggleCommentLike(String commentId) async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return;
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
            .eq('user_id', uid);
      } else {
        await _supabase.from('community_comment_likes').insert({
          'comment_id': commentId,
          'user_id': uid,
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(
        () => wasLiked
            ? _likedComments.add(commentId)
            : _likedComments.remove(commentId),
      );
      CommunityPostsProvider.instance.bumpCommentLike(
        commentId,
        wasLiked ? 1 : -1,
      );
      showAppSnackBar(
        context,
        'Unable to process your like. Please try again.',
        type: AppSnackType.error,
      );
    }
  }

  void _openComments(Map<String, dynamic> post, {String? highlightCommentId}) {
    showCommentsSheet(
      context,
      post: post,
      likedComments: _likedComments,
      onToggleLike: _toggleCommentLike,
      highlightCommentId: highlightCommentId,
      officialName: widget.officialName,
    ).whenComplete(_loadMyInteractions);
  }

  @override
  Widget build(BuildContext context) {
    final provider = CommunityPostsProvider.instance;
    final posts = provider.sortedPosts;

    if (!provider.initialLoadDone && provider.isLoading) {
      return const StaffShimmer(
        child: Column(
          children: [
            _SubmissionSkeletonCard(),
            SizedBox(height: 10),
            _SubmissionSkeletonCard(),
            SizedBox(height: 10),
            _SubmissionSkeletonCard(),
          ],
        ),
      );
    }
    if (posts.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 30),
        child: StaffEmptyState(
          icon: Icons.campaign_outlined,
          title: 'No community updates yet',
          subtitle: 'Approved posts appear here for everyone.',
        ),
      );
    }
    return Column(
      children: [
        for (final p in posts)
          Padding(
            key: highlightKey(p['id'] as String),
            padding: const EdgeInsets.only(bottom: 10),
            child: highlightRing(
              highlighted: isHighlighted(p['id'] as String),
              radius: 14,
              accent: StaffUi.accent,
              child: _FeedPostCard(
                post: p,
                liked: _likedPosts.contains(p['id']),
                onToggleLike: () => _togglePostLike(p['id'] as String),
                onOpenComments: () => _openComments(p),
              ),
            ),
          ),
      ],
    );
  }
}

/// One published post on the staff feed: author identity (resolved by the
/// shared provider — staff show name · office), text, photos, heart + comments.
class _FeedPostCard extends StatelessWidget {
  final Map<String, dynamic> post;
  final bool liked;
  final VoidCallback onToggleLike;
  final VoidCallback onOpenComments;
  const _FeedPostCard({
    required this.post,
    required this.liked,
    required this.onToggleLike,
    required this.onOpenComments,
  });

  @override
  Widget build(BuildContext context) {
    final p = post;
    final ts = p['timestamp'] as DateTime?;
    final dept = (p['authorDept'] as String?)?.trim() ?? '';
    final barangay = (p['barangay'] as String?)?.trim() ?? '';
    final title = (p['title'] as String?)?.trim() ?? '';
    final body = (p['body'] as String?)?.trim() ?? '';
    final imageUrls = (p['imageUrls'] as List?)?.cast<String>() ?? const [];
    final likes = int.tryParse('${p['likes']}') ?? 0;
    final commentCount = (p['commentCount'] as int?) ?? 0;
    final meta = [
      if (barangay.isNotEmpty) barangay else 'City-wide',
      if (ts != null) formatTimeAgo(ts),
    ].join(' · ');

    return StaffCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              buildAuthorAvatar(
                38,
                p['authorPhotoUrl'] as String?,
                photoPath: p['authorPhotoPath'] as String?,
                blank: p['blankAvatar'] == true,
                ring: p['isOfficial'] != true,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dept.isNotEmpty
                          ? '${p['author']} · $dept'
                          : '${p['author']}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: StaffUi.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      meta,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: StaffUi.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if ((p['tag'] as String?)?.isNotEmpty ?? false)
                StaffPill(
                  label: p['tag'] as String,
                  color: (p['tagColor'] as Color?) ?? StaffUi.accent,
                ),
            ],
          ),
          if (title.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: StaffUi.textPrimary,
              ),
            ),
          ],
          if (body.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              body,
              style: const TextStyle(
                fontSize: 13,
                height: 1.45,
                color: StaffUi.textSecondary,
              ),
            ),
          ],
          if (imageUrls.isNotEmpty) ...[
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, c) => buildImageGrid(
                c.maxWidth.clamp(0.0, 520.0),
                imageUrls.length,
                imageUrls: imageUrls,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              _EngageButton(
                icon: liked ? Icons.favorite_rounded : Icons.favorite_border,
                color: liked ? StaffUi.danger : StaffUi.textMuted,
                label: '$likes',
                onTap: onToggleLike,
              ),
              const SizedBox(width: 16),
              _EngageButton(
                icon: Icons.mode_comment_outlined,
                color: StaffUi.textMuted,
                label: '$commentCount',
                onTap: onOpenComments,
              ),
              const Spacer(),
              if (p['pinned'] == true)
                const Icon(
                  Icons.push_pin_rounded,
                  size: 15,
                  color: StaffUi.textMuted,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EngageButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  const _EngageButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: color == StaffUi.danger ? color : StaffUi.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
