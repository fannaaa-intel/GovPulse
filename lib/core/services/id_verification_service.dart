import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect;
// ignore_for_file: avoid_print
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';

enum VerificationConfidence { high, low, none }

class IdVerificationResult {
  final bool isValid;
  final VerificationConfidence confidence;
  final String? errorMessage;
  final Map<String, String> extractedData;
  final int matchedKeywords;
  final String rawText;

  IdVerificationResult({
    required this.isValid,
    required this.confidence,
    this.errorMessage,
    this.extractedData = const {},
    this.matchedKeywords = 0,
    required this.rawText,
  });
}

class IdVerificationService {
  // ─────────────────────────────────────────────────────────────────────────
  // KEYWORDS — front, back, and back-side data hints per ID type
  // ─────────────────────────────────────────────────────────────────────────

  static const Map<String, List<String>> _frontKeywords = {
    "PhilSys ID": [
      "PHILSYS",
      "PHIL SYS",
      "PHILIPPINE IDENTIFICATION",
      "PHILIPPINE LDENTIFICATION",
      "IDENTIFICATION CARD",
      "LDENTIFICATION CARD",
      "REPUBLIKA NG PILIPINAS",
      "PAMBANSANG PAGKAKAKILANLAN",
      "BANSANG PAGKAKAKILANL",
      "PAGKAKAKILANLAN",
    ],
    "Driver's License ID": [
      "DRIVER'S LICENSE",
      "DRIVERS LICENSE",
      "LAND TRANSPORTATION OFFICE",
      "NON-PROFESSIONAL",
      "NON PROFESSIONAL",
      "PROFESSIONAL DRIVER",
    ],
    "Postal ID": ["POSTAL ID", "PHILPOST", "PHILIPPINE POSTAL", "PHLPOST"],
    "Philippine Passport ID": [
      "PASSPORT",
      "PASAPORTE",
      "DEPARTMENT OF FOREIGN AFFAIRS",
      "REPUBLIKA NG PILIPINAS",
    ],
    "PhilHealth ID": [
      "PHILHEALTH",
      "PHIL HEALTH",
      "PHILIPPINE HEALTH INSURANCE",
      "MEMBER DATA RECORD",
    ],
    "PRC ID": [
      "PROFESSIONAL REGULATION COMMISSION",
      "PROFESSIONAL IDENTIFICATION CARD",
      "PRC",
    ],
    "SSS ID": ["SOCIAL SECURITY SYSTEM", "COMMON REFERENCE NUMBER", "SSS"],
    "TIN ID": [
      "TAXPAYER IDENTIFICATION",
      "BUREAU OF INTERNAL REVENUE",
      "BIR",
      "TIN",
    ],
    "UMID ID": [
      "UNIFIED MULTI-PURPOSE",
      "UNIFIED MULTIPURPOSE IDENTIFICATION",
      "UMID",
    ],
  };

  static const Map<String, List<String>> _backKeywords = {
    "PhilSys ID": [
      "KASARIAN",
      "KALAGAYANG SIBIL",
      "LUGAR NG KAPANGANAKAN",
      "LUGAR NG KAPANGANÁKAN",
      "MARITAL STATUS",
      "PLACE OF BIRTH",
      "PHILSYS",
      "PSA",
      "PAGKAKAKILANLAN",
      "BLOOD TYPE",
      "URI NG DUGO",
    ],
    "Driver's License ID": [
      "LAND TRANSPORTATION OFFICE",
      "RESTRICTIONS",
      "CONDITIONS",
      "EXPIRATION",
      "DRIVERS LICENSE",
      "DRIVER'S LICENSE",
      "LTO",
    ],
    "Postal ID": [
      "PHILPOST",
      "PHILIPPINE POSTAL",
      "POSTAL ID",
      "PHLPOST",
      "POSTMASTER",
    ],
    "Philippine Passport ID": [
      "DEPARTMENT OF FOREIGN AFFAIRS",
      "PASSPORT",
      "REPUBLIKA NG PILIPINAS",
      "NOT VALID",
      "BEARER",
    ],
    "PhilHealth ID": [
      "PHILHEALTH",
      "PHIL HEALTH",
      "PHILIPPINE HEALTH INSURANCE",
      "BENEFIT",
      "MEMBER",
    ],
    "PRC ID": [
      "PROFESSIONAL REGULATION COMMISSION",
      "PRC",
      "BOARD",
      "LICENSE NUMBER",
    ],
    "SSS ID": [
      "SOCIAL SECURITY SYSTEM",
      "SSS",
      "COMMON REFERENCE NUMBER",
      "BENEFICIARY",
    ],
    "TIN ID": ["BUREAU OF INTERNAL REVENUE", "BIR", "TAXPAYER", "TIN"],
    "UMID ID": [
      "UNIFIED MULTI-PURPOSE",
      "UMID",
      "SSS",
      "GSIS",
      "PHILHEALTH",
      "PAG-IBIG",
      "PAGIBIG",
    ],
  };

  static const Map<String, List<String>> _backDataFields = {
    "PhilSys ID": ['gender', 'civilStatus', 'birthplace', 'idNumber'],
    "Driver's License ID": ['idNumber', 'gender', 'street'],
    "Postal ID": ['lastName', 'firstName', 'street'],
    "Philippine Passport ID": ['idNumber', 'birthdate', 'lastName'],
    "PhilHealth ID": ['idNumber', 'lastName', 'firstName'],
    "PRC ID": ['idNumber', 'lastName'],
    "SSS ID": ['idNumber', 'lastName'],
    "TIN ID": ['idNumber'],
    "UMID ID": ['idNumber', 'lastName'],
  };

