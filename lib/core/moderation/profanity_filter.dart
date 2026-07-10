// ════════════════════════════════════════════════════════════════════════════
//  Multilingual profanity filter — English + Filipino/Tagalog + Ilocano
//
//  Used across the citizen community feed (posts + comments) two ways:
//    • analyze()        → is there profanity? (drives the `flagged` column so
//                         admins can review; also enforced server-side).
//    • maskForDisplay() → render-time masking so citizens never SEE profanity,
//                         even if a row was inserted by a bypassed client.
//
//  The original text is always stored unchanged — admins see the real content to
//  judge it; masking is display-only.
//
//  Detection is resilient to common evasion: leetspeak (g4go, t@ngina), padded
//  repeats (puuuta), diacritics (ñ), and spaced-out letters (p u t a). A
//  safe-word allowlist prevents the classic false positives (e.g. "puto",
//  "assist", "Scunthorpe").
// ════════════════════════════════════════════════════════════════════════════

class ProfanityResult {
  final bool hasProfanity;

  /// The normalized roots that matched — useful as a flag reason for admins.
  final List<String> matches;

  const ProfanityResult(this.hasProfanity, this.matches);

  /// A short admin-facing reason, e.g. "Possible profanity: gago, puta".
  String get reason =>
      hasProfanity ? 'Possible profanity: ${matches.join(', ')}' : '';
}

class ProfanityFilter {
  ProfanityFilter._();

  // ── Lexicon ────────────────────────────────────────────────────────────────
  // Roots are stored already-normalized (lowercase, leetspeak resolved, repeats
  // collapsed). Matching tolerates affixes (gago → gagong, tangina → putangina),
  // so keep roots short but unambiguous. Add new terms here in ONE place.
  static const Set<String> _roots = {
    // English
    'fuck', 'shit', 'bitch', 'asshole', 'bastard', 'dick', 'pussy', 'cunt',
    'motherfucker', 'nigger', 'faggot', 'whore', 'slut', 'retard',
    // Tagalog / Filipino
    'putangina', 'tangina', 'putanginamo', 'puta', 'gago', 'gaga', 'tanga',
    'ulol', 'tarantado', 'bobo', 'pakyu', 'kingina', 'kupal', 'hindot',
    'hayop', 'punyeta', 'leche', 'pesteng', 'buwisit', 'yawa', 'lintik',
    'tae', 'jakol', 'iyot', 'kantot', 'burat', 'titi', 'puke', 'pekpek',
    // Ilocano (Cagayan)
    'ukinnam', 'ukinam', 'okinnam', 'okinam', 'ukininam', 'kimat', 'baboy',
    'nabuang', 'giddan',
  };

  // Words that would be FALSE positives under substring matching. Compared as
  // whole normalized tokens — if a token is here, it's never flagged.
  static const Set<String> _allow = {
    // English safe words that contain a root substring
    'assist', 'assistant', 'assign', 'assess', 'class', 'classic', 'pass',
    'passion', 'grass', 'glass', 'bass', 'mass', 'massage', 'assassin',
    'assume', 'assumption', 'analysis', 'analyst', 'shitake', 'cockpit',
    'scunthorpe', 'dickens', 'canal',
    // Filipino / Ilocano safe words that resemble a root
    'puto', 'putol', 'putok', 'puti', 'putin', 'reputasyon',
    'diputado', 'tagana', 'tanggap', 'tanggapan', 'tanghali', 'tanging',
    'baboyan', 'hayopan', 'titik', 'titig', 'titser', 'bobato',
  };

  // Leetspeak / homoglyph → letter. Applied before matching.
  static const Map<String, String> _leet = {
    '0': 'o', '1': 'i', '3': 'e', '4': 'a', '5': 's', '7': 't', '8': 'b',
    '@': 'a', '\$': 's', '!': 'i', '+': 't',
  };

  // Common accented characters → ASCII (Dart has no built-in NFD stripping).
  static const Map<String, String> _accents = {
    'ñ': 'n', 'á': 'a', 'à': 'a', 'â': 'a', 'ä': 'a', 'é': 'e', 'è': 'e',
    'ê': 'e', 'í': 'i', 'ì': 'i', 'î': 'i', 'ó': 'o', 'ò': 'o', 'ô': 'o',
    'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
  };

