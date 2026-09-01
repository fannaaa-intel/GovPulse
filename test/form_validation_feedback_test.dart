// test/form_validation_feedback_test.dart
//
// ════════════════════════════════════════════════════════════════════════════
//  A primary button that refuses must SAY it refused.
//
//  ── The defect ──────────────────────────────────────────────────────────
//  Reported from the Citizen Management console: messaging a citizen without a
//  title did nothing. Not an error, not a highlight, not a closed dialog — the
//  Send button simply had no effect. The code was
//
//      if (t.isEmpty || b.isEmpty) return;   // ← admin_user_actions.dart
//
//  A bare `return` inside `onPressed`. From the admin's side of the screen a
//  validation refusal, a dead button and a dropped network are indistinguishable
//  — all three look like "nothing happened" — so the reasonable conclusion is
//  that the feature is broken, and the message never gets sent.
//
//  The same shape was in three more places, all of them a button someone
//  presses after typing:
//    • the admin reply composer   (admin_submission_ui.dart)
//    • the "Return this update" reason dialog (report_progress_updates.dart)
//    • the progress-update composer          (report_progress_updates.dart)
//
//  ── The rule ────────────────────────────────────────────────────────────
//  Refusing is fine. Refusing SILENTLY is not. Every one of these now names the
//  field that is wrong, in place, and clears the complaint as soon as the admin
//  starts fixing it.
//
//  ── Why the button is not simply disabled instead ───────────────────────
//  A greyed-out button says "not yet" without saying what is missing. On a
//  two-field form with one field filled, that reads as the button being broken
//  — the same wrong conclusion, reached a different way. So the button stays
//  live and answers when pressed.
// ════════════════════════════════════════════════════════════════════════════

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';


// ── A faithful stand-in for the fixed forms ─────────────────────────────────
//
// The real forms are private (`_MessageForm`, `_ReplyComposer`) and each needs
// a live Supabase client and an authenticated admin session to reach — the same
// wall completion_media_picker_test.dart documents. What CAN be pinned without
// them is the behaviour every one of them was changed to have, expressed as the
// same widget shape: two required fields, one always-enabled primary button,
// per-field errors set on press and cleared on edit.
//
// This is the contract the four real call sites now implement. A source guard
// (upload_compression_guard_test.dart does the same job for compression) would
// be the belt to this braces, but the behaviour itself is what the reported bug
// was about, so it is what is tested here.
class _TwoFieldForm extends StatefulWidget {
  final void Function(String title, String body)? onAccepted;
  const _TwoFieldForm({this.onAccepted});

  @override
  State<_TwoFieldForm> createState() => _TwoFieldFormState();
}

class _TwoFieldFormState extends State<_TwoFieldForm> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  String? _titleError;
  String? _bodyError;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  void _submit() {
    final t = _title.text.trim();
    final b = _body.text.trim();
    setState(() {
      _titleError = t.isEmpty ? 'Add a short headline.' : null;
      _bodyError = b.isEmpty ? 'Write the message to send.' : null;
    });
    if (_titleError != null || _bodyError != null) return;
    widget.onAccepted?.call(t, b);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            TextField(
              key: const Key('title'),
              controller: _title,
              decoration: InputDecoration(errorText: _titleError),
              onChanged: (v) {
                if (_titleError != null && v.trim().isNotEmpty) {
                  setState(() => _titleError = null);
                }
              },
            ),
            TextField(
              key: const Key('body'),
              controller: _body,
              decoration: InputDecoration(errorText: _bodyError),
              onChanged: (v) {
                if (_bodyError != null && v.trim().isNotEmpty) {
                  setState(() => _bodyError = null);
                }
              },
            ),
            FilledButton(onPressed: _submit, child: const Text('Send')),
          ],
        ),
      ),
    );
  }
}

