import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show HardwareKeyboard, KeyDownEvent, LogicalKeyboardKey;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../services/chat_service.dart';
import '../../../theme/app_colors.dart';
import 'chat_bubbles_model.dart';
import 'chat_bubbles_widget.dart';
import '../Chat-agent/chat_models.dart' as cm;
import '../Chat-agent/chat_models.dart' show ConversationStage;

const _kTextPri = Color(0xFF111827);

/// Floating bubble chat panel.
///
/// All conversation state lives in [ChatService.I] — this widget is now a
/// pure view that listens to the service and forwards user actions to it.
class HomeChatPanelCard extends StatefulWidget {
  final VoidCallback onAgentMessage;
  final double panelW;
  final double panelH;

  /// Extra controls pinned to the right of the header — minimise, close, and
  /// anything else the host window needs.
  ///
  /// Empty by default, which is exactly what the draggable bubble wants: it owns
  /// its own dismissal, so its header is title-only and unchanged. The shell's
  /// docked window supplies its own controls here rather than drawing a second
  /// header on top of this one.
  final List<Widget> headerActions;

  /// Corner radius of the card. The floating bubble is a free-floating rounded
  /// card; a docked window wants square bottom corners where it meets the edge.
  final BorderRadius borderRadius;

  /// Widest a single message bubble may get, for BOTH sides of the thread.
  ///
  /// 240 is what every caller rendered before this was a parameter, so leaving
  /// it alone is byte-identical: the mobile bubble and the wide docked window
  /// both pass nothing and keep it.
  ///
  /// The citizen shell's full-screen sheet is the one caller that raises it.
  /// Below 600 that sheet spans the whole viewport, and a 240 bubble in a
  /// ~600-wide column reads as a thin ribbon down one side rather than a chat.
  final double bubbleMaxWidth;

  const HomeChatPanelCard({
    super.key,
    required this.onAgentMessage,
    required this.panelW,
    required this.panelH,
    this.headerActions = const [],
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
    this.bubbleMaxWidth = 240,
  });

  @override
  State<HomeChatPanelCard> createState() => _HomeChatPanelCardState();
}

class _HomeChatPanelCardState extends State<HomeChatPanelCard> {
  final _scrollCtrl = ScrollController();
  final _focusNode = FocusNode();
  final _textCtrl = TextEditingController();
  final _textFieldKey = GlobalKey();

  // ── Track agent-message arrivals so we can notify the bubble (unread badge)
  int _lastSeenMsgCount = 0;

  /// Stars picked in the post-chat rating card, 0 = none yet.
  int _ratingStars = 0;

  /// Whether that card was showing on the previous rebuild, so a FRESH card
  /// always starts empty instead of inheriting the last conversation's stars.
  /// Same false→true edge ChatAgentScreen resets on.
  bool _wasShowingRating = false;

  /// The citizen's own profile photo, for their outgoing bubbles.
  String? _myPhotoUrl;

  @override
  void initState() {
    super.initState();

    // Subscribe to the single source of truth.
    ChatService.I.addListener(_onChatChanged);
    ChatService.I.onChatOpened();

    _lastSeenMsgCount = ChatService.I.messages.length;
    _loadMyPhoto();
    _scrollDownSoon();
  }

  Future<void> _loadMyPhoto() async {
    try {
      final client = Supabase.instance.client;
      final uid = client.auth.currentUser?.id;
      if (uid == null) return;
      final cd = await client
          .from('citizen_details')
          .select('profile_photo_path')
          .eq('user_id', uid)
          .maybeSingle();
      final path = (cd?['profile_photo_path'] as String?)?.trim() ?? '';
      if (path.isEmpty || !mounted) return;
      setState(() => _myPhotoUrl =
          client.storage.from('profile-photos').getPublicUrl(path));
    } catch (_) {/* default icon */}
  }

  @override
  void dispose() {
    ChatService.I.removeListener(_onChatChanged);
    ChatService.I.onChatClosed();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    _textCtrl.dispose();
    super.dispose();
  }

