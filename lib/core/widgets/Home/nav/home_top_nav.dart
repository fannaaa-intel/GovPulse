import 'package:flutter/material.dart';
import 'dart:async';
import '../../../../core/theme/citizen_ui.dart';

/// One destination in the top nav: the label, and the index handed back to
/// `onTap`. Public so a caller with a different set of destinations can supply
/// its own — see [HomeTopNav.items].
typedef HomeTopNavItem = ({String label, int index});

class HomeTopNav extends StatefulWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final VoidCallback onNotificationTap;
  final VoidCallback onLogoutTap;
  final int notificationCount;
  final String? username;
  final String? fullName;
  final String? facePhotoUrl;
  final String verifStatus;

  /// Destinations to show. Null keeps [defaultItems] — the four the standalone
  /// pages have always shown — so the mobile app and the live web routes are
  /// unaffected by callers that pass their own.
  ///
  /// The citizen web shell supplies a shorter set: it merged NewsFeed into Home,
  /// so its nav is Home · My Reports · Emergency.
  final List<HomeTopNavItem>? items;

  /// Index reported when the user chip's "Settings" is chosen. Defaults to 4,
  /// the position Settings occupies in the standalone 0–4 destination contract.
  /// The shell overrides it because dropping NewsFeed shifts Settings down.
  final int settingsIndex;

  /// Collapses the user chip to its avatar — no name, no chevron, tighter
  /// padding. The chip's DROPDOWN still shows the full name; only the closed
  /// button shrinks.
  ///
  /// Opt-in and defaults to false, which is the layout every existing caller
  /// gets. That matters: this widget is not web-only. `resolveNavBand` returns
  /// `topNav` for any device at least 900 wide whose shortest side is at least
  /// 600, so the MOBILE app builds this on tablets — an iPad in landscape
  /// (1024x768) lands here. Neither mobile call site passes this flag, so their
  /// rendering is byte-identical to before.
  ///
  /// Only the citizen web shell sets it, below ~600px, where brand + bell +
  /// named chip cannot fit alongside its hamburger.
  final bool avatarOnlyChip;

  const HomeTopNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.onNotificationTap,
    required this.onLogoutTap,
    required this.notificationCount,
    required this.verifStatus,
    this.username,
    this.fullName,
    this.facePhotoUrl,
    this.items,
    this.settingsIndex = 4,
    this.avatarOnlyChip = false,
  });

  /// The standalone destination set. Unchanged.
  static const defaultItems = <HomeTopNavItem>[
    (label: 'Home', index: 0),
    (label: 'My Reports', index: 1),
    (label: 'NewsFeed', index: 2),
    (label: 'Emergency', index: 3),
  ];

  @override
  State<HomeTopNav> createState() => _HomeTopNavState();
}

class _HomeTopNavState extends State<HomeTopNav> {
  int? _hoveredIndex;
  VoidCallback? _closeUserChip;

  void _registerCloseUserChip(VoidCallback cb) {
    _closeUserChip = cb;
  }

  void _onNavZoneEntered() {
    _closeUserChip?.call();
  }

  bool _isHighlighted(int index) => _hoveredIndex == null
      ? widget.currentIndex == index
      : _hoveredIndex == index;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(
          bottom: BorderSide(color: CitizenUi.sharedBorder, width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const _BrandLogo(),
          Expanded(
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final item in (widget.items ?? HomeTopNav.defaultItems))
                    _NavLink(
                      label: item.label,
                      isActive: _isHighlighted(item.index),
                      onEnter: () {
                        setState(() => _hoveredIndex = item.index);
                        _onNavZoneEntered();
                      },
                      onExit: () => setState(() {
                        if (_hoveredIndex == item.index) _hoveredIndex = null;
                      }),
                      onTap: () => widget.onTap(item.index),
                    ),
                ],
              ),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _NotifBell(
                count: widget.notificationCount,
                onTap: widget.onNotificationTap,
                onEnter: _onNavZoneEntered,
              ),
              const SizedBox(width: 10),
              _UserChip(
                username: widget.username,
                fullName: widget.fullName,
                facePhotoUrl: widget.facePhotoUrl,
                verifStatus: widget.verifStatus,
                onSettingsTap: () => widget.onTap(widget.settingsIndex),
                onLogoutTap: widget.onLogoutTap,
                onRegisterClose: _registerCloseUserChip,
                avatarOnly: widget.avatarOnlyChip,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Brand logo ────────────────────────────────────────────────────────────────
class _BrandLogo extends StatelessWidget {
  const _BrandLogo();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          'assets/images/applogocrop.webp',
          width: 28,
          height: 28,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: const Color(0xFF1A4DB8),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(
              Icons.account_balance,
              size: 16,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 8),
        const Text(
          'GovPulse',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: Color(0xFF1A4DB8),
            letterSpacing: -0.3,
          ),
        ),
      ],
    );
  }
}

