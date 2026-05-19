import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../core/widgets/Home/Chat-agent/chat_models.dart';
import 'ticket_repository.dart';

/// Single source of truth for the LGU citizen chat.
///
/// ─── Conversation lifecycle ───────────────────────────────────────────────
///   greeting → awaitingCategory → awaitingDetails → submitting →
///       └─ ticketCreated   (no staff available, ticket logged)
///       └─ connectedToAgent (staff picked it up — Phase 2 only)
///
/// ─── Reset triggers ───────────────────────────────────────────────────────
///   • Logout         → clearOnLogout() wipes cache + restarts conversation.
///   • 15-min idle    → only while bot is awaiting user input; resets convo.
///   • New convo      → only from terminal stages (ticketCreated etc.) via
///                       startNewConversation().
///
/// ─── Persistence ──────────────────────────────────────────────────────────
///   Hive box 'chat_cache' stores messages, stage, category, and the
///   reference of the last submitted ticket so reopen shows the ticket card.
class ChatService extends ChangeNotifier {
  ChatService._();
  static final ChatService I = ChatService._();

  // ── State ─────────────────────────────────────────────────────────────
  final List<ChatMsg> _messages = [];
  ConversationStage _stage = ConversationStage.greeting;
  ConcernCategory? _category;
  String? _pendingDetails;
  String? _lastTicketReference;
  String? _lastTicketId;
  bool _isAgentTyping = false;
  int _unreadCount = 0;
  bool _isViewing = false;

  /// Incremented on every reset (logout, idle timeout, new conversation).
  /// Pending async work checks this — if it changed mid-await, the work
  /// silently bails instead of polluting the new conversation.
  int _sessionId = 0;

  Timer? _idleTimer;
  static const _idleDuration = Duration(minutes: 15);

  // ── Public getters ────────────────────────────────────────────────────
  List<ChatMsg> get messages => List.unmodifiable(_messages);
  ConversationStage get stage => _stage;
  ConcernCategory? get category => _category;
  bool get isAgentTyping => _isAgentTyping;
  int get unreadCount => _unreadCount;
  bool get hasUnread => _unreadCount > 0;

  /// Show category chips only when the bot is actively waiting on category
  /// selection AND isn't mid-typing.
  bool get showCategoryChips =>
      _stage == ConversationStage.awaitingCategory && !_isAgentTyping;

  /// True when the conversation is in a terminal state (ticket submitted /
  /// connected to agent / timed out) — UI uses this to show a "Start new
  /// conversation" button instead of the normal input.
  bool get isTerminal =>
      _stage == ConversationStage.ticketCreated ||
      _stage == ConversationStage.connectedToAgent ||
      _stage == ConversationStage.timedOut;

  /// Reference code of the most recently submitted ticket, or null.
  String? get lastTicketReference => _lastTicketReference;
  String? get lastTicketId => _lastTicketId;

  // ── Lifecycle ─────────────────────────────────────────────────────────

  /// Call once at app start, AFTER Hive is initialized.
  Future<void> init() async {
    await _loadCache();
    // No greeting fired here — _onChatOpened() will trigger it when the
    // user actually opens the chat, so the typing animation is visible.
    if (_messages.isNotEmpty) {
      _maybeStartIdleTimer();
    }
  }

  void onChatOpened() {
    _isViewing = true;
    _unreadCount = 0;
    _markUserMessagesSeen();
    notifyListeners();

    // If this is a fresh slate (post-logout, post-timeout, or first ever
    // launch with no cache), kick off the greeting now — while the user
    // is actually watching — so they see the typing animation play out.
    if (_messages.isEmpty && _stage == ConversationStage.greeting) {
      _kickoff();
    }
  }

  /// Call when the chat UI closes.
  void onChatClosed() {
    _isViewing = false;
  }

  /// Full wipe — call on logout. Also re-kicks the greeting so the next
  /// user (or same user re-login) sees the intro.
  Future<void> clearOnLogout() async {
    await _resetAll(reason: _ResetReason.logout);
  }

  /// User tapped "Start new conversation" from a terminal stage.
  Future<void> startNewConversation() async {
    if (!isTerminal) return;
    await _resetAll(reason: _ResetReason.userRequested);
  }

  // ── User actions ──────────────────────────────────────────────────────

  Future<void> sendUserText(String raw) async {
    final text = raw.trim();
    if (text.isEmpty || _isAgentTyping || isTerminal) return;

    final session = _sessionId;
    final msg = ChatMsg(text: text, isUser: true, time: DateTime.now());
    _messages.add(msg);
    _cancelIdleTimer(); // user replied — stop the countdown
    notifyListeners();
    _persist();

    // sent → delivered after a short delay
    Future.delayed(const Duration(milliseconds: 650), () {
      if (session != _sessionId) return;
      if (!_messages.contains(msg)) return;
      msg.status = MessageStatus.delivered;
      notifyListeners();
      _persist();
    });

    await _routeUserMessage(msg, session);
  }

