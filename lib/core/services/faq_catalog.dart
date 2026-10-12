// lib/core/services/faq_catalog.dart
//
// Ready-made answers for Kuya Gov's "Common questions" chips.
//
// Panel revision (2026-10-12): the chat is for FAQs, not conversation. Tapping
// a chip answers instantly from this catalog — no AI call, no rate limit, works
// offline — so the most common questions always get the same, checked answer.
// Typed questions still go to the AI, which is held to the same scope.
//
// RULES FOR AN ANSWER HERE (same as LocalAssistant's knowledge base):
//   • Process steps only. Never a peso amount or a date that is not in a
//     verified fact — fees and schedules change and a wrong one is worse than
//     "confirm at the office".
//   • Anything specific to Aparri (names, hours, places, hotlines) comes from
//     public.lgu_facts at runtime via [Faq.factKeys], never from this file, so
//     an LGU correction reaches citizens without an app release.

/// A FAQ group, in the order the "All questions" sheet lists them.
enum FaqTopic {
  app('Using GovPulse'),
  documents('Documents & IDs'),
  offices('Offices & officials'),
  safety('Emergencies');

  const FaqTopic(this.label);
  final String label;
}

class Faq {
  final String id;
  final FaqTopic topic;

  /// Short enough for a chip.
  final String question;

  /// Builds the answer. [facts] is the published `lgu_facts` rows as
  /// key → value (empty when offline or unpublished); an answer that names a
  /// fact must still read correctly when it is missing.
  final String Function(Map<String, String> facts) answer;

  /// The `lgu_facts` keys [answer] reads. Empty for answers that need none, so
  /// those never wait on a fetch.
  final List<String> factKeys;

  const Faq({
    required this.id,
    required this.topic,
    required this.question,
    required this.answer,
    this.factKeys = const [],
  });
}

String _fact(Map<String, String> facts, String key) =>
    (facts[key] ?? '').trim();

const _confirmAtHall =
    'Para sa pinakabagong detalye, i-confirm po sa Municipal Hall ng Aparri.';

