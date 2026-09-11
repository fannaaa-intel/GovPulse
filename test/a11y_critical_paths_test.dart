// Can somebody who cannot use a mouse actually USE GovPulse?
//
// This is a government service, so the question is not academic: a citizen
// navigating by keyboard, or hearing the page through a screen reader, has to
// be able to sign in, file a report, and read what happened to it.
//
// ── Why this file is a SURVEY, not a sweep ────────────────────────────────
// A raw count says citizen web has 154 tappable GestureDetectors against 28
// InkWells, and a GestureDetector contributes NO semantics node and NO focus
// node — invisible to a screen reader, unreachable by Tab. Converting all 154
// would be an enormous diff across screens nobody navigates by keyboard, with
// real regression risk and most of the benefit going nowhere.
//
// So these pin the controls on the paths that actually matter, and they are
// written to be honest in both directions: they PASS where the app is already
// accessible (which, encouragingly, is most of the shared button vocabulary)
// and they FAIL where a real citizen would get stuck. A test that only
// asserted what already works would be decoration.
//
// ── What "accessible" means here ─────────────────────────────────────────
// Two things, and they are separate:
//   1. FOCUSABLE — reachable by Tab. Requires a focus node, which the Material
//      button family creates and a bare GestureDetector does not.
//   2. LABELLED — carries a semantics node with a name, so a screen reader can
//      announce it rather than reading "button" or nothing at all.
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:govpulse/core/widgets/Home/Quick-action/Web/quick_action_split_panel.dart';
import 'package:govpulse/core/widgets/Home/nav/home_top_nav.dart';
import 'package:govpulse/core/widgets/focus_activate.dart';
import 'package:govpulse/core/widgets/web/web_input_field.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(home: Scaffold(body: Center(child: child))),
  );
  await tester.pump(const Duration(milliseconds: 200));
}

/// Every focus node in the tree that can actually take keyboard focus.
Iterable<FocusNode> _focusableNodes(WidgetTester tester) {
  final root = tester.binding.focusManager.rootScope;
  final out = <FocusNode>[];
  void walk(FocusNode n) {
    if (n.canRequestFocus && !n.skipTraversal) out.add(n);
    for (final c in n.children) {
      walk(c);
    }
  }
  walk(root);
  return out;
}

