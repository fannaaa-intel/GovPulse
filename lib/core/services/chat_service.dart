import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/Home/Chat-agent/chat_models.dart';
import 'assistant_knowledge.dart';
import 'faq_catalog.dart';
import 'local_assistant.dart';

/// Kuya Gov, the citizen-facing assistant.
///
/// ── NO LIVE STAFF CHAT (panel revision, 2026-10-12) ─────────────────────────
/// This used to hand a citizen off to an on-duty staff member over
/// `concern_tickets` / `ticket_messages`. The panel ruled that a direct line
/// bypasses GovPulse's own channels (a concern typed into a chat is not a
/// report anyone tracks) and invites idle or abusive conversation with staff.
/// The assistant now only answers questions; anything that needs action is
/// pointed at Report / Suggestion / Feedback. An `[ACTION:AGENT]` reply from
/// the model is answered with [_explainNoLiveStaff], never a handoff.
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

  /// One-time cleanup of the pre-fix UNSCOPED boxes.
  ///
  /// Until the `_scoped` fix in [_resetAll], starting a new conversation while
  /// signed in rebound this service to the bare `chat_cache` name and every
  /// `_persist()` afterwards wrote there — a box shared by every account on the
  /// device, and the one [init] reads when nobody is signed in. The fix stops
  /// new writes, but devices that ran the old build still carry whatever landed
  /// there, so it would keep surfacing to the next user (and to signed-out
  /// visitors) until something removes it.
  ///
  /// Safe to run unconditionally on every launch. Post-fix these names are only
  /// ever used while `_currentUserId` is null — the signed-out case, which
  /// starts from a greeting and has nothing worth keeping — so deleting them
  /// costs a signed-out visitor nothing and reliably drops the leaked data.
  ///
  /// Runs BEFORE any bind, so it cannot delete a box the live session is using.
  /// Failures are swallowed: on web these are IndexedDB round-trips, and a
  /// cleanup that cannot run is not a reason to fail app start.
  static Future<void> purgeLegacyUnscopedBoxes() async {
    for (final name in const [
      'chat_cache',
      'chat_cache_followup',
      _followUpIndexBox,
    ]) {
      try {
        await Hive.deleteBoxFromDisk(name);
      } catch (_) {}
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

  /// The REPORT's human-facing display reference (`RPT-B34A6055`) for the
  /// follow-up conversation. Display and prompt-context only: it is shown to
  /// the citizen who filed the report, and passed to the chat-agent function so
  /// the assistant can say which report it is looking at. It is also the seed
  /// for the Hive box name: see [_boxNameForReport].
  String? _followUpReportRef;

  String? _followUpReportStatus;
  String? _followUpDepartment;
  String? _followUpReportId;
  String? _followUpReportCategory;
  bool _isAgentTyping = false;
  /// Set by [_callAgent]: true when the last reply came from the on-device
  /// fallback brain (AI unavailable) rather than the Groq function. Read by the
  /// consumer branches so the message is flagged + shown with an offline chip.
  bool _lastReplyOffline = false;
  int _unreadCount = 0;
  bool _isViewing = false;
  bool _disposed = false;
  int _sessionId = 0;
  DateTime? _lastSendAt;
  static const _minSendGap = Duration(milliseconds: 1500);

  Timer? _idleTimer;
  static const _idleDuration = Duration(minutes: 15);

  // ── Public getters ────────────────────────────────────────────────────
  List<ChatMsg> get messages => List.unmodifiable(_messages);
  ConversationStage get stage => _stage;
  bool get isAgentTyping => _isAgentTyping;
  int get unreadCount => _unreadCount;
  bool get hasUnread => _unreadCount > 0;

  /// The "Common questions" chips under the greeting (main chat only).
  bool get showFaqChips =>
      _stage == ConversationStage.awaitingIntent &&
      !_isAgentTyping &&
      identical(this, I);
  bool get showBackToMenu =>
      _stage == ConversationStage.askingQuestion && !_isAgentTyping;
  bool get isTerminal =>
      _stage == ConversationStage.timedOut ||
      _stage == ConversationStage.ended;

  String? get followUpReportRef => _followUpReportRef;

  // ── Lifecycle ─────────────────────────────────────────────────────────

  @override
  void dispose() {
    _disposed = true;
    _sessionId++;
    _cancelIdleTimer();
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
  }

  Future<void> _rebindToCurrentUser() async {
    _sessionId++;
    _cancelIdleTimer();
    _messages.clear();
    _stage = ConversationStage.greeting;
    _followUpReportStatus = null;
    _followUpDepartment = null;
    _followUpReportId = null;
    _followUpReportCategory = null;
    _followUpReportRef = null;
    _isAgentTyping = false;
    _unreadCount = 0;
    _lastSendAt = null;

    _activeBoxName = _scoped(_baseBox);
    await _loadCache();
    if (_messages.isNotEmpty) _maybeStartIdleTimer();
    notifyListeners();
  }

  void onChatOpened({bool isFollowUp = false}) {
    _isViewing = true;
    _unreadCount = 0;
    _markUserMessagesSeen();

    if (!isFollowUp && _stage == ConversationStage.followUp) {
      _sessionId++;
      _cancelIdleTimer();
      _messages.clear();
      _activeBoxName = _scoped(_baseBox);
      _stage = ConversationStage.greeting;
      _followUpReportStatus = null;
      _followUpDepartment = null;
      _followUpReportId = null;
      _followUpReportCategory = null;
      _followUpReportRef = null;
    }

    notifyListeners();

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

    _messages.clear();
    _stage = ConversationStage.followUp;
    _followUpReportRef = reportRef;
    _followUpReportStatus = reportStatus;
    _followUpDepartment = reportDepartment;
    _followUpReportId = reportId;
    _followUpReportCategory = reportCategory;
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

      _stage = _readStage(b);
      _restoreReferences(b);
      // A resumed follow-up thread must show the report it is about, even if
      // the cached box predates the split and carried no 'followUpRef'.
      _followUpReportRef ??= reportRef;

      _messages
        ..clear()
        ..addAll(tempMessages);

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

  /// Answers a FAQ chip with its ready-made answer — no AI call, so it is
  /// instant, costs no quota, and says the same checked thing every time.
  ///
  /// Only the facts the answer names are fetched (cached, see
  /// [AssistantKnowledge.getLguFacts]); an answer with none never waits.
  Future<void> askFaq(Faq faq) async {
    if (_isAgentTyping || isTerminal) return;
    if (_stage != ConversationStage.awaitingIntent &&
        _stage != ConversationStage.askingQuestion) {
      return;
    }
    final session = _sessionId;
    _cancelIdleTimer();
    _messages.add(ChatMsg(
      text: faq.question,
      isUser: true,
      time: DateTime.now(),
      status: MessageStatus.seen,
    ));
    _stage = ConversationStage.askingQuestion;
    notifyListeners();
    _persist();

    var facts = const <String, String>{};
    if (faq.factKeys.isNotEmpty) {
      _isAgentTyping = true;
      notifyListeners();
      final rows = await AssistantKnowledge.I.getLguFacts();
      if (session != _sessionId) return;
      facts = {
        for (final r in rows)
          if (faq.factKeys.contains(r['key']))
            r['key'].toString(): (r['value'] ?? '').toString(),
      };
    }
    await _agentSay(faq.answer(facts), session, skipTyping: true);
    if (session != _sessionId) return;
    _maybeStartIdleTimer();
  }

  Future<void> backToMenu() async {
    final session = _sessionId;
    _stage = ConversationStage.awaitingIntent;
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

  /// What the citizen hears when they ask for a person (the model's
  /// `[ACTION:AGENT]`, or the offline brain's). There is no live staff chat:
  /// the answer points at the channels that actually reach an office and get
  /// tracked, and at the hotlines for anything urgent.
  ///
  /// The model's own text for that turn is DROPPED, not shown: a chat-agent
  /// deployment older than the panel revision still answers "connecting you to
  /// staff", and an installed app must not repeat a promise nobody keeps.
  Future<void> _explainNoLiveStaff(int session, String userText) async {
    await _agentSay(
      LocalAssistant.noLiveStaff(userText),
      session,
      skipTyping: true,
      offline: _lastReplyOffline,
    );
    if (session != _sessionId) return;
    _maybeStartIdleTimer();
  }

  // ── Conversation routing ──────────────────────────────────────────────

  Future<void> _routeUserMessage(ChatMsg msg, int session) async {
    switch (_stage) {
      case ConversationStage.greeting:
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
          _stage = ConversationStage.askingQuestion;
          await _explainNoLiveStaff(session, msg.text);
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
          await _explainNoLiveStaff(session, msg.text);
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
          _stage = ConversationStage.askingQuestion;
          await _explainNoLiveStaff(session, msg.text);
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

      // Retired live-chat stages. [_readStage] never restores one, so these
      // are unreachable; listed because the switch must be exhaustive.
      case ConversationStage.awaitingCategory:
      case ConversationStage.awaitingDetails:
      case ConversationStage.submitting:
      case ConversationStage.ticketCreated:
      case ConversationStage.connectedToAgent:
      case ConversationStage.confirmingContact:
      case ConversationStage.correctingContact:
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
          _stage = ConversationStage.askingQuestion;
          await _explainNoLiveStaff(session, msg.text);
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
    // Show the typing bubble for the WHOLE AI round trip. Every caller hands
    // the reply to _agentSay(skipTyping: true), so without this the citizen
    // stared at their own message for the seconds Groq took, with no sign
    // anything was happening. _agentSay clears the flag when the reply lands;
    // a stale session is reset by the new one. Holding the flag also blocks a
    // second send while this call is in flight (sendUserText gates on it).
    _isAgentTyping = true;
    _markUserMessagesSeen();
    notifyListeners();

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
      events = (await AssistantKnowledge.I.getLatestEvents())
          .map(_trimEvent)
          .toList();
    }

    // Verified Aparri facts (mayor, hotlines, office locations). Sent on the
    // two stages that actually answer questions — askingQuestion, and
    // awaitingIntent, where a citizen who typed "sino ang mayor?" instead of
    // tapping a menu button gets answered in place rather than routed.
    //
    // Deliberately NOT sent on greeting: that turn has no citizen message to
    // ground and already runs on a trimmed prompt for exactly this reason (see
    // GREETING_SYSTEM_PROMPT in the edge function). Nor on the report/agent
    // redirect stages, whose replies are two fixed sentences.
    List<Map<String, dynamic>> lguFacts = const [];
    if (_stage == ConversationStage.askingQuestion ||
        _stage == ConversationStage.awaitingIntent) {
      lguFacts = await AssistantKnowledge.I.getLguFacts();
    }
    if (session != _sessionId) return '';

    final payload = {
      'stage': _stage.name,
      'category': _stage == ConversationStage.followUp
          ? _followUpReportCategory
          : null,
      'department': _stage == ConversationStage.followUp
          ? _followUpDepartment
          : null,
      'history': history,
      'userMessage': latest.text,
      'events': events,
      'lguFacts': lguFacts,
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
      // AI unavailable → fall back to the on-device brain so the assistant
      // stays useful (hybrid).
      //
      // TWO DIFFERENT CAUSES, TWO DIFFERENT MESSAGES. chat-agent deliberately
      // returns a NON-2xx on a Groq 429 so functions.invoke throws and we land
      // here — that is by design (see the comment at chat-agent/index.ts:968).
      // But it is NOT the same situation as a dead connection:
      //
      //   • 429  → the AI is BUSY. The citizen's internet is fine. Telling them
      //            "offline mode" sends them off to check their wifi for a
      //            problem that isn't theirs, and the wait is usually seconds.
      //   • else → genuinely unreachable (no signal, function down).
      //
      // The server also hands us Retry-After / retryAfterSeconds, which the
      // client used to discard. We surface it so the message can say how long.
      final busy = _isRateLimited(e);
      debugPrint('ChatService: edge function error (busy=$busy): $e');
      if (session != _sessionId) return '';
      return _offlineReply(latest.text, busy: busy, retryAfter: _retryAfterOf(e));
    }
  }

  /// True when [e] is chat-agent's Groq-throttle 429 rather than a transport
  /// failure. FunctionException carries the status; the string check is a
  /// backstop for wrapped/rethrown errors so a shape change degrades to the
  /// generic offline copy rather than mislabelling a real outage as "busy".
  static bool _isRateLimited(Object e) {
    if (e is FunctionException && e.status == 429) return true;
    return e.toString().contains('rate_limited');
  }

  /// Seconds chat-agent asked us to wait, when it said. Null when absent or
  /// unparseable — the caller then omits the duration rather than inventing one.
  static int? _retryAfterOf(Object e) {
    if (e is! FunctionException) return null;
    final details = e.details;
    if (details is Map && details['retryAfterSeconds'] != null) {
      final v = details['retryAfterSeconds'];
      if (v is int) return v;
      if (v is num) return v.ceil();
      return int.tryParse(v.toString());
    }
    return null;
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
  ///
  /// [busy] selects the wording for a Groq throttle ("lots of people are asking
  /// right now, try again shortly") over the connection wording. [retryAfter] is
  /// the server's own hint in seconds, shown when it sent one. The answer itself
  /// is identical either way — only the apology differs.
  String _offlineReply(String userText, {bool busy = false, int? retryAfter}) {
    _lastReplyOffline = true;
    return LocalAssistant.reply(
      userText,
      followUp: _stage == ConversationStage.followUp,
      reportRef: _followUpReportRef,
      reportStatus: _followUpReportStatus,
      reportCategory: _followUpReportCategory,
      busy: busy,
      retryAfterSeconds: retryAfter,
    );
  }

  // ── Idle timer ────────────────────────────────────────────────────────
  bool get _stageAwaitsUser =>
      _stage == ConversationStage.awaitingIntent ||
      _stage == ConversationStage.askingQuestion ||
      _stage == ConversationStage.followUp;

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
    _sessionId++;
    _cancelIdleTimer();
    _lastSendAt = null;
    _messages.clear();
    _stage = ConversationStage.greeting;
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
    // SCOPED, not the bare [_baseBox] this used to assign.
    //
    // `userRequested` is the path that was broken. The user is still signed IN
    // when they start a new conversation, so dropping the `__<uid>` suffix
    // pointed this instance at the SHARED, unscoped box for the rest of the
    // session: every `_persist()` afterwards wrote that citizen's messages to
    // `chat_cache`, where the next account on the same device read them back.
    // Nothing re-scoped it in between — [_rebindToCurrentUser] only rebinds
    // when the uid CHANGES, so even the same user signing back in kept it.
    //
    // `logout` is unaffected either way. `_currentUserId` is still set here
    // (onUserSignedOut nulls it in its `finally`, after this returns), so this
    // now leaves the field on the scoped name rather than the base one — but
    // the disk clear above has already emptied that box, and the next
    // [onUserAuthenticated] assigns the field before any read of it.
    _activeBoxName = _scoped(_baseBox);

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
        "Tap a common question below, or type your own.";
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

  /// Shape of the old concern-ticket reference (`LGU-YYYYMMDD-XXXXXX`). Only
  /// read now, to tell a legacy cached ticket reference apart from a report
  /// reference in [_restoreReferences].
  static final RegExp _ticketRefPattern = RegExp(r'^LGU-\d{8}-');

  /// True for the report follow-up surface, false for the main chat agent.
  ///
  /// One class backs two surfaces: [ChatService.I] (main, base box
  /// `chat_cache`) and the per-report instances from [forReport] (base box
  /// `chat_cache_followup_<ref>`). Report-scoped state belongs only to the
  /// latter, and [_baseBox] is fixed at construction so this cannot drift.
  bool get _isFollowUpSurface => _baseBox.startsWith('chat_cache_followup');

  /// Restores the follow-up report reference from a Hive box, healing boxes
  /// written before the report-ref / ticket-ref split.
  ///
  /// Legacy boxes stored the REPORT's display reference ('RPT-B34A6055') under
  /// `lastTicketReference`, because one field served both roles. Anything there
  /// not shaped like a ticket reference is what it actually was — a report
  /// reference — and is moved across.
  ///
  /// No box is orphaned: the box NAME is still derived from the report ref
  /// (see [_boxNameForReport]), which this change does not touch, so every
  /// cached thread still resolves to the same box.
  void _restoreReferences(Box b) {
    final cached = b.get('lastTicketReference') as String?;
    final looksGenerated =
        cached != null && _ticketRefPattern.hasMatch(cached);

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

  /// The Hive box this instance currently reads and writes.
  ///
  /// Exposed so the scoping regression can be asserted directly: the bug was
  /// this field silently losing its `__<uid>` suffix, which is invisible from
  /// the outside until another account reads the messages back.
  @visibleForTesting
  String get activeBoxNameForTest => _activeBoxName;

  /// Binds/unbinds the static user scope without touching Hive or the network,
  /// so a test can exercise the naming rules on their own.
  @visibleForTesting
  static void setUserScopeForTest(String? uid) => _currentUserId = uid;

  @visibleForTesting
  static String scopedForTest(String base) => _scoped(base);

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
    // Reset the live follow-up instance first (clears its active box + state).
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
      'followUpRef': _followUpReportRef,
      'followUpStatus': _followUpReportStatus,
      'followUpDepartment': _followUpDepartment,
      'followUpReportId': _followUpReportId,
      'followUpReportCategory': _followUpReportCategory,
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
    _stage = _readStage(b);
    _restoreReferences(b);
    _followUpReportStatus = b.get('followUpStatus') as String?;
    _followUpDepartment = b.get('followUpDepartment') as String?;
    _followUpReportId = b.get('followUpReportId') as String?;
    _followUpReportCategory = b.get('followUpReportCategory') as String?;
  }

  /// The cached stage, with the retired live-chat stages mapped out.
  ///
  /// Stages are persisted by INDEX, which is why [ConversationStage] keeps its
  /// old values. A phone that last ran a build with live staff chat can hold a
  /// conversation cached mid-handoff (connected to staff, picking a category,
  /// a logged ticket). None of those can continue, so the main chat restores
  /// as ended — the citizen sees "Start new conversation" — and a report
  /// follow-up simply carries on as a follow-up.
  ConversationStage _readStage(Box b) {
    final idx = b.get('stage', defaultValue: 0) as int;
    final stage = ConversationStage
        .values[idx.clamp(0, ConversationStage.values.length - 1)];
    switch (stage) {
      case ConversationStage.awaitingCategory:
      case ConversationStage.awaitingDetails:
      case ConversationStage.submitting:
      case ConversationStage.ticketCreated:
      case ConversationStage.connectedToAgent:
      case ConversationStage.confirmingContact:
      case ConversationStage.correctingContact:
        return _isFollowUpSurface
            ? ConversationStage.followUp
            : ConversationStage.ended;
      default:
        return stage;
    }
  }
}

enum _ResetReason { logout, userRequested }
