import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/Home/Chat-agent/chat_models.dart';
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
    await I.clearOnLogout();
    await clearAllFollowUpBoxes();
    _currentUserId = null;
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
  String? _lastTicketReference;
  String? _followUpReportStatus;
  String? _followUpDepartment;
  String? _followUpReportId;
  String? _followUpReportCategory;
  String? _lastTicketId;
  bool _isAgentTyping = false;
  int _unreadCount = 0;
  bool _isViewing = false;
  bool _disposed = false;
  int _sessionId = 0;
  RealtimeChannel? _agentChannel;
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
  bool get showBackToMenu =>
      _stage == ConversationStage.askingQuestion && !_isAgentTyping;
  bool get showContactConfirm =>
      _stage == ConversationStage.confirmingContact && !_isAgentTyping;
  bool get isTerminal =>
      _stage == ConversationStage.ticketCreated ||
      _stage == ConversationStage.timedOut ||
      _stage == ConversationStage.ended;

  String? get lastTicketReference => _lastTicketReference;
  String? get lastTicketId => _lastTicketId;
  String? get followUpReportRef => _lastTicketReference;

  // ── Lifecycle ─────────────────────────────────────────────────────────

  @override
  void dispose() {
    _disposed = true;
    _sessionId++;
    _cancelIdleTimer();
    _agentChannel?.unsubscribe();
    _agentChannel = null;
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
    _agentChannel?.unsubscribe();
    _agentChannel = null;
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
      _messages.clear();
      _activeBoxName = _scoped(_baseBox);
      _stage = ConversationStage.greeting;
      _lastTicketReference = null;
      _lastTicketId = null;
      _followUpReportStatus = null;
      _followUpDepartment = null;
      _followUpReportId = null;
      _followUpReportCategory = null;
      _isGhostTicket = false;
      _category = null;
      _pendingDetails = null;
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
    _agentChannel?.unsubscribe();
    _agentChannel = null;

    _messages.clear();
    _stage = ConversationStage.followUp;
    _category = null;
    _pendingDetails = null;
    _lastTicketReference = reportRef;
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
      'reportRef': _lastTicketReference,
      'reportStatus': _followUpReportStatus,
    };

    String greeting;
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'chat-agent',
        body: payload,
      );
      if (session != _sessionId) return;
      final data = res.data;
      greeting = (data is Map && data['reply'] is String)
          ? (data['reply'] as String).trim()
          : _followUpFallbackGreeting();
    } catch (_) {
      if (session != _sessionId) return;
      greeting = _followUpFallbackGreeting();
    }

    if (session != _sessionId) return;
    await _agentSay(greeting, session, skipTyping: true);
    if (session != _sessionId) return;
    _maybeStartIdleTimer();
    notifyListeners();
    _persist();
  }

  String _followUpFallbackGreeting() =>
      'I can see your report ${_lastTicketReference ?? ''} about '
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
      _agentChannel?.unsubscribe();
      _agentChannel = null;
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
      _lastTicketReference = b.get('lastTicketReference') as String?;
      _lastTicketId = b.get('lastTicketId') as String?;
      _isGhostTicket = b.get('isGhostTicket', defaultValue: false) as bool;

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
      msg.status = MessageStatus.delivered;
      notifyListeners();
      _persist();
    });

    await _routeUserMessage(msg, session);
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
          );
          if (session != _sessionId) return;
          _stage = ConversationStage.ended;
          _maybeStartIdleTimer();
        } else {
          await _agentSay(raw, session, skipTyping: true);
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
          );
          if (session != _sessionId) return;
          _stage = ConversationStage.ended;
        } else {
          await _agentSay(cleaned, session, skipTyping: true);
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
          );
          if (session != _sessionId) return;
          _stage = ConversationStage.ended;
        } else {
          await _agentSay(cleaned, session, skipTyping: true);
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
        final reference = _generateRef();
        final ticket = await TicketRepository.I.createGhostTicket(
          category: _category!,
          referenceCode: reference,
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

      final reference = _generateRef();
      final ticket = await TicketRepository.I.createTicket(
        category: _category!,
        details: _pendingDetails!,
        referenceCode: reference,
        contactName: _cName,
        contactNumber: _cNumber,
        contactAddress: _cAddress,
        contactEmail: _cEmail,
        contactNote: _cNote,
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

  Future<String> _callAgent(int session) async {
    final priorMessages = _messages.take(_messages.length - 1).toList();
    final history =
        (_stage == ConversationStage.askingQuestion ||
            _stage == ConversationStage.followUp)
        ? priorMessages
              .skip(priorMessages.length > 6 ? priorMessages.length - 6 : 0)
              .map((m) => {'text': m.text, 'isUser': m.isUser})
              .toList()
        : priorMessages
              .map((m) => {'text': m.text, 'isUser': m.isUser})
              .toList();
    final latest = _messages.last;

    List<Map<String, dynamic>> events = [];
    if (_stage == ConversationStage.askingQuestion) {
      events = await TicketRepository.I.getLatestEvents();
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
        'reportRef': _lastTicketReference,
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
        return (data['reply'] as String).trim();
      }

      debugPrint('ChatService: unexpected edge function response: $data');
      return _fallbackReply;
    } catch (e) {
      debugPrint('ChatService: edge function error: $e');
      if (session != _sessionId) return '';
      return _fallbackReply;
    }
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
        final ticket = await TicketRepository.I.createFollowUpTicket(
          reportId: _followUpReportId!,
          category: _followUpReportCategory!,
          department: _followUpDepartment!,
          referenceCode: _lastTicketReference ?? _generateRef(),
        );
        if (session != _sessionId) return;
        _lastTicketId = ticket['id']?.toString();
        _isGhostTicket = true;
      } catch (e) {
        debugPrint('follow-up ticket (retry) failed: $e');
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
    }
  }

  void _startAgentSubscription() {
    final ticketId = _lastTicketId;
    if (ticketId == null) return;
    _agentChannel?.unsubscribe();
    final session = _sessionId;

    _agentChannel = TicketRepository.I.subscribeToTicketMessages(
      ticketId: ticketId,
      onInsert: (row) {
        if (session != _sessionId) return;
        if (row['sender_type'] != 'staff') return;
        final text = (row['message'] as String?)?.trim() ?? '';
        if (text.isEmpty) return;
        _messages.add(ChatMsg(text: text, isUser: false, time: DateTime.now()));
        if (!_isViewing) _unreadCount++;
        notifyListeners();
        _persist();
      },
    );
  }

  static const _fallbackReply =
      'Sorry po, I\'m having trouble connecting right now. '
      'Please try again in a moment.';

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
      await TicketRepository.I.deleteGhostTicketIfUnused(_lastTicketId!);
    }
    _sessionId++;
    _cancelIdleTimer();
    _agentChannel?.unsubscribe();
    _agentChannel = null;
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

    final b = await Hive.openBox(_activeBoxName);
    await b.clear();
    await b.flush();
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

    String greeting;
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'chat-agent',
        body: greetingPayload,
      );
      if (session != _sessionId) return;
      final data = res.data;
      greeting = (data is Map && data['reply'] is String)
          ? (data['reply'] as String).trim()
          : "Good day po! I'm Kuya Gov, your LGU Aparri Support Agent. 👋\n\n"
                "How can I help you today? Please choose an option below.";
    } catch (_) {
      if (session != _sessionId) return;
      greeting =
          "Good day po! I'm Kuya Gov, your LGU Aparri Support Agent. 👋\n\n"
          "How can I help you today? Please choose an option below.";
    }

    if (session != _sessionId) return;
    await _agentSay(greeting, session, skipTyping: true);

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
    _messages.add(ChatMsg(text: text, isUser: false, time: DateTime.now()));
    if (_messages.length > 200) {
      _messages.removeRange(0, _messages.length - 200);
    }
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

    final idx = await Hive.openBox(_scoped(_followUpIndexBox));
    final List names = (idx.get('names') as List?) ?? [];
    for (final name in names) {
      try {
        await Hive.deleteBoxFromDisk(name.toString());
      } catch (_) {}
    }
    await idx.clear();
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
      'followUpRef': _lastTicketReference,
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
    final stageIdx = b.get('stage', defaultValue: 0) as int;
    _stage = ConversationStage
        .values[stageIdx.clamp(0, ConversationStage.values.length - 1)];
    final ci = b.get('category') as int?;
    _category = ci != null ? ConcernCategory.values[ci] : null;
    _pendingDetails = b.get('pendingDetails') as String?;
    _lastTicketReference = b.get('lastTicketReference') as String?;
    _lastTicketId = b.get('lastTicketId') as String?;
    _isGhostTicket = b.get('isGhostTicket', defaultValue: false) as bool;
    _detailAttempts = b.get('detailAttempts', defaultValue: 0) as int;
    _followUpReportStatus = b.get('followUpStatus') as String?;
    _followUpDepartment = b.get('followUpDepartment') as String?;
    _followUpReportId = b.get('followUpReportId') as String?;
    _followUpReportCategory = b.get('followUpReportCategory') as String?;
  }
}

enum _ResetReason { logout, userRequested }
