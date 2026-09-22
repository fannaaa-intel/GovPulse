// ════════════════════════════════════════════════════════════════════════════
//  Admin — staff reply approval queue
//
//  Staff answer the suggestions routed to their office, but nothing reaches the
//  citizen until it is approved here. This panel is the gate.
//
//  It is ordered by how long the CITIZEN has been waiting, not by when the
//  draft was written: an office that answers late should not be rewarded with a
//  fresh place at the front of the queue.
//
//  Rejecting REQUIRES a reason. A draft returned with no explanation gives the
//  author nothing to act on and comes straight back — the reason is what makes
//  the loop terminate.
//
//  ── WHY ONLY TWO ROWS SHOW ────────────────────────────────────────────────
//  Each row is tall: an avatar line, the citizen's words, the office's reply,
//  and two buttons. Seven of them is a screen and a half of scrolling on a
//  desktop and far worse on a phone — and all of it sits ABOVE the suggestions
//  list, so a busy queue buries the page it is attached to. The panel is a
//  gate, not the work surface: it shows the two longest-waiting drafts (the
//  ordering already puts those first) and sends the rest to a surface built for
//  a list. Nothing is hidden — the header still counts every one of them, and
//  the footer row names how many are behind it.
// ════════════════════════════════════════════════════════════════════════════

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_dialog.dart';
import '../providers/admin_staff_replies_provider.dart';
import '../theme/admin_ui.dart';
import 'admin_detail_screen.dart';
import 'admin_snackbar.dart';

/// Below this the action buttons stack instead of sharing a row.
const double _kActionsRowFrom = 420;

/// How many drafts the inline panel draws before deferring to "View all".
const int kInlineApprovalRows = 2;

class StaffReplyApprovalsPanel extends ConsumerWidget {
  const StaffReplyApprovalsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(adminStaffRepliesProvider);
    final items = async.valueOrNull ?? const <PendingStaffReply>[];

    // A FAILED read must not look like an empty queue. Collapsing on error is
    // how the broken admin_profiles embed stayed invisible: the read threw on
    // every load, the panel rendered nothing, and the console said — silently —
    // that there was no work waiting. An error now says so and offers a retry.
    if (async.hasError && items.isEmpty) {
      return _PanelFrame(
        accent: const Color(0xFFDC2626),
        icon: Icons.error_outline_rounded,
        title: 'Approvals could not be loaded',
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Staff replies may be waiting. This is a loading problem, not '
                'an empty queue.',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.45,
                  color: AdminUi.textSecondary,
                ),
              ),
              const SizedBox(height: 11),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () =>
                      ref.read(adminStaffRepliesProvider.notifier).refresh(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFDC2626),
                    side: const BorderSide(color: Color(0xFFE5A3A3)),
                    minimumSize: const Size(0, 40),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(AdminUi.controlRadius),
                    ),
                  ),
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Try again'),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // First load shows a skeleton in the panel's own shape, so nothing below it
    // jumps when the queue lands. Only on the FIRST load — a refresh keeps the
    // rows on screen rather than blanking work the admin is reading.
    if (async.isLoading && items.isEmpty) {
      return const _ApprovalsSkeleton();
    }

    // The panel disappears when there is nothing to approve rather than showing
    // an empty box on every visit — this is a queue, not a permanent section.
    if (items.isEmpty) return const SizedBox.shrink();

    return _PanelFrame(
      accent: const Color(0xFFF39C12),
      icon: Icons.rate_review_rounded,
      title: items.length == 1
          ? '1 staff reply waiting for approval'
          : '${items.length} staff replies waiting for approval',
      // One line of orientation for an admin meeting this queue for the first
      // time. Without it the panel states a count but never says what pressing
      // the green button actually does to the citizen.
      subtitle: 'Nothing here has reached the citizen yet. Approving publishes '
          'the reply and notifies them.',
      child: _ApprovalList(
        items: items,
        // The inline panel shows the front of the queue only. The full list
        // lives behind the footer, where it has a surface of its own.
        max: kInlineApprovalRows,
        onViewAll: () => _openAllApprovals(context),
      ),
    );
  }
}

/// The rows, divided, optionally capped with a "View all N" footer.
///
/// Shared by the inline panel and the full view so a row cannot drift between
/// the two: the expanded surface is the SAME widget with the cap lifted.
class _ApprovalList extends StatelessWidget {
  final List<PendingStaffReply> items;

