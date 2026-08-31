import 'package:flutter/material.dart';

import '../theme/admin_ui.dart';
import 'admin_dialog_back.dart';
import 'admin_dialog_keyboard.dart';

// ════════════════════════════════════════════════════════════════════════════
//  A dialog that becomes a SCREEN on a phone
//
//  The admin console's dialogs are the report process: endorse to an entity,
//  reject with a reason, dismiss as spam, merge a duplicate, review an update.
//  Each is a form, and on a desktop a centred modal is the right shape for one
//  — it keeps the report visible behind it and says "this is a step, not a
//  destination".
//
//  On a phone that shape stops paying for itself. A 409px viewport leaves the
//  modal ~385px wide after its inset, minus its own padding, to hold a search
//  field and a 2-up grid of agency cards — and the barrier it floats on is
//  showing perhaps 12px either side. Nothing is gained by the float, and the
//  content pays for it twice: once in the inset, once in the corner radius
//  eating the grid.
//
//  ── WHY THE CHEVRON, AND WHY THAT ONE ─────────────────────────────────────
//  A modal is dismissed by an ✕ in its corner, because it is a thing floating
//  over the page. A SCREEN is dismissed by a back chevron, because it is a
//  place you navigated to. Getting this wrong is how a fullscreen dialog ends
//  up feeling like a page you cannot leave.
//
//  [AdminDialogBack] is that chevron — the console's existing one, already on
//  the profile editor, change password, the activity log and community
//  updates. It mirrors the citizen [AppBackChevron]: an OUTLINE, not a filled
//  chip, with a neutral glyph, so back recedes and the title leads. Reusing it
//  rather than drawing another is the entire point of that file's header note.
// ════════════════════════════════════════════════════════════════════════════

/// Viewport width below which an admin dialog is drawn as a full screen.
///
/// 640 matches the `narrow` test the endorse dialog already made for its own
/// internals, so a dialog does not change its INTERNAL layout at one width and
/// its outer shape at another.
const double kAdminDialogFullscreenBelow = 640;

/// Whether [context]'s viewport should draw admin dialogs full screen.
bool adminDialogIsFullscreen(BuildContext context) =>
    MediaQuery.sizeOf(context).width < kAdminDialogFullscreenBelow;

/// The shell every report-process dialog sits in.
///
/// Phone: a full-bleed screen with a back chevron, its header pinned and its
/// body scrolling under it.
/// Tablet and desktop: the centred modal the console has always drawn.
///
/// [title] and [subtitle] make the header. [leading] is an optional glyph
/// shown before the title on the modal form only — on a phone the chevron
/// occupies that slot, and two marks side by side read as a toolbar.
/// [actions] pin to the bottom on both shapes.
class AdminResponsiveDialog extends StatelessWidget {
  final String title;
  final String? subtitle;

  /// Extra header line under [subtitle] — the endorse dialog's "this issues a
  /// printed letter" warning, for instance.
  final Widget? headerNote;
  final Widget? leading;
  final Widget child;
  final List<Widget> actions;

  /// Widest the modal form may draw. Ignored on the phone form.
  final double maxWidth;

  const AdminResponsiveDialog({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.headerNote,
    this.leading,
    this.actions = const [],
    this.maxWidth = 880,
  });

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final full = adminDialogIsFullscreen(context);

    final content = Column(
      mainAxisSize: full ? MainAxisSize.max : MainAxisSize.min,
      children: [
        _header(context, full),
        const Divider(height: 1, color: AdminUi.border),
        Flexible(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(full ? 16 : 24, 18, full ? 16 : 24, 8),
            child: child,
          ),
        ),
        if (actions.isNotEmpty) _actionBar(context, full),
      ],
    );

    if (full) {
      // Still a dialog ROUTE, not a pushed page: the callers are
      // `showAppDialog(...)` and they await a RESULT. Turning them into routes
      // would change every call site's control flow to fix a shape, and the
      // barrier/blur behaviour in app_dialog would have to be rebuilt for the
      // new route type.
      //
      // What DID change is the fullscreen shell inside that route — a Scaffold
      // rather than a zero-inset Dialog. See AdminFullBleedDialog for the
      // keyboard race that settles.
      return AdminFullBleedDialog(
        backgroundColor: AdminUi.surface,
        child: content,
      );
    }

    return Dialog(
      backgroundColor: AdminUi.surface,
      insetPadding: const EdgeInsets.all(40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          maxHeight: media.size.height * 0.9,
        ),
        child: content,
      ),
    );
  }

  Widget _header(BuildContext context, bool full) {
    return Padding(
      padding: EdgeInsets.fromLTRB(full ? 12 : 24, full ? 8 : 20, full ? 12 : 20, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Back on a screen, close on a modal — see the header note.
          if (full) ...[
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: AdminDialogBack(onTap: () => Navigator.of(context).pop()),
            ),
            const SizedBox(width: 10),
          ] else if (leading != null) ...[
            leading!,
            const SizedBox(width: 14),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: full ? 17 : 19,
                    fontWeight: FontWeight.w800,
                    color: AdminUi.textPrimary,
                    letterSpacing: -0.2,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      color: AdminUi.textSecondary,
                    ),
                  ),
                ],
                if (headerNote != null) ...[
                  const SizedBox(height: 4),
                  headerNote!,
                ],
              ],
            ),
          ),
          // The modal keeps its ✕. The screen does not: it already has the
          // chevron, and two ways out in one header is one too many.
          if (!full) ...[
            const SizedBox(width: 12),
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded, size: 20),
              color: AdminUi.textSecondary,
              tooltip: 'Close',
            ),
          ],
        ],
      ),
    );
  }

  Widget _actionBar(BuildContext context, bool full) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        full ? 16 : 24,
        12,
        full ? 16 : 24,
        full ? 12 : 20,
      ),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AdminUi.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < actions.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            SizedBox(width: double.infinity, child: actions[i]),
          ],
        ],
      ),
    );
  }
}
