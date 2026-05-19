import 'package:flutter/material.dart';

enum SkeletonLayout { none, home, settings }

// ── Main widget ───────────────────────────────────────────────────────────────
class LoadingOverlay extends StatelessWidget {
  final bool isLoading;
  final Widget child;
  final Color barrierColor;
  final Widget? loadingIndicator;
  final SkeletonLayout skeletonLayout;

  const LoadingOverlay({
    super.key,
    required this.isLoading,
    required this.child,
    this.barrierColor = const Color(0x55000000),
    this.loadingIndicator,
    this.skeletonLayout = SkeletonLayout.none,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading && skeletonLayout != SkeletonLayout.none) {
      return _SkeletonScreen(layout: skeletonLayout);
    }

    return Stack(
      children: [
        child,
        if (isLoading)
          Positioned.fill(
            child: _LoadingBarrier(
              color: barrierColor,
              indicator: loadingIndicator ?? const _DefaultSpinner(),
            ),
          ),
      ],
    );
  }
}

// ── Barrier (spinner overlay) ─────────────────────────────────────────────────
class _LoadingBarrier extends StatefulWidget {
  final Color color;
  final Widget indicator;

  const _LoadingBarrier({required this.color, required this.indicator});

  @override
  State<_LoadingBarrier> createState() => _LoadingBarrierState();
}

class _LoadingBarrierState extends State<_LoadingBarrier>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..forward();
    _fadeAnim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnim,
      child: AbsorbPointer(
        absorbing: true,
        child: Container(
          color: widget.color,
          alignment: Alignment.center,
          child: widget.indicator,
        ),
      ),
    );
  }
}

// ── Default spinner ───────────────────────────────────────────────────────────
class _DefaultSpinner extends StatelessWidget {
  const _DefaultSpinner();

  @override
  Widget build(BuildContext context) {
    return const CircularProgressIndicator(
      strokeWidth: 3,
      color: Color(0xFF1D4ED8),
    );
  }
}

// ── Shimmer box ───────────────────────────────────────────────────────────────
class _Shimmer extends StatefulWidget {
  final double width;
  final double height;
  final double radius;

  const _Shimmer({required this.width, required this.height, this.radius = 8});

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, _) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius),
          gradient: LinearGradient(
            begin: Alignment(-1.5 + _anim.value * 3, 0),
            end: Alignment(-0.5 + _anim.value * 3, 0),
            colors: const [
              Color(0xFFE5E7EB),
              Color(0xFFF3F4F6),
              Color(0xFFE5E7EB),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Skeleton screen router ────────────────────────────────────────────────────
class _SkeletonScreen extends StatelessWidget {
  final SkeletonLayout layout;
  const _SkeletonScreen({required this.layout});

  @override
  Widget build(BuildContext context) {
    return layout == SkeletonLayout.home
        ? const _HomeSkeletonScreen()
        : const _SettingsSkeletonScreen();
  }
}

// ── Home skeleton ─────────────────────────────────────────────────────────────
class _HomeSkeletonScreen extends StatelessWidget {
  const _HomeSkeletonScreen();

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final h = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header image
              _Shimmer(width: double.infinity, height: w * 0.52, radius: 0),

              Padding(
                padding: EdgeInsets.symmetric(horizontal: w * 0.04),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: w * 0.02),

                    // Profile card
                    Container(
                      padding: EdgeInsets.all(w * 0.04),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(w * 0.04),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              _Shimmer(
                                width: w * 0.18,
                                height: w * 0.18,
                                radius: w * 0.09,
                              ),
                              SizedBox(width: w * 0.04),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _Shimmer(width: w * 0.40, height: w * 0.04),
                                  SizedBox(height: w * 0.02),
                                  _Shimmer(width: w * 0.28, height: w * 0.03),
                                  SizedBox(height: w * 0.025),
                                  _Shimmer(
                                    width: w * 0.22,
                                    height: w * 0.06,
                                    radius: w * 0.03,
                                  ),
                                ],
                              ),
                            ],
                          ),
                          SizedBox(height: w * 0.04),
                          _Shimmer(
                            width: double.infinity,
                            height: w * 0.12,
                            radius: w * 0.03,
                          ),
                        ],
                      ),
                    ),

                    SizedBox(height: w * 0.05),

                    // Section label
                    _Shimmer(width: w * 0.35, height: w * 0.035),
                    SizedBox(height: w * 0.03),

                    // Community cards
                    Row(
                      children: List.generate(
                        3,
                        (i) => Padding(
                          padding: EdgeInsets.only(right: i < 2 ? w * 0.03 : 0),
                          child: _Shimmer(
                            width: (w - w * 0.08 - w * 0.06) / 3,
                            height: w * 0.32,
                            radius: w * 0.03,
                          ),
                        ),
                      ),
                    ),

                    SizedBox(height: w * 0.05),

                    // Quick actions label
                    _Shimmer(width: w * 0.30, height: w * 0.035),
                    SizedBox(height: w * 0.03),

                    // Quick action chips
                    Row(
                      children: List.generate(
                        3,
                        (i) => Padding(
                          padding: EdgeInsets.only(right: i < 2 ? w * 0.03 : 0),
                          child: Column(
                            children: [
                              _Shimmer(
                                width: w * 0.20,
                                height: w * 0.20,
                                radius: w * 0.04,
                              ),
                              SizedBox(height: w * 0.02),
                              _Shimmer(width: w * 0.16, height: w * 0.025),
                            ],
                          ),
                        ),
                      ),
                    ),

                    SizedBox(height: h * 0.04),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: Container(
        height: w * 0.18,
        color: Colors.white,
        padding: EdgeInsets.symmetric(horizontal: w * 0.04, vertical: w * 0.03),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: List.generate(
            5,
            (_) =>
                _Shimmer(width: w * 0.10, height: w * 0.10, radius: w * 0.02),
          ),
        ),
      ),
    );
  }
}

