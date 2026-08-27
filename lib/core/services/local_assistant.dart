// lib/core/services/local_assistant.dart
//
// On-device fallback brain for "Kuya Gov" (the citizen chat assistant).
//
// When the Groq `chat-agent` Edge Function is unavailable — no connection, or
// its usage/rate limit is exhausted — ChatService routes the user's message
// here instead of showing a dead-end "try again later" message. This keeps the
// assistant genuinely useful offline: it detects intent (report / live agent /
// goodbye) and answers common Philippine civic questions from a compact local
// knowledge base mirrored from the Edge Function's KB.
//
// Contract: it returns the SAME format the Edge Function uses — an optional
// [ACTION:REPORT|AGENT|END] tag on the first line — so ChatService's existing
// routing works with zero changes. Everything here is rule-based (keyword
// matching), so it's instant and needs no network. Replies are flagged
// `offline` by the caller and shown with an "answered on-device" chip.

class LocalAssistant {
  /// Produces a reply for [userMessage]. [followUp] tailors the generic
  /// fallback to the report-follow-up screen (using [reportRef]/[reportStatus]/
  /// [reportCategory] when known).
  /// [busy] means the AI was reachable but THROTTLED (chat-agent surfaced a Groq
  /// 429), not that the device is offline — the citizen's connection is fine and
  /// the wait is usually seconds. [retryAfterSeconds] is the server's own hint,
  /// shown when it sent one. They only affect the no-match apology below; every
  /// answer this class actually knows is returned unchanged either way.
  static String reply(
    String userMessage, {
    bool followUp = false,
    String? reportRef,
    String? reportStatus,
    String? reportCategory,
    bool busy = false,
    int? retryAfterSeconds,
  }) {
    final t = _norm(userMessage);
    // Mirror the citizen's language (Ybanag → Ilocano, the AI's safe rule).
    final lang = _detectLang(t);

    // 1. Intent detection — mirrors the AI's ACTION tags so routing is identical.
    //    END and AGENT apply in both the main and follow-up chats.
    if (_isEnd(t)) {
      return '[ACTION:END]\n${_pick(lang, _mEnd)}';
    }
    if (_wantsAgent(t)) {
      return '[ACTION:AGENT]\n${_pick(lang, _mAgent)}';
    }

    if (followUp) {
      // ── FOLLOW-UP CONTEXT: answers center on the report being followed ──
      // Questions about this report's status/progress/timeline are answered
      // from the report's own context, not the general KB.
      final specific =
          _followUpSpecific(t, lang, reportRef, reportStatus, reportCategory);
      if (specific != null) return specific;

      // A general civic question is still answerable while following up.
      final answer = _knowledge(t);
      if (answer != null) return answer;

      // Otherwise, a report-scoped fallback (never the main-menu one).
      return _followUpGeneric(lang, reportRef, reportStatus, reportCategory);
    }

    // ── MAIN CHAT CONTEXT: general LGU assistant ──
    if (_wantsReport(t)) {
      return '[ACTION:REPORT]\n${_pick(lang, _mReport)}';
    }

    final answer = _knowledge(t);
    if (answer != null) return answer;

    // Nothing matched — an honest, still-helpful main-chat fallback. When the
    // cause was throttling rather than a dead connection, say so: "offline mode"
    // sends the citizen to check a connection that was never the problem.
    if (busy) {
      return _pick(lang, _mBusyHelp) + _retrySuffix(lang, retryAfterSeconds);
    }
    return _pick(lang, _mGenericHelp);
  }

  /// " Subukan ulit sa ~7 segundo." — appended only when chat-agent actually
  /// sent a Retry-After. Rounded up and capped in words, never a countdown: the
  /// number is a hint from the upstream provider, not a guarantee.
  static String _retrySuffix(_Lang lang, int? seconds) {
    if (seconds == null || seconds <= 0) return '';
    final s = seconds > 60 ? 60 : seconds;
    // Ybanag → Ilocano, the same rule _pick applies (never fabricate Ybanag).
    return switch (lang) {
      _Lang.tagalog => '\n\nSubukan po ulit sa mga $s segundo. ⏱️',
      _Lang.ilocano ||
      _Lang.ybanag => '\n\nPadasenyo manen kalpasan ti agarup $s a segundo. ⏱️',
      _Lang.english => '\n\nPlease try again in about $s seconds. ⏱️',
    };
  }

