import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show HardwareKeyboard, KeyDownEvent, LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/widgets/app_snackbar.dart';
import '../data/staff_repository.dart';
import '../providers/staff_providers.dart';
import '../theme/staff_ui.dart';
import '../widgets/staff_common.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Conversations — the live-chat inbox.
//
//  Wide screens: a two-pane helpdesk (conversation list | thread).
//  Narrow screens: the list; tapping a chat pushes the thread full-screen.
// ════════════════════════════════════════════════════════════════════════════

class StaffConversationsPage extends ConsumerStatefulWidget {
  /// A ticket to OPEN on arrival, from a chat/ticket/message notification.
  ///
  /// Deliberately not a "flash the row" deep-link like the other consoles: a
  /// conversation's whole point is its thread, so a notification about a new
  /// message should land the staffer IN it, not accent a list row they then
  /// have to tap anyway.
  final String? openTicketId;
  const StaffConversationsPage({super.key, this.openTicketId});

  @override
  ConsumerState<StaffConversationsPage> createState() =>
      _StaffConversationsPageState();
}

class _StaffConversationsPageState
    extends ConsumerState<StaffConversationsPage> {
  StaffConversation? _selected;
  RealtimeChannel? _ticketChannel;
  String? _subscribedDept;
  Timer? _debounce;

  /// One-shot: the deep-linked ticket opens on the first build that has it.
  bool _openedDeepLink = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _ticketChannel?.unsubscribe();
    super.dispose();
  }

  /// Opens [c]: side-by-side on a wide console, pushed as its own screen on a
  /// narrow one. Shared by a list tap and a notification deep-link so both land
  /// identically.
  void _openConversation(StaffConversation c, bool wide) {
    if (wide) {
      setState(() => _selected = c);
    } else {
      // Instant on enter (the thread body slides up itself); fade out on
      // exit. transitionDuration:0 makes the push instant, so the
      // FadeTransition only animates on pop (reverseTransitionDuration).
      Navigator.of(context).push(PageRouteBuilder(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, _, _) => _ThreadScreen(conversation: c),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      ));
    }
  }

  /// Opens the ticket a notification pointed at, once the list has loaded and
  /// can resolve the id into a conversation. Runs at most once.
  ///
  /// Called from build, so the open is deferred past the current frame — it
  /// either calls setState or pushes a route, neither legal mid-build.
  void _maybeOpenDeepLink(
    AsyncValue<List<StaffConversation>> async,
    bool wide,
  ) {
    if (_openedDeepLink) return;
    final id = widget.openTicketId;
    if (id == null || id.isEmpty) return;
    final data = async.valueOrNull;
    if (data == null) return; // still loading — try again on the next build

    StaffConversation? match;
    for (final c in data) {
      if (c.id == id) {
        match = c;
        break;
      }
    }
    // Not in this staffer's list (reassigned, or another department's) — leave
    // them on the list rather than opening nothing.
    if (match == null) return;

    _openedDeepLink = true;
    final target = match;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _openConversation(target, wide);
    });
  }

  /// (Re)subscribes to the department's ticket stream so new waiting chats
  /// appear live. Debounced so a burst of changes triggers one refetch.
  void _ensureSubscribed(String? dept) {
    if (dept == _subscribedDept) return;
    _ticketChannel?.unsubscribe();
    _subscribedDept = dept;
    if (dept == null) return;
    _ticketChannel = StaffRepository.I.subscribeDepartmentTickets(dept, () {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 400), () {
        ref.read(staffConversationsProvider.notifier).silentRefresh();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(
      staffDepartmentProvider,
      (_, next) => _ensureSubscribed(next),
    );
    _ensureSubscribed(ref.read(staffDepartmentProvider));
    final async = ref.watch(staffConversationsProvider);
    final wide = MediaQuery.of(context).size.width >= 900;

    // A notification about a message opens its thread, once the list has loaded
    // enough to resolve the ticket id into a conversation.
    _maybeOpenDeepLink(async, wide);

    final list = _ConversationList(
      async: async,
      selectedId: wide ? _selected?.id : null,
      onRefresh: () => ref.read(staffConversationsProvider.notifier).refresh(),
      onTap: (c) => _openConversation(c, wide),
    );

    if (!wide) return Container(color: StaffUi.pageBg, child: list);

    // Keep the selection valid as the list refreshes.
    final data = async.valueOrNull;
    if (_selected != null && data != null) {
      final match = data.where((c) => c.id == _selected!.id).toList();
      if (match.isNotEmpty) _selected = match.first;
    }

    return Container(
      color: StaffUi.pageBg,
      child: Row(
        children: [
          SizedBox(width: 340, child: list),
          const VerticalDivider(width: 1, color: StaffUi.border),
          Expanded(
            child: _selected == null
                ? const StaffEmptyState(
                    icon: Icons.forum_outlined,
                    title: 'Select a conversation',
                    subtitle: 'Pick a citizen chat on the left to start replying.',
                  )
                : StaffThreadView(
                    key: ValueKey(_selected!.id),
                    conversation: _selected!,
                  ),
          ),
        ],
      ),
    );
  }
}

class _ConversationList extends StatelessWidget {
  final AsyncValue<List<StaffConversation>> async;
  final String? selectedId;
  final Future<void> Function() onRefresh;
  final void Function(StaffConversation) onTap;
  const _ConversationList({
    required this.async,
    required this.selectedId,
    required this.onRefresh,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: StaffUi.accent,
      onRefresh: onRefresh,
      child: async.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: StaffUi.accent),
        ),
        error: (e, _) => StaffErrorState(
          message: "Couldn't load conversations.",
          onRetry: onRefresh,
        ),
        data: (items) {
          if (items.isEmpty) {
            return ListView(
              children: const [
                SizedBox(height: 60),
                StaffEmptyState(
                  icon: Icons.chat_bubble_outline_rounded,
                  title: 'No conversations yet',
                  subtitle:
                      'When a citizen asks to talk to a person, their chat appears here. Stay Online to receive them.',
                ),
              ],
            );
          }
          final waiting = items.where((c) => c.isWaiting).toList();
          final mine = items.where((c) => !c.isWaiting && !c.isResolved).toList();
          final done = items.where((c) => c.isResolved).toList();
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              if (waiting.isNotEmpty) ...[
                const _GroupHeader('Waiting'),
                for (final c in waiting) _tile(c),
              ],
              if (mine.isNotEmpty) ...[
                const _GroupHeader('Active'),
                for (final c in mine) _tile(c),
              ],
              if (done.isNotEmpty) ...[
                const _GroupHeader('Resolved'),
                for (final c in done) _tile(c),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _tile(StaffConversation c) => _ConversationTile(
        conversation: c,
        selected: c.id == selectedId,
        onTap: () => onTap(c),
      );
}

class _GroupHeader extends StatelessWidget {
  final String label;
  const _GroupHeader(this.label);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
        child: Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: StaffUi.textMuted,
          ),
        ),
      );
}