  /// User tapped a category chip.
  Future<void> pickCategory(ConcernCategory c) async {
    if (_stage != ConversationStage.awaitingCategory) return;
    _category = c;
    // Send as a normal user message so it appears in the bubble list,
    // and routing logic picks up _category to advance the stage.
    await sendUserText(c.label);
  }

  // ── Conversation routing (state machine) ──────────────────────────────

  Future<void> _routeUserMessage(ChatMsg msg, int session) async {
    switch (_stage) {
      case ConversationStage.greeting:
      case ConversationStage.awaitingCategory:
        if (_category != null) {
          await _agentSay(
            'Got it — your concern falls under ${_category!.label}. '
            'This will go to the ${_category!.department}.',
            session,
          );
          await _agentSay(
            'Please describe what happened in detail. Include the '
            '**location** and **when** it occurred.',
            session,
          );
          if (session != _sessionId) return;
          _stage = ConversationStage.awaitingDetails;
          _maybeStartIdleTimer();
        } else {
          await _agentSay(
            'Please tap one of the category buttons below so I can '
            'route this correctly.',
            session,
          );
        }
        break;

      case ConversationStage.awaitingDetails:
        _pendingDetails = msg.text;
        await _submitTicket(session);
        break;

      // Terminal stages — user input is locked out via isTerminal, but
      // keep these defensive in case something slips through.
      case ConversationStage.submitting:
      case ConversationStage.ticketCreated:
      case ConversationStage.connectedToAgent:
      case ConversationStage.timedOut:
        break;
    }

    if (session != _sessionId) return;
    notifyListeners();
    _persist();
  }

  // ── Ticket submission ─────────────────────────────────────────────────

  Future<void> _submitTicket(int session) async {
    if (_category == null || _pendingDetails == null) return;

    _stage = ConversationStage.submitting;
    notifyListeners();

    await _agentSay('Thanks. Logging your concern now…', session);
    if (session != _sessionId) return;

    try {
      // 1. Check for live agent (Phase 2; currently always null).
      final staffId = await TicketRepository.I.findAvailableStaffId(_category!);

      // 2. Create the ticket row in Supabase regardless — we want a
      //    permanent record either way.
      final reference = _generateRef();
      final ticket = await TicketRepository.I.createTicket(
        category: _category!,
        details: _pendingDetails!,
        referenceCode: reference,
      );

      if (session != _sessionId) return;

      _lastTicketReference = ticket.referenceCode;
      _lastTicketId = ticket.id;

      // 3. Branch: live agent or just ticket?
      if (staffId != null) {
        // Phase 2 path — not reachable today since findAvailableStaffId
        // returns null with no staff onboarded.
        await TicketRepository.I.assignStaff(
          ticketId: ticket.id,
          staffUserId: staffId,
        );
        await _agentSay(
          'A staff member from the ${_category!.department} is online and '
          'will be with you shortly. Reference: ${ticket.referenceCode}',
          session,
        );
        if (session != _sessionId) return;
        _stage = ConversationStage.connectedToAgent;
      } else {
        await _agentSay(
          'No agent is available right now, but your concern has been '
          'logged and forwarded to the ${_category!.department}.\n\n'
          'Reference: ${ticket.referenceCode}\n\n'
          'Our team will follow up within 24–48 hours.',
          session,
        );
        if (session != _sessionId) return;
        _stage = ConversationStage.ticketCreated;
      }
    } on TicketException catch (e) {
      if (session != _sessionId) return;
      await _agentSay('⚠️ ${e.message}\n\nPlease try again later.', session);
      if (session != _sessionId) return;
      _stage = ConversationStage.awaitingDetails; // let them retry
    } catch (_) {
      if (session != _sessionId) return;
      await _agentSay(
        '⚠️ Something went wrong submitting your concern. Please check '
        'your internet connection and try again.',
        session,
      );
      if (session != _sessionId) return;
      _stage = ConversationStage.awaitingDetails;
    }

    if (session != _sessionId) return;
    _cancelIdleTimer(); // terminal stages don't time out
    notifyListeners();
    _persist();
  }

  // ── Idle timer ────────────────────────────────────────────────────────
  // The timer only runs while the bot is waiting on the user. It resets
  // when the user sends a message, and cancels when entering any
  // terminal stage.

  bool get _stageAwaitsUser =>
      _stage == ConversationStage.awaitingCategory ||
      _stage == ConversationStage.awaitingDetails;

  void _maybeStartIdleTimer() {
    _cancelIdleTimer();
    if (!_stageAwaitsUser) return;
    final session = _sessionId;
    _idleTimer = Timer(_idleDuration, () => _onIdleTimeout(session));
  }

