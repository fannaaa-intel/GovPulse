import 'package:flutter/material.dart';
import '../../../../core/widgets/responsive_page.dart';
import '../../../../core/services/chat_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/Home/Chat-agent/chat_agent_info_bar.dart';
import '../../../../core/widgets/Home/Chat-agent/chat_input_bar.dart';
import '../../../../core/widgets/Home/Chat-agent/chat_message.dart';
import '../../../../core/widgets/Home/Chat-agent/chat_message_bubble.dart';
import '../../../../core/widgets/Home/Chat-agent/chat_models.dart' as cm;

/// Full-screen chat with the LGU agent.
///
/// State lives in [ChatService.I]. This screen and the floating bubble panel
/// both subscribe to the same service — anything typed in one appears in the
/// other instantly.
///
/// NOTE: "Report Issue" is no longer shown as an intent chip here.
/// Citizens report issues via the Quick Action button on the Home screen.
/// Free-text messages like "gusto ko mag-report" still route to the report
/// flow automatically via AI intent detection ([ACTION:REPORT]).
class ChatAgentScreen extends StatefulWidget {
  final String username;
  final ChatService service;
  ChatAgentScreen({super.key, required this.username, ChatService? service})
    : service = service ?? ChatService.I;

  @override
  State<ChatAgentScreen> createState() => _ChatAgentScreenState();
}