class _ConversationTile extends StatelessWidget {
  final StaffConversation conversation;
  final bool selected;
  final VoidCallback onTap;
  const _ConversationTile({
    required this.conversation,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = conversation;
    return Material(
      color: selected ? StaffUi.accentWash : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: StaffUi.subtle)),
          ),
          child: Row(
            children: [
              _TileAvatar(
                label: c.citizenLabel,
                anonymous: c.isAnonymous,
                photoUrl: c.photoUrl,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            c.citizenLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: StaffUi.textPrimary,
                            ),
                          ),
                        ),
                        Text(staffAgo(c.updatedAt ?? c.createdAt),
                            style: const TextStyle(
                                fontSize: 10.5, color: StaffUi.textMuted)),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            c.category,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12, color: StaffUi.textSecondary),
                          ),
                        ),
                        if (c.isWaiting)
                          const StaffPill(label: 'New', color: StaffUi.warn)
                        else if (c.isResolved)
                          (c.rating != null
                              ? StaffStarRow(c.rating!, size: 13)
                              : const StaffPill(
                                  label: 'Resolved', color: StaffUi.online)),
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

}

/// The 40px inbox-list avatar: citizen photo, default person icon (anonymous),
/// or name initial.
class _TileAvatar extends StatelessWidget {
  final String label;
  final bool anonymous;
  final String? photoUrl;
  const _TileAvatar({
    required this.label,
    required this.anonymous,
    required this.photoUrl,
  });

  @override
  Widget build(BuildContext context) {
    const d = 40.0;
    if (anonymous) {
      return Container(
        width: d,
        height: d,
        decoration:
            const BoxDecoration(color: StaffUi.subtle, shape: BoxShape.circle),
        child: const Icon(Icons.person_rounded, size: 22, color: StaffUi.textMuted),
      );
    }
    if (photoUrl != null && photoUrl!.isNotEmpty) {
      return Container(
        width: d,
        height: d,
        decoration: const BoxDecoration(shape: BoxShape.circle),
        clipBehavior: Clip.antiAlias,
        child: CachedNetworkImage(
          imageUrl: photoUrl!,
          fit: BoxFit.cover,
          errorWidget: (_, _, _) => _initialCircle(),
        ),
      );
    }
    return _initialCircle();
  }

  Widget _initialCircle() {
    final t = label.trim();
    final ch = t.isEmpty ? 'C' : t.substring(0, 1).toUpperCase();
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: StaffUi.accent.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Text(ch,
          style: const TextStyle(
              color: StaffUi.accent, fontWeight: FontWeight.w700, fontSize: 15)),
    );
  }
}