  // ── Language detection + localisation ────────────────────────────────────────
  /// Detects the citizen's language from high-signal markers. Ybanag maps to
  /// Ilocano downstream (the AI's safe rule — never fabricate shaky Ybanag).
  static _Lang _detectLang(String t) {
    const ybanag = [
      'kunnasi', 'anni ', 'piga', 'egga', 'mapia', 'dukko', 'kagitta',
      'ajjan', 'nakuan', 'yaw ', 'kunna',
    ];
    const ilocano = [
      'ania', 'aniya', 'kasano', 'kasanno', 'sadino', 'mano ', 'naimbag',
      'agyaman', 'kayat', 'dagiti', 'apay', 'kaano', ' ti ', 'adda ', 'awan',
      'saan', 'wen ', 'nga ', 'kunam', 'kasta',
    ];
    const english = [
      'how ', 'what ', 'where ', 'when ', 'can i', 'could ', 'please',
      'hello', 'thanks', 'i want', 'i need', 'the ', 'is there',
    ];
    if (_hasAny(t, ybanag)) return _Lang.ybanag;
    if (_hasAny(t, ilocano)) return _Lang.ilocano;
    if (_hasAny(t, english)) return _Lang.english;
    return _Lang.tagalog;
  }

  /// Picks the message variant for [lang]. Ybanag reuses the Ilocano variant.
  static String _pick(_Lang lang, Map<_Lang, String> m) {
    if (lang == _Lang.ybanag) return m[_Lang.ilocano] ?? m[_Lang.tagalog]!;
    return m[lang] ?? m[_Lang.tagalog]!;
  }

  // Short system replies, per language. Ybanag intentionally omitted → Ilocano.
  static const _mEnd = {
    _Lang.tagalog:
        'Salamat po! Kung may iba pa kayong katanungan, nandito lang po ako. '
        'Ingat kayo! 😊',
    _Lang.ilocano:
        'Agyamanak po! No adda pay saludsodyo, adtoyak laeng. Agannad kayo! 😊',
    _Lang.english:
        'Thank you po! If you have more questions, I\'m just here. Take care! 😊',
  };
  static const _mAgent = {
    _Lang.tagalog:
        'Sige po, susubukan kong ikonekta kayo sa isang staff ng LGU Aparri. 🧑‍💼',
    _Lang.ilocano:
        'Sige po, padasek nga iyasideg kayo iti maysa a staff ti LGU Aparri. 🧑‍💼',
    _Lang.english:
        'Alright po, I\'ll try to connect you to an LGU Aparri staff member. 🧑‍💼',
  };
  static const _mReport = {
    _Lang.tagalog:
        'Para mag-report po ng concern, gamitin ang "Report Issue" sa Quick '
        'Actions ng Home screen — doon po ito direktang naipapadala sa tamang '
        'opisina. 📋',
    _Lang.ilocano:
        'Tapno agi-report iti concern, usaren po ti "Report Issue" idiay Quick '
        'Actions ti Home screen — sadiay ket direkta a maipatulod iti umno nga '
        'opisina. 📋',
    _Lang.english:
        'To report a concern po, use "Report Issue" in Quick Actions on the '
        'Home screen — it goes straight to the right office. 📋',
  };
  /// Shown when the AI was reachable but THROTTLED (Groq 429), not when the
  /// device is offline. Deliberately does NOT say "offline" or mention the
  /// connection: the citizen's internet is working, and pointing them at it
  /// sends them to debug a problem that is ours, not theirs. It also does not
  /// blame citizen traffic ("marami pong gumagamit") — the quota is our own
  /// key's, which is the mistake chat-agent's v4 branch already documents.
  /// Same service list as [_mGenericHelp] so the fallback stays equally useful.
  static const _mBusyHelp = {
    _Lang.tagalog:
        'Sandali lang po — abala ang AI assistant ngayon, kaya limitado muna '
        'ang masasagot ko. ⏳ Pero matutulungan pa rin po kita sa mga karaniwang '
        'serbisyo: barangay clearance, cedula, business permit, PSA documents, '
        'National ID, passport, voter registration, senior/PWD ID.\n\n'
        'I-type po ang paksa, o piliin ang "Talk to a person" para sa live na staff.',
    _Lang.ilocano:
        'Saan nga agbayag po — okupado ti AI assistant ita, isu a limitado pay '
        'ti masungbatak. ⏳ Ngem matulongan pa rin kayo iti gagangay a serbisio: '
        'barangay clearance, cedula, business permit, PSA documents, National ID, '
        'passport, voter registration, senior/PWD ID.\n\n'
        'I-type po ti paksa, wenno pilien ti "Talk to a person" para iti live nga staff.',
    _Lang.english:
        'One moment po — the AI assistant is busy right now, so what I can '
        'answer is limited. ⏳ But I can still help with common services: '
        'barangay clearance, cedula, business permit, PSA documents, National '
        'ID, passport, voter registration, senior/PWD ID.\n\n'
        'Type the topic, or choose "Talk to a person" for live staff.',
  };

