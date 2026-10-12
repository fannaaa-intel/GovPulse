import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/widgets/responsive_page.dart';
import '../../../../core/services/chat_service.dart';
import '../../../../core/services/faq_catalog.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/Home/Chat-agent/chat_agent_info_bar.dart';
import '../../../../core/widgets/Home/Chat-agent/chat_input_bar.dart';
import '../../../../core/widgets/Home/Chat-agent/chat_message.dart';
import '../../../../core/widgets/Home/Chat-agent/chat_message_bubble.dart';
import '../../../../core/widgets/Home/Chat-agent/faq_picker.dart';
import '../../../../core/widgets/Home/Chat-agent/chat_models.dart' as cm;
import '../../../../core/theme/citizen_ui.dart';
import '../../../../core/theme/mobile_metrics.dart';
import '../../../../core/widgets/app_back_chevron.dart';

/// Full-screen chat with Kuya Gov, the automated assistant.
///
/// State lives in [ChatService.I]. This screen and the floating bubble panel
/// both subscribe to the same service — anything typed in one appears in the
/// other instantly.
///
/// Questions only. There is no live staff chat (panel revision, 2026-10-12):
/// a concern that needs action goes through Report / Suggestion / Feedback,
/// which the assistant points to when asked.
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

  /// The signed-in citizen's own profile photo, for their outgoing bubbles.
  String? _myPhotoUrl;

  // ── Lifecycle ─────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _loadMyPhoto();

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

  /// Loads the citizen's own profile photo (public `profile-photos` bucket) so
  /// their outgoing bubbles show their face, falling back to a person icon.
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
      setState(
        () => _myPhotoUrl = client.storage
            .from('profile-photos')
            .getPublicUrl(path),
      );
    } catch (_) {
      /* fall back to the default person icon */
    }
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
      offline: m.offline,
    );
  }

  // ── Terminal-state card ──────────────────────────────────────────────────
  Widget _buildTerminalCard(double width) {
    final stage = _svc.stage;

    late final IconData icon;
    late final Color tint;
    late final String title;
    late final String subtitle;

    switch (stage) {
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
        border: Border(
          top: BorderSide(color: CitizenUi.sharedStroke, width: 1),
        ),
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
    final width = uiScaleWidth(context);

    // The browser always gets the web layout — `kIsWeb` alone, no width test,
    // for the reason EditProfileScreen spells out.
    if (kIsWeb) return _buildWebScaffold(width);

    return Scaffold(
      backgroundColor: AppColors.inputBg,
      body: ResponsivePageBody(
        maxWidth: 600,
        shellTitle: 'Ask Kuya Gov',
        shellSubtitle:
            'Answers to common questions about Aparri services and offices.',
        shellIcon: Icons.support_agent_rounded,
        shellHighlights: const [
          (Icons.chat_bubble_outline_rounded, 'Instant answers'),
          (Icons.menu_book_rounded, 'Services and requirements'),
          (Icons.verified_user_outlined, 'Official LGU information'),
        ],
        shellContentWidth: 620,
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(width),
              ChatAgentInfoBar(width: width),
              Expanded(child: _buildMessageList(width)),
              if (_svc.showBackToMenu && _svc == ChatService.I)
                _buildBackToMenu(width),
              if (_svc.showFaqChips) _buildFaqChips(width),
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

  // ═════════════════════════════════════════════════════════════════════════
  //  WEB
  //
  //  Reached only from the `kIsWeb` branch of build(). The mobile layout below
  //  is untouched; this is a second frame around the SAME conversation, service
  //  and composer.
  // ═════════════════════════════════════════════════════════════════════════

  /// Widest the conversation column gets.
  ///
  /// Matches the submission detail screens rather than the account pages' 880.
  /// A chat set across 880 gives bubbles a line length nobody reads a message
  /// at, and the composer under it grows into a text editor.
  static const double _kChatWebMeasure = 760;

  Widget _buildWebScaffold(double width) {
    // No ResponsivePageBody, and so no `shellTitle`: that path is for a
    // standalone route with a decorative brand panel beside it, and this opens
    // inside a pane that already has a top nav and a left rail.
    return Scaffold(
      backgroundColor: AppColors.inputBg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _kChatWebMeasure),
            child: Column(
              children: [
                _buildWebHeader(),
                ChatAgentInfoBar(width: width),
                Expanded(child: _buildMessageList(width)),
                if (_svc.showBackToMenu && _svc == ChatService.I)
                  _buildBackToMenu(width),
                if (_svc.showFaqChips) _buildFaqChips(width),
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
      ),
    );
  }

  /// The web header: a way out, and the name of the screen.
  ///
  /// ── Why the GovPulse mark is gone ───────────────────────────────────────
  /// The phone header carries the logo because on a phone this screen IS the
  /// app — there is no other chrome telling you what you are in. In the shell
  /// the top nav already shows that mark about 60px above this row, so the
  /// header was printing it twice, and the second one said nothing the first
  /// had not.
  ///
  /// What it did NOT say was where you are, which on a pushed screen is the
  /// question worth answering. So the mark gives way to the screen's name, and
  /// [ChatAgentInfoBar] directly below still identifies who you are talking to.
  Widget _buildWebHeader() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: CitizenUi.border)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: 'Back',
            // The app-wide chevron+title pair: an outlined chip with the iOS
            // chevron, not a filled one with the Material arrow.
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(CitizenUi.controlRadius),
              child: InkWell(
                onTap: () => Navigator.pop(context),
                borderRadius: BorderRadius.circular(CitizenUi.controlRadius),
                child: Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(
                      CitizenUi.controlRadius,
                    ),
                    border: Border.all(color: kBackChevronBorder),
                  ),
                  child: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    size: 17,
                    color: kBackChevronGlyph,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          const Text(
            'Ask Kuya Gov',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: CitizenUi.textPrimary,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _buildHeader(double width) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: CitizenUi.sharedStroke, width: 1),
        ),
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
              width: width * 0.09,
              height: width * 0.09,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(width * 0.025),
                border: Border.all(color: kBackChevronBorder, width: 1),
              ),
              child: Icon(
                Icons.arrow_back_ios_new_rounded,
                size: width * 0.046,
                color: kBackChevronGlyph,
              ),
            ),
          ),
          SizedBox(width: width * 0.03),
          Image.asset(
            'assets/images/newslogo.webp',
            height: width * 0.085,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => Row(
              children: [
                Icon(
                  Icons.account_balance_rounded,
                  size: width * 0.07,
                  color: AppColors.primaryBlue,
                ),
                SizedBox(width: width * 0.02),
                Text(
                  'GovPulse',
                  style: TextStyle(
                    fontSize: width * 0.048,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryBlue,
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
        final src = messages[realIndex];
        return ChatMessageBubble(
          width: width,
          message: _toViewMsg(src),
          formatTime: _formatTime,
          citizenPhotoUrl: _myPhotoUrl,
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
          border: Border.all(color: CitizenUi.sharedStroke, width: 1),
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
          label: '← Common questions',
          width: width,
          onTap: () => _svc.backToMenu(),
        ),
      ),
    );
  }

  Future<void> _openAllFaqs() async {
    final faq = await showAllFaqs(context);
    if (faq != null && mounted) await _svc.askFaq(faq);
  }

  // ── Common-question chips (ready-made answers, no AI call) ────────────────
  Widget _buildFaqChips(double width) {
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
            'COMMON QUESTIONS — OR TYPE YOUR OWN',
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
            children: [
              for (final faq in featuredFaqs)
                _CategoryChip(
                  label: faq.question,
                  width: width,
                  onTap: () => _svc.askFaq(faq),
                ),
              _CategoryChip(
                label: 'All questions…',
                width: width,
                onTap: _openAllFaqs,
              ),
            ],
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