// ── Full-screen thread wrapper (narrow layout) ───────────────────────────────
class _ThreadScreen extends StatelessWidget {
  final StaffConversation conversation;
  const _ThreadScreen({required this.conversation});

  @override
  Widget build(BuildContext context) {
    // No AppBar — the thread's own header carries the back chevron + name, so the
    // name isn't duplicated. Body slides up; header is instant.
    return Scaffold(
      backgroundColor: StaffUi.pageBg,
      body: SafeArea(
        child: StaffThreadView(
          conversation: conversation,
          onBack: () => Navigator.of(context).pop(),
          animateIn: true,
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  Thread view — messages + realtime + composer.
// ════════════════════════════════════════════════════════════════════════════
class StaffThreadView extends ConsumerStatefulWidget {
  final StaffConversation conversation;
  // Mobile full-screen thread: renders a back chevron in the header and slides
  // the message body up on open (the header stays put — no page-level slide).
  final VoidCallback? onBack;
  final bool animateIn;
  const StaffThreadView({
    super.key,
    required this.conversation,
    this.onBack,
    this.animateIn = false,
  });

  @override
  ConsumerState<StaffThreadView> createState() => _StaffThreadViewState();
}

class _StaffThreadViewState extends ConsumerState<StaffThreadView> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <StaffMessage>[];
  final _seenIds = <String>{};
  RealtimeChannel? _channel;
  bool _loading = true;
  bool _sending = false;
  // Set the instant this staff ends the chat, so the thread flips to its ended
  // state immediately even on mobile (where the pushed screen holds a stale,
  // still-"open" conversation object that the list refresh can't update).
  bool _ended = false;
  // The citizen's profile photo (non-anonymous only), fetched once on open.
  String? _citizenPhotoUrl;

  // ── Inactivity auto-end ────────────────────────────────────────────────────
  // If the citizen goes quiet, warn them, then auto-close so the staff isn't
  // held on a dead chat. Both timers reset on every citizen message.
  static const _kIdleWarn = Duration(minutes: 1);
  static const _kIdleEnd = Duration(minutes: 5);
  Timer? _idleWarnTimer;
  Timer? _idleEndTimer;
  bool _idleWarned = false;

  StaffRepository get _repo => ref.read(staffRepoProvider);

  /// A staff message counts as "seen" once the citizen has sent anything after
  /// it — messages are ordered oldest-first, so any later citizen message means
  /// they were in the chat and read it. (There's no read-receipt column.)
  bool _isSeen(int i) {
    for (var j = i + 1; j < _messages.length; j++) {
      final mj = _messages[j];
      if (!mj.isStaff && !mj.isBot) return true;
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _idleWarnTimer?.cancel();
    _idleEndTimer?.cancel();
    _channel?.unsubscribe();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Restarts the inactivity clock — called after load and on every citizen
  /// message. Only arms on an active (assigned, not ended) chat.
  void _resetIdle() {
    _idleWarnTimer?.cancel();
    _idleEndTimer?.cancel();
    _idleWarned = false;
    final c = widget.conversation;
    if (_ended || c.isResolved || c.isWaiting) return;
    _idleWarnTimer = Timer(_kIdleWarn, _onIdleWarn);
  }

  void _onIdleWarn() {
    if (!mounted || _ended || widget.conversation.isResolved) return;
    if (_idleWarned) return;
    _idleWarned = true;
    // A gentle nudge the citizen sees too (sent as a normal message).
    _sendText('⏳ Are you still there po? This chat will automatically end in '
        '5 minutes if there\'s no reply. 🙏');
    _idleEndTimer = Timer(_kIdleEnd, () {
      if (!mounted || _ended || widget.conversation.isResolved) return;
      _closeChat(auto: true);
    });
  }

  Future<void> _load() async {
    try {
      final msgs = await _repo.fetchMessages(widget.conversation.id);
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(msgs);
        _seenIds
          ..clear()
          ..addAll(msgs.map((m) => m.id));
        _loading = false;
      });
      _subscribe();
      _jumpToBottom();
      _maybeAutoGreet();
      _resetIdle();
      _loadCitizenPhoto();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Loads the citizen's real photo (non-anonymous chats only) so their header +
  /// bubbles show their face instead of an initial.
  Future<void> _loadCitizenPhoto() async {
    if (widget.conversation.isAnonymous) return;
    final url = await _repo.fetchCitizenPhoto(widget.conversation.id);
    if (url != null && mounted) setState(() => _citizenPhotoUrl = url);
  }

  /// Sends a personalised greeting automatically the first time a staff member
  /// opens an active, assigned live chat — so the citizen who just got connected
  /// immediately sees "Hi po! I'm Mark from the Engineering Office…" without the
  /// staff having to tap anything. Fires once: skipped if any staff message
  /// already exists, if the chat is still unclaimed (Waiting), or if it's ended.
  Future<void> _maybeAutoGreet() async {
    final c = widget.conversation;
    if (c.isWaiting || c.isResolved) return;
    if (_messages.any((m) => m.isStaff)) return;
    final id = ref.read(staffIdentityProvider).valueOrNull;
    if (id == null) return;
    // Only the staff the chat is assigned to greets — a colleague peeking at the
    // same department chat must not fire a second greeting.
    if (c.assignedStaffId != null && c.assignedStaffId != id.userId) return;
    await _sendText(_composeGreeting(id.displayName, id.department));
  }

  /// "Hi po! I'm {name} from the {department}. How may I help you today? 😊",
  /// gracefully dropping whichever part is missing.
  String _composeGreeting(String? name, String? department) {
    final n = (name ?? '').trim();
    final d = (department ?? '').trim();
    if (n.isEmpty) return 'Hi po! How may I help you today? 😊';
    final from = d.isEmpty ? '' : ' from the $d';
    return "Hi po! I'm $n$from. How may I help you today? 😊";
  }

  void _subscribe() {
    _channel = _repo.subscribeMessages(widget.conversation.id, (m) {
      if (!mounted || _seenIds.contains(m.id)) return;
      setState(() {
        _seenIds.add(m.id);
        _messages.add(m);
      });
      _jumpToBottom();
      // A citizen reply restarts the inactivity clock.
      if (!m.isStaff && !m.isBot) _resetIdle();
    });
  }

  void _jumpToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() => _sendText(_input.text, clearInput: true);

  /// Optimistic send (Messenger-style): the bubble appears instantly in a
  /// `sending` state — only this staff sees it until the DB write lands, at
  /// which point realtime delivers it to the citizen too. A failed write flips
  /// the bubble to `failed`, offering resend/delete via [_resend]/[_deleteLocal].
  Future<void> _sendText(String raw, {bool clearInput = false}) async {
    final text = raw.trim();
    if (text.isEmpty) return;
    if (clearInput) _input.clear();
    final optimistic = StaffMessage(
      id: 'local-${DateTime.now().microsecondsSinceEpoch}',
      senderType: 'staff',
      message: text,
      createdAt: DateTime.now(),
      sendState: StaffMsgSend.sending,
    );
    setState(() {
      _messages.add(optimistic);
      _seenIds.add(optimistic.id);
    });
    _jumpToBottom();
    await _deliver(optimistic);
  }

  /// Writes an optimistic message to the DB and reconciles it: swaps the temp
  /// bubble for the persisted row on success (deduping against any realtime
  /// echo that already arrived), or marks it `failed` on error.
  Future<void> _deliver(StaffMessage optimistic) async {
    try {
      final msg = await _repo.sendMessage(widget.conversation.id, optimistic.message);
      if (!mounted) return;
      setState(() {
        final idx = _messages.indexWhere((m) => identical(m, optimistic));
        _seenIds.remove(optimistic.id);
        if (_seenIds.contains(msg.id)) {
          // Realtime already appended the real row — just drop the temp.
          if (idx >= 0) _messages.removeAt(idx);
        } else {
          _seenIds.add(msg.id);
          if (idx >= 0) {
            _messages[idx] = msg;
          } else {
            _messages.add(msg);
          }
        }
      });
      _jumpToBottom();
    } catch (_) {
      if (mounted) setState(() => optimistic.sendState = StaffMsgSend.failed);
    }
  }

  void _resend(StaffMessage m) {
    setState(() => m.sendState = StaffMsgSend.sending);
    _deliver(m);
  }

  void _deleteLocal(StaffMessage m) {
    setState(() {
      _messages.remove(m);
      _seenIds.remove(m.id);
    });
  }

  /// Ends the conversation: flips the ticket to `closed` (a chat is ended, not
  /// "resolved" like a report). The citizen app watches the status and shows its
  /// star-rating card on close; the staff thread shows an inline "Chat ended"
  /// notice + the citizen's stars once they rate. No goodbye chat-bubble is
  /// sent — the closure is a system notice on both sides, not a message.
  Future<void> _endChat() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('End this chat?',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
        content: const Text(
            'The citizen will be asked to rate the chat. You can still find it '
            'under History.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(foregroundColor: StaffUi.textSecondary),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: StaffUi.accent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('End chat'),
          ),
        ],
      ),
    );
    if (confirm != true || _sending) return;
    await _closeChat(auto: false);
  }

  /// Flips the ticket to `closed` and stops the inactivity clock. [auto] is true
  /// when the inactivity timer fired it (no staff tap) — the snackbar wording
  /// reflects that.
  Future<void> _closeChat({required bool auto}) async {
    if (_sending || _ended || widget.conversation.isResolved) return;
    _idleWarnTimer?.cancel();
    _idleEndTimer?.cancel();
    setState(() => _sending = true);
    try {
      await ref
          .read(staffConversationsProvider.notifier)
          .setStatus(widget.conversation.id, 'closed');
      if (mounted) {
        setState(() => _ended = true);
        showAppSnackBar(context,
            auto ? 'Chat auto-ended after inactivity.' : 'Chat ended.',
            type: AppSnackType.success);
      }
    } catch (e) {
      if (mounted) showAppSnackBar(context, '$e', type: AppSnackType.error);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _claim() async {
    await ref
        .read(staffConversationsProvider.notifier)
        .claim(widget.conversation.id);
    if (mounted) {
      showAppSnackBar(context, 'You claimed this conversation.',
          type: AppSnackType.success);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.conversation;
    final identity = ref.watch(staffIdentityProvider).valueOrNull;
    final staffName = identity?.displayName;
    final department = identity?.department;
    final resolved = c.isResolved || _ended;

    return Column(
      children: [
        _Header(
          conversation: c,
          ended: resolved,
          citizenPhotoUrl: _citizenPhotoUrl,
          onEnd: _endChat,
          onClaim: _claim,
          onBack: widget.onBack,
        ),
        const Divider(height: 1, color: StaffUi.border),
        if (c.isAnonymous) const _AnonymityBanner(),
        Expanded(
          // On wide panes the chat column is capped + centred (like Slack), so
          // bubbles don't stretch across a huge desktop pane. Bubbles size off
          // this local width, not the whole window.
          child: LayoutBuilder(
            builder: (context, cons) {
              const maxContent = 820.0;
              final contentW =
                  cons.maxWidth < maxContent ? cons.maxWidth : maxContent;
              final bubbleMax = contentW * 0.74;

              final Widget body = _loading
                  ? const _ThreadSkeleton()
                  : (_messages.isEmpty && !resolved)
                      ? const StaffEmptyState(
                          icon: Icons.waving_hand_outlined,
                          title: 'Say hello',
                          subtitle:
                              'No messages yet — send the first reply below.',
                        )
                      : ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.all(16),
                          itemCount: _messages.length + (resolved ? 1 : 0),
                          itemBuilder: (_, i) {
                            if (i >= _messages.length) {
                              return _EndedNotice(rating: c.rating);
                            }
                            final m = _messages[i];
                            return _Bubble(
                              message: m,
                              maxWidth: bubbleMax,
                              seen: m.isStaff && _isSeen(i),
                              citizenLabel: c.citizenLabel,
                              citizenAnonymous: c.isAnonymous,
                              citizenPhotoUrl: _citizenPhotoUrl,
                              staffPhotoUrl: identity?.photoUrl,
                              staffInitials: identity?.initials ?? 'S',
                              onResend: () => _resend(m),
                              onDelete: () => _deleteLocal(m),
                            );
                          },
                        );
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: maxContent),
                  child: widget.animateIn ? _SlideUpOnce(child: body) : body,
                ),
              );
            },
          ),
        ),
        if (!resolved)
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _QuickReplies(
                    staffName: staffName,
                    department: department,
                    enabled: !_sending,
                    onPick: (t) => _sendText(t),
                  ),
                  _Composer(
                    controller: _input,
                    sending: _sending,
                    onSend: _send,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Tappable canned replies above the composer — a staff member can greet and
/// respond with one tap. The greeting is personalised with the staff name.
class _QuickReplies extends StatelessWidget {
  final String? staffName;
  final String? department;
  final bool enabled;
  final ValueChanged<String> onPick;
  const _QuickReplies({
    required this.staffName,
    required this.department,
    required this.enabled,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final name = (staffName ?? '').trim();
    final dept = (department ?? '').trim();
    final greeting = name.isEmpty
        ? 'Hi po! How may I help you today? 😊'
        : "Hi po! I'm $name${dept.isEmpty ? '' : ' from the $dept'}. "
            'How may I help you today? 😊';
    final replies = <String>[
      greeting,
      'Please give me a moment to check po. 🙏',
      'Could you share more details po?',
      'Salamat po for your patience!',
      'Is there anything else I can help with po?',
    ];
    // Shorten the greeting for its chip label; send the full text.
    final chips = [
      for (var i = 0; i < replies.length; i++)
        _chip(i == 0 ? 'Greeting 👋' : replies[i], replies[i]),
    ];
    return Container(
      color: StaffUi.surface,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
      // A horizontal strip can't be swiped with a mouse, so on web the chips
      // WRAP onto multiple lines (nothing gets clipped); the phone app keeps
      // them in a single swipeable row to save vertical space.
      child: kIsWeb
          ? Wrap(spacing: 8, runSpacing: 8, children: chips)
          : SizedBox(
              height: 34,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: chips.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) => chips[i],
              ),
            ),
    );
  }

  Widget _chip(String label, String full) {
    return Material(
      color: StaffUi.accentWash,
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        borderRadius: BorderRadius.circular(17),
        onTap: enabled ? () => onPick(full) : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: StaffUi.accent.withValues(alpha: 0.30)),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: StaffUi.accent,
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final StaffConversation conversation;
  final bool ended;
  final String? citizenPhotoUrl;
  final VoidCallback onEnd;
  final VoidCallback onClaim;
  // Non-null only on the mobile full-screen thread — renders a back chevron so
  // the header doubles as the app bar (no separate AppBar, no duplicated name).
  final VoidCallback? onBack;
  const _Header({
    required this.conversation,
    required this.ended,
    required this.citizenPhotoUrl,
    required this.onEnd,
    required this.onClaim,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final c = conversation;
    return Container(
      color: StaffUi.surface,
      padding: EdgeInsets.fromLTRB(onBack != null ? 12 : 16, 12, 16, 12),
      child: Row(
        children: [
          if (onBack != null) ...[
            // Mirrors the citizen chat header chevron: rounded square, subtle
            // fill + border, accent-coloured chevron.
            GestureDetector(
              onTap: onBack,
              child: Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: StaffUi.subtle,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: StaffUi.border),
                ),
                child: const Icon(Icons.arrow_back_ios_new_rounded,
                    size: 18, color: StaffUi.accent),
              ),
            ),
            const SizedBox(width: 12),
          ],
          // The other party's avatar — the citizen's photo/initial, or a default
          // person icon when the chat is anonymous.
          _CitizenAvatar(
            label: c.citizenLabel,
            bot: false,
            anonymous: c.isAnonymous,
            photoUrl: citizenPhotoUrl,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        c.citizenLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: StaffUi.textPrimary,
                        ),
                      ),
                    ),
                    if (c.isAnonymous) ...[
                      const SizedBox(width: 8),
                      const StaffPill(
                        label: 'Anonymous',
                        color: StaffUi.textMuted,
                        icon: Icons.visibility_off_rounded,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${c.category}'
                  '${(c.shownNumber ?? '').isNotEmpty ? ' · ${c.shownNumber}' : ''}'
                  '${c.referenceCode != null ? ' · ${c.referenceCode}' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: StaffUi.textMuted),
                ),
              ],
            ),
          ),
          if (ended)
            const StaffPill(label: 'Ended', color: StaffUi.textMuted)
          else if (c.isWaiting)
            TextButton.icon(
              onPressed: onClaim,
              icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
              label: const Text('Claim'),
              style: TextButton.styleFrom(foregroundColor: StaffUi.accent),
            )
          else
            TextButton.icon(
              onPressed: onEnd,
              icon: const Icon(Icons.flag_circle_outlined, size: 18),
              label: const Text('End chat'),
              style: TextButton.styleFrom(foregroundColor: StaffUi.danger),
            ),
        ],
      ),
    );
  }
}

/// A Messenger-style chat row: the other party's avatar sits to the left of an
/// incoming bubble, the staff's own avatar to the right of an outgoing one, with
/// a timestamp + delivery ticks under the staff's messages.
class _Bubble extends StatelessWidget {
  final StaffMessage message;
  final double maxWidth;
  final bool seen;
  final String citizenLabel;
  final bool citizenAnonymous;
  final String? citizenPhotoUrl;
  final String? staffPhotoUrl;
  final String staffInitials;
  final VoidCallback onResend;
  final VoidCallback onDelete;
  const _Bubble({
    required this.message,
    required this.maxWidth,
    required this.seen,
    required this.citizenLabel,
    required this.citizenAnonymous,
    required this.citizenPhotoUrl,
    required this.staffPhotoUrl,
    required this.staffInitials,
    required this.onResend,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final m = message;
    final mine = m.isStaff;
    final failed = m.sendState == StaffMsgSend.failed;
    final sending = m.sendState == StaffMsgSend.sending;
    final bg = mine
        ? (failed ? StaffUi.danger.withValues(alpha: 0.85) : StaffUi.accent)
        : (m.isBot ? StaffUi.subtle : StaffUi.surface);
    final fg = mine ? Colors.white : StaffUi.textPrimary;

    final bubble = Opacity(
      opacity: sending ? 0.65 : 1,
      child: Container(
        constraints: BoxConstraints(maxWidth: maxWidth),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(mine ? 16 : 4),
            bottomRight: Radius.circular(mine ? 4 : 16),
          ),
          border: mine ? null : Border.all(color: StaffUi.border),
        ),
        child: Text(m.message,
            style: TextStyle(fontSize: 13.5, color: fg, height: 1.35)),
      ),
    );

