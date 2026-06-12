import 'package:flutter/material.dart';
import '../../home_enums.dart';
import 'package:cached_network_image/cached_network_image.dart';

class HomeProfileStrip extends StatelessWidget {
  final String username;
  final String? fullName;
  final String? facePhotoUrl;
  final VerifStatus verifStatus;
  final bool profileLoading;
  final int notificationCount;
  final VoidCallback onNotificationTap;
  final VoidCallback onVerifyTap;

  const HomeProfileStrip({
    super.key,
    required this.username,
    required this.fullName,
    required this.facePhotoUrl,
    required this.verifStatus,
    required this.profileLoading,
    required this.notificationCount,
    required this.onNotificationTap,
    required this.onVerifyTap,
  });

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final isVerified = verifStatus == VerifStatus.verified;
    final isPending = verifStatus == VerifStatus.pending;
    final width = MediaQuery.of(context).size.width;
    final isNarrow = width < 760;

    return Container(
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0D2352).withOpacity(0.22),
            blurRadius: 48,
            spreadRadius: -6,
            offset: const Offset(0, 20),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF0A1628),
                    Color(0xFF0D2352),
                    Color(0xFF10337A),
                    Color(0xFF0F2D6B),
                  ],
                  stops: [0.0, 0.35, 0.70, 1.0],
                ),
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),
          Positioned(
            top: -60,
            right: -40,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF2D9CDB).withOpacity(0.18),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -40,
            left: 60,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF22C55E).withOpacity(0.10),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned.fill(child: CustomPaint(painter: _DotGridPainter())),
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isNarrow ? 20 : 28,
              vertical: 22,
            ),
            child: isNarrow
                ? _buildNarrow(isVerified, isPending)
                : _buildWide(isVerified, isPending),
          ),
        ],
      ),
    );
  }

  Widget _buildWide(bool isVerified, bool isPending) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _Avatar(
          url: facePhotoUrl,
          loading: profileLoading,
          isVerified: isVerified,
        ),
        const SizedBox(width: 20),
        Expanded(
          child: _NameBlock(
            username: username,
            fullName: fullName,
            greeting: _greeting(),
            verifStatus: verifStatus,
          ),
        ),
        const SizedBox(width: 20),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isVerified)
              _StatCard(
                icon: Icons.shield_rounded,
                iconColor: const Color(0xFF22C55E),
                label: 'Account Verified',
                value: 'Full access',
                onTap: null,
              )
            else
              _StatCard(
                icon: Icons.verified_user_outlined,
                iconColor: const Color(0xFFFBBF24),
                label: isPending ? 'Verification' : 'Get verified',
                value: isPending ? 'Under review' : 'Tap to start',
                onTap: isPending ? null : onVerifyTap,
              ),
            const SizedBox(width: 12),
            _NotifCard(count: notificationCount, onTap: onNotificationTap),
          ],
        ),
      ],
    );
  }

  Widget _buildNarrow(bool isVerified, bool isPending) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _Avatar(
              url: facePhotoUrl,
              loading: profileLoading,
              isVerified: isVerified,
              size: 48,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _NameBlock(
                username: username,
                fullName: fullName,
                greeting: _greeting(),
                verifStatus: verifStatus,
              ),
            ),
            _NotifCard(
              count: notificationCount,
              onTap: onNotificationTap,
              compact: true,
            ),
          ],
        ),
        if (!isVerified) ...[
          const SizedBox(height: 14),
          _VerifyBanner(isPending: isPending, onTap: onVerifyTap),
        ],
      ],
    );
  }
}

class _DotGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {}
  @override
  bool shouldRepaint(_) => false;
}

class _Avatar extends StatelessWidget {
  final String? url;
  final bool loading;
  final bool isVerified;
  final double size;

