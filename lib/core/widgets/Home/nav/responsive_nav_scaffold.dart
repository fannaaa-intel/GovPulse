// lib/core/widgets/Home/nav/responsive_nav_scaffold.dart
//
// Shared responsive chrome for the five top-level nav destinations
// (Home, My Reports, NewsFeed, Emergency, Settings).
//
// It reproduces the exact three-band behaviour that `home_screen.dart` uses
// inline, so every nav screen behaves identically instead of each re-inventing
// it:
//
//   • phone   (native, width < 600)  → bottom app nav  (AppBottomNav)
//   • drawer  (tablet / narrow web)  → side nav drawer (HomeNavDrawer) + slim app bar
//   • topNav  (width >= 900)         → horizontal top nav (HomeTopNav)
//
// Usage — wrap whatever used to be inside `Scaffold.body`:
//
//   return ResponsiveNavScaffold(
//     currentIndex: 1,                 // which destination this screen is
//     username: widget.username,
//     isVerified: true,
//     backgroundColor: const Color(0xFFF3F4F6),
//     body: SafeArea(child: Column(children: [ _header(w), Expanded(content) ])),
//   );
//
// Screens that have richer profile data (name / avatar / verify status) can
// pass `fullName`, `facePhotoUrl`, `verifStatus`. Screens that don't simply
// omit them and the header degrades gracefully. Notifications + logout are
// owned here so plain StatefulWidget screens don't have to wire them up.

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../network/network_wrapper.dart';
import '../../app_snackbar.dart';
import '../../../providers/user_profile_provider.dart';
import '../../../services/chat_service.dart';
import '../../../services/push_service.dart';
import '../../modal/verification_required_dialog.dart';
import '../../../../features/home/screen/home_screen.dart';
import '../../../../features/home/screen/notification_popup.dart';
import '../Chat-bubbles/home_chat_bubble.dart';
import '../home_enums.dart';

import 'app_bottom_nav.dart';
import 'home_nav_drawer.dart';
import 'home_top_nav.dart';

/// Which navigation chrome to show for a given viewport width.
enum NavBand { phone, drawer, topNav }

/// Width at/above which the horizontal top nav is shown (matches Home).
const double kNavTopBreakpoint = 900;

/// Width below which native mobile uses the bottom nav (matches Home).
const double kNavMobileBreakpoint = 600;

/// Mirror of the band logic in `home_screen.dart` (kIsWeb aware):
///   useMobile = !kIsWeb && width < 600
///   useTopNav = width >= 900
///   else      → drawer
NavBand resolveNavBand(double width) {
  if (width >= kNavTopBreakpoint) return NavBand.topNav;
  if (!kIsWeb && width < kNavMobileBreakpoint) return NavBand.phone;
  return NavBand.drawer;
}

class ResponsiveNavScaffold extends ConsumerWidget {
  /// 0 Home · 1 My Reports · 2 NewsFeed · 3 Emergency · 4 Settings
  final int currentIndex;
  final String username;
  final bool isVerified;
  final String? userBarangay;

  /// Everything that used to live inside the old `Scaffold.body`.
  final Widget body;

  // ── Chrome ────────────────────────────────────────────────────────────────
  final Color backgroundColor;
  final bool extendBody;

  /// When false (guest / signed-out contexts) no nav chrome is shown — just a
  /// plain Scaffold wrapping [body]. Lets guest screens reuse this wrapper.
  final bool showNav;

  /// Optional max width for the body in drawer / topNav bands. Defaults to
  /// unconstrained so a screen's existing layout is rendered byte-for-byte;
  /// pass e.g. 1100 to centre the content on large screens.
  final double maxContentWidth;

  // ── Optional richer header data ─────────────────────────────────────────────
  final String? fullName;
  final String? facePhotoUrl;

  /// If null, derived from [isVerified] (verified / none — no pending state).
  final VerifStatus? verifStatus;

  /// Override the shared logout if a screen needs special cleanup.
  final Future<void> Function(BuildContext context)? onLogout;

  const ResponsiveNavScaffold({
    super.key,
    required this.currentIndex,
    required this.username,
    required this.isVerified,
    required this.body,
    this.userBarangay,
    this.backgroundColor = const Color(0xFFF3F4F6),
    this.extendBody = true,
    this.showNav = true,
    this.maxContentWidth = 1100,
    this.fullName,
    this.facePhotoUrl,
    this.verifStatus,
    this.onLogout,
  });