  // ─────────────────────────────────────────────────────────────────────────
  // VALIDATORS — used by every ID extractor. Empty result if not confident.
  // ─────────────────────────────────────────────────────────────────────────

  static const _allLabelWords = [
    // PhilSys labels
    'APELYIDO', 'PANGALAN', 'GITNANG', 'KAPANGANAKAN', 'KAPANGANAKAR',
    'KAPANGANAKARN', 'LAST NAME', 'GIVEN NAME', 'MIDDLE NAME',
    'DATE OF BIRTH', 'PLACE OF BIRTH', 'KASARIAN', 'TIRAHAN', 'LUGAR',
    'REPUBLIKA', 'PHILIPPINES', 'PILIPINAS', 'IDENTIFICATION',
    'PHILSYS', 'PAGKAKAKILANLAN', 'KALAGAYANG', 'MARITAL STATUS',
    'URI NG DUGO', 'BLOOD TYPE', 'ARAW NG PAGKAKALOOB', 'DATE OF ISSUE',
    'PSA OFFICE', 'IFFOUND', 'PSA.GOV', 'WWW.',
    // Driver's License labels
    'LAND TRANSPORTATION', 'LICENSE NO', 'EXPIRATION DATE',
    'AGENCY CODE', 'NATIONALITY', 'WEIGHT', 'HEIGHT', 'BLOOD',
    'EYES COLOR', 'RESTRICTIONS', 'CONDITIONS', 'LTO',
    "DRIVER'S LICENSE", 'DRIVERS LICENSE',
    // Postal ID labels
    'POSTAL ID', 'PHILPOST', 'POSTMASTER', 'SURNAME', 'ADDRESS',
    'EFFECTIVE', 'EXPIRY',
    // Passport labels
    'PASSPORT', 'PASAPORTE', 'BEARER', 'SURNAME', 'GIVEN NAMES',
    'DATE OF EXPIRY', 'PLACE OF ISSUE', 'AUTHORITY', 'TYPE',
    'COUNTRY CODE', 'NOT VALID',
    // PhilHealth
    'PHILHEALTH', 'PIN', 'MEMBER', 'MDR',
    // PRC
    'PROFESSIONAL REGULATION', 'REGISTRATION', 'VALID UNTIL',
    // SSS / UMID / TIN
    'SOCIAL SECURITY', 'COMMON REFERENCE', 'CRN', 'CARD NO',
    'TAXPAYER', 'BUREAU OF INTERNAL', 'GSIS', 'PAG-IBIG', 'PAGIBIG',
  ];

  static bool _looksLikeLabel(String text) {
    final up = text.toUpperCase();
    return _allLabelWords.any((w) => up.contains(w));
  }

  /// Real person's name — letters only, mostly uppercase, no labels.
  static bool _looksLikeName(String s) {
    final trimmed = s.trim();
    if (trimmed.length < 2 || trimmed.length > 50) return false;
    if (RegExp(r'\d').hasMatch(trimmed)) return false;
    if (_looksLikeLabel(trimmed)) return false;
    if (!RegExp(r"^[A-Za-zÑñ\s\-.']+$").hasMatch(trimmed)) return false;
    final letters = trimmed.replaceAll(RegExp(r'[^A-Za-zÑñ]'), '');
    if (letters.length < 2) return false;
    final upperLetters = letters.replaceAll(RegExp(r'[^A-ZÑ]'), '');
    return upperLetters.length / letters.length >= 0.7;
  }

  /// PhilSys PCN: 4-4-4-4 digits, rejects all-same-digit noise.
  static String? _extractConfidentPcn(String upper) {
    final match = RegExp(
      r'(\d{4})[\s\-]+(\d{4})[\s\-]+(\d{4})[\s\-]+(\d{4})',
    ).firstMatch(upper);
    if (match == null) return null;
    final joined = '${match[1]}${match[2]}${match[3]}${match[4]}';
    if (RegExp(r'^(\d)\1{15}$').hasMatch(joined)) return null;
    return '${match[1]}-${match[2]}-${match[3]}-${match[4]}';
  }

  /// Driver's License number: e.g. N03-12-345678
  static String? _extractConfidentDlNumber(String upper) {
    final m = RegExp(
      r'\b([A-Z]\d{2})[-\s]?(\d{2})[-\s]?(\d{6})\b',
    ).firstMatch(upper);
    if (m == null) return null;
    return '${m[1]}-${m[2]}-${m[3]}';
  }

  /// PhilHealth PIN: 12 digits split 2-9-1 or 4-4-4
  static String? _extractConfidentPhilHealthPin(String upper) {
    final m = RegExp(r'\b(\d{2})[-\s](\d{9})[-\s](\d)\b').firstMatch(upper);
    if (m != null) return '${m[1]}-${m[2]}-${m[3]}';
    final alt = RegExp(
      r'\b(\d{4})[-\s](\d{4})[-\s](\d{4})\b',
    ).firstMatch(upper);
    if (alt != null) return '${alt[1]}-${alt[2]}-${alt[3]}';
    return null;
  }

  /// SSS / UMID CRN: 10 digits split 2-7-1 e.g. 12-3456789-0
  static String? _extractConfidentSssNumber(String upper) {
    final m = RegExp(r'\b(\d{2})[-\s](\d{7})[-\s](\d)\b').firstMatch(upper);
    if (m == null) return null;
    return '${m[1]}-${m[2]}-${m[3]}';
  }

