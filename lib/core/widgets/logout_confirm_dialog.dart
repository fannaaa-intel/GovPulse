import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'logout_control.dart';
import 'app_dialog.dart';
import '../../core/theme/citizen_ui.dart';

/// A single, clean logout confirmation shared across the citizen app, admin
/// console and staff console, so the experience is identical everywhere.
///
/// Shows a red logout glyph in a soft circle at the top. Returns `true` when
/// the user confirms the logout.
Future<bool> showLogoutConfirmDialog(
  BuildContext context, {
  String message = "You'll need to sign in again to access your account.",
}) async {
  final result = await showAppDialog<bool>(
    context: context,
    barrierColor: Colors.black54,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      // Web trims to the shared scale in app_dialog.dart so this and the
      // verification/success dialogs are one size; the app keeps its own.
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kIsWeb ? kWebDialogRadius : 20),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kWebDialogMaxWidth),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 26, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: kIsWeb ? kWebDialogIcon : 64,
                height: kIsWeb ? kWebDialogIcon : 64,
                decoration: BoxDecoration(
                  color: AppColors.red.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.logout_rounded,
                  size: kIsWeb ? kWebDialogGlyph : 30,
                  color: AppColors.red,
                ),
              ),
              SizedBox(height: kIsWeb ? kWebDialogGapIcon : 18),
              Text(
                'Log Out?',
                style: TextStyle(
                  fontSize: kIsWeb ? kWebDialogTitle : 21,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1F2937),
                ),
              ),
              SizedBox(height: kIsWeb ? kWebDialogGapTitle : 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: kWebDialogBody,
                  height: 1.45,
                  color: Color(0xFF6B7280),
                ),
              ),
              SizedBox(height: kIsWeb ? kWebDialogGapActions : 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: CitizenUi.sharedStroke),
                        padding: EdgeInsets.symmetric(
                          vertical: kIsWeb ? kWebDialogButtonPadV : 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            kIsWeb ? kWebDialogButtonRadius : 12,
                          ),
                        ),
                      ),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          fontSize: kIsWeb ? kWebDialogButtonFont : 14.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF374151),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: kIsWeb ? kWebDialogButtonGap : 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.red,
                        elevation: 0,
                        padding: EdgeInsets.symmetric(
                          vertical: kIsWeb ? kWebDialogButtonPadV : 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            kIsWeb ? kWebDialogButtonRadius : 12,
                          ),
                        ),
                      ),
                      child: Text(
                        kLogoutLabel,
                        style: TextStyle(
                          fontSize: kIsWeb ? kWebDialogButtonFont : 14.5,
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
    ),
  );
  return result == true;
}

/// The branded "Signing you out" overlay shown while the sign-out is in flight —
/// state 2 of the logout flow, shared by the citizen app, admin console and
/// staff console so the wait looks the same everywhere.
///
/// Drop it into a [showAppDialog] `builder` (which supplies the frosted, blurred
/// backdrop) instead of a bare [CircularProgressIndicator]. The caller still
/// owns the route: pop it when the sign-out finishes or fails.
///
/// No card, no container: just the GovPulse mark inside a slow brand-gradient
/// ring with two lines of text, floating directly on the frosted backdrop. The
/// [Material] wrapper is what gives the text a real style — a dialog builder
/// returning bare [Text] otherwise falls back to the framework's yellow
/// double-underlined error style.
class LogoutLoadingOverlay extends StatelessWidget {
  const LogoutLoadingOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    // Keep everything comfortably inside the smallest dimension so the overlay
    // never clips in landscape or on tiny screens; SafeArea guards notches.
    final shortest = MediaQuery.of(context).size.shortestSide;
    final compact = shortest < 340;

    return Material(
      type: MaterialType.transparency,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _BrandSpinner(size: compact ? 72 : 84),
                SizedBox(height: compact ? 20 : 24),
                Text(
                  'Signing you out',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: compact ? 16 : 17.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Ending your session securely',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: compact ? 12 : 13,
                    height: 1.4,
                    fontWeight: FontWeight.w400,
                    color: Colors.white.withValues(alpha: 0.75),
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The GovPulse mark centred in a slowly rotating brand-gradient arc. The ring
/// carries the "still working" signal; the logo carries the identity.
class _BrandSpinner extends StatefulWidget {
  final double size;
  const _BrandSpinner({this.size = 84});

  @override
  State<_BrandSpinner> createState() => _BrandSpinnerState();
}

class _BrandSpinnerState extends State<_BrandSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final logo = size * 0.69; // white disc sits inside the ring's track
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          RepaintBoundary(
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) => CustomPaint(
                size: Size(size, size),
                painter: _RingPainter(_c.value * 2 * math.pi),
              ),
            ),
          ),
          ClipOval(
            child: Container(
              width: logo,
              height: logo,
              color: Colors.white,
              padding: EdgeInsets.all(logo * 0.1),
              child: Image.asset(
                'assets/images/applogocrop.webp',
                fit: BoxFit.contain,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A rounded arc sweeping the brand blue→green gradient, rotated by [rotation].
/// A faint full track underneath keeps the ring visible where the arc isn't.
class _RingPainter extends CustomPainter {
  final double rotation;
  const _RingPainter(this.rotation);

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 4.0;
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - stroke) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = Colors.white.withValues(alpha: 0.08);
    canvas.drawCircle(center, radius, track);

    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = const SweepGradient(
        colors: [AppColors.primaryBlue, AppColors.green, AppColors.primaryBlue],
      ).createShader(rect);

    // ~70% of the circle, rotating — a clear moving gap reads as progress.
    canvas.drawArc(rect, rotation, math.pi * 1.4, false, arc);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.rotation != rotation;
}
