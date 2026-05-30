import 'package:flutter/material.dart';

// In SkeletonLayout enum — replace with:
enum SkeletonLayout { none, home, settings, editProfile, myReports, newsFeed }

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
    switch (layout) {
      case SkeletonLayout.home:
        return const _HomeSkeletonScreen();
      case SkeletonLayout.editProfile:
        return const _EditProfileSkeletonScreen();
      case SkeletonLayout.settings:
      case SkeletonLayout.none:
        return const _SettingsSkeletonScreen();
      case SkeletonLayout.myReports:
        return const _MyReportsSkeletonScreen();
      case SkeletonLayout.newsFeed:
        return const _NewsFeedSkeletonScreen();
    }
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

// ── Edit Profile skeleton ─────────────────────────────────────────────────────
class _EditProfileSkeletonScreen extends StatelessWidget {
  const _EditProfileSkeletonScreen();

  // Section label placeholder — matches _buildSectionLabel
  Widget _label(double w) => Padding(
    padding: EdgeInsets.only(left: w * 0.01),
    child: _Shimmer(width: w * 0.40, height: w * 0.034, radius: w * 0.01),
  );

  // Card wrapper — matches _buildCard
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

  // One field row — matches _buildField / _buildLockedDisplayField
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

  // Section = label + spacing + card with `rows` field rows
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

  // One stat column inside the avatar card — matches _buildStatItem
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

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: SafeArea(
        child: Column(
          children: [
            // ── Header — matches _buildHeader ─────────────────────────────
            Container(
              padding: EdgeInsets.fromLTRB(
                w * 0.02,
                w * 0.04,
                w * 0.04,
                w * 0.03,
              ),
              color: const Color(0xFFF3F4F6),
              child: Row(
                children: [
                  SizedBox(
                    width: w * 0.13,
                    child: Center(
                      child: _Shimmer(
                        width: w * 0.05,
                        height: w * 0.05,
                        radius: w * 0.012,
                      ),
                    ),
                  ),
                  _Shimmer(
                    width: w * 0.36,
                    height: w * 0.055,
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
                  w * 0.08,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Avatar card — matches _buildAvatarCard ───────────
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
                          // Avatar circle
                          _Shimmer(
                            width: w * 0.28,
                            height: w * 0.28,
                            radius: w * 0.14,
                          ),
                          SizedBox(height: w * 0.032),
                          // Display name
                          _Shimmer(
                            width: w * 0.46,
                            height: w * 0.052,
                            radius: w * 0.012,
                          ),
                          SizedBox(height: w * 0.014),
                          // Verified badge
                          _Shimmer(
                            width: w * 0.34,
                            height: w * 0.05,
                            radius: w * 0.06,
                          ),
                          SizedBox(height: w * 0.028),
                          // Stats row
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: w * 0.02,
                              vertical: w * 0.028,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF9FAFB),
                              borderRadius: BorderRadius.circular(w * 0.03),
                              border: Border.all(
                                color: const Color(0xFFE5E7EB),
                              ),
                            ),
                            child: IntrinsicHeight(
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
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
                          // Photo hint
                          _Shimmer(width: w * 0.30, height: w * 0.028),
                        ],
                      ),
                    ),
                    SizedBox(height: w * 0.04),

                    // ── ACCOUNT (Email + Username) ───────────────────────
                    _section(w, 2),
                    SizedBox(height: w * 0.04),

                    // ── PERSONAL INFORMATION (First/Middle/Last) ─────────
                    _section(w, 3),
                    SizedBox(height: w * 0.04),

                    // ── CONTACT (Mobile) ─────────────────────────────────
                    _section(w, 1),
                    SizedBox(height: w * 0.04),

                    // ── ADDRESS (Barangay + Street) ──────────────────────
                    _section(w, 2),
                    SizedBox(height: w * 0.04),

                    // ── Save button ──────────────────────────────────────
                    _Shimmer(
                      width: double.infinity,
                      height: w * 0.13,
                      radius: w * 0.03,
                    ),
                    SizedBox(height: w * 0.03),

                    // ── Cancel button ────────────────────────────────────
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

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: SafeArea(
        child: Column(
          children: [
            // ── Top bar ──────────────────────────────────────────────────────
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
                  // Logo
                  _Shimmer(
                    width: w * 0.36,
                    height: w * 0.075,
                    radius: w * 0.015,
                  ),
                  SizedBox(height: w * .018),
                  // "My Reports" title + subtitle
                  _Shimmer(
                    width: w * 0.38,
                    height: w * 0.055,
                    radius: w * 0.012,
                  ),
                  SizedBox(height: w * .012),
                  _Shimmer(
                    width: w * 0.52,
                    height: w * 0.028,
                    radius: w * 0.008,
                  ),
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
                      // ── KPI row (4 cards) ──────────────────────────────────
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
                                    // Icon circle
                                    _Shimmer(
                                      width: w * .092,
                                      height: w * .092,
                                      radius: w * .046,
                                    ),
                                    SizedBox(height: w * .018),
                                    // Count value
                                    _Shimmer(
                                      width: w * .07,
                                      height: w * .044,
                                      radius: w * .01,
                                    ),
                                    SizedBox(height: w * .008),
                                    // Label
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

                      // ── Report history card ────────────────────────────────
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(w * .04),
                          border: Border.all(color: const Color(0xFFE5E7EB)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Header row
                            Padding(
                              padding: EdgeInsets.fromLTRB(
                                w * .04,
                                w * .04,
                                w * .04,
                                0,
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
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

                            // Filter chips
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

                            // Report tiles
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
                                        // Row 1: icon + category + status badge
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
                                        // Row 2: location
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
                                        // Row 3: remarks
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
                                        // Row 4: date + file count
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

// ── News Feed skeleton ────────────────────────────────────────────────────────
class _NewsFeedSkeletonScreen extends StatelessWidget {
  const _NewsFeedSkeletonScreen();

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: SafeArea(
        child: Column(
          children: [
            // ── Top bar ──────────────────────────────────────────────────────
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
                  // Logo
                  _Shimmer(
                    width: w * 0.36,
                    height: w * 0.075,
                    radius: w * 0.015,
                  ),
                  SizedBox(height: w * 0.045),
                  // Title row + filter chip
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

            // ── Post cards ───────────────────────────────────────────────────
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
          // Header: avatar + author info + more icon
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

          // Post title
          _Shimmer(width: w * 0.72, height: w * 0.042, radius: w * 0.01),
          SizedBox(height: w * 0.012),
          _Shimmer(width: w * 0.55, height: w * 0.042, radius: w * 0.01),

          SizedBox(height: w * 0.012),

          // Body lines
          _Shimmer(
            width: double.infinity,
            height: w * 0.030,
            radius: w * 0.008,
          ),
          SizedBox(height: w * 0.010),
          _Shimmer(width: w * 0.70, height: w * 0.030, radius: w * 0.008),

          SizedBox(height: w * 0.025),

          // Image grid placeholder (2-col grid)
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

          // Footer: likes + comments
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

          // Divider + comment previews
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
