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
                              // Name + inline verified seal. The seal used to
                              // live in a full-width strip below the card; it
                              // sits next to the name now so the quick actions
                              // rise into view without a scroll, and the
                              // sentence it replaced is one tap (or hover)
                              // away on the seal itself.
                              _NameWithSeal(
                                name: fullName ?? username,
                                width: width,
                                showSeal: isVerified,
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

// ── Name + seal ──────────────────────────────────────────────────────────────
/// A verified citizen's name with the seal tucked against its last letter.
///
/// ── Why this is measured rather than laid out ────────────────────────────
/// `Flexible` alone does not do it. A Text that ellipsizes still OCCUPIES its
/// full allotted width — the glyphs stop at the ellipsis but the box does not —
/// so the seal was pushed out to the truncation point and ended up floating at
/// the far right, visibly detached from the name it belongs to. "Chanzelyn
/// Sa… ✓" put the seal a third of the card away from the word it certifies.
///
/// So the name is measured first, and the row picks the longest form that fits
/// beside the seal:
///
///   1. the full name, when it fits;
///   2. the FIRST name alone, when the full one does not — a real name the
///      citizen recognises, rather than a machine-cut fragment;
///   3. an ellipsis, only if even the first name overflows.
///
/// Step 2 is the point: an ellipsis is a failure state, and one is avoidable
/// here because a person's first name is a legitimate way to address them.
class _NameWithSeal extends StatelessWidget {
  final String name;
  final double width;
  final bool showSeal;

  const _NameWithSeal({
    required this.name,
    required this.width,
    required this.showSeal,
  });

  /// The leading word of [name], or the whole string when there is only one.
  static String firstNameOf(String name) {
    final trimmed = name.trim();
    final cut = trimmed.indexOf(' ');
    return cut == -1 ? trimmed : trimmed.substring(0, cut);
  }

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: width * 0.052,
      fontWeight: FontWeight.w700,
      color: const Color(0xFF1F2937),
    );

    if (!showSeal) {
      return Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }

    // The space between the last letter and the seal.
    //
    // Deliberately tight. A verified mark reads as part of the NAME, the way
    // Facebook and X set theirs — it is not a separate item in a row, and any
    // daylight between the two makes it look like one. Clamped so the value
    // stays in that hairline range across the phone widths rather than growing
    // proportionally into a visible gap on a large screen.
    final gap = (width * 0.008).clamp(2.0, 4.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        // What the seal actually costs the NAME.
        //
        // Not the full 44dp target. That box is left-aligned around a ~19dp
        // glyph (see [_VerifiedNameBadge]), so its trailing ~25dp is empty
        // space the name never competes with — it simply overhangs the card's
        // own trailing padding. Charging the name for all 44 made a name that
        // plainly fits, the 'Mark Reduca' the tests pin, measure as too long
        // and get cut to 'Mark'.
        //
        // Measured against the same scale factor the Text will be painted
        // with, so a user at Android's Largest font size gets the decision the
        // layout will actually produce, not one taken at 1.0x.
        final sealCost = (width * 0.048).clamp(15.0, 23.0) + gap;
        final available = constraints.maxWidth - sealCost;
        final scaler = MediaQuery.textScalerOf(context);

        double widthOf(String text) {
          final painter = TextPainter(
            text: TextSpan(text: text, style: style),
            maxLines: 1,
            textDirection: Directionality.of(context),
            textScaler: scaler,
          )..layout();
          return painter.width;
        }

        var shown = name;
        if (available > 0 && widthOf(shown) > available) {
          final first = firstNameOf(name);
          // Only worth swapping if the first name is genuinely shorter — a
          // single-word name would otherwise be "shortened" to itself and the
          // ellipsis below still handles it.
          if (first.length < name.trim().length) shown = first;
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Flexible so an over-long FIRST name still ellipsizes rather than
            // overflowing — the last resort in the ladder above.
            Flexible(
              child: Text(
                shown,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
            SizedBox(width: gap),
            _VerifiedNameBadge(width: width),

          ],
        );
      },
    );
  }
}

/// The minimum comfortable touch target, in logical pixels.
///
/// 44dp is the floor Apple's HIG and Material's accessibility guidance both
/// land on. Named rather than inlined so the intent survives the next edit to
/// the seal's size.
const double _kMinTouchTarget = 44.0;

// ── Verified Name Badge ───────────────────────────────────────────────────────
/// The seal that follows a verified citizen's name, and the only place the
/// "You're a verified Aparri citizen" sentence still lives — revealed on hover
/// (web/desktop) or a tap (mobile) rather than occupying a permanent strip.
///
/// [Tooltip] carries both gestures in one widget: it opens on hover by default
/// and [TooltipTriggerMode.tap] adds the touch path, so there is no separate
/// mobile branch to keep in sync. [showDuration] is generous because on touch
/// the tooltip is the only way to read the sentence — the default 1.5s is tuned
/// for a hover the user can simply repeat.
class _VerifiedNameBadge extends StatelessWidget {
  final double width;
  const _VerifiedNameBadge({required this.width});

  @override
  Widget build(BuildContext context) {
    final w = width;
    // Clamped rather than purely proportional, for the same reason the strip's
    // seal was: the floor keeps the knocked-out check legible on a 320dp phone,
    // and the ceiling stops it out-growing the name it sits beside at 480.
    final iconSize = (w * 0.048).clamp(15.0, 23.0);

    return Tooltip(
      message: "You're a verified Aparri citizen",
      triggerMode: TooltipTriggerMode.tap,
      preferBelow: false,
      showDuration: const Duration(seconds: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF15803D),
        borderRadius: BorderRadius.circular(w * 0.02),
      ),
      textStyle: TextStyle(
        fontSize: w * 0.030,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
      padding: EdgeInsets.symmetric(
        horizontal: w * 0.028,
        vertical: w * 0.018,
      ),
      // The seal itself is smaller than a comfortable touch target, so the
      // tooltip's gesture area is padded out to one. The padding is inside the
      // Tooltip and outside the Icon, so it grows what you can tap without
      // moving the glyph off the name's baseline.
      //
      // ── The tap target, without pushing the seal off the name ──────────
      // 44dp is the floor Apple's HIG and Material both publish, and it
      // matters more here than usual: removing the strip made this seal the
      // ONLY route to the verification sentence, so a target the thumb misses
      // is a sentence nobody can reach.
      //
      // A centred 44dp box around a ~19dp glyph, though, leaves ~12dp of dead
      // space on EACH side — which visibly detached the seal from the name it
      // certifies. It read as an unrelated icon floating after the text.
      //
      // So the box is asymmetric: the full 44dp of height (free — the name's
      // line box is already tall), and a width that reaches the minimum by
      // extending RIGHT, into the card's own trailing space, rather than
      // padding both sides. The glyph therefore starts immediately after the
      // gap — tight against the name — while the thumb still gets its 44dp.
      child: SizedBox(
        width: _kMinTouchTarget,
        height: _kMinTouchTarget,
        child: Align(
          // Left, not centre: this is what keeps the glyph beside the name.
          alignment: Alignment.centerLeft,
          child: Icon(
            Icons.verified_rounded,
            size: iconSize,
            color: const Color(0xFF16A34A),
          ),
        ),
      ),
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
