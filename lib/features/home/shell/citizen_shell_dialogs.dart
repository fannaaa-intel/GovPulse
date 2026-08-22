import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/citizen_ui.dart';
import '../../../core/widgets/Home/Quick-action/Web/quick_action_split_panel.dart'
    show QaFullBleedScope, QaKeyboardScope;
import '../../../core/widgets/app_dialog.dart';

// ════════════════════════════════════════════════════════════════════════════
//  How the citizen web shell opens things.
//
//  What is left here is the QUICK ACTIONS, and only them. A report, a
//  suggestion or a piece of feedback is an interruption: you start it from the
//  feed, you finish it, and you come back to the post you were reading. Keeping
//  the feed and both rails mounted underneath is the whole point, and a route
//  would break it — the feed unmounts and reloads on the way back, and the
//  browser gains a history entry for something that is really a panel.
//
//  The five ACCOUNT screens used to be here too, behind a third helper. They
//  are not interruptions, they are places you GO, and they are pages now —
//  routes under the Settings branch. See [CitizenAccountPage] in
//  citizen_shell_router.dart for why, and for why nesting them in that branch
//  costs the feed nothing.
//
//  Both helpers go through [showAppDialog], so they inherit the app's frosted
//  backdrop and its open/close animation rather than inventing a second way for
//  a pop-up to arrive.
//
//  Two shapes, because a quick action arrives in two:
//
//    • [showCitizenFormDialog] — the long single-column forms. Deliberately
//      BIG: these have a category picker, a map, a photo grid and a disclaimer,
//      and squeezing them into a panel makes them unusable. Gets a header with
//      a title and an X, and the form scrolls INSIDE the dialog so the page
//      behind never moves.
//
//    • [showCitizenSplitPanelDialog] — the same actions once they grew a
//      summary rail. Wider still, no header of its own, and fullscreen on a
//      phone.
// ════════════════════════════════════════════════════════════════════════════

/// Width of the big form modal: most of the viewport, capped so it never
/// stretches into an unreadable line length on an ultrawide monitor.
const double _kFormDialogMaxWidth = 900;

/// Width cap for the two-column split-panel modal.
///
/// Wider than [_kFormDialogMaxWidth] because it seats two columns rather than
/// one: the working area still wants the ~620px the single-column form had, and
/// the rail needs ~380 before its summary values start wrapping. 620 + 380 +
/// the 14px gap + 2×20 of dialog padding ≈ 1074, rounded up for breathing room.
const double _kSplitDialogMaxWidth = 1160;

/// Fraction of the viewport a dialog may occupy.
const double _kDialogWidthFactor = 0.9;
const double _kDialogHeightFactor = 0.85;

/// Below this VIEWPORT width the split panel stops being a dialog and takes the
/// whole screen.
///
/// ── Why a second number, and why it is not 880 ───────────────────────────
/// [kQaSplitCollapseBelow] (880) is measured on the PANEL's width and decides
/// whether the panel draws as two columns or three stacked zones. This one is
/// measured on the VIEWPORT and decides whether that panel is presented as a
/// floating card or as the page. They are different questions about different
/// boxes and they do not collapse into one another: at a 1000px window the
/// panel stacks while still clearly being a dialog over the shell.
///
/// 1024 is the tablet/desktop line — the same one the verification wizard uses
/// to decide whether to offer a camera, for the same underlying reason: below
/// it you are probably holding the thing, and a held device gets a soft
/// keyboard.
///
/// It was 600, which covered phones only. Between 600 and here the panel was
/// already STACKED — a floating card is only worth its inset when there are two
/// columns inside it to frame — so that band got the worst of both: a card too
/// narrow to lay out side by side, floating inside a viewport it could not use,
/// with a keyboard that a Dialog cannot help it with. Fullscreen from here down
/// means every touch-sized viewport gets the Scaffold keyboard behaviour, and
/// the floating card is kept for the widths where it is actually framing
/// something.
///
/// The four quick-action forms read this constant too, so they and the host
/// cannot disagree about which presentation they are in.
const double kSplitDialogFullscreenBelow = 1024;

/// Lets a form hosted in [showCitizenFormDialog] keep its "discard changes?"
/// guard when the dialog is closed from the outside (the X, or the barrier).
///
/// The standalone screens get that guard from a [PopScope]; a dialog has no
/// equivalent, and losing it on a half-filled report form would be a real
/// regression. The form assigns [confirmDiscard] in its initState, and the
/// dialog's close path awaits it. A form that sets nothing simply closes.
///
/// This is a plain holder passed DOWN into the form, deliberately not a lookup
/// back up the element tree — the pattern that was just removed from Settings'
/// logout.
class FormDialogGuard {
  Future<bool> Function()? confirmDiscard;
}

