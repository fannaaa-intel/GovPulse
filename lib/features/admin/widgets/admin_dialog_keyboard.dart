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