  static const _mGenericHelp = {
    _Lang.tagalog:
        'Pasensya na po — offline mode muna ako ngayon, kaya limitado ang '
        'masasagot ko. 📶 Pero matutulungan pa rin po kita sa mga karaniwang '
        'serbisyo: barangay clearance, cedula, business permit, PSA documents, '
        'National ID, passport, voter registration, senior/PWD ID.\n\n'
        'I-type po ang paksa, o piliin ang "Talk to a person" para sa live na '
        'staff kapag available na ulit.',
    _Lang.ilocano:
        'Pasensia po — offline mode pay laeng ita, isu a limitado ti masungbatak. '
        '📶 Ngem matulongan pa rin kayo iti gagangay a serbisio: barangay '
        'clearance, cedula, business permit, PSA documents, National ID, '
        'passport, voter registration, senior/PWD ID.\n\n'
        'I-type po ti paksa, wenno pilien ti "Talk to a person" para iti live '
        'nga staff no adda manen ti koneksion.',
    _Lang.english:
        'Sorry po — I\'m in offline mode right now, so what I can answer is '
        'limited. 📶 But I can still help with common services: barangay '
        'clearance, cedula, business permit, PSA documents, National ID, '
        'passport, voter registration, senior/PWD ID.\n\n'
        'Type the topic, or choose "Talk to a person" for live staff once the '
        'connection is back.',
  };

  // ── Follow-up: report-scoped questions ───────────────────────────────────────
  /// Answers questions that are specifically about the followed report — status,
  /// progress, timeline, or resolution — from the report's own context. Returns
  /// null when the message isn't about the report (so the caller can try the KB).
  static String? _followUpSpecific(
    String t,
    _Lang lang,
    String? reportRef,
    String? reportStatus,
    String? reportCategory,
  ) {
    final asksStatus = _hasAny(t, [
      'status',
      'update',
      'progress',
      'ano na',
      'anong nangyari',
      'kumusta ang report',
      'kamusta ang report',
      'na-ayos na',
      'naayos na',
      'tapos na ba',
      'resolved',
      'ayos na ba',
    ]);
    final asksWhen = _hasAny(t, [
      'kailan',
      'when',
      'gaano katagal',
      'how long',
      'timeline',
      'matatapos',
      'maaayos',
    ]);
    if (!asksStatus && !asksWhen) return null;

    final ref = reportRef ?? 'inyong report';
    final cat = reportCategory ?? 'concern';
    final status = reportStatus ?? 'pending';
    final ilocano = lang == _Lang.ilocano || lang == _Lang.ybanag;
    final english = lang == _Lang.english;

    if (asksWhen) {
      if (english) {
        return 'About report $ref ($cat): its current status is "$status". ⏱️ '
            'Reports are usually updated within 24–48 hours. I\'m in offline '
            'mode right now — for the latest update, choose "Talk to a person" '
            'once the connection is back. Thank you po for your patience!';
      }
      if (ilocano) {
        return 'Maipapan iti report $ref ($cat): ti kasasaad na ita ket '
            '"$status". ⏱️ Dagiti report ket masansan a ma-update iti uneg ti '
            '24–48 nga oras. Offline mode pay laeng ak ita — para iti kabaruanan '
            'nga update, pilien ti "Talk to a person" no adda manen ti koneksion. '
            'Agyamanak iti panagitured!';
      }
      return 'Tungkol po sa report na $ref ($cat): kasalukuyang status po ay '
          '"$status". ⏱️ Ang mga report po ay karaniwang na-a-update sa loob ng '
          '24–48 oras. Offline mode muna po ako ngayon — para sa mas bagong '
          'update, piliin po ang "Talk to a person" kapag available na ulit. '
          'Salamat po sa pasensya!';
    }

    if (english) {
      return 'Here\'s what I know about report $ref ($cat): the status is '
          '"$status". 📌 I\'m in offline mode right now, so I can\'t check the '
          'latest update — for that, choose "Talk to a person" once the '
          'connection is back. Thank you po!';
    }
    if (ilocano) {
      return 'Daytoy ti ammok maipapan iti report $ref ($cat): ti kasasaad na '
          'ket "$status". 📌 Offline mode pay laeng ak ita, isu a saan ko a '
          'ma-check ti kabaruanan — para iti dayta, pilien ti "Talk to a person" '
          'no agsubli ti koneksion. Agyamanak po!';
    }
    return 'Ito po ang alam ko tungkol sa report na $ref ($cat): '
        'ang status po ay "$status". 📌 Offline mode muna po ako ngayon, kaya '
        'hindi ko ma-check ang pinakabagong update — para po dito, piliin ang '
        '"Talk to a person" kapag bumalik na ang koneksyon. Salamat po!';
  }