  /// Called every time ChatService notifies — rebuilds the panel
  /// and scrolls to the latest message.
  void _onChatChanged() {
    if (!mounted) return;

    final messages = ChatService.I.messages;

    // If a new agent message arrived, ping the bubble so it can flash
    // the unread badge (matches your old onAgentMessage contract).
    if (messages.length > _lastSeenMsgCount) {
      final newest = messages.last;
      if (!newest.isUser) widget.onAgentMessage();
    }
    _lastSeenMsgCount = messages.length;

    // Reset the picked stars each time a fresh rating card appears, so a new
    // conversation never inherits the previous chat's selection.
    final showingRating = ChatService.I.showRatingBar;
    if (showingRating && !_wasShowingRating) _ratingStars = 0;
    _wasShowingRating = showingRating;

    setState(() {});
    _scrollDownSoon();
  }

  void _scrollDownSoon() {
    Future.delayed(const Duration(milliseconds: 80), () {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _fmtTime(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m ${t.hour >= 12 ? "PM" : "AM"}';
  }

  void _send() {
    // Guard: don't send while agent is mid-reply.
    if (ChatService.I.isAgentTyping) return;

    final text = _textCtrl.text;
    if (text.trim().isEmpty) return;

    _textCtrl.value = const TextEditingValue(
      text: '',
      selection: TextSelection.collapsed(offset: 0),
      composing: TextRange.empty,
    );

    ChatService.I.sendUserText(text);
  }

  // ── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.panelW,
      height: widget.panelH,
      child: Material(
        color: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: widget.borderRadius,
            border: Border.all(color: AppColors.stroke, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.14),
                blurRadius: 32,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: widget.borderRadius,
            child: Column(
              children: [
                _buildHeader(),
                const Divider(
                  height: 1,
                  thickness: 1,
                  color: Color(0xFFE3E6EF),
                ),
                Expanded(child: _buildMessages()),

                if (ChatService.I.showIntentChips) _buildIntentChips(),
                if (ChatService.I.showBackToMenu) _buildBackToMenu(),
                if (ChatService.I.showCategoryChips) _buildCategoryChips(),

                const Divider(
                  height: 1,
                  thickness: 1,
                  color: Color(0xFFE3E6EF),
                ),

                // ── Terminal stages show a card instead of the input bar, so
                // the user has a clear next action. The rating card comes first:
                // `ended` is a terminal stage too, and a citizen whose chat the
                // staff just closed is being ASKED for something here.
                if (ChatService.I.showRatingBar)
                  _buildRatingCard()
                else if (ChatService.I.isTerminal)
                  _buildTerminalCard()
                else
                  _buildInput(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Post-chat rating card ────────────────────────────────────────────────
  // The compact sibling of ChatAgentScreen's full-width card. It has to exist
  // in BOTH places: this panel is the whole chat for anyone using the floating
  // bubble or the web docked window, and without it a chat the staff ended left
  // the panel with no composer and no card at all — a dead strip. The rating
  // then only showed up if the citizen happened to open the full chat screen,
  // which is what "the rating only appears after I move between screens" was.
  //
  // Trimmed, not redesigned: no hero icon, no "Need more help?" (the terminal
  // card's "Start new conversation" covers it one tap later), because this card
  // lives in a 360×520 window and has to fit under the thread, not replace it.
  Widget _buildRatingCard() {
    const tint = AppColors.primaryBlue;
    final selected = _ratingStars;
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'How was your chat?',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: _kTextPri,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) {
              final star = i + 1;
              final active = star <= selected;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _ratingStars = star),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Icon(
                    active ? Icons.star_rounded : Icons.star_outline_rounded,
                    size: 26,
                    color: active ? const Color(0xFFF5A623) : AppColors.stroke,
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: selected == 0
                      ? null
                      : () => ChatService.I.submitRating(selected),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: tint,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: tint.withValues(alpha: 0.35),
                    disabledForegroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: const Text('Submit rating'),
                ),
              ),
              const SizedBox(width: 8),
              // Skip never blocks the citizen behind a rating they don't want
              // to give — it dismisses the card and leaves the chat ended.
              TextButton(
                onPressed: () => ChatService.I.dismissRating(),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.hint,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                child: const Text(
                  'Skip',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Terminal-state card ──────────────────────────────────────────────────
  // Shown when the conversation is in ticketCreated / connectedToAgent /
  // ended / timedOut. Replaces the input bar with context + a clear CTA.
  Widget _buildTerminalCard() {
    final stage = ChatService.I.stage;
    final reference = ChatService.I.lastTicketReference;

    // Stage-specific copy and icon
    late final IconData icon;
    late final Color tint;
    late final String title;
    late final String subtitle;

    switch (stage) {
      case ConversationStage.ticketCreated:
        icon = Icons.check_circle_rounded;
        tint = AppColors.green;
        title = 'Ticket submitted';
        subtitle = reference != null
            ? 'Reference: $reference'
            : 'Your concern has been logged.';
        break;
      case ConversationStage.connectedToAgent:
        icon = Icons.support_agent_rounded;
        tint = AppColors.primaryBlue;
        title = 'Connected to staff';
        subtitle = 'An LGU agent is handling your concern.';
        break;
      case ConversationStage.timedOut:
        icon = Icons.timer_off_rounded;
        tint = AppColors.hint;
        title = 'Session ended';
        subtitle = 'No activity for 15 minutes.';
        break;
      // `ended` fell through to the default below, so a chat the staff closed
      // left this panel showing NOTHING where the composer had been: no notice,
      // no rating, no way forward. It is a terminal stage like the three above
      // and gets the same treatment. Reached once the citizen has rated or
      // skipped — before that, _buildRatingCard has the slot.
      case ConversationStage.ended:
        icon = Icons.check_circle_outline_rounded;
        tint = AppColors.hint;
        title = 'Chat ended';
        subtitle = ChatService.I.submittedRating > 0
            ? 'Thank you for your feedback.'
            : 'The staff member has closed this conversation.';
        break;
      default:
        return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: tint, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _kTextPri,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 11.5, color: AppColors.hint),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (stage == ConversationStage.ticketCreated) ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => ChatService.I.requestLiveAgent(),
                icon: const Icon(Icons.support_agent_rounded, size: 16),
                label: const Text('Talk to a person'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primaryBlue,
                  side: const BorderSide(color: AppColors.primaryBlue),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => ChatService.I.startNewConversation(),
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Start new conversation'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Header ───────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    const double avatarSize = 38;
    // Swap the bot identity for the live staff member once connected.
    final connected = ChatService.I.isConnectedToStaff;
    final staffName = ChatService.I.connectedStaffName;
    final staffPhoto = ChatService.I.connectedStaffPhotoUrl;
    final dept = ChatService.I.connectedDepartment;
    final title = connected
        ? ((staffName?.trim().isNotEmpty ?? false)
            ? staffName!.trim()
            : (dept != null ? '$dept staff' : 'LGU Staff'))
        : 'LGU Aparri Agent';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
      child: Row(
        children: [
          ChatAgentAvatar(
            size: avatarSize,
            photoUrl: connected ? staffPhoto : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _kTextPri,
                    letterSpacing: -0.2,
                  ),
                ),
                Text(
                  connected ? 'Online · Connected to a person' : 'Online',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.green,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          ...widget.headerActions,
        ],
      ),
    );
  }

  // ── Messages list ────────────────────────────────────────────────────────
  Widget _buildMessages() {
    final messages = ChatService.I.messages;
    final isTyping = ChatService.I.isAgentTyping;
    final count = messages.length + (isTyping ? 1 : 0);

    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      itemCount: count,
      itemBuilder: (_, i) {
        if (i == messages.length && isTyping) return _typingBubble();
        final msg = messages[i];
        return _bubbleRow(msg);
      },
    );
  }

  /// Maps cm.MessageStatus → MessageStatus (the model used by ChatStatusTicks).
  /// Both enums have the same order, so .index is safe.
  MessageStatus _mapStatus(cm.MessageStatus s) => MessageStatus.values[s.index];

  Widget _bubbleRow(cm.ChatMsg msg) {
    final isUser = msg.isUser;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser)
            Padding(
              padding: const EdgeInsets.only(right: 7),
              child: ChatAgentAvatar(
                photoUrl:
                    msg.fromStaff ? ChatService.I.connectedStaffPhotoUrl : null,
              ),
            ),
          Flexible(
            child: Column(
              crossAxisAlignment: isUser
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 9,
                  ),
                  constraints: BoxConstraints(maxWidth: widget.bubbleMaxWidth),
                  decoration: BoxDecoration(
                    color: isUser ? AppColors.primaryBlue : AppColors.inputBg,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(15),
                      topRight: const Radius.circular(15),
                      bottomLeft: Radius.circular(isUser ? 15 : 3),
                      bottomRight: Radius.circular(isUser ? 3 : 15),
                    ),
                    border: isUser
                        ? null
                        : Border.all(color: AppColors.stroke, width: 1),
                  ),
                  child: Text(
                    msg.text,
                    style: TextStyle(
                      fontSize: 13.5,
                      color: isUser ? Colors.white : _kTextPri,
                      height: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _fmtTime(msg.time),
                      style: TextStyle(fontSize: 10.5, color: AppColors.hint),
                    ),
                    if (isUser) ...[
                      const SizedBox(width: 4),
                      ChatStatusTicks(status: _mapStatus(msg.status)),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (isUser)
            Padding(
              padding: const EdgeInsets.only(left: 7),
              child: ChatCitizenAvatar(photoUrl: _myPhotoUrl),
            ),
        ],
      ),
    );
  }

  Widget _typingBubble() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const Padding(
            padding: EdgeInsets.only(right: 7),
            child: ChatAgentAvatar(),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
            decoration: BoxDecoration(
              color: AppColors.inputBg,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(15),
                topRight: Radius.circular(15),
                bottomLeft: Radius.circular(3),
                bottomRight: Radius.circular(15),
              ),
              border: Border.all(color: AppColors.stroke, width: 1),
            ),
            child: const ChatTypingDots(),
          ),
        ],
      ),
    );
  }