  // ── Navigation (mirrors AppBottomNav._handleTap exactly) ───────────────────
  void _navigate(
    BuildContext context,
    int index, {
    String? effectiveBarangay,
    bool? effectiveIsVerified,
  }) {
    if (index == currentIndex) return;

    switch (index) {
      case 0:
        Navigator.pushAndRemoveUntil(
          context,
          PageRouteBuilder(
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
            pageBuilder: (_, _, _) =>
                NetworkWrapper(child: HomePage(username: username)),
            transitionsBuilder: (_, _, _, child) => child,
          ),
          (route) => false,
        );
        break;
      case 1:
        if (!(effectiveIsVerified ?? isVerified)) {
          showVerificationRequiredDialog(
            context,
            message: 'Only verified citizens can access My Reports.',
          );
          return;
        }
        Navigator.pushNamed(context, '/my_reports', arguments: username);
        break;
      case 2:
        Navigator.pushNamed(
          context,
          '/newsfeed',
          arguments: {
            'username': username,
            'isVerified': effectiveIsVerified ?? isVerified,
            'userBarangay': effectiveBarangay,
          },
        );
        break;
      case 3:
        Navigator.pushNamed(
          context,
          '/emergency',
          arguments: {
            'username': username,
            'isVerified': effectiveIsVerified ?? isVerified,
          },
        );
        break;
      case 4:
        Navigator.pushNamed(context, '/settings', arguments: username);
        break;
    }
  }

