import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/Home/Chat-agent/chat_models.dart';
import 'local_assistant.dart';
import 'ticket_repository.dart';

class ChatService extends ChangeNotifier {
  ChatService._(String baseBox) : _baseBox = baseBox, _activeBoxName = baseBox;
  static final ChatService I = ChatService._('chat_cache'); // main chat
  static final ChatService followUp = ChatService._(
    'chat_cache_followup',
  ); // follow-up chat only

  // ── Per-user storage scoping ──────────────────────────────────────────
  static String? _currentUserId;

  static String _scoped(String base) {
    final uid = _currentUserId;
    return uid == null ? base : '${base}__$uid';
  }

  /// Bind chat storage to [userId] and load that user's cache.
  /// Call on sign-in and on app start when a session is restored.
  static Future<void> onUserAuthenticated(String userId) async {
    if (_currentUserId == userId) return; // ignore token refreshes
    _currentUserId = userId;
    await I._rebindToCurrentUser();
  }

  /// Clear this user's chat from memory + disk and unbind storage.
  /// Call on sign-out.
  static Future<void> onUserSignedOut() async {
    if (_currentUserId == null) return;
    try {
      // Each step guarded independently: a failure clearing the main chat must
      // not skip the follow-up boxes, and neither must skip the id reset below.
      // Both touch Hive/IndexedDB, and by the time this runs the Supabase
      // session is already gone — so anything inside that still reaches the
      // network fails by construction.
      try {
        await I.clearOnLogout();
      } catch (_) {}
      try {
        await clearAllFollowUpBoxes();
      } catch (_) {}
    } finally {
      // ALWAYS, whatever happened above. Leaving this set is worse than a
      // half-cleared cache: [onUserAuthenticated] short-circuits on
      // `_currentUserId == userId`, so the SAME user signing back in would
      // never rebind their storage and would inherit the previous session's
      // chat. The call sites wrap this too, but that is a safety net — it must
      // not be what keeps the id from leaking.
      _currentUserId = null;
    }
  }

  static String _boxNameForReport(String reportRef) {
    final safe = reportRef.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    return _scoped('chat_cache_followup_$safe');
  }

  static ChatService forReport(String reportRef) {
    final boxName = _boxNameForReport(reportRef);
    final svc = ChatService._(boxName);
    svc._stage = ConversationStage.followUp;
    return svc;
  }

  final String _baseBox;
  String _activeBoxName;

  // ── State ─────────────────────────────────────────────────────────────
  final List<ChatMsg> _messages = [];
  ConversationStage _stage = ConversationStage.greeting;
  ConcernCategory? _category;
  String? _pendingDetails;
  /// The concern ticket's OWN reference code — the `LGU-YYYYMMDD-NNNNN` value
  /// stored in `concern_tickets.reference_code`. Set from the row the database
  /// returns after an insert, never guessed locally.
  ///
  /// Deliberately SEPARATE from [_followUpReportRef]. These were one field
  /// until migration 20260722000017: the follow-up path assigned the report's
  /// display reference here and it was written straight into
  /// `reference_code`, putting an 8-hex prefix of the report's uuid into a
  /// column staff read unredacted. Keep them apart.
  String? _lastTicketReference;

  /// The REPORT's human-facing display reference (`RPT-B34A6055`) for the
  /// follow-up conversation. Display and prompt-context only: it is shown to
  /// the citizen who filed the report, and passed to the chat-agent function so
  /// the assistant can say which report it is looking at.
  ///
  /// MUST NEVER be written to `concern_tickets.reference_code` — it is derived
  /// from the report id, and the database now rejects it (the trigger allowlists
  /// `^LGU-\d{8}-\d{5}$`). It is also the seed for the Hive box name, which is
  /// why it stays report-derived: see [_boxNameForReport].
  String? _followUpReportRef;

  String? _followUpReportStatus;
  String? _followUpDepartment;
  String? _followUpReportId;
  String? _followUpReportCategory;
  String? _lastTicketId;
  // The connected staff member's public identity, fetched on connect so the
  // header can show the real person (name + photo). Cleared when the chat ends.
  String? _agentName;
  String? _agentPhotoUrl;
  bool _isAgentTyping = false;
  /// Set by [_callAgent]: true when the last reply came from the on-device
  /// fallback brain (AI unavailable) rather than the Groq function. Read by the
  /// consumer branches so the message is flagged + shown with an offline chip.
  bool _lastReplyOffline = false;
  int _unreadCount = 0;
  bool _isViewing = false;
  bool _disposed = false;
  int _sessionId = 0;
  RealtimeChannel? _agentChannel;
  RealtimeChannel? _ticketStatusChannel;

  /// Backstop for [_ticketStatusChannel]. Runs only while the citizen is joined
  /// to a live staff chat, and re-reads the ticket's status on an interval.
  ///
  /// WHY A POLL EXISTS BESIDE A WORKING SUBSCRIPTION: the end-of-chat signal is
  /// a SINGLE realtime event. Realtime replays nothing, so if that one UPDATE
  /// lands while the socket is down — backgrounded phone, sleeping browser tab,
  /// a few seconds of bad signal, a channel that joined with an error — the
  /// citizen never learns the chat ended and the rating card simply never
  /// appears. Until they navigate away and reopen the chat, which is the only
  /// other thing that re-reads the status ([onChatOpened]). That is exactly the
  /// "rating only shows up after I move between screens" report.
  ///
  /// It is deliberately NOT a replacement for the subscription: the socket
  /// still delivers the card in well under a second in the normal case. This
  /// only bounds the worst case. One `select status` on one row per tick, and
  /// only during an active live chat — no live chat, no timer, no query.
  Timer? _statusPollTimer;
  static const _statusPollInterval = Duration(seconds: 10);

  /// Post-chat rating state. When a staff member ends the live conversation the
  /// citizen is asked to rate it; [_submittedRating] locks in their score.
  bool _awaitingRating = false;
  int _submittedRating = 0;

  /// A message the citizen typed that could not be delivered because the staff
  /// member ended the chat in the same instant (the ticket_messages INSERT is
  /// rejected with 42501 once the ticket is terminal — migration
  /// 20260722000005 phase 3). Held so the text is never silently lost: the
  /// "Need more help?" action carries it into the new bot conversation. See
  /// [consumeUndeliveredText].
  String? _undeliveredText;

  bool _connectAfterTicket = false;
  bool _isGhostTicket = false;
  String? _cName, _cNumber, _cAddress, _cEmail, _cNote;
  int _detailAttempts = 0;
  DateTime? _lastSendAt;
  static const _minSendGap = Duration(milliseconds: 1500);

  Timer? _idleTimer;
  static const _idleDuration = Duration(minutes: 15);

  // ── Public getters ────────────────────────────────────────────────────
  List<ChatMsg> get messages => List.unmodifiable(_messages);
  ConversationStage get stage => _stage;
  ConcernCategory? get category => _category;
  bool get isAgentTyping => _isAgentTyping;
  int get unreadCount => _unreadCount;
  bool get hasUnread => _unreadCount > 0;

  bool get showCategoryChips =>
      _stage == ConversationStage.awaitingCategory &&
      !_isAgentTyping &&
      identical(this, I);
  bool get showIntentChips =>
      _stage == ConversationStage.awaitingIntent &&
      !_isAgentTyping &&
      identical(this, I);
  /// True while the citizen is connected to a live human staff member (vs the
  /// bot). Drives the chat header swapping from "LGU Aparri Agent" to a live
  /// staff identity, and back to the bot once the chat ends.
  bool get isConnectedToStaff =>
      _stage == ConversationStage.connectedToAgent;

  /// The department the connected staff belongs to (for the header label), from
  /// whichever flow opened the live chat. Null when not connected / unknown.
  String? get connectedDepartment =>
      isConnectedToStaff ? (_category?.department ?? _followUpDepartment) : null;

  /// The connected staff member's real name once fetched (else null → the header
  /// falls back to the department label).
  String? get connectedStaffName => isConnectedToStaff ? _agentName : null;

  /// The connected staff member's photo URL once fetched.
  String? get connectedStaffPhotoUrl =>
      isConnectedToStaff ? _agentPhotoUrl : null;

  bool get showBackToMenu =>
      _stage == ConversationStage.askingQuestion && !_isAgentTyping;
  bool get showContactConfirm =>
      _stage == ConversationStage.confirmingContact && !_isAgentTyping;
  bool get isTerminal =>
      _stage == ConversationStage.ticketCreated ||
      _stage == ConversationStage.timedOut ||
      _stage == ConversationStage.ended;