  // ── Category chips ───────────────────────────────────────────────────────
  // Shown only while ChatService.stage == awaitingCategory.
  Widget _buildCategoryChips() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: const BoxDecoration(color: Colors.white),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'CHOOSE A CATEGORY',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppColors.hint,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: cm.ConcernCategory.values.map((c) {
              return _CategoryChip(
                label: c.label,
                onTap: () => ChatService.I.pickCategory(c),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildIntentChips() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: const BoxDecoration(color: Colors.white),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'WHAT CAN I DO FOR YOU PO?',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppColors.hint,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: cm.ChatIntent.values.map((i) {
              return _CategoryChip(
                label: i.label,
                onTap: () => ChatService.I.pickIntent(i),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildBackToMenu() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      color: Colors.white,
      child: Align(
        alignment: Alignment.centerLeft,
        child: _CategoryChip(
          label: '⬅ Main menu',
          onTap: () => ChatService.I.backToMenu(),
        ),
      ),
    );
  }

  // ── Input bar ────────────────────────────────────────────────────────────
  Widget _buildInput() {
    final isTyping = ChatService.I.isAgentTyping;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.inputBg,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: AppColors.stroke, width: 1),
              ),
              child: Focus(
                onKeyEvent: (node, event) {
                  // Enter sends; Shift+Enter inserts a newline.
                  if (event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.enter &&
                      !HardwareKeyboard.instance.isShiftPressed) {
                    _send();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: TextField(
                key: _textFieldKey,
                controller: _textCtrl,
                focusNode: _focusNode,

                maxLines: 3,
                minLines: 1,
                // Enter sends (button also works); Shift+Enter = newline.
                textInputAction: TextInputAction.newline,
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
                autocorrect: false,
                enableSuggestions: false,
                autofillHints: const [],
                style: const TextStyle(
                  fontSize: 13.5,
                  color: _kTextPri,
                  height: 1.4,
                ),
                decoration: InputDecoration(
                  hintText: isTyping ? 'Agent is typing…' : 'Type a message…',
                  hintStyle: TextStyle(fontSize: 13.5, color: AppColors.hint),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 11,
                  ),
                ),
              ),
              ),
            ),
          ),
          const SizedBox(width: 9),
          GestureDetector(
            onTap: isTyping ? null : _send,
            child: Opacity(
              opacity: isTyping ? 0.45 : 1.0,
              child: Container(
                width: 42,
                height: 42,
                decoration: const BoxDecoration(
                  color: AppColors.primaryBlue,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Image.asset(
                    'assets/images/send.webp',
                    width: 18,
                    color: Colors.white,
                    colorBlendMode: BlendMode.srcIn,
                    errorBuilder: (_, _, _) => const Icon(
                      Icons.send_rounded,
                      size: 18,
                      color: Colors.white,
                    ),
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

// ── Category chip ─────────────────────────────────────────────────────────────
class _CategoryChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _CategoryChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.primaryBlue.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppColors.primaryBlue.withValues(alpha: 0.30),
            ),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.primaryBlue,
            ),
          ),
        ),
      ),
    );
  }
}
