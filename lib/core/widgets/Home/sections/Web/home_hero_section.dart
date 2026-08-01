// lib/core/widgets/Home/sections/Web/home_hero_section.dart

import 'package:flutter/material.dart';
import '../../home_enums.dart';
import 'package:cached_network_image/cached_network_image.dart';
// ---------------------------------------------------------------------------
// Layout notes (web only)
// ---------------------------------------------------------------------------
// The profile card matches the COMMUNITY ("Latest Updates") panel width at
// every web width, using the same split the dashboard uses:
//
//   bandWidth = min(screen, contentMaxWidth) - 2*sidePadding
//   card      = 2-column ? (bandWidth - colGap) * communityFlex  ← left column
//                        : bandWidth                             ← full band
//
// Left edges always line up (both are left-aligned in the same centered band),
// and matching the width this way makes the right edges line up too — so in
// single-column the card spans the panel, and in two-column it stops exactly
// where Latest Updates stops (not over Quick Actions).
//
// The card's INNER content is fluid: a ROW layout (avatar • name+badge •
// description • action) down to ~460px card width, falling back to a STACKED
// layout below that — which still keeps the description ("saying") visible.
//
// Because the card and the community panel are both left-aligned inside the
// same centered band, matching the WIDTH this way makes the two share the same
// left AND right edge across the whole responsive range.
//
// The card's INNER content is fully fluid: a ROW layout (avatar • name+badge •
// description • action) that scales every element with the card width, with the
// description kept as a centered, readable block so it never smears across very
// wide cards. Only at genuinely tiny widths (< 460px card) does it fall back to
// the STACKED layout, which still keeps the description ("saying") visible.
// All inner decisions key off the card's own width via LayoutBuilder.
// ---------------------------------------------------------------------------

/// Identifies the overlapping profile card so a layout test can measure its
/// true bounds. See home_hero_overlap_test.dart.
const Key kHomeHeroProfileCardKey = Key('home-hero-profile-card');

class HomeHeroSection extends StatelessWidget {
  final String username;
  final String? fullName;
  final String? facePhotoUrl;
  final String? facePhotoPath;
  final VerifStatus verifStatus;
  final bool profileLoading;
  final VoidCallback onVerifyTap;

  final double contentMaxWidth;
  final double sidePadding;

  // These three MUST mirror home_page.dart's dashboard so the card matches the
  // Latest Updates column. If your home page uses different values, change
  // these to match (they're the only knobs):
  //   _kDashboardBreakpoint → width where the dashboard becomes 2-column
  //   _kColGap              → gap between Community and Quick Actions
  //   _kCommunityFlex       → Community's share of (band - gap). EXACT match to
  //                           the dashboard's `leftW = (totalW - gap) * 0.62`.
  static const double _kDashboardBreakpoint = 1100;
  static const double _kColGap = 28;
  static const double _kCommunityFlex = 0.62;

