// test/auth_keyboard_button_reachable_test.dart
//
// ════════════════════════════════════════════════════════════════════════════
//  Can you still reach Sign in once the keyboard is up?
//
//  ── The defect ──────────────────────────────────────────────────────────
//  Reported from mobile web (Chrome on Android, /login): tap Username, the
//  keyboard opens, and the Sign in button is nowhere — the form ends in a band
//  of blank white above the keyboard, and scrolling does not bring the button
//  back.
//
//  WebGlassCard's full-bleed branch asked for
//
//      minHeight: MediaQuery.sizeOf(context).height
//
//  `sizeOf` is the WHOLE SCREEN. It does not shrink when the keyboard opens —
//  that is what `viewInsets` is for. So with a 320px keyboard on an 800px
//  screen the card kept demanding 800px of height inside a viewport that was
//  now only 480px tall, and `alignment: Alignment.center` centred the form in
//  that oversized box. The bottom ~320px of the card — the part holding the
//  button — was laid out underneath the keyboard, and the white the citizen
//  could see was the card's own gradient filling the space above it.
//
//  ── Why it looked unscrollable ──────────────────────────────────────────
//  It was scrollable, but only just: the content was already near the bottom
//  of its own box, so the little scroll available did not move the button into
//  view. The page looked broken rather than tall.
//
//  ── The fix ─────────────────────────────────────────────────────────────
//  Subtract the insets the caller has NOT already handled. Scaffold with
//  `resizeToAvoidBottomInset: true` shrinks the body and zeroes the inset in
//  the MediaQuery the body sees, so inside it `viewInsets.bottom` is 0 and the
//  height read is already the shrunken one. Reading `MediaQuery.of` rather
//  than `sizeOf` and subtracting whatever inset remains is therefore correct
//  in BOTH cases — under a resizing Scaffold and standing alone.
// ════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:govpulse/core/widgets/web/web_auth_scaffold.dart';
import 'package:govpulse/core/widgets/web/web_glass_card.dart';

// A phone-sized viewport under the full-bleed threshold (600), so the card
// takes the branch the bug was in.
const Size _kPhone = Size(400, 800);
const double _kKeyboard = 320;

