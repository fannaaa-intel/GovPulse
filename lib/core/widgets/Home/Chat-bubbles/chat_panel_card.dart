import 'package:flutter/material.dart';
import '../../../../features/auth/services/chat_service.dart';
import '../../../theme/app_colors.dart';
import 'Chat_bubbles_model.dart';
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

  const HomeChatPanelCard({
    super.key,
    required this.onAgentMessage,
    required this.panelW,
    required this.panelH,
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

  @override
  void initState() {
    super.initState();

    // Subscribe to the single source of truth.
    ChatService.I.addListener(_onChatChanged);
    ChatService.I.onChatOpened();

    _lastSeenMsgCount = ChatService.I.messages.length;
    _scrollDownSoon();
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
            borderRadius: BorderRadius.circular(20),
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
            borderRadius: BorderRadius.circular(20),
            child: Column(
              children: [
                _buildHeader(),
                const Divider(
                  height: 1,
                  thickness: 1,
                  color: Color(0xFFE3E6EF),
                ),
                Expanded(child: _buildMessages()),

                if (ChatService.I.showCategoryChips) _buildCategoryChips(),

                const Divider(
                  height: 1,
                  thickness: 1,
                  color: Color(0xFFE3E6EF),
                ),

                // ── Terminal stages show the "Start new conversation" card
                // instead of the input bar, so the user has a clear next action.
                if (ChatService.I.isTerminal)
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

  // ── Terminal-state card ──────────────────────────────────────────────────
  // Shown when the conversation is in ticketCreated / connectedToAgent /
  // timedOut. Replaces the input bar with context + a clear CTA.
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

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
      child: Row(
        children: [
          Container(
            width: avatarSize,
            height: avatarSize,
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Image.asset(
                'assets/images/customer.png',
                width: avatarSize * 0.53,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => Icon(
                  Icons.support_agent_rounded,
                  size: avatarSize * 0.53,
                  color: AppColors.primaryBlue,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'LGU Aparri Agent',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _kTextPri,
                    letterSpacing: -0.2,
                  ),
                ),
                Text(
                  'Online',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppColors.green,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
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
            const Padding(
              padding: EdgeInsets.only(right: 7),
              child: ChatAgentAvatar(),
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
                  constraints: const BoxConstraints(maxWidth: 240),
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
              child: TextField(
                key: _textFieldKey,
                controller: _textCtrl,
                focusNode: _focusNode,

                maxLines: 3,
                minLines: 1,
                // Enter key inserts a newline; send is button-only so the keyboard
                // never auto-dismisses on submit.
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
                    'assets/images/send.png',
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