  /// True while the citizen should see the star-rating card (staff ended the
  /// chat and they haven't rated yet). Consumed by the chat screen.
  bool get showRatingBar => _awaitingRating && _submittedRating == 0;
  int get submittedRating => _submittedRating;

  /// Returns (and clears) any message the citizen typed that lost the send/end
  /// race, so the caller can drop it into the composer of the new bot
  /// conversation. Null when there is nothing pending. See [_undeliveredText].
  String? consumeUndeliveredText() {
    final t = _undeliveredText;
    _undeliveredText = null;
    return t;
  }

  String? get lastTicketReference => _lastTicketReference;
  String? get lastTicketId => _lastTicketId;
  String? get followUpReportRef => _followUpReportRef;

  // ── Lifecycle ─────────────────────────────────────────────────────────

  /// Drops everything that keeps a live-chat conversation talking to the
  /// server: both realtime channels and the status-poll backstop.
  ///
  /// ONE helper rather than the four inline copies this replaced, because
  /// [_statusPollTimer] must die at every one of those sites. A teardown that
  /// forgets it leaves a timer polling a conversation that no longer exists —
  /// the same orphaned-timer shape documented in StaffIntervalPoll.
  ///
  /// NOT used by [_onAgentEnded], which deliberately keeps the message channel
  /// open for a moment longer; see the note there.
  void _teardownLiveChannels() {
    _agentChannel?.unsubscribe();
    _agentChannel = null;
    _ticketStatusChannel?.unsubscribe();
    _ticketStatusChannel = null;
    _cancelStatusPoll();
  }

  @override
  void dispose() {
    _disposed = true;
    _sessionId++;
    _cancelIdleTimer();
    _teardownLiveChannels();
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  Future<void> init() async {
    await _loadCache();
    if (_messages.isNotEmpty) {
      _maybeStartIdleTimer();
    }
    if (_stage == ConversationStage.connectedToAgent && _lastTicketId != null) {
      _startAgentSubscription();
    }
  }

  Future<void> _rebindToCurrentUser() async {
    _sessionId++;
    _cancelIdleTimer();
    _teardownLiveChannels();
    _awaitingRating = false;
    _submittedRating = 0;
    _messages.clear();
    _stage = ConversationStage.greeting;
    _category = null;
    _pendingDetails = null;
    _lastTicketReference = null;
    _lastTicketId = null;
    _followUpReportStatus = null;
    _followUpDepartment = null;
    _followUpReportId = null;
    _followUpReportCategory = null;
    _followUpReportRef = null;
    _isGhostTicket = false;
    _isAgentTyping = false;
    _unreadCount = 0;
    _lastSendAt = null;

    _activeBoxName = _scoped(_baseBox);
    await _loadCache();
    if (_messages.isNotEmpty) _maybeStartIdleTimer();
    if (_stage == ConversationStage.connectedToAgent && _lastTicketId != null) {
      _startAgentSubscription();
    }
    notifyListeners();
  }

  void onChatOpened({bool isFollowUp = false}) {
    _isViewing = true;
    _unreadCount = 0;
    _markUserMessagesSeen();

    if (!isFollowUp && _stage == ConversationStage.followUp) {
      _sessionId++;
      _cancelIdleTimer();
      _teardownLiveChannels();
      _awaitingRating = false;
      _submittedRating = 0;
      _messages.clear();
      _activeBoxName = _scoped(_baseBox);
      _stage = ConversationStage.greeting;
      _lastTicketReference = null;
      _lastTicketId = null;
      _followUpReportStatus = null;
      _followUpDepartment = null;
      _followUpReportId = null;
      _followUpReportCategory = null;
      _followUpReportRef = null;
      _isGhostTicket = false;
      _category = null;
      _pendingDetails = null;
    }

    notifyListeners();

    // Every time the chat is opened while "connected", make sure the live
    // subscription is running and re-check the ticket status — this is what
    // catches a chat the staff ended while the citizen's app was closed.
    if (_stage == ConversationStage.connectedToAgent && _lastTicketId != null) {
      if (_agentChannel == null) {
        _startAgentSubscription(); // also verifies status + arms the backstop
      } else {
        unawaited(_verifyAgentStatus(_lastTicketId!, _sessionId));
        // Re-arm the backstop too. A surviving channel is not proof the poll
        // survived with it, and this is the branch a returning citizen takes.
        _startStatusPoll(_lastTicketId!, _sessionId);
      }
    }

    if (_messages.isEmpty &&
        _stage == ConversationStage.greeting &&
        !_isAgentTyping) {
      _kickoff();
    }
  }

  void onChatClosed() {
    _isViewing = false;
  }

  Future<void> clearOnLogout() async {
    await _resetAll(reason: _ResetReason.logout);
  }

  Future<void> startNewConversation() async {
    if (!isTerminal) return;
    await _resetAll(reason: _ResetReason.userRequested);
  }

  /// Synchronous visible reset — screen opens instantly with a typing bubble
  /// and can never show another report's messages.
  void _beginFreshFollowUpSync({
    required String reportRef,
    required String reportCategory,
    required String reportStatus,
    required String reportId,
    required String reportDepartment,
    required String boxName,
  }) {
    _sessionId++;
    _cancelIdleTimer();
    _teardownLiveChannels();
    _awaitingRating = false;
    _submittedRating = 0;

    _messages.clear();
    _stage = ConversationStage.followUp;
    _category = null;
    _pendingDetails = null;
    // The report's display reference — NOT the ticket's. _lastTicketReference
    // stays null until the database hands back a real reference_code.
    _followUpReportRef = reportRef;
    _lastTicketReference = null;
    _followUpReportStatus = reportStatus;
    _followUpDepartment = reportDepartment;
    _followUpReportId = reportId;
    _followUpReportCategory = reportCategory;
    _lastTicketId = null;
    _isGhostTicket = false;
    _unreadCount = 0;
    _isViewing = true;
    _isAgentTyping = true; // typing bubble shows immediately
    _activeBoxName = boxName;

    notifyListeners(); // renders empty + typing, right away
  }

  /// Loads the greeting in the background. NOT awaited by the caller.
  Future<void> _fetchFollowUpGreeting(int session, Box b) async {
    if (session != _sessionId) return;
    await b.clear();
    if (session != _sessionId) return;

    final payload = {
      'stage': 'followUp',
      'category': _followUpReportCategory,
      'department': _followUpDepartment,
      'history': <Map>[],
      'userMessage': '__followup__',
      'reportRef': _followUpReportRef,
      'reportStatus': _followUpReportStatus,
    };

    String greeting;
    var greetingOffline = false;
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'chat-agent',
        body: payload,
      );
      if (session != _sessionId) return;
      final data = res.data;
      final reply = (data is Map && data['reply'] is String)
          ? (data['reply'] as String).trim()
          : '';
      if (reply.isNotEmpty) {
        greeting = reply;
      } else {
        greeting = _followUpFallbackGreeting();
        greetingOffline = true;
      }
    } catch (_) {
      if (session != _sessionId) return;
      greeting = _followUpFallbackGreeting();
      greetingOffline = true;
    }

