import 'dart:math' as math;
import 'package:flutter/material.dart';

class IntroScreen extends StatefulWidget {
  final VoidCallback onSignUpClick;
  final VoidCallback onLoginClick;

  const IntroScreen({
    super.key,
    required this.onSignUpClick,
    required this.onLoginClick,
  });

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen>
    with SingleTickerProviderStateMixin {
  final PageController _controller = PageController();

  int _currentPage = 0;

  late AnimationController _arrowController;
  late Animation<double> _arrowScale;

  final List<Map<String, String>> pages = [
    {
      "image": "assets/images/onboard1.gif",
      "title": "Your LGU in One App",
      "desc":
          "Your all-in-one app for Aparri.\nGet news, access LGU services, send reports, and share feedback — all in one place.",
    },
    {
      "image": "assets/images/onboard2.gif",
      "title": "Stay Updated & Connected",
      "desc":
          "Receive official updates instantly.\nSubmit concerns, track reports, and connect with your local government easily.",
    },
    {
      "image": "assets/images/onboard3.gif",
      "title": "Better Services for Everyone",
      "desc":
          "Your feedback improves public services.\nTogether, we build a faster, more responsive, connected community.",
    },
  ];

  @override
  void initState() {
    super.initState();

    _arrowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );

    _arrowScale = Tween<double>(
      begin: 1.0,
      end: 1.15,
    ).animate(CurvedAnimation(parent: _arrowController, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    _arrowController.dispose();
    super.dispose();
  }

  void _animateArrow() async {
    await _arrowController.forward();
    await _arrowController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              const SizedBox(height: 28),

              Image.asset(
                "assets/images/applogocrop.png",
                width: MediaQuery.of(context).size.width * 0.42,
              ),

              const SizedBox(height: 30),

              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: pages.length,
                  physics: const BouncingScrollPhysics(),
                  onPageChanged: (index) {
                    setState(() => _currentPage = index);
                  },
                  itemBuilder: (context, index) {
                    return _buildPage(index);
                  },
                ),
              ),

              const SizedBox(height: 10),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  pages.length,
                  (index) => AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.symmetric(horizontal: 5),
                    height: 8,
                    width: _currentPage == index ? 24 : 8,
                    decoration: BoxDecoration(
                      color: _currentPage == index
                          ? const Color(0xFF1A237E)
                          : Colors.grey.shade400,
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 22),

              Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: () {
                        if (_currentPage == 0) {
                          widget.onLoginClick();
                        } else {
                          _controller.previousPage(
                            duration: const Duration(milliseconds: 500),
                            curve: Curves.easeOutBack, // keep bouncy feel
                          );
                        }
                      },
                      child: Text(
                        _currentPage == 0 ? "Skip" : "Back",
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF1A237E),
                        ),
                      ),
                    ),

                    SizedBox(
                      width: MediaQuery.of(context).size.width * 0.6,
                      height: 56,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 450),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        layoutBuilder: (currentChild, previousChildren) =>
                            Stack(
                              alignment: Alignment.centerRight,
                              children: [...previousChildren, ?currentChild],
                            ),
                        transitionBuilder: (child, animation) {
                          final isGetStarted =
                              child.key == const ValueKey("getStarted");

                          final slide = Tween<Offset>(
                            begin: isGetStarted
                                ? const Offset(0.15, 0)
                                : const Offset(-0.15, 0),
                            end: Offset.zero,
                          ).animate(animation);

                          return FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: slide,
                              child: child,
                            ),
                          );
                        },
                        child: _currentPage == pages.length - 1
                            ? ElevatedButton(
                                key: const ValueKey("getStarted"),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF1A237E),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(28),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 28,
                                    vertical: 14,
                                  ),
                                  elevation: 6,
                                ),
                                onPressed: widget.onSignUpClick,
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      "Get Started",
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ),
                                    SizedBox(width: 8),
                                    Icon(
                                      Icons.arrow_forward,
                                      color: Colors.white,
                                    ),
                                  ],
                                ),
                              )
                            : GestureDetector(
                                key: const ValueKey("arrow"),
                                onTap: () {
                                  _animateArrow();
                                  _controller.nextPage(
                                    duration: const Duration(milliseconds: 500),
                                    curve: Curves.easeOutBack, // keep bounce
                                  );
                                },
                                child: Container(
                                  height: 56,
                                  width: 56,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF1A237E),
                                    shape: BoxShape.circle,
                                  ),
                                  child: ScaleTransition(
                                    scale: _arrowScale,
                                    child: const Icon(
                                      Icons.arrow_forward,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPage(int index) {
    final data = pages[index];

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        double page = 0;

        if (_controller.hasClients && _controller.position.haveDimensions) {
          page = _controller.page ?? 0;
        }

        final double offset = page - index;

        // 0..1 progress away from center
        final double t = offset.abs().clamp(0.0, 1.0);

        // Premium smooth base easing
        final double smooth = Curves.easeOutCubic.transform(t);

        // Subtle spring/bounce (gentle, premium)
        // Peaks near mid-swipe and fades to 0 at edges/center.
        final double spring = math.sin((1 - t) * math.pi) * 0.018;

        // Gentle parallax slide (smoother, less harsh than 60)
        final double translateX = offset * 52;

        // Keep your depth effect, plus tiny spring overshoot
        final double scale = (1 - (smooth * 0.06)) + spring;

        // Smooth fade
        final double opacity = 1 - (smooth * 0.38);

        return Transform.translate(
          offset: Offset(translateX, 0),
          child: Transform.scale(
            scale: scale,
            child: Opacity(
              opacity: opacity.clamp(0.0, 1.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(
                    flex: 5,
                    child: ColorFiltered(
                      // KEEP your background removal exactly
                      colorFilter: const ColorFilter.mode(
                        Color(0xFFF4F7FB),
                        BlendMode.modulate,
                      ),
                      child: Image.asset(data["image"]!, fit: BoxFit.contain),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    data["title"]!,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                      color: Color(0xFF1A237E),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      data["desc"]!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 15,
                        height: 1.7,
                        fontWeight: FontWeight.w400,
                        color: Color(0xFF4A4A4A),
                      ),
                    ),
                  ),
                  const Spacer(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
