import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../theme/admin_ui.dart';

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
Future<T?> showAdminDetail<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  if (adminDetailIsNarrow(context)) {
    return Navigator.of(context).push<T>(
      PageRouteBuilder<T>(
        opaque: true,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (ctx, _, _) => builder(ctx),
      ),
    );
  }
  return showDialog<T>(
    context: context,
    barrierColor: Colors.black54,
    builder: builder,
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
          Material(
            color: AdminUi.subtle,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => Navigator.of(context).maybePop(),
              child: Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AdminUi.border),
                ),
                child: const Icon(
                  Icons.chevron_left_rounded,
                  size: 24,
                  color: AppColors.primaryBlue,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.primaryBlue,
                letterSpacing: -0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Slides its child up (with a light fade) on first build. Use inside an instant
/// (Duration.zero) route so the route swap is instant and only the content
/// animates — the citizen-side feel.
class AdminSlideUp extends StatefulWidget {
  final Widget child;
  const AdminSlideUp({super.key, required this.child});

  @override
  State<AdminSlideUp> createState() => _AdminSlideUpState();
}

class _AdminSlideUpState extends State<AdminSlideUp>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  )..forward();

  late final Animation<Offset> _offset = Tween<Offset>(
    begin: const Offset(0, 0.08),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic));

  late final Animation<double> _fade = CurvedAnimation(
    parent: _c,
    curve: Curves.easeOut,
  );

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
    return AdminSlideUp(
      child: Scaffold(
        backgroundColor: AdminUi.surface,
        body: SafeArea(
          child: Column(
            children: [
              AdminChevronHeader(title: title),
              const Divider(height: 1, color: AdminUi.border),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}