  // ── Notifications ──────────────────────────────────────────────────────────
  Future<void> _showNotifications(BuildContext context, double width) async {
    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Notifications',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (_, _, _) => NotificationPopup(width: width),
      transitionBuilder: (_, anim, _, child) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(
          scale: CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
          child: child,
        ),
      ),
    );
  }

  // ── Logout (mirrors Home / Settings) ───────────────────────────────────────
  Future<void> _handleLogout(BuildContext context) async {
    if (onLogout != null) {
      await onLogout!(context);
      return;
    }

    final shouldLogout = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.logout_rounded,
                  size: 28,
                  color: Color(0xFFEF4444),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Log Out?',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1F2937),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                "You'll need to sign in again to access your account.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF6B7280),
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFE5E7EB)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF374151),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEF4444),
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        'Log Out',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (shouldLogout != true || !context.mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: Color(0xFF1A4DB8)),
      ),
    );

    try {
      await PushService.I.unregister();
      await Supabase.instance.client.auth.signOut();
      await ChatService.I.clearOnLogout();
      HomeChatBubble.hideGlobal();
      if (!context.mounted) return;
      Navigator.pop(context); // close spinner
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
    } catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context);
      showAppSnackBar(context, 'Logout failed: $e', type: AppSnackType.error);
    }
  }

  // ── Body wrapper (optional max-width centring on wide bands) ────────────────
  Widget _constrained(BuildContext context, Widget child) {
    if (maxContentWidth == double.infinity) return child;
    final mq = MediaQuery.of(context);
    if (mq.size.width <= maxContentWidth) return child;
    // Centre the body in a fixed-width column on wide screens. Overriding the
    // MediaQuery width the body sees keeps its internal `width * 0.xx` sizing
    // self-consistent, so nothing overflows the narrower column. The stretched
    // Row keeps height bounded so Column/Expanded bodies still lay out.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Spacer(),
        SizedBox(
          width: maxContentWidth,
          child: MediaQuery(
            data: mq.copyWith(size: Size(maxContentWidth, mq.size.height)),
            child: child,
          ),
        ),
        const Spacer(),
      ],
    );
  }

  // ── Slim app bar shown in drawer band (mirrors Home._buildDrawerAppBar) ─────
  PreferredSizeWidget _drawerAppBar(BuildContext context, double width) {
    return AppBar(
      backgroundColor: Colors.white,
      foregroundColor: const Color(0xFF1F2937),
      elevation: 0,
      surfaceTintColor: Colors.white,
      iconTheme: const IconThemeData(color: Color(0xFF374151)),
      title: Image.asset(
        'assets/images/applogocrop.webp',
        height: 32,
        errorBuilder: (_, _, _) => const Text(
          'Aparri',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 18,
            color: Color(0xFF1F2937),
          ),
        ),
      ),
      shape: const Border(
        bottom: BorderSide(color: Color(0xFFE5E7EB), width: 1),
      ),
      actions: [
        IconButton(
          onPressed: () => _showNotifications(context, width),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              Image.asset(
                'assets/images/notifications.webp',
                width: 28,
                height: 28,
                errorBuilder: (_, _, _) =>
                    const Icon(Icons.notifications_outlined, size: 30),
              ),
              if (NotificationService.count > 0)
                Positioned(
                  right: -4,
                  top: -4,
                  child: Container(
                    constraints: const BoxConstraints(
                      minWidth: 14,
                      minHeight: 14,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF22C55E),
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(color: Colors.white, width: 1.2),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${NotificationService.count}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = MediaQuery.of(context).size.width;

    if (!showNav) {
      return Scaffold(
        extendBody: extendBody,
        backgroundColor: backgroundColor,
        body: body,
      );
    }

    final band = resolveNavBand(width);

    // Display fields (name / avatar / verify badge) are global to the signed-in
    // user, so prefer anything the screen passed explicitly but fall back to the
    // shared profile provider. This keeps the drawer / top-nav fully populated
    // even on plain StatefulWidget screens (My Reports, NewsFeed, Emergency)
    // that have no profile data of their own.
    final profile = ref.watch(userProfileProvider).valueOrNull;
    final effFullName = fullName ?? profile?.fullName;
    final effFacePhotoUrl = facePhotoUrl ?? profile?.facePhotoUrl;
    final VerifStatus effVerif =
        verifStatus ??
        profile?.verifStatus ??
        (isVerified ? VerifStatus.verified : VerifStatus.none);
    final String effVerifString = switch (effVerif) {
      VerifStatus.verified => 'approved',
      VerifStatus.pending => 'pending',
      VerifStatus.none => 'none',
    };
    // Barangay: prefer the value the screen passed in, fall back to the
    // profile provider so screens that don't receive userBarangay (Emergency,
    // Settings) still forward the correct barangay when the user taps NewsFeed.
    final effBarangay = userBarangay ?? profile?.barangay;
    // isVerified: same pattern — prefer the screen prop, fall back to the
    // profile provider so Emergency/Settings don't incorrectly block My Reports.
    final effIsVerified = effVerif == VerifStatus.verified;

    switch (band) {
      // ── Phone: identical to the previous AppBottomNav behaviour ───────────
      case NavBand.phone:
        return Scaffold(
          extendBody: extendBody,
          backgroundColor: backgroundColor,
          body: body,
          bottomNavigationBar: AppBottomNav(
            width: width,
            currentIndex: currentIndex,
            username: username,
            isVerified: effIsVerified,
            userBarangay: effBarangay,
          ),
        );

      // ── Tablet / narrow web: side drawer + slim app bar ───────────────────
      case NavBand.drawer:
        return Scaffold(
          extendBody: extendBody,
          backgroundColor: backgroundColor,
          appBar: _drawerAppBar(context, width),
          drawer: HomeNavDrawer(
            currentIndex: currentIndex,
            onTap: (i) => _navigate(
              context,
              i,
              effectiveBarangay: effBarangay,
              effectiveIsVerified: effIsVerified,
            ),
            username: username,
            fullName: effFullName,
            facePhotoUrl: effFacePhotoUrl,
            verifStatus: effVerif,
            onLogout: () => _handleLogout(context),
          ),
          body: _constrained(context, body),
        );

      // ── Desktop: horizontal top nav ───────────────────────────────────────
      case NavBand.topNav:
        return Scaffold(
          backgroundColor: backgroundColor,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              HomeTopNav(
                currentIndex: currentIndex,
                onTap: (i) => _navigate(
                  context,
                  i,
                  effectiveBarangay: effBarangay,
                  effectiveIsVerified: effIsVerified,
                ),
                notificationCount: NotificationService.count,
                onNotificationTap: () => _showNotifications(context, width),
                onLogoutTap: () => _handleLogout(context),
                compact: width < 1050,
                username: username,
                fullName: effFullName,
                facePhotoUrl: effFacePhotoUrl,
                verifStatus: effVerifString,
              ),
              Expanded(child: _constrained(context, body)),
            ],
          ),
        );
    }
  }
}