  /// Null draws every row — the full view.
  final int? max;
  final VoidCallback? onViewAll;

  const _ApprovalList({required this.items, this.max, this.onViewAll});

  @override
  Widget build(BuildContext context) {
    final shown = max == null ? items.length : items.length.clamp(0, max!);
    final hidden = items.length - shown;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < shown; i++) ...[
          if (i > 0)
            const Divider(height: 1, thickness: 1, color: AdminUi.border),
          _ReplyRow(item: items[i]),
        ],
        if (hidden > 0 && onViewAll != null) ...[
          const Divider(height: 1, thickness: 1, color: AdminUi.border),
          _ViewAllRow(hidden: hidden, onTap: onViewAll!),
        ],
      ],
    );
  }
}

/// The footer that opens the rest of the queue.
///
/// It states the REMAINDER, not the total: "2 of 7 shown" makes the admin do
/// the subtraction to learn what pressing it gains them.
class _ViewAllRow extends StatelessWidget {
  final int hidden;
  final VoidCallback onTap;
  const _ViewAllRow({required this.hidden, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  hidden == 1
                      ? 'View all — 1 more reply waiting'
                      : 'View all — $hidden more replies waiting',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primaryBlue,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // The console's "this opens something" cue, the same glyph the
              // dashboard cards and settings rows use.
              const Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: AppColors.primaryBlue,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens the whole queue.
///
/// [showAdminDetail] already makes the choice the console makes everywhere
/// else: a centred dialog card on desktop and laptop, and below 640px an
/// INSTANT full-screen route whose chevron header stays put while only the
/// body slides up. Rebuilding either shape here would be a near-miss of a
/// surface the admin already knows.
void _openAllApprovals(BuildContext context) {
  showAdminDetail<void>(
    context,
    builder: (_) => const _AllApprovalsView(),
  );
}

/// The full queue, on whichever surface [showAdminDetail] chose.
///
/// It watches the same provider rather than taking a snapshot: approving from
/// in here empties a row, and a list built from a tap-time copy would keep
/// offering work that no longer exists.
class _AllApprovalsView extends StatelessWidget {
  const _AllApprovalsView();

  static const String title = 'Staff replies waiting';

  @override
  Widget build(BuildContext context) {
    if (adminDetailIsNarrow(context)) {
      return const AdminDetailScaffold(
        title: title,
        child: _AllApprovalsBody(),
      );
    }

    // Desktop / laptop: the centred card. Capped in both directions so a queue
    // of forty does not grow a dialog taller than the window.
    return Dialog(
      backgroundColor: AdminUi.surface,
      insetPadding: const EdgeInsets.all(40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 720,
          maxHeight: MediaQuery.sizeOf(context).height * 0.86,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 14),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AdminUi.textPrimary,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, size: 20),
                    color: AdminUi.textSecondary,
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AdminUi.border),
            const Flexible(child: _AllApprovalsBody()),
          ],
        ),
      ),
    );
  }
}

/// The phone body, separated so [AdminDetailScaffold] can be `const` and the
/// list rebuilds from the provider inside the slide-up rather than around it.
class _AllApprovalsBody extends ConsumerWidget {
  const _AllApprovalsBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items =
        ref.watch(adminStaffRepliesProvider).valueOrNull ?? const [];
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
          child: Text(
            items.isEmpty
                ? 'Everything here has been decided.'
                : 'Nothing here has reached the citizen yet. Approving '
                    'publishes the reply and notifies them. Longest wait '
                    'first.',
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.45,
              color: AdminUi.textSecondary,
            ),
          ),
        ),
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 30, 16, 16),
            child: Center(
              child: Text(
                'No replies are waiting for approval.',
                style: TextStyle(fontSize: 13, color: AdminUi.textMuted),
              ),
            ),
          )
        else
          _ApprovalList(items: items),
      ],
    );
  }
}

/// The panel's shell — one border, one tinted header, one body — shared by the
/// queue, the skeleton and the error state so all three occupy the same shape
/// and nothing below shifts as the panel moves between them.
class _PanelFrame extends StatelessWidget {
  final Color accent;
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget child;

