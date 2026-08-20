import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../citizen_shell_scope.dart';
import '../../../core/theme/citizen_ui.dart';

enum SkeletonLayout {
  none,
  home,
  settings,
  editProfile,
  myReports,
  mySubmissions,
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

  /// [webWide] is the CALLER's own "I am about to render my web body" flag —
  /// the same `wide` the caller already computed to choose [child]. It is not
  /// re-derived here, and that is the point.
  ///
  /// ── Why this cannot be a width test, or even `kIsWeb` ──────────────────
  /// This picks a skeleton for a body it cannot see, and the callers disagree
  /// about what they are about to render on web. MyReportsBody uses `kIsWeb`
  /// alone, so on web its web body ALWAYS renders. NewsFeedBody uses
  /// `embedded || …`, so the guest feed route — not embedded — still renders
  /// the phone body in a browser. HomeScreen renders its mobile body at
  /// `NavBand.phone`, which a narrow browser reaches.
  ///
  /// The old `screenW >= 900` here was measured against a MediaQuery the shell
  /// has already overridden to describe the centre column, so inside the shell
  /// it never passed and every web page flashed its PHONE skeleton before
  /// rearranging into the web body on load. But swapping it for a blanket
  /// `kIsWeb` would fix My Reports and the embedded feed while introducing the
  /// same defect, reversed, in the guest feed and narrow home: a web skeleton
  /// promising a layout that never arrives.
  ///
  /// Only the caller knows. So the caller says.
  static Widget bodyOrSkeleton({
    required bool isLoading,
    required SkeletonLayout layout,
    required Widget child,
    bool webWide = false,
  }) {
    if (isLoading && layout != SkeletonLayout.none) {
      return _SkeletonScreen(layout: layout, webWide: webWide);
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
    _slowTimer = Timer(const Duration(seconds: 10), () {
      if (mounted) setState(() => _stage = _SlowStage.slow);
    });
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
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;
  late final AnimationController _barCtrl;
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

/// A single shimmering placeholder block — the citizen-side equivalent of the
/// admin console's `SkeletonBox` / the staff console's `StaffSkeletonBox`.
///
/// The full-page skeletons below are built from these, but it is also public so
/// that surfaces which render a *profile inline* (the home card, the web profile
/// strip, the Settings summary card, Edit Profile's avatar) can shimmer just the
/// parts that are still loading instead of dropping a spinner into the layout.
/// Sizing is entirely caller-driven — pass width/height derived from the design
/// width so it stays proportional on phone, tablet and web.
///
/// [dark] swaps the fill for a translucent-white pair, for placements on a dark
/// surface (the navy web profile strip) where the default grey reads as a hole.
class AppShimmerBox extends StatefulWidget {
  final double width;
  final double height;
  final double radius;
  final bool dark;

  const AppShimmerBox({
    super.key,
    required this.width,
    required this.height,
    this.radius = 8,
    this.dark = false,
  });

  @override
  State<AppShimmerBox> createState() => _AppShimmerBoxState();
}

class _AppShimmerBoxState extends State<AppShimmerBox>
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
    final colors = widget.dark
        ? const [Color(0x1FFFFFFF), Color(0x3DFFFFFF), Color(0x1FFFFFFF)]
        : const [Color(0xFFE5E7EB), Color(0xFFF3F4F6), Color(0xFFE5E7EB)];

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
            colors: colors,
          ),
        ),
      ),
    );
  }
}

/// Internal alias kept so the skeleton screens below stay terse.
class _Shimmer extends StatelessWidget {
  final double width;
  final double height;
  final double radius;

  const _Shimmer({required this.width, required this.height, this.radius = 8});

  @override
  Widget build(BuildContext context) =>
      AppShimmerBox(width: width, height: height, radius: radius);
}

// ── Skeleton screen router ────────────────────────────────────────────────────
class _SkeletonScreen extends StatelessWidget {
  final SkeletonLayout layout;

  /// See [LoadingOverlay.bodyOrSkeleton]. Defaults to false so the only other
  /// construction site — [_SkeletonWithSlowToast], reached from the
  /// [LoadingOverlay] widget whose `skeletonLayout` defaults to
  /// [SkeletonLayout.none] and which no caller overrides — keeps compiling
  /// without claiming a web body it knows nothing about.
  final bool webWide;

