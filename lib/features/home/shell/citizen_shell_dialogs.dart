import 'package:flutter/material.dart';

import '../../../core/theme/citizen_ui.dart';
import '../../../core/widgets/app_dialog.dart';

// ════════════════════════════════════════════════════════════════════════════
//  How the citizen web shell opens things.
//
//  The shell's whole premise is that the feed and both rails stay mounted. A
//  full-screen route breaks that — it replaces the page, the feed unmounts and
//  reloads on the way back, and the browser gains a history entry for something
//  that is really a panel. So inside the shell, everything opens as a dialog
//  over the still-mounted page.
//
//  Both helpers go through [showAppDialog], so they inherit the app's frosted
//  backdrop and its open/close animation rather than inventing a second way for
//  a pop-up to arrive.
//
//  Two sizes, because two very different things are being shown:
//
//    • [showCitizenPanelDialog] — settings-shaped content (Edit Profile,
//      Change Password, My Submissions, Contact Support, About). Comfortable
//      reading width; the hosted screen keeps its own header.
//
//    • [showCitizenFormDialog] — the long quick-action forms (Report,
//      Suggestion, Feedback). Deliberately BIG: these have a category picker, a
//      map, a photo grid and a disclaimer, and squeezing them into a panel makes
//      them unusable. Gets a header with a title and an X, and the form scrolls
//      INSIDE the dialog so the page behind never moves.
// ════════════════════════════════════════════════════════════════════════════

/// Width of the big form modal: most of the viewport, capped so it never
/// stretches into an unreadable line length on an ultrawide monitor.
const double _kFormDialogMaxWidth = 900;

/// Fraction of the viewport a dialog may occupy.
const double _kDialogWidthFactor = 0.9;
const double _kDialogHeightFactor = 0.85;

/// Standard-size dialog for settings-shaped content.
///
/// [child] is the existing screen, hosted as-is — it keeps its own Scaffold and
/// header, which inside these bounds reads as a self-contained panel. Its own
/// back/close button calls `Navigator.pop`, which closes this dialog, so nothing
/// had to change inside those screens.
Future<T?> showCitizenPanelDialog<T>({
  required BuildContext context,
  required Widget child,
  double maxWidth = 620,
}) {
  final size = MediaQuery.sizeOf(context);
  return showAppDialog<T>(
    context: context,
    builder: (_) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          maxHeight: size.height * _kDialogHeightFactor,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(CitizenUi.cardRadius + 4),
          child: Material(color: CitizenUi.surface, child: child),
        ),
      ),
    ),
  );
}

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
