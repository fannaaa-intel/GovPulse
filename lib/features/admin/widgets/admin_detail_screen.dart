import 'package:flutter/material.dart';

import '../../../core/widgets/app_dialog.dart';
import '../theme/admin_ui.dart';
import 'admin_dialog_back.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Admin detail presentation
//
//  On small screens (web-narrow + the app) a detail is a FULL-SCREEN page with a
//  chevron header, pushed on an instant route so only the content animates —
//  it slides up on mount, matching the citizen-side sub-screens. On wide screens
//  it stays a centered dialog card.
// ════════════════════════════════════════════════════════════════════════════

/// Below this width a detail becomes a full-screen slide-up page.
const double kAdminDetailNarrowBelow = 640;

bool adminDetailIsNarrow(BuildContext context) =>
    MediaQuery.of(context).size.width < kAdminDetailNarrowBelow;

/// Present a detail. [builder] returns the SAME widget for both modes — that
/// widget decides its own narrow/wide layout via [adminDetailIsNarrow].
///   • narrow → instant full-screen route (content slides up itself)
///   • wide    → centered dialog card
///
/// Pass [barrierDismissible] `false` for a detail holding unsaved input, so a
/// stray click beside the card can't throw the work away.
Future<T?> showAdminDetail<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  if (adminDetailIsNarrow(context)) {
    return Navigator.of(context).push<T>(
      PageRouteBuilder<T>(
        // Instant IN (the screen appears with no page transition), fade OUT on
        // the way back — matching the citizen settings sub-screens. The content
        // does its own slide-up inside the screen (see AdminDetailScaffold), so
        // the opaque scaffold never flashes.
        transitionDuration: Duration.zero,
        reverseTransitionDuration: kAppDialogDuration,
        pageBuilder: (ctx, _, _) => builder(ctx),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }
  return showAppDialog<T>(
    context: context,
    builder: builder,
    barrierDismissible: barrierDismissible,
  );
}

/// Two detail panes side by side at a SHARED height — the wide layout for a
/// detail that splits into a main pane and a sidebar.
///
/// Both panes are stretched to the row's full height and each scrolls on its
/// own, so:
///   • the cards always read as a balanced pair — the shorter one grows to its
///     sibling's height instead of leaving a gap beneath it;
///   • a long pane scrolls without dragging the other one out of view.
///
/// Must be given a BOUNDED height (the stretch has nothing to measure against
/// otherwise). Intrinsics are deliberately not used: the panes contain
/// LayoutBuilders, which can't answer an intrinsic-height query.
class AdminTwoPaneRow extends StatelessWidget {
  final Widget main;
  final Widget side;
  final int mainFlex;
  final int sideFlex;
  final double gap;
  const AdminTwoPaneRow({
    super.key,
    required this.main,
    required this.side,
    this.mainFlex = 62,
    this.sideFlex = 38,
    this.gap = 14,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: mainFlex, child: _pane(main)),
        SizedBox(width: gap),
        Expanded(flex: sideFlex, child: _pane(side)),
      ],
    );
  }

  /// Fills the row's height, and scrolls only once the content outgrows it.
  static Widget _pane(Widget child) => LayoutBuilder(
        builder: (context, c) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: c.maxHeight),
            child: child,
          ),
        ),
      );
}

/// Rounded chevron back button + title, for the top of a full-screen detail
/// (mirrors the citizen settings sub-screens).
class AdminChevronHeader extends StatelessWidget {
  final String title;
  const AdminChevronHeader({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 16, 8),
      child: Row(
        children: [
          // The one back chip, not a second copy of it: this header used to
          // redraw AdminDialogBack's Material/InkWell/Container by hand, so
          // restyling "back" meant finding both.
          AdminDialogBack(onTap: () => Navigator.of(context).maybePop()),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              // Near-black, not the brand blue: with the chevron receding to
              // an outline, a blue title left the header reading as two
              // competing accents. Matches the Activity log / Recent activity
              // sheets, which already used AdminUi.textPrimary.
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AdminUi.textPrimary,
                letterSpacing: -0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Slides its child up (with a light fade) on first build — mirroring the
/// citizen settings sub-screens. IMPORTANT: place this BELOW the pinned header,
/// never around it: only the content should animate; the chevron header stays
/// put and the opaque background paints instantly (no black flash).
class AdminSlideUp extends StatefulWidget {
  final Widget child;
  const AdminSlideUp({super.key, required this.child});

  @override
  State<AdminSlideUp> createState() => _AdminSlideUpState();
}

class _AdminSlideUpState extends State<AdminSlideUp>
    with SingleTickerProviderStateMixin {
  // Values match the citizen sub-screens (e.g. AboutGovPulseScreen): a 420ms
  // easeOutCubic rise from 10% down, with a subtle 0.8→1.0 fade.
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  )..forward();

  late final Animation<Offset> _offset = Tween<Offset>(
    begin: const Offset(0, 0.10),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic));

  late final Animation<double> _fade = Tween<double>(
    begin: 0.8,
    end: 1.0,
  ).animate(CurvedAnimation(parent: _c, curve: Curves.easeOut));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _offset, child: widget.child),
    );
  }
}

/// Full-screen scaffold for a narrow detail: chevron header + slide-up body.
/// [child] fills the space below the header (give it an Expanded-friendly body).
class AdminDetailScaffold extends StatelessWidget {
  final String title;
  final Widget child;
  const AdminDetailScaffold({
    super.key,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    // Scaffold (opaque background) paints instantly. The chevron header is
    // PINNED — only the body below it slides up, exactly like the citizen
    // settings sub-screens (header stays put, content rises + fades in).
    return Scaffold(
      backgroundColor: AdminUi.surface,
      body: SafeArea(
        child: Column(
          children: [
            AdminChevronHeader(title: title),
            const Divider(height: 1, color: AdminUi.border),
            Expanded(child: AdminSlideUp(child: child)),
          ],
        ),
      ),
    );
  }
}