  // ── Normalisation ──────────────────────────────────────────────────────────
  static String _norm(String s) => s.toLowerCase().trim();

  static bool _hasAny(String t, List<String> needles) {
    for (final n in needles) {
      if (t.contains(n)) return true;
    }
    return false;
  }

  // ── Intent ──────────────────────────────────────────────────────────────────
  static bool _isEnd(String t) {
    // Short "thanks/bye" style closers. Guard length so "thank you, but how…"
    // (a real question) isn't treated as goodbye.
    const closers = [
      'salamat',
      'thank you',
      'thanks',
      'ok na',
      'okay na',
      'oks na',
      'sige salamat',
      'bye',
      'goodbye',
      'paalam',
      'wala na',
      'ayos na',
      'tapos na',
      'done',
      'that\'s all',
      'thats all',
    ];
    if (!_hasAny(t, closers)) return false;
    // If it's a longer sentence that also asks something, don't end.
    return t.length <= 30 || !_hasAny(t, ['?', 'paano', 'how', 'ano', 'saan', 'magkano']);
  }

  static bool _wantsAgent(String t) => _hasAny(t, [
    'live agent',
    'human',
    'real person',
    'talk to a person',
    'kausapin',
    'tao ',
    ' tao',
    'staff',
    'opisyal',
    'connect me',
    'customer service',
    'representative',
  ]);

  static bool _wantsReport(String t) => _hasAny(t, [
    'gusto ko mag report',
    'gusto ko magreport',
    'gusto kong magreport',
    'mag report',
    'magreport',
    'mag-report',
    'magsumbong',
    'i-report',
    'ireport',
    'file a report',
    'report a',
    'report an',
    'report ng',
    'reklamo',
    'magrereklamo',
  ]);

  // ── Knowledge base ───────────────────────────────────────────────────────────
  // Each entry: trigger keywords → concise, honest answer. Process steps are
  // safe/stable; exact fees are never invented — we tell the citizen to confirm
  // at the office, exactly like the Edge Function's grounding rules.
  static String? _knowledge(String t) {
    for (final e in _kb) {
      if (_hasAny(t, e.keywords)) return e.answer;
    }
    // Greetings.
    if (_hasAny(t, ['hi', 'hello', 'kumusta', 'kamusta', 'good morning',
      'good afternoon', 'good evening', 'magandang'])) {
      return 'Kumusta po! Ako si Kuya Gov ng LGU Aparri. 👋 Maitatanong po ninyo '
          'ang tungkol sa mga serbisyo — barangay clearance, cedula, business '
          'permit, PSA documents, National ID, at iba pa. Ano po ang maitutulong ko?';
    }
    return null;
  }

