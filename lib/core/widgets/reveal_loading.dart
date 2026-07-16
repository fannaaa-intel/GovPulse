import 'package:flutter/material.dart';

/// A bottom-to-top "develops upward" loading reveal, drawn OVER a media
/// thumbnail while that item is still being processed (e.g. baking the GPS
/// stamp into a fresh camera photo, decoding a gallery image, generating a
/// video thumbnail).
///
/// It is a SINGLE determinate sweep — NOT a loop. While busy the reveal
/// trickles upward and eases into a near-top hold; it never resets back to the
/// bottom. The moment [completed] flips true it finishes the last stretch to
/// the very top, rests there for a beat, then fades out and calls [onFinished]
/// so the parent can drop it. The thumbnail's real image sits underneath the
/// whole time; this only animates a dim cover that recedes upward plus a bright
/// scan line at the reveal edge, so the photo appears to "load" from the bottom
/// up with no blocking spinner.
class RevealLoading extends StatefulWidget {
  final BorderRadius borderRadius;

  /// Flip to true when the underlying work is done. Drives the closing sweep to
  /// the very top followed by a quick fade-out.
  final bool completed;

  /// Fired once the closing sweep + fade have played out — the parent should
  /// stop rendering this reveal at this point.
  final VoidCallback? onFinished;

  const RevealLoading({
    super.key,
    this.borderRadius = BorderRadius.zero,
    this.completed = false,
    this.onFinished,
  });

  @override
  State<RevealLoading> createState() => _RevealLoadingState();
}

class _RevealLoadingState extends State<RevealLoading>
    with SingleTickerProviderStateMixin {
  // Reveal fraction: 0 = fully covered (bottom), 1 = fully revealed (top).
  late final AnimationController _c = AnimationController(vsync: this);

  // While busy the sweep eases up to this cap and waits there — never the full
  // 1.0, so there is always visible headroom to complete into once work ends.
  static const double _busyCap = 0.9;

  bool _finishing = false;
  bool _fadingOut = false;

  @override
  void initState() {
    super.initState();
    if (widget.completed) {
      _finish(); // Work was already done before we mounted.
    } else {
      _startBusySweep();
    }
  }

  // Slow, decelerating climb to the near-top hold. Long enough that a typical
  // capture finishes mid-climb; if processing runs long the reveal simply rests
  // at the cap (no reset, no loop).
  void _startBusySweep() {
    _c.animateTo(
      _busyCap,
      duration: const Duration(milliseconds: 5000),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _finish() async {
    if (_finishing) return;
    _finishing = true;
    // Complete the last stretch to the very top…
    await _c.animateTo(
      1,
      duration: const Duration(milliseconds: 340),
      curve: Curves.easeOut,
    );
    if (!mounted) return;
    // …rest at the top for a beat, then fade out and hand back to the parent.
    setState(() => _fadingOut = true);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    widget.onFinished?.call();
  }

  @override
  void didUpdateWidget(RevealLoading old) {
    super.didUpdateWidget(old);
    if (widget.completed && !old.completed) _finish();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: _fadingOut ? 0 : 1,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
        child: ClipRRect(
          borderRadius: widget.borderRadius,
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              // Reveal fraction 0 → 1 (already eased by the controller).
              final t = _c.value;
              final coverFactor = (1 - t).clamp(0.0001, 1.0);
              return Stack(
                fit: StackFit.expand,
                children: [
                  // Dim cover over the not-yet-revealed (top) portion; recedes up.
                  Align(
                    alignment: Alignment.topCenter,
                    child: FractionallySizedBox(
                      heightFactor: coverFactor,
                      widthFactor: 1,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.55),
                              Colors.black.withValues(alpha: 0.28),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Bright scan line at the reveal boundary.
                  Align(
                    alignment: Alignment(0, 1 - 2 * t),
                    child: Container(
                      height: 2.5,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.85),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.white.withValues(alpha: 0.55),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