// ── Settings skeleton ─────────────────────────────────────────────────────────
class _SettingsSkeletonScreen extends StatelessWidget {
  const _SettingsSkeletonScreen();

  Widget _sectionCard(double w, int rows) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(w * 0.035),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        children: List.generate(
          rows,
          (i) => Column(
            children: [
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: w * 0.04,
                  vertical: w * 0.034,
                ),
                child: Row(
                  children: [
                    _Shimmer(
                      width: w * 0.095,
                      height: w * 0.095,
                      radius: w * 0.022,
                    ),
                    SizedBox(width: w * 0.035),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Shimmer(width: w * 0.38, height: w * 0.036),
                        SizedBox(height: w * 0.012),
                        _Shimmer(width: w * 0.28, height: w * 0.026),
                      ],
                    ),
                  ],
                ),
              ),
              if (i < rows - 1)
                Padding(
                  padding: EdgeInsets.only(left: w * 0.165),
                  child: const Divider(height: 1, color: Color(0xFFE5E7EB)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: SafeArea(
        child: Column(
          children: [
            // ── Header — matches actual SettingScreen header exactly ──────────
            // White card with a drop shadow, logo on top, title below
            Container(
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(
                w * 0.04,
                w * 0.04,
                w * 0.04,
                w * 0.04,
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Logo placeholder — same height as Image.asset(height: w * 0.075)
                  _Shimmer(
                    width: w * 0.36,
                    height: w * 0.075,
                    radius: w * 0.015,
                  ),
                  SizedBox(height: w * 0.018),
                  // "Settings" title placeholder — same fontSize: w * 0.058
                  _Shimmer(
                    width: w * 0.28,
                    height: w * 0.056,
                    radius: w * 0.012,
                  ),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  w * 0.04,
                  w * 0.02,
                  w * 0.04,
                  w * 0.06,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Profile card
                    Container(
                      padding: EdgeInsets.all(w * 0.04),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(w * 0.04),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: Row(
                        children: [
                          _Shimmer(
                            width: w * 0.16,
                            height: w * 0.16,
                            radius: w * 0.08,
                          ),
                          SizedBox(width: w * 0.035),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _Shimmer(width: w * 0.42, height: w * 0.042),
                              SizedBox(height: w * 0.015),
                              _Shimmer(width: w * 0.32, height: w * 0.028),
                              SizedBox(height: w * 0.018),
                              _Shimmer(
                                width: w * 0.24,
                                height: w * 0.055,
                                radius: w * 0.03,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // 4 section cards
                    ...List.generate(
                      4,
                      (i) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(height: w * 0.04),
                          _Shimmer(width: w * 0.25, height: w * 0.030),
                          SizedBox(height: w * 0.02),
                          _sectionCard(w, [4, 4, 2, 3][i]),
                        ],
                      ),
                    ),

                    SizedBox(height: w * 0.06),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        height: w * 0.18,
        color: Colors.white,
        padding: EdgeInsets.symmetric(horizontal: w * 0.04, vertical: w * 0.03),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: List.generate(
            5,
            (_) =>
                _Shimmer(width: w * 0.10, height: w * 0.10, radius: w * 0.02),
          ),
        ),
      ),
    );
  }
}