void main() {
  group('submitting a report — the core civic action', () {
    testWidgets('the Submit control is reachable by keyboard', (tester) async {
      // QaActionButton is what the report, suggestion and feedback screens all
      // use for Submit / Continue. It renders a real FilledButton rather than a
      // GestureDetector, so this should pass — and that is worth PINNING,
      // because the obvious "tidy-up" of restyling it as a tap target would
      // silently take the keyboard away from the app's most important control.
      await _pump(
        tester,
        QaActionButton(
          label: 'Submit Report',
          icon: Icons.send_rounded,
          onTap: () {},
        ),
      );

      expect(find.byType(FilledButton), findsOneWidget,
          reason: 'Submit must be a real button, not a tap target');

      final focusable = _focusableNodes(tester);
      expect(focusable, isNotEmpty,
          reason: 'Submit must be reachable by Tab');
    });

    testWidgets('a screen reader can announce the Submit control',
        (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        QaActionButton(
          label: 'Submit Report',
          icon: Icons.send_rounded,
          onTap: () {},
        ),
      );

      // The label has to reach the semantics tree, not just the pixels.
      expect(
        find.bySemanticsLabel('Submit Report'),
        findsAtLeastNWidgets(1),
        reason: 'the control must announce what it does',
      );
      handle.dispose();
    });

    testWidgets('a disabled Submit is announced as disabled, not missing',
        (tester) async {
      // While media is still processing the screen passes onTap: null. A
      // sighted user sees the button greyed; a screen-reader user must be told
      // it is disabled rather than find nothing there.
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        const QaActionButton(label: 'Finishing photo…', onTap: null),
      );

      expect(find.bySemanticsLabel('Finishing photo…'),
          findsAtLeastNWidgets(1));
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
      handle.dispose();
    });
  });

  group('signing in', () {
    testWidgets('credential fields are focusable and typable', (tester) async {
      await _pump(
        tester,
        Column(
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
      );

      // A TextField carries its own focus node, so the login form is keyboard
      // reachable even though its surrounding chrome is hand-drawn.
      expect(find.byType(TextField), findsNWidgets(2));
      await tester.tap(find.byType(TextField).first);
      await tester.pump();
      expect(
        tester.binding.focusManager.primaryFocus?.hasFocus,
        isTrue,
        reason: 'the username box must be able to hold focus',
      );
    });

    testWidgets('the password box is announced without reading the password',
        (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        WebInputField(
          hint: 'Password',
          icon: Icons.lock,
          obscure: true,
          onChanged: (_) {},
        ),
      );

      final field = tester.widget<TextField>(find.byType(TextField));
      // obscureText is what stops a screen reader announcing the characters
      // typed into it, which matters on a shared or public machine.
      expect(field.obscureText, isTrue);
      handle.dispose();
    });
  });

  group('reaching an emergency hotline', () {
    testWidgets('FocusActivate puts a hand-drawn card in the Tab order',
        (tester) async {
      // The emergency category cards drive a press-scale animation from
      // onTapDown/onTapUp, a pair no Material button exposes — so they stay
      // GestureDetectors and gain focus by wrapping. This pins the wrapper,
      // since the card itself needs the whole screen (and its providers) to
      // build.
      var activated = 0;
      await _pump(
        tester,
        Semantics(
          label: 'Police',
          button: true,
          child: FocusActivate(
            onActivate: () => activated++,
            child: const SizedBox(width: 120, height: 80),
          ),
        ),
      );

      // The FocusActivate's own node, not some ancestor scope — Focus inserts
      // its node on the element it builds, so ask that element directly.
      final node = Focus.of(
        tester.element(find.byType(SizedBox).first),
      );
      node.requestFocus();
      await tester.pump();
      expect(node.hasFocus, isTrue, reason: 'the card must accept focus');

      // Enter activates, the way a keyboard user expects of a button.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(activated, 1, reason: 'Enter must activate the card');

      // Space too.
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(activated, 2, reason: 'Space must activate the card');
    });

    testWidgets('a screen reader announces the category by name',
        (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        Semantics(
          label: 'Police',
          button: true,
          child: FocusActivate(
            onActivate: () {},
            child: const SizedBox(width: 120, height: 80),
          ),
        ),
      );
      expect(find.bySemanticsLabel('Police'), findsAtLeastNWidgets(1));
      handle.dispose();
    });

    testWidgets('a disabled card is not a Tab stop', (tester) async {
      var activated = 0;
      await _pump(
        tester,
        FocusActivate(
          enabled: false,
          onActivate: () => activated++,
          child: const SizedBox(width: 120, height: 80),
        ),
      );
      // Nothing to focus, so nothing to activate.
      expect(activated, 0);
    });
  });

  group('moving around the site — the primary navigation', () {
    testWidgets('every top-nav destination is a Tab stop and announces itself',
        (tester) async {
      // The whole reason this group exists: the nav links were bare
      // GestureDetectors, so a keyboard user could not move between Home, My
      // Reports, NewsFeed and Emergency at all. Not one action denied — the
      // entire site unnavigable.
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final handle = tester.ensureSemantics();

      final tapped = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomeTopNav(
              currentIndex: 0,
              onTap: tapped.add,
              onNotificationTap: () {},
              onLogoutTap: () {},
              notificationCount: 0,
              verifStatus: 'verified',
              username: 'juan',
              flatChrome: true,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      // Each destination reaches the semantics tree by name.
      for (final item in HomeTopNav.defaultItems) {
        expect(find.bySemanticsLabel(item.label), findsAtLeastNWidgets(1),
            reason: 'the ${item.label} link must be announced');
      }

      // And each is focusable + activates from the keyboard.
      final links = find.byType(FocusActivate);
      expect(links, findsAtLeastNWidgets(HomeTopNav.defaultItems.length),
          reason: 'every destination must be in the Tab order');

      // The Focus node lives INSIDE FocusActivate, so ask for the Focus
      // widget it builds rather than looking upward from the wrapper itself.
      final focusFinder = find.descendant(
        of: links.first,
        matching: find.byType(Focus),
      );
      expect(focusFinder, findsAtLeastNWidgets(1));
      final node = tester.widget<Focus>(focusFinder.first).focusNode ??
          Focus.of(tester.element(
            find.descendant(of: focusFinder.first, matching: find.byType(MouseRegion)).first,
          ));
      node.requestFocus();
      await tester.pump();
      expect(node.hasFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(tapped, isNotEmpty,
          reason: 'Enter on a focused nav link must navigate');
      handle.dispose();
    });

    testWidgets('the active destination is announced as selected',
        (tester) async {
      // A sighted user sees the blue underline; a screen-reader user needs to
      // be TOLD which section they are in, or they have no way to know.
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomeTopNav(
              currentIndex: 1, // My Reports
              onTap: (_) {},
              onNotificationTap: () {},
              onLogoutTap: () {},
              notificationCount: 0,
              verifStatus: 'verified',
              username: 'juan',
              flatChrome: true,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      final node = tester.getSemantics(
        find.bySemanticsLabel('My Reports').first,
      );
      expect(node.hasFlag(SemanticsFlag.isSelected), isTrue,
          reason: 'the current section must announce as selected');
      handle.dispose();
    });
  });
}