  const _PanelFrame({
    required this.accent,
    required this.icon,
    required this.title,
    required this.child,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AdminUi.surface,
        borderRadius: BorderRadius.circular(AdminUi.cardRadius),
        border: Border.all(color: accent.withValues(alpha: 0.5)),
        boxShadow: AdminUi.cardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            color: accent.withValues(alpha: 0.09),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Nudged onto the first line's optical centre so the icon does
                // not float when the title wraps to two lines on a phone.
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(icon,
                      size: 17, color: Color.lerp(accent, Colors.black, 0.28)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: Color.lerp(accent, Colors.black, 0.45),
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11.5,
                            height: 1.35,
                            color: AdminUi.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// First-load placeholder in the panel's own shape.
class _ApprovalsSkeleton extends StatelessWidget {
  const _ApprovalsSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget bar(double w, double h) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: AdminUi.border,
            borderRadius: BorderRadius.circular(4),
          ),
        );

    return _PanelFrame(
      accent: const Color(0xFFF39C12),
      icon: Icons.rate_review_rounded,
      title: 'Checking for staff replies…',
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: const BoxDecoration(
                    color: AdminUi.border,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      bar(140, 11),
                      const SizedBox(height: 6),
                      bar(96, 9),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 13),
            // Full-width bars: LayoutBuilder-free, so they shrink with the
            // phone rather than overflowing a narrow console.
            bar(double.infinity, 44),
            const SizedBox(height: 9),
            bar(double.infinity, 44),
          ],
        ),
      ),
    );
  }
}

class _ReplyRow extends ConsumerStatefulWidget {
  final PendingStaffReply item;
  const _ReplyRow({required this.item});

  @override
  ConsumerState<_ReplyRow> createState() => _ReplyRowState();
}

class _ReplyRowState extends ConsumerState<_ReplyRow> {
  /// Guards the write, not just the button's look. A flag that only reaches the
  /// widget tree still permits a second tap in the same frame, which here would
  /// mean approving twice.
  bool _busy = false;

  /// The console's shared top-anchored toast, not a SnackBar.
  ///
  /// [overlay] is captured by the caller BEFORE its await: approving removes
  /// this row from the queue, so by the time the result lands this widget is
  /// often already unmounted and its own context can no longer find an
  /// overlay. The root overlay lives for the app's lifetime.
  void _say(OverlayState? overlay, String message, {bool error = false}) {
    showAdminSnackBar(
      null,
      message,
      type: error ? AdminSnackType.error : AdminSnackType.success,
      overlay: overlay,
    );
  }

  /// Turns a failure into something the admin can act on. "Please try again" is
  /// the wrong advice for two of these three cases, and retrying a permission
  /// error forever is how a real problem gets mistaken for a flaky network.
  String _failure(Object e, String verb) {
    final s = e.toString();
    // Raised by the provider when the UPDATE matched no row: either RLS
    // filtered it out, or someone else already decided this draft.
    if (s.contains('-no-op:')) {
      return 'Nothing changed — this draft was already decided, or your '
          'account lacks permission. Refresh to see its current state.';
    }
    // PostgREST's RLS refusal.
    if (s.contains('42501') || s.toLowerCase().contains('row-level security')) {
      return 'Your account does not have permission to approve replies. '
          'An administrator role is required.';
    }
    return 'The reply could not be $verb. Check your connection and try again.';
  }

