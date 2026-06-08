import 'dart:async';
import 'package:flutter/material.dart';

enum SkeletonLayout {
  none,
  home,
  settings,
  editProfile,
  myReports,
  newsFeed,
  events,
  changePassword,
}

// ── Slow connection stage ─────────────────────────────────────────────────────
enum _SlowStage {
  none, // 0–9s   → no message
  slow, // 10–29s → "Apologies… this is taking longer than usual"
  very, // 30s+   → "Check your internet connection"
}

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

  static Widget bodyOrSkeleton({
    required bool isLoading,
    required SkeletonLayout layout,
    required Widget child,
  }) {
    if (isLoading && layout != SkeletonLayout.none) {
      return _SkeletonScreen(layout: layout);
    }
    return child;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (isLoading && skeletonLayout != SkeletonLayout.none)
          Positioned.fill(
            child: _SkeletonWithSlowToast(layout: skeletonLayout),
          ),
        if (isLoading && skeletonLayout == SkeletonLayout.none)
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

// ── Skeleton + slow-connection toast manager ──────────────────────────────────
class _SkeletonWithSlowToast extends StatefulWidget {
  final SkeletonLayout layout;
  const _SkeletonWithSlowToast({required this.layout});

  @override
  State<_SkeletonWithSlowToast> createState() => _SkeletonWithSlowToastState();
}

class _SkeletonWithSlowToastState extends State<_SkeletonWithSlowToast> {
  _SlowStage _stage = _SlowStage.none;
  Timer? _slowTimer;
  Timer? _veryTimer;

  @override
  void initState() {
    super.initState();
    // 10s → show first message
    _slowTimer = Timer(const Duration(seconds: 10), () {
      if (mounted) setState(() => _stage = _SlowStage.slow);
    });
    // 30s → escalate message
    _veryTimer = Timer(const Duration(seconds: 30), () {
      if (mounted) setState(() => _stage = _SlowStage.very);
    });
  }

  @override
  void dispose() {
    _slowTimer?.cancel();
    _veryTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        _SkeletonScreen(layout: widget.layout),
        if (_stage != _SlowStage.none)
          Positioned.fill(child: _SlowConnectionToast(stage: _stage)),
      ],
    );
  }
}

// ── Slow connection toast ─────────────────────────────────────────────────────
class _SlowConnectionToast extends StatefulWidget {
  final _SlowStage stage;
  const _SlowConnectionToast({required this.stage});

  @override
  State<_SlowConnectionToast> createState() => _SlowConnectionToastState();
}

