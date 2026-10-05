// Pins the offline assistant's language detection.
//
// Detection used to be a substring check, so ordinary Tagalog came back in
// the wrong language: "Saan po…" and "ano nga po…" matched the Ilocano
// markers 'saan' and 'nga ', and "ayaw ko…" matched the Ybanag marker 'yaw '
// inside 'ayaw'. These cases are the regressions to keep out.

import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/core/services/local_assistant.dart';

void main() {
  String lang(String m) => LocalAssistant.detectedLanguageName(m);

  group('Tagalog stays Tagalog', () {
    for (final m in [
      'Saan po kukuha ng cedula?',
      'ano nga po ang requirements?',
      'ayaw ko na po maghintay',
      'Magkano po ang barangay clearance?',
      'taga Aparri po ako', // 'ari' must not fire inside Aparri
      'paano mag-apply ng senior citizen id',
    ]) {
      test(m, () => expect(lang(m), 'tagalog'));
    }
  });

  group('Ilocano is recognised', () {
    for (final m in [
      'Ania ti requirements para iti barangay clearance?',
      'Sadino ti ayan ti Municipal Hall?',
      'Mano daytoy?',
      'Kasano ti agala iti cedula?',
      'Agyamanak unay',
      'Saan ko a maawatan', // Ilocano 'saan' still detected via its partners
    ]) {
      test(m, () => expect(lang(m), 'ilocano'));
    }
  });

  group('Ybanag is recognised', () {
    for (final m in [
      'Kunnasi ka?',
      'Piga i cedula?',
      'Sitaw i municipal hall?',
      "Mabbalo'",
      'Mapia nga umma',
      'Anni i mawag para ta business permit?',
    ]) {
      test(m, () => expect(lang(m), 'ybanag'));
    }
  });

  group('English is recognised', () {
    for (final m in [
      'How do I renew my business permit?',
      'Where is the municipal hall?',
      'I need a barangay clearance please',
    ]) {
      test(m, () => expect(lang(m), 'english'));
    }
  });

  test('a Ybanag question still gets an Ilocano answer offline', () {
    // The AI's safe rule: never fabricate Ybanag. The offline brain has no
    // Ybanag variants, so Ybanag must land on the Ilocano text.
    final ybanag = LocalAssistant.reply('Kunnasi ka? Piga i cedula?');
    final ilocano = LocalAssistant.reply('Kasano ti cedula? Mano ti bayad?');
    expect(ybanag, ilocano);
  });
}
