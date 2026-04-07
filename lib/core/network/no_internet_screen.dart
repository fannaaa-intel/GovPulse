import 'package:flutter/material.dart';

class NoInternetScreen extends StatelessWidget {
  final bool hasInternet;
  final VoidCallback onContinue;

  const NoInternetScreen({
    super.key,
    required this.hasInternet,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 500),
          child: hasInternet
              ? const SizedBox.shrink()
              : const _NoInternetOverlay(key: ValueKey("no-internet")),
        ),
      ],
    );
  }
}

class _NoInternetOverlay extends StatefulWidget {
  const _NoInternetOverlay({super.key});

  @override
  State<_NoInternetOverlay> createState() => _NoInternetOverlayState();
}

class _NoInternetOverlayState extends State<_NoInternetOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  int dots = 1;

  @override
  void initState() {
    super.initState();

    /// smoother shimmer
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3500),
    )..repeat();

    _animateDots();
  }

  /// ✅ FIXED (ONLY CHANGE HERE)
  void _animateDots() async {
    while (true) {
      await Future.delayed(const Duration(milliseconds: 700));

      if (!mounted) break; // ✅ prevents setState after dispose

      setState(() {
        dots = dots % 3 + 1;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Material(
        color: Colors.transparent,
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFEAF2FB), Color(0xFFDCE9F8)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 60),

                  /// ICON
                  Container(
                    width: 130,
                    height: 130,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(40),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(
                            0xFF2D6CDF,
                          ).withValues(alpha: 0.15),
                          blurRadius: 25,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.wifi_off_rounded,
                      size: 65,
                      color: Color(0xFF2D6CDF),
                    ),
                  ),

                  const SizedBox(height: 40),

                  /// 🔥 SMOOTH SHIMMER "OOPS!"
                  AnimatedBuilder(
                    animation: _controller,
                    builder: (context, child) {
                      return ShaderMask(
                        shaderCallback: (bounds) {
                          return LinearGradient(
                            colors: const [
                              Color(0xFF2D6CDF),
                              Color(0xFF8BB8FF),
                              Color(0xFF2D6CDF),
                            ],
                            stops: [
                              (_controller.value - 0.2).clamp(0.0, 1.0),
                              _controller.value,
                              (_controller.value + 0.2).clamp(0.0, 1.0),
                            ],
                          ).createShader(bounds);
                        },
                        child: const Text(
                          "Oops!",
                          style: TextStyle(
                            fontSize: 52,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 28),

                  /// TITLE
                  const Text(
                    "No internet connection",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A2A4A),
                    ),
                  ),

                  const SizedBox(height: 12),

                  /// MESSAGE
                  const Text(
                    "We’ll reconnect you automatically as soon as possible.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: Colors.black54,
                    ),
                  ),

                  const SizedBox(height: 30),

                  /// STATUS
                  Text(
                    "Waiting for connection${"." * dots}",
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF2D6CDF),
                    ),
                  ),

                  const Spacer(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