    if (session != _sessionId) return;
    await _agentSay(greeting, session, skipTyping: true, offline: greetingOffline);
    if (session != _sessionId) return;
    _maybeStartIdleTimer();
    notifyListeners();
    _persist();
  }

  String _followUpFallbackGreeting() =>
      'I can see your report ${_followUpReportRef ?? ''} about '
      '${_followUpReportCategory ?? 'your concern'} '
      '(Status: ${_followUpReportStatus ?? 'pending'}). How can I help you po?';

  Future<void> openFollowUp({
    required String reportRef,
    required String reportCategory,
    required String reportStatus,
    required String reportId,
    required String reportDepartment,
  }) async {
    final boxName = _boxNameForReport(reportRef);

    // Already showing this exact report — instant.
    if (_activeBoxName == boxName && _messages.isNotEmpty) {
      _unreadCount = 0;
      _isViewing = true;
      notifyListeners();
      return;
    }

    await _registerFollowUpBox(boxName);
    final b = await Hive.openBox(boxName);
    final saved = b.get('messages') as List?;
    final hasSaved = saved != null && saved.isNotEmpty;

    if (hasSaved) {
      _sessionId++;
      _cancelIdleTimer();
      _teardownLiveChannels();
      _activeBoxName = boxName;

      _followUpReportStatus = reportStatus;
      _followUpDepartment = reportDepartment;
      _followUpReportId = reportId;
      _followUpReportCategory = reportCategory;
      _unreadCount = 0;
      _isAgentTyping = false;
      _isViewing = true;

      final tempMessages = <ChatMsg>[];
      for (final m in saved) {
        tempMessages.add(ChatMsg.fromJson(Map<String, dynamic>.from(m)));
      }

      final stageIdx = b.get('stage', defaultValue: 0) as int;
      _stage = ConversationStage
          .values[stageIdx.clamp(0, ConversationStage.values.length - 1)];
      final ci = b.get('category') as int?;
      _category = ci != null ? ConcernCategory.values[ci] : null;
      _restoreReferences(b);
      // A resumed follow-up thread must show the report it is about, even if
      // the cached box predates the split and carried no 'followUpRef'.
      _followUpReportRef ??= reportRef;
      _lastTicketId = b.get('lastTicketId') as String?;
      _isGhostTicket = b.get('isGhostTicket', defaultValue: false) as bool;
      _awaitingRating = b.get('awaitingRating', defaultValue: false) as bool;
      _submittedRating = b.get('submittedRating', defaultValue: 0) as int;

      _messages
        ..clear()
        ..addAll(tempMessages);

      if (_stage == ConversationStage.connectedToAgent &&
          _lastTicketId != null) {
        _startAgentSubscription();
      }
      notifyListeners();
      _maybeStartIdleTimer();
      return;
    }

    _beginFreshFollowUpSync(
      reportRef: reportRef,
      reportCategory: reportCategory,
      reportStatus: reportStatus,
      reportId: reportId,
      reportDepartment: reportDepartment,
      boxName: boxName,
    );
    unawaited(_fetchFollowUpGreeting(_sessionId, b));
  }

  // ── User actions ──────────────────────────────────────────────────────

  Future<void> sendUserText(String raw) async {
    final text = raw.trim();
    if (text.isEmpty || _isAgentTyping || isTerminal) return;

    final now = DateTime.now();
    if (_lastSendAt != null && now.difference(_lastSendAt!) < _minSendGap) {
      return;
    }
    _lastSendAt = now;

    final session = _sessionId;
    final msg = ChatMsg(text: text, isUser: true, time: DateTime.now());
    _messages.add(msg);
    if (_messages.length > 200) {
      _messages.removeRange(0, _messages.length - 200);
    }
    _cancelIdleTimer();
    notifyListeners();
    _persist();

    Future.delayed(const Duration(milliseconds: 650), () {
      if (session != _sessionId) return;
      if (!_messages.contains(msg)) return;
      // Don't clobber a delivery that already failed (or advanced further).
      if (msg.status != MessageStatus.sent) return;
      msg.status = MessageStatus.delivered;
      notifyListeners();
      _persist();
    });

    await _routeUserMessage(msg, session);
  }

  /// Retries a failed outgoing message (the "Resend" affordance). Only messages
  /// that failed to reach staff are retried through the ticket; anything else
  /// re-runs the normal route.
  Future<void> resendMessage(ChatMsg msg) async {
    if (msg.status != MessageStatus.failed) return;
    msg.status = MessageStatus.sent;
    notifyListeners();
    _persist();
    final session = _sessionId;
    if (_stage == ConversationStage.connectedToAgent) {
      await _sendToStaff(msg, session);
    } else {
      await _routeUserMessage(msg, session);
    }
  }

  /// Removes a message locally (the "Delete" affordance on a failed send). Only
  /// meaningful for a failed message that never persisted to the DB.
  void deleteMessage(ChatMsg msg) {
    if (_messages.remove(msg)) {
      notifyListeners();
      _persist();
    }
  }

  Future<void> pickCategory(ConcernCategory c) async {
    if (_stage != ConversationStage.awaitingCategory) return;
    _category = c;
    await sendUserText(c.label);
  }

  // ── pickIntent: "Report Issue" removed — only question & liveAgent ────
  Future<void> pickIntent(ChatIntent intent) async {
    if (_stage != ConversationStage.awaitingIntent) return;
    final session = _sessionId;

    switch (intent) {
      case ChatIntent.question:
        _stage = ConversationStage.askingQuestion;
        notifyListeners();
        _persist();
        await _agentSay(
          'Sure po! Ano po ang gusto ninyong itanong? '
          'You can type your question below — like how to get a document, '
          'office hours, or the steps for a service. 💬',
          session,
        );
        if (session != _sessionId) return;
        _maybeStartIdleTimer();
        break;

      case ChatIntent.liveAgent:
        await _startLiveAgentFromMenu(session);
        break;
    }
  }

  Future<void> backToMenu() async {
    final session = _sessionId;
    _stage = ConversationStage.awaitingIntent;
    _category = null;
    _connectAfterTicket = false;
    notifyListeners();
    _persist();
    await _agentSay(
      'Sige po! Ano pa po ang maitutulong ko? Pumili lang po. 😊',
      session,
      skipTyping: true,
    );
    if (session != _sessionId) return;
    _maybeStartIdleTimer();
  }

  String? _extractAction(String raw) {
    final m = RegExp(r'\[ACTION:(REPORT|AGENT|END)\]').firstMatch(raw);
    return m?.group(1);
  }

  String _stripAction(String raw) =>
      raw.replaceAll(RegExp(r'\[ACTION:(REPORT|AGENT|END)\]'), '').trim();

  Future<void> _goToReport(int session, {String? aiReply}) async {
    await _agentSay(
      (aiReply != null && aiReply.isNotEmpty)
          ? aiReply
          : 'Para mag-report ng concern, i-tap po ang "Report Issue" button '
                'sa Quick Actions section sa Home screen ng GovPulse app. 📋',
      session,
      skipTyping: true,
    );
    if (session != _sessionId) return;
    _stage = ConversationStage.awaitingIntent;
    _maybeStartIdleTimer();
    notifyListeners();
    _persist();
  }

  Future<void> _startLiveAgentFromMenu(int session) async {
    _connectAfterTicket = true;
    _stage = ConversationStage.awaitingCategory;
    notifyListeners();
    _persist();
    await _agentSay(
      'Sige po! Para makonekta kayo sa tamang staff, '
      'piliin po ang kategorya ng inyong concern. 🧑‍💼',
      session,
    );
    if (session != _sessionId) return;
    _maybeStartIdleTimer();
  }

  Future<void> confirmContact() async {
    if (_stage != ConversationStage.confirmingContact) return;
    await _submitTicket(_sessionId);
  }

  Future<void> editContact() async {
    if (_stage != ConversationStage.confirmingContact) return;
    final session = _sessionId;
    _stage = ConversationStage.correctingContact;
    notifyListeners();
    _persist();
    await _agentSay(
      'Sige po, paki-type lang po ang tamang contact details '
      '(pangalan, numero, address). 📝',
      session,
    );
    if (session != _sessionId) return;
    _maybeStartIdleTimer();
  }

  // ── Conversation routing ──────────────────────────────────────────────

  Future<void> _routeUserMessage(ChatMsg msg, int session) async {
    switch (_stage) {
      case ConversationStage.greeting:
      case ConversationStage.awaitingCategory:
        // Category was picked — this is a live agent request only
        if (_category != null && _connectAfterTicket) {
          _pendingDetails = 'Live agent request';
          await _submitTicket(session);
          break;
        }

        final raw = await _callAgent(session);
        if (session != _sessionId) return;
        final action = _extractAction(raw);
        final cleaned = _stripAction(raw);

        if (action == 'REPORT') {
          await _goToReport(
            session,
            aiReply: cleaned.isNotEmpty ? cleaned : null,
          );
        } else if (action == 'AGENT') {
          if (cleaned.isNotEmpty) {
            await _agentSay(cleaned, session, skipTyping: true);
          }
          if (session != _sessionId) return;
          await _startLiveAgentFromMenu(session);
        } else if (action == 'END') {
          await _agentSay(
            cleaned.isNotEmpty ? cleaned : 'Salamat po! Ingat kayo. 😊',
            session,
            skipTyping: true,
            offline: _lastReplyOffline,
          );
          if (session != _sessionId) return;
          _stage = ConversationStage.ended;
          _maybeStartIdleTimer();
        } else {
          await _agentSay(
            raw,
            session,
            skipTyping: true,
            offline: _lastReplyOffline,
          );
          if (session != _sessionId) return;
          _stage = ConversationStage.awaitingIntent;
          _maybeStartIdleTimer();
        }
        break;

      case ConversationStage.awaitingDetails:
        // No longer used — reporting is done via Quick Actions on Home screen.
        break;
      case ConversationStage.followUp:
        final raw = await _callAgent(session);
        if (session != _sessionId) return;
        final action = _extractAction(raw);
        final cleaned = _stripAction(raw);

        if (action == 'REPORT') {
          await _goToReport(
            session,
            aiReply: cleaned.isNotEmpty ? cleaned : null,
          );
        } else if (action == 'AGENT') {
          if (cleaned.isNotEmpty) {
            await _agentSay(cleaned, session, skipTyping: true);
          }
          if (session != _sessionId) return;
          await _connectLiveAgentForFollowUp(session);
        } else if (action == 'END') {
          await _agentSay(
            cleaned.isNotEmpty ? cleaned : 'Salamat po! Ingat kayo. 😊',
            session,
            skipTyping: true,
            offline: _lastReplyOffline,
          );
          if (session != _sessionId) return;
          _stage = ConversationStage.ended;
        } else {
          await _agentSay(
            cleaned,
            session,
            skipTyping: true,
            offline: _lastReplyOffline,
          );
          if (session != _sessionId) return;
          _maybeStartIdleTimer();
        }
        break;

      case ConversationStage.askingQuestion:
        final raw = await _callAgent(session);
        if (session != _sessionId) return;
        final action = _extractAction(raw);
        final cleaned = _stripAction(raw);

        if (action == 'REPORT') {
          await _goToReport(
            session,
            aiReply: cleaned.isNotEmpty ? cleaned : null,
          );
        } else if (action == 'AGENT') {
          if (cleaned.isNotEmpty) {
            await _agentSay(cleaned, session, skipTyping: true);
          }
          if (session != _sessionId) return;
          await _startLiveAgentFromMenu(session);
        } else if (action == 'END') {
          await _agentSay(
            cleaned.isNotEmpty ? cleaned : 'Salamat po! Ingat kayo. 😊',
            session,
            skipTyping: true,
            offline: _lastReplyOffline,
          );
          if (session != _sessionId) return;
          _stage = ConversationStage.ended;
        } else {
          await _agentSay(
            cleaned,
            session,
            skipTyping: true,
            offline: _lastReplyOffline,
          );
          if (session != _sessionId) return;
          _maybeStartIdleTimer();
        }
        break;

      case ConversationStage.connectedToAgent:
        await _sendToStaff(msg, session);
        break;

      case ConversationStage.confirmingContact:
      case ConversationStage.correctingContact:
        // No longer used — reporting is done via Quick Actions on Home screen.
        break;

      case ConversationStage.submitting:
      case ConversationStage.ticketCreated:
      case ConversationStage.timedOut:
      case ConversationStage.ended:
        break;

      case ConversationStage.awaitingIntent:
        final raw = await _callAgent(session);
        if (session != _sessionId) return;
        final action = _extractAction(raw);
        final cleaned = _stripAction(raw);

        if (action == 'REPORT') {
          await _goToReport(
            session,
            aiReply: cleaned.isNotEmpty ? cleaned : null,
          );
        } else if (action == 'AGENT') {
          if (cleaned.isNotEmpty) {
            await _agentSay(cleaned, session, skipTyping: true);
          }
          if (session != _sessionId) return;
          await _startLiveAgentFromMenu(session);
        } else if (action == 'END') {
          await _agentSay(
            cleaned.isNotEmpty ? cleaned : 'Salamat po! Ingat kayo. 😊',
            session,
            skipTyping: true,
            offline: _lastReplyOffline,
          );
          if (session != _sessionId) return;
          _stage = ConversationStage.ended;
        } else {
          _stage = ConversationStage.askingQuestion;
          notifyListeners();
          await _agentSay(
            cleaned,
            session,
            skipTyping: true,
            offline: _lastReplyOffline,
          ); // reuse first response
          if (session != _sessionId) return;
          _maybeStartIdleTimer();
        }
        break;
    }

    if (session != _sessionId) return;
    notifyListeners();
    _persist();
  }

  // ── Ticket submission ─────────────────────────────────────────────────

  Future<void> _submitTicket(int session) async {
    if (_category == null) return;
    if (!_connectAfterTicket && _pendingDetails == null) return;

    _stage = ConversationStage.submitting;
    notifyListeners();

    // ── Live agent path — silent ghost ticket, then connect ───────────────
    if (_connectAfterTicket) {
      try {
        final ticket = await _withUniqueRef(
          (reference) => TicketRepository.I.createGhostTicket(
            category: _category!,
            referenceCode: reference,
          ),
        );
        if (session != _sessionId) return;
        _lastTicketReference = ticket['reference_code'] as String?;
        _lastTicketId = ticket['id']?.toString();
        _isGhostTicket = true;
        _connectAfterTicket = false;
      } catch (e) {
        debugPrint('createGhostTicket failed: $e');
        if (session != _sessionId) return;
        await _agentSay(
          '⚠️ Something went wrong. Please try again po.',
          session,
        );
        _stage = ConversationStage.awaitingIntent;
        notifyListeners();
        _persist();
        return;
      }
      await requestLiveAgent();
      notifyListeners();
      _persist();
      return;
    }

    // ── Report path — show messages, create real ticket ───────────────────
    await _agentSay('Thanks po! Logging your concern now…', session);
    if (session != _sessionId) return;

    try {
      final staffId = await TicketRepository.I.findAvailableStaffId(
        _category!.department,
      );

      final ticket = await _withUniqueRef(
        (reference) => TicketRepository.I.createTicket(
          category: _category!,
          details: _pendingDetails!,
          referenceCode: reference,
          contactName: _cName,
          contactNumber: _cNumber,
          contactAddress: _cAddress,
          contactEmail: _cEmail,
          contactNote: _cNote,
        ),
      );

      if (session != _sessionId) return;

      _lastTicketReference = ticket['reference_code'] as String?;
      _lastTicketId = ticket['id']?.toString();

      if (staffId != null) {
        await TicketRepository.I.promoteTicket(
          ticketId: ticket['id']?.toString() ?? '',
          staffUserId: staffId,
        );
        await _agentSay(
          'A staff member from the ${_category!.department} is online and '
          'will be with you shortly. Reference: ${ticket['reference_code']}',
          session,
        );
        if (session != _sessionId) return;
        _stage = ConversationStage.connectedToAgent;
        _startAgentSubscription();
      } else {
        await _agentSay(
          'Your concern has been logged and forwarded to the '
          '${_category!.department}, po. 📋\n\n'
          'Reference: ${ticket['reference_code']}\n\n'
          'Our team will follow up within 24–48 hours. '
          'Thank you for reaching out to LGU Aparri!',
          session,
        );
        if (session != _sessionId) return;
        _stage = ConversationStage.ticketCreated;
      }
    } on TicketException catch (e) {
      if (session != _sessionId) return;
      await _agentSay('⚠️ ${e.message}\n\nPlease try again later.', session);
      if (session != _sessionId) return;
      _stage = ConversationStage.awaitingDetails;
    } catch (e, st) {
      debugPrint('createTicket failed: $e\n$st');
      if (session != _sessionId) return;

      final msg = e.toString();
      final isRateLimit =
          msg.contains('daily limit') ||
          msg.contains('rate limit') ||
          msg.contains('Please try again tomorrow');

      if (isRateLimit) {
        await _agentSay(
          'Pasensya na po — naabot na ninyo ang daily limit na 5 reports '
          'ngayong araw. 🙏 Paki-subukan po ulit bukas.\n\n'
          'Kung urgent po, pwede kayong direktang pumunta sa LGU Aparri office. '
          'Salamat po!',
          session,
          skipTyping: true,
        );
        if (session != _sessionId) return;
        _stage = ConversationStage.ticketCreated;
      } else {
        await _agentSay(
          '⚠️ Something went wrong submitting your concern. '
          'Please check your connection and try again.',
          session,
        );
        if (session != _sessionId) return;
        _stage = ConversationStage.awaitingDetails;
      }
    }

    if (session != _sessionId) return;
    _cancelIdleTimer();
    notifyListeners();
    _persist();
  }

  // ── AI call ───────────────────────────────────────────────────────────

  /// How many past messages ride along with each chat-agent call. Every token
  /// in that payload is spent against a Groq quota metered per API KEY — 8K
  /// tokens/minute across the whole app, not per citizen — so an untrimmed
  /// payload does not just cost latency, it brings the next citizen's 429
  /// forward. See the v5 notes in supabase/functions/chat-agent/index.ts.
  static const _historyMessages = 6;

  /// An event blurb long enough to be useful, short enough that five of them
  /// don't outweigh the citizen's actual question.
  static const _eventDescriptionLimit = 200;

  Future<String> _callAgent(int session) async {
    final priorMessages = _messages.take(_messages.length - 1).toList();
    // Capped for EVERY stage. The cap used to apply only to askingQuestion and
    // followUp; the other stages sent the whole transcript, which grew without
    // bound over a long chat and quietly ate the per-minute token budget.
    final history = priorMessages
        .skip(
          priorMessages.length > _historyMessages
              ? priorMessages.length - _historyMessages
              : 0,
        )
        .map((m) => {'text': m.text, 'isUser': m.isUser})
        .toList();
    final latest = _messages.last;

    List<Map<String, dynamic>> events = [];
    if (_stage == ConversationStage.askingQuestion) {
      events = (await TicketRepository.I.getLatestEvents())
          .map(_trimEvent)
          .toList();
    }
    if (session != _sessionId) return '';

    final payload = {
      'stage': _stage.name,
      'category': _stage == ConversationStage.followUp
          ? _followUpReportCategory
          : _category?.label,
      'department': _stage == ConversationStage.followUp
          ? _followUpDepartment
          : _category?.department,
      'history': history,
      'userMessage': latest.text,
      'events': events,
      if (_stage == ConversationStage.followUp) ...{
        'reportRef': _followUpReportRef,
        'reportStatus': _followUpReportStatus,
      },
    };

    try {
      final res = await Supabase.instance.client.functions.invoke(
        'chat-agent',
        body: payload,
      );

      if (session != _sessionId) return '';

      final data = res.data;
      if (data is Map && data['reply'] is String) {
        final reply = (data['reply'] as String).trim();
        if (reply.isNotEmpty) {
          _lastReplyOffline = false;
          return reply;
        }
      }

      debugPrint('ChatService: unexpected edge function response: $data');
      return _offlineReply(latest.text);
    } catch (e) {
      // AI unavailable (offline / rate-limited / usage exhausted) → fall back to
      // the on-device brain so the assistant stays useful (hybrid).
      debugPrint('ChatService: edge function error: $e');
      if (session != _sessionId) return '';
      return _offlineReply(latest.text);
    }
  }

  /// Drops an event row down to what Kuya Gov actually reads out. The full row
  /// carries a free-text description that can run to several paragraphs, and
  /// five of those are sent on every single question turn.
  Map<String, dynamic> _trimEvent(Map<String, dynamic> e) {
    final desc = (e['description'] as String?)?.trim() ?? '';
    return {
      'title': e['title'],
      'event_date': e['event_date'],
      'event_time': e['event_time'],
      'location': e['location'],
      'category': e['category'],
      if (desc.isNotEmpty) 'description': _clip(desc),
    };
  }

  /// Truncates [text] to [_eventDescriptionLimit] without cutting a surrogate
  /// pair in half — an emoji sliced down the middle leaves a lone surrogate
  /// that is not valid UTF-8, and this string is about to be JSON-encoded.
  static String _clip(String text) {
    if (text.length <= _eventDescriptionLimit) return text;
    var end = _eventDescriptionLimit;
    final last = text.codeUnitAt(end - 1);
    if (last >= 0xD800 && last <= 0xDBFF) end -= 1; // high surrogate, no tail
    return '${text.substring(0, end)}…';
  }

  /// On-device fallback answer for [userText], tagged with [_lastReplyOffline].
  String _offlineReply(String userText) {
    _lastReplyOffline = true;
    return LocalAssistant.reply(
      userText,
      followUp: _stage == ConversationStage.followUp,
      reportRef: _followUpReportRef,
      reportStatus: _followUpReportStatus,
      reportCategory: _followUpReportCategory,
    );
  }

  Future<void> requestLiveAgent() async {
    if (_lastTicketId == null) return;
    if (_stage == ConversationStage.connectedToAgent) return;

    final session = _sessionId;
    final dept = _category?.department ?? 'the LGU';

    await _agentSay(
      'Let me check if a staff member is available, po… 🔎',
      session,
    );
    if (session != _sessionId) return;

    final staffId = await TicketRepository.I.findAvailableStaffId(
      _category?.department ?? '',
    );
    if (session != _sessionId) return;

    if (staffId != null) {
      _isGhostTicket = false;
      try {
        await TicketRepository.I.promoteTicket(
          ticketId: _lastTicketId!,
          staffUserId: staffId,
        );
      } catch (e) {
        debugPrint('promoteTicket failed: $e');
      }
      if (session != _sessionId) return;

      _stage = ConversationStage.connectedToAgent;
      _cancelIdleTimer();
      notifyListeners();
      _persist();

      await _agentSay(
        'You are now connected to a staff member from $dept, po. '
        'Please go ahead with your concern. 🧑‍💼',
        session,
      );
      _startAgentSubscription();
    } else {
      // No staff available — delete the ghost ticket and go back to menu
      if (_lastTicketId != null && _isGhostTicket) {
        await TicketRepository.I.deleteGhostTicketIfUnused(_lastTicketId!);
        _lastTicketId = null;
        _lastTicketReference = null;
        _isGhostTicket = false;
      }
      _stage = ConversationStage.awaitingIntent;
      _category = null;
      notifyListeners();
      _persist();
      await _agentSay(
        'Sorry po, walang available na staff ngayon. 😔\n\n'
        'Paki-subukan po ulit mamaya. Salamat po!',
        session,
      );
      if (session != _sessionId) return;
      _maybeStartIdleTimer();
    }
  }

  /// Live-agent connect for the follow-up flow.
  /// Never asks for a category and never creates a duplicate ghost ticket —
  /// it reuses the follow-up ticket and the report's known department.
  Future<void> _connectLiveAgentForFollowUp(int session) async {
    if (_stage == ConversationStage.connectedToAgent) return;

    final deptName = _followUpDepartment ?? 'the LGU';

    await _agentSay(
      'Let me check if a staff member is available, po… 🔎',
      session,
    );
    if (session != _sessionId) return;

    // If startFollowUp's ticket insert failed, recreate it now from the
    // report we're following up on — no category prompt needed.
    if (_lastTicketId == null &&
        _followUpReportId != null &&
        _followUpReportCategory != null &&
        _followUpDepartment != null) {
      try {
        // A GENERATED reference — never _followUpReportRef. That value is
        // derived from the report id, and writing it here is the leak migration
        // 20260722000017 closes; the database now rejects it outright.
        // The report linkage travels in report_id, which staff cannot see.
        final ticket = await _withUniqueRef(
          (reference) => TicketRepository.I.createFollowUpTicket(
            reportId: _followUpReportId!,
            category: _followUpReportCategory!,
            department: _followUpDepartment!,
            referenceCode: reference,
          ),
        );
        if (session != _sessionId) return;
        _lastTicketId = ticket['id']?.toString();
        // Take the reference back from the row the database actually wrote.
        _lastTicketReference = ticket['reference_code'] as String?;
        _isGhostTicket = true;
      } catch (e) {
        // MUST NOT fall through. Without this return, control reached the
        // "no staff available" branch below and told the citizen nobody was on
        // duty — which is false, and sends staff chasing a staffing problem
        // that does not exist. A ticket we could not create is our failure, and
        // it says so.
        debugPrint('follow-up ticket failed: $e');
        if (session != _sessionId) return;
        await _agentSay(
          '⚠️ Hindi po namin ma-open ang chat para sa report na ito ngayon. '
          'Hindi ito tungkol sa availability ng staff — may problema po sa '
          'aming sistema. Paki-subukan po ulit mamaya.',
          session,
        );
        if (session != _sessionId) return;
        _stage = ConversationStage.followUp;
        notifyListeners();
        _persist();
        return;
      }
    }

    final staffId = await TicketRepository.I.findAvailableStaffId(
      _followUpDepartment ?? '',
    );
    if (session != _sessionId) return;

    if (staffId != null && _lastTicketId != null) {
      _isGhostTicket = false; // promoted to a real live-agent session
      try {
        await TicketRepository.I.promoteTicket(
          ticketId: _lastTicketId!,
          staffUserId: staffId,
        );
      } catch (e) {
        debugPrint('promoteTicket (follow-up) failed: $e');
      }
      if (session != _sessionId) return;

      _stage = ConversationStage.connectedToAgent;
      _cancelIdleTimer();
      notifyListeners();
      _persist();

      await _agentSay(
        'You are now connected to a staff member from $deptName, po. '
        'Please go ahead with your concern. 🧑‍💼',
        session,
      );
      _startAgentSubscription();
    } else {
      // No staff — delete the unused ghost (consistent with the main chat).
      // A later retry recreates the ticket from the report data above.
      if (_lastTicketId != null && _isGhostTicket) {
        await TicketRepository.I.deleteGhostTicketIfUnused(_lastTicketId!);
        if (session != _sessionId) return;
        _lastTicketId = null;
        _isGhostTicket = false;
      }
      _stage = ConversationStage.followUp;
      notifyListeners();
      _persist();
      await _agentSay(
        'Sorry po, walang available na staff ngayon. 😔\n\n'
        'Pwede ko po kayong tulungan dito habang hinihintay, '
        'o subukan po ulit mamaya. Salamat po!',
        session,
      );
      if (session != _sessionId) return;
      _maybeStartIdleTimer();
    }
  }

  Future<void> _sendToStaff(ChatMsg msg, int session) async {
    final ticketId = _lastTicketId;
    if (ticketId == null) return;
    final userId = Supabase.instance.client.auth.currentUser?.id ?? 'citizen';
    try {
      await TicketRepository.I.saveMessage(
        ticketId: ticketId,
        senderId: userId,
        senderType: 'citizen',
        message: msg.text,
      );
      if (session != _sessionId) return;
      msg.status = MessageStatus.delivered;
      notifyListeners();
      _persist();
    } catch (e) {
      debugPrint('sendToStaff failed: $e');
      if (session != _sessionId) return;

      // The send/end race: staff ended the chat in the same instant the citizen
      // hit send, so the ticket_messages INSERT was rejected by RLS with 42501
      // (the status condition added in migration 20260722000005 phase 3). This
      // is NOT a transient failure — resending would hit the same wall, so a
      // "Resend" bubble would be a trap. Instead: pull the undelivered text
      // aside so it is never lost, drop the dead bubble, and end the chat
      // locally (locks the composer, shows the rating card + "Need more help?").
      if (e is PostgrestException && e.code == '42501') {
        _undeliveredText = msg.text;
        _messages.remove(msg);
        notifyListeners();
        _persist();
        _onAgentEnded(session);
        return;
      }

      // Any other failure is treated as transient: surface it so the citizen
      // can resend or delete the bubble.
      msg.status = MessageStatus.failed;
      notifyListeners();
      _persist();
    }
  }

  void _startAgentSubscription() {
    final ticketId = _lastTicketId;
    if (ticketId == null) return;
    _agentChannel?.unsubscribe();
    _ticketStatusChannel?.unsubscribe();
    final session = _sessionId;
    // Start clean so a fresh connect never briefly shows a previous staffer.
    _agentName = null;
    _agentPhotoUrl = null;
    unawaited(_fetchAgentIdentity(ticketId, session));

    _agentChannel = TicketRepository.I.subscribeToTicketMessages(
      ticketId: ticketId,
      onInsert: (row) {
        if (session != _sessionId) return;
        if (row['sender_type'] != 'staff') return;
        final text = (row['text'] as String?)?.trim() ?? '';
        if (text.isEmpty) return;
        _messages.add(ChatMsg(
            text: text, isUser: false, time: DateTime.now(), fromStaff: true));
        if (!_isViewing) _unreadCount++;
        notifyListeners();
        _persist();
      },
    );

    // When the staff member ends the chat, the ticket's status flips — that's
    // the citizen's cue to show the rating card.
    _ticketStatusChannel = TicketRepository.I.subscribeToTicketStatus(
      ticketId: ticketId,
      onStatus: (status) {
        if (session != _sessionId) return;
        if (status == 'resolved' || status == 'ended' || status == 'closed') {
          _onAgentEnded(session);
        }
      },
      // Every (re)join re-reads the row. A rejoin means the socket was down,
      // and realtime does not replay what it missed while it was.
      onJoined: () => unawaited(_verifyAgentStatus(ticketId, session)),
    );

    // Catch a chat the staff already ended while the app was closed — the
    // realtime channel above only sees changes from now on.
    unawaited(_verifyAgentStatus(ticketId, session));
    _startStatusPoll(ticketId, session);
  }

  /// Arms the [_statusPollTimer] backstop for a live chat. Safe to call
  /// repeatedly — the previous timer is always cancelled first, so there is
  /// never more than one in flight.
  void _startStatusPoll(String ticketId, int session) {
    _cancelStatusPoll();
    _statusPollTimer = Timer.periodic(_statusPollInterval, (_) {
      // A poll that outlives its conversation must touch nothing: the session
      // guard inside _verifyAgentStatus already refuses to act, but stopping
      // here also spares the query.
      if (_disposed || session != _sessionId) {
        _cancelStatusPoll();
        return;
      }
      if (_stage != ConversationStage.connectedToAgent) {
        _cancelStatusPoll();
        return;
      }
      unawaited(_verifyAgentStatus(ticketId, session));
    });
  }

  void _cancelStatusPoll() {
    _statusPollTimer?.cancel();
    _statusPollTimer = null;
  }

  /// One-shot check of the ticket's current status on (re)connect; if it's
  /// already terminal, end the chat locally so the citizen gets the rating card
  /// instead of being able to keep typing into a closed conversation.
  Future<void> _verifyAgentStatus(String ticketId, int session) async {
    final status = await TicketRepository.I.fetchTicketStatus(ticketId);
    if (session != _sessionId) return;
    if (status == 'resolved' || status == 'ended' || status == 'closed') {
      _onAgentEnded(session);
    }
  }

  /// Fetches the connected staff member's real name + photo so the header shows
  /// the actual person. Best-effort: on failure (or before the RPC is deployed)
  /// the header just keeps the department label.
  Future<void> _fetchAgentIdentity(String ticketId, int session) async {
    final info = await TicketRepository.I.fetchTicketAgent(ticketId);
    if (info == null || session != _sessionId) return;
    _agentName = (info.name?.isNotEmpty ?? false) ? info.name : null;
    _agentPhotoUrl = (info.photoUrl?.isNotEmpty ?? false) ? info.photoUrl : null;
    notifyListeners();
  }

  /// Called when a staff member ends the live conversation. Closes the live
  /// channels, moves to the terminal `ended` stage and — unless the citizen has
  /// already rated — surfaces the rating card.
  void _onAgentEnded(int session) {
    if (session != _sessionId) return;
    if (_stage == ConversationStage.ended) return; // already ended
    // Keep the message channel alive briefly: the staff's closing message and
    // this status update arrive on separate channels, so the goodbye may still
    // be in flight. It's torn down on dispose / reset / new conversation.
    _ticketStatusChannel?.unsubscribe();
    _ticketStatusChannel = null;
    // The status can never change again in a way this chat cares about, so the
    // backstop stops here rather than at the next teardown.
    _cancelStatusPoll();
    _cancelIdleTimer();
    _isAgentTyping = false;
    _stage = ConversationStage.ended;
    _awaitingRating = _submittedRating == 0;
    if (!_isViewing) _unreadCount++;
    notifyListeners();
    _persist();
  }

  /// Records the citizen's 1–5 star rating for the just-ended conversation and
  /// thanks them. First rating wins; the DB write is best-effort.
  Future<void> submitRating(int stars, {String? comment}) async {
    if (_submittedRating != 0 || stars < 1) return;
    final session = _sessionId;
    _submittedRating = stars.clamp(1, 5);
    _awaitingRating = false;
    notifyListeners();
    _persist();

    final ticketId = _lastTicketId;
    if (ticketId != null) {
      try {
        await TicketRepository.I.rateTicket(
          ticketId,
          _submittedRating,
          comment: comment,
        );
      } catch (e) {
        debugPrint('rateTicket failed: $e');
      }
    }
    if (session != _sessionId) return;
    await _agentSay(
      'Maraming salamat po sa inyong feedback! ⭐ Ingat kayo palagi. 😊',
      session,
      skipTyping: true,
    );
  }

  /// Dismisses the rating card without scoring (the "Maybe later" action).
  void dismissRating() {
    if (!_awaitingRating) return;
    _awaitingRating = false;
    notifyListeners();
    _persist();
  }

  // ── Idle timer ────────────────────────────────────────────────────────
  bool get _stageAwaitsUser =>
      _stage == ConversationStage.awaitingIntent ||
      _stage == ConversationStage.awaitingCategory ||
      _stage == ConversationStage.awaitingDetails ||
      _stage == ConversationStage.askingQuestion ||
      _stage == ConversationStage.followUp ||
      _stage == ConversationStage.confirmingContact ||
      _stage == ConversationStage.correctingContact;

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
    debugPrint('_resetAll: isGhost=$_isGhostTicket ticketId=$_lastTicketId');
    if (_isGhostTicket && _lastTicketId != null) {
      debugPrint('_resetAll: deleting ghost ticket $_lastTicketId');
      // Best effort, and it MUST NOT abort the reset below.
      //
      // On the sign-out path this is a Supabase write issued AFTER
      // `auth.signOut()` has already run — the logout handlers sign out first,
      // then tear the chat down — so with no JWT it fails against RLS by
      // construction. Unguarded, that threw out of _resetAll and skipped every
      // line of state clearing that follows, which is the likeliest origin of
      // the sign-out teardown failure.
      //
      // The userRequested path benefits identically: a ghost ticket that will
      // not delete is no reason to refuse to start a new conversation.
      try {
        await TicketRepository.I.deleteGhostTicketIfUnused(_lastTicketId!);
      } catch (_) {}
    }
    _sessionId++;
    _cancelIdleTimer();
    _teardownLiveChannels();
    _awaitingRating = false;
    _submittedRating = 0;
    _lastSendAt = null;
    _messages.clear();
    _stage = ConversationStage.greeting;
    _category = null;
    _pendingDetails = null;
    _cName = null;
    _cNumber = null;
    _cAddress = null;
    _cEmail = null;
    _cNote = null;
    _detailAttempts = 0;
    _lastTicketReference = null;
    _lastTicketId = null;
    _isGhostTicket = false;
    _isAgentTyping = false;
    _unreadCount = 0;
    _isViewing = true;
    _followUpReportStatus = null;
    _followUpDepartment = null;
    _followUpReportId = null;
    _followUpReportCategory = null;
    _followUpReportRef = null;

    // Guarded so the DISK clear failing cannot strand the IN-MEMORY reset. The
    // two lines below are what actually make this instance forget the previous
    // conversation; leaving them unrun because IndexedDB refused a box is the
    // worst of both worlds — state kept, cache half-gone.
    try {
      final b = await Hive.openBox(_activeBoxName);
      await b.clear();
      await b.flush();
    } catch (_) {}
    _activeBoxName = _baseBox;

    notifyListeners();
    debugPrint('ChatService: reset (reason=${reason.name})');

    if (reason == _ResetReason.userRequested) {
      _kickoff();
    }
  }

  // ── Bot helpers ───────────────────────────────────────────────────────

  Future<void> _kickoff() async {
    final session = _sessionId;

    _isAgentTyping = true;
    notifyListeners();

    final greetingPayload = {
      'stage': 'greeting',
      'category': null,
      'department': null,
      'history': <Map>[],
      'userMessage': '__greeting__',
    };

    const staticGreeting =
        "Good day po! I'm Kuya Gov, your LGU Aparri Support Agent. 👋\n\n"
        "How can I help you today? Please choose an option below.";
    String greeting;
    var greetingOffline = false;
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'chat-agent',
        body: greetingPayload,
      );
      if (session != _sessionId) return;
      final data = res.data;
      final reply = (data is Map && data['reply'] is String)
          ? (data['reply'] as String).trim()
          : '';
      if (reply.isNotEmpty) {
        greeting = reply;
      } else {
        greeting = staticGreeting;
        greetingOffline = true;
      }
    } catch (_) {
      if (session != _sessionId) return;
      greeting = staticGreeting;
      greetingOffline = true;
    }

    if (session != _sessionId) return;
    await _agentSay(greeting, session, skipTyping: true, offline: greetingOffline);

    if (session != _sessionId) return;
    _stage = ConversationStage.awaitingIntent;
    _maybeStartIdleTimer();
    notifyListeners();
    _persist();
  }

  Future<void> _agentSay(
    String text,
    int session, {
    bool skipTyping = false,
    bool offline = false,
  }) async {
    if (session != _sessionId) return;

    if (!skipTyping) {
      _isAgentTyping = true;
      _markUserMessagesSeen();
      notifyListeners();
      await Future.delayed(const Duration(milliseconds: 1200));
    } else {
      await Future.delayed(Duration.zero); // was 400ms
    }

    if (session != _sessionId) return;

    _isAgentTyping = false;
    _messages.add(
      ChatMsg(text: text, isUser: false, time: DateTime.now(), offline: offline),
    );
    if (_messages.length > 200) {
      _messages.removeRange(0, _messages.length - 200);
    }
    if (!_isViewing) _unreadCount++;
    notifyListeners();
    _persist();
  }

  void _markUserMessagesSeen() {
    for (final m in _messages) {
      // A failed send is never "seen" — leave it so the resend/delete UI stays.
      if (m.isUser &&
          m.status != MessageStatus.seen &&
          m.status != MessageStatus.failed) {
        m.status = MessageStatus.seen;
      }
    }
  }

  /// Shape of a reference produced by [_generateRef] — and, since migration
  /// 20260722000017, the only shape `concern_tickets.reference_code` accepts.
  static final RegExp _generatedRefPattern = RegExp(r'^LGU-\d{8}-\d{5}$');

  /// True for the report follow-up surface, false for the main chat agent.
  ///
  /// One class backs two surfaces: [ChatService.I] (main, base box
  /// `chat_cache`) and the per-report instances from [forReport] (base box
  /// `chat_cache_followup_<ref>`). Report-scoped state belongs only to the
  /// latter, and [_baseBox] is fixed at construction so this cannot drift.
  bool get _isFollowUpSurface => _baseBox.startsWith('chat_cache_followup');

  /// Reads the two reference fields out of a Hive box, healing boxes written
  /// before the report-ref / ticket-ref split.
  ///
  /// Legacy boxes stored the REPORT's display reference ('RPT-B34A6055') under
  /// `lastTicketReference`, because one field served both roles. Restoring that
  /// verbatim would put a report-derived value back into the slot that feeds
  /// `reference_code`. Anything not matching the generated shape is therefore
  /// treated as what it actually was — a report reference — and moved across.
  ///
  /// No box is orphaned: the box NAME is still derived from the report ref
  /// (see [_boxNameForReport]), which this change does not touch, so every
  /// cached thread still resolves to the same box.
  void _restoreReferences(Box b) {
    final cached = b.get('lastTicketReference') as String?;
    final looksGenerated =
        cached != null && _generatedRefPattern.hasMatch(cached);

    // Only a generated reference is a real ticket reference. Anything else is
    // either a legacy report ref or junk, and must not be presented as one.
    _lastTicketReference = looksGenerated ? cached : null;

    // SURFACE-SCOPED. The main chat agent has no report context at all, so it
    // never restores one — not from 'followUpRef', not by healing.
    //
    // This guard is load-bearing, not defensive dressing: the pre-split
    // _persist() wrote `'followUpRef': _lastTicketReference`, which on the MAIN
    // chat held that chat's own LGU- ticket reference. Reading it back
    // unconditionally would seed _followUpReportRef on ChatService.I with a
    // value that is not a report reference and describes no report.
    if (!_isFollowUpSurface) {
      _followUpReportRef = null;
      return;
    }

    _followUpReportRef = b.get('followUpRef') as String?;
    // Legacy follow-up box: one field served both roles, and it held the
    // REPORT's display ref. Move it across — but only a non-empty value, so an
    // empty string cannot become a phantom report reference.
    if ((_followUpReportRef == null || _followUpReportRef!.isEmpty) &&
        !looksGenerated &&
        cached != null &&
        cached.isNotEmpty) {
      _followUpReportRef = cached;
    }
  }

  /// Attempts allowed when landing a unique `reference_code`.
  static const _refAttempts = 4;
  static final Random _refJitter = Random();

  /// Runs [create] with a freshly generated reference, retrying on a unique
  /// violation (SQLSTATE 23505).
  ///
  /// WHY THIS EXISTS. `reference_code` is UNIQUE and [_generateRef] is random,
  /// so a collision is possible however large the namespace. At 32^6 slots per
  /// day it is genuinely rare rather than routine, but "rare" against a hard
  /// constraint still means a citizen occasionally cannot open a chat, and the
  /// recovery is one cheap retry.
  ///
  /// ON THE DELAY — it is NOT load-bearing, and an earlier version of this
  /// comment claimed it was. That was true when the tail came from the
  /// millisecond clock: [_generateRef] was then a pure function of the current
  /// millisecond, an immediate retry regenerated the identical string, and
  /// sleeping past the boundary was the only thing that made the next attempt a
  /// different draw. With a [Random.secure] tail every call is an independent
  /// draw regardless of timing, so that rationale is dead.
  ///
  /// The delay is kept as ordinary retry backoff, not as correctness: it costs
  /// nothing on a path that has already failed, and it still helps for the one
  /// remaining case a retry can address — a transient rejection rather than a
  /// true value collision. If it were removed the loop would still be correct.
  /// Documented rather than deleted so the next reader does not reconstruct the
  /// old, wrong reason for it.
  ///
  /// Retries on any 23505: the only unique constraints on concern_tickets are
  /// the primary key and reference_code, and a fresh attempt regenerates both.
  Future<T> _withUniqueRef<T>(Future<T> Function(String reference) create) async {
    for (var attempt = 1; attempt <= _refAttempts; attempt++) {
      try {
        return await create(_generateRef());
      } on PostgrestException catch (e) {
        if (e.code != '23505' || attempt == _refAttempts) rethrow;
        debugPrint('reference collision (attempt $attempt), regenerating');
        await Future<void>.delayed(
          Duration(milliseconds: 3 + _refJitter.nextInt(40)),
        );
      }
    }
    // Unreachable: the final attempt either returns or rethrows above.
    throw const TicketException('Could not allocate a ticket reference.');
  }

  /// Crockford base32 — the ten digits plus the twenty-two unambiguous letters.
  /// I, L, O and U are excluded: the first three because they are misread as 1,
  /// 1 and 0 off a screen or over a phone, and U because it is the convention's
  /// reserved character. Exactly 32 characters; asserted in
  /// verify_20260722000017.sql rather than trusted by eye.
  static const _refAlphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

  /// Cryptographic, so references are unguessable as well as unique. There is
  /// no secret here, but enumeration of a day's references is free to deny.
  static final Random _refRandom = Random.secure();

  /// A ticket reference: `LGU-YYYYMMDD-XXXXXX`, 19 characters.
  ///
  /// The tail was previously the last five digits of the millisecond epoch —
  /// about 100,000 slots per calendar day. Against a UNIQUE constraint that is
  /// a birthday problem with even odds at ~372 tickets in one day, and, because
  /// collisions accumulate across days, a ~50% chance of at least one collision
  /// within a year at only TWENTY tickets a day. That is a quiet Tuesday for an
  /// LGU, and the peak case — a typhoon or flood driving hundreds of reports in
  /// an afternoon — is exactly when the system must not start failing.
  ///
  /// Six random base32 characters is 32^6 ≈ 1.07e9 slots per day, which moves
  /// even odds out to ~38,700 tickets/day and makes the annual figure
  /// negligible at any volume this deployment will see.
  ///
  /// The date prefix is kept: it is human-meaningful, it is what makes the
  /// namespace day-scoped, and it costs nothing.
  ///
  /// MUST stay in sync with the database allowlist — the CHECK constraint and
  /// the trigger in migration 20260722000017 both pin
  /// `^LGU-[0-9]{8}-[0-9A-HJKMNP-TV-Z]{6}$`. A change here without a migration
  /// makes every ticket insert fail.
  /// Test hooks. The reference format is a CONTRACT WITH THE DATABASE — the
  /// CHECK constraint and trigger in migration 20260722000017 reject anything
  /// this method can't produce — but Dart and SQL hold two independent copies of
  /// that 32-character alphabet and nothing else compares them. These expose the
  /// real generator (not a reimplementation) so a test can cross-check its
  /// output against the live regex. See test/reference_format_test.dart.
  @visibleForTesting
  static String generateReferenceForTest() => _generateRef();
  @visibleForTesting
  static String get referenceAlphabetForTest => _refAlphabet;

  /// Exposes the collision-retry loop with an injectable create function, so a
  /// test can assert WHICH failures it retries. A 4-attempt loop in front of a
  /// rate limiter would turn one blocked request into four, so "retries only on
  /// 23505" is a property worth proving rather than reading.
  @visibleForTesting
  static Future<T> withUniqueRefForTest<T>(
    Future<T> Function(String reference) create,
  ) =>
      I._withUniqueRef(create);
  @visibleForTesting
  static int get refAttemptsForTest => _refAttempts;

  static String _generateRef() {
    final n = DateTime.now();
    final d =
        '${n.year}${n.month.toString().padLeft(2, '0')}${n.day.toString().padLeft(2, '0')}';
    final tail = String.fromCharCodes(
      List.generate(
        6,
        (_) => _refAlphabet.codeUnitAt(_refRandom.nextInt(_refAlphabet.length)),
      ),
    );
    return 'LGU-$d-$tail';
  }

  // ── Cache (Hive) ──────────────────────────────────────────────────────

  static const _followUpIndexBox = 'chat_followup_index';

  /// Records a follow-up box name so logout can find and delete it later,
  /// even across app restarts (the index survives in its own box).
  static Future<void> _registerFollowUpBox(String name) async {
    final idx = await Hive.openBox(_scoped(_followUpIndexBox));
    final List names = (idx.get('names') as List?) ?? [];
    if (!names.contains(name)) {
      names.add(name);
      await idx.put('names', names);
    }
  }

  /// Deletes every per-report follow-up box recorded in the index.
  /// Call on logout so one user's follow-up chats don't linger for the next.
  static Future<void> clearAllFollowUpBoxes() async {
    // Reset the live follow-up instance first (clears its active box + state,
    // and deletes any unused ghost ticket).
    try {
      await followUp._resetAll(reason: _ResetReason.logout);
    } catch (_) {}

    // The index open and clear were the only unguarded Hive calls left in the
    // sign-out path — the per-box delete below was already wrapped, which made
    // it look as though the whole loop was covered. On web these are IndexedDB
    // round-trips and can fail for reasons that have nothing to do with us (a
    // blocked upgrade, a box still held open elsewhere), and a throw here used
    // to propagate all the way out of onUserSignedOut.
    try {
      final idx = await Hive.openBox(_scoped(_followUpIndexBox));
      final List names = (idx.get('names') as List?) ?? const [];
      for (final name in names) {
        try {
          await Hive.deleteBoxFromDisk(name.toString());
        } catch (_) {}
      }
      await idx.clear();
    } catch (_) {}
  }

  String get _boxName => _activeBoxName;

  Future<void> _persist() async {
    final session = _sessionId;
    final b = await Hive.openBox(_boxName);
    if (session != _sessionId) return;

    final snapshot = {
      'messages':
          (_messages.length > 100
                  ? _messages.sublist(_messages.length - 100)
                  : _messages)
              .map((m) => m.toJson())
              .toList(),
      'stage': _stage.index,
      'category': _category?.index,
      'pendingDetails': _pendingDetails,
      'lastTicketReference': _lastTicketReference,
      'lastTicketId': _lastTicketId,
      'isGhostTicket': _isGhostTicket,
      'detailAttempts': _detailAttempts,
      'followUpRef': _followUpReportRef,
      'followUpStatus': _followUpReportStatus,
      'followUpDepartment': _followUpDepartment,
      'followUpReportId': _followUpReportId,
      'followUpReportCategory': _followUpReportCategory,
      'awaitingRating': _awaitingRating,
      'submittedRating': _submittedRating,
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
    _restoreReferences(b);
    _lastTicketId = b.get('lastTicketId') as String?;
    _isGhostTicket = b.get('isGhostTicket', defaultValue: false) as bool;
    _detailAttempts = b.get('detailAttempts', defaultValue: 0) as int;
    _followUpReportStatus = b.get('followUpStatus') as String?;
    _followUpDepartment = b.get('followUpDepartment') as String?;
    _followUpReportId = b.get('followUpReportId') as String?;
    _followUpReportCategory = b.get('followUpReportCategory') as String?;
    _awaitingRating = b.get('awaitingRating', defaultValue: false) as bool;
    _submittedRating = b.get('submittedRating', defaultValue: 0) as int;
  }
}

enum _ResetReason { logout, userRequested }
