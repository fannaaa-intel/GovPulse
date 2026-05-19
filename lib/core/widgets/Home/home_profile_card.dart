import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import 'home_enums.dart';

// ── Main card widget ──────────────────────────────────────────────────────────
class HomeProfileCard extends StatelessWidget {
  final String username;
  final VerifStatus verifStatus;
  final String? fullName;
  final String? facePhotoUrl;
  final bool profileLoading;
  final int notificationCount;
  final VoidCallback onNotificationTap;
  final VoidCallback onVerifyTap;

  const HomeProfileCard({
    super.key,
    required this.username,
    required this.verifStatus,
    required this.fullName,
    required this.facePhotoUrl,
    required this.profileLoading,
    required this.notificationCount,
    required this.onNotificationTap,
    required this.onVerifyTap,
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

    if (profileLoading) {
      return Container(
        width: size,
        height: size,
        color: const Color(0xFFE5E7EB),
        child: Center(
          child: SizedBox(
            width: size * 0.40,
            height: size * 0.40,
            child: const CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.primaryBlue,
            ),
          ),
        ),
      );
    }

    if (facePhotoUrl != null && facePhotoUrl!.isNotEmpty) {
      return Image.network(
        facePhotoUrl!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Container(
            width: size,
            height: size,
            color: const Color(0xFFE5E7EB),
            child: Center(
              child: SizedBox(
                width: size * 0.40,
                height: size * 0.40,
                child: const CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.primaryBlue,
                ),
              ),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) => Image.asset(
          'assets/images/profilenew.png',
          fit: BoxFit.cover,
          width: size,
          height: size,
        ),
      );
    }

    return Image.asset(
      'assets/images/profilenew.png',
      fit: BoxFit.cover,
      width: size,
      height: size,
    );
  }

  Widget _buildNotificationBadge(double width) {
    return GestureDetector(
      onTap: onNotificationTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Image.asset(
            'assets/images/notifications.png',
            width: width * 0.090,
            height: width * 0.090,
          ),
          Positioned(
            right: -width * 0.008,
            top: -width * 0.008,
            child: Container(
              width: width * 0.04,
              height: width * 0.04,
              decoration: BoxDecoration(
                color: AppColors.green,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              alignment: Alignment.center,
              child: Text(
                '$notificationCount',
                style: TextStyle(
                  fontSize: width * 0.022,
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
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
    final width = MediaQuery.of(context).size.width;
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fullName ?? username,
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
                                  profileLoading
                                      ? SizedBox(
                                          width: width * 0.022,
                                          height: width * 0.022,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 1.5,
                                            color: badge.dot,
                                          ),
                                        )
                                      : Container(
                                          width: width * 0.010,
                                          height: width * 0.010,
                                          decoration: BoxDecoration(
                                            color: badge.dot,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                  SizedBox(width: width * 0.012),
                                  Text(
                                    profileLoading ? 'Loading...' : badge.label,
                                    style: TextStyle(
                                      fontSize: width * 0.030,
                                      color: badge.text,
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

            // ── Description (non-verified) ──
            if (desc.isNotEmpty) ...[
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
            if (isVerified) ...[
              SizedBox(height: width * 0.038),
              _VerifiedStripShimmer(width: width),
            ],

            // ── Action button (non-verified) ──
            if (!isVerified) ...[
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
                'assets/images/check.png',
                width: w * 0.042,
                height: w * 0.042,
                color: const Color(0xFF15803D),
              ),
              SizedBox(width: w * 0.020),
              Text(
                'You\'re a verified Aparri citizen',
                style: TextStyle(
                  fontSize: w * 0.032,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF15803D),
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