  const HomeHeroSection({
    super.key,
    required this.username,
    required this.fullName,
    required this.facePhotoUrl,
    this.facePhotoPath,
    required this.verifStatus,
    required this.profileLoading,
    required this.onVerifyTap,
    this.contentMaxWidth = 1280,
    this.sidePadding = 32,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final pad = sidePadding;

    // ── Card width === community (Latest Updates) panel width ──────────────
    // Clamp the screen to the cap FIRST, then subtract padding — this is the
    // exact content band the dashboard's LayoutBuilder sees.
    final double bandWidth = (screenWidth.clamp(0.0, contentMaxWidth) - pad * 2)
        .clamp(0.0, double.infinity);

    // 2-column → match the Community left column; 1-column → fill the band.
    final double cardWidth = screenWidth >= _kDashboardBreakpoint
        ? ((bandWidth - _kColGap) * _kCommunityFlex).clamp(0.0, bandWidth)
        : bandWidth;

    // bghome.webp is 3324 × 960 ≈ aspect 3.46

    const double heroAspect = 3.46;

    final double heroHeight = screenWidth < 1024
        ? 280.0
        : (screenWidth / heroAspect).clamp(280.0, 320.0);
    // How much the card overlaps the hero image from the bottom.
    final double cardOverhang = screenWidth < 1024 ? 32.0 : 40.0;

    // ── Why this is a Column + Transform, not a Stack + Positioned ──────────
    // The card used to be Positioned(bottom: 0) inside a Stack whose height was
    // a CONSTANT (heroHeight + cardOverhang + 40). Anchoring to the bottom means
    // a taller card grows UPWARD, so the overlap was really `cardHeight -
    // cardOverhang - 40` — it depended on the card's own height, which is the
    // one thing that changes most across the responsive range.
    //
    // On desktop the card is a short single row and it happened to work out.
    // On a phone the card falls back to its tall STACKED layout, grew upward,
    // and buried the hero subtitle completely (reported from a real phone,
    // 2026-08-01; pinned by home_hero_overlap_test.dart at 320-430px).
    //
    // Laying the card out in normal Column flow makes its height accounted for,
    // and Transform.translate lifts it by EXACTLY cardOverhang without changing
    // layout — so the overlap is now a fixed amount no matter how tall the card
    // gets. Transform also transforms hit-testing, so taps still land.
    // The trailing gap is trimmed by the same amount to keep the whitespace
    // below the card at the intended ~40px.
    return Column(
      children: [
        // ── Hero image ──────────────────────────────────────────────────────
        Column(
          children: [
            // minHeight, not a fixed height: the hero is allowed to GROW when
            // its copy needs more room. The text block below is the Stack's
            // only non-positioned child, so it is what sizes the Stack, and it
            // reserves cardOverhang at the foot — which makes it structurally
            // impossible for the copy to end up underneath the profile card.
            //
            // A fixed height cannot promise that. The copy wraps to more lines
            // at narrow widths and at large system text scales (an accessibility
            // setting, not an edge case), and at ~1.5x the subtitle needs a
            // third and fourth line that a 280px band has no room for.
            ConstrainedBox(
              constraints: BoxConstraints(minHeight: heroHeight),
              child: Stack(
                // Applies to the non-positioned text child, preserving the
                // vertically-centred look the fixed-height version had.
                alignment: Alignment.center,
                children: [
                  // Background image
                  Positioned.fill(
                    child: Image.asset(
                      'assets/images/bghome.webp',
                      fit: BoxFit.cover,
                      alignment: const Alignment(0, 0.3),
                      errorBuilder: (_, _, _) => Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFFBFE3FF), Color(0xFF7FB8E6)],
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Left-side light scrim
                  const Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            Color(0x80FFFFFF),
                            Color(0x10FFFFFF),
                            Color(0x00FFFFFF),
                          ],
                          stops: [0.0, 0.5, 1.0],
                        ),
                      ),
                    ),
                  ),

                  // Bottom fade into page background
                  const Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 80,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Color(0xFFF3F6FC)],
                        ),
                      ),
                    ),
                  ),

                  // Hero text — the Stack's ONLY non-positioned child, so it is
                  // what gives the Stack its height. A Row (not a Center) does
                  // the horizontal centring: Row wraps to its child's height,
                  // whereas Center/Align would expand to fill and defeat the
                  // whole point of sizing the Stack from the copy.
                  //
                  // The bottom padding is the collision guarantee — it reserves
                  // the strip the profile card is lifted into.
                  Padding(
                    padding: EdgeInsets.only(
                      top: screenWidth < 600 ? 36 : 56,
                      bottom: cardOverhang + 16,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Flexible(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: contentMaxWidth,
                            ),
                            child: Padding(
                              padding: EdgeInsets.symmetric(horizontal: pad),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: _HeroText(screenWidth: screenWidth),
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

          ],
        ),

        // ── Profile card — left-aligned, matched to the community column ─────
        Transform.translate(
          offset: Offset(0, -cardOverhang),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: contentMaxWidth),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: pad),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    // Keyed so a layout test can measure the card's real
                    // bounds. Measuring a text INSIDE it silently passes: the
                    // copy sits below the card's top edge, which is exactly
                    // where the hero-overlap bug happens.
                    key: kHomeHeroProfileCardKey,
                    width: cardWidth,
                    child: _ProfileCard(
                      username: username,
                      fullName: fullName,
                      facePhotoUrl: facePhotoUrl,
                      facePhotoPath: facePhotoPath,
                      verifStatus: verifStatus,
                      loading: profileLoading,
                      onVerifyTap: onVerifyTap,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),

        // Lifting the card by cardOverhang leaves that much slack at the foot
        // of the Column, so only the remainder is added to reach the intended
        // ~40px of breathing room before the dashboard starts.
        SizedBox(height: (40 - cardOverhang).clamp(0.0, 40.0)),
      ],
    );
  }
}