/// The login screen's own shape: glass surface, scroll view, bleed fill, card.
///
/// Rebuilt here rather than mounting LoginScreen itself, which reaches for
/// Supabase and Firebase in initState. Every widget in the chain that decides
/// the layout is the real one.
Widget _authPage({required Key buttonKey}) => MaterialApp(
      home: Scaffold(
        resizeToAvoidBottomInset: true,
        body: WebGlassSurface(
          child: SafeArea(
            child: bleedOrCentre(
              true,
              SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: WebGlassCard(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 120), // logo + headings
                      const TextField(decoration: InputDecoration()),
                      const SizedBox(height: 12),
                      const TextField(decoration: InputDecoration()),
                      const SizedBox(height: 20),
                      FilledButton(
                        key: buttonKey,
                        onPressed: () {},
                        child: const Text('Sign in'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

void main() {
  const buttonKey = Key('signin');

  testWidgets('the submit button is on screen when the keyboard is open', (
    tester,
  ) async {
    tester.view.physicalSize = _kPhone;
    tester.view.devicePixelRatio = 1.0;
    tester.view.viewInsets = const FakeViewPadding(bottom: _kKeyboard);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_authPage(buttonKey: buttonKey));
    await tester.pumpAndSettle();

    // The visible area is the screen minus the keyboard.
    final visibleBottom = _kPhone.height - _kKeyboard;
    final button = tester.getRect(find.byKey(buttonKey));

    expect(
      button.bottom,
      lessThanOrEqualTo(visibleBottom),
      reason: 'Sign in is laid out at ${button.top}-${button.bottom}, but the '
          'keyboard covers everything below $visibleBottom. This is the '
          'reported bug: the button sits under the keyboard with a band of '
          'blank card gradient where it should be.',
    );
  });

  testWidgets('the card does not demand more height than the viewport has', (
    tester,
  ) async {
    tester.view.physicalSize = _kPhone;
    tester.view.devicePixelRatio = 1.0;
    tester.view.viewInsets = const FakeViewPadding(bottom: _kKeyboard);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_authPage(buttonKey: buttonKey));
    await tester.pumpAndSettle();

    // The direct cause, pinned separately from its symptom: the card's own
    // box must not be taller than the space the keyboard leaves. `sizeOf`
    // returned the full 800 here, which is what pushed the button down.
    final card = tester.getRect(
      find.ancestor(
        of: find.byKey(buttonKey),
        matching: find.byType(ConstrainedBox),
      ).first,
    );
    expect(
      card.height,
      lessThanOrEqualTo(_kPhone.height - _kKeyboard + 1),
      reason: 'The full-bleed card asked for ${card.height}px inside a '
          '${_kPhone.height - _kKeyboard}px viewport.',
    );
  });

  testWidgets('with no keyboard the card still fills the screen', (
    tester,
  ) async {
    // The reason minHeight exists at all: a short form must paint its white to
    // the bottom of the screen, or the backdrop's glows show through beneath
    // it and the page reads as a very wide card. Fixing the keyboard case must
    // not cost that.
    tester.view.physicalSize = _kPhone;
    tester.view.devicePixelRatio = 1.0;
    tester.view.viewInsets = FakeViewPadding.zero;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_authPage(buttonKey: buttonKey));
    await tester.pumpAndSettle();

    final card = tester.getRect(
      find.ancestor(
        of: find.byKey(buttonKey),
        matching: find.byType(ConstrainedBox),
      ).first,
    );
    expect(
      card.height,
      greaterThanOrEqualTo(_kPhone.height - 1),
      reason: 'A short form must still paint the full screen height when '
          'there is no keyboard.',
    );
  });

  _scaffoldTests();
}

// ── The other four screens ──────────────────────────────────────────────────
//
// login and signup build their own scaffold; the guest screen and the four
// reset / verification steps go through WebAuthScaffold instead. That file had
// its OWN copy of the full-bleed stretch — the same two lines, inlined — so
// fixing web_glass_card alone would have left those screens still laying their
// button out under the keyboard. This pins that they share one path.
class _TickerHost extends StatefulWidget {
  final Widget Function(AnimationController) build;
  const _TickerHost({required this.build});
  @override
  State<_TickerHost> createState() => _TickerHostState();
}

class _TickerHostState extends State<_TickerHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1),
  )..value = 1;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.build(_c);
}

void _scaffoldTests() {
  const buttonKey = Key('reset-submit');

  testWidgets('WebAuthScaffold keeps its button above the keyboard too', (
    tester,
  ) async {
    tester.view.physicalSize = _kPhone;
    tester.view.devicePixelRatio = 1.0;
    tester.view.viewInsets = const FakeViewPadding(bottom: _kKeyboard);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: _TickerHost(
          build: (c) => WebAuthScaffold(
            heroController: c,
            headline: 'Reset password',
            subtitle: 'We will email you a link.',
            card: WebAuthCard(
              children: [
                const SizedBox(height: 120),
                const TextField(decoration: InputDecoration()),
                const SizedBox(height: 20),
                FilledButton(
                  key: buttonKey,
                  onPressed: () {},
                  child: const Text('Send link'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final visibleBottom = _kPhone.height - _kKeyboard;
    final button = tester.getRect(find.byKey(buttonKey));
    expect(
      button.bottom,
      lessThanOrEqualTo(visibleBottom),
      reason: 'Send link sits at ${button.top}-${button.bottom}, under a '
          'keyboard that starts at $visibleBottom. web_auth_scaffold must use '
          'bleedOrCentre rather than its own copy of the stretch.',
    );
  });
}
