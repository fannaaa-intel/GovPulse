import 'package:flutter/material.dart';
import '../../../theme/app_colors.dart';
import '../../loading/loading_overlay.dart';
import '../home_enums.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../theme/mobile_metrics.dart';

// ── Main card widget ──────────────────────────────────────────────────────────
class HomeProfileCard extends StatelessWidget {
  final String username;
  final VerifStatus verifStatus;
  final String? fullName;
  final String? facePhotoUrl;
  final String? facePhotoPath;
  final bool profileLoading;
  final int notificationCount;
  final VoidCallback onNotificationTap;
  final VoidCallback onVerifyTap;

  /// Optional. When provided, drives all internal sizing instead of the raw
  /// screen width — lets the parent cap it on wide web so the card keeps its
  /// mobile proportions. Falls back to MediaQuery for existing callers.
  final double? width;

  const HomeProfileCard({
    super.key,
    required this.username,
    required this.verifStatus,
    required this.fullName,
    required this.facePhotoUrl,
    this.facePhotoPath,
    required this.profileLoading,
    required this.notificationCount,
    required this.onNotificationTap,
    required this.onVerifyTap,
    this.width,
  });

  ({String label, Color bg, Color border, Color dot, Color text})
  get _statusBadge {
    switch (verifStatus) {
      case VerifStatus.pending:
        return (
          label: 'Status: Pending',
          bg: const Color(0xFFFFF7ED),
          border: const Color(0xFFF59E0B),
          dot: const Color(0xFFF59E0B),
          text: const Color(0xFFB45309),
        );
      case VerifStatus.verified:
        return (
          label: 'Status: Verified',
          bg: const Color(0xFFECFDF5),
          border: const Color(0xFF22C55E),
          dot: const Color(0xFF22C55E),
          text: const Color(0xFF15803D),
        );
      case VerifStatus.none:
        return (
          label: 'Status: Not Verified',
          bg: const Color(0xFFFFF7ED),
          border: const Color(0xFFF59E0B),
          dot: const Color(0xFFF59E0B),
          text: const Color(0xFFB45309),
        );
    }
  }

  Widget _buildAvatar(double width) {
    final size = width * 0.17;

    // Both the "profile row still fetching" and the "photo still downloading"
    // states shimmer rather than spin, so the avatar reads as the same
    // placeholder the rest of the card uses instead of a second loading idiom.
    Widget shimmer() =>
        AppShimmerBox(width: size, height: size, radius: size / 2);

    if (profileLoading) return shimmer();

    if (facePhotoUrl != null && facePhotoUrl!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: facePhotoUrl!,
        cacheKey: facePhotoPath ?? facePhotoUrl!,
        memCacheWidth: 170,
        width: size,
        height: size,
        fit: BoxFit.cover,
        fadeInDuration: const Duration(milliseconds: 300),
        fadeOutDuration: const Duration(milliseconds: 100),
        placeholder: (context, url) => shimmer(),
        errorWidget: (context, url, error) => Image.asset(
          'assets/images/profilenew.webp',
          fit: BoxFit.cover,
          width: size,
          height: size,
        ),
      );
    }