    // Failed → an inline retry/delete affordance instead of ticks.
    final Widget meta = mine && failed
        ? Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded,
                    size: 12, color: StaffUi.danger),
                const SizedBox(width: 3),
                const Text('Not sent',
                    style: TextStyle(fontSize: 10, color: StaffUi.danger)),
                const SizedBox(width: 8),
                _MetaAction(label: 'Retry', onTap: onResend),
                const SizedBox(width: 4),
                _MetaAction(label: 'Delete', onTap: onDelete),
              ],
            ),
          )
        : Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(sending ? 'Sending…' : staffAgo(m.createdAt),
                    style:
                        const TextStyle(fontSize: 9.5, color: StaffUi.textMuted)),
                if (mine && !sending) ...[
                  const SizedBox(width: 4),
                  _Ticks(seen: seen),
                ],
              ],
            ),
          );

    final avatar = mine
        ? _StaffAvatar(photoUrl: staffPhotoUrl, initials: staffInitials)
        : _CitizenAvatar(
            label: citizenLabel,
            bot: m.isBot,
            anonymous: citizenAnonymous,
            photoUrl: citizenPhotoUrl,
          );

    // Avatar pinned to a fixed edge column (right for staff, left for the
    // citizen) so it never drifts with the bubble width — Messenger-style. The
    // meta line sits under the bubble, clearing the avatar gutter (28 + 8).
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment:
                mine ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: mine
                ? [Flexible(child: bubble), const SizedBox(width: 8), avatar]
                : [avatar, const SizedBox(width: 8), Flexible(child: bubble)],
          ),
          Padding(
            padding: EdgeInsets.only(
                top: 3, left: mine ? 0 : 36, right: mine ? 36 : 0),
            child: meta,
          ),
        ],
      ),
    );
  }
}