  /// TIN: 9 or 12 digits split 3-3-3 or 3-3-3-3
  static String? _extractConfidentTin(String upper) {
    final m = RegExp(
      r'\b(\d{3})[-\s](\d{3})[-\s](\d{3})(?:[-\s](\d{3}))?\b',
    ).firstMatch(upper);
    if (m == null) return null;
    final base = '${m[1]}-${m[2]}-${m[3]}';
    return m[4] != null ? '$base-${m[4]}' : base;
  }

  /// PRC license: 7 digits
  static String? _extractConfidentPrcNumber(String upper) {
    final m = RegExp(r'\b(\d{7})\b').firstMatch(upper);
    return m?.group(0);
  }

  /// Passport: 1 letter + 7 digits (e.g. P1234567) or 9-digit format
  static String? _extractConfidentPassportNumber(String upper) {
    final m = RegExp(r'\b([A-Z]\d{7}[A-Z]?)\b').firstMatch(upper);
    return m?.group(1);
  }

  /// Postal ID number: typically 13-digit alphanumeric
  static String? _extractConfidentPostalNumber(String upper) {
    final m = RegExp(r'\b([A-Z]{3}\d{4}[A-Z]\d{5})\b').firstMatch(upper);
    if (m != null) return m.group(1);
    final alt = RegExp(r'\b(\d{4}[-\s]\d{4}[-\s]\d{4})\b').firstMatch(upper);
    return alt?.group(1)?.replaceAll(' ', '-');
  }

  /// Real place — mostly letters, no labels.
  static bool _looksLikePlace(String s) {
    final trimmed = s.trim();
    if (trimmed.length < 3 || trimmed.length > 80) return false;
    if (_looksLikeLabel(trimmed)) return false;
    if (!RegExp(r"^[A-Za-zÑñ0-9\s,.\-/]+$").hasMatch(trimmed)) return false;
    final letters = trimmed.replaceAll(RegExp(r'[^A-Za-zÑñ]'), '');
    return letters.length / trimmed.length >= 0.6;
  }

  /// Address — looser than place: allows numbers (house numbers, etc.)
  static bool _looksLikeAddress(String s) {
    final trimmed = s.trim();
    if (trimmed.length < 5 || trimmed.length > 120) return false;
    if (_looksLikeLabel(trimmed)) return false;
    if (!RegExp(r"^[A-Za-zÑñ0-9\s,.#'\-/]+$").hasMatch(trimmed)) return false;
    final letters = trimmed.replaceAll(RegExp(r'[^A-Za-zÑñ]'), '');
    return letters.length / trimmed.length >= 0.4;
  }

  static String? _normalizeGender(String s) {
    final up = s.toUpperCase().trim().replaceAll(RegExp(r'[^A-Z]'), '');
    if (up == 'MALE' || up == 'LALAKI' || up == 'M') return 'male';
    if (up == 'FEMALE' || up == 'BABAE' || up == 'F') return 'female';
    return null;
  }

  static String? _normalizeCivilStatus(String s) {
    final up = s.toUpperCase().trim();
    if (up.contains('SINGLE')) return 'Single';
    if (up.contains('MARRIED')) return 'Married';
    if (up.contains('WIDOW')) return 'Widowed';
    if (up.contains('SEPARAT')) return 'Separated';
    return null;
  }

  static String? _extractConfidentDate(String raw) {
    final normalized = _normalizeDate(raw);
    if (RegExp(r'^\d{1,2}/\d{1,2}/\d{4}$').hasMatch(normalized)) {
      return normalized;
    }
    return null;
  }

  static String _normalize(String s) =>
      s.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  // ─────────────────────────────────────────────────────────────────────────
  // OCR runner & verify() — unchanged from your file
  // ─────────────────────────────────────────────────────────────────────────

  static Future<RecognizedText> _runOcr(Uint8List bytes) async {
    final tempDir = await getTemporaryDirectory();
    final file = File(
      '${tempDir.path}/ocr_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    await file.writeAsBytes(bytes);
    print('[ID-VERIFY] OCR input file: ${file.path} (${bytes.length} bytes)');

    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final input = InputImage.fromFilePath(file.path);
      final r = await recognizer.processImage(input);
      print('[ID-VERIFY] OCR completed. Blocks=${r.blocks.length}');
      return r;
    } finally {
      await recognizer.close();
      if (await file.exists()) await file.delete();
    }
  }

