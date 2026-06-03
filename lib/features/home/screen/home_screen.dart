import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../auth/services/chat_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import '../../../features/home/screen/notification_popup.dart';
import '../../../core/network/network_wrapper.dart';
import '../../../core/utils/overlay_exit.dart';
import '../../../core/widgets/modal/verification_required_dialog.dart';
import '../Quick-action/Report/report_issue_screen.dart';
import '../Quick-action/Chat-with-Agent/chat_agent_screen.dart';
import '../Quick-action/Suggestion/suggestion_screen.dart';

import '../../../core/widgets/Home/nav/home_bottom_nav.dart';
import '../../../core/widgets/Home/nav/home_top_nav.dart';
import '../../../core/widgets/Home/nav/home_nav_drawer.dart';

import '../../../core/widgets/Home/sections/home_profile_card.dart';
import '../../../core/widgets/Home/sections/home_community_section.dart';
import '../../../core/widgets/Home/sections/home_quick_actions_section.dart';

import '../../../core/widgets/Home/sections/Web/home_community_section_web.dart';
import '../../../core/widgets/Home/sections/Web/home_hero_section.dart';
import '../../../core/widgets/Home/sections/Web/home_quick_actions_section_web.dart';
import '../../../core/widgets/Home/sections/Web/home_stats_bar.dart';
import '../../../core/widgets/Home/sections/Web/home_footer.dart';

import '../../../core/widgets/Home/home_enums.dart';
import '../../../core/widgets/Home/Chat-bubbles/home_chat_bubble.dart';
import '../../../core/widgets/loading/loading_overlay.dart';
import '../Quick-action/Events/events_screen.dart';

class HomePage extends StatefulWidget {
  final String username;
  const HomePage({super.key, required this.username});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with TickerProviderStateMixin
    implements RouteAware {
  final FlutterLocalNotificationsPlugin notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  DateTime? lastBackPressed;

  VerifStatus _verifStatus = VerifStatus.none;
  String? _facePhotoUrl;
  String? _facePhotoPath;
  String? _fullName;
  bool _profileLoading = true;

  late final AnimationController _entryCtrl;
  static const int _navIndex = 0;

  // ── Responsive bands ──────────────────────────────────────────────────────
  //   width <  _kMobileBreakpoint  → MOBILE body  + bottom nav   (phones)
  //   600–900                      → WEB body      + drawer       (tablet-web)
  //   width >= _kTopNavBreakpoint   → WEB body      + top nav      (desktop)
  static const double _kMobileBreakpoint = 600;
  static const double _kTopNavBreakpoint = 900;
  // Mobile sections scale every dimension off the width they receive. Capping
  // that width keeps phone proportions stable across the whole < 600 band:
  // true phones (≤ this) are unchanged; 480–600 windows get a centered,
  // phone-width column instead of ballooned fonts/avatars.
  static const double _kMobileContentMax = 480;

  static const double _kTwoColumnBreakpoint = 1100;
  static const double _kNavCompactBelow = 1050;
  static const double _kDashboardMaxWidth = 1280;
  static const double _kSidePadDesktop = 32;
  static const double _kSidePadNarrowWeb = 20;
  static const double _kColGap = 28;

  @override
  void initState() {
    super.initState();
    _initNotifications();
    _loadVerificationStatus();

    NotificationService.load().then((_) {
      if (mounted) setState(() {});
    });

    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {});

    Future.delayed(const Duration(minutes: 3), () {
      if (mounted && _verifStatus == VerifStatus.none) {
        _triggerVerificationReminder();
      }
    });
  }

  @override
  void dispose() {
    homeRouteObserver.unsubscribe(this);
    _entryCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    homeRouteObserver.subscribe(this, ModalRoute.of(context)!);
  }

  @override
  void didPopNext() {
    _loadVerificationStatus();
    Future.delayed(const Duration(milliseconds: 320), () {
      if (mounted) _entryCtrl.forward(from: 0);
    });
  }