/// Double-check delivery ticks under a staff message — grey once sent, teal once
/// the citizen has replied (our best proxy for "seen", no read-receipt column).
class _Ticks extends StatelessWidget {
  final bool seen;
  const _Ticks({required this.seen});

  @override
  Widget build(BuildContext context) {
    final color = seen ? StaffUi.accent : StaffUi.textMuted;
    return SizedBox(
      width: 16,
      height: 11,
      child: Stack(
        children: [
          Positioned(
              left: 0,
              child: Icon(Icons.check_rounded, size: 11, color: color)),
          Positioned(
              left: 5,
              child: Icon(Icons.check_rounded, size: 11, color: color)),
        ],
      ),
    );
  }
}

/// A quiet reminder shown atop an anonymous chat so staff don't try to draw out
/// the citizen's identity — the reporter chose to stay anonymous.
class _AnonymityBanner extends StatelessWidget {
  const _AnonymityBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: StaffUi.warn.withValues(alpha: 0.08),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.visibility_off_rounded,
              size: 15, color: StaffUi.warn),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              "This citizen is anonymous — please don't ask for their name, "
              'number, or address.',
              style: TextStyle(fontSize: 11.5, color: StaffUi.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// One-shot slide-up + fade for the message body when the mobile thread opens,
/// so the header appears instantly while the conversation eases up into place.
class _SlideUpOnce extends StatelessWidget {
  final Widget child;
  const _SlideUpOnce({required this.child});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      builder: (_, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, (1 - t) * 24), child: child),
      ),
      child: child,
    );
  }
}