  const _Avatar({
    required this.url,
    required this.loading,
    required this.isVerified,
    this.size = 60,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size + 6,
      height: size + 6,
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: isVerified
            ? const LinearGradient(
                colors: [Color(0xFF22C55E), Color(0xFF16A34A)],
              )
            : const LinearGradient(
                colors: [Color(0xFF475569), Color(0xFF334155)],
              ),
        boxShadow: isVerified
            ? [
                BoxShadow(
                  color: const Color(0xFF22C55E).withOpacity(0.35),
                  blurRadius: 16,
                  spreadRadius: -2,
                ),
              ]
            : null,
      ),
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Color(0xFF0A1628),
        ),
        child: ClipOval(
          child: SizedBox(
            width: size,
            height: size,
            child: loading
                ? Container(
                    color: const Color(0xFF1E3A5F),
                    child: Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white.withOpacity(0.6),
                        ),
                      ),
                    ),
                  )
                // AFTER
                : (url != null && url!.isNotEmpty)
                ? CachedNetworkImage(
                    imageUrl: url!,
                    cacheKey: url,
                    fit: BoxFit.cover,
                    width: size,
                    height: size,
                    placeholder: (_, _) => Container(
                      color: const Color(0xFF1E3A5F),
                      child: Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white.withOpacity(0.6),
                          ),
                        ),
                      ),
                    ),
                    errorWidget: (_, _, _) => Image.asset(
                      'assets/images/profilenew.webp',
                      fit: BoxFit.cover,
                    ),
                  )
                : Image.asset(
                    'assets/images/profilenew.webp',
                    fit: BoxFit.cover,
                  ),
          ),
        ),
      ),
    );
  }
}

// ── Name block ────────────────────────────────────────────────────────────────
class _NameBlock extends StatelessWidget {
  final String username;
  final String? fullName;
  final String greeting;
  final VerifStatus verifStatus;

  const _NameBlock({
    required this.username,
    required this.fullName,
    required this.greeting,
    required this.verifStatus,
  });

  /// Returns a short motivational/status saying for each verification state.
  String _saying() {
    switch (verifStatus) {
      case VerifStatus.verified:
        return 'Your identity is confirmed. Welcome back!';
      case VerifStatus.pending:
        return 'Hang tight — your verification is being reviewed.';
      case VerifStatus.none:
        return 'Verify your identity to unlock all features.';
    }
  }

  Color _sayingColor() {
    switch (verifStatus) {
      case VerifStatus.verified:
        return const Color(0xFF4ADE80); // green-400
      case VerifStatus.pending:
        return const Color(0xFFFCD34D); // amber-300
      case VerifStatus.none:
        return const Color(0xFF93C5FD); // blue-300
    }
  }

  IconData _sayingIcon() {
    switch (verifStatus) {
      case VerifStatus.verified:
        return Icons.check_circle_rounded;
      case VerifStatus.pending:
        return Icons.hourglass_top_rounded;
      case VerifStatus.none:
        return Icons.info_outline_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Greeting row ───────────────────────────────────────────
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              greeting,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.white.withOpacity(0.55),
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(width: 6),
            const Text('👋', style: TextStyle(fontSize: 12)),
          ],
        ),
        const SizedBox(height: 3),

        // ── Name + chip ────────────────────────────────────────────
        Row(
          children: [
            Flexible(
              child: Text(
                fullName ?? username,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -0.5,
                  height: 1.1,
                ),
              ),
            ),
            const SizedBox(width: 10),
            _VerifChip(status: verifStatus),
          ],
        ),
        const SizedBox(height: 5),

        // ── Saying / status line ───────────────────────────────────
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _sayingIcon(),
              size: 11,
              color: _sayingColor().withOpacity(0.85),
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                _saying(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: _sayingColor().withOpacity(0.80),
                  letterSpacing: 0.1,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),

        // ── Location / username row ────────────────────────────────
        Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: Color(0xFF22C55E),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'Aparri, Cagayan  •  @$username',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withOpacity(0.50),
                  letterSpacing: 0.1,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _VerifChip extends StatelessWidget {
  final VerifStatus status;
  const _VerifChip({required this.status});

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case VerifStatus.verified:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF22C55E).withOpacity(0.18),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: const Color(0xFF22C55E).withOpacity(0.40),
              width: 1,
            ),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.verified_rounded, size: 11, color: Color(0xFF22C55E)),
              SizedBox(width: 4),
              Text(
                'Verified',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF22C55E),
                ),
              ),
            ],
          ),
        );
      case VerifStatus.pending:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFFBBF24).withOpacity(0.15),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: const Color(0xFFFBBF24).withOpacity(0.35),
              width: 1,
            ),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 8,
                height: 8,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: Color(0xFFFBBF24),
                ),
              ),
              SizedBox(width: 5),
              Text(
                'Pending',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFFBBF24),
                ),
              ),
            ],
          ),
        );
      case VerifStatus.none:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withOpacity(0.18), width: 1),
          ),
          child: Text(
            'Unverified',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.white.withOpacity(0.55),
            ),
          ),
        );
    }
  }
}