// ── Hero text with fluid sizing ────────────────────────────────────────────
class _HeroText extends StatelessWidget {
  final double screenWidth;
  const _HeroText({required this.screenWidth});

  @override
  Widget build(BuildContext context) {
    final double titleSize = screenWidth < 480
        ? 24
        : screenWidth < 768
        ? 30
        : screenWidth < 1024
        ? 34
        : 38;

    final double subtitleSize = screenWidth < 480 ? 12 : 14.5;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: 'Building a better\ncommunity ',
                style: TextStyle(
                  fontSize: titleSize,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF0D2352),
                  height: 1.15,
                  letterSpacing: -0.8,
                ),
              ),
              TextSpan(
                text: 'together',
                style: TextStyle(
                  fontSize: titleSize,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF16A34A),
                  height: 1.15,
                  letterSpacing: -0.8,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Report issues, get updates, and access\ngovernment services in Aparri.',
          style: TextStyle(
            fontSize: subtitleSize,
            color: const Color(0xFF475569),
            height: 1.55,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// ── Profile card ─────────────────────────────────────────────────────────────
class _ProfileCard extends StatelessWidget {
  final String username;
  final String? fullName;
  final String? facePhotoUrl;
  final String? facePhotoPath;
  final VerifStatus verifStatus;
  final bool loading;
  final VoidCallback onVerifyTap;

  const _ProfileCard({
    required this.username,
    required this.fullName,
    required this.facePhotoUrl,
    this.facePhotoPath,
    required this.verifStatus,
    required this.loading,
    required this.onVerifyTap,
  });

  String _statusDescription(VerifStatus status) {
    switch (status) {
      case VerifStatus.verified:
        return 'You\'re a verified citizen with full access to all Aparri government services.';
      case VerifStatus.pending:
        return 'Your identity verification is under review. We\'ll notify you once approved.';
      case VerifStatus.none:
        return 'Verify your identity as an Aparri citizen to unlock full government services.';
    }
  }

  @override
  Widget build(BuildContext context) {
    // All decisions key off the CARD's own width, never the screen width — so
    // the card stays well-proportioned whether it's a 600px two-column column
    // or a 1200px full-width single-column band.
    return LayoutBuilder(
      builder: (context, constraints) {
        final double cardW = constraints.maxWidth;
        final isVerified = verifStatus == VerifStatus.verified;
        final isPending = verifStatus == VerifStatus.pending;
        final displayName = fullName ?? username;

        // Row layout (the screenshot look) holds down to ~460px card width.
        // Below that the badge + description + chip can't share a row without
        // overflow, so we fall back to stacked — which STILL shows the saying.
        final bool useWideRow = cardW >= 460;
        final bool isXs = cardW < 340; // extra-tight: shrink stacked paddings

        return Container(
          padding: EdgeInsets.symmetric(
            horizontal: isXs ? 14 : 18,
            vertical: isXs ? 12 : 16,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE8EEF8), width: 1),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF1A4DB8).withOpacity(0.10),
                blurRadius: 24,
                spreadRadius: -2,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: useWideRow
              ? _buildRowLayout(displayName, isVerified, isPending, cardW)
              : _buildStackedLayout(displayName, isVerified, isPending, isXs),
        );
      },
    );
  }

  // ── Wide row layout — fluid; holds the screenshot look from ~460px up ──────
  // Name block sits left, action pinned to the right edge, description as a
  // centered, capped-width block that fills the space between them.
  Widget _buildRowLayout(
    String displayName,
    bool isVerified,
    bool isPending,
    double cardW,
  ) {
    final bool tight = cardW < 620;
    final double avatarSize = tight ? 48 : 56;
    final double nameFs = tight ? 14.5 : 16;
    final double descFs = tight ? 11.5 : 12;
    final double gap = tight ? 10 : 14;
    final double descGap = tight ? 12 : 16;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _AvatarRing(
          url: facePhotoUrl,
          cacheKey: facePhotoPath,
          loading: loading,
          verifStatus: verifStatus,
          size: avatarSize,
        ),
        SizedBox(width: gap),

        // Name + username + badge — intrinsic width (does NOT expand), so the
        // badge keeps its natural size and the description fills the rest.
        Flexible(
          flex: 0,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: nameFs,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF0F172A),
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 3),
              _UsernameLocation(username: username, small: tight),
              const SizedBox(height: 7),
              _StatusBadge(verifStatus: verifStatus),
            ],
          ),
        ),

        SizedBox(width: descGap),

        // Description — fills the remaining space and PUSHES the action to the
        // far right edge, but stays a centered, readable block (capped width)
        // so it never smears across a very wide card.
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 250),
              child: Text(
                _statusDescription(verifStatus),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: descFs,
                  color: const Color(0xFF64748B),
                  height: 1.4,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ),
        ),
        SizedBox(width: gap),

        // Action — fixed width, sits flush against the right edge.
        if (isVerified)
          const _FullAccessChip()
        else if (isPending)
          const _PendingChip()
        else
          _VerifyNowButton(onTap: onVerifyTap),
      ],
    );
  }

  // ── Stacked layout — name row on top, description + action below ──────────
  // Used only on tiny cards (< 460px). Always shows the saying.
  Widget _buildStackedLayout(
    String displayName,
    bool isVerified,
    bool isPending,
    bool isXs,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Top row: avatar + name block
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _AvatarRing(
              url: facePhotoUrl,
              loading: loading,
              verifStatus: verifStatus,
              size: isXs ? 44 : 48,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: isXs ? 14 : 15,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF0F172A),
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 3),
                  _UsernameLocation(username: username, small: true),
                  const SizedBox(height: 6),
                  _StatusBadge(verifStatus: verifStatus),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Bottom row: description (always shown) + action
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                _statusDescription(verifStatus),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: isXs ? 11 : 11.5,
                  color: const Color(0xFF64748B),
                  height: 1.55,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
            const SizedBox(width: 12),
            if (isVerified)
              const _FullAccessChip()
            else if (isPending)
              const _PendingChip()
            else
              _VerifyNowButton(onTap: onVerifyTap),
          ],
        ),
      ],
    );
  }
}