  static Future<IdVerificationResult> verify({
    required Uint8List imageBytes,
    required String selectedIdType,
    bool isFront = true,
  }) async {
    print('');
    print('═══════════════════════════════════════════════════');
    print('[ID-VERIFY] Starting verify');
    print('[ID-VERIFY] ID type   : "$selectedIdType"');
    print('[ID-VERIFY] Side      : ${isFront ? "FRONT" : "BACK"}');
    print('[ID-VERIFY] Img bytes : ${imageBytes.length}');
    print('═══════════════════════════════════════════════════');

    try {
      final recognized = await _runOcr(imageBytes);

      print('');
      print('━━━━━━━━━━ RAW OCR TEXT ━━━━━━━━━━');
      if (recognized.text.isEmpty) {
        print('(EMPTY)');
      } else {
        for (final line in recognized.text.split('\n')) {
          print('| $line');
        }
      }
      print('━━━━━━━━━━ END OCR TEXT ━━━━━━━━━━');
      print('');

      print('━━━━━━━━━━ POSITIONED LINES ━━━━━━━━━━');
      for (final block in recognized.blocks) {
        for (final line in block.lines) {
          final r = line.boundingBox;
          print(
            '| "${line.text}"  @ '
            'L${r.left.toInt()},T${r.top.toInt()},'
            'W${r.width.toInt()},H${r.height.toInt()}',
          );
        }
      }
      print('━━━━━━━━━━ END POSITIONED LINES ━━━━━━━━━━');
      print('');

      final normalizedText = _normalize(recognized.text);
      final upper = recognized.text.toUpperCase();

      if (!isFront) {
        return _verifyBack(
          selectedIdType: selectedIdType,
          recognized: recognized,
          normalizedText: normalizedText,
          upper: upper,
        );
      }

      final keywords = _frontKeywords[selectedIdType] ?? [];
      print(
        '[ID-VERIFY] Checking ${keywords.length} front keywords for "$selectedIdType":',
      );
      final matched = <String>[];
      for (final k in keywords) {
        final found = normalizedText.contains(_normalize(k));
        print('[ID-VERIFY]   ${found ? "✓ MATCH" : "✗ miss "} "$k"');
        if (found) matched.add(k);
      }

      print('[ID-VERIFY] Total matched: ${matched.length}');

      var isValid = matched.isNotEmpty;
      final extractedData = _extractData(
        selectedIdType,
        recognized,
        upper,
        isFront: true,
      );

      print('[ID-VERIFY] Extracted fields: $extractedData');

      // A card whose branding did not survive the capture, but which still
      // yielded a name AND a date of birth, is almost certainly a real ID that
      // was photographed badly — glare across the header is the single most
      // common way a genuine card loses its keywords.
      //
      // This block used to read `if (!isValid && matched.isNotEmpty)`, which
      // is unreachable: `isValid` IS `matched.isNotEmpty` two lines above, so
      // the condition simplifies to `matched.isEmpty && matched.isNotEmpty`.
      // The fallback it implements had therefore never run once. The intended
      // condition is the one below.
      if (!isValid) {
        final hasName =
            (extractedData['firstName']?.isNotEmpty ?? false) ||
            (extractedData['lastName']?.isNotEmpty ?? false);
        final hasDob = extractedData['birthdate']?.isNotEmpty ?? false;
        if (hasName && hasDob) {
          isValid = true;
        }
      }

      final confidence = matched.length >= 2
          ? VerificationConfidence.high
          : matched.isNotEmpty
          ? VerificationConfidence.low
          : VerificationConfidence.none;

      print('[ID-VERIFY] FINAL: isValid=$isValid confidence=$confidence');
      print('═══════════════════════════════════════════════════');
      print('');

      return IdVerificationResult(
        isValid: isValid,
        confidence: confidence,
        matchedKeywords: matched.length,
        errorMessage: isValid
            ? null
            : "We couldn't recognize this as a $selectedIdType. "
                  "Make sure the front of the card is fully visible and "
                  "all the text is in focus.",
        extractedData: isValid ? extractedData : {},
        rawText: recognized.text,
      );
    } catch (e, st) {
      print('[ID-VERIFY] ❌ EXCEPTION: $e');
      print(st);
      return IdVerificationResult(
        isValid: false,
        confidence: VerificationConfidence.none,
        errorMessage: "We had trouble reading the photo. Please try again.",
        rawText: "",
      );
    }
  }