    return Image.asset(
      'assets/images/profilenew.webp',
      fit: BoxFit.cover,
      width: size,
      height: size,
    );
  }

  /// Name + handle + status badge, shimmered while the profile row is in
  /// flight. Widths are fractions of the design width so the block keeps its
  /// proportions on phone, landscape and the 480-capped web column.
  Widget _buildIdentitySkeleton(double width) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppShimmerBox(
          width: width * 0.44,
          height: width * 0.052,
          radius: width * 0.012,
        ),
        SizedBox(height: width * 0.016),
        AppShimmerBox(
          width: width * 0.26,
          height: width * 0.030,
          radius: width * 0.008,
        ),
        SizedBox(height: width * 0.018),
        AppShimmerBox(
          width: width * 0.34,
          height: width * 0.055,
          radius: width * 0.03,
        ),
      ],
    );
  }

  Widget _buildNotificationBadge(double width) {
    return GestureDetector(
      onTap: onNotificationTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Image.asset(
            'assets/images/notifications.webp',
            width: width * 0.090,
            height: width * 0.090,
          ),
          // Only when there IS something unread. A fixed circle that always
          // rendered meant an empty bell still wore a green "0".
          if (notificationCount > 0)
            Positioned(
              right: -width * 0.008,
              top: -width * 0.008,
              // A pill that grows with its label, not a fixed circle: at two
              // digits the old square box clipped the text. minWidth == the
              // old diameter, so a single digit looks exactly as before.
              child: Container(
                constraints: BoxConstraints(
                  minWidth: width * 0.04,
                  minHeight: width * 0.04,
                ),
                padding: EdgeInsets.symmetric(horizontal: width * 0.008),
                decoration: BoxDecoration(
                  color: AppColors.green,
                  borderRadius: BorderRadius.circular(width * 0.02),
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                alignment: Alignment.center,
                child: Text(
                  notificationCount > 9 ? '9+' : '$notificationCount',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: width * 0.022,
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Use the caller-supplied width when given; otherwise fall back to the
    // screen width, clamped to the same 480 design width the callers pass. The
    // card is laid out inside a 480 column either way, so an unclamped fallback
    // would only mis-proportion it — noticeably so on a landscape phone, where
    // raw width is roughly double.
    final width = this.width ?? uiScaleWidth(context);
    final badge = _statusBadge;
    final isVerified = verifStatus == VerifStatus.verified;

    const String descNone =
        'Complete your identity verification as Aparri citizen to access full local government unit of Aparri services.';

    const String descPending =
        'Your submission is currently being processed by our admin team. '
        'Sit tight — once approved, you\'ll unlock the full potential of the app and all exclusive services for Aparri citizens!';

    final String desc = verifStatus == VerifStatus.pending
        ? descPending
        : verifStatus == VerifStatus.none
        ? descNone
        : '';

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: width * 0.04),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        width: double.infinity,
        padding: EdgeInsets.all(width * 0.04),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(width * 0.04),
          boxShadow: [
            BoxShadow(
              color: isVerified
                  ? const Color(0xFF22C55E).withValues(alpha: 0.18)
                  : Colors.black.withValues(alpha: .08),
              blurRadius: isVerified ? 18 : 10,
              offset: const Offset(0, 3),
            ),
          ],
          border: Border.all(
            color: isVerified
                ? const Color(0xFF22C55E).withValues(alpha: 0.30)
                : const Color(0xFFE5E7EB),
            width: isVerified ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Top row: avatar + name + notification ──
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isVerified)
                  _VerifiedAvatarRing(width: width, child: _buildAvatar(width))
                else
                  Container(
                    width: width * 0.17,
                    height: width * 0.17,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.10),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ClipOval(child: _buildAvatar(width)),
                  ),
                SizedBox(width: width * 0.03),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(top: width * 0.012),
                    child: profileLoading
                        ? _buildIdentitySkeleton(width)
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                fullName ?? username,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: width * 0.052,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF1F2937),
                                ),
                              ),
                              if (fullName != null) ...[
                                SizedBox(height: width * 0.004),
                                Text(
                                  '@$username',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: width * 0.030,
                                    fontWeight: FontWeight.w400,
                                    color: const Color(0xFF6B7280),
                                  ),
                                ),
                              ],
                              if (!isVerified) ...[
                                SizedBox(height: width * 0.008),
                                AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 350),
                                  child: Container(
                                    key: ValueKey(verifStatus),
                                    padding: EdgeInsets.symmetric(
                                      horizontal: width * 0.025,
                                      vertical: width * 0.012,
                                    ),
                                    decoration: BoxDecoration(
                                      color: badge.bg,
                                      borderRadius: BorderRadius.circular(
                                        width * 0.03,
                                      ),
                                      border: Border.all(color: badge.border),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: width * 0.010,
                                          height: width * 0.010,
                                          decoration: BoxDecoration(
                                            color: badge.dot,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        SizedBox(width: width * 0.012),
                                        Flexible(
                                          child: Text(
                                            badge.label,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: width * 0.030,
                                              color: badge.text,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                  ),
                ),
                _buildNotificationBadge(width),
              ],
            ),

            // ── Loading body ──
            // Stands in for the description + action button so the card keeps
            // roughly its final height and doesn't snap taller once the profile
            // lands. Nothing below renders while loading — the verification
            // state isn't known yet, and guessing it would flash "Verify Now"
            // at an already-verified citizen.
            if (profileLoading) ...[
              SizedBox(height: width * 0.04),
              AppShimmerBox(
                width: double.infinity,
                height: width * 0.030,
                radius: width * 0.008,
              ),
              SizedBox(height: width * 0.014),
              AppShimmerBox(
                width: width * 0.62,
                height: width * 0.030,
                radius: width * 0.008,
              ),
              SizedBox(height: width * 0.045),
              AppShimmerBox(
                width: double.infinity,
                height: width * 0.12,
                radius: width * 0.03,
              ),
            ],

            // ── Description (non-verified) ──
            if (!profileLoading && desc.isNotEmpty) ...[
              SizedBox(height: width * 0.04),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                child: Text(
                  desc,
                  key: ValueKey(verifStatus),
                  style: TextStyle(
                    fontSize: width * 0.032,
                    color: const Color(0xFF374151),
                    height: 1.5,
                  ),
                ),
              ),
            ],

            // ── Verified shimmer strip ──
            if (!profileLoading && isVerified) ...[
              SizedBox(height: width * 0.038),
              _VerifiedStripShimmer(width: width),
            ],

            // ── Action button (non-verified) ──
            if (!profileLoading && !isVerified) ...[
              SizedBox(height: width * 0.045),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: verifStatus == VerifStatus.pending
                      ? null
                      : onVerifyTap,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    elevation: 0,
                    minimumSize: Size.zero,
                    fixedSize: Size(double.infinity, width * 0.12),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(width * 0.03),
                    ),
                    padding: EdgeInsets.zero,
                  ),
                  child: verifStatus == VerifStatus.pending
                      ? _PendingButtonContent(width: width)
                      : _VerifyNowButtonContent(width: width),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Verified Avatar Ring ──────────────────────────────────────────────────────