  Future<void> _approve() async {
    if (_busy) return;
    // Before the await: an approved row leaves the queue, unmounting this
    // widget, and an unmounted context can no longer find an overlay.
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    setState(() => _busy = true);
    try {
      await ref
          .read(adminStaffRepliesProvider.notifier)
          .approve(widget.item.id);
      _say(overlay, 'Reply published. The citizen has been notified.');
    } catch (e) {
      _say(overlay, _failure(e, 'published'), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    if (_busy) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    final reason = await _askReason(context);
    if (reason == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(adminStaffRepliesProvider.notifier)
          .reject(widget.item.id, reason);
      _say(overlay, 'Sent back to the office with your note.');
    } catch (e) {
      _say(overlay, _failure(e, 'returned'), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final it = widget.item;
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Avatar(url: it.authorPhotoUrl, name: it.authorName),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      it.authorName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: AdminUi.textPrimary,
                      ),
                    ),
                    Text(
                      '${it.department} · ${it.categoryLabel}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AdminUi.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _WaitBadge(waiting: it.citizenWaiting),
            ],
          ),
          const SizedBox(height: 11),
          // The citizen's words first: a reply cannot be judged without the
          // thing it answers.
          _Quote(
            label: 'The citizen wrote',
            body: it.suggestionDetails,
            color: AdminUi.textMuted,
          ),
          const SizedBox(height: 9),
          _Quote(
            label: 'The office replied',
            body: it.body,
            color: AppColors.primaryBlue,
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, c) {
              final approve = FilledButton.icon(
                onPressed: _busy ? null : _approve,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF16A34A),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(AdminUi.controlRadius),
                  ),
                ),
                icon: _busy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.check_rounded, size: 16),
                label: const Text('Approve & publish'),
              );
              final reject = OutlinedButton.icon(
                onPressed: _busy ? null : _reject,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFDC2626),
                  side: const BorderSide(color: Color(0xFFE5A3A3)),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(AdminUi.controlRadius),
                  ),
                ),
                icon: const Icon(Icons.undo_rounded, size: 16),
                label: const Text('Send back'),
              );
              if (c.maxWidth < _kActionsRowFrom) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(height: 40, child: approve),
                    const SizedBox(height: 8),
                    SizedBox(height: 40, child: reject),
                  ],
                );
              }
              // Flexible, not bare: the buttons are intrinsically sized, so on
              // a narrow-but-above-breakpoint console (a tablet rail, a split
              // window) two unshrinkable labels would overflow the row rather
              // than ellipsise. Flexible lets them give way instead.
              return Row(
                children: [
                  Flexible(child: SizedBox(height: 40, child: approve)),
                  const SizedBox(width: 9),
                  Flexible(child: SizedBox(height: 40, child: reject)),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Quote extends StatelessWidget {
  final String label;
  final String body;
  final Color color;
  const _Quote({
    required this.label,
    required this.body,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: AdminUi.subtle,
        borderRadius: BorderRadius.circular(AdminUi.controlRadius),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
              color: color,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            body,
            // A long suggestion must not push the approve button below the
            // fold — a control the admin cannot see is one they cannot press.
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.45,
              color: AdminUi.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _WaitBadge extends StatelessWidget {
  final Duration waiting;
  const _WaitBadge({required this.waiting});

  @override
  Widget build(BuildContext context) {
    final days = waiting.inDays;
    final late = days >= 3;
    // A reply drafted within the hour read as "0h waiting", which looks like a
    // bug rather than a fresh item. Minutes below the hour, and a floor of
    // "just now" below that.
    final String label;
    if (days >= 1) {
      label = '${days}d waiting';
    } else if (waiting.inHours >= 1) {
      label = '${waiting.inHours}h waiting';
    } else if (waiting.inMinutes >= 1) {
      label = '${waiting.inMinutes}m waiting';
    } else {
      label = 'just now';
    }
    return Semantics(
      // The colour alone carries the "overdue" meaning; a screen reader needs
      // it said.
      label: late
          ? 'Overdue: the citizen has been waiting $label'
          : 'Citizen waiting $label',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: (late ? const Color(0xFFDC2626) : AdminUi.textMuted)
              .withValues(alpha: 0.11),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          softWrap: false,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            color: late ? const Color(0xFFDC2626) : AdminUi.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String? url;
  final String name;
  const _Avatar({required this.url, required this.name});

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    final fallback = Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: Color(0xFFEAF1FB),
        shape: BoxShape.circle,
      ),
      child: Text(
        initial,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w800,
          color: AppColors.primaryBlue,
        ),
      ),
    );
    if (url == null || url!.isEmpty) return fallback;
    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: url!,
        width: 34,
        height: 34,
        fit: BoxFit.cover,
        placeholder: (_, _) => fallback,
        errorWidget: (_, _, _) => fallback,
      ),
    );
  }
}

/// Asks for the reason. Returns null when cancelled, and never returns an empty
/// string — the send-back is refused until a reason is typed, and the refusal
/// names the field rather than silently doing nothing.
///
/// ── WHY THE SHAPE CHANGES WITH THE SCREEN ─────────────────────────────────
/// As a centred AlertDialog on a 445px phone this was a small white card
/// floating in the middle of the viewport: the field it exists to collect was
/// four lines tall inside a box narrower than the page behind it, and the
/// keyboard then covered the buttons. A phone's own answer to "type one thing
/// and confirm" is a sheet that rises from the bottom edge, sits above the
/// keyboard, and gives the field the full width. On a laptop the card is still
/// right — it keeps the reply visible behind it and says "this is a step".
///
/// Both shapes render the SAME body, so the copy, the validation and the
/// refusal message cannot drift between them.
Future<String?> _askReason(BuildContext context) {
  final ctrl = TextEditingController();
  // `error` lives OUTSIDE the builder. Declared inside, every rebuild would
  // reset it to null and the message would never render — the button would
  // look dead, which is the exact failure this message exists to prevent.
  String? error;

  // The same 640 the console uses to decide screen-vs-modal everywhere else,
  // so one dialog does not change shape at a width no other dialog does.
  final narrow = MediaQuery.sizeOf(context).width < kAdminDetailNarrowBelow;

  Widget body(BuildContext ctx, StateSetter setLocal, {required bool sheet}) {
    final field = TextField(
      controller: ctrl,
      maxLines: sheet ? 3 : 4,
      // Not on the sheet: autofocus raises the keyboard as the sheet is still
      // animating up, and the two movements fight. The admin taps the field.
      autofocus: !sheet,
      textInputAction: TextInputAction.newline,
      style: const TextStyle(fontSize: 13.5),
      onChanged: (_) {
        if (error != null) setLocal(() => error = null);
      },
      decoration: InputDecoration(
        hintText: 'e.g. Please answer the drainage question too.',
        hintStyle: const TextStyle(fontSize: 13, color: AdminUi.textMuted),
        errorText: error,
        filled: true,
        fillColor: AdminUi.subtle,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AdminUi.controlRadius),
          borderSide: const BorderSide(color: AdminUi.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AdminUi.controlRadius),
          borderSide: const BorderSide(color: AdminUi.border),
        ),
      ),
    );

    void submit() {
      final v = ctrl.text.trim();
      // Name the field. A bare return here reads as a dead button.
      if (v.isEmpty) {
        setLocal(() => error = 'Please say what needs changing.');
        return;
      }
      Navigator.of(ctx).pop(v);
    }

    final cancel = TextButton(
      onPressed: () => Navigator.of(ctx).pop(),
      child: const Text('Cancel'),
    );
    final send = FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFFDC2626),
        minimumSize: sheet ? const Size(0, 46) : null,
      ),
      onPressed: submit,
      child: const Text('Send back'),
    );

    if (!sheet) {
      return AlertDialog(
        backgroundColor: AdminUi.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AdminUi.cardRadius),
        ),
        title: const Text(
          'Send back for changes',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Tell the office what to change. They see this note.',
              style: TextStyle(fontSize: 13, color: AdminUi.textMuted),
            ),
            const SizedBox(height: 12),
            field,
          ],
        ),
        actions: [cancel, send],
      );
    }

    // The sheet. The drag handle is the grab affordance; the title carries the
    // same words as the card so the two are recognisably one control.
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Send back for changes',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AdminUi.textPrimary,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Tell the office what to change. They see this note.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: AdminUi.textSecondary,
              ),
            ),
            const SizedBox(height: 14),
            field,
            const SizedBox(height: 16),
            // Full width, confirm on top: on a phone the thumb sits at the
            // bottom, and the destructive-but-intended action is the one being
            // reached for. Cancel stays a text button so the two never read as
            // a pair of equal choices.
            SizedBox(width: double.infinity, child: send),
            const SizedBox(height: 4),
            Center(child: cancel),
          ],
        ),
      ),
    );
  }

  if (narrow) {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: AdminUi.surface,
      // Both load-bearing: without them the sheet is capped at half the screen
      // and the keyboard covers the field it just raised.
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        // viewInsets read from the SHEET's context, not the caller's: the
        // caller's media query does not change when the keyboard opens, so
        // padding built from it never moves and the field stays covered.
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(ctx).bottom,
        ),
        child: StatefulBuilder(
          builder: (ctx, setLocal) => body(ctx, setLocal, sheet: true),
        ),
      ),
    );
  }

  return showAppDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => body(ctx, setLocal, sheet: false),
    ),
  );
}