class _SlowConnectionToastState extends State<_SlowConnectionToast>
    with TickerProviderStateMixin {
  // Fade-in for the whole toast
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  // Wifi bar pulse
  late final AnimationController _barCtrl;

  // Bouncing dots
  late final AnimationController _dotCtrl;
  late final List<Animation<double>> _dotAnims;

  @override
  void initState() {
    super.initState();

    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..forward();
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);

    _barCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();

    _dotCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();

    _dotAnims = List.generate(3, (i) {
      final start = i * 0.18;
      final end = (start + 0.45).clamp(0.0, 1.0);
      return TweenSequence([
        TweenSequenceItem(
          tween: Tween(
            begin: 0.0,
            end: -4.0,
          ).chain(CurveTween(curve: Curves.easeOut)),
          weight: 50,
        ),
        TweenSequenceItem(
          tween: Tween(
            begin: -4.0,
            end: 0.0,
          ).chain(CurveTween(curve: Curves.easeIn)),
          weight: 50,
        ),
      ]).animate(
        CurvedAnimation(
          parent: _dotCtrl,
          curve: Interval(start, end > 1.0 ? 1.0 : end),
        ),
      );
    });
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _barCtrl.dispose();
    _dotCtrl.dispose();
    super.dispose();
  }

  String get _subtitle => widget.stage == _SlowStage.very
      ? 'Check your internet connection'
      : 'This is taking longer than usual';

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnim,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Wifi bars ───────────────────────────────────────────────────
            AnimatedBuilder(
              animation: _barCtrl,
              builder: (_, _) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: List.generate(4, (i) {
                    final heights = [6.0, 10.0, 14.0, 18.0];
                    final delay = i * 0.15;
                    final t = (_barCtrl.value - delay).clamp(0.0, 1.0);
                    final opacity = 0.2 + 0.6 * (t < 0.5 ? t * 2 : (1 - t) * 2);
                    return Padding(
                      padding: const EdgeInsets.only(right: 3),
                      child: Opacity(
                        opacity: opacity,
                        child: Container(
                          width: 4,
                          height: heights[i],
                          decoration: BoxDecoration(
                            color: const Color(0xFF9CA3AF),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    );
                  }),
                );
              },
            ),

            const SizedBox(height: 12),

            // ── Title ───────────────────────────────────────────────────────
            const Text(
              'Apologies…',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF374151),
                letterSpacing: -0.2,
              ),
            ),

            const SizedBox(height: 4),

            // ── Subtitle (animates between slow / very) ─────────────────────
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Text(
                _subtitle,
                key: ValueKey(_subtitle),
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF6B7280),
                  height: 1.5,
                ),
              ),
            ),

            const SizedBox(height: 12),

            // ── Bouncing dots ───────────────────────────────────────────────
            AnimatedBuilder(
              animation: _dotCtrl,
              builder: (_, _) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(3, (i) {
                    return Transform.translate(
                      offset: Offset(0, _dotAnims[i].value),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3.5),
                        child: Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(
                            color: Color(0xFF9CA3AF),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    );
                  }),
                );
              },
            ),
          ],
        ),
      ),
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
    final Widget body = switch (layout) {
      SkeletonLayout.home => const _HomeSkeletonScreen(),
      SkeletonLayout.editProfile => const _EditProfileSkeletonScreen(),
      SkeletonLayout.settings ||
      SkeletonLayout.none => const _SettingsSkeletonScreen(),
      SkeletonLayout.myReports => const _MyReportsSkeletonScreen(),
      SkeletonLayout.newsFeed => const _NewsFeedSkeletonScreen(),
      SkeletonLayout.events => const EventsSkeletonScreen(),
      SkeletonLayout.changePassword => const _ChangePasswordSkeletonScreen(),
    };
    return Material(color: const Color(0xFFF3F4F6), child: body);
  }
}

// ── Home skeleton ─────────────────────────────────────────────────────────────
class _HomeSkeletonScreen extends StatelessWidget {
  const _HomeSkeletonScreen();

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final h = MediaQuery.of(context).size.height;

    return SafeArea(
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Shimmer(width: double.infinity, height: w * 0.52, radius: 0),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: w * 0.04),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: w * 0.02),
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
                  _Shimmer(width: w * 0.35, height: w * 0.035),
                  SizedBox(height: w * 0.03),
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
                  _Shimmer(width: w * 0.30, height: w * 0.035),
                  SizedBox(height: w * 0.03),
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

    return SafeArea(
      child: Column(
        children: [
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
                _Shimmer(width: w * 0.36, height: w * 0.075, radius: w * 0.015),
                SizedBox(height: w * 0.018),
                _Shimmer(width: w * 0.28, height: w * 0.056, radius: w * 0.012),
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
    );
  }
}

// ── Edit Profile skeleton ─────────────────────────────────────────────────────
class _EditProfileSkeletonScreen extends StatelessWidget {
  const _EditProfileSkeletonScreen();

  Widget _label(double w) => Padding(
    padding: EdgeInsets.only(left: w * 0.01),
    child: _Shimmer(width: w * 0.40, height: w * 0.034, radius: w * 0.01),
  );

  Widget _card(double w, List<Widget> children) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(w * 0.035),
      border: Border.all(color: const Color(0xFFE5E7EB)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: Column(children: children),
  );