  static const List<_Kb> _kb = [
    _Kb(
      ['barangay clearance', 'brgy clearance', 'clearance sa barangay'],
      'Para sa Barangay Clearance po:\n'
          '1. Pumunta sa inyong Barangay Hall (kung saan kayo nakatira).\n'
          '2. Magdala ng valid ID (minsan proof of residency) at sabihin ang '
          'layunin.\n'
          '3. Bayaran ang local fee → i-claim (madalas same day).\n'
          'Ang bayad po ay iba-iba kada barangay — i-confirm na lang po sa '
          'inyong barangay.',
    ),
    _Kb(
      ['cedula', 'community tax', 'ctc'],
      'Para sa Cedula (Community Tax Certificate) po:\n'
          '• Saan: Municipal Treasurer\'s Office (o sa ilang barangay).\n'
          '• Dalhin: valid ID at basic na personal/income info.\n'
          '• May maliit na basic fee kasama ng kaunti base sa kita — i-confirm '
          'po ang eksaktong halaga sa treasurer\'s office.',
    ),
    _Kb(
      ['business permit', 'mayor\'s permit', 'mayors permit', 'negosyo permit',
        'business clearance'],
      'Para sa Business / Mayor\'s Permit po:\n'
          '1. Kumuha ng Barangay Clearance.\n'
          '2. DTI (single) o SEC (corp/partnership) registration.\n'
          '3. Mag-apply sa Business Permits & Licensing Office (BPLO) → '
          'assessment → bayad → release.\n'
          'Ang renewal po ay madalas tuwing January. Ang fees ay depende sa uri '
          'at capital — i-confirm po sa BPLO.',
    ),
    _Kb(
      ['psa', 'birth certificate', 'birth cert', 'marriage certificate',
        'death certificate', 'cenomar'],
      'Para sa PSA documents (birth/marriage/death/CENOMAR) po:\n'
          '• Online: psahelpline.ph o PSA Serbilis para sa delivery.\n'
          '• Local na kopya/correction: Municipal Civil Registrar; ang '
          'PSA-authenticated na kopya ay galing sa PSA.\n'
          '• Dalhin ang valid ID at detalye ng taong nakarehistro.',
    ),
    _Kb(
      ['national id', 'philsys', 'philid', 'national i.d'],
      'Para sa National ID (PhilSys) po:\n'
          '• Libre po ito. Mag-register sa PhilSys center o philsys.gov.ph.\n'
          '• Steps: demographic info → biometrics (photo, fingerprints, iris) → '
          'matatanggap ang PhilID / ePhilID.\n'
          '• Dalhin ang PSA birth certificate at isang valid ID.',
    ),
    _Kb(
      ['passport', 'dfa'],
      'Para sa Passport (DFA) po:\n'
          '• Kailangan ng online appointment: passport.gov.ph (walang walk-in '
          'sa karamihan).\n'
          '• Dalhin: confirmed appointment, PSA birth certificate, valid ID.\n'
          '• Pinakamalapit na DFA sa rehiyon ay sa Tuguegarao — i-verify po ang '
          'site at slots online. I-check din po ang current fee sa website.',
    ),
    _Kb(
      ['voter', 'comelec', 'boto', 'rehistro sa boto', 'voters id',
        'voter registration'],
      'Para sa Voter Registration (COMELEC) po:\n'
          '• Saan: local COMELEC Office ng munisipyo. Libre po.\n'
          '• Dalhin ang valid ID → punan ang application → biometrics → i-claim.\n'
          '• Tumatakbo lang po ito sa mga announced na registration period — '
          'i-confirm po kung bukas ngayon.',
    ),
    _Kb(
      ['sss', 'philhealth', 'pag-ibig', 'pagibig', 'pag ibig'],
      'Ang SSS, PhilHealth, at Pag-IBIG po ay national agencies — bawat isa ay '
          'may sariling membership. Sa pangkalahatan: mag-register para sa '
          'member number → isumite ang requirements → itago ang number para sa '
          'contributions/benefits. Para sa eksaktong requirements at halaga, '
          'pumunta po sa branch o website ng ahensya.',
    ),
    _Kb(
      ['senior', 'osca', 'senior citizen'],
      'Para sa Senior Citizen ID po:\n'
          '• Para sa 60 taong gulang pataas. Saan: local OSCA. Libre po.\n'
          '• Dalhin: proof of age (PSA birth cert / valid ID) at proof of '
          'residency.',
    ),
    _Kb(
      ['pwd', 'pdao', 'disability', 'may kapansanan'],
      'Para sa PWD ID po:\n'
          '• Saan: local PDAO o MSWDO. Libre po.\n'
          '• Dalhin: medical certificate/assessment ng disability, valid ID, at '
          'ID photos.',
    ),
    _Kb(
      ['emergency', 'accident', 'sunog', 'fire', 'aksidente', 'krimen',
        'nasaktan', 'ambulansya', 'ambulance'],
      '⚠️ Kung may emergency po (aksidente, sunog, krimen, o banta sa buhay), '
          'tumawag AGAD sa 911 (nationwide). Huwag na po itong daanin sa chat — '
          'ang mabilis na tawag po ang pinakamabuti.',
    ),
    _Kb(
      ['office hour', 'bukas', 'oras ng', 'saan ang munisipyo', 'location ng',
        'hours', 'anong oras', 'schedule ng opisina'],
      'Para sa eksaktong oras at lokasyon ng opisina po, mas mabuting '
          'i-confirm sa Municipal Hall ng Aparri — nag-iiba po minsan ang '
          'schedule. Sa pangkalahatan, bukas po ang LGU tuwing weekdays sa oras '
          'ng trabaho. Salamat po sa pang-unawa!',
    ),
    // Officials are answered ONLINE from public.lgu_facts, which this offline
    // path cannot read. Rather than fall through to the generic fallback reply,
    // say plainly that the answer needs a connection — and never hardcode a
    // name here, which would go stale at the next election with nobody watching.
    _Kb(
      ['sino ang mayor', 'sinong mayor', 'mayor ng aparri', 'kasalukuyang mayor',
        'vice mayor', 'bise mayor', 'sino ang alkalde', 'alkalde',
        'konsehal', 'sangguniang bayan', 'sb member', 'opisyal ng aparri',
        'who is the mayor', 'current mayor'],
      'Pasensya na po — kailangan ko pong maka-connect sa internet para '
          'masagot nang tama ang tanong tungkol sa mga kasalukuyang opisyal ng '
          'Aparri. Ayoko pong manghula sa ganitong bagay. Pakisubukan po ulit '
          'kapag may koneksyon, o i-confirm sa Municipal Hall ng Aparri.',
    ),
    _Kb(
      ['govpulse', 'app na ito', 'ano ang app', 'gamit ng app'],
      'Sa GovPulse app po pwede kayong: mag-report ng issue (Quick Actions sa '
          'Home), magpadala ng Suggestions & Feedback, at makakita ng Events at '
          'Announcements ng Aparri. Ano po ang gusto ninyong gawin?',
    ),
  ];


