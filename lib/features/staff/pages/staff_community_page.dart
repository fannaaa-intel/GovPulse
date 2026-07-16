import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/deeplink_highlight.dart';
import '../../admin/providers/community_updates_provider.dart'
    show UpdateCategory, kBarangayOptions;
import '../data/staff_repository.dart';
import '../providers/staff_providers.dart';
import '../theme/staff_ui.dart';
import '../widgets/staff_common.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Community — staff compose updates that are QUEUED for admin approval before
//  they reach the citizen feed (they never publish directly).
// ════════════════════════════════════════════════════════════════════════════

class StaffCommunityPage extends ConsumerStatefulWidget {
  /// A post id to scroll to and flash once, when arriving from an
  /// approval/comment notification. Null for a normal open.
  final String? highlightId;
  const StaffCommunityPage({super.key, this.highlightId});

  @override
  ConsumerState<StaffCommunityPage> createState() => _StaffCommunityPageState();
}

class _StaffCommunityPageState extends ConsumerState<StaffCommunityPage>
    with DeepLinkHighlightMixin {
  @override
  Widget build(BuildContext context) {
    final async = ref.watch(staffCommunityProvider);

    // Rows exist only once the fetch resolves — flash the deep-link target then.
    if (async.hasValue) flashHighlightOnce(widget.highlightId);

    return Stack(
      children: [
        StaffPageBody(
          onRefresh: () => ref.read(staffCommunityProvider.notifier).refresh(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: StaffUi.accentWash,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: StaffUi.accent.withValues(alpha: 0.25)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline_rounded,
                        size: 18, color: StaffUi.accent),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Posts you submit are reviewed by an LGU admin before they '
                        'appear on the citizen feed.',
                        style: TextStyle(fontSize: 12.5, color: StaffUi.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text('My submissions',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: StaffUi.textPrimary,
                  )),
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
                        subtitle: 'Tap "New update" to submit one for approval.',
                      ),
                    );
                  }
                  return Column(
                    children: [
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
          ),
        ),
        Positioned(
          right: 20,
          bottom: 24,
          child: FloatingActionButton.extended(
            backgroundColor: StaffUi.accent,
            foregroundColor: Colors.white,
            onPressed: () => _openComposer(context, ref),
            icon: const Icon(Icons.add_rounded),
            label: const Text('New update'),
          ),
        ),
      ],
    );
  }

  void _openComposer(BuildContext context, WidgetRef ref) {
    final narrow = MediaQuery.of(context).size.width < 600;
    const sheet = _ComposerSheet();
    if (narrow) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: sheet,
        ),
      );
    } else {
      showDialog(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.45),
        builder: (_) => const Center(
          child: Padding(padding: EdgeInsets.all(24), child: sheet),
        ),
      );
    }
  }
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
    final (label, color) = p.isApproved
        ? ('Approved', StaffUi.online)
        : p.isRejected
            ? ('Rejected', StaffUi.danger)
            : ('Pending review', StaffUi.warn);
    return highlightRing(
      highlighted: highlighted,
      radius: 14,
      accent: StaffUi.accent,
      child: StaffCard(
        padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  p.title.isEmpty ? '(untitled)' : p.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: StaffUi.textPrimary,
                  ),
                ),
              ),
              StaffPill(label: label, color: color),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            p.body,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5, color: StaffUi.textSecondary),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              StaffPill(label: p.tag, color: StaffUi.accent),
              const Spacer(),
              Text(staffAgo(p.createdAt),
                  style: const TextStyle(fontSize: 11, color: StaffUi.textMuted)),
            ],
          ),
          if (p.isRejected && (p.rejectedReason ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: StaffUi.danger.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('Reason: ${p.rejectedReason}',
                  style: const TextStyle(fontSize: 12, color: StaffUi.danger)),
            ),
          ],
          ],
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
  const _ComposerSheet();
  @override
  ConsumerState<_ComposerSheet> createState() => _ComposerSheetState();
}

class _ComposerSheetState extends ConsumerState<_ComposerSheet> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  UpdateCategory _category = UpdateCategory.all.first;
  String _barangay = ''; // '' == city-wide
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final t = _title.text.trim();
    final b = _body.text.trim();
    if (t.isEmpty || b.isEmpty) {
      setState(() => _error = 'A title and message are required.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(staffCommunityProvider.notifier).submit(
            title: t,
            body: b,
            barangay: _barangay,
            tag: _category.label,
            tagColorHex: _category.hex,
          );
      if (mounted) {
        Navigator.pop(context);
        showAppSnackBar(context, 'Submitted for admin approval.',
            type: AppSnackType.success);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
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
                child: Text('New community update',
                    style: TextStyle(
                      fontSize: 16.5,
                      fontWeight: FontWeight.w800,
                      color: StaffUi.textPrimary,
                    )),
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
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!,
                      style: const TextStyle(fontSize: 12.5, color: StaffUi.danger)),
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
                onPressed: _busy ? null : () => Navigator.pop(context),
                style: TextButton.styleFrom(foregroundColor: StaffUi.textSecondary),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: StaffUi.accent),
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Submit for approval'),
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

  Widget _field(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(t,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: StaffUi.textSecondary,
            )),
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
          icon: const Icon(Icons.keyboard_arrow_down_rounded,
              color: StaffUi.textMuted),
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