  const _SkeletonScreen({required this.layout, this.webWide = false});

  @override
  Widget build(BuildContext context) {
    Widget makeBody() => switch (layout) {
      SkeletonLayout.home => const _HomeSkeletonScreen(),
      SkeletonLayout.editProfile => const _EditProfileSkeletonScreen(),
      SkeletonLayout.settings ||
      SkeletonLayout.none => const _SettingsSkeletonScreen(),
      SkeletonLayout.myReports => const _MyReportsSkeletonScreen(),
      SkeletonLayout.mySubmissions => const MySubmissionsBodySkeleton(),
      SkeletonLayout.newsFeed => const _NewsFeedSkeletonScreen(),
      SkeletonLayout.events => const EventsSkeletonScreen(),
      SkeletonLayout.changePassword => const _ChangePasswordSkeletonScreen(),
    };

    final mq = MediaQuery.of(context);
    const double maxContentWidth = 480;
    final double screenW = mq.size.width;

    // WEB: render a multi-column skeleton so the loading state matches the wide
    // web body instead of stranding a single phone-width column. Only the
    // screens that gained a web body opt in here, and only when the caller says
    // it is actually rendering that body — see [LoadingOverlay.bodyOrSkeleton].
    // The mobile app never hits this branch: `kIsWeb` is a compile-time false
    // there, so the whole thing is dead code in the app binary.
    const Set<SkeletonLayout> webMultiCol = {
      SkeletonLayout.home,
      SkeletonLayout.myReports,
      SkeletonLayout.newsFeed,
      SkeletonLayout.settings,
      SkeletonLayout.mySubmissions,
      SkeletonLayout.editProfile,
    };
    if (kIsWeb && webWide && webMultiCol.contains(layout)) {
      final Widget web = switch (layout) {
        SkeletonLayout.home => const _WebHomeSkeleton(),
        SkeletonLayout.newsFeed => const _WebFeedSkeleton(),
        SkeletonLayout.myReports => const _WebGridSkeleton(kpi: true),
        SkeletonLayout.settings ||
        SkeletonLayout.editProfile => const _WebProfileSkeleton(),
        _ => const _WebGridSkeleton(),
      };
      return Material(color: const Color(0xFFF3F4F6), child: web);
    }

    final Widget body = makeBody();
    final double clampedWidth =
        (layout != SkeletonLayout.home && screenW > maxContentWidth)
        ? maxContentWidth
        : screenW;

    final Widget sized = clampedWidth >= screenW
        ? body
        : Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              SizedBox(
                width: clampedWidth,
                child: MediaQuery(
                  data: mq.copyWith(size: Size(clampedWidth, mq.size.height)),
                  child: body,
                ),
              ),
              const Spacer(),
            ],
          );

    return Material(color: const Color(0xFFF3F4F6), child: sized);
  }
}

// ── WEB skeletons (wide screens ≥ 900) ────────────────────────────────────────
// Dedicated loading states that mirror the wide web bodies, so the skeleton
// fills the same band instead of duplicating a phone column.

Widget _skelSurface(
  Widget child, {
  EdgeInsetsGeometry padding = const EdgeInsets.all(18),
}) {
  return Container(
    padding: padding,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: CitizenUi.sharedBorder),
    ),
    child: child,
  );
}

/// The page band a web skeleton sits in.
///
/// Standalone, it is centred and capped at 1080 — the measure the standalone
/// web pages use. Inside the citizen shell it is neither: the pane has already
/// been given exactly the width it should occupy, and re-centring inside it
/// would inset the skeleton from a column the real content fills, so the page
/// would appear to jump sideways on load.
Widget _skelBand(Widget child) {
  return Builder(
    builder: (context) {
      final inShell = CitizenShellScope.of(context);
      return SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: inShell ? double.infinity : 1080,
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                inShell ? 0 : 24,
                24,
                inShell ? 0 : 24,
                40,
              ),
              child: child,
            ),
          ),
        ),
      );
    },
  );
}