class _VerifiedAvatarRing extends StatefulWidget {
  final double width;
  final Widget child;
  const _VerifiedAvatarRing({required this.width, required this.child});

  @override
  State<_VerifiedAvatarRing> createState() => _VerifiedAvatarRingState();
}

class _VerifiedAvatarRingState extends State<_VerifiedAvatarRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.width * 0.17;
    final ringSize = size + widget.width * 0.022;

    return SizedBox(
      width: ringSize,
      height: ringSize,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, child) {
          return Stack(
            alignment: Alignment.center,
            children: [
              Transform.rotate(
                angle: _ctrl.value * 2 * 3.14159265,
                child: Container(
                  width: ringSize,
                  height: ringSize,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: SweepGradient(
                      colors: [
                        Color(0xFF4ADE80),
                        Color(0xFF22C55E),
                        Color(0xFF16A34A),
                        Color(0xFF86EFAC),
                        Color(0xFF4ADE80),
                      ],
                    ),
                  ),
                ),
              ),
              Container(
                width: size + widget.width * 0.010,
                height: size + widget.width * 0.010,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              ),
              ClipOval(
                child: SizedBox(width: size, height: size, child: child),
              ),
            ],
          );
        },
        child: widget.child,
      ),
    );
  }
}

// ── Verified Strip Shimmer ────────────────────────────────────────────────────
class _VerifiedStripShimmer extends StatefulWidget {
  final double width;
  const _VerifiedStripShimmer({required this.width});

  @override
  State<_VerifiedStripShimmer> createState() => _VerifiedStripShimmerState();
}