// ── Username + location row ────────────────────────────────────────────────
class _UsernameLocation extends StatelessWidget {
  final String username;
  final bool small;
  const _UsernameLocation({required this.username, required this.small});

  @override
  Widget build(BuildContext context) {
    final double fs = small ? 11 : 12;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.alternate_email_rounded,
          size: small ? 10 : 11,
          color: const Color(0xFF9CA3AF),
        ),
        const SizedBox(width: 2),
        Flexible(
          child: Text(
            username,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: fs, color: const Color(0xFF6B7280)),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          width: 3,
          height: 3,
          decoration: const BoxDecoration(
            color: Color(0xFFD1D5DB),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Icon(
          Icons.location_on_rounded,
          size: small ? 10 : 11,
          color: const Color(0xFF9CA3AF),
        ),
        const SizedBox(width: 2),
        Flexible(
          child: Text(
            'Aparri, Cagayan',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: fs, color: const Color(0xFF6B7280)),
          ),
        ),
      ],
    );
  }
}

// ── Avatar ring ────────────────────────────────────────────────────────────
class _AvatarRing extends StatelessWidget {
  final String? url;
  final String? cacheKey;
  final bool loading;
  final VerifStatus verifStatus;
  final double size;

  const _AvatarRing({
    required this.url,
    this.cacheKey,
    required this.loading,
    required this.verifStatus,
    this.size = 56,
  });

  Color get _ringColor {
    switch (verifStatus) {
      case VerifStatus.verified:
        return const Color(0xFF22C55E);
      case VerifStatus.pending:
        return const Color(0xFFF59E0B);
      case VerifStatus.none:
        return const Color(0xFFD1D5DB);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(shape: BoxShape.circle, color: _ringColor),
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
        ),
        child: ClipOval(
          child: loading
              ? Container(
                  color: const Color(0xFFF3F4F6),
                  child: const Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF1A4DB8),
                    ),
                  ),
                )
              : (url != null && url!.isNotEmpty)
              ? CachedNetworkImage(
                  imageUrl: url!,
                  cacheKey: cacheKey ?? url!,
                  memCacheWidth: 120,
                  fit: BoxFit.cover,
                  fadeInDuration: const Duration(milliseconds: 300),
                  fadeOutDuration: const Duration(milliseconds: 100),
                  placeholder: (context, url) => _defaultAvatar(),
                  errorWidget: (context, url, error) => _defaultAvatar(),
                )
              : _defaultAvatar(),
        ),
      ),
    );
  }

  Widget _defaultAvatar() => Container(
    color: const Color(0xFFEFF6FF),
    child: Icon(Icons.person, size: size * 0.5, color: const Color(0xFF1A4DB8)),
  );
}