  static IdVerificationResult _verifyBack({
    required String selectedIdType,
    required RecognizedText recognized,
    required String normalizedText,
    required String upper,
  }) {
    final rawTrimmed = recognized.text.trim();
    if (rawTrimmed.length < 15) {
      print('[ID-VERIFY BACK] ✗ Not enough text (${rawTrimmed.length} chars)');
      return IdVerificationResult(
        isValid: false,
        confidence: VerificationConfidence.none,
        matchedKeywords: 0,
        errorMessage:
            "We can't see any text on this side. Make sure the back "
            "of the ID is in the frame and clearly visible.",
        extractedData: const {},
        rawText: recognized.text,
      );
    }

    final backKws = _backKeywords[selectedIdType] ?? [];
    print(
      '[ID-VERIFY BACK] Checking ${backKws.length} back keywords for "$selectedIdType":',
    );
    final matched = <String>[];
    for (final k in backKws) {
      final found = normalizedText.contains(_normalize(k));
      print('[ID-VERIFY BACK]   ${found ? "✓ MATCH" : "✗ miss "} "$k"');
      if (found) matched.add(k);
    }
    print('[ID-VERIFY BACK] Matched ${matched.length} back keywords');

    final backData = _extractData(
      selectedIdType,
      recognized,
      upper,
      isFront: false,
    );
    final expectedFields = _backDataFields[selectedIdType] ?? [];
    final populatedExpected = expectedFields
        .where((f) => backData[f]?.isNotEmpty ?? false)
        .toList();
    print('[ID-VERIFY BACK] Populated expected fields: $populatedExpected');

    String? dominantOtherType;
    int dominantOtherScore = 0;
    for (final entry in _backKeywords.entries) {
      if (entry.key == selectedIdType) continue;
      final otherScore = entry.value
          .where((k) => normalizedText.contains(_normalize(k)))
          .length;
      if (otherScore > dominantOtherScore) {
        dominantOtherScore = otherScore;
        dominantOtherType = entry.key;
      }
    }
    print(
      '[ID-VERIFY BACK] Best competing type: '
      '${dominantOtherType ?? "none"} (score=$dominantOtherScore)',
    );

    final selectedScore = matched.length;
    final contaminationDetected =
        dominantOtherScore > 0 && dominantOtherScore > selectedScore;

    if (contaminationDetected) {
      print(
        '[ID-VERIFY BACK] ✗ CROSS-CONTAMINATION: '
        '"$dominantOtherType" scored $dominantOtherScore vs our $selectedScore',
      );
      return IdVerificationResult(
        isValid: false,
        confidence: VerificationConfidence.none,
        matchedKeywords: 0,
        errorMessage:
            "This looks like a different type of ID. "
            "Please make sure you selected the correct ID type before scanning.",
        extractedData: const {},
        rawText: recognized.text,
      );
    }

    final isValid = matched.isNotEmpty;

    final confidence = matched.length >= 2
        ? VerificationConfidence.high
        : matched.isNotEmpty
        ? VerificationConfidence.low
        : populatedExpected.isNotEmpty
        ? VerificationConfidence.low
        : VerificationConfidence.none;

    print('[ID-VERIFY BACK] FINAL: isValid=$isValid confidence=$confidence');
    print('═══════════════════════════════════════════════════');
    print('');

    return IdVerificationResult(
      isValid: isValid,
      confidence: confidence,
      matchedKeywords: matched.length,
      errorMessage: isValid
          ? null
          : "This doesn't look like the back of a $selectedIdType. "
                "Make sure the correct ID type is selected and the back of "
                "the card is fully visible and in focus.",
      extractedData: isValid ? backData : {},
      rawText: recognized.text,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // DISPATCHER
  // ─────────────────────────────────────────────────────────────────────────

  static Map<String, String> _extractData(
    String idType,
    RecognizedText recognized,
    String upper, {
    bool isFront = true,
  }) {
    switch (idType) {
      case "PhilSys ID":
        return isFront
            ? _extractPhilSysFront(recognized, upper)
            : _extractPhilSysBack(recognized, upper);
      case "Driver's License ID":
        return _extractDriversLicense(recognized, upper);
      case "Postal ID":
        return _extractPostal(recognized, upper);
      case "Philippine Passport ID":
        return _extractPassport(recognized, upper);
      case "PhilHealth ID":
        return _extractPhilHealth(recognized, upper);
      case "PRC ID":
        return _extractPrc(recognized, upper);
      case "SSS ID":
        return _extractSss(recognized, upper);
      case "TIN ID":
        return _extractTin(recognized, upper);
      case "UMID ID":
        return _extractUmid(recognized, upper);
      default:
        return _extractGeneric(recognized, upper);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // GEOMETRY HELPERS (shared by all extractors)
  // ─────────────────────────────────────────────────────────────────────────

  static List<_PositionedLine> _positionedLines(RecognizedText r) {
    final lines = <_PositionedLine>[];
    for (final block in r.blocks) {
      for (final line in block.lines) {
        final t = line.text.trim();
        if (t.isEmpty) continue;
        lines.add(_PositionedLine(text: t, rect: line.boundingBox));
      }
    }
    return lines;
  }

  /// Closest valid line BELOW the label in same column.
  static String? _findValueBelow(
    List<_PositionedLine> lines,
    List<String> markers, {
    bool Function(String)? validator,
  }) {
    _PositionedLine? labelLine;
    for (final l in lines) {
      final up = l.text.toUpperCase();
      if (markers.any((m) => up.contains(m))) {
        labelLine = l;
        break;
      }
    }
    if (labelLine == null) return null;

    final labelLeft = labelLine.rect.left;
    final labelRight = labelLine.rect.right;
    final labelBottom = labelLine.rect.bottom;
    final labelHeight = labelLine.rect.height;

    _PositionedLine? best;
    double bestDist = double.infinity;

    for (final l in lines) {
      if (identical(l, labelLine)) continue;

      // Must be below the label
      if (l.rect.top <= labelBottom - 4) continue;

      // Skip other labels
      if (_looksLikeLabel(l.text)) continue;

      // Strict vertical gap: must be within 3x label height below
      final vGap = l.rect.top - labelBottom;
      if (vGap <= 0 || vGap > labelHeight * 3) continue;

      // Must horizontally overlap with label bounds
      final lineLeft = l.rect.left;
      final lineRight = l.rect.right;
      if (lineLeft >= labelRight || lineRight <= labelLeft) continue;

      if (validator != null && !validator(l.text)) continue;

      if (vGap < bestDist) {
        bestDist = vGap;
        best = l;
      }
    }

    print(
      '[ID-VERIFY] findValueBelow ${markers.first} → '
      '${best?.text ?? "(none)"}',
    );
    return best?.text.trim();
  }
  // ─────────────────────────────────────────────────────────────────────────
  // PER-ID EXTRACTORS — all priority-driven, blank if not confident
  // Priority order: idNumber → lastName → firstName → middleName → others
  // ─────────────────────────────────────────────────────────────────────────

  // ── PhilSys FRONT (value sits BELOW label — confirmed by OCR log) ──
  static Map<String, String> _extractPhilSysFront(
    RecognizedText recognized,
    String upper,
  ) {
    final out = <String, String>{};
    final lines = _positionedLines(recognized);

    // ID Number
    final pcn = _extractConfidentPcn(upper);
    if (pcn != null) out['idNumber'] = pcn;

    // Last Name — OCR reads label as "ApelyidofLast Name" (f instead of /)
    final last = _findValueBelow(lines, [
      'APELYIDOFLAST', // OCR merges slash as 'f': "ApelyidofLast"
      'APELYIDO/LAST',
      'APELYIDO / LAST',
      'APELYIDO',
    ], validator: _looksLikeName);
    if (last != null) out['lastName'] = last;

    // First Name — OCR reads "Mga Pangalan/Given Names"
    final given = _findValueBelow(lines, [
      'MGA PANGALAN/GIVEN',
      'PANGALAN/GIVEN',
      'MGA PANGALAN',
      'PANGALAN',
    ], validator: _looksLikeName);
    if (given != null) out['firstName'] = given;

    // Middle Name — OCR reads "Gitnang Apelyido/Middie Name" (typo: Middie)
    final middle = _findValueBelow(lines, [
      'GITNANG APELYIDO/MIDDIE', // OCR typo: "Middie" instead of "Middle"
      'GITNANG APELYIDO/MIDDLE',
      'GITNANG APELYIDO',
      'GITNANG',
    ], validator: _looksLikeName);
    if (middle != null) out['middleName'] = middle;

    // Date of Birth — OCR reads "Petsa ng Kapanganakan/Date of Birth"

    final dobRaw = _findValueBelow(lines, [
      'PETSA NG KAPANGANAKAN', // normalised (no accent)
      'PETSA NG KAPANGANÁKAN', // raw accent variant
      'KAPANGANAKAN/DATE',
      'KAPANGANÁKAN/DATE',
      'DATE OF BIRTH',
      'KAPANGANAKAN',
      'KAPANGANÁKAN',
    ]);
    if (dobRaw != null) {
      final dob = _extractConfidentDate(dobRaw);
      if (dob != null) out['birthdate'] = dob;
    }

    print('[PhilSys FRONT] Extracted: $out');
    return out;
  }

  // ── PhilSys BACK (value sits below label) ──
  static Map<String, String> _extractPhilSysBack(
    RecognizedText recognized,
    String upper,
  ) {
    final out = <String, String>{};
    final lines = _positionedLines(recognized);

    final pcn = _extractConfidentPcn(upper);
    if (pcn != null) out['idNumber'] = pcn;

    // ── Sex: scan the whole OCR text for MALE/FEMALE/LALAKI/BABAE ─────────
    // _findValueBelow fails here because the "Uri ng Dugo/Blood Type" label
    // sits between "Kasarian/Sex" and "FEMALE", and "O+" is closer, stealing
    // the slot.  Scanning the full text is safe because gender tokens are
    // unambiguous and appear exactly once on the back.
    final genderFromText = _extractGenderFromText(upper);
    if (genderFromText != null) out['gender'] = genderFromText;

    // ── Civil Status ─────────────────────────────────────────────────────
    // Scan the full text instead of using _findValueBelow — same trap as
    // gender: the "Uri ng Dugo/Blood Type" row sits between the
    // "Kalagayang Sibil/Marital Status" label and the value, so the
    // positional lookup grabs the wrong line. SINGLE/MARRIED/WIDOWED/
    // SEPARATED are unambiguous and appear exactly once on the back.
    final civil = _normalizeCivilStatus(upper);
    if (civil != null) out['civilStatus'] = civil;

    // ── Place of Birth ─────────────────────────────────────────────────────
    // Must stay positional (free-text place name, no pattern to match).
    // OCR renders "Kapanganákan" (with accent); _normalize strips diacritics
    // so the first marker will match. Extra raw-accent variants are kept as
    // fallbacks. The validator also blocks gender/civil-status tokens from
    // being mistaken for a place if the layout shifts.
    final pob = _findValueBelow(
      lines,
      [
        'LUGAR NG KAPANGANAKAN', // matched after _normalize strips accent
        'LUGAR NG KAPANGANÁKAN', // literal raw-OCR variant
        'KAPANGANÁKAN/PLACE',
        'KAPANGANAKAN/PLACE',
        'PLACE OF BIRTH',
        'KAPANGANAKAN',
        'KAPANGANÁKAN',
      ],
      validator: (s) {
        if (!_looksLikePlace(s)) return false;
        if (_normalizeGender(s) != null) return false; // not MALE/FEMALE
        if (_normalizeCivilStatus(s) != null) {
          return false; // not SINGLE/MARRIED…
        }
        return true;
      },
    );
    if (pob != null) out['birthplace'] = pob;

    print('[PhilSys BACK] Extracted: $out');
    return out;
  }

  /// Scan the full OCR text for a gender token regardless of position.
  /// Safe because MALE/FEMALE/LALAKI/BABAE are unambiguous on a PhilSys back.
  static String? _extractGenderFromText(String upper) {
    for (final word in upper.split(RegExp(r'[\s/,\n]+'))) {
      final g = _normalizeGender(word);
      if (g != null) return g;
    }
    return null;
  }

  // ── Driver's License (value sits below label) ──
  static Map<String, String> _extractDriversLicense(
    RecognizedText recognized,
    String upper,
  ) {
    final out = <String, String>{};
    final lines = _positionedLines(recognized);

    final lic = _extractConfidentDlNumber(upper);
    if (lic != null) out['idNumber'] = lic;

    final last = _findValueBelow(lines, [
      'LAST NAME',
    ], validator: _looksLikeName);
    if (last != null) out['lastName'] = last;

    final first = _findValueBelow(lines, [
      'FIRST NAME',
      'GIVEN NAME',
    ], validator: _looksLikeName);
    if (first != null) out['firstName'] = first;

    final middle = _findValueBelow(lines, [
      'MIDDLE NAME',
    ], validator: _looksLikeName);
    if (middle != null) out['middleName'] = middle;

    final dobRaw = _findValueBelow(lines, ['DATE OF BIRTH', 'BIRTHDATE']);
    if (dobRaw != null) {
      final dob = _extractConfidentDate(dobRaw);
      if (dob != null) out['birthdate'] = dob;
    }

    final sexRaw = _findValueBelow(lines, ['SEX']);
    if (sexRaw != null) {
      final g = _normalizeGender(sexRaw);
      if (g != null) out['gender'] = g;
    }

    final addr = _findValueBelow(lines, [
      'ADDRESS',
    ], validator: _looksLikeAddress);
    if (addr != null) out['street'] = addr;

    return out;
  }

  // ── Postal ID (value sits below label) ──
  static Map<String, String> _extractPostal(
    RecognizedText recognized,
    String upper,
  ) {
    final out = <String, String>{};
    final lines = _positionedLines(recognized);

    final id = _extractConfidentPostalNumber(upper);
    if (id != null) out['idNumber'] = id;

    final last = _findValueBelow(lines, [
      'SURNAME',
      'LAST NAME',
    ], validator: _looksLikeName);
    if (last != null) out['lastName'] = last;

    final first = _findValueBelow(lines, [
      'GIVEN NAME',
      'FIRST NAME',
    ], validator: _looksLikeName);
    if (first != null) out['firstName'] = first;

    final middle = _findValueBelow(lines, [
      'MIDDLE NAME',
    ], validator: _looksLikeName);
    if (middle != null) out['middleName'] = middle;

    final dobRaw = _findValueBelow(lines, ['DATE OF BIRTH', 'BIRTHDATE']);
    if (dobRaw != null) {
      final dob = _extractConfidentDate(dobRaw);
      if (dob != null) out['birthdate'] = dob;
    }

    final addr = _findValueBelow(lines, [
      'ADDRESS',
    ], validator: _looksLikeAddress);
    if (addr != null) out['street'] = addr;

    return out;
  }

  // ── Passport (value sits below label) ──
  static Map<String, String> _extractPassport(
    RecognizedText recognized,
    String upper,
  ) {
    final out = <String, String>{};
    final lines = _positionedLines(recognized);

    final pp = _extractConfidentPassportNumber(upper);
    if (pp != null) out['idNumber'] = pp;

    final last = _findValueBelow(lines, [
      'SURNAME',
      'LAST NAME',
    ], validator: _looksLikeName);
    if (last != null) out['lastName'] = last;

    final given = _findValueBelow(lines, [
      'GIVEN NAMES',
      'GIVEN NAME',
      'FIRST NAME',
    ], validator: _looksLikeName);
    if (given != null) out['firstName'] = given;

    final dobRaw = _findValueBelow(lines, ['DATE OF BIRTH', 'BIRTHDATE']);
    if (dobRaw != null) {
      final dob = _extractConfidentDate(dobRaw);
      if (dob != null) out['birthdate'] = dob;
    }

    final pob = _findValueBelow(lines, [
      'PLACE OF BIRTH',
    ], validator: _looksLikePlace);
    if (pob != null) out['birthplace'] = pob;

    final sexRaw = _findValueBelow(lines, ['SEX']);
    if (sexRaw != null) {
      final g = _normalizeGender(sexRaw);
      if (g != null) out['gender'] = g;
    }

    return out;
  }

  // ── PhilHealth (value sits below label) ──
  static Map<String, String> _extractPhilHealth(
    RecognizedText recognized,
    String upper,
  ) {
    final out = <String, String>{};
    final lines = _positionedLines(recognized);

    final pin = _extractConfidentPhilHealthPin(upper);
    if (pin != null) out['idNumber'] = pin;

    final last = _findValueBelow(lines, [
      'LAST NAME',
      'SURNAME',
    ], validator: _looksLikeName);
    if (last != null) out['lastName'] = last;

    final first = _findValueBelow(lines, [
      'FIRST NAME',
      'GIVEN NAME',
    ], validator: _looksLikeName);
    if (first != null) out['firstName'] = first;

    final middle = _findValueBelow(lines, [
      'MIDDLE NAME',
    ], validator: _looksLikeName);
    if (middle != null) out['middleName'] = middle;

    final dobRaw = _findValueBelow(lines, ['DATE OF BIRTH', 'BIRTHDATE']);
    if (dobRaw != null) {
      final dob = _extractConfidentDate(dobRaw);
      if (dob != null) out['birthdate'] = dob;
    }

    return out;
  }

  // ── PRC (value sits below label) ──
  static Map<String, String> _extractPrc(
    RecognizedText recognized,
    String upper,
  ) {
    final out = <String, String>{};
    final lines = _positionedLines(recognized);

    final prc = _extractConfidentPrcNumber(upper);
    if (prc != null) out['idNumber'] = prc;

    // PRC often prints "SURNAME, FIRSTNAME MIDDLENAME" on one line. Try both.
    final last = _findValueBelow(lines, [
      'LAST NAME',
      'SURNAME',
    ], validator: _looksLikeName);
    if (last != null) out['lastName'] = last;

    final first = _findValueBelow(lines, [
      'FIRST NAME',
      'GIVEN NAME',
    ], validator: _looksLikeName);
    if (first != null) out['firstName'] = first;

    final middle = _findValueBelow(lines, [
      'MIDDLE NAME',
    ], validator: _looksLikeName);
    if (middle != null) out['middleName'] = middle;

    final dobRaw = _findValueBelow(lines, ['DATE OF BIRTH']);
    if (dobRaw != null) {
      final dob = _extractConfidentDate(dobRaw);
      if (dob != null) out['birthdate'] = dob;
    }

    return out;
  }

  // ── SSS (value sits below label) ──
  static Map<String, String> _extractSss(
    RecognizedText recognized,
    String upper,
  ) {
    final out = <String, String>{};
    final lines = _positionedLines(recognized);

    final sss = _extractConfidentSssNumber(upper);
    if (sss != null) out['idNumber'] = sss;

    final last = _findValueBelow(lines, [
      'LAST NAME',
      'SURNAME',
    ], validator: _looksLikeName);
    if (last != null) out['lastName'] = last;

    final first = _findValueBelow(lines, [
      'FIRST NAME',
      'GIVEN NAME',
    ], validator: _looksLikeName);
    if (first != null) out['firstName'] = first;

    final middle = _findValueBelow(lines, [
      'MIDDLE NAME',
    ], validator: _looksLikeName);
    if (middle != null) out['middleName'] = middle;

    final dobRaw = _findValueBelow(lines, ['DATE OF BIRTH', 'BIRTHDATE']);
    if (dobRaw != null) {
      final dob = _extractConfidentDate(dobRaw);
      if (dob != null) out['birthdate'] = dob;
    }

    return out;
  }

  // ── TIN ──
  static Map<String, String> _extractTin(
    RecognizedText recognized,
    String upper,
  ) {
    final out = <String, String>{};
    final lines = _positionedLines(recognized);

    final tin = _extractConfidentTin(upper);
    if (tin != null) out['idNumber'] = tin;

    final last = _findValueBelow(lines, [
      'LAST NAME',
      'SURNAME',
    ], validator: _looksLikeName);
    if (last != null) out['lastName'] = last;

    final first = _findValueBelow(lines, [
      'FIRST NAME',
      'GIVEN NAME',
    ], validator: _looksLikeName);
    if (first != null) out['firstName'] = first;

    final middle = _findValueBelow(lines, [
      'MIDDLE NAME',
    ], validator: _looksLikeName);
    if (middle != null) out['middleName'] = middle;

    return out;
  }

  // ── UMID (value sits below label) ──
  static Map<String, String> _extractUmid(
    RecognizedText recognized,
    String upper,
  ) {
    final out = <String, String>{};
    final lines = _positionedLines(recognized);

    final crn = _extractConfidentSssNumber(upper);
    if (crn != null) out['idNumber'] = crn;

    final last = _findValueBelow(lines, [
      'LAST NAME',
      'SURNAME',
    ], validator: _looksLikeName);
    if (last != null) out['lastName'] = last;

    final first = _findValueBelow(lines, [
      'FIRST NAME',
      'GIVEN NAME',
    ], validator: _looksLikeName);
    if (first != null) out['firstName'] = first;

    final middle = _findValueBelow(lines, [
      'MIDDLE NAME',
    ], validator: _looksLikeName);
    if (middle != null) out['middleName'] = middle;

    final dobRaw = _findValueBelow(lines, ['DATE OF BIRTH', 'BIRTHDATE']);
    if (dobRaw != null) {
      final dob = _extractConfidentDate(dobRaw);
      if (dob != null) out['birthdate'] = dob;
    }

    final sexRaw = _findValueBelow(lines, ['SEX']);
    if (sexRaw != null) {
      final g = _normalizeGender(sexRaw);
      if (g != null) out['gender'] = g;
    }

    return out;
  }

  // ── Generic fallback ──
  static Map<String, String> _extractGeneric(
    RecognizedText recognized,
    String upper,
  ) {
    final out = <String, String>{};

    final dobMatch = RegExp(
      r'\b(\d{1,2}[/-]\d{1,2}[/-]\d{2,4})\b',
    ).firstMatch(upper);
    if (dobMatch != null) {
      final dob = _extractConfidentDate(dobMatch.group(0)!);
      if (dob != null) out['birthdate'] = dob;
    }

    final phone = RegExp(r'\b(09\d{9}|\+639\d{9})\b').firstMatch(upper);
    if (phone != null) out['contactNumber'] = phone.group(0)!;

    return out;
  }

  static String _normalizeDate(String raw) {
    final months = {
      'JANUARY': 1,
      'JAN': 1,
      'FEBRUARY': 2,
      'FEB': 2,
      'MARCH': 3,
      'MAR': 3,
      'APRIL': 4,
      'APR': 4,
      'MAY': 5,
      'JUNE': 6,
      'JUN': 6,
      'JULY': 7,
      'JUL': 7,
      'AUGUST': 8,
      'AUG': 8,
      'SEPTEMBER': 9,
      'SEP': 9,
      'SEPT': 9,
      'OCTOBER': 10,
      'OCT': 10,
      'NOVEMBER': 11,
      'NOV': 11,
      'DECEMBER': 12,
      'DEC': 12,
    };
    final up = raw.toUpperCase();
    for (final entry in months.entries) {
      if (up.contains(entry.key)) {
        final full = RegExp(r'(\d{1,2})[^\d]+(\d{4})').firstMatch(up);
        if (full != null) {
          return "${entry.value}/${full.group(1)}/${full.group(2)}";
        }
        final partial = RegExp(r'(\d{1,2})').firstMatch(up);
        if (partial != null) {
          return "${entry.value}/${partial.group(1)}/";
        }
      }
    }
    // Try pure numeric (e.g. 12/25/1990)
    final numeric = RegExp(
      r'(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})',
    ).firstMatch(up);
    if (numeric != null) {
      var year = numeric.group(3)!;
      if (year.length == 2) year = '19$year';
      return '${int.parse(numeric.group(1)!)}/${int.parse(numeric.group(2)!)}/$year';
    }
    return raw;
  }
}

class _PositionedLine {
  final String text;
  final Rect rect;
  _PositionedLine({required this.text, required this.rect});
}
