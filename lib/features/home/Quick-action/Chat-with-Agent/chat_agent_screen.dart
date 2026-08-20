import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/widgets/responsive_page.dart';
import '../../../../core/services/chat_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/Home/Chat-agent/chat_agent_info_bar.dart';
import '../../../../core/widgets/Home/Chat-agent/chat_input_bar.dart';
import '../../../../core/widgets/Home/Chat-agent/chat_message.dart';
import '../../../../core/widgets/Home/Chat-agent/chat_message_bubble.dart';
import '../../../../core/widgets/Home/Chat-agent/chat_models.dart' as cm;
import '../../../../core/theme/citizen_ui.dart';

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

  /// Locally-selected star count in the post-chat rating card (0 = none yet).
  int _ratingStars = 0;

  /// Whether the rating card was showing on the previous rebuild. Used to reset
  /// [_ratingStars] each time a *fresh* rating card appears — otherwise a new
  /// conversation's rating card inherits the stars picked for the previous one.
  bool _wasShowingRating = false;

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
    // Reset the picked stars each time a fresh rating card appears (false→true
    // edge), so a new conversation never inherits the previous chat's rating.
    final showingRating = _svc.showRatingBar;
    if (showingRating && !_wasShowingRating) _ratingStars = 0;
    _wasShowingRating = showingRating;
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

  /// Returns the citizen to the bot for a fresh conversation (a NEW ticket if
  /// they escalate again — never a reopen of the resolved one). If a message
  /// lost the send/end race, it is carried into the new composer rather than
  /// discarded, so the citizen can send it to the bot instead.
  Future<void> _needMoreHelp() async {
    final draft = _svc.consumeUndeliveredText();
    await _svc.startNewConversation();
    if (!mounted) return;
    if (draft != null && draft.trim().isNotEmpty) {
      _inputCtrl.text = draft;
      _inputCtrl.selection = TextSelection.collapsed(offset: draft.length);
      _focusNode.requestFocus();
    }
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
      fromStaff: m.fromStaff,
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

  // ── Post-chat rating card ─────────────────────────────────────────────────
  static const List<String> _ratingLabels = [
    'Tap a star to rate',
    'Poor',
    'Fair',
    'Good',
    'Great',
    'Excellent',
  ];

  Widget _buildRatingCard(double width) {
    final selected = _ratingStars;
    final tint = AppColors.primaryBlue;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: CitizenUi.sharedStroke, width: 1),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        width * 0.05,
        width * 0.045,
        width * 0.05,
        width * 0.05,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: width * 0.12,
            height: width * 0.12,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.support_agent_rounded,
              color: tint,
              size: width * 0.062,
            ),
          ),
          SizedBox(height: width * 0.03),
          Text(
            'How was your chat?',
            style: TextStyle(
              fontSize: width * 0.044,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF111827),
            ),
          ),
          SizedBox(height: width * 0.012),
          Text(
            'Your feedback helps our staff serve you better.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: width * 0.031, color: AppColors.hint),
          ),
          SizedBox(height: width * 0.04),
          // ── Stars ──────────────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) {
              final starIndex = i + 1;
              final active = starIndex <= selected;
              return GestureDetector(
                onTap: () => setState(() => _ratingStars = starIndex),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: width * 0.014),
                  child: AnimatedScale(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutBack,
                    scale: active ? 1.12 : 1.0,
                    child: Icon(
                      active ? Icons.star_rounded : Icons.star_outline_rounded,
                      size: width * 0.095,
                      color: active
                          ? const Color(0xFFF5A623)
                          : AppColors.stroke,
                    ),
                  ),
                ),
              );
            }),
          ),
          SizedBox(height: width * 0.022),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Text(
              _ratingLabels[selected],
              key: ValueKey(selected),
              style: TextStyle(
                fontSize: width * 0.033,
                fontWeight: FontWeight.w700,
                color: selected == 0 ? AppColors.hint : tint,
              ),
            ),
          ),
          SizedBox(height: width * 0.04),
          // ── Submit ─────────────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: selected == 0
                  ? null
                  : () => _svc.submitRating(selected),
              style: ElevatedButton.styleFrom(
                backgroundColor: tint,
                foregroundColor: Colors.white,
                disabledBackgroundColor: tint.withValues(alpha: 0.35),
                disabledForegroundColor: Colors.white,
                elevation: 0,
                padding: EdgeInsets.symmetric(vertical: width * 0.038),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(width * 0.028),
                ),
              ),
              child: Text(
                'Submit rating',
                style: TextStyle(
                  fontSize: width * 0.036,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          SizedBox(height: width * 0.01),
          // Skip never blocks the citizen behind a rating they don't want to
          // give — it just dismisses the card and leaves the chat ended.
          TextButton(
            onPressed: () => _svc.dismissRating(),
            style: TextButton.styleFrom(foregroundColor: AppColors.hint),
            child: Text(
              'Skip',
              style: TextStyle(
                fontSize: width * 0.032,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          // A way back to the bot straight from the rating card, so a citizen
          // who still needs help isn't forced to rate first (main chat only).
          if (_svc == ChatService.I)
            TextButton.icon(
              onPressed: _needMoreHelp,
              icon: Icon(Icons.support_agent_rounded, size: width * 0.042),
              style: TextButton.styleFrom(foregroundColor: tint),
              label: Text(
                'Need more help?',
                style: TextStyle(
                  fontSize: width * 0.032,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Locked composer (chat ended) ──────────────────────────────────────────
  /// Shown once the chat has ended and the citizen has rated or skipped. The
  /// composer is locked with a clear notice — the database also rejects writes
  /// to an ended ticket (migration 20260722000005 phase 3), so this is the UI
  /// side of a control enforced on both ends, not the only guard. "Need more
  /// help?" starts a fresh bot conversation (a new ticket if escalated, never a
  /// reopen of this one).
  Widget _buildEndedComposer(double width) {
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
        width * 0.032,
        width * 0.04,
        width * 0.04,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(
              horizontal: width * 0.04,
              vertical: width * 0.032,
            ),
            decoration: BoxDecoration(
              color: AppColors.inputBg,
              borderRadius: BorderRadius.circular(width * 0.055),
              border: Border.all(color: CitizenUi.sharedStroke, width: 1),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.lock_outline_rounded,
                  size: width * 0.044,
                  color: AppColors.hint,
                ),
                SizedBox(width: width * 0.025),
                Expanded(
                  child: Text(
                    'This conversation has ended',
                    style: TextStyle(
                      fontSize: width * 0.034,
                      color: AppColors.hint,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Main chat can start over; a follow-up chat panel cannot (it is
          // scoped to one report and has no bot kickoff).
          if (_svc == ChatService.I) ...[
            SizedBox(height: width * 0.028),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _needMoreHelp,
                icon: Icon(Icons.support_agent_rounded, size: width * 0.045),
                label: Text(
                  'Need more help?',
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
        ],
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width.clamp(0.0, 480.0);

    // The browser always gets the web layout — `kIsWeb` alone, no width test,
    // for the reason EditProfileScreen spells out.
    if (kIsWeb) return _buildWebScaffold(width);

    return Scaffold(
      backgroundColor: AppColors.inputBg,
      body: ResponsivePageBody(
        maxWidth: 600,
        shellTitle: 'Chat with an Agent',
        shellSubtitle:
            'Ask questions and get help from the Aparri support team.',
        shellIcon: Icons.support_agent_rounded,
        shellHighlights: const [
          (Icons.chat_bubble_outline_rounded, 'Real-time answers'),
          (Icons.schedule_rounded, 'Fast responses'),
          (Icons.verified_user_outlined, 'Official support'),
        ],
        shellContentWidth: 620,
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(width),
              ChatAgentInfoBar(
                width: width,
                connected: _svc.isConnectedToStaff,
                // Real staff name once fetched; department label until then.
                staffLabel:
                    _svc.connectedStaffName ??
                    (_svc.connectedDepartment != null
                        ? '${_svc.connectedDepartment} staff'
                        : null),
                staffPhotoUrl: _svc.connectedStaffPhotoUrl,
              ),
              Expanded(child: _buildMessageList(width)),
              // AFTER
              if (_svc.showBackToMenu && _svc == ChatService.I)
                _buildBackToMenu(width),
              if (_svc.showIntentChips && _svc == ChatService.I)
                _buildIntentChips(width),
              if (_svc.showCategoryChips && _svc == ChatService.I)
                _buildCategoryChips(width),
              if (_svc.showRatingBar)
                _buildRatingCard(width)
              else if (_svc.stage == cm.ConversationStage.ended)
                // Chat ended and the citizen has rated or skipped: lock the
                // composer with a clear notice and a way back to the bot.
                _buildEndedComposer(width)
              else if (_svc.isTerminal)
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
                ChatAgentInfoBar(
                  width: width,
                  connected: _svc.isConnectedToStaff,
                  staffLabel:
                      _svc.connectedStaffName ??
                      (_svc.connectedDepartment != null
                          ? '${_svc.connectedDepartment} staff'
                          : null),
                  staffPhotoUrl: _svc.connectedStaffPhotoUrl,
                ),
                Expanded(child: _buildMessageList(width)),
                if (_svc.showBackToMenu && _svc == ChatService.I)
                  _buildBackToMenu(width),
                if (_svc.showIntentChips && _svc == ChatService.I)
                  _buildIntentChips(width),
                if (_svc.showCategoryChips && _svc == ChatService.I)
                  _buildCategoryChips(width),
                if (_svc.showRatingBar)
                  _buildRatingCard(width)
                else if (_svc.stage == cm.ConversationStage.ended)
                  _buildEndedComposer(width)
                else if (_svc.isTerminal)
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
            child: Material(
              color: AppColors.inputBg,
              borderRadius: BorderRadius.circular(CitizenUi.controlRadius),
              child: InkWell(
                onTap: () => Navigator.pop(context),
                borderRadius: BorderRadius.circular(CitizenUi.controlRadius),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(
                      CitizenUi.controlRadius,
                    ),
                    border: Border.all(color: CitizenUi.border),
                  ),
                  child: const Icon(
                    Icons.arrow_back_rounded,
                    size: 18,
                    color: CitizenUi.textSecondary,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          const Text(
            'Chat with an Agent',
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
              width: width * 0.088,
              height: width * 0.088,
              decoration: BoxDecoration(
                color: AppColors.inputBg,
                borderRadius: BorderRadius.circular(width * 0.022),
                border: Border.all(color: CitizenUi.sharedStroke, width: 1),
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
        final src = messages[realIndex];
        return ChatMessageBubble(
          width: width,
          message: _toViewMsg(src),
          formatTime: _formatTime,
          // Staff photo for the connected staffer's bubbles; the citizen's own
          // photo for their outgoing bubbles.
          agentPhotoUrl: _svc.connectedStaffPhotoUrl,
          citizenPhotoUrl: _myPhotoUrl,
          onResend: () => _svc.resendMessage(src),
          onDelete: () => _svc.deleteMessage(src),
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
