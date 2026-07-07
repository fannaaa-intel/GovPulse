import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/chat_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import '../../../features/home/screen/notification_popup.dart';
import '../../../core/network/network_wrapper.dart';
import '../../../core/utils/overlay_exit.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/modal/verification_required_dialog.dart';
import '../Quick-action/Report/report_issue_screen.dart';
import '../Quick-action/Chat-with-Agent/chat_agent_screen.dart';
import '../Quick-action/Suggestion/suggestion_screen.dart';
// ─── NEW ──────────────────────────────────────────────────────────────────────
import '../Quick-action/Feedback/feedback_screen.dart';
// ─────────────────────────────────────────────────────────────────────────────

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

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/push_service.dart';
import '../../../core/services/citizen_guard.dart';
import '../../../core/widgets/citizen_guard_modals.dart';
import '../../../core/providers/user_profile_provider.dart';

class HomePage extends ConsumerStatefulWidget {
  final String username;
  const HomePage({super.key, required this.username});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage>
    with TickerProviderStateMixin
    implements RouteAware {
  final FlutterLocalNotificationsPlugin notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  DateTime? lastBackPressed;

  late final AnimationController _entryCtrl;
  static const int _navIndex = 0;

  // ── Responsive bands ──────────────────────────────────────────────────────
  //   width <  _kMobileBreakpoint  → MOBILE body  + bottom nav   (phones)
  //   600–900                      → WEB body      + drawer       (tablet-web)
  //   width >= _kTopNavBreakpoint   → WEB body      + top nav      (desktop)
  static const double _kMobileBreakpoint = 600;
  static const double _kTopNavBreakpoint = 900;
  static const double _kMobileContentMax = 480;
  static const double _kTwoColumnBreakpoint = 1100;
  static const double _kNavCompactBelow = 1050;
  static const double _kDashboardMaxWidth = 1280;
  static const double _kSidePadDesktop = 32;
  static const double _kSidePadNarrowWeb = 20;
  static const double _kColGap = 28;

  // ── Helper getter so methods outside build() can read verifStatus ─────────
  VerifStatus get _verifStatus =>
      ref.read(userProfileProvider).valueOrNull?.verifStatus ??
      VerifStatus.none;

  @override
  void initState() {
    super.initState();
    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _initNotifications();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      precacheImage(const AssetImage('assets/images/bg.webp'), context);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final current = ref.read(userProfileProvider);
      if (current.hasValue && !current.isLoading) {
        _entryCtrl.forward(from: 0);
      }
    });

    ref.listenManual(userProfileProvider, (prev, next) {
      if ((prev == null || prev.isLoading) && !next.isLoading && mounted) {
        final status = next.valueOrNull?.verifStatus ?? VerifStatus.none;
        if (status == VerifStatus.none) {
          Future.delayed(const Duration(minutes: 3), () {
            if (mounted) _triggerVerificationReminder();
          });
        }
        _entryCtrl.forward(from: 0);
      }
    });

    NotificationService.load().then((_) {
      if (mounted) setState(() {});
    });

