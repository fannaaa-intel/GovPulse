import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/features/admin/utils/admin_pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// The standard-14 PDF fonts the admin documents use cover exactly U+0000-U+00FF.
/// Anything above that renders as a blank "tofu" box on the printed page, so the
/// contract [pdfSafe] has to keep is simply: nothing above 0xFF ever escapes it.
///
/// This matters most for section 4 of the findings report, which prints
/// free-form text written by the AI model — a hand-maintained denylist of
/// "glyphs we happened to hit" cannot stay correct against that.
void main() {
  /// Every rune the standard-14 fonts can actually draw.
  bool renderable(String s) => s.runes.every((r) => r <= 0xFF);

  group('pdfSafe keeps text inside the font', () {
    test('the exact glyphs that tofu-boxed a filed report', () {
      // Verbatim from GovPulse-Findings-30d-20260906.pdf, page 3, where the AI
      // recommendations printed U+2011 (non-breaking hyphen) as blank boxes.
      const fromTheAi =
          'High‑urgency reports have jumped to 2 this month. '
          'Improve public‑service feedback handling, hold a '
          'courtesy‑training session and circulate a '
          'service‑standard reminder.';

      final safe = pdfSafe(fromTheAi);

      expect(renderable(safe), isTrue);
      expect(safe, contains('High-urgency'));
      expect(safe, contains('public-service'));
      expect(safe, contains('courtesy-training'));
      expect(safe, contains('service-standard'));
      expect(safe, isNot(contains('?')));
    });

    test('maps the dash family to a hyphen', () {
      expect(pdfSafe('a–b'), 'a-b'); // en dash
      expect(pdfSafe('a—b'), 'a-b'); // em dash
      expect(pdfSafe('a‐b'), 'a-b'); // hyphen
      expect(pdfSafe('a‑b'), 'a-b'); // non-breaking hyphen
      expect(pdfSafe('a−b'), 'a-b'); // minus
    });

    test('maps quotes, ellipses and symbols to their meaning', () {
      expect(pdfSafe('“quoted”'), '"quoted"');
      expect(pdfSafe('it’s'), "it's");
      expect(pdfSafe('wait…'), 'wait...');
      expect(pdfSafe('4★'), '4 / 5');
      expect(pdfSafe('a→b'), 'a->b');
      expect(pdfSafe('≥ 3'), '>= 3');
      expect(pdfSafe('₱500'), 'PHP 500');
    });

    test('collapses non-breaking and zero-width whitespace', () {
      expect(pdfSafe('a b'), 'a b');
      expect(pdfSafe('a​b'), 'ab');
      expect(pdfSafe('﻿leading bom'), 'leading bom');
    });

    test('keeps Latin-1 accents, which the font does have', () {
      // Spanish-derived place and office names are common in Cagayan.
      expect(pdfSafe('Peñablanca'), 'Peñablanca');
      expect(pdfSafe('Señor'), 'Señor');
      expect(renderable(pdfSafe('Peñablanca')), isTrue);
    });

    test('drops combining marks instead of corrupting the word', () {
      // "é" as e + U+0301 rather than the precomposed Latin-1 character.
      expect(pdfSafe('café'), 'cafe');
    });

    test('backstop: unmapped glyphs never reach the page', () {
      // Nothing here is in the map. The point of the test is that the output is
      // still printable — an allowlist does not need to have predicted these.
      const unpredicted = 'emoji 🚧 CJK 道 Cyrillic Ж Greek Δ dingbat ✔ box ░';
      final safe = pdfSafe(unpredicted);

      expect(renderable(safe), isTrue);
      // Dropped characters are visible as "?" so a proofreader can see that
      // something was substituted, rather than the text silently changing.
      expect(safe, contains('?'));
      expect(safe, startsWith('emoji '));
    });

    test('leaves pure ASCII untouched', () {
      const plain = 'Resolution rate stands at 33%; 2 reports remain open.';
      expect(pdfSafe(plain), same(plain));
    });

    test('handles the empty string', () {
      expect(pdfSafe(''), '');
    });
  });

  test('the font really is limited to Latin-1', () {
    // Guards the assumption the whole allowlist rests on. If a future change
    // bundles a Unicode TTF, this fails and pdfSafe can be relaxed.
    final helvetica = pw.Font.helvetica().getFont(_ctx());
    expect(helvetica.isRuneSupported(0x00FF), isTrue);
    expect(helvetica.isRuneSupported(0x2011), isFalse);
  });
}

/// A throwaway context, just to materialise the PdfFont behind the widget font.
pw.Context _ctx() {
  final doc = pw.Document();
  final page = pw.Page(build: (c) => pw.Container());
  doc.addPage(page);
  return pw.Context(document: doc.document);
}