/// Big modal for a long form.
///
/// [builder] receives a close callback so the form can dismiss itself on submit
/// or cancel without knowing it is in a dialog.
Future<T?> showCitizenFormDialog<T>({
  required BuildContext context,
  required String title,
  required IconData icon,
  required Widget Function(BuildContext context, VoidCallback close) builder,
  FormDialogGuard? guard,
}) {
  final size = MediaQuery.sizeOf(context);
  final width = (size.width * _kDialogWidthFactor).clamp(
    320.0,
    _kFormDialogMaxWidth,
  );
  return showAppDialog<T>(
    context: context,
    // Tapping the backdrop must not silently bin a half-filled form; closing
    // goes through the X, which honours the discard guard.
    barrierDismissible: false,
    builder: (dialogContext) {
      Future<void> close() async {
        final ask = guard?.confirmDiscard;
        if (ask != null && !await ask()) return;
        if (dialogContext.mounted) Navigator.of(dialogContext).pop();
      }

      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: width,
            maxHeight: size.height * _kDialogHeightFactor,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(CitizenUi.cardRadius + 4),
            child: Material(
              color: CitizenUi.pageBg,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _FormDialogHeader(title: title, icon: icon, onClose: close),
                  // The form scrolls in here. Flexible (not Expanded) so a short
                  // form makes a short dialog instead of always filling 85vh.
                  Flexible(child: builder(dialogContext, close)),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// Big modal for a quick action laid out as a two-column split panel.
///
/// Differs from [showCitizenFormDialog] in three ways, the first two because
/// the split panel supplies its own chrome:
///
///   • No header. The title sits at the top of the left panel and the close
///     button is the round × in the right rail's header, so a dialog-level
///     header would be a second title bar over the first.
///   • Wider ([_kSplitDialogMaxWidth]), because two columns need the room.
///   • Fullscreen below [kSplitDialogFullscreenBelow], because a phone has no
///     width to spend on being a card.
///
/// The discard guard works exactly as it does for the form dialog: [close]
/// awaits `guard.confirmDiscard` before popping, and the panel wires both its ×
/// and its Cancel button to that same callback.
Future<T?> showCitizenSplitPanelDialog<T>({
  required BuildContext context,
  required Widget Function(BuildContext context, VoidCallback close) builder,
  FormDialogGuard? guard,
}) {
  return showAppDialog<T>(
    context: context,
    // Same reasoning as the form dialog: a stray backdrop tap must not bin a
    // half-filled report. Closing goes through the ×, which honours the guard.
    barrierDismissible: false,
    builder: (dialogContext) {
      // ── Measured INSIDE the builder, unlike the other two helpers ────────
      // Reading the size before showAppDialog captures it once, at open. That
      // is survivable for a dialog whose only job is to be 90% of something,
      // and not for this one: dragging a browser window across 600 has to
      // actually change the presentation, and across 880 has to reach the
      // panel as a new width. Reading it here subscribes this subtree to the
      // size, so both happen on the frame the window changes. `sizeOf` depends
      // on the size aspect alone, so a keyboard inset does not rebuild it.
      final size = MediaQuery.sizeOf(dialogContext);
      final fullscreen = size.width < kSplitDialogFullscreenBelow;

      // ── The keyboard flag has to be read HERE ────────────────────────
      //
      // This context is ABOVE the [Dialog] built below, which is the only
      // place the real inset is still visible: Dialog pads itself by
      // viewInsets and then strips them from everything it contains, so a
      // check made inside the panel reads zero forever. That is exactly how
      // the first attempt at this shipped without doing anything.
      //
      // `viewInsetsOf` rather than reusing `size`: the note above is right
      // that `sizeOf` alone does not rebuild on a keyboard, so this call is
      // doing two jobs — reading the value, and subscribing this subtree to
      // it so the panel is rebuilt on the frame the keyboard moves.
      final keyboardUp = MediaQuery.viewInsetsOf(dialogContext).bottom > 0;

      Future<void> close() async {
        final ask = guard?.confirmDiscard;
        if (ask != null && !await ask()) return;
        if (dialogContext.mounted) Navigator.of(dialogContext).pop();
      }

      // Phone: the panel IS the page. No inset, no rounded card, no barrier
      // showing round the edges — [BoxConstraints.expand] against the loose
      // constraints the Dialog hands down resolves to a tight fit on whatever
      // is actually available, which is the viewport less the route's own safe
      // area. The 12px inside is the panel's only margin; the three-zone
      // stacked layout takes the height from there and pins its actions to the
      // bottom of the screen.
      // ── Fullscreen is a SCAFFOLD, deliberately not a Dialog ─────────────
      //
      // It was a Dialog with zero inset and BoxConstraints.expand(), which
      // looks the same and behaves quite differently once a keyboard is
      // involved. [Dialog] pads itself by `viewInsets` and then strips them
      // from its subtree, so:
      //
      //   • the panel is handed a shorter box, but nothing INSIDE it knows a
      //     keyboard exists, and
      //   • the padding is animated (AnimatedPadding, 100ms) while the browser
      //     reports the inset in steps, so the panel re-laid out against a
      //     moving target every frame — which is what read as the transition
      //     going "brick by brick".
      //
      // A [Scaffold] with `resizeToAvoidBottomInset` is the mechanism
      // keyboard_visibility_test.dart already pins as correct: it shrinks the
      // body AND removes the inset from the MediaQuery the body sees, so a
      // nested Scaffold cannot double-count it, and — the part that matters
      // here — a focused field below the fold is scrolled above the keyboard
      // by the framework instead of being left under it.
      //
      // The panel still needs to be TOLD about the keyboard, because Scaffold
      // strips the inset for exactly the same reason Dialog does. That is what
      // [QaKeyboardScope] is for, and why it is still read from `dialogContext`
      // above rather than from inside.
      if (fullscreen) {
        return Scaffold(
          // The panel's own surface, not the shell's grey. Fullscreen there is
          // nothing behind the panel for a page colour to be the colour OF, and
          // the only place the grey still showed was the 12px band around the
          // cards and the trough between them — which is exactly what made a
          // sheet filling the viewport read as a card floating over something.
          backgroundColor: CitizenUi.surface,
          resizeToAvoidBottomInset: true,
          body: SafeArea(
            // ── No inset, and the cards give up their outline ──────────────
            //
            // It was `Padding(all: 12)` around bordered, rounded cards. Every
            // one of those pixels is spent framing the panel against a page
            // that is not there: 12 a side plus the 14px trough between the two
            // zones is ~38px of grey on a 390px phone, and it cost the list the
            // same height it cost the frame.
            //
            // [QaFullBleedScope] is the other half — it is what turns the two
            // cards into one sheet, so removing the inset does not simply move
            // a rounded card up against the screen edge. The docked chat made
            // the same call for the same reason: `BorderRadius.zero`, edge to
            // edge, "the card meets every viewport edge, so rounded corners
            // would leave the page showing through in four notches".
            //
            // [SafeArea] stays: flush to the viewport is not flush under a
            // notch or a home indicator.
            child: QaFullBleedScope(
              fullBleed: true,
              child: QaKeyboardScope(
                keyboardUp: keyboardUp,
                child: builder(dialogContext, close),
              ),
            ),
          ),
        );
      }

      // The dialog's own inset — 24 a side — is space the Dialog does NOT
      // have. Subtracting it here is what guarantees the panel can never be
      // handed more width than the viewport, at any viewport: the 0.9 factor
      // alone stops covering the inset below a ~480px window, and the 1160 cap
      // would stop covering it on any window narrower than 1208 if the factor
      // were ever raised. `lower <= upper` is asserted by clamp, hence the
      // max(). `math.min` twice rather than clamp(): on a viewport under
      // ~368px the available width drops below the 320 floor, and clamp()
      // asserts when its lower bound exceeds its upper. Taking the smallest of
      // the three degrades instead — such a window now renders fullscreen
      // above, but this must still not throw if the threshold ever moves.
      final available = size.width - 48;
      final width = math.min<double>(
        math.min<double>(
          size.width * _kDialogWidthFactor,
          _kSplitDialogMaxWidth,
        ),
        math.max<double>(available, 0),
      );

      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: width,
            maxHeight: size.height * _kDialogHeightFactor,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(CitizenUi.cardRadius + 4),
            child: Material(
              color: CitizenUi.pageBg,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: QaKeyboardScope(
                  keyboardUp: keyboardUp,
                  child: builder(dialogContext, close),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _FormDialogHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final VoidCallback onClose;

  const _FormDialogHeader({
    required this.title,
    required this.icon,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
      decoration: const BoxDecoration(
        color: CitizenUi.surface,
        border: Border(bottom: BorderSide(color: CitizenUi.border)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: CitizenUi.accentWash,
              borderRadius: BorderRadius.circular(CitizenUi.controlRadius),
            ),
            child: Icon(icon, size: 19, color: CitizenUi.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: CitizenUi.textPrimary,
              ),
            ),
          ),
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded),
            color: CitizenUi.textMuted,
            tooltip: 'Close',
          ),
        ],
      ),
    );
  }
}
