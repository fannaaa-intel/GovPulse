import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/facebook_signin_service.dart';
import '../../theme/app_colors.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Facebook auth UX helpers (shared by Login + Sign-up — the flow is identical)
//
//  • facebookSignInDetectingCancel() — runs the OAuth flow but resolves promptly
//    when the user backs out of the external browser, instead of leaving the UI
//    on a spinner for the service's 60s safety-net.
//  • FacebookAuthOverlay — a blocking "Connecting to Facebook" spinner shown over
//    the login/sign-up screen while the whole process finishes, so the user
//    never sees the auth screen flash back mid-flight.
// ════════════════════════════════════════════════════════════════════════════

/// Runs Facebook OAuth and returns the signed-in [User], or `null` if the user
/// cancelled (backed out of the browser). Rethrows a genuine sign-in error.
///
/// Cancellation is inferred from the app lifecycle: if we come back to the
/// foreground from the Facebook browser and no sign-in lands within a short
/// grace window, the user backed out — so we resolve as a cancel right away
/// rather than waiting for the 60-second safety-net inside the service.
Future<User?> facebookSignInDetectingCancel() {
  final result = Completer<User?>();
  Timer? grace;
  AppLifecycleListener? lifecycle;

  void finish({User? user, Object? error}) {
    if (result.isCompleted) return;
    grace?.cancel();
    lifecycle?.dispose();
    if (error != null) {
      result.completeError(error);
    } else {
      result.complete(user);
    }
  }

  lifecycle = AppLifecycleListener(
    onStateChange: (state) {
      if (state == AppLifecycleState.resumed) {
        // Give the sign-in event a moment to land after returning from the
        // browser; if it doesn't, treat it as a cancel.
        grace?.cancel();
        grace = Timer(const Duration(seconds: 3), () => finish(user: null));
      }
    },
  );

  FacebookSignInService.signIn().then(
    (user) => finish(user: user),
    onError: (Object e) {
      // The service reports a genuine back-out as "…cancelled."; treat that as a
      // silent cancel, and surface anything else as a real error.
      final cancelled = e.toString().toLowerCase().contains('cancel');
      finish(user: null, error: cancelled ? null : e);
    },
  );

  return result.future;
}

/// Full-screen blocking overlay shown while Facebook sign-in/sign-up is in
/// progress. Drop it into a [Stack] above the auth screen while a busy flag is
/// set. Absorbs input and swallows the back button so nothing underneath can be
/// tapped mid-flight.
class FacebookAuthOverlay extends StatelessWidget {
  /// The reassuring line under the title.
  final String message;
  const FacebookAuthOverlay({
    super.key,
    this.message = 'Hold on while we finish signing you in',
  });

  static const Color _fbBlue = Color(0xFF1877F2);
  static const Color _heading = Color(0xFF1F2937);

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      // A Material ancestor gives the text a real style + baseline. Without it,
      // Flutter paints the debug "yellow underline" under every line (the
      // yellow marks in the old design).
      child: Material(
        type: MaterialType.transparency,
        child: PopScope(
          canPop: false,
          child: Stack(
            children: [
              // Full-screen frosted backdrop: blur the login/sign-up screen and
              // lay a light scrim over it, so this reads as an immersive
              // "working…" state (no floating card) while keeping soft context
              // of the screen behind. The blur covers whatever is painted below
              // it in the Stack (the auth screen).
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: ColoredBox(
                    color: Colors.white.withValues(alpha: 0.62),
                  ),
                ),
              ),
              // Absorb every tap + block the back button so nothing underneath
              // can be interacted with mid-flight.
              const ModalBarrier(color: Colors.transparent, dismissible: false),
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // GovPulse logomark — reuse the app's existing mark asset.
                      Image.asset(
                        'assets/images/applogocrop.webp',
                        height: 34,
                        filterQuality: FilterQuality.medium,
                      ),
                      const SizedBox(height: 24),
                      // Facebook-blue ring on a light track, with the Facebook
                      // mark centred inside it.
                      SizedBox(
                        width: 60,
                        height: 60,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            const SizedBox.expand(
                              child: CircularProgressIndicator(
                                value: 1,
                                strokeWidth: 3,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  AppColors.stroke,
                                ),
                              ),
                            ),
                            const SizedBox.expand(
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(_fbBlue),
                              ),
                            ),
                            const Icon(
                              Icons.facebook,
                              size: 28,
                              color: _fbBlue,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Connecting to Facebook',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: _heading,
                          decoration: TextDecoration.none,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          fontWeight: FontWeight.w400,
                          color: AppColors.hint,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
