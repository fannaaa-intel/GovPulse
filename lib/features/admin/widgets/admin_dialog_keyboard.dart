import 'package:flutter/material.dart';

import 'admin_dialog_back.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Pinned dialog actions that stand down while the keyboard is up
//
//  Every report-process dialog on a phone is a full-bleed screen: a header, a
//  scrolling body, and an action bar pinned to the bottom. That pin is right
//  until a text field takes focus — then the keyboard covers the bar anyway,
//  and the bar is charging the body 100–150px for buttons nobody can reach.
//
//  On the reject dialog this was visible as the thing the request describes:
//  the reason field stayed above the keyboard (the framework scrolls it into
//  view), but the buttons rode up with it and sat directly on the keyboard.
//
//  ── WHY A SCOPE AND NOT A MEDIAQUERY READ ─────────────────────────────────
//  [Dialog] pads itself by `MediaQuery.viewInsets` and then wraps its child in
//  `MediaQuery.removeViewInsets(removeBottom: true, ...)` — dialog.dart does
//  this so a dialog's contents are not asked to dodge a keyboard the dialog has
//  already dodged for them. The consequence is absolute: anywhere INSIDE the
//  dialog, `viewInsets.bottom` is zero no matter what the keyboard is doing.
//
//  This is not a theory. The citizen quick-action panel shipped exactly that
//  check — `MediaQuery.viewInsetsOf(context).bottom > 0`, read from inside the
//  Dialog — and it never fired once; see the header of QaKeyboardScope in
//  quick_action_split_panel.dart, and quick_action_keyboard_test.dart, which
//  exists to stop it being written a third time.
//
//  So the answer is read ABOVE the strip and carried down. These dialogs build
//  their own [Dialog] inside their own `build`, and that build's context is
//  above the strip the Dialog installs for its child — [AdminDialogKeyboard.of]
//  falls back to that read, so a dialog gets the right answer with no host
//  wiring, and a test can still force either state by wrapping a scope.
// ════════════════════════════════════════════════════════════════════════════

/// Carries "a soft keyboard is open" across the [Dialog] boundary.
///
/// With no scope present, [of] falls back to the ambient `viewInsets` — correct
/// at a dialog's OWN build site (above the strip), and correctly `false` in
/// tests and previews that never raise a keyboard.
class AdminDialogKeyboard extends InheritedWidget {
  final bool keyboardUp;

  const AdminDialogKeyboard({
    super.key,
    required this.keyboardUp,
    required super.child,
  });

  static bool of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<AdminDialogKeyboard>();
    if (scope != null) return scope.keyboardUp;
    return MediaQuery.viewInsetsOf(context).bottom > 0;
  }

  @override
  bool updateShouldNotify(AdminDialogKeyboard oldWidget) =>
      oldWidget.keyboardUp != keyboardUp;
}

/// Collapses [child] out of the layout while [keyboardUp], animating only on
/// the way BACK.
///
/// ── Instant out, eased back ───────────────────────────────────────────────
/// Animating the collapse WHILE the keyboard rises puts two animations on the
/// same dimension on different clocks. The Dialog shrinks at the keyboard's
/// speed while a timed collapse frees the bar's height on its own, so early in
/// the rise the resize outruns the collapse and later the collapse overtakes
/// it — measured on the quick-action panel as the body going down 58px, back
/// up 55, then down 53, and felt as a shake.
///
/// Going out there must therefore be exactly ONE moving part, and it has to be
/// the keyboard's. Coming back there is nothing to race — `keyboardUp` only
/// clears once the inset reaches zero, so the keyboard has already finished —
/// and that is the direction worth easing, since an instant return would snap
/// the whole bar in one frame.
class AdminKeyboardCollapse extends StatelessWidget {
  final bool keyboardUp;
  final Widget child;

  const AdminKeyboardCollapse({
    super.key,
    required this.keyboardUp,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      // Not `Duration.zero`: AnimatedSize completes a zero-duration controller
      // synchronously inside its own performLayout and asserts
      // "RenderAnimatedSize was mutated in its own performLayout". One
      // millisecond finishes on the next frame instead — instant to the eye,
      // legal to the framework.
      duration: keyboardUp
          ? const Duration(milliseconds: 1)
          : const Duration(milliseconds: 260),
      curve: Curves.easeInOutCubic,
      alignment: Alignment.topCenter,
      child: keyboardUp ? const SizedBox.shrink() : child,
    );
  }
}

/// The shared phone-screen header for a report-process dialog: the back chevron
/// and the TITLE on one row, the description on its own beneath them.
///
/// ── The shape ─────────────────────────────────────────────────────────────
///     [<]  Accept & Assign
///     This report is valid and will be assigned to a department for action.
///     This action cannot be undone.
///
/// Back is chrome, so it stays at the top-left where every pushed screen in
/// this app puts it, and the title travels with it rather than being pushed
/// down a line.
///
/// ── Why the seal is not here on a phone ───────────────────────────────────
/// It was, sitting to the left of the description — and it cost the copy about
/// 70px of a ~390px screen, wrapping two readable lines into three or four
/// narrow ones. The seal is decoration: it repeats what the title has already
/// said in words, and the description is the part that states what pressing
/// the button will actually do — including the irreversibility warning, which
/// is the single most important sentence on the screen. Decoration does not
/// get to squeeze the warning.
///
/// So on the phone the description runs the full width and the seal is
/// dropped. The MODAL keeps it: there the dialog is 860px wide, the seal costs
/// the copy nothing, and it gives an otherwise plain header a point of entry.
class AdminDialogScreenHeader extends StatelessWidget {
  /// The circular seal identifying the action. Drawn on the modal form only —
  /// see the note above for why the phone form omits it.
  final Widget seal;
  final Widget title;
  final Widget description;