// ── Stat card ─────────────────────────────────────────────────────────────────
class _StatCard extends StatefulWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final VoidCallback? onTap;

  const _StatCard({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  State<_StatCard> createState() => _StatCardState();
}

class _StatCardState extends State<_StatCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final tappable = widget.onTap != null;
    return MouseRegion(
      cursor: tappable ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(_hover ? 0.14 : 0.09),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Colors.white.withOpacity(_hover ? 0.28 : 0.14),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: widget.iconColor.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(widget.icon, size: 18, color: widget.iconColor),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.label,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withOpacity(0.55),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.value,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Notification card ─────────────────────────────────────────────────────────
class _NotifCard extends StatefulWidget {
  final int count;
  final VoidCallback onTap;
  final bool compact;

  const _NotifCard({
    required this.count,
    required this.onTap,
    this.compact = false,
  });

  @override
  State<_NotifCard> createState() => _NotifCardState();
}

class _NotifCardState extends State<_NotifCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          padding: widget.compact
              ? const EdgeInsets.all(10)
              : const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(_hover ? 0.14 : 0.09),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Colors.white.withOpacity(_hover ? 0.28 : 0.14),
              width: 1,
            ),
          ),
          child: widget.compact
              ? _buildIcon()
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildIcon(),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.count > 0
                              ? '${widget.count} New'
                              : 'Notifications',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          widget.count > 0 ? 'Tap to view' : 'All caught up',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withOpacity(0.50),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildIcon() {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: const Color(0xFF3B82F6).withOpacity(0.20),
            borderRadius: BorderRadius.circular(9),
          ),
          child: const Icon(
            Icons.notifications_rounded,
            size: 20,
            color: Color(0xFF93C5FD),
          ),
        ),
        if (widget.count > 0)
          Positioned(
            right: -4,
            top: -4,
            child: Container(
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF22C55E),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF0A1628), width: 1.5),
              ),
              alignment: Alignment.center,
              child: Text(
                '${widget.count}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ── Verify banner ─────────────────────────────────────────────────────────────
class _VerifyBanner extends StatefulWidget {
  final bool isPending;
  final VoidCallback onTap;

  const _VerifyBanner({required this.isPending, required this.onTap});

  @override
  State<_VerifyBanner> createState() => _VerifyBannerState();
}

class _VerifyBannerState extends State<_VerifyBanner> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.isPending
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.isPending ? null : widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            color: widget.isPending
                ? const Color(0xFFFBBF24).withOpacity(0.12)
                : (_hover
                      ? const Color(0xFF22C55E).withOpacity(0.15)
                      : const Color(0xFF22C55E).withOpacity(0.10)),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: widget.isPending
                  ? const Color(0xFFFBBF24).withOpacity(0.35)
                  : const Color(0xFF22C55E).withOpacity(_hover ? 0.50 : 0.35),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                widget.isPending
                    ? Icons.hourglass_top_rounded
                    : Icons.verified_user_outlined,
                size: 15,
                color: widget.isPending
                    ? const Color(0xFFFBBF24)
                    : const Color(0xFF22C55E),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.isPending
                      ? 'Verification under review'
                      : 'Verify your account to unlock all features',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: widget.isPending
                        ? const Color(0xFFFBBF24)
                        : const Color(0xFF22C55E),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!widget.isPending) ...[
                AnimatedSlide(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  offset: Offset(_hover ? 0.15 : 0, 0),
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    size: 14,
                    color: const Color(0xFF22C55E).withOpacity(0.7),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