  Widget _fieldRow(double w, {bool showDivider = true}) => Column(
    children: [
      Padding(
        padding: EdgeInsets.symmetric(
          horizontal: w * 0.04,
          vertical: w * 0.034,
        ),
        child: Row(
          children: [
            _Shimmer(width: w * 0.095, height: w * 0.095, radius: w * 0.022),
            SizedBox(width: w * 0.035),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Shimmer(width: w * 0.28, height: w * 0.026),
                  SizedBox(height: w * 0.012),
                  _Shimmer(width: w * 0.52, height: w * 0.038),
                ],
              ),
            ),
          ],
        ),
      ),
      if (showDivider)
        Padding(
          padding: EdgeInsets.only(left: w * 0.165),
          child: const Divider(height: 1, color: Color(0xFFE5E7EB)),
        ),
    ],
  );

  Widget _section(double w, int rows) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _label(w),
      SizedBox(height: w * 0.02),
      _card(
        w,
        List.generate(rows, (i) => _fieldRow(w, showDivider: i < rows - 1)),
      ),
    ],
  );

  Widget _stat(double w) => Expanded(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Shimmer(width: w * 0.052, height: w * 0.052, radius: w * 0.012),
        SizedBox(height: w * 0.012),
        _Shimmer(width: w * 0.14, height: w * 0.024),
        SizedBox(height: w * 0.010),
        _Shimmer(width: w * 0.10, height: w * 0.032),
      ],
    ),
  );

  VerticalDivider _vDivider(double w) => VerticalDivider(
    color: const Color(0xFFE5E7EB),
    thickness: 1,
    width: w * 0.01,
  );

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;

    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                w * 0.04,
                w * 0.02,
                w * 0.04,
                w * 0.08,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.fromLTRB(
                      w * 0.04,
                      w * 0.06,
                      w * 0.04,
                      w * 0.05,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(w * 0.04),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        _Shimmer(
                          width: w * 0.28,
                          height: w * 0.28,
                          radius: w * 0.14,
                        ),
                        SizedBox(height: w * 0.032),
                        _Shimmer(
                          width: w * 0.46,
                          height: w * 0.052,
                          radius: w * 0.012,
                        ),
                        SizedBox(height: w * 0.014),
                        _Shimmer(
                          width: w * 0.34,
                          height: w * 0.05,
                          radius: w * 0.06,
                        ),
                        SizedBox(height: w * 0.028),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: w * 0.02,
                            vertical: w * 0.028,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF9FAFB),
                            borderRadius: BorderRadius.circular(w * 0.03),
                            border: Border.all(color: const Color(0xFFE5E7EB)),
                          ),
                          child: IntrinsicHeight(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                _stat(w),
                                _vDivider(w),
                                _stat(w),
                                _vDivider(w),
                                _stat(w),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(height: w * 0.022),
                        _Shimmer(width: w * 0.30, height: w * 0.028),
                      ],
                    ),
                  ),
                  SizedBox(height: w * 0.04),
                  _section(w, 2),
                  SizedBox(height: w * 0.04),
                  _section(w, 3),
                  SizedBox(height: w * 0.04),
                  _section(w, 1),
                  SizedBox(height: w * 0.04),
                  _section(w, 2),
                  SizedBox(height: w * 0.04),
                  _Shimmer(
                    width: double.infinity,
                    height: w * 0.13,
                    radius: w * 0.03,
                  ),
                  SizedBox(height: w * 0.03),
                  _Shimmer(
                    width: double.infinity,
                    height: w * 0.12,
                    radius: w * 0.03,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── My Reports skeleton ───────────────────────────────────────────────────────
class _MyReportsSkeletonScreen extends StatelessWidget {
  const _MyReportsSkeletonScreen();

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;

    return SafeArea(
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(w * .04, w * .04, w * .04, w * .04),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _Shimmer(width: w * 0.36, height: w * 0.075, radius: w * 0.015),
                SizedBox(height: w * .018),
                _Shimmer(width: w * 0.38, height: w * 0.055, radius: w * 0.012),
                SizedBox(height: w * .012),
                _Shimmer(width: w * 0.52, height: w * 0.028, radius: w * 0.008),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: w * .04,
                  vertical: w * .04,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: List.generate(4, (i) {
                        final isLast = i == 3;
                        return Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(
                              right: isLast ? 0 : w * .03,
                            ),
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: w * .025,
                                vertical: w * .035,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(w * .035),
                                border: Border.all(
                                  color: const Color(0xFFE5E7EB),
                                ),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _Shimmer(
                                    width: w * .092,
                                    height: w * .092,
                                    radius: w * .046,
                                  ),
                                  SizedBox(height: w * .018),
                                  _Shimmer(
                                    width: w * .07,
                                    height: w * .044,
                                    radius: w * .01,
                                  ),
                                  SizedBox(height: w * .008),
                                  _Shimmer(
                                    width: w * .10,
                                    height: w * .025,
                                    radius: w * .008,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                    SizedBox(height: w * .04),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(w * .04),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: EdgeInsets.fromLTRB(
                              w * .04,
                              w * .04,
                              w * .04,
                              0,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                _Shimmer(
                                  width: w * .36,
                                  height: w * .036,
                                  radius: w * .01,
                                ),
                                _Shimmer(
                                  width: w * .20,
                                  height: w * .028,
                                  radius: w * .008,
                                ),
                              ],
                            ),
                          ),
                          SizedBox(
                            height: w * .14,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              physics: const NeverScrollableScrollPhysics(),
                              padding: EdgeInsets.symmetric(
                                horizontal: w * .04,
                                vertical: w * .03,
                              ),
                              children: List.generate(5, (i) {
                                final widths = [
                                  w * .14,
                                  w * .16,
                                  w * .22,
                                  w * .24,
                                  w * .28,
                                ];
                                return Padding(
                                  padding: EdgeInsets.only(
                                    right: i < 4 ? w * .02 : 0,
                                  ),
                                  child: _Shimmer(
                                    width: widths[i],
                                    height: w * .072,
                                    radius: w * .06,
                                  ),
                                );
                              }),
                            ),
                          ),
                          const Divider(height: 1, color: Color(0xFFE5E7EB)),
                          ...List.generate(
                            4,
                            (i) => Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: EdgeInsets.all(w * .04),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          _Shimmer(
                                            width: w * .088,
                                            height: w * .088,
                                            radius: w * .022,
                                          ),
                                          SizedBox(width: w * .03),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                _Shimmer(
                                                  width: w * .44,
                                                  height: w * .034,
                                                  radius: w * .01,
                                                ),
                                                SizedBox(height: w * .012),
                                                _Shimmer(
                                                  width: w * .28,
                                                  height: w * .026,
                                                  radius: w * .008,
                                                ),
                                              ],
                                            ),
                                          ),
                                          SizedBox(width: w * .02),
                                          _Shimmer(
                                            width: w * .22,
                                            height: w * .052,
                                            radius: w * .04,
                                          ),
                                        ],
                                      ),
                                      SizedBox(height: w * .025),
                                      Row(
                                        children: [
                                          _Shimmer(
                                            width: w * .034,
                                            height: w * .034,
                                            radius: w * .008,
                                          ),
                                          SizedBox(width: w * .015),
                                          _Shimmer(
                                            width: w * .55,
                                            height: w * .028,
                                            radius: w * .008,
                                          ),
                                        ],
                                      ),
                                      SizedBox(height: w * .015),
                                      Row(
                                        children: [
                                          _Shimmer(
                                            width: w * .034,
                                            height: w * .034,
                                            radius: w * .008,
                                          ),
                                          SizedBox(width: w * .015),
                                          _Shimmer(
                                            width: w * .68,
                                            height: w * .028,
                                            radius: w * .008,
                                          ),
                                        ],
                                      ),
                                      SizedBox(height: w * .015),
                                      Row(
                                        children: [
                                          _Shimmer(
                                            width: w * .028,
                                            height: w * .028,
                                            radius: w * .006,
                                          ),
                                          SizedBox(width: w * .015),
                                          _Shimmer(
                                            width: w * .30,
                                            height: w * .024,
                                            radius: w * .006,
                                          ),
                                          SizedBox(width: w * .03),
                                          _Shimmer(
                                            width: w * .18,
                                            height: w * .024,
                                            radius: w * .006,
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                if (i < 3)
                                  const Divider(
                                    height: 1,
                                    color: Color(0xFFE5E7EB),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: w * .06),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── News Feed skeleton ────────────────────────────────────────────────────────
class _NewsFeedSkeletonScreen extends StatelessWidget {
  const _NewsFeedSkeletonScreen();

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;

    return SafeArea(
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(
              w * 0.04,
              w * 0.025,
              w * 0.04,
              w * 0.035,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .04),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Shimmer(width: w * 0.36, height: w * 0.075, radius: w * 0.015),
                SizedBox(height: w * 0.045),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _Shimmer(
                      width: w * 0.50,
                      height: w * 0.048,
                      radius: w * 0.012,
                    ),
                    _Shimmer(
                      width: w * 0.26,
                      height: w * 0.072,
                      radius: w * 0.04,
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                w * 0.04,
                w * 0.035,
                w * 0.04,
                w * 0.04,
              ),
              itemCount: 3,
              separatorBuilder: (_, _) => SizedBox(height: w * 0.035),
              itemBuilder: (_, i) => _buildPostCardSkeleton(w),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPostCardSkeleton(double w) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(w * 0.035),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      padding: EdgeInsets.all(w * 0.035),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Shimmer(width: w * 0.105, height: w * 0.105, radius: w * 0.0525),
              SizedBox(width: w * 0.025),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Shimmer(
                      width: w * 0.38,
                      height: w * 0.034,
                      radius: w * 0.01,
                    ),
                    SizedBox(height: w * 0.012),
                    Row(
                      children: [
                        _Shimmer(
                          width: w * 0.28,
                          height: w * 0.024,
                          radius: w * 0.008,
                        ),
                        SizedBox(width: w * 0.018),
                        _Shimmer(
                          width: w * 0.18,
                          height: w * 0.042,
                          radius: w * 0.025,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              _Shimmer(width: w * 0.05, height: w * 0.028, radius: w * 0.008),
            ],
          ),
          SizedBox(height: w * 0.03),
          _Shimmer(width: w * 0.72, height: w * 0.042, radius: w * 0.01),
          SizedBox(height: w * 0.012),
          _Shimmer(width: w * 0.55, height: w * 0.042, radius: w * 0.01),
          SizedBox(height: w * 0.012),
          _Shimmer(
            width: double.infinity,
            height: w * 0.030,
            radius: w * 0.008,
          ),
          SizedBox(height: w * 0.010),
          _Shimmer(width: w * 0.70, height: w * 0.030, radius: w * 0.008),
          SizedBox(height: w * 0.025),
          Row(
            children: [
              Expanded(
                child: _Shimmer(
                  width: double.infinity,
                  height: w * 0.38,
                  radius: w * 0.025,
                ),
              ),
              SizedBox(width: w * 0.02),
              Expanded(
                child: _Shimmer(
                  width: double.infinity,
                  height: w * 0.38,
                  radius: w * 0.025,
                ),
              ),
            ],
          ),
          SizedBox(height: w * 0.03),
          Row(
            children: [
              _Shimmer(width: w * 0.046, height: w * 0.046, radius: w * 0.023),
              SizedBox(width: w * 0.012),
              _Shimmer(width: w * 0.06, height: w * 0.030, radius: w * 0.008),
              SizedBox(width: w * 0.05),
              _Shimmer(width: w * 0.048, height: w * 0.048, radius: w * 0.024),
              SizedBox(width: w * 0.012),
              _Shimmer(width: w * 0.06, height: w * 0.030, radius: w * 0.008),
            ],
          ),
          Padding(
            padding: EdgeInsets.symmetric(vertical: w * 0.025),
            child: const Divider(height: 1, color: Color(0xFFE5E7EB)),
          ),
          ...List.generate(
            2,
            (_) => Padding(
              padding: EdgeInsets.only(bottom: w * 0.02),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Shimmer(
                    width: w * 0.072,
                    height: w * 0.072,
                    radius: w * 0.036,
                  ),
                  SizedBox(width: w * 0.02),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Shimmer(
                          width: w * 0.28,
                          height: w * 0.026,
                          radius: w * 0.008,
                        ),
                        SizedBox(height: w * 0.010),
                        _Shimmer(
                          width: double.infinity,
                          height: w * 0.026,
                          radius: w * 0.008,
                        ),
                        SizedBox(height: w * 0.006),
                        _Shimmer(
                          width: w * 0.55,
                          height: w * 0.026,
                          radius: w * 0.008,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Events skeleton ───────────────────────────────────────────────────────────
class EventsSkeletonScreen extends StatelessWidget {
  const EventsSkeletonScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;

    return SafeArea(
      child: Column(
        children: [
          // Skeleton header (used only when the whole screen is a skeleton).
          Container(
            color: Colors.white,
            padding: EdgeInsets.symmetric(
              horizontal: w * 0.04,
              vertical: w * 0.03,
            ),
            child: Row(
              children: [
                _Shimmer(width: w * 0.09, height: w * 0.09, radius: w * 0.025),
                SizedBox(width: w * 0.03),
                _Shimmer(width: w * 0.36, height: w * 0.075, radius: w * 0.015),
              ],
            ),
          ),
          const Expanded(child: EventsBodySkeleton()),
        ],
      ),
    );
  }
}

// ── Events BODY skeleton (no header — caller supplies the real one) ──────────
class EventsBodySkeleton extends StatelessWidget {
  const EventsBodySkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final cardW = w * 0.42;
    final cardH = cardW * 1.42;
    final imageH = cardW * 0.62;

    Widget eventCardList() => SizedBox(
      height: cardH,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.symmetric(horizontal: w * 0.04),
        itemCount: 3,
        itemBuilder: (_, i) => Padding(
          padding: EdgeInsets.only(right: w * 0.03),
          child: SizedBox(
            width: cardW,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(w * 0.03),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Shimmer(width: cardW, height: imageH, radius: w * 0.03),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      w * 0.025,
                      w * 0.020,
                      w * 0.025,
                      w * 0.020,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Shimmer(
                          width: cardW * 0.75,
                          height: w * 0.030,
                          radius: 4,
                        ),
                        SizedBox(height: w * 0.010),
                        _Shimmer(
                          width: cardW * 0.55,
                          height: w * 0.025,
                          radius: 4,
                        ),
                        SizedBox(height: w * 0.008),
                        _Shimmer(
                          width: cardW * 0.45,
                          height: w * 0.025,
                          radius: 4,
                        ),
                        SizedBox(height: w * 0.008),
                        _Shimmer(
                          width: cardW * 0.38,
                          height: w * 0.025,
                          radius: 4,
                        ),
                        SizedBox(height: w * 0.012),
                        _Shimmer(
                          width: double.infinity,
                          height: w * 0.068,
                          radius: w * 0.02,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.only(bottom: w * 0.06),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: w * 0.04),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: w * 0.04),
            child: _Shimmer(
              width: double.infinity,
              height: w * 0.30,
              radius: w * 0.04,
            ),
          ),
          SizedBox(height: w * 0.035),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: w * 0.04),
            child: _Shimmer(
              width: double.infinity,
              height: w * 0.115,
              radius: w * 0.03,
            ),
          ),
          SizedBox(height: w * 0.025),
          SizedBox(
            height: w * 0.088,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.symmetric(horizontal: w * 0.04),
              itemCount: 6,
              itemBuilder: (_, i) => Padding(
                padding: EdgeInsets.only(right: w * 0.02),
                child: _Shimmer(
                  width: w * 0.17,
                  height: w * 0.088,
                  radius: w * 0.05,
                ),
              ),
            ),
          ),
          SizedBox(height: w * 0.045),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: w * 0.04),
            child: _Shimmer(width: w * 0.38, height: w * 0.042, radius: 6),
          ),
          SizedBox(height: w * 0.02),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: w * 0.04),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(w * 0.035),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              padding: EdgeInsets.all(w * 0.035),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Shimmer(
                    width: w * 0.32,
                    height: w * 0.38,
                    radius: w * 0.025,
                  ),
                  SizedBox(width: w * 0.035),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Shimmer(
                          width: double.infinity,
                          height: w * 0.038,
                          radius: 4,
                        ),
                        SizedBox(height: w * 0.010),
                        _Shimmer(width: w * 0.30, height: w * 0.038, radius: 4),
                        SizedBox(height: w * 0.018),
                        _Shimmer(width: w * 0.42, height: w * 0.026, radius: 4),
                        SizedBox(height: w * 0.010),
                        _Shimmer(width: w * 0.36, height: w * 0.026, radius: 4),
                        SizedBox(height: w * 0.010),
                        _Shimmer(width: w * 0.30, height: w * 0.026, radius: 4),
                        SizedBox(height: w * 0.018),
                        _Shimmer(
                          width: double.infinity,
                          height: w * 0.022,
                          radius: 4,
                        ),
                        SizedBox(height: w * 0.006),
                        _Shimmer(width: w * 0.38, height: w * 0.022, radius: 4),
                        SizedBox(height: w * 0.022),
                        _Shimmer(
                          width: double.infinity,
                          height: w * 0.075,
                          radius: w * 0.022,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: w * 0.045),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: w * 0.04),
            child: _Shimmer(width: w * 0.30, height: w * 0.042, radius: 6),
          ),
          SizedBox(height: w * 0.02),
          eventCardList(),
          SizedBox(height: w * 0.045),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: w * 0.04),
            child: _Shimmer(width: w * 0.34, height: w * 0.042, radius: 6),
          ),
          SizedBox(height: w * 0.02),
          eventCardList(),
          SizedBox(height: w * 0.04),
        ],
      ),
    );
  }
}