class _ChatAgentScreenState extends State<ChatAgentScreen>
    with TickerProviderStateMixin {
  // ── Controllers ───────────────────────────────────────────────────────────
  late final AnimationController _entryCtrl;
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final FocusNode _focusNode = FocusNode();
  ChatService get _svc => widget.service;

  // ── Lifecycle ─────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _svc.addListener(_onChatChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final isFollowUp = _svc != ChatService.I;
      _svc.onChatOpened(isFollowUp: isFollowUp);
      _entryCtrl.forward();
      _scrollToBottom();
    });
  }

  @override
  void dispose() {
    _svc.removeListener(_onChatChanged);
    _svc.onChatClosed();
    _entryCtrl.dispose();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChatChanged() {
    if (!mounted) return;
    setState(() {}); // ✅ immediate rebuild, no flicker frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollToBottom(); // scroll can still be deferred
    });
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendMessage() {
    final text = _inputCtrl.text;
    if (text.trim().isEmpty) return;

    _inputCtrl.value = const TextEditingValue(
      text: '',
      selection: TextSelection.collapsed(offset: 0),
      composing: TextRange.empty,
    );

    _svc.sendUserText(text);
  }

  String _formatTime(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    final p = t.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $p';
  }

  ChatMessage _toViewMsg(cm.ChatMsg m) {
    return ChatMessage(
      text: m.text,
      isUser: m.isUser,
      time: m.time,
      status: MessageStatus.values[m.status.index],
    );
  }

  // ── Terminal-state card ──────────────────────────────────────────────────
  Widget _buildTerminalCard(double width) {
    final stage = _svc.stage;
    final reference = _svc.lastTicketReference;

    late final IconData icon;
    late final Color tint;
    late final String title;
    late final String subtitle;

    switch (stage) {
      case cm.ConversationStage.ticketCreated:
        icon = Icons.check_circle_rounded;
        tint = AppColors.green;
        title = 'Ticket submitted successfully';
        subtitle = reference != null
            ? 'Reference: $reference'
            : 'Your concern has been logged.';
        break;
      case cm.ConversationStage.connectedToAgent:
        icon = Icons.support_agent_rounded;
        tint = AppColors.primaryBlue;
        title = 'Connected to LGU staff';
        subtitle = 'An agent is now handling your concern.';
        break;
      case cm.ConversationStage.timedOut:
        icon = Icons.timer_off_rounded;
        tint = AppColors.hint;
        title = 'Session ended';
        subtitle = 'No activity for 15 minutes.';
        break;
      case cm.ConversationStage.ended:
        icon = Icons.check_circle_outline_rounded;
        tint = AppColors.hint;
        title = 'Conversation ended';
        subtitle = 'Thanks for chatting with Kuya Gov.';
        break;
      default:
        return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.stroke, width: 1)),
      ),
      padding: EdgeInsets.fromLTRB(
        width * 0.04,
        width * 0.035,
        width * 0.04,
        width * 0.045,
      ),
      child: Column(
        children: [
          // ── Status row ─────────────────────────────────────────────────
          Container(
            padding: EdgeInsets.all(width * 0.032),
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(width * 0.030),
              border: Border.all(color: tint.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                Container(
                  width: width * 0.10,
                  height: width * 0.10,
                  decoration: BoxDecoration(
                    color: tint.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: tint, size: width * 0.054),
                ),
                SizedBox(width: width * 0.03),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: width * 0.036,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF111827),
                        ),
                      ),
                      SizedBox(height: width * 0.005),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: width * 0.030,
                          color: AppColors.hint,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: width * 0.030),

          // ── Talk to a person button (main chat only) ───────────────────
          if (_svc == ChatService.I &&
              stage == cm.ConversationStage.ticketCreated) ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _svc.requestLiveAgent(),
                icon: Icon(Icons.support_agent_rounded, size: width * 0.045),
                label: Text(
                  'Talk to a person',
                  style: TextStyle(
                    fontSize: width * 0.036,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primaryBlue,
                  side: BorderSide(color: AppColors.primaryBlue),
                  padding: EdgeInsets.symmetric(vertical: width * 0.038),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(width * 0.028),
                  ),
                ),
              ),
            ),
            SizedBox(height: width * 0.022),
          ],

          // ── Start new conversation button (main chat only) ─────────────
          if (_svc == ChatService.I)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _svc.startNewConversation(),
                icon: Icon(Icons.refresh_rounded, size: width * 0.045),
                label: Text(
                  'Start new conversation',
                  style: TextStyle(
                    fontSize: width * 0.036,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: EdgeInsets.symmetric(vertical: width * 0.038),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(width * 0.028),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width.clamp(0.0, 480.0);
    return Scaffold(
      backgroundColor: AppColors.inputBg,
      body: ResponsivePageBody(
        maxWidth: 600,
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(width),
              ChatAgentInfoBar(width: width),
              Expanded(child: _buildMessageList(width)),
              // AFTER
              if (_svc.showBackToMenu && _svc == ChatService.I)
                _buildBackToMenu(width),
              if (_svc.showIntentChips && _svc == ChatService.I)
                _buildIntentChips(width),
              if (_svc.showCategoryChips && _svc == ChatService.I)
                _buildCategoryChips(width),
              if (_svc.isTerminal)
                _buildTerminalCard(width)
              else
                ChatInputBar(
                  width: width,
                  controller: _inputCtrl,
                  focusNode: _focusNode,
                  onSend: _sendMessage,
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _buildHeader(double width) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.stroke, width: 1)),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: width * 0.04,
        vertical: width * 0.03,
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: width * 0.088,
              height: width * 0.088,
              decoration: BoxDecoration(
                color: AppColors.inputBg,
                borderRadius: BorderRadius.circular(width * 0.022),
                border: Border.all(color: AppColors.stroke, width: 1),
              ),
              child: Icon(
                Icons.arrow_back_ios_new_rounded,
                size: width * 0.040,
                color: AppColors.primaryBlue,
              ),
            ),
          ),
          SizedBox(width: width * 0.03),
          Image.asset(
            'assets/images/newslogo.webp',
            height: width * 0.080,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => Row(
              children: [
                Icon(
                  Icons.account_balance_rounded,
                  size: width * 0.062,
                  color: AppColors.primaryBlue,
                ),
                SizedBox(width: width * 0.018),
                Text(
                  'GovPulse',
                  style: TextStyle(
                    fontSize: width * 0.045,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF111827),
                    letterSpacing: -0.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Message list ──────────────────────────────────────────────────────────
  Widget _buildMessageList(double width) {
    final messages = _svc.messages;
    final isTyping = _svc.isAgentTyping;
    final itemCount = messages.length + (isTyping ? 1 : 0);

    return ListView.builder(
      controller: _scrollCtrl,
      padding: EdgeInsets.symmetric(
        horizontal: width * 0.04,
        vertical: width * 0.032,
      ),
      itemCount: itemCount + 1,
      itemBuilder: (context, index) {
        if (index == 0) return _buildDateChip(width);
        final realIndex = index - 1;
        if (realIndex == messages.length && isTyping) {
          return ChatTypingBubble(width: width);
        }
        return ChatMessageBubble(
          width: width,
          message: _toViewMsg(messages[realIndex]),
          formatTime: _formatTime,
        );
      },
    );
  }

  Widget _buildDateChip(double width) {
    return Center(
      child: Container(
        margin: EdgeInsets.only(bottom: width * 0.042),
        padding: EdgeInsets.symmetric(
          horizontal: width * 0.038,
          vertical: width * 0.012,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(width * 0.06),
          border: Border.all(color: AppColors.stroke, width: 1),
        ),
        child: Text(
          'TODAY',
          style: TextStyle(
            fontSize: width * 0.023,
            color: AppColors.hint,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.8,
          ),
        ),
      ),
    );
  }

  Widget _buildBackToMenu(double width) {
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(
        width * 0.04,
        width * 0.02,
        width * 0.04,
        width * 0.02,
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: _CategoryChip(
          label: '⬅ Main menu',
          width: width,
          onTap: () => _svc.backToMenu(),
        ),
      ),
    );
  }

  // ── Category chips (live agent flow only) ─────────────────────────────────
  Widget _buildCategoryChips(double width) {
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(
        width * 0.04,
        width * 0.025,
        width * 0.04,
        width * 0.03,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'CHOOSE A CATEGORY',
            style: TextStyle(
              fontSize: width * 0.026,
              fontWeight: FontWeight.w700,
              color: AppColors.hint,
              letterSpacing: 0.8,
            ),
          ),
          SizedBox(height: width * 0.022),
          Wrap(
            spacing: width * 0.022,
            runSpacing: width * 0.022,
            children: cm.ConcernCategory.values.map((c) {
              return _CategoryChip(
                label: c.label,
                width: width,
                onTap: () => _svc.pickCategory(c),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ── Intent chips — only "Ask a question" and "Talk to a person" ───────────
  Widget _buildIntentChips(double width) {
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(
        width * 0.04,
        width * 0.025,
        width * 0.04,
        width * 0.03,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'WHAT CAN I DO FOR YOU PO?',
            style: TextStyle(
              fontSize: width * 0.026,
              fontWeight: FontWeight.w700,
              color: AppColors.hint,
              letterSpacing: 0.8,
            ),
          ),
          SizedBox(height: width * 0.022),
          Wrap(
            spacing: width * 0.022,
            runSpacing: width * 0.022,
            // ChatIntent.values now only contains: question, liveAgent
            children: cm.ChatIntent.values.map((i) {
              return _CategoryChip(
                label: i.label,
                width: width,
                onTap: () => _svc.pickIntent(i),
              );
            }).toList(),
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
  final double width;
  const _CategoryChip({
    required this.label,
    required this.onTap,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(width * 0.06),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: width * 0.038,
            vertical: width * 0.022,
          ),
          decoration: BoxDecoration(
            color: AppColors.primaryBlue.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(width * 0.06),
            border: Border.all(
              color: AppColors.primaryBlue.withValues(alpha: 0.30),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: width * 0.032,
              fontWeight: FontWeight.w600,
              color: AppColors.primaryBlue,
            ),
          ),
        ),
      ),
    );
  }
}