  /// Normalize a single word for matching: lowercase, de-accent, resolve
  /// leetspeak, keep letters only, then collapse runs of the same letter
  /// (puuuta → puta) so padded evasion still matches.
  static String _normalize(String word) {
    final buf = StringBuffer();
    for (final ch in word.toLowerCase().split('')) {
      final deAccented = _accents[ch] ?? ch;
      final deLeet = _leet[deAccented] ?? deAccented;
      // keep a-z only
      if (deLeet.codeUnitAt(0) >= 0x61 && deLeet.codeUnitAt(0) <= 0x7a) {
        buf.write(deLeet);
      }
    }
    return _collapseRepeats(buf.toString());
  }

  static String _collapseRepeats(String s) {
    if (s.length < 2) return s;
    final out = StringBuffer()..write(s[0]);
    for (var i = 1; i < s.length; i++) {
      if (s[i] != s[i - 1]) out.write(s[i]);
    }
    return out.toString();
  }

  /// Does a normalized token match a root? Long roots (>= 6) match anywhere in
  /// the token (they're unambiguous); short roots must sit at a word boundary
  /// (equal / prefix / suffix) so "reputation" ⊅ "puta" and "chicago" ⊅ "gago".
  static bool _matchesRoot(String token) {
    for (final r in _roots) {
      final hit = r.length >= 6
          ? token.contains(r)
          : (token == r || token.startsWith(r) || token.endsWith(r));
      if (hit) return true;
    }
    return false;
  }

  static bool _tokenIsProfane(String normalizedToken) {
    if (normalizedToken.length < 3) return false;
    if (_allow.contains(normalizedToken)) return false;
    return _matchesRoot(normalizedToken);
  }

  /// Is there any profanity in [text]? Also catches spaced-out evasion
  /// ("p u t a") by scanning the whole condensed string for longer roots.
  static ProfanityResult analyze(String? text) {
    if (text == null || text.trim().isEmpty) {
      return const ProfanityResult(false, []);
    }
    final matches = <String>{};

    // Word-level (handles leetspeak, repeats, affixes, allowlist). We also join
    // runs of single-letter tokens to catch letter-spaced evasion ("p u t a").
    final words = text.split(RegExp(r'[^\p{L}\p{N}@$!+]+', unicode: true));
    final condensedBuf = StringBuffer();
    final singleRun = StringBuffer();

    void flushRun() {
      final r = singleRun.toString();
      singleRun.clear();
      if (r.length >= 3 && _matchesRoot(r)) matches.add(r);
    }

    for (final w in words) {
      final n = _normalize(w);
      if (n.isEmpty) continue;
      condensedBuf.write(n);
      if (n.length == 1) {
        singleRun.write(n);
        continue;
      }
      flushRun();
      if (n.length < 3 || _allow.contains(n)) continue;
      if (_matchesRoot(n)) matches.add(n);
    }
    flushRun();

    // Multi-char split evasion ("puta ngina"): scan the fully condensed text for
    // longer roots only — short roots would over-match once gaps are gone.
    final condensed = condensedBuf.toString();
    for (final r in _roots) {
      if (r.length >= 5 && condensed.contains(r)) matches.add(r);
    }

    return ProfanityResult(matches.isNotEmpty, matches.toList());
  }

  /// True if [text] contains profanity (convenience wrapper).
  static bool contains(String? text) => analyze(text).hasProfanity;

  /// Returns [text] with any profane WORD replaced by asterisks, preserving the
  /// surrounding punctuation/spacing. Display-only — never mutate stored text.
  static String maskForDisplay(String? text) {
    if (text == null || text.isEmpty) return text ?? '';
    // Split into word / non-word chunks so we can rebuild the string verbatim.
    return text.splitMapJoin(
      RegExp(r'[\p{L}\p{N}@$!+]+', unicode: true),
      onMatch: (m) {
        final word = m[0]!;
        return _tokenIsProfane(_normalize(word)) ? '*' * word.length : word;
      },
      onNonMatch: (s) => s,
    );
  }
}