/// A pulsing placeholder shown while a thread's messages load — a few alternating
/// bubble shapes instead of a bare spinner.
class _ThreadSkeleton extends StatefulWidget {
  const _ThreadSkeleton();
  @override
  State<_ThreadSkeleton> createState() => _ThreadSkeletonState();
}

class _ThreadSkeletonState extends State<_ThreadSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // (mine, widthFactor) — a believable back-and-forth of bubbles.
    const rows = <(bool, double)>[
      (false, 0.5),
      (true, 0.6),
      (false, 0.42),
      (true, 0.38),
      (false, 0.55),
      (true, 0.3),
    ];
    // Size the placeholder bars off the LOCAL width so they never overflow the
    // centered max-width column on wide desktop panes.
    return LayoutBuilder(
      builder: (context, cons) {
        final w0 = cons.maxWidth - 32; // minus ListView padding
        return FadeTransition(
          opacity: Tween(begin: 0.45, end: 0.9).animate(_c),
          child: ListView(
            padding: const EdgeInsets.all(16),
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (final (mine, w) in rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Row(
                    mainAxisAlignment:
                        mine ? MainAxisAlignment.end : MainAxisAlignment.start,
                    children: [
                      if (!mine) _dot(),
                      if (!mine) const SizedBox(width: 8),
                      Container(
                        height: 34,
                        width: w0 * w,
                        decoration: BoxDecoration(
                          color: StaffUi.subtle,
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      if (mine) const SizedBox(width: 8),
                      if (mine) _dot(),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _dot() => Container(
        width: 28,
        height: 28,
        decoration:
            const BoxDecoration(color: StaffUi.subtle, shape: BoxShape.circle),
      );
}

/// Tiny tappable label (Retry / Delete) shown under a failed message.
class _MetaAction extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _MetaAction({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        child: Text(label,
            style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: StaffUi.accent)),
      ),
    );
  }
}

/// The citizen's (or bot's) avatar shown beside incoming bubbles. An anonymous
/// citizen gets a neutral default person icon (no initial that could hint at a
/// name); the bot gets a robot icon; everyone else shows their name initial.
class _CitizenAvatar extends StatelessWidget {
  final String label;
  final bool bot;
  final bool anonymous;
  final String? photoUrl;
  const _CitizenAvatar({
    required this.label,
    required this.bot,
    required this.anonymous,
    this.photoUrl,
  });

  @override
  Widget build(BuildContext context) {
    if (bot) {
      return _circle(
        StaffUi.subtle,
        const Icon(Icons.smart_toy_rounded, size: 15, color: StaffUi.textMuted),
      );
    }
    // Anonymous → default person icon (never the real photo/initial).
    if (anonymous) {
      return _circle(
        StaffUi.subtle,
        const Icon(Icons.person_rounded, size: 16, color: StaffUi.textMuted),
      );
    }
    if (photoUrl != null && photoUrl!.isNotEmpty) {
      return Container(
        width: 28,
        height: 28,
        decoration: const BoxDecoration(shape: BoxShape.circle),
        clipBehavior: Clip.antiAlias,
        child: CachedNetworkImage(
          imageUrl: photoUrl!,
          fit: BoxFit.cover,
          errorWidget: (_, _, _) => _initial(),
        ),
      );
    }
    return _initial();
  }

  Widget _initial() {
    final t = label.trim();
    final ch = t.isEmpty ? 'C' : t.substring(0, 1).toUpperCase();
    return _circle(
      StaffUi.accent.withValues(alpha: 0.12),
      Text(ch,
          style: const TextStyle(
              fontSize: 12, fontWeight: FontWeight.w700, color: StaffUi.accent)),
    );
  }

  Widget _circle(Color bg, Widget child) => Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: child,
      );
}

/// The staff member's own avatar shown beside outgoing bubbles.
class _StaffAvatar extends StatelessWidget {
  final String? photoUrl;
  final String initials;
  const _StaffAvatar({required this.photoUrl, required this.initials});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration:
          const BoxDecoration(color: StaffUi.accentWash, shape: BoxShape.circle),
      clipBehavior: Clip.antiAlias,
      child: (photoUrl != null && photoUrl!.isNotEmpty)
          ? CachedNetworkImage(
              imageUrl: photoUrl!,
              fit: BoxFit.cover,
              errorWidget: (_, _, _) => _mono(),
            )
          : _mono(),
    );
  }

  Widget _mono() => Center(
        child: Text(initials,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: StaffUi.accent)),
      );
}

/// Inline "Chat ended" system notice + the citizen's rating (once they submit),
/// shown at the tail of a closed conversation instead of a goodbye bubble.
class _EndedNotice extends StatelessWidget {
  final int? rating;
  const _EndedNotice({required this.rating});

  @override
  Widget build(BuildContext context) {
    final rated = rating != null && rating! > 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: StaffUi.subtle,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle_rounded, size: 14, color: StaffUi.online),
                SizedBox(width: 6),
                Text('Chat ended',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: StaffUi.textSecondary)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (rated) ...[
            const Text('Citizen rated this chat',
                style: TextStyle(fontSize: 11.5, color: StaffUi.textMuted)),
            const SizedBox(height: 5),
            StaffStarRow(rating!, size: 20),
          ] else
            const Text('Waiting for the citizen to rate…',
                style: TextStyle(fontSize: 11.5, color: StaffUi.textMuted)),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;
  const _Composer({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: StaffUi.surface,
      padding: EdgeInsets.fromLTRB(
        12,
        10,
        12,
        10 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Focus(
                onKeyEvent: (node, event) {
                  // Enter sends; Shift+Enter inserts a newline.
                  if (event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.enter &&
                      !HardwareKeyboard.instance.isShiftPressed) {
                    if (!sending) onSend();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.newline,
                  style: const TextStyle(fontSize: 14, color: StaffUi.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Type a reply…',
                  hintStyle: const TextStyle(color: StaffUi.textMuted, fontSize: 14),
                  filled: true,
                  fillColor: StaffUi.subtle,
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: const BorderSide(color: StaffUi.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: const BorderSide(color: StaffUi.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: const BorderSide(color: StaffUi.accent, width: 1.4),
                  ),
                ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Material(
              color: StaffUi.accent,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: sending ? null : onSend,
                child: Padding(
                  padding: const EdgeInsets.all(11),
                  child: sending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      // Same send glyph as the citizen chat for consistency.
                      : Image.asset(
                          'assets/images/send.webp',
                          width: 20,
                          height: 20,
                          fit: BoxFit.contain,
                          color: Colors.white,
                          colorBlendMode: BlendMode.srcIn,
                          errorBuilder: (_, _, _) => const Icon(
                              Icons.send_rounded,
                              color: Colors.white,
                              size: 20),
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