Widget _skelHeaderBar() => _skelSurface(
  Row(
    children: const [
      _Shimmer(width: 140, height: 26),
      Spacer(),
      _Shimmer(width: 80, height: 18),
    ],
  ),
);

Widget _skelKpiCard() => _skelSurface(
  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
  Column(
    mainAxisSize: MainAxisSize.min,
    children: const [
      _Shimmer(width: 40, height: 40, radius: 20),
      SizedBox(height: 12),
      _Shimmer(width: 40, height: 22),
      SizedBox(height: 8),
      _Shimmer(width: 56, height: 12),
    ],
  ),
);

Widget _skelDetailCard() => _skelSurface(
  Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: const [
      Row(
        children: [
          _Shimmer(width: 40, height: 40, radius: 10),
          SizedBox(width: 12),
          Expanded(child: _Shimmer(width: double.infinity, height: 16)),
          SizedBox(width: 12),
          _Shimmer(width: 64, height: 20, radius: 10),
        ],
      ),
      SizedBox(height: 16),
      _Shimmer(width: 240, height: 12),
      SizedBox(height: 10),
      _Shimmer(width: 180, height: 12),
      SizedBox(height: 10),
      _Shimmer(width: 120, height: 12),
    ],
  ),
);

class _WebGridSkeleton extends StatelessWidget {
  final bool kpi;
  const _WebGridSkeleton({this.kpi = false});