/// Every FAQ, in display order (grouped by [FaqTopic] in the full list).
final List<Faq> kFaqs = [
  // ── Using GovPulse ────────────────────────────────────────────────────────
  Faq(
    id: 'how_to_report',
    topic: FaqTopic.app,
    question: 'Paano mag-report ng problema?',
    answer: (_) =>
        'Para mag-report po ng problema sa inyong lugar (sirang daan, basura, '
        'baha, streetlight, at iba pa):\n'
        '1. Sa Home, i-tap ang "Report Issue" sa Quick Actions.\n'
        '2. Piliin ang kategorya at ilarawan ang problema.\n'
        '3. Ilagay ang lokasyon at magdagdag ng litrato kung meron.\n'
        '4. I-submit — mapupunta ito sa tamang opisina.\n'
        'Makikita po ninyo ang status nito sa "My Reports".',
  ),
  Faq(
    id: 'track_report',
    topic: FaqTopic.app,
    question: 'Paano ko makikita ang status ng report ko?',
    answer: (_) =>
        'Buksan po ang "My Reports" at i-tap ang report. Makikita ninyo ang '
        'timeline nito — kung natanggap na, ginagawa na, o naayos na — pati '
        'ang mga update at litrato mula sa opisina. Makakatanggap din po kayo '
        'ng notification tuwing may pagbabago.',
  ),
  Faq(
    id: 'talk_to_staff',
    topic: FaqTopic.app,
    question: 'Pwede ko bang makausap ang staff dito?',
    answer: (_) =>
        'Walang live chat sa staff dito sa GovPulse, para bawat concern ay '
        'naitatala at nasusundan ng tamang opisina. Gamitin po ang Quick '
        'Actions sa Home:\n'
        '• Report Issue — para sa problema o reklamo\n'
        '• Suggestion — para sa mungkahi\n'
        '• Feedback — para sa serbisyo ng isang opisina\n'
        'Kung emergency po, tawagan ang hotlines sa Emergency section.',
  ),
  Faq(
    id: 'why_verify',
    topic: FaqTopic.app,
    question: 'Bakit kailangan i-verify ang account ko?',
    answer: (_) =>
        'Para matiyak po na totoong residente ng Aparri ang nagpapadala ng '
        'report, suggestion at feedback. Magpapasa kayo ng valid ID at selfie; '
        'sinusuri ito ng LGU bago ma-verify ang account. Habang hindi pa '
        'verified, pwede pa rin kayong magbasa ng announcements at events.',
  ),
  Faq(
    id: 'anonymous',
    topic: FaqTopic.app,
    question: 'Pwede ba akong mag-report nang anonymous?',
    answer: (_) =>
        'Opo. Sa Report, Suggestion at Feedback ay may opsyon na "Submit '
        'anonymously". Hindi makikita ng mga opisina kung sino kayo, pero '
        'makikita pa rin ninyo ang status at mga update ng inyong submission '
        'sa inyong account.',
  ),
  Faq(
    id: 'suggestion_vs_feedback',
    topic: FaqTopic.app,
    question: 'Ano ang pagkakaiba ng Suggestion at Feedback?',
    answer: (_) =>
        '• Suggestion — isang ideya o mungkahi para sa bayan, gaya ng bagong '
        'programa o pagbabago sa serbisyo. Sinasagot ito ng opisina.\n'
        '• Feedback — rating at komento tungkol sa serbisyong natanggap ninyo '
        'mula sa isang opisina ng munisipyo.\n'
        'Para sa problemang kailangang ayusin, gamitin po ang Report Issue.',
  ),

  // ── Documents & IDs ───────────────────────────────────────────────────────
  Faq(
    id: 'barangay_clearance',
    topic: FaqTopic.documents,
    question: 'Paano kumuha ng Barangay Clearance?',
    answer: (_) =>
        'Para sa Barangay Clearance po:\n'
        '1. Pumunta sa Barangay Hall kung saan kayo nakatira.\n'
        '2. Magdala ng valid ID (minsan proof of residency) at sabihin ang '
        'layunin.\n'
        '3. Bayaran ang local fee at i-claim (madalas same day).\n'
        'Iba-iba po ang bayad kada barangay — i-confirm sa inyong barangay.',
  ),
  Faq(
    id: 'cedula',
    topic: FaqTopic.documents,
    question: 'Paano kumuha ng Cedula?',
    factKeys: const ['cedula_office', 'cedula_fee'],
    answer: (f) {
      final office = _fact(f, 'cedula_office');
      final fee = _fact(f, 'cedula_fee');
      return 'Para sa Cedula (Community Tax Certificate) po:\n'
          '• Saan: ${office.isNotEmpty ? office : "Municipal Treasurer's Office"}\n'
          '• Dalhin: valid ID at basic na personal/income info.\n'
          '${fee.isNotEmpty ? '• Bayad: $fee\n' : '• May maliit na basic fee at dagdag na base sa kita.\n'}'
          '$_confirmAtHall';
    },
  ),
  Faq(
    id: 'business_permit',
    topic: FaqTopic.documents,
    question: 'Paano kumuha ng Business Permit?',
    factKeys: const ['business_permit_office', 'business_permit_requirements'],
    answer: (f) {
      final office = _fact(f, 'business_permit_office');
      final reqs = _fact(f, 'business_permit_requirements');
      return 'Para sa Business / Mayor\'s Permit po:\n'
          '1. Kumuha ng Barangay Clearance.\n'
          '2. DTI (single) o SEC (corporation/partnership) registration.\n'
          '3. Mag-apply sa ${office.isNotEmpty ? office : 'Business Permits & Licensing Office (BPLO)'} '
          '→ assessment → bayad → release.\n'
          '${reqs.isNotEmpty ? 'Requirements: $reqs\n' : ''}'
          'Ang fees ay depende sa uri at capital ng negosyo. $_confirmAtHall';
    },
  ),
  Faq(
    id: 'birth_certificate',
    topic: FaqTopic.documents,
    question: 'Paano kumuha ng Birth Certificate?',
    factKeys: const ['birth_registration'],
    answer: (f) {
      final reg = _fact(f, 'birth_registration');
      return 'Para sa Birth Certificate po:\n'
          '• PSA copy: online sa psahelpline.ph o PSA Serbilis (may delivery), '
          'o sa PSA outlet.\n'
          '• Local copy o pag-rehistro/pagtama: Municipal Civil Registrar.\n'
          '${reg.isNotEmpty ? '• $reg\n' : ''}'
          '• Dalhin ang valid ID at detalye ng taong nakarehistro.';
    },
  ),
  Faq(
    id: 'national_id',
    topic: FaqTopic.documents,
    question: 'Paano mag-apply ng National ID?',
    answer: (_) =>
        'Para sa National ID (PhilSys) po:\n'
        '• Libre ito. Mag-register sa PhilSys registration center o sa '
        'philsys.gov.ph.\n'
        '• Steps: personal info → biometrics (litrato, fingerprints, iris) → '
        'matatanggap ang PhilID o ePhilID.\n'
        '• Dalhin ang PSA birth certificate at isang valid ID.',
  ),
  Faq(
    id: 'senior_pwd_id',
    topic: FaqTopic.documents,
    question: 'Paano kumuha ng Senior Citizen o PWD ID?',
    factKeys: const ['osca_office', 'pdao_office'],
    answer: (f) {
      final osca = _fact(f, 'osca_office');
      final pdao = _fact(f, 'pdao_office');
      return 'Libre po ang dalawa:\n'
          '• Senior Citizen ID (60 pataas): ${osca.isNotEmpty ? osca : 'sa OSCA'}. '
          'Dalhin ang proof of age (PSA birth certificate o valid ID) at proof '
          'of residency.\n'
          '• PWD ID: ${pdao.isNotEmpty ? pdao : 'sa PDAO o MSWDO'}. Dalhin ang '
          'medical certificate ng disability, valid ID at ID photos.';
    },
  ),

  // ── Offices & officials ───────────────────────────────────────────────────
  Faq(
    id: 'mayor',
    topic: FaqTopic.offices,
    question: 'Sino ang Mayor ng Aparri?',
    factKeys: const ['mayor', 'vice_mayor'],
    answer: (f) {
      final mayor = _fact(f, 'mayor');
      final vice = _fact(f, 'vice_mayor');
      if (mayor.isEmpty) {
        return 'Pasensya na po — hindi ko ito ma-check ngayon. $_confirmAtHall';
      }
      return 'Ang kasalukuyang Mayor ng Aparri ay si $mayor.'
          '${vice.isNotEmpty ? ' Ang Vice Mayor naman ay si $vice.' : ''}';
    },
  ),
  Faq(
    id: 'municipal_hall',
    topic: FaqTopic.offices,
    question: 'Saan at anong oras bukas ang Municipal Hall?',
    factKeys: const ['municipal_hall_location', 'municipal_hall_hours'],
    answer: (f) {
      final where = _fact(f, 'municipal_hall_location');
      final hours = _fact(f, 'municipal_hall_hours');
      if (where.isEmpty && hours.isEmpty) {
        return 'Karaniwang bukas po ang munisipyo tuwing weekdays sa oras ng '
            'trabaho. $_confirmAtHall';
      }
      return 'Municipal Hall ng Aparri:\n'
          '${where.isNotEmpty ? '• Lokasyon: $where\n' : ''}'
          '${hours.isNotEmpty ? '• Oras: $hours\n' : ''}'
          'Paalala po: nagbabago minsan ang schedule tuwing holiday.';
    },
  ),
  Faq(
    id: 'contact_lgu',
    topic: FaqTopic.offices,
    question: 'Paano makontak ang munisipyo?',
    factKeys: const ['municipal_hotline', 'mayors_office_line'],
    answer: (f) {
      final hotline = _fact(f, 'municipal_hotline');
      final mayors = _fact(f, 'mayors_office_line');
      if (hotline.isEmpty && mayors.isEmpty) {
        return 'Pasensya na po — wala pa akong verified na numero ngayon. '
            '$_confirmAtHall';
      }
      return 'Mga numero ng munisipyo:\n'
          '${hotline.isNotEmpty ? '• Hotline: $hotline\n' : ''}'
          '${mayors.isNotEmpty ? "• Mayor's Office: $mayors\n" : ''}'
          'Para sa concern na kailangang aksyunan, mas mabuting gamitin ang '
          'Report Issue para ito ay masundan.';
    },
  ),

  // ── Emergencies ───────────────────────────────────────────────────────────
  Faq(
    id: 'emergency',
    topic: FaqTopic.safety,
    question: 'Ano ang gagawin sa emergency?',
    factKeys: const ['police_hotline', 'fire_hotline', 'hospital_hotline'],
    answer: (f) {
      final police = _fact(f, 'police_hotline');
      final fire = _fact(f, 'fire_hotline');
      final hospital = _fact(f, 'hospital_hotline');
      return '⚠️ Kung may aksidente, sunog, krimen o banta sa buhay, tumawag '
          'AGAD sa 911. Huwag na pong daanin sa chat.\n'
          '${police.isNotEmpty ? '• Pulis: $police\n' : ''}'
          '${fire.isNotEmpty ? '• Bumbero: $fire\n' : ''}'
          '${hospital.isNotEmpty ? '• Ospital: $hospital\n' : ''}'
          'Nasa Emergency section din po ng app ang mga hotline, na isang tap '
          'lang para tumawag.';
    },
  ),
];

/// The chips shown under the greeting — a mix of the questions people ask
/// most, not just the first rows. Everything else is behind "All questions".
const List<String> kFeaturedFaqIds = [
  'how_to_report',
  'track_report',
  'mayor',
  'municipal_hall',
  'barangay_clearance',
  'emergency',
];

List<Faq> get featuredFaqs => [
      for (final id in kFeaturedFaqIds) kFaqs.firstWhere((f) => f.id == id),
    ];