void main() {
  group('pressing Send on an incomplete form', () {
    testWidgets('says which field is missing instead of nothing', (t) async {
      var accepted = 0;
      await t.pumpWidget(_TwoFieldForm(onAccepted: (_, _) => accepted++));

      // Exactly the reported case: a body typed, no title.
      await t.enterText(find.byKey(const Key('body')), 'Please come in.');
      await t.tap(find.text('Send'));
      await t.pump();

      // The bug: this used to be the entire outcome — nothing on screen.
      expect(accepted, 0, reason: 'An untitled message must not be sent.');
      expect(
        find.text('Add a short headline.'),
        findsOneWidget,
        reason: 'The refusal must be visible, not silent.',
      );
      // And it must name the field that is actually wrong, not both.
      expect(find.text('Write the message to send.'), findsNothing);
    });

    testWidgets('names BOTH fields when both are empty', (t) async {
      await t.pumpWidget(const _TwoFieldForm());

      await t.tap(find.text('Send'));
      await t.pump();

      expect(find.text('Add a short headline.'), findsOneWidget);
      expect(find.text('Write the message to send.'), findsOneWidget);
    });

    testWidgets('whitespace is not a title', (t) async {
      var accepted = 0;
      await t.pumpWidget(_TwoFieldForm(onAccepted: (_, _) => accepted++));

      await t.enterText(find.byKey(const Key('title')), '    ');
      await t.enterText(find.byKey(const Key('body')), 'Body text.');
      await t.tap(find.text('Send'));
      await t.pump();

      expect(accepted, 0);
      expect(find.text('Add a short headline.'), findsOneWidget);
    });
  });

  group('the complaint gets out of the way', () {
    testWidgets('clears as soon as the admin starts typing', (t) async {
      await t.pumpWidget(const _TwoFieldForm());

      await t.tap(find.text('Send'));
      await t.pump();
      expect(find.text('Add a short headline.'), findsOneWidget);

      // Fixing the field must retract the complaint immediately — not on the
      // next press. A message contradicting a field that is now filled in is
      // its own small lie.
      await t.enterText(find.byKey(const Key('title')), 'Office visit');
      await t.pump();

      expect(find.text('Add a short headline.'), findsNothing);
      // The OTHER field's complaint stays: it is still true.
      expect(find.text('Write the message to send.'), findsOneWidget);
    });

    testWidgets('a completed form submits and shows no errors', (t) async {
      String? gotTitle;
      String? gotBody;
      await t.pumpWidget(
        _TwoFieldForm(
          onAccepted: (a, b) {
            gotTitle = a;
            gotBody = b;
          },
        ),
      );

      await t.enterText(find.byKey(const Key('title')), '  Office visit  ');
      await t.enterText(find.byKey(const Key('body')), '  Please come in.  ');
      await t.tap(find.text('Send'));
      await t.pump();

      // Trimmed on the way out — a title of spaces was already refused above,
      // so the accepted value must not carry them either.
      expect(gotTitle, 'Office visit');
      expect(gotBody, 'Please come in.');
      expect(find.text('Add a short headline.'), findsNothing);
      expect(find.text('Write the message to send.'), findsNothing);
    });
  });

  testWidgets('the button stays pressable while the form is incomplete', (
    t,
  ) async {
    await t.pumpWidget(const _TwoFieldForm());

    // Deliberately NOT disabled. A dead-looking button is the same wrong
    // signal the bare `return` gave; the button must be pressable so that
    // pressing it can produce the explanation.
    final button = t.widget<FilledButton>(find.byType(FilledButton));
    expect(
      button.onPressed,
      isNotNull,
      reason: 'A disabled button cannot tell the admin what is missing.',
    );
  });


  // ── The real files, not the stand-in ──────────────────────────────────────
  //
  // Everything above pins the BEHAVIOUR, but it pins it on a local widget —
  // which proves the contract is coherent, not that the four reported call
  // sites implement it. These read the shipped source instead, so that
  // reintroducing the bare `return` fails here even though the stand-in above
  // would still be perfectly green.
  group('the shipped call sites', () {
    const fixed = <String, List<String>>{
      // path : the error-state field(s) it must carry
      'lib/features/admin/widgets/admin_user_actions.dart': [
        '_titleError',
        '_bodyError',
      ],
      'lib/features/admin/widgets/admin_submission_ui.dart': ['_replyError'],
      'lib/core/widgets/report_progress_updates.dart': ['_composerError'],
    };

    test('each still carries its error state and renders it', () {
      for (final entry in fixed.entries) {
        final src = File(entry.key).readAsStringSync();
        for (final field in entry.value) {
          expect(
            src.contains(field),
            isTrue,
            reason: '${entry.key} lost $field — the field that carries the '
                'refusal. Without it the button fails silently again.',
          );
        }
        expect(
          src.contains('errorText:'),
          isTrue,
          reason: '${entry.key} no longer renders an errorText, so whatever '
              'it computes never reaches the screen.',
        );
      }
    });

    test('no submit handler bails on empty typed text without saying so', () {
      // ── Why this does NOT look for `.text` on the guard line ─────────────
      // The first version of this rule did, and it was worthless: the reported
      // bug read `if (t.isEmpty || b.isEmpty) return;` against locals that had
      // been pulled out of `.text` four lines earlier, so the pattern could
      // never match the very defect it was written for. It was only caught by
      // putting the bug back and watching this test stay green.
      //
      // So: match ANY emptiness-guarded bare return, then require that the
      // enclosing method reads a controller — which is what makes the value
      // something a person typed rather than a picker result or a route id.
      final bail = RegExp(r'if\s*\([^)]*isEmpty[^)]*\)\s*\{?\s*return;');
      final tells = RegExp(
        r'_error|errorText|setState|SnackBar|showAppSnackBar'
        r'|showAdminSnackBar|_toast|showFriendly|_touched|_valid',
      );

      // Send-on-empty in a MESSAGE composer is the universal chat idiom: an
      // empty send box doing nothing is understood everywhere, and an error
      // for it would be noise on every stray Enter key. These are threads,
      // not forms — there is no field to go back and fix.
      const chatComposers = <String>{
        'lib/features/staff/pages/staff_conversations_page.dart',
        'lib/features/admin/pages/community_updates_page.dart',
        'lib/core/widgets/Home/Chat-bubbles/chat_panel_card.dart',
        'lib/features/home/Quick-action/Chat-with-Agent/chat_agent_screen.dart',
        'lib/core/services/chat_service.dart',
        'lib/core/widgets/Home/Newsfeed/comments_sheet.dart',
      };

      final offenders = <String>[];
      var scanned = 0;
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        scanned++;
        final path = f.path.replaceAll(r'\', '/');
        final rel = path.substring(path.indexOf('lib/'));
        if (chatComposers.contains(rel)) continue;

        final lines = f.readAsStringSync().split('\n');
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (line.trimLeft().startsWith('//')) continue; // a comment about it
          if (!bail.hasMatch(line)) continue;
          // Only user-TYPED values: the enclosing method must read a
          // controller. Without this the rule fires on picker results and
          // deep-link ids, where a silent return is exactly right.
          final back = lines.sublist((i - 20).clamp(0, lines.length), i + 1);
          if (!back.join('\n').contains('.text')) continue;

          final lo = (i - 4).clamp(0, lines.length);
          final hi = (i + 5).clamp(0, lines.length);
          if (tells.hasMatch(lines.sublist(lo, hi).join('\n'))) continue;

          // The OTHER honest answer to an incomplete form: a button that is
          // visibly disabled until it can be pressed. Then the bare return is
          // unreachable belt-and-braces, not a silent refusal — the greying is
          // the feedback. endorse_entity_dialog does exactly this.
          //
          // What is NOT acceptable is neither: a live button that swallows the
          // press. So the rule accepts either affordance and rejects the gap.
          final whole = lines.join('\n');
          final guarded = RegExp(
            r'onPressed:\s*_can\w+\s*\?|onPressed:\s*\w*[Cc]anSubmit',
          ).hasMatch(whole);
          if (guarded) continue;

          offenders.add('$rel:${i + 1}');
        }
      }

      // A scan that walked nothing would make this rule vacuous.
      expect(scanned, greaterThan(100), reason: 'lib/ was not scanned.');
      expect(
        offenders,
        isEmpty,
        reason: 'These refuse a press without telling anyone:\n'
            '  ${offenders.join('\n  ')}\n\n'
            'Set an error field and render it as errorText on the offending '
            'input, the way _MessageForm now does.',
      );
    });
  });
}