  @override
  void didPush() {}
  @override
  void didPushNext() {}
  @override
  void didPop() {}

  Animation<double> _fade(int i) => Tween<double>(begin: 0, end: 1).animate(
    CurvedAnimation(
      parent: _entryCtrl,
      curve: Interval(
        (i * 0.18).clamp(0.0, 1.0),
        ((i * 0.18) + 0.5).clamp(0.0, 1.0),
        curve: Curves.easeOut,
      ),
    ),
  );

  Animation<Offset> _slideAnim(int i) =>
      Tween<Offset>(begin: const Offset(0, 0.28), end: Offset.zero).animate(
        CurvedAnimation(
          parent: _entryCtrl,
          curve: Interval(
            (i * 0.18).clamp(0.0, 1.0),
            ((i * 0.18) + 0.5).clamp(0.0, 1.0),
            curve: Curves.easeOutCubic,
          ),
        ),
      );

  Widget _animated(int i, Widget child) => FadeTransition(
    opacity: _fade(i),
    child: SlideTransition(position: _slideAnim(i), child: child),
  );

  Route<T> _quickActionRoute<T>(Widget page) {
    return PageRouteBuilder<T>(
      // Entry is instant — the screen's own content does the slide-up.
      transitionDuration: Duration.zero,
      // Back animates: fade out, no slide.
      reverseTransitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (_, _, _) => page,
      transitionsBuilder: (_, anim, _, child) =>
          FadeTransition(opacity: anim, child: child),
    );
  }

  void _goToNewsFeed() {
    Navigator.pushNamed(
      context,
      '/newsfeed',
      arguments: {
        'username': widget.username,
        'isVerified': _verifStatus == VerifStatus.verified,
      },
    );
  }

  void _goToReport() {
    if (_verifStatus != VerifStatus.verified) {
      showVerificationRequiredDialog(
        context,
        message:
            'Only verified Aparri citizens can submit a report. '
            'Please complete your identity verification first.',
      );
      return;
    }
    Navigator.push(
      context,
      _quickActionRoute(
        NetworkWrapper(child: ReportIssueScreen(username: widget.username)),
      ),
    );
  }

  void _goToSuggestion() {
    if (_verifStatus != VerifStatus.verified) {
      showVerificationRequiredDialog(
        context,
        message:
            'Only verified Aparri citizens can submit a suggestion. '
            'Please complete your identity verification first.',
      );
      return;
    }
    Navigator.push(
      context,
      _quickActionRoute(
        NetworkWrapper(child: SuggestionScreen(username: widget.username)),
      ),
    );
  }

  void _goToEvents() {
    Navigator.push(
      context,
      _quickActionRoute(
        NetworkWrapper(
          child: EventsScreen(
            username: widget.username,
            isVerified: _verifStatus == VerifStatus.verified,
          ),
        ),
      ),
    );
  }

  void _goToChat() {
    if (_verifStatus != VerifStatus.verified) {
      showVerificationRequiredDialog(
        context,
        message:
            'Only verified Aparri citizens can chat with an agent. '
            'Please complete your identity verification first.',
      );
      return;
    }

    final bubbleWasVisible = chatBubbleVisible.value;
    if (bubbleWasVisible) HomeChatBubble.hideGlobal();

    Navigator.push(
      context,
      _quickActionRoute(
        NetworkWrapper(child: ChatAgentScreen(username: widget.username)),
      ),
    ).then((_) {
      if (!mounted) return;
      HomeChatBubble.showGlobal();
    });
  }

  void _goToVerification() {
    if (_verifStatus == VerifStatus.pending) return;
    Navigator.pushNamed(context, '/verification', arguments: widget.username);
  }

  void _handleQuickAction(String key) {
    switch (key) {
      case 'chat':
        _goToChat();
        break;
      case 'report':
        _goToReport();
        break;
      case 'events':
        _goToEvents();
        break;
      case 'suggestion':
        _goToSuggestion();
        break;
    }
  }