  /// True on the phone/screen form.
  final bool full;
  final EdgeInsets padding;

  const AdminDialogScreenHeader({
    super.key,
    required this.seal,
    required this.title,
    required this.description,
    required this.full,
    required this.padding,
  });

  @override
  Widget build(BuildContext context) {
    // Wide: seal left, title over description to its right — the modal shape
    // this console has always drawn, and where the seal is free.
    if (!full) {
      return Padding(
        padding: padding,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            seal,
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [title, const SizedBox(height: 6), description],
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              AdminDialogBack(onTap: () => Navigator.of(context).pop()),
              const SizedBox(width: 12),
              // Flexible, not Expanded-with-no-wrap: a long title at a large
              // system text scale must wrap under itself rather than overflow.
              Flexible(child: title),
            ],
          ),
          const SizedBox(height: 10),
          // Full width — no seal, no indent. The description is the sentence
          // that says what the button does, so it gets the whole screen.
          SizedBox(width: double.infinity, child: description),
        ],
      ),
    );
  }
}

/// [Expanded] when [expand], [Flexible] otherwise — the one difference between
/// a dialog's screen form and its modal form, named once.
///
/// See the call sites for why it matters: Flexible lets the scroll view be
/// SHORTER than the space offered, so on a phone a dialog with little content
/// left its pinned action bar floating mid-screen, while a dialog with a lot
/// pushed the bar to the bottom. Same widget, two positions, decided by how
/// many cards it happened to be showing.
class AdminDialogFlex extends StatelessWidget {
  final bool expand;
  final Widget child;
  const AdminDialogFlex({
    super.key,
    required this.expand,
    required this.child,
  });

  @override
  Widget build(BuildContext context) =>
      expand ? Expanded(child: child) : Flexible(child: child);
}

/// The full-bleed phone form of a report-process dialog.
///
/// ── Why this is a Scaffold and NOT a Dialog with a zero inset ─────────────
/// The two look identical and behave quite differently once a keyboard is
/// involved. [Dialog] pads itself by `viewInsets` using an [AnimatedPadding]
/// — 100ms, `Curves.decelerate`, on its own clock — while the OS reports the
/// keyboard's rise in steps on a different one. Two animations on the same
/// dimension, racing: the content box lags the keyboard by a frame or two and
/// then catches up in a jump, which is what reads as the transition going
/// brick by brick rather than sliding.
///
/// Measured on the endorse dialog at a 900px viewport with a 320px keyboard:
/// the box was still 745 tall on the frame the inset reached its full 320,
/// then snapped to 580. The same lag, mirrored, on the way back down.
///
/// [Scaffold] with `resizeToAvoidBottomInset` is the mechanism
/// keyboard_visibility_test.dart already pins as correct, and the one the
/// citizen quick-action panel switched to for exactly this reason. It shrinks
/// the body on the keyboard's OWN clock — no second animation to race — AND
/// strips the inset from the MediaQuery the body sees, so a focused field
/// below the fold is scrolled above the keyboard by the framework instead of
/// being left under it.
///
/// The body still has to be TOLD a keyboard is up, because Scaffold strips the
/// inset for the same reason Dialog does — that is what [AdminDialogKeyboard]
/// carries, and why the caller reads it above this widget rather than inside.
class AdminFullBleedDialog extends StatelessWidget {
  final Widget child;

  /// Painted behind the form — the console surface, not the shell's grey.
  final Color backgroundColor;

  const AdminFullBleedDialog({
    super.key,
    required this.child,
    required this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      // The whole point — see the class note.
      resizeToAvoidBottomInset: true,
      // Flush to the viewport is not flush under a notch or a home indicator.
      //
      // ⚠ bottom: false, and the action bar owns that inset instead.
      //
      // Insetting the bottom HERE lifts the whole column off the screen edge,
      // so the pinned action bar drew its top border, its buttons and its
      // background, and then stopped — leaving a band of bare scaffold
      // underneath it. On a gesture-nav phone that band is the home-indicator
      // strip; on a button-nav phone it is zero and nothing looks wrong, which
      // is why this survived. Either way the bar was floating rather than
      // sitting on the bottom of the screen the way a phone's own sheets do.
      //
      // The fix is not to drop the inset — a button under the home indicator is
      // a button that swipes the app away instead of pressing. It is to move
      // the inset INSIDE the bar, so the bar's fill reaches the true edge and
      // its padding keeps the buttons clear of the gesture area. See
      // AdminResponsiveDialog._actionBar, which reads viewPadding.bottom.
      body: SafeArea(bottom: false, child: child),
    );
  }
}
