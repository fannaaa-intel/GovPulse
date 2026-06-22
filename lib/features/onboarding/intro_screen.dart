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
    final size = MediaQuery.of(context).size;
    final w = size.width;
    final h = size.height;

    // ── Responsive tokens ──────────────────────────────────────────────────
    final bool isTablet = w >= 600;
    final double contentMax = isTablet ? 520.0 : w;

    // Spacing scales with height so short phones don't overflow
    final double topGap = (h * 0.034).clamp(12.0, 32.0);
    final double logoGap = (h * 0.030).clamp(10.0, 28.0);
    final double dotsGap = (h * 0.012).clamp(6.0, 14.0);
    final double bottomGap = (h * 0.028).clamp(10.0, 28.0);

    // Logo
    final double logoWidth = (w * 0.42).clamp(120.0, 220.0);

    // Button row
    final double btnRowH = (h * 0.072).clamp(48.0, 64.0);
    final double btnWidth = (w * 0.60).clamp(160.0, 280.0);
    final double arrowSize = (h * 0.072).clamp(48.0, 64.0);

    // Text sizes
    final double titleSize = isTablet ? 26.0 : (w < 360 ? 18.0 : 22.0);
    final double descSize = isTablet ? 16.0 : (w < 360 ? 13.0 : 15.0);
    final double btnLabelSz = isTablet ? 17.0 : 16.0;
    final double skipLabelSz = isTablet ? 17.0 : 16.0;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: contentMax),
            child: LayoutBuilder(
              builder: (context, c) {
                final double pageH = (c.maxHeight * 0.55).clamp(260.0, 480.0);
                return SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: c.maxHeight),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: isTablet ? 40 : 28,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(height: topGap),

                          // ── Logo ────────────────────────────────────────────────
                          Image.asset(
                            "assets/images/applogocrop.webp",
                            width: logoWidth,
                            filterQuality: FilterQuality.high,
                          ),

                          SizedBox(height: logoGap),

                          // ── PageView ─────────────────────────────────────────────
                          SizedBox(
                            height: pageH,
                            child: PageView.builder(
                              controller: _controller,
                              itemCount: pages.length,
                              physics: const BouncingScrollPhysics(),
                              onPageChanged: (i) =>
                                  setState(() => _currentPage = i),
                              itemBuilder: (context, index) => _buildPage(
                                index,
                                titleSize: titleSize,
                                descSize: descSize,
                              ),
                            ),
                          ),

                          SizedBox(height: dotsGap),

                          // ── Dots ─────────────────────────────────────────────────
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(
                              pages.length,
                              (i) => AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                ),
                                height: 8,
                                width: _currentPage == i ? 24 : 8,
                                decoration: BoxDecoration(
                                  color: _currentPage == i
                                      ? const Color(0xFF1A237E)
                                      : Colors.grey.shade400,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                              ),
                            ),
                          ),

                          SizedBox(height: dotsGap),

                          // ── Navigation row ───────────────────────────────────────
                          Padding(
                            padding: EdgeInsets.only(bottom: bottomGap),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                // Skip / Back
                                TextButton(
                                  onPressed: () {
                                    if (_currentPage == 0) {
                                      widget.onLoginClick();
                                    } else {
                                      _controller.previousPage(
                                        duration: const Duration(
                                          milliseconds: 500,
                                        ),
                                        curve: Curves.easeOutBack,
                                      );
                                    }
                                  },
                                  child: Text(
                                    _currentPage == 0 ? "Skip" : "Back",
                                    style: TextStyle(
                                      fontSize: skipLabelSz,
                                      fontWeight: FontWeight.w500,
                                      color: const Color(0xFF1A237E),
                                    ),
                                  ),
                                ),

                                // Next / Get Started
                                SizedBox(
                                  width: btnWidth,
                                  height: btnRowH,
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 450),
                                    switchInCurve: Curves.easeOutCubic,
                                    switchOutCurve: Curves.easeInCubic,
                                    layoutBuilder: (cur, prev) => Stack(
                                      alignment: Alignment.centerRight,
                                      children: [...prev, ?cur],
                                    ),
                                    transitionBuilder: (child, anim) {
                                      final isGet =
                                          child.key ==
                                          const ValueKey("getStarted");
                                      final slide = Tween<Offset>(
                                        begin: isGet
                                            ? const Offset(0.15, 0)
                                            : const Offset(-0.15, 0),
                                        end: Offset.zero,
                                      ).animate(anim);
                                      return FadeTransition(
                                        opacity: anim,
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
                                              backgroundColor: const Color(
                                                0xFF1A237E,
                                              ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(28),
                                              ),
                                              padding: EdgeInsets.symmetric(
                                                horizontal: isTablet ? 32 : 28,
                                                vertical: 14,
                                              ),
                                              elevation: 6,
                                            ),
                                            onPressed: widget.onSignUpClick,
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  "Get Started",
                                                  style: TextStyle(
                                                    fontSize: btnLabelSz,
                                                    fontWeight: FontWeight.w600,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                const Icon(
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
                                                duration: const Duration(
                                                  milliseconds: 500,
                                                ),
                                                curve: Curves.easeOutBack,
                                              );
                                            },
                                            child: Container(
                                              height: arrowSize,
                                              width: arrowSize,
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
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPage(
    int index, {
    required double titleSize,
    required double descSize,
  }) {
    final data = pages[index];

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        double page = 0;
        if (_controller.hasClients && _controller.position.haveDimensions) {
          page = _controller.page ?? 0;
        }
        final double offset = page - index;
        final double t = offset.abs().clamp(0.0, 1.0);
        final double smooth = Curves.easeOutCubic.transform(t);
        final double spring = math.sin((1 - t) * math.pi) * 0.018;
        final double translateX = offset * 52;
        final double scale = (1 - (smooth * 0.06)) + spring;
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
                      colorFilter: const ColorFilter.mode(
                        Color(0xFFF4F7FB),
                        BlendMode.modulate,
                      ),
                      child: Image.asset(
                        data["image"]!,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                        gaplessPlayback: true,
                      ),
                    ),
                  ),
                  SizedBox(
                    height: (MediaQuery.of(context).size.height * 0.030).clamp(
                      12.0,
                      28.0,
                    ),
                  ),
                  Text(
                    data["title"]!,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: titleSize,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                      color: const Color(0xFF1A237E),
                    ),
                  ),
                  SizedBox(
                    height: (MediaQuery.of(context).size.height * 0.018).clamp(
                      8.0,
                      16.0,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      data["desc"]!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: descSize,
                        height: 1.7,
                        fontWeight: FontWeight.w400,
                        color: const Color(0xFF4A4A4A),
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
