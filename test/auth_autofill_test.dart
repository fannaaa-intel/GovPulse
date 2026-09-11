// Can a password manager fill and SAVE a GovPulse credential?
//
// It could not. WebInputField had no autofillHints parameter at all, so the
// five auth screens built on it were opaque to 1Password, Chrome and Safari —
// and the half that is easier to miss is SAVE, not fill: an account created
// on the signup screen left no stored credential anywhere, which is a direct
// line to the password-reset queue.
//
// Two things are pinned here, because autofill needs both and either one alone
// is silently useless:
//
//   1. The field carries a hint. Without it the browser has no idea what the
//      box is for.
//   2. The fields sit inside an AutofillGroup. A manager saves a CREDENTIAL —
//      username AND password together — so it needs to know which fields form
//      one form; on web Flutter only emits the surrounding <form> element for
//      fields inside a group. Hints without a group offer to fill but
//      frequently never offer to save.
//
// The screens themselves need Supabase and Firebase to build, so these test
// the two shared pieces every one of them is assembled from, plus the hint
// vocabulary the call sites use.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:govpulse/core/widgets/web/web_input_field.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(home: Scaffold(body: child)),
  );
}

void main() {
  group('WebInputField', () {
    testWidgets('passes autofillHints through to the TextField', (tester) async {
      await _pump(
        tester,
        WebInputField(
          hint: 'Username',
          icon: Icons.person,
          autofillHints: const [AutofillHints.username],
          onChanged: (_) {},
        ),
      );

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.autofillHints, contains(AutofillHints.username));
    });

    testWidgets('a password field can carry newPassword', (tester) async {
      // newPassword, not password, is what makes a manager offer to GENERATE
      // and save rather than re-fill an existing credential into a form that
      // is creating a new account.
      await _pump(
        tester,
        WebInputField(
          hint: 'Password',
          icon: Icons.lock,
          obscure: true,
          autofillHints: const [AutofillHints.newPassword],
          onChanged: (_) {},
        ),
      );

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.autofillHints, contains(AutofillHints.newPassword));
      expect(field.obscureText, isTrue);
    });

    testWidgets('stays null when not a credential box', (tester) async {
      // A search box or a free-text note must NOT claim to be a credential.
      await _pump(
        tester,
        WebInputField(hint: 'Search', icon: Icons.search, onChanged: (_) {}),
      );

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.autofillHints, isNull);
    });
  });

  group('AutofillGroup', () {
    testWidgets('groups a username and password into one credential',
        (tester) async {
      // The shape every auth screen now mounts: both boxes under one group, so
      // the manager is offered a credential rather than two unrelated strings.
      await _pump(
        tester,
        AutofillGroup(
          onDisposeAction: AutofillContextAction.commit,
          child: Column(
            children: [
              WebInputField(
                hint: 'Username',
                icon: Icons.person,
                autofillHints: const [AutofillHints.username],
                onChanged: (_) {},
              ),
              WebInputField(
                hint: 'Password',
                icon: Icons.lock,
                obscure: true,
                autofillHints: const [AutofillHints.password],
                onChanged: (_) {},
              ),
            ],
          ),
        ),
      );

      expect(find.byType(AutofillGroup), findsOneWidget);

      final fields = tester.widgetList<TextField>(find.byType(TextField));
      expect(fields.length, 2);
      expect(
        fields.every((f) => f.autofillHints?.isNotEmpty ?? false),
        isTrue,
        reason: 'every field in the group must declare what it holds',
      );

      // commit, not cancel: these screens are torn down BY a successful submit
      // navigating away, which is exactly when the credential is worth saving.
      final group = tester.widget<AutofillGroup>(find.byType(AutofillGroup));
      expect(group.onDisposeAction, AutofillContextAction.commit);
    });
  });
}