  void _handleNavTap(int index) {
    if (index == _navIndex) return;
    if (index == 1) {
      if (_verifStatus != VerifStatus.verified) {
        showVerificationRequiredDialog(
          context,
          message: 'Only verified citizens can access My Reports.',
        );
        return;
      }
      Navigator.pushNamed(context, '/my_reports', arguments: widget.username);
    } else if (index == 2) {
      _goToNewsFeed();
    } else if (index == 3) {
      Navigator.pushNamed(
        context,
        '/emergency',
        arguments: {
          'username': widget.username,
          'isVerified': _verifStatus == VerifStatus.verified,
        },
      );
    } else if (index == 4) {
      Navigator.pushNamed(context, '/settings', arguments: widget.username);
    }
  }

  void _showNotificationsDialog(double width) async {
    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Notifications',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (_, _, _) => NotificationPopup(width: width),
      transitionBuilder: (_, anim, _, child) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(
          scale: CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
          child: child,
        ),
      ),
    );
    setState(() {});
  }

  Future<void> _handleLogout() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withOpacity(0.10),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.logout_rounded,
                  size: 28,
                  color: Color(0xFFEF4444),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Log Out?',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1F2937),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'You\'ll need to sign in again to access your account.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF6B7280),
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFE5E7EB)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF374151),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEF4444),
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        'Log Out',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (shouldLogout != true || !mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: Color(0xFF1A4DB8)),
      ),
    );

    try {
      await Supabase.instance.client.auth.signOut();
      await ChatService.I.clearOnLogout(); // ← same as setting_screen
      HomeChatBubble.hideGlobal();
      if (!mounted) return;
      Navigator.pop(context);
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Logout failed: $e'),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _loadVerificationStatus() async {
    try {
      final supabase = Supabase.instance.client;
      final uid = supabase.auth.currentUser?.id;
      if (uid == null) {
        if (mounted) setState(() => _profileLoading = false);
        return;
      }

      final verifRow = await supabase
          .from('verification_submissions')
          .select('status, face_photo_path')
          .eq('user_id', uid)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      VerifStatus verifStatus = VerifStatus.none;
      String? facePath;

      if (verifRow != null) {
        final status = verifRow['status'] as String?;
        facePath = verifRow['face_photo_path'] as String?;
        if (status == 'approved') verifStatus = VerifStatus.verified;
        if (status == 'pending') verifStatus = VerifStatus.pending;
      }

      if (verifStatus == VerifStatus.verified) {
        String? fullName;
        String? faceUrl;
        try {
          final res = await supabase
              .from('citizen_details')
              .select('first_name, last_name, profile_photo_path')
              .eq('user_id', uid)
              .maybeSingle();

          if (res != null) {
            final first = res['first_name'] as String? ?? '';
            final last = res['last_name'] as String? ?? '';
            fullName = '${first.trim()} ${last.trim()}'.trim();
            if (fullName.trim().isEmpty) fullName = null;
            final photo = res['profile_photo_path'] as String? ?? '';
            if (photo.isNotEmpty) facePath = photo;
          }
        } catch (_) {}
        if (facePath != null && facePath.isNotEmpty) {
          faceUrl = await supabase.storage
              .from('verification-assets')
              .createSignedUrl(facePath, 3600);
        }

        if (mounted) {
          setState(() {
            _verifStatus = verifStatus;
            _facePhotoUrl = faceUrl;
            _facePhotoPath = facePath;
            _fullName = fullName;
            _profileLoading = false;
          });
          _entryCtrl.forward(from: 0);
        }
      } else {
        // pending or none
        String? fullName;
        try {
          final res = await supabase
              .from('profiles')
              .select('username, email')
              .eq('id', uid)
              .maybeSingle();
          if (res != null) fullName = res['username'] as String?;
        } catch (_) {}

        if (mounted) {
          setState(() {
            _verifStatus = verifStatus;
            _facePhotoUrl = null;
            _facePhotoPath = null;
            _fullName = fullName;
            _profileLoading = false;
          });
          _entryCtrl.forward(from: 0);
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => _profileLoading = false);
        _entryCtrl.forward(from: 0);
      }
    }
  }

  void _initNotifications() async {
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await notificationsPlugin.initialize(settings);
  }

  void _triggerVerificationReminder() async {
    final added = await NotificationService.add(
      AppNotification(
        icon: Icons.verified_user,
        title: 'Verification Required',
        subtitle: 'Complete your identity verification now',
        time: DateTime.now(),
        color: Colors.orange,
        type: 'verification_reminder',
      ),
    );
    if (added && mounted) {
      setState(() {});
      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          'verification_channel',
          'Verification Reminder',
          importance: Importance.max,
          priority: Priority.high,
        ),
      );
      await notificationsPlugin.show(
        0,
        'Complete Verification',
        'Tap to verify your account now',
        details,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final width = size.width;
    final height = size.height;

    // Bottom-nav mobile body is for the native app only. On web we always use
    // the web body: top nav when wide, hamburger drawer when narrow — never
    // the bottom nav, no matter how small the browser window gets.
    final bool useMobile = !kIsWeb && width < _kMobileBreakpoint;
    final bool useTopNav = width >= _kTopNavBreakpoint;
    final bool useDrawer = !useMobile && !useTopNav;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (handleChatBubbleBack()) return;
        final now = DateTime.now();
        if (lastBackPressed == null ||
            now.difference(lastBackPressed!) > const Duration(seconds: 2)) {
          lastBackPressed = now;
          ExitOverlay.show(context, 'Press again to exit');
        } else {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        extendBody: true,
        backgroundColor: useMobile ? Colors.white : const Color(0xFFF3F6FC),

        // Drawer app bar ONLY in the 600–900 band.
        appBar: useDrawer ? _buildDrawerAppBar(width) : null,
        drawer: useDrawer
            ? HomeNavDrawer(
                currentIndex: _navIndex,
                onTap: _handleNavTap,
                username: widget.username,
                fullName: _fullName,
                facePhotoUrl: _facePhotoUrl,
                verifStatus: _verifStatus,
                onLogout: _handleLogout,
              )
            : null,

        body: LoadingOverlay.bodyOrSkeleton(
          isLoading: _profileLoading,
          layout: SkeletonLayout.home,
          child: useMobile
              ? SafeArea(child: _buildMobileBody(width, height))
              : _buildWebBody(width, height, showTopNav: useTopNav),
        ),

        // Bottom nav ONLY on mobile.
        bottomNavigationBar: useMobile
            ? HomeBottomNav(
                width: width,
                currentIndex: _navIndex,
                onTap: _handleNavTap,
              )
            : null,
      ),
    );
  }

  // ── Mobile body — responsive: header + spacing clamp so it stays in
  // proportion from small phones up to the 600px band edge. The inner
  // section widgets (profile card, community, quick actions) scale themselves
  // off the `width` they receive. ───────────────────────────────────────────
  Widget _buildMobileBody(double width, double height) {
    // Header tracks width but is clamped so it's neither a thin strip on a
    // 320px phone nor a giant banner approaching 600px.
    final double headerHeight = (width * 0.52).clamp(200.0, 300.0);
    // How far the profile card is pulled up over the header.
    final double cardPull = (width * 0.05).clamp(14.0, 28.0);
    // Vertical rhythm between the stacked sections.
    final double sectionGap = (width * 0.05).clamp(16.0, 28.0);
    // Width handed to the section widgets: real width on phones, capped on
    // wider windows so their proportional sizing stays phone-like.
    final double contentW = math.min(width, _kMobileContentMax);

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        children: [
          // Header stays full-bleed across the band.
          _buildMobileHeader(width, headerHeight),
          // Content column caps + centers; phones (≤480) are unaffected.
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _kMobileContentMax),
              child: Column(
                children: [
                  _animated(
                    0,
                    Transform.translate(
                      offset: Offset(0, -cardPull),
                      child: HomeProfileCard(
                        width: contentW,
                        username: widget.username,
                        verifStatus: _verifStatus,
                        fullName: _fullName,
                        facePhotoUrl: _facePhotoUrl,
                        facePhotoPath: _facePhotoPath,
                        profileLoading: _profileLoading,
                        notificationCount: NotificationService.count,
                        onNotificationTap: () =>
                            _showNotificationsDialog(width),
                        onVerifyTap: _goToVerification,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  _animated(
                    1,
                    HomeCommunitySection(
                      width: contentW,
                      onViewAll: _goToNewsFeed,
                    ),
                  ),
                  SizedBox(height: sectionGap),
                  _animated(
                    2,
                    HomeQuickActionsSection(
                      width: contentW,
                      onActionTap: _handleQuickAction,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileHeader(double width, double height) {
    return SizedBox(
      width: double.infinity,
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/bg.png',
            fit: BoxFit.cover,
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
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              height: math.min(width * 0.20, 80),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  // Fade into the mobile scaffold bg for a seamless join.
                  colors: [Colors.transparent, Colors.white],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Web body — divider line removed, hero handles its own spacing ──────────
  Widget _buildWebBody(
    double width,
    double height, {
    required bool showTopNav,
  }) {
    final sidePad = width >= _kTwoColumnBreakpoint
        ? _kSidePadDesktop
        : _kSidePadNarrowWeb;

    return ColoredBox(
      color: const Color(0xFFF3F6FC),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Top navigation bar (wide only) ─────────────────────
            if (showTopNav)
              HomeTopNav(
                currentIndex: _navIndex,
                onTap: _handleNavTap,
                notificationCount: NotificationService.count,
                onNotificationTap: () => _showNotificationsDialog(width),
                onLogoutTap: _handleLogout,
                compact: width < _kNavCompactBelow,
                username: widget.username,
                fullName: _fullName,
                facePhotoUrl: _facePhotoUrl,
                verifStatus: _verifStatus == VerifStatus.verified
                    ? 'approved'
                    : _verifStatus == VerifStatus.pending
                    ? 'pending'
                    : 'none',
              ),

            // ── Hero section — card overlaps bottom via Stack ──────
            _animated(
              0,
              HomeHeroSection(
                username: widget.username,
                fullName: _fullName,
                facePhotoUrl: _facePhotoUrl,
                facePhotoPath: _facePhotoPath,
                verifStatus: _verifStatus,
                profileLoading: _profileLoading,
                onVerifyTap: _goToVerification,
                sidePadding: sidePad,
                contentMaxWidth: _kDashboardMaxWidth,
              ),
            ),

            // ── Two-column / single-column content ─────────────────
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: _kDashboardMaxWidth,
                ),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(sidePad, 16, sidePad, 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (width >= _kTwoColumnBreakpoint)
                        _buildTwoColumn()
                      else
                        _buildSingleColumn(),
                    ],
                  ),
                ),
              ),
            ),

            // ── Stats bar ──────────────────────────────────────────
            _animated(3, const HomeStatsBar()),

            // ── Footer ────────────────────────────────────────────
            _animated(4, const HomeFooter()),
          ],
        ),
      ),
    );
  }

  Widget _buildTwoColumn() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalW = constraints.maxWidth;
        final leftW = (totalW - _kColGap) * 0.62;
        final rightW = (totalW - _kColGap) * 0.38;

        return _EqualHeightColumns(
          leftWidth: leftW,
          rightWidth: rightW,
          gap: _kColGap,
          // Community = left, receives the matched height and scrolls internally.
          left: (matchedHeight) => _animated(
            1,
            HomeCommunitySectionWeb(
              onViewAll: _goToNewsFeed,
              height: matchedHeight,
            ),
          ),
          // Quick Actions = right, drives the height (sized to its 4 tiles).
          right: (matchedHeight) => _animated(
            2,
            HomeQuickActionsSectionWeb(
              onActionTap: _handleQuickAction,
              height: matchedHeight,
            ),
          ),
        );
      },
    );
  }

  Widget _buildSingleColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _animated(1, HomeCommunitySectionWeb(onViewAll: _goToNewsFeed)),
        const SizedBox(height: 20),
        _animated(
          2,
          HomeQuickActionsSectionWeb(onActionTap: _handleQuickAction),
        ),
      ],
    );
  }

  PreferredSizeWidget _buildDrawerAppBar(double width) {
    return AppBar(
      backgroundColor: Colors.white,
      foregroundColor: const Color(0xFF1F2937),
      elevation: 0,
      surfaceTintColor: Colors.white,
      iconTheme: const IconThemeData(color: Color(0xFF374151)),
      title: Image.asset(
        'assets/images/applogocrop.png',
        height: 32,
        errorBuilder: (_, _, _) => const Text(
          'Aparri',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 18,
            color: Color(0xFF1F2937),
          ),
        ),
      ),
      shape: const Border(
        bottom: BorderSide(color: Color(0xFFE5E7EB), width: 1),
      ),
      actions: [
        IconButton(
          onPressed: () => _showNotificationsDialog(width),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              Image.asset(
                'assets/images/notifications.png',
                width: 28,
                height: 28,
                errorBuilder: (_, _, _) =>
                    const Icon(Icons.notifications_outlined, size: 30),
              ),
              if (NotificationService.count > 0)
                Positioned(
                  right: -4,
                  top: -4,
                  child: Container(
                    constraints: const BoxConstraints(
                      minWidth: 14,
                      minHeight: 14,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF22C55E),
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(color: Colors.white, width: 1.2),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${NotificationService.count}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
      ],
    );
  }
}

class _EqualHeightColumns extends StatefulWidget {
  final double leftWidth;
  final double rightWidth;
  final double gap;
  final Widget Function(double? matchedHeight) left;
  final Widget Function(double? matchedHeight) right;

  const _EqualHeightColumns({
    required this.leftWidth,
    required this.rightWidth,
    required this.gap,
    required this.left,
    required this.right,
  });

  @override
  State<_EqualHeightColumns> createState() => _EqualHeightColumnsState();
}

class _EqualHeightColumnsState extends State<_EqualHeightColumns> {
  final GlobalKey _leftKey = GlobalKey();
  final GlobalKey _rightKey = GlobalKey();
  double? _matched;
  bool _scheduled = false;

  void _scheduleMeasure() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      _measure();
    });
  }

  void _measure() {
    if (!mounted) return;
    try {
      // Read contexts defensively — on the first frame (and after a hot
      // reload) the keyed subtrees may not be attached yet.
      final leftCtx = _leftKey.currentContext;
      final rightCtx = _rightKey.currentContext;
      if (leftCtx == null || rightCtx == null) {
        // Not laid out yet — try again next frame.
        _scheduleMeasure();
        return;
      }

      final lh = leftCtx.size?.height;
      final rh = rightCtx.size?.height;
      if (lh == null || rh == null) {
        _scheduleMeasure();
        return;
      }

      final target = math.max(lh, rh);
      if (target > 0 &&
          (_matched == null || (_matched! - target).abs() > 0.5)) {
        setState(() => _matched = target);
      }
    } catch (_) {
      // Swallow stale-callback / detached-element errors (common during
      // hot reload). The next build will reschedule a clean measure.
    }
  }

  @override
  void didUpdateWidget(covariant _EqualHeightColumns oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.leftWidth != widget.leftWidth ||
        oldWidget.rightWidth != widget.rightWidth) {
      _matched = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    _scheduleMeasure();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: widget.leftWidth,
          child: KeyedSubtree(key: _leftKey, child: widget.left(_matched)),
        ),
        SizedBox(width: widget.gap),
        SizedBox(
          width: widget.rightWidth,
          child: KeyedSubtree(key: _rightKey, child: widget.right(_matched)),
        ),
      ],
    );
  }
}