// ── Nav link ──────────────────────────────────────────────────────────────────
class _NavLink extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onEnter;
  final VoidCallback onExit;
  final VoidCallback onTap;

  const _NavLink({
    required this.label,
    required this.isActive,
    required this.onEnter,
    required this.onExit,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => onEnter(),
      onExit: (_) => onExit(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeInOut,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: isActive
                      ? const Color(0xFF1A4DB8)
                      : const Color(0xFF374151),
                ),
                child: Text(label),
              ),
              const SizedBox(height: 3),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeInOut,
                height: 2.5,
                width: isActive ? 20.0 : 0.0,
                decoration: BoxDecoration(
                  color: const Color(0xFF1A4DB8),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Notification bell ─────────────────────────────────────────────────────────
class _NotifBell extends StatefulWidget {
  final int count;
  final VoidCallback onTap;
  final VoidCallback onEnter;
  const _NotifBell({
    required this.count,
    required this.onTap,
    required this.onEnter,
  });

  @override
  State<_NotifBell> createState() => _NotifBellState();
}

class _NotifBellState extends State<_NotifBell> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        setState(() => _hover = true);
        widget.onEnter();
      },
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: _hover ? const Color(0xFFEFF6FF) : const Color(0xFFF3F4F6),
            shape: BoxShape.circle,
            border: Border.all(
              color: _hover
                  ? const Color(0xFF1A4DB8).withOpacity(0.20)
                  : Colors.transparent,
              width: 1,
            ),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Icon(
                Icons.notifications_rounded,
                size: 24,
                color: _hover
                    ? const Color(0xFF1A4DB8)
                    : const Color(0xFF4B5563),
              ),
              if (widget.count > 0)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      widget.count > 9 ? '9+' : '${widget.count}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        height: 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── User chip ─────────────────────────────────────────────────────────────────
class _UserChip extends StatefulWidget {
  final String? username;
  final String? fullName;
  final String? facePhotoUrl;
  final String verifStatus;
  final VoidCallback onSettingsTap;
  final VoidCallback onLogoutTap;
  final void Function(VoidCallback closeCallback) onRegisterClose;

  /// Render the closed button as just the avatar. The dropdown is unaffected —
  /// it still shows the full name. See [HomeTopNav.avatarOnlyChip].
  final bool avatarOnly;

  const _UserChip({
    this.username,
    this.fullName,
    this.facePhotoUrl,
    required this.verifStatus,
    required this.onSettingsTap,
    required this.onLogoutTap,
    required this.onRegisterClose,
    this.avatarOnly = false,
  });

  @override
  State<_UserChip> createState() => _UserChipState();
}

class _UserChipState extends State<_UserChip>
    with SingleTickerProviderStateMixin {
  bool _isOpen = false;
  bool _closing = false;
  OverlayEntry? _overlay;
  Timer? _closeTimer;

  // Tracks how many "zones" the mouse is inside (chip + bridge + panel = up to 3).
  // When it drops to 0, we schedule a close.
  int _hoverZones = 0;

  final LayerLink _layerLink = LayerLink();

  late final AnimationController _animCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _fadeAnim = CurvedAnimation(
      parent: _animCtrl,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );
    _scaleAnim = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(
        parent: _animCtrl,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      ),
    );

    widget.onRegisterClose(_forceClose);
  }

  @override
  void dispose() {
    _closeTimer?.cancel();
    _animCtrl.dispose();
    _removeOverlay();
    super.dispose();
  }

  void _removeOverlay() {
    _overlay?.remove();
    _overlay = null;
  }

  void _open() {
    if (_isOpen || _closing) return;
    _overlay = OverlayEntry(builder: (_) => _buildOverlayContent());
    Overlay.of(context).insert(_overlay!);
    _animCtrl.forward(from: 0);
    if (mounted) setState(() => _isOpen = true);
  }

  void _close({VoidCallback? then}) {
    if (!_isOpen || _closing) {
      then?.call();
      return;
    }
    _closing = true;
    _animCtrl.reverse().whenCompleteOrCancel(() {
      if (mounted) {
        _removeOverlay();
        setState(() {
          _isOpen = false;
          _closing = false;
        });
      } else {
        _removeOverlay();
      }
      then?.call();
    });
  }

  /// Called by nav links / bell entering — closes regardless of how it was opened.
  void _forceClose() {
    if (!_isOpen) return;
    _closeTimer?.cancel();
    _hoverZones = 0;
    _close();
  }

  /// Mouse entered one of our zones (chip, bridge, panel).
  void _zoneEnter() {
    _closeTimer?.cancel();
    _hoverZones++;
    if (!_isOpen && !_closing) _open();
  }

  /// Mouse left one of our zones.
  void _zoneExit() {
    _hoverZones = (_hoverZones - 1).clamp(0, 99);
    if (_hoverZones > 0) return; // still inside another zone
    _closeTimer?.cancel();
    _closeTimer = Timer(const Duration(milliseconds: 120), () {
      if (mounted) _close();
    });
  }

  void _onTap() {
    if (_isOpen) {
      _closeTimer?.cancel();
      _hoverZones = 0;
      _close();
    } else {
      _open();
    }
  }

  Widget _buildOverlayContent() {
    const dropdownWidth = 220.0;
    const bridgeHeight = 8.0;
    final isVerified = widget.verifStatus == 'approved';

    return AnimatedBuilder(
      animation: _animCtrl,
      builder: (context, _) {
        return Positioned(
          width: dropdownWidth,
          child: CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            targetAnchor: Alignment.bottomRight,
            followerAnchor: Alignment.topRight,
            offset: const Offset(0, -bridgeHeight),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Invisible bridge
                MouseRegion(
                  onEnter: (_) => _zoneEnter(),
                  onExit: (_) => _zoneExit(),
                  child: Container(
                    width: dropdownWidth,
                    height: bridgeHeight,
                    color: Colors.transparent,
                  ),
                ),
                FadeTransition(
                  opacity: _fadeAnim,
                  child: ScaleTransition(
                    scale: _scaleAnim,
                    alignment: Alignment.topRight,
                    child: MouseRegion(
                      onEnter: (_) => _zoneEnter(),
                      onExit: (_) => _zoneExit(),
                      child: Material(
                        color: Colors.transparent,
                        child: Container(
                          width: dropdownWidth,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: CitizenUi.sharedBorder),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.12),
                                blurRadius: 24,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _DropdownHeader(
                                fullName: widget.fullName,
                                username: widget.username,
                                facePhotoUrl: widget.facePhotoUrl,
                              ),
                              const Divider(
                                height: 1,
                                color: CitizenUi.sharedBorder,
                              ),
                              if (isVerified) ...[
                                _DropdownItem(
                                  icon: Icons.settings_rounded,
                                  iconColor: const Color(0xFF1A4DB8),
                                  iconBg: const Color(0xFFEFF6FF),
                                  iconBorder: const Color(0xFFBFDBFE),
                                  label: 'Settings',
                                  onTap: () =>
                                      _close(then: widget.onSettingsTap),
                                ),
                                const Divider(
                                  height: 1,
                                  color: CitizenUi.sharedBorder,
                                ),
                              ],
                              _DropdownItem(
                                icon: Icons.logout_rounded,
                                iconColor: const Color(0xFFEF4444),
                                iconBg: const Color(0xFFFEF2F2),
                                iconBorder: const Color(0xFFFECACA),
                                label: 'Sign Out',
                                danger: true,
                                isLast: true,
                                onTap: () => _close(then: widget.onLogoutTap),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final displayName = widget.fullName ?? widget.username ?? 'User';

    return CompositedTransformTarget(
      link: _layerLink,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => _zoneEnter(),
        onExit: (_) => _zoneExit(),
        child: GestureDetector(
          onTap: _onTap,
          child: Container(
            padding: widget.avatarOnly
                ? const EdgeInsets.all(4)
                : const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _isOpen
                  ? const Color(0xFFEFF6FF)
                  : const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: _isOpen
                    ? const Color(0xFF1A4DB8).withOpacity(0.20)
                    : const Color(0xFFE5E7EB),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipOval(
                  child: SizedBox(
                    width: 30,
                    height: 30,
                    child:
                        (widget.facePhotoUrl != null &&
                            widget.facePhotoUrl!.isNotEmpty)
                        ? Image.network(
                            widget.facePhotoUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => _defaultAvatar(),
                          )
                        : _defaultAvatar(),
                  ),
                ),
                if (!widget.avatarOnly) ...[
                  const SizedBox(width: 8),
                  Text(
                    displayName,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1F2937),
                    ),
                  ),
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: _isOpen ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    child: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 16,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _defaultAvatar() => Container(
    color: const Color(0xFF1A4DB8),
    child: const Icon(Icons.person, size: 18, color: Colors.white),
  );
}

// ── Dropdown header ───────────────────────────────────────────────────────────
class _DropdownHeader extends StatelessWidget {
  final String? fullName;
  final String? username;
  final String? facePhotoUrl;

  const _DropdownHeader({this.fullName, this.username, this.facePhotoUrl});

  @override
  Widget build(BuildContext context) {
    final displayName = fullName ?? username ?? 'User';
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Row(
        children: [
          ClipOval(
            child: SizedBox(
              width: 40,
              height: 40,
              child: (facePhotoUrl != null && facePhotoUrl!.isNotEmpty)
                  ? Image.network(
                      facePhotoUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _avatar(),
                    )
                  : _avatar(),
            ),
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
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
                if (username != null)
                  Text(
                    '@$username',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6B7280),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatar() => Container(
    color: const Color(0xFF1A4DB8),
    child: const Icon(Icons.person, size: 22, color: Colors.white),
  );
}

// ── Dropdown item ─────────────────────────────────────────────────────────────
class _DropdownItem extends StatefulWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final Color iconBorder;
  final String label;
  final bool danger;
  final bool isLast;
  final VoidCallback onTap;

  const _DropdownItem({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.iconBorder,
    required this.label,
    required this.onTap,
    this.danger = false,
    this.isLast = false,
  });

  @override
  State<_DropdownItem> createState() => _DropdownItemState();
}

class _DropdownItemState extends State<_DropdownItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          decoration: BoxDecoration(
            color: _hover ? widget.iconBg : Colors.transparent,
            borderRadius: widget.isLast
                ? const BorderRadius.only(
                    bottomLeft: Radius.circular(14),
                    bottomRight: Radius.circular(14),
                  )
                : BorderRadius.zero,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: widget.iconBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _hover ? widget.iconColor : widget.iconBorder,
                    width: _hover ? 1.5 : 1.0,
                  ),
                ),
                child: Icon(widget.icon, size: 17, color: widget.iconColor),
              ),
              const SizedBox(width: 12),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: _hover
                      ? widget.iconColor
                      : widget.danger
                      ? const Color(0xFFEF4444)
                      : const Color(0xFF111827),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
