import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/core/services/faq_catalog.dart';

/// Kuya Gov's ready-made answers (panel revision, 2026-10-12). The catalog is
/// the one place an answer is guaranteed to be the same every time, so these
/// pin the rules it was written under.
void main() {
  test('ids are unique', () {
    final ids = kFaqs.map((f) => f.id).toList();
    expect(ids.toSet().length, ids.length);
  });

  test('every featured chip exists', () {
    expect(featuredFaqs.length, kFeaturedFaqIds.length);
  });

  test('every topic has at least one question', () {
    for (final t in FaqTopic.values) {
      expect(kFaqs.where((f) => f.topic == t), isNotEmpty, reason: t.label);
    }
  });

  group('with NO facts (offline, or a row not yet verified)', () {
    for (final faq in kFaqs) {
      test(faq.id, () {
        final a = faq.answer(const {});
        expect(a.trim(), isNotEmpty);
        // An absent fact must never surface as a hole in the sentence.
        expect(a, isNot(contains('null')));
        expect(a, isNot(contains(': \n')));
        // No invented money: a peso amount may only come from a verified fact.
        expect(a, isNot(contains('₱')));
        expect(RegExp(r'\bP\d').hasMatch(a), isFalse);
      });
    }
  });

  test('a verified fact is used verbatim when present', () {
    final mayor = kFaqs.firstWhere((f) => f.id == 'mayor');
    expect(mayor.factKeys, contains('mayor'));
    expect(mayor.answer(const {'mayor': 'Juan Dela Cruz'}),
        contains('Juan Dela Cruz'));
  });

  test('only the facts an answer names are requested', () {
    final report = kFaqs.firstWhere((f) => f.id == 'how_to_report');
    expect(report.factKeys, isEmpty,
        reason: 'a fact-free answer must never wait on a network fetch');
  });

  test('no answer offers to connect the citizen to a person', () {
    for (final faq in kFaqs) {
      final a = faq.answer(const {}).toLowerCase();
      for (final promise in ['ikonekta', 'connect you', 'live agent']) {
        expect(a, isNot(contains(promise)), reason: faq.id);
      }
    }
  });
}