// ── Status badge ──────────────────────────────────────────────────────────
class _StatusBadge extends StatelessWidget {
  final VerifStatus verifStatus;
  const _StatusBadge({required this.verifStatus});

  @override
  Widget build(BuildContext context) {
    switch (verifStatus) {
      case VerifStatus.verified:
        return _badge(
          icon: Icons.verified_rounded,
          label: 'Verified Citizen',
          bg: const Color(0xFFDCFCE7),
          fg: const Color(0xFF16A34A),
          border: const Color(0xFFBBF7D0),
        );
      case VerifStatus.pending:
        return _badge(
          icon: Icons.access_time_rounded,
          label: 'Verification Pending',
          bg: const Color(0xFFFEF9C3),
          fg: const Color(0xFFA16207),
          border: const Color(0xFFFDE68A),
        );
      case VerifStatus.none:
        return _badge(
          icon: Icons.warning_amber_rounded,
          label: 'Not Yet Verified',
          bg: const Color(0xFFFFF7ED),
          fg: const Color(0xFFC2410C),
          border: const Color(0xFFFED7AA),
        );
    }
  }

  Widget _badge({
    required IconData icon,
    required String label,
    required Color bg,
    required Color fg,
    required Color border,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Action widgets ────────────────────────────────────────────────────────
const double _kActionWidth = 90;
const double _kActionHeight = 56;

class _FullAccessChip extends StatelessWidget {
  const _FullAccessChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _kActionWidth,
      // minHeight, not height: the chip stacks an icon over a label, and at
      // raised system text scales that column needs more than 56px. A fixed
      // height clips it and logs a RenderFlex overflow.
      constraints: const BoxConstraints(minHeight: _kActionHeight),
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFBBF7D0), width: 1),
      ),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.shield_rounded, size: 20, color: Color(0xFF22C55E)),
          SizedBox(height: 3),
          Text(
            'Full Access',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF16A34A),
            ),
          ),
        ],
      ),
    );
  }
}

class _PendingChip extends StatelessWidget {
  const _PendingChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _kActionWidth,
      // minHeight, not height: the chip stacks an icon over a label, and at
      // raised system text scales that column needs more than 56px. A fixed
      // height clips it and logs a RenderFlex overflow.
      constraints: const BoxConstraints(minHeight: _kActionHeight),
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFFEFCE8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFDE68A), width: 1),
      ),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.hourglass_top_rounded, size: 20, color: Color(0xFFF59E0B)),
          SizedBox(height: 3),
          Text(
            'Under Review',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFFA16207),
            ),
          ),
        ],
      ),
    );
  }
}

class _VerifyNowButton extends StatefulWidget {
  final VoidCallback onTap;
  const _VerifyNowButton({required this.onTap});

  @override
  State<_VerifyNowButton> createState() => _VerifyNowButtonState();
}

class _VerifyNowButtonState extends State<_VerifyNowButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          // See the chips above: minHeight so a scaled-up label grows the
          // button instead of overflowing it.
          constraints: const BoxConstraints(minHeight: _kActionHeight),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: _hovered
                  ? const [Color(0xFF15803D), Color(0xFF166534)]
                  : const [Color(0xFF22C55E), Color(0xFF16A34A)],
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: const Color(
                  0xFF16A34A,
                ).withOpacity(_hovered ? 0.40 : 0.25),
                blurRadius: _hovered ? 16 : 10,
                offset: Offset(0, _hovered ? 6 : 4),
              ),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Verify Now',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: 0.2,
                ),
              ),
              SizedBox(width: 6),
              Icon(Icons.arrow_forward_rounded, size: 15, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}
