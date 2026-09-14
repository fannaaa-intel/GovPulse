import 'package:flutter/material.dart';

import '../landing_page.dart'
    show LandingBand, LandingEyebrow, LandingHeading, LandingSubhead;
import '../landing_theme.dart';
import '../widgets/reveal_on_scroll.dart';

/// The five most-asked questions.
///
/// ── Why the answers are conservative ───────────────────────────────────────
/// These are commitments made on a government platform's front page, so each
/// answer says only what the product actually does today. Two in particular are
/// written narrowly on purpose:
///
///   • "Is my personal information safe" describes the mechanisms that exist
///     (identity verification, restricted staff access, encrypted transport)
///     without promising an outcome no system can guarantee.
///   • "Which agencies or LGUs are covered" names Aparri alone, because that is
///     the only municipality deployed. Implying a wider rollout would be the
///     kind of claim a neighbouring LGU could read as a false statement.
class LandingFaq extends StatefulWidget {
  const LandingFaq({super.key});

  @override
  State<LandingFaq> createState() => _LandingFaqState();
}

class _LandingFaqState extends State<LandingFaq> {
  /// Which item is open. The design shows the first one expanded on arrival,
  /// which also demonstrates that the rows are interactive at all — a column of
  /// closed rows reads as a static list.
  int? _open = 0;

  static const List<({String q, String a})> _faqs = [
    (
      q: 'Is GovPulse free to use?',
      a:
          'Yes. GovPulse is completely free for all citizens. There are no '
          'subscription fees and no charges for submitting reports or '
          'tracking their status.',
    ),
    (
      q: 'How do I submit a report or concern?',
      a:
          'Create an account, verify your identity, then choose Report Issue '
          'from the quick actions. You can describe the problem, attach '
          'photos, and pin the location so the right office can find it.',
    ),
    (
      q: 'How will I know my report is being acted on?',
      a:
          'Every report gets a reference number you can follow. Its status '
          'moves from received to in progress to resolved, and you are '
          'notified when it changes or when staff add an update.',
    ),
    (
      q: 'Is my personal information safe?',
      a:
          'Your account is protected by identity verification, and access to '
          'your details is restricted to authorised LGU staff who need it to '
          'act on your report. Information is sent over an encrypted '
          'connection. You can also submit a report anonymously, which hides '
          'your name from the public feed.',
    ),
    (
      q: "Which agencies or LGUs are covered?",
      a:
          'GovPulse currently serves the Municipality of Aparri, Cagayan, and '
          'the municipal offices that handle citizen reports. Reports that '
          'need another agency can be endorsed to them by LGU staff.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < LandingUi.mobileBreak;

    return LandingBand(
      background: LandingUi.surface,
      padding: EdgeInsets.symmetric(
        vertical: narrow ? 64 : 88,
        horizontal: LandingUi.gutter,
      ),
      // Narrower than the page band: a line of body text past about 70
      // characters is measurably harder to read, and an FAQ is the one section
      // people actually read rather than scan.
      maxWidth: 820,
      child: Column(
        children: [
          const RevealOnScroll(child: LandingEyebrow('FAQ')),
          const SizedBox(height: 18),
          const RevealOnScroll(
            delay: Duration(milliseconds: 60),
            child: LandingHeading(
              lead: "Need Help? We've Got ",
              highlight: 'Answers',
            ),
          ),
          const SizedBox(height: 16),
          const RevealOnScroll(
            delay: Duration(milliseconds: 110),
            child: LandingSubhead(
              'Everything you need to know about using GovPulse with '
              'confidence.',
            ),
          ),
          SizedBox(height: narrow ? 34 : 44),
          for (final (index, faq) in _faqs.indexed) ...[
            RevealOnScroll(
              delay: Duration(milliseconds: 50 * index),
              child: _FaqRow(
                question: faq.q,
                answer: faq.a,
                expanded: _open == index,
                // Tapping the open row closes it, so there is always a way back
                // to the compact list.
                onTap: () =>
                    setState(() => _open = _open == index ? null : index),
              ),
            ),
            if (index != _faqs.length - 1) const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _FaqRow extends StatelessWidget {
  final String question;
  final String answer;
  final bool expanded;
  final VoidCallback onTap;

  const _FaqRow({
    required this.question,
    required this.answer,
    required this.expanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      // Announces open/closed state, which the +/- glyph conveys visually and
      // a screen reader otherwise could not.
      expanded: expanded,
      child: Material(
        color: expanded ? const Color(0xFFF6F9FE) : LandingUi.surface,
        borderRadius: BorderRadius.circular(LandingUi.cardRadius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(LandingUi.cardRadius),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(LandingUi.cardRadius),
              border: Border.all(
                color: expanded
                    ? const Color(0xFFD8E4F5)
                    : const Color(0xFFE8ECF2),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        question,
                        style: const TextStyle(
                          fontSize: 15.5,
                          height: 1.4,
                          fontWeight: FontWeight.w700,
                          color: LandingUi.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Rotates 45 degrees, turning the + into an x. Cheaper and
                    // calmer than swapping two icons, and it reads as the same
                    // control changing state rather than a different control.
                    AnimatedRotation(
                      turns: expanded ? 0.125 : 0,
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOut,
                      child: Icon(
                        Icons.add_rounded,
                        size: 22,
                        color: expanded
                            ? LandingUi.textPrimary
                            : LandingUi.textMuted,
                      ),
                    ),
                  ],
                ),
                // AnimatedSize over a conditional child: the row grows and
                // shrinks smoothly instead of snapping, which at five rows in a
                // column is the difference between a polished accordion and the
                // page jumping under the reader's cursor.
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  alignment: Alignment.topCenter,
                  child: expanded
                      ? Padding(
                          padding: const EdgeInsets.only(top: 12, right: 38),
                          child: Text(
                            answer,
                            style: const TextStyle(
                              fontSize: 14.5,
                              height: 1.65,
                              color: LandingUi.textBody,
                            ),
                          ),
                        )
                      : const SizedBox(width: double.infinity),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