  @override
  Widget build(BuildContext context) {
    return _skelBand(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _skelHeaderBar(),
          const SizedBox(height: 24),
          if (kpi) ...[
            Row(
              children: [
                for (int i = 0; i < 4; i++) ...[
                  Expanded(child: _skelKpiCard()),
                  if (i < 3) const SizedBox(width: 16),
                ],
              ],
            ),
            const SizedBox(height: 28),
          ],
          const _Shimmer(width: 180, height: 20),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, c) {
              const target = 320.0;
              final cols = (c.maxWidth / target).floor().clamp(1, 3);
              final cellW = (c.maxWidth - 16 * (cols - 1)) / cols;
              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  for (int i = 0; i < 6; i++)
                    SizedBox(width: cellW, child: _skelDetailCard()),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _WebProfileSkeleton extends StatelessWidget {
  const _WebProfileSkeleton();

  @override
  Widget build(BuildContext context) {
    return _skelBand(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _skelHeaderBar(),
          const SizedBox(height: 24),
          // Profile banner
          _skelSurface(
            Row(
              children: const [
                _Shimmer(width: 64, height: 64, radius: 32),
                SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Shimmer(width: 160, height: 18),
                      SizedBox(height: 10),
                      _Shimmer(width: 220, height: 13),
                      SizedBox(height: 10),
                      _Shimmer(width: 90, height: 22, radius: 11),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          // Two columns
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  children: const [
                    _Shimmer(width: 120, height: 14),
                    SizedBox(height: 12),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              const Expanded(child: SizedBox.shrink()),
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  children: [
                    _skelDetailCard(),
                    const SizedBox(height: 20),
                    _skelDetailCard(),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  children: [
                    _skelDetailCard(),
                    const SizedBox(height: 20),
                    _skelDetailCard(),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WebHomeSkeleton extends StatelessWidget {
  const _WebHomeSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Top nav bar
        Container(
          height: 60,
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Row(
            children: const [
              _Shimmer(width: 120, height: 24),
              Spacer(),
              _Shimmer(width: 240, height: 18),
              SizedBox(width: 24),
              _Shimmer(width: 40, height: 40, radius: 20),
            ],
          ),
        ),
        Expanded(
          child: _skelBand(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Hero band
                const _Shimmer(width: double.infinity, height: 160, radius: 18),
                const SizedBox(height: 24),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: _skelSurface(
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            _Shimmer(width: 160, height: 18),
                            SizedBox(height: 18),
                            _Shimmer(
                              width: double.infinity,
                              height: 90,
                              radius: 12,
                            ),
                            SizedBox(height: 14),
                            _Shimmer(
                              width: double.infinity,
                              height: 90,
                              radius: 12,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      flex: 2,
                      child: _skelSurface(
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            _Shimmer(width: 140, height: 18),
                            SizedBox(height: 16),
                            _Shimmer(
                              width: double.infinity,
                              height: 44,
                              radius: 10,
                            ),
                            SizedBox(height: 12),
                            _Shimmer(
                              width: double.infinity,
                              height: 44,
                              radius: 10,
                            ),
                            SizedBox(height: 12),
                            _Shimmer(
                              width: double.infinity,
                              height: 44,
                              radius: 10,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _WebFeedSkeleton extends StatelessWidget {
  const _WebFeedSkeleton();

  Widget _postCard() => _skelSurface(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        Row(
          children: [
            _Shimmer(width: 40, height: 40, radius: 20),
            SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Shimmer(width: 140, height: 14),
                SizedBox(height: 6),
                _Shimmer(width: 90, height: 12),
              ],
            ),
          ],
        ),
        SizedBox(height: 14),
        _Shimmer(width: 340, height: 12),
        SizedBox(height: 8),
        _Shimmer(width: 300, height: 12),
        SizedBox(height: 8),
        _Shimmer(width: 200, height: 12),
        SizedBox(height: 14),
        _Shimmer(width: double.infinity, height: 180, radius: 12),
      ],
    ),
  );

  Widget _railCard() => _skelSurface(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        Row(
          children: [
            _Shimmer(width: 36, height: 36, radius: 10),
            SizedBox(width: 10),
            Expanded(child: _Shimmer(width: double.infinity, height: 14)),
          ],
        ),
        SizedBox(height: 12),
        _Shimmer(width: double.infinity, height: 11),
        SizedBox(height: 8),
        _Shimmer(width: 180, height: 11),
      ],
    ),
  );

  /// Feed column width, and the info rail beside it, with the gutter between.
  ///
  /// Their sum is the width the two-column layout needs. [_skelBand] gives this
  /// Row `min(viewport, 1080) - 48` of padding, so any viewport under about
  /// 980px leaves the pair short — and because all three children used to be
  /// fixed-width `SizedBox`es, the Row simply overflowed by the difference (51px
  /// at 881px available) rather than adapting.
  static const double _kFeedWidth = 600;
  static const double _kGutter = 32;
  static const double _kRailWidth = 300;
  static const double _kPairWidth = _kFeedWidth + _kGutter + _kRailWidth;

  @override
  Widget build(BuildContext context) {
    return _skelBand(
      LayoutBuilder(
        builder: (context, constraints) {
          // Drop the rail when the pair does not fit, exactly as the real feed
          // does — news_feed_screen notes the same 932px threshold, and the
          // embedded body drops its 300px rail there. A skeleton exists to
          // predict the layout that replaces it, so it has to break at the same
          // width; stretching the columns or scrolling sideways would both
          // predict a layout the feed never actually shows.
          //
          // ── And it never shows inside the citizen shell ─────────────────
          // The rail predicts the STANDALONE feed's second column. The shell's
          // Home pane has no such column — the shell's own left rail and right
          // sidebar live outside the pane entirely — so drawing one here
          // promised a two-column layout and then delivered one column, which
          // is the visible rearrangement a skeleton exists to prevent.
          //
          // The width test alone could not catch this: the pane reports the
          // CENTRE COLUMN's width, which on a large monitor is comfortably over
          // the threshold. Only the shell knows, so the shell says so.
          final showRail =
              constraints.maxWidth >= _kPairWidth &&
              !CitizenShellScope.of(context);

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Flexible + maxWidth rather than a fixed SizedBox: identical at
              // any width that fits 600px, and below that the column shrinks
              // instead of overflowing. That covers the narrow end, which a
              // rail-only fix would still leave broken.
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _kFeedWidth),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _skelHeaderBar(),
                      const SizedBox(height: 20),
                      _postCard(),
                      const SizedBox(height: 16),
                      _postCard(),
                      const SizedBox(height: 16),
                      _postCard(),
                    ],
                  ),
                ),
              ),
              if (showRail) ...[
                const SizedBox(width: _kGutter),
                SizedBox(
                  width: _kRailWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _railCard(),
                      const SizedBox(height: 16),
                      _railCard(),
                      const SizedBox(height: 16),
                      _railCard(),
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
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
                      border: Border.all(color: CitizenUi.sharedBorder),
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
        border: Border.all(color: CitizenUi.sharedBorder),
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
                  child: const Divider(
                    height: 1,
                    color: CitizenUi.sharedBorder,
                  ),
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
    const sectionRows = [3, 1, 2, 3];

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
                      border: Border.all(color: CitizenUi.sharedBorder),
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
                    sectionRows.length,
                    (i) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(height: w * 0.04),
                        _Shimmer(width: w * 0.25, height: w * 0.030),
                        SizedBox(height: w * 0.02),
                        _sectionCard(w, sectionRows[i]),
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
      border: Border.all(color: CitizenUi.sharedBorder),
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
          child: const Divider(height: 1, color: CitizenUi.sharedBorder),
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
    color: CitizenUi.sharedBorder,
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
                      border: Border.all(color: CitizenUi.sharedBorder),
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
                            border: Border.all(color: CitizenUi.sharedBorder),
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
// ONLY the content below the real app bar + "My Reports" title shimmers.
// The app bar (hamburger / logo / bell) and page title are rendered by the
// real screen — this skeleton never duplicates them.
//
// Content that shimmers:
//   1. 4-up summary stat cards  (icon circle + number + label)
//   2. Report list card         (section header + filter chips + 4 rows)
class _MyReportsSkeletonScreen extends StatelessWidget {
  const _MyReportsSkeletonScreen();

  // ── Single summary stat card ──────────────────────────────────────────────
  Widget _statCard(double w) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: w * .025, vertical: w * .035),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(w * .035),
          border: Border.all(color: CitizenUi.sharedBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon circle
            _Shimmer(width: w * .092, height: w * .092, radius: w * .046),
            SizedBox(height: w * .018),
            // Number
            _Shimmer(width: w * .07, height: w * .044, radius: w * .010),
            SizedBox(height: w * .008),
            // Label
            _Shimmer(width: w * .10, height: w * .025, radius: w * .008),
          ],
        ),
      ),
    );
  }

  // ── Single report list row ────────────────────────────────────────────────
  Widget _reportRow(double w, {required bool showDivider}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.all(w * .04),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Thumbnail + title + status badge
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Shimmer(width: w * .088, height: w * .088, radius: w * .022),
                  SizedBox(width: w * .03),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Shimmer(
                          width: w * .44,
                          height: w * .034,
                          radius: w * .010,
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
                  _Shimmer(width: w * .22, height: w * .052, radius: w * .04),
                ],
              ),
              SizedBox(height: w * .025),
              // Location
              Row(
                children: [
                  _Shimmer(width: w * .034, height: w * .034, radius: w * .008),
                  SizedBox(width: w * .015),
                  _Shimmer(width: w * .55, height: w * .028, radius: w * .008),
                ],
              ),
              SizedBox(height: w * .015),
              // Category
              Row(
                children: [
                  _Shimmer(width: w * .034, height: w * .034, radius: w * .008),
                  SizedBox(width: w * .015),
                  _Shimmer(width: w * .68, height: w * .028, radius: w * .008),
                ],
              ),
              SizedBox(height: w * .015),
              // Date + upvote count
              Row(
                children: [
                  _Shimmer(width: w * .028, height: w * .028, radius: w * .006),
                  SizedBox(width: w * .015),
                  _Shimmer(width: w * .30, height: w * .024, radius: w * .006),
                  SizedBox(width: w * .03),
                  _Shimmer(width: w * .18, height: w * .024, radius: w * .006),
                ],
              ),
            ],
          ),
        ),
        if (showDivider)
          const Divider(height: 1, color: CitizenUi.sharedBorder),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;

    return SafeArea(
      // top: false because the real app bar + page title already consumed
      // the top safe-area inset — we must not add it a second time.
      top: false,
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Padding(
          padding: EdgeInsets.fromLTRB(w * .04, w * .04, w * .04, w * .06),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── 4-up stat cards ─────────────────────────────────────────
              Row(
                children: [
                  _statCard(w),
                  SizedBox(width: w * .03),
                  _statCard(w),
                  SizedBox(width: w * .03),
                  _statCard(w),
                  SizedBox(width: w * .03),
                  _statCard(w),
                ],
              ),

              SizedBox(height: w * .04),

              // ── Report list card ─────────────────────────────────────────
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(w * .04),
                  border: Border.all(color: CitizenUi.sharedBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Section header row
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
                            radius: w * .010,
                          ),
                          _Shimmer(
                            width: w * .20,
                            height: w * .028,
                            radius: w * .008,
                          ),
                        ],
                      ),
                    ),

                    // Horizontal filter chips
                    SizedBox(
                      height: w * .14,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        physics: const NeverScrollableScrollPhysics(),
                        padding: EdgeInsets.symmetric(
                          horizontal: w * .04,
                          vertical: w * .03,
                        ),
                        children: [w * .14, w * .16, w * .22, w * .24, w * .28]
                            .asMap()
                            .entries
                            .map((e) {
                              final isLast = e.key == 4;
                              return Padding(
                                padding: EdgeInsets.only(
                                  right: isLast ? 0 : w * .02,
                                ),
                                child: _Shimmer(
                                  width: e.value,
                                  height: w * .072,
                                  radius: w * .06,
                                ),
                              );
                            })
                            .toList(),
                      ),
                    ),

                    const Divider(height: 1, color: CitizenUi.sharedBorder),

                    // 4 report rows
                    ...List.generate(
                      4,
                      (i) => _reportRow(w, showDivider: i < 3),
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
        border: Border.all(color: CitizenUi.sharedBorder),
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
            child: const Divider(height: 1, color: CitizenUi.sharedBorder),
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
    final double w = MediaQuery.of(context).size.width.clamp(0.0, 480.0);

    return SafeArea(
      child: Column(
        children: [
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

// ── Events sections skeleton (Featured / Today / Upcoming) ────────────────
// Shared by [EventsBodySkeleton] (initial load) and the EventsScreen pull-to-
// refresh state so both render the *same* skeleton. Sizing mirrors the real
// event cards and is clamped to 480 so it stays proportional on phones,
// landscape and tablets instead of ballooning on wide viewports.
class EventsSectionsSkeleton extends StatelessWidget {
  const EventsSectionsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final double w = MediaQuery.of(context).size.width.clamp(0.0, 480.0);
    final double cardW = w * 0.42;
    final double cardH = cardW * 1.42;
    final double imageH = cardW * 0.62;

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
                border: Border.all(color: CitizenUi.sharedBorder),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: w * 0.045),
        // Featured label
        Padding(
          padding: EdgeInsets.symmetric(horizontal: w * 0.04),
          child: _Shimmer(width: w * 0.38, height: w * 0.042, radius: 6),
        ),
        SizedBox(height: w * 0.02),
        // Featured card
        Padding(
          padding: EdgeInsets.symmetric(horizontal: w * 0.04),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(w * 0.035),
              border: Border.all(color: CitizenUi.sharedBorder),
            ),
            padding: EdgeInsets.all(w * 0.035),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Shimmer(width: w * 0.32, height: w * 0.38, radius: w * 0.025),
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
        // Today label
        Padding(
          padding: EdgeInsets.symmetric(horizontal: w * 0.04),
          child: _Shimmer(width: w * 0.30, height: w * 0.042, radius: 6),
        ),
        SizedBox(height: w * 0.02),
        eventCardList(),
        SizedBox(height: w * 0.045),
        // Upcoming label
        Padding(
          padding: EdgeInsets.symmetric(horizontal: w * 0.04),
          child: _Shimmer(width: w * 0.34, height: w * 0.042, radius: 6),
        ),
        SizedBox(height: w * 0.02),
        eventCardList(),
        SizedBox(height: w * 0.04),
      ],
    );
  }
}

// ── Events BODY skeleton ──────────────────────────────────────────────────────
// Full events screen body skeleton: hero banner + search + filter chips +
// the shared [EventsSectionsSkeleton]. Width is clamped to 480 to match the
// real EventsScreen layout across devices and orientations.
class EventsBodySkeleton extends StatelessWidget {
  const EventsBodySkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final double w = MediaQuery.of(context).size.width.clamp(0.0, 480.0);

    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.only(bottom: w * 0.06),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: w * 0.04),
          // Hero banner
          Padding(
            padding: EdgeInsets.symmetric(horizontal: w * 0.04),
            child: _Shimmer(
              width: double.infinity,
              height: w * 0.30,
              radius: w * 0.04,
            ),
          ),
          SizedBox(height: w * 0.035),
          // Search bar
          Padding(
            padding: EdgeInsets.symmetric(horizontal: w * 0.04),
            child: _Shimmer(
              width: double.infinity,
              height: w * 0.115,
              radius: w * 0.03,
            ),
          ),
          SizedBox(height: w * 0.025),
          // Filter chips
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
          // Featured / Today / Upcoming sections
          const EventsSectionsSkeleton(),
        ],
      ),
    );
  }
}

// ── Change Password skeleton ──────────────────────────────────────────────────
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
                    _Shimmer(width: size, height: size, radius: size / 2),
                    SizedBox(height: w * 0.07),
                    _Shimmer(
                      width: w * 0.52,
                      height: w * 0.052,
                      radius: w * 0.012,
                    ),
                    SizedBox(height: w * 0.025),
                    _Shimmer(
                      width: w * 0.64,
                      height: w * 0.032,
                      radius: w * 0.008,
                    ),
                    SizedBox(height: w * 0.010),
                    _Shimmer(
                      width: w * 0.50,
                      height: w * 0.032,
                      radius: w * 0.008,
                    ),
                    SizedBox(height: w * 0.07),
                    _Shimmer(
                      width: double.infinity,
                      height: w * 0.18,
                      radius: w * 0.035,
                    ),
                    SizedBox(height: w * 0.04),
                    _Shimmer(
                      width: double.infinity,
                      height: w * 0.18,
                      radius: w * 0.03,
                    ),
                    SizedBox(height: w * 0.07),
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

// ── My Submissions BODY skeleton ──────────────────────────────────────────────
class MySubmissionsBodySkeleton extends StatelessWidget {
  const MySubmissionsBodySkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    // Clamp to 480 like MySubmissionsScreen so the skeleton stays proportional
    // on landscape / tablet viewports instead of stretching.
    final double w = MediaQuery.of(context).size.width.clamp(0.0, 480.0);

