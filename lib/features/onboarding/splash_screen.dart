import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../onboarding/intro_screen.dart';
import '../../core/network/connectivity_service.dart';
import '../../core/network/network_wrapper.dart';
import '../../core/network/no_internet_screen.dart';

/// ===============================
/// SPLASH SCREEN
/// ===============================
class GovPulseSplashScreen extends StatefulWidget {
  const GovPulseSplashScreen({super.key});

  @override
  State<GovPulseSplashScreen> createState() => _GovPulseSplashScreenState();
}

class _GovPulseSplashScreenState extends State<GovPulseSplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  late final Animation<double> _containerScale;
  late final Animation<double> _logoScale;
  late final Animation<double> _textSlide;
  late final Animation<double> _floodProgress;

  bool _showLoader = false;
  bool _goOffline = false;

  late final TextPainter _textPainter;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3400),
    );

    _containerScale = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.28, curve: Curves.easeOutBack),
    );

    _logoScale = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.2, 0.5, curve: Curves.easeOutExpo),
    );

    _textSlide = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.35, 0.65, curve: Curves.easeOutCubic),
    );

    _floodProgress = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.55, 1.0, curve: Curves.easeInOutCubic),
    );

    _textPainter = TextPainter(
      text: const TextSpan(
        text: "GovPulse",
        style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    _start();
  }

  PageRoute _buildIntroRoute() {
    return PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 900),
      reverseTransitionDuration: const Duration(milliseconds: 600),
      pageBuilder: (context, animation, secondaryAnimation) {
        return IntroScreen(
          onSignUpClick: () {
            Navigator.pushNamed(context, '/signup');
          },
          onLoginClick: () {
            Navigator.pushNamed(context, '/login');
          },
        );
      },
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeInOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 1.02, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  Future<void> _start() async {
    try {
      bool online = false;

      // Animation + internet check race together
      await Future.wait<void>([
        _controller.forward(),
        hasRealInternet().then((result) => online = result),
      ]);

      if (!mounted) return;

      // Animation is 100% done — NOW decide
      cachedInternetStatus = online;

      if (!online) {
        setState(
          () => _goOffline = true,
        ); // shows NoInternetScreen (full replace)
        _waitForInternet();
        return;
      }

      // Online path — show loader then navigate
      setState(() => _showLoader = true);
      await Future.delayed(const Duration(milliseconds: 800));
      if (!mounted) return;

      Navigator.of(context).pushReplacement(_buildIntroRoute());
    } catch (_) {}
  }

  Future<void> _waitForInternet() async {
    while (mounted) {
      await Future.delayed(const Duration(seconds: 3));
      final online = await hasRealInternet();
      if (online && mounted) {
        cachedInternetStatus = true;
        Navigator.of(context).pushReplacementNamed('/login');
        return;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ── Offline: shown AFTER animation completes ──
    if (_goOffline) {
      return const NoInternetScreen(hasInternet: false, onContinue: null);
    }

    final media = MediaQuery.of(context);
    final size = media.size;
    final safeBottom = media.padding.bottom;
    final textRowHeight = _textPainter.height;

    return Scaffold(
      body: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final flood = _floodProgress.value;

            final gradientOpacity = 1 - ((flood - 0.9) / 0.1).clamp(0.0, 1.0);

            final whiteFade = Curves.easeInOut.transform(
              ((flood - 0.8) / 0.2).clamp(0.0, 1.0),
            );

            final bloomGlow = Curves.easeOut.transform(
              ((flood - 0.82) / 0.18).clamp(0.0, 1.0),
            );

            final settleScale =
                1 + (sin(flood * pi) * 0.02 * pow(1 - flood, 1.4));

            final subtleFloat = -8 * ((flood - 0.8).clamp(0.0, 0.2) / 0.2);

            final textColorProgress = ((flood - 0.7) / 0.3).clamp(0.0, 1.0);

            final shimmer = (sin(_controller.value * pi * 3) * 0.03).clamp(
              -0.015,
              0.015,
            );

            final translateY = -35 + subtleFloat;

            final containerCenter = Offset(
              size.width / 2,
              (size.height / 2) + translateY - (12 + textRowHeight / 2),
            );

            final maxRadius = [
              (Offset.zero - containerCenter).distance,
              (Offset(size.width, 0) - containerCenter).distance,
              (Offset(0, size.height) - containerCenter).distance,
              (Offset(size.width, size.height) - containerCenter).distance,
            ].reduce(max);

            return Stack(
              children: [
                // ── Gradient background ──
                Opacity(
                  opacity: gradientOpacity,
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Color(0xFF00448F),
                          Color(0xFF2380C3),
                          Color(0xFF2A9648),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                  ),
                ),

                // ── Radial wave burst ──
                if (flood > 0 && flood < 1)
                  SizedBox.expand(
                    child: CustomPaint(
                      painter: RadialWaveBurstPainter(
                        progress: flood,
                        center: containerCenter,
                        maxRadius: maxRadius,
                      ),
                    ),
                  ),

                // ── White fade overlay ──
                Opacity(
                  opacity: whiteFade,
                  child: Container(color: Colors.white),
                ),

                // ── Bloom glow ──
                if (bloomGlow > 0)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: bloomGlow * 0.12,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: RadialGradient(
                              center: Alignment(
                                (containerCenter.dx / size.width) * 2 - 1,
                                (containerCenter.dy / size.height) * 2 - 1,
                              ),
                              radius: 0.8 + bloomGlow * 0.6,
                              colors: [
                                Colors.white,
                                Colors.white.withValues(alpha: 0.6),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                // ── Logo + text ──
                Center(
                  child: Transform.translate(
                    offset: Offset(0, translateY),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Transform.scale(
                          scale:
                              (_containerScale.value *
                                  (1 + flood * 0.025) *
                                  settleScale) +
                              shimmer,
                          child: Container(
                            width: 104,
                            height: 104,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(26),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(
                                    alpha: (0.05 + (whiteFade * 0.15)),
                                  ),
                                  blurRadius: 24 + (whiteFade * 20),
                                  offset: Offset(0, 8 + (whiteFade * 6)),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(26),
                              child: Center(
                                child: Transform.scale(
                                  scale: _logoScale.value,
                                  child: Image.asset(
                                    'assets/images/applogo.png',
                                    width: 70,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildText(
                              text: "Gov",
                              slide: -60,
                              progress: _textSlide.value,
                              color: Color.lerp(
                                Colors.white,
                                const Color(0xFF00448F),
                                textColorProgress,
                              )!,
                              letterSpacing: 1.2 * textColorProgress,
                            ),
                            _buildText(
                              text: "Pulse",
                              slide: 60,
                              progress: _textSlide.value,
                              color: Color.lerp(
                                Colors.white,
                                const Color(0xFF2A9648),
                                textColorProgress,
                              )!,
                              letterSpacing: 1.2 * textColorProgress,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Loader ──
                if (_showLoader)
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: EdgeInsets.only(bottom: safeBottom + 85),
                      child: const SizedBox(
                        width: 42,
                        height: 42,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.6,
                          valueColor: AlwaysStoppedAnimation(Color(0xFF00448F)),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildText({
    required String text,
    required double slide,
    required double progress,
    required Color color,
    required double letterSpacing,
  }) {
    return Transform.translate(
      offset: Offset(slide * (1 - progress), 0),
      child: Opacity(
        opacity: progress,
        child: Text(
          text,
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: color,
            letterSpacing: letterSpacing,
          ),
        ),
      ),
    );
  }
}

/// ===============================
/// ENHANCED WAVE PAINTER
/// ===============================
class RadialWaveBurstPainter extends CustomPainter {
  final double progress;
  final Offset center;
  final double maxRadius;

  RadialWaveBurstPainter({
    required this.progress,
    required this.center,
    required this.maxRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final eased = const Cubic(0.16, 1.0, 0.3, 1.0).transform(progress);

    final snappedCenter = Offset(
      center.dx.roundToDouble(),
      center.dy.roundToDouble(),
    );

    final radius = maxRadius * eased;

    final outerGlow = Paint()
      ..isAntiAlias = true
      ..shader =
          RadialGradient(
            colors: [
              Colors.white.withValues(alpha: 0.18 * (1 - progress)),
              Colors.white.withValues(alpha: 0.08 * (1 - progress)),
              Colors.transparent,
            ],
          ).createShader(
            Rect.fromCircle(center: snappedCenter, radius: radius * 1.4),
          );

    canvas.drawCircle(snappedCenter, radius * 1.4, outerGlow);

    final fillPaint = Paint()
      ..isAntiAlias = true
      ..shader = RadialGradient(
        colors: [
          Colors.white,
          Colors.white.withValues(alpha: 0.98),
          Colors.white.withValues(alpha: 0.92),
        ],
      ).createShader(Rect.fromCircle(center: snappedCenter, radius: radius));

    canvas.drawCircle(snappedCenter, radius, fillPaint);
  }

  @override
  bool shouldRepaint(covariant RadialWaveBurstPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.center != center ||
      oldDelegate.maxRadius != maxRadius;
}