class _VerifiedStripShimmerState extends State<_VerifiedStripShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
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
    final w = widget.width;
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, _) {
        final t = -0.25 + (_anim.value * 1.50);
        return Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            vertical: w * 0.028,
            horizontal: w * 0.04,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(w * 0.03),
            border: Border.all(
              color: const Color(0xFF22C55E).withValues(alpha: 0.40),
            ),
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                const Color(0xFFECFDF5),
                const Color(0xFFECFDF5),
                Color.lerp(const Color(0xFFECFDF5), Colors.white, 0.85)!,
                Colors.white.withValues(alpha: 0.95),
                Color.lerp(const Color(0xFFECFDF5), Colors.white, 0.85)!,
                const Color(0xFFECFDF5),
                const Color(0xFFECFDF5),
              ],
              stops: [
                0.0,
                (t - 0.12).clamp(0.0, 1.0),
                (t - 0.04).clamp(0.0, 1.0),
                t.clamp(0.0, 1.0),
                (t + 0.04).clamp(0.0, 1.0),
                (t + 0.12).clamp(0.0, 1.0),
                1.0,
              ],
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'assets/images/check.webp',
                width: w * 0.042,
                height: w * 0.042,
                color: const Color(0xFF15803D),
              ),
              SizedBox(width: w * 0.020),
              // Flexible, not bare: this label is the widest thing in the card
              // and the Row gave it no way to yield. At 320dp with the font
              // size at Android's Largest it clears the strip by about 5px in
              // English, and the Tagalog rendering of the same sentence is
              // longer than that margin — so the layout was one setting or one
              // translation away from a striped overflow on the home screen.
              Flexible(
                child: Text(
                  'You\'re a verified Aparri citizen',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: w * 0.032,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF15803D),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Verify Now Button ─────────────────────────────────────────────────────────
class _VerifyNowButtonContent extends StatefulWidget {
  final double width;
  const _VerifyNowButtonContent({required this.width});

  @override
  State<_VerifyNowButtonContent> createState() =>
      _VerifyNowButtonContentState();
}

class _VerifyNowButtonContentState extends State<_VerifyNowButtonContent>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
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
    final w = widget.width;
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, _) {
        final t = -0.25 + (_anim.value * 1.50);
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(w * 0.03),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF22C55E),
                const Color(0xFF22C55E),
                Color.lerp(const Color(0xFF22C55E), Colors.white, 0.28)!,
                Color.lerp(const Color(0xFF22C55E), Colors.white, 0.38)!,
                Color.lerp(const Color(0xFF22C55E), Colors.white, 0.28)!,
                const Color(0xFF22C55E),
                const Color(0xFF22C55E),
              ],
              stops: [
                0.0,
                (t - 0.12).clamp(0.0, 1.0),
                (t - 0.04).clamp(0.0, 1.0),
                t.clamp(0.0, 1.0),
                (t + 0.04).clamp(0.0, 1.0),
                (t + 0.12).clamp(0.0, 1.0),
                1.0,
              ],
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            'Verify Now',
            style: TextStyle(
              fontSize: w * 0.038,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        );
      },
    );
  }
}

// ── Pending Button ────────────────────────────────────────────────────────────
class _PendingButtonContent extends StatefulWidget {
  final double width;
  const _PendingButtonContent({required this.width});

  @override
  State<_PendingButtonContent> createState() => _PendingButtonContentState();
}

class _PendingButtonContentState extends State<_PendingButtonContent>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
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
    final w = widget.width;
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, _) {
        final t = -0.25 + (_anim.value * 1.50);
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(w * 0.03),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFFF59E0B),
                const Color(0xFFF59E0B),
                Color.lerp(const Color(0xFFF59E0B), Colors.white, 0.22)!,
                Color.lerp(const Color(0xFFF59E0B), Colors.white, 0.32)!,
                Color.lerp(const Color(0xFFF59E0B), Colors.white, 0.22)!,
                const Color(0xFFF59E0B),
                const Color(0xFFF59E0B),
              ],
              stops: [
                0.0,
                (t - 0.12).clamp(0.0, 1.0),
                (t - 0.04).clamp(0.0, 1.0),
                t.clamp(0.0, 1.0),
                (t + 0.04).clamp(0.0, 1.0),
                (t + 0.12).clamp(0.0, 1.0),
                1.0,
              ],
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            'Verification In Progress',
            style: TextStyle(
              fontSize: w * 0.038,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        );
      },
    );
  }
}