  void _cancelIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = null;
  }

  Future<void> _onIdleTimeout(int session) async {
    if (session != _sessionId) return;
    if (!_stageAwaitsUser) return;

    _isAgentTyping = false;
    _messages.add(
      ChatMsg(
        text:
            '⏱️ This conversation has been ended due to 15 minutes of '
            'inactivity. Tap "Start new conversation" to begin again.',
        isUser: false,
        time: DateTime.now(),
      ),
    );
    _stage = ConversationStage.timedOut;
    _cancelIdleTimer();
    if (!_isViewing) _unreadCount++;
    notifyListeners();
    _persist();
  }

  // ── Reset ─────────────────────────────────────────────────────────────

  Future<void> _resetAll({required _ResetReason reason}) async {
    // Bump session — any in-flight delays from before this point will
    // see the new value on resume and silently drop their writes.
    _sessionId++;
    _cancelIdleTimer();

    _messages.clear();
    _stage = ConversationStage.greeting;
    _category = null;
    _pendingDetails = null;
    _lastTicketReference = null;
    _lastTicketId = null;
    _isAgentTyping = false;
    _unreadCount = 0;
    _isViewing = false;

    final b = await Hive.openBox(_boxName);
    await b.clear();
    await b.flush();

    notifyListeners();

    debugPrint('ChatService: reset (reason=${reason.name})');
    // Greeting is NOT fired here — it fires on the next onChatOpened() instead,
    // so the user actually sees the typing animation when they open the chat.
  }

  // ── Bot helpers ───────────────────────────────────────────────────────

  Future<void> _kickoff() async {
    final session = _sessionId;
    await _agentSay("Good day! I'm the LGU Aparri Support Agent.", session);
    await _agentSay(
      'I can log your concern and route it to the right office. '
      'What category does your concern fall under?',
      session,
    );
    if (session != _sessionId) return;
    _stage = ConversationStage.awaitingCategory;
    _maybeStartIdleTimer();
    notifyListeners();
    _persist();
  }

  Future<void> _agentSay(String text, int session) async {
    if (session != _sessionId) return;

    _isAgentTyping = true;
    _markUserMessagesSeen();
    notifyListeners();

    await Future.delayed(const Duration(milliseconds: 1400));
    if (session != _sessionId) return;

    _isAgentTyping = false;
    _messages.add(ChatMsg(text: text, isUser: false, time: DateTime.now()));
    if (!_isViewing) _unreadCount++;
    notifyListeners();
    _persist();
  }

  void _markUserMessagesSeen() {
    for (final m in _messages) {
      if (m.isUser && m.status != MessageStatus.seen) {
        m.status = MessageStatus.seen;
      }
    }
  }

  String _generateRef() {
    final n = DateTime.now();
    final d =
        '${n.year}${n.month.toString().padLeft(2, '0')}${n.day.toString().padLeft(2, '0')}';
    final t = n.millisecondsSinceEpoch.toString();
    return 'LGU-$d-${t.substring(t.length - 5)}';
  }

  // ── Cache (Hive) ──────────────────────────────────────────────────────
  static const _boxName = 'chat_cache';

  Future<void> _persist() async {
    final session = _sessionId;
    final b = await Hive.openBox(_boxName);
    if (session != _sessionId) return; // session changed mid-await, drop write

    final snapshot = {
      'messages': _messages.map((m) => m.toJson()).toList(),
      'stage': _stage.index,
      'category': _category?.index,
      'pendingDetails': _pendingDetails,
      'lastTicketReference': _lastTicketReference,
      'lastTicketId': _lastTicketId,
    };

    if (session != _sessionId) return;
    await b.putAll(snapshot);
  }

  Future<void> _loadCache() async {
    final b = await Hive.openBox(_boxName);
    final raw = b.get('messages') as List?;
    if (raw != null) {
      _messages
        ..clear()
        ..addAll(
          raw.map((m) => ChatMsg.fromJson(Map<String, dynamic>.from(m))),
        );
    }
    final stageIdx = b.get('stage', defaultValue: 0) as int;
    _stage = ConversationStage
        .values[stageIdx.clamp(0, ConversationStage.values.length - 1)];
    final ci = b.get('category') as int?;
    _category = ci != null ? ConcernCategory.values[ci] : null;
    _pendingDetails = b.get('pendingDetails') as String?;
    _lastTicketReference = b.get('lastTicketReference') as String?;
    _lastTicketId = b.get('lastTicketId') as String?;
  }
}

/// Why a reset happened — used for logging and (eventually) varying welcome
/// copy ("Welcome back" vs "Starting over").
enum _ResetReason { logout, idleTimeout, userRequested }