class _ChangePasswordSkeletonScreen extends StatelessWidget {
  const _ChangePasswordSkeletonScreen();

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final size = (w * 0.28).clamp(80.0, 140.0);

    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: Container(
              color: Colors.white,
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.symmetric(horizontal: w * 0.06),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(height: w * 0.08),
                    // Icon circle
                    _Shimmer(width: size, height: size, radius: size / 2),
                    SizedBox(height: w * 0.07),
                    // Title
                    _Shimmer(
                      width: w * 0.52,
                      height: w * 0.052,
                      radius: w * 0.012,
                    ),
                    SizedBox(height: w * 0.025),
                    // Subtitle line 1
                    _Shimmer(
                      width: w * 0.64,
                      height: w * 0.032,
                      radius: w * 0.008,
                    ),
                    SizedBox(height: w * 0.010),
                    // Subtitle line 2
                    _Shimmer(
                      width: w * 0.50,
                      height: w * 0.032,
                      radius: w * 0.008,
                    ),
                    SizedBox(height: w * 0.07),
                    // Email field
                    _Shimmer(
                      width: double.infinity,
                      height: w * 0.18,
                      radius: w * 0.035,
                    ),
                    SizedBox(height: w * 0.04),
                    // Info chip
                    _Shimmer(
                      width: double.infinity,
                      height: w * 0.18,
                      radius: w * 0.03,
                    ),
                    SizedBox(height: w * 0.07),
                    // Button
                    _Shimmer(
                      width: double.infinity,
                      height: w * 0.138,
                      radius: w * 0.035,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