  static String _followUpGeneric(
    _Lang lang,
    String? reportRef,
    String? reportStatus,
    String? reportCategory,
  ) {
    final ref = reportRef ?? 'inyong report';
    final cat = reportCategory ?? 'concern';
    final status = reportStatus ?? 'pending';
    if (lang == _Lang.english) {
      return 'I can see report $ref ($cat) — status: $status. 📌\n\n'
          'I\'m in offline mode right now, but here\'s what I know: reports are '
          'usually updated within 24–48 hours. For live staff, choose "Talk to '
          'a person" once the connection is back. Thank you po for your patience!';
    }
    if (lang == _Lang.ilocano || lang == _Lang.ybanag) {
      return 'Makitkitak ti report $ref ($cat) — kasasaad: $status. 📌\n\n'
          'Offline mode pay laeng ak ita, ngem daytoy ti ammok: dagiti report '
          'ket masansan a ma-update iti uneg ti 24–48 nga oras. Para iti live '
          'nga staff, pilien ti "Talk to a person" no agsubli ti koneksion. '
          'Agyamanak iti panagitured!';
    }
    return 'Nakikita ko po ang report na $ref ($cat) — status: $status. 📌\n\n'
        'Offline mode muna po ako ngayon, pero ito po ang alam ko: '
        'ang mga report ay karaniwang na-a-update sa loob ng 24–48 oras. '
        'Para sa live na staff, piliin po ang "Talk to a person" kapag '
        'available na ulit ang koneksyon. Salamat po sa pasensya!';
  }
}

/// Languages the on-device brain localises its short replies into. Ybanag maps
/// to Ilocano (never fabricate shaky Ybanag — the same safe rule the AI uses).
enum _Lang { tagalog, ilocano, ybanag, english }

class _Kb {
  final List<String> keywords;
  final String answer;
  const _Kb(this.keywords, this.answer);
}