    // Account enforcement: suspension → modal + auto sign-out; restriction →
    // notice modal + per-feature gates. Starts the live subscription and shows
    // the right modal on first load / whenever the status changes.
    CitizenGuard.I.start();
    CitizenGuard.I.status.addListener(_onGuardStatus);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onGuardStatus());
  }

  bool _guardModalOpen = false;
  String? _shownRestrictionSig;

  void _onGuardStatus() {
    if (!mounted || _guardModalOpen) return;
    final s = CitizenGuard.I.status.value;
    if (s.suspension != null) {
      _guardModalOpen = true;
      showSuspendedModal(context, s.suspension!)
          .whenComplete(() => _guardModalOpen = false);
      return;
    }
    final r = s.restriction;
    if (r != null && r.signature != _shownRestrictionSig) {
      _shownRestrictionSig = r.signature;
      _guardModalOpen = true;
      showRestrictionNotice(context, r)
          .whenComplete(() => _guardModalOpen = false);
    }
  }

  @override
  void dispose() {
    CitizenGuard.I.status.removeListener(_onGuardStatus);
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
  void didPopNext() {}
  @override
  void didPush() {}
  @override
  void didPushNext() {}
  @override
  void didPop() {}

  Animation<double> _fade(int i) {
    return Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _entryCtrl,
        curve: Interval(
          (i * 0.18).clamp(0.0, 1.0),
          ((i * 0.18) + 0.5).clamp(0.0, 1.0),
          curve: Curves.easeOut,
        ),
      ),
    );
  }

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

  /// Instant push — the destination screen's AnimationController handles the
  /// slide-up of its own content, so there is no double-animation.
  Route<T> _quickActionRoute<T>(Widget page) {
    return PageRouteBuilder<T>(
      transitionDuration: Duration.zero,
      reverseTransitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (_, _, _) => page,
      transitionsBuilder: (_, anim, _, child) =>
          FadeTransition(opacity: anim, child: child),
    );
  }

  // ── Navigation helpers ────────────────────────────────────────────────────

  void _goToNewsFeed({String? postId, bool openComments = false}) async {
    if (!citizenGuardAllow(context, 'newsfeed')) return;
    // Ensure the profile is loaded before navigating, so the feed filters by
    // the user's barangay on first open — not just city-wide / LGU broadcasts.
    // On a fresh app launch the profile may still be loading when the user
    // taps; reading valueOrNull then would give null → wrong (city-wide) feed.
    var profile = ref.read(userProfileProvider).valueOrNull;
    if (profile == null) {
      try {
        profile = await ref.read(userProfileProvider.future);
      } catch (_) {}
    }
    if (!mounted) return;
    Navigator.pushNamed(
      context,
      '/newsfeed',
      arguments: {
        'username': widget.username,
        'isVerified':
            (profile?.verifStatus ?? _verifStatus) == VerifStatus.verified,
        'userBarangay': profile?.barangay,
        // Optional: jump to a specific post (from a notification tap).
        'initialPostId': ?postId,
        if (postId != null) 'initialOpenComments': openComments,
      },
    );
  }

  void _goToReport() {
    if (!citizenGuardAllow(context, 'reports')) return;
    if (_verifStatus != VerifStatus.verified) {
      showVerificationRequiredDialog(
        context,
        username: widget.username,
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
    if (!citizenGuardAllow(context, 'suggestions')) return;
    if (_verifStatus != VerifStatus.verified) {
      showVerificationRequiredDialog(
        context,
        username: widget.username,
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

  // ─── NEW ────────────────────────────────────────────────────────────────────
  void _goToFeedback() {
    if (!citizenGuardAllow(context, 'feedback')) return;
    if (_verifStatus != VerifStatus.verified) {
      showVerificationRequiredDialog(
        context,
        username: widget.username,
        message:
            'Only verified Aparri citizens can submit feedback. '
            'Please complete your identity verification first.',
      );
      return;
    }
    Navigator.push(
      context,
      _quickActionRoute(
        NetworkWrapper(child: FeedbackScreen(username: widget.username)),
      ),
    );
  }
  // ────────────────────────────────────────────────────────────────────────────

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
    if (!citizenGuardAllow(context, 'ai_chat')) return;
    if (_verifStatus != VerifStatus.verified) {
      showVerificationRequiredDialog(
        context,
        username: widget.username,
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

  // ─── Quick-action dispatcher ─────────────────────────────────────────────
  void _handleQuickAction(String key) {
    switch (key) {
      case 'report':
        _goToReport();
        break;
      case 'chat':
        _goToChat();
        break;
      case 'events':
        _goToEvents();
        break;
      case 'suggestion':
        _goToSuggestion();
        break;
      // ─── NEW ─────────────────────────────────────────────────────────────
      case 'feedback':
        _goToFeedback();
        break;
      // ─────────────────────────────────────────────────────────────────────
    }
  }

  void _handleNavTap(int index) {
    if (index == _navIndex) return;
    if (index == 1) {
      if (_verifStatus != VerifStatus.verified) {
        showVerificationRequiredDialog(
          context,
          username: widget.username,
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
      pageBuilder: (_, _, _) => NotificationPopup(
        width: width,
        onTap: (n) {
          Navigator.pop(context); // close the sheet, then route the tap
          routeCitizenNotificationTap(
            context,
            n,
            username: widget.username,
            isVerified: _verifStatus == VerifStatus.verified,
            isPending: _verifStatus == VerifStatus.pending,
            onOpenNewsFeed: ({String? postId, bool openComments = false}) =>
                _goToNewsFeed(postId: postId, openComments: openComments),
          );
        },
      ),
      transitionBuilder: (_, anim, _, child) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(
          scale: CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
          child: child,
        ),
      ),
    );
    // Re-sync from the DB after the sheet closes so a mid-animation Clear-All
    // still leaves the badge accurate (it may not finish deleting every row
    // before dismissal). load() updates NotificationService.unread; setState
    // also refreshes any child badges that read the count directly.
    await NotificationService.load();
    if (mounted) setState(() {});
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
                "You'll need to sign in again to access your account.",
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
      await PushService.I.unregister();
      await Supabase.instance.client.auth.signOut();
      await ChatService.I.clearOnLogout();
      HomeChatBubble.hideGlobal();
      if (!mounted) return;

      Navigator.pop(context);
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      showAppSnackBar(context, 'Logout failed: $e', type: AppSnackType.error);
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

  // ── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final width = size.width;
    final height = size.height;

    final profileAsync = ref.watch(userProfileProvider);
    final profile = profileAsync.valueOrNull;
    final verifStatus = profile?.verifStatus ?? VerifStatus.none;
    final facePhotoUrl = profile?.facePhotoUrl;
    final facePhotoPath = profile?.facePhotoPath;
    final fullName = profile?.fullName;
    final profileLoading = profileAsync.isLoading;

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
        appBar: useDrawer ? _buildDrawerAppBar(width) : null,
        drawer: useDrawer
            ? HomeNavDrawer(
                currentIndex: _navIndex,
                onTap: _handleNavTap,
                username: widget.username,
                fullName: fullName,
                facePhotoUrl: facePhotoUrl,
                verifStatus: verifStatus,
                onLogout: _handleLogout,
              )
            : null,
        body: LoadingOverlay.bodyOrSkeleton(
          isLoading: profileLoading,
          layout: SkeletonLayout.home,
          child: useMobile
              ? SafeArea(
                  child: _buildMobileBody(
                    width,
                    height,
                    verifStatus,
                    facePhotoUrl,
                    facePhotoPath,
                    fullName,
                    profileLoading,
                    profile?.barangay,
                  ),
                )
              : _buildWebBody(
                  width,
                  height,
                  showTopNav: useTopNav,
                  verifStatus: verifStatus,
                  facePhotoUrl: facePhotoUrl,
                  facePhotoPath: facePhotoPath,
                  fullName: fullName,
                  profileLoading: profileLoading,
                  barangay: profile?.barangay,
                ),
        ),
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

  // ── Mobile body ───────────────────────────────────────────────────────────
  Widget _buildMobileBody(
    double width,
    double height,
    VerifStatus verifStatus,
    String? facePhotoUrl,
    String? facePhotoPath,
    String? fullName,
    bool profileLoading,
    String? barangay,
  ) {
    final double headerHeight = (width * 0.52).clamp(200.0, 300.0);
    final double cardPull = (width * 0.05).clamp(14.0, 28.0);
    final double sectionGap = (width * 0.05).clamp(16.0, 28.0);
    final double contentW = math.min(width, _kMobileContentMax);

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        children: [
          _buildMobileHeader(width, headerHeight),
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
                        verifStatus: verifStatus,
                        fullName: fullName,
                        facePhotoUrl: facePhotoUrl,
                        facePhotoPath: facePhotoPath,
                        profileLoading: profileLoading,
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
                      barangay: barangay,
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
            'assets/images/bg.webp',
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
                  colors: [Colors.transparent, Colors.white],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Web body ──────────────────────────────────────────────────────────────
  Widget _buildWebBody(
    double width,
    double height, {
    required bool showTopNav,
    required VerifStatus verifStatus,
    required String? facePhotoUrl,
    required String? facePhotoPath,
    required String? fullName,
    required bool profileLoading,
    required String? barangay,
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
            if (showTopNav)
              HomeTopNav(
                currentIndex: _navIndex,
                onTap: _handleNavTap,
                notificationCount: NotificationService.count,
                onNotificationTap: () => _showNotificationsDialog(width),
                onLogoutTap: _handleLogout,
                compact: width < _kNavCompactBelow,
                username: widget.username,
                fullName: fullName,
                facePhotoUrl: facePhotoUrl,
                verifStatus: verifStatus == VerifStatus.verified
                    ? 'approved'
                    : verifStatus == VerifStatus.pending
                    ? 'pending'
                    : 'none',
              ),
            _animated(
              0,
              HomeHeroSection(
                username: widget.username,
                fullName: fullName,
                facePhotoUrl: facePhotoUrl,
                facePhotoPath: facePhotoPath,
                verifStatus: verifStatus,
                profileLoading: profileLoading,
                onVerifyTap: _goToVerification,
                sidePadding: sidePad,
                contentMaxWidth: _kDashboardMaxWidth,
              ),
            ),
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
                        _buildTwoColumn(barangay)
                      else
                        _buildSingleColumn(barangay),
                    ],
                  ),
                ),
              ),
            ),
            _animated(3, const HomeStatsBar()),
            _animated(4, const HomeFooter()),
          ],
        ),
      ),
    );
  }

  Widget _buildTwoColumn(String? barangay) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalW = constraints.maxWidth;
        final leftW = (totalW - _kColGap) * 0.62;
        final rightW = (totalW - _kColGap) * 0.38;

        return _EqualHeightColumns(
          leftWidth: leftW,
          rightWidth: rightW,
          gap: _kColGap,
          left: (h) => _animated(
            1,
            HomeCommunitySectionWeb(
              onViewAll: _goToNewsFeed,
              height: h,
              barangay: barangay,
            ),
          ),
          right: (h) => _animated(
            2,
            HomeQuickActionsSectionWeb(
              onActionTap: _handleQuickAction,
              height: h,
            ),
          ),
        );
      },
    );
  }

  Widget _buildSingleColumn(String? barangay) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _animated(
          1,
          HomeCommunitySectionWeb(onViewAll: _goToNewsFeed, barangay: barangay),
        ),
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
        'assets/images/applogocrop.webp',
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
                'assets/images/notifications.webp',
                width: 28,
                height: 28,
                errorBuilder: (_, _, _) =>
                    const Icon(Icons.notifications_outlined, size: 30),
              ),
              Positioned(
                right: -4,
                top: -4,
                child: ValueListenableBuilder<int>(
                  valueListenable: NotificationService.unread,
                  builder: (_, count, _) {
                    if (count <= 0) return const SizedBox.shrink();
                    return Container(
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
                        '$count',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    );
                  },
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

// ── Equal-height two-column layout ────────────────────────────────────────────

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
      final lh = _leftKey.currentContext?.size?.height;
      final rh = _rightKey.currentContext?.size?.height;
      if (lh == null || rh == null) {
        _scheduleMeasure();
        return;
      }
      final target = math.max(lh, rh);
      if (target > 0 &&
          (_matched == null || (_matched! - target).abs() > 0.5)) {
        setState(() => _matched = target);
      }
    } catch (_) {}
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