    Widget card() => Container(
      margin: EdgeInsets.only(bottom: w * 0.03),
      padding: EdgeInsets.all(w * 0.035),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(w * 0.05),
        border: Border.all(color: const Color(0xFFEEF1F5)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1F2937).withValues(alpha: 0.07),
            blurRadius: 20,
            offset: const Offset(0, 9),
            spreadRadius: -8,
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Shimmer(width: w * 0.12, height: w * 0.12, radius: w * 0.038),
              SizedBox(height: w * 0.012),
              _Shimmer(width: w * 0.13, height: w * 0.022, radius: w * 0.006),
            ],
          ),
          SizedBox(width: w * 0.03),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _Shimmer(
                        width: double.infinity,
                        height: w * 0.034,
                        radius: w * 0.008,
                      ),
                    ),
                    SizedBox(width: w * 0.02),
                    _Shimmer(
                      width: w * 0.22,
                      height: w * 0.05,
                      radius: w * 0.04,
                    ),
                  ],
                ),
                SizedBox(height: w * 0.025),
                _Shimmer(
                  width: double.infinity,
                  height: w * 0.028,
                  radius: w * 0.008,
                ),
                SizedBox(height: w * 0.012),
                _Shimmer(width: w * 0.62, height: w * 0.028, radius: w * 0.008),
                SizedBox(height: w * 0.02),
                _Shimmer(width: w * 0.34, height: w * 0.024, radius: w * 0.006),
              ],
            ),
          ),
        ],
      ),
    );

    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(w * 0.04, w * 0.025, w * 0.04, w * 0.08),
      itemCount: 5,
      itemBuilder: (_, _) => card(),
    );
  }
}
