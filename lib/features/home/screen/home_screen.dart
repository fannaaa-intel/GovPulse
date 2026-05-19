import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../profileVerification/verification_screen.dart';
import '../../../features/home/screen/notification_popup.dart';
import '../../../core/network/network_wrapper.dart';
import '../../../core/utils/overlay_exit.dart';
import '../../../core/widgets/modal/verification_required_dialog.dart';
import '../Quick-action/Report/report_issue_screen.dart';
import '../Quick-action/Chat-with-Agent/chat_agent_screen.dart';
import '../Quick-action/Suggestion/suggestion_screen.dart';
// ── Widget imports ────────────────────────────────────────────────────────────
import '../../../core/widgets/Home/home_enums.dart';
import '../../../core/widgets/Home/home_profile_card.dart';
import '../../../core/widgets/Home/home_community_section.dart';
import '../../../core/widgets/Home/home_quick_actions_section.dart';
import '../../../core/widgets/Home/home_bottom_nav.dart';
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

  // ── State ─────────────────────────────────────────────────────────────────
  VerifStatus _verifStatus = VerifStatus.none;
  String? _facePhotoUrl;
  String? _fullName;
  bool _profileLoading = true;

  // ── Scroll ────────────────────────────────────────────────────────────────
  final ScrollController _communityScrollController = ScrollController();
  int _currentCommunityDot = 0;

  // ── Animation ─────────────────────────────────────────────────────────────
  late final AnimationController _entryCtrl;
  static const int _navIndex = 0;

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) _entryCtrl.forward();
      });
    });

    Future.delayed(const Duration(minutes: 3), () {
      if (mounted && _verifStatus == VerifStatus.none) {
        _triggerVerificationReminder();
      }
    });

    _communityScrollController.addListener(() {
      final width = MediaQuery.of(context).size.width;
      final cardWidth = (width * 0.86 - width * 0.04) / 3;
      final gap = width * 0.02;
      final index = (_communityScrollController.offset / (cardWidth + gap))
          .round();
      final clamped = index.clamp(0, 3);
      if (_currentCommunityDot != clamped) {
        setState(() => _currentCommunityDot = clamped);
      }
    });
  }

  @override
  void dispose() {
    homeRouteObserver.unsubscribe(this);
    _entryCtrl.dispose();
    _communityScrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    homeRouteObserver.subscribe(this, ModalRoute.of(context)!);
  }

  @override
  void didPopNext() => _loadVerificationStatus();
  @override
  void didPush() {}
  @override
  void didPushNext() {}
  @override
  void didPop() {}

  // ── Animation helpers ─────────────────────────────────────────────────────
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

  // ── Navigation ────────────────────────────────────────────────────────────
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
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (_, _, _) =>
            NetworkWrapper(child: ReportIssueScreen(username: widget.username)),
        transitionsBuilder: (_, anim, _, child) => SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: child,
        ),
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
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (_, _, _) =>
            NetworkWrapper(child: SuggestionScreen(username: widget.username)),
        transitionsBuilder: (_, anim, _, child) => SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: child,
        ),
      ),
    );
  }

  void _goToEvents() {
    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 420),
        pageBuilder: (_, _, _) => NetworkWrapper(
          child: EventsScreen(
            username: widget.username,
            isVerified: _verifStatus == VerifStatus.verified,
          ),
        ),
        transitionsBuilder: (_, anim, _, child) => SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: child,
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
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 420),
        pageBuilder: (_, _, _) =>
            NetworkWrapper(child: ChatAgentScreen(username: widget.username)),
        transitionsBuilder: (_, anim, _, child) => SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: child,
        ),
      ),
    ).then((_) {
      if (!mounted) return;
      HomeChatBubble.showGlobal();
    });
  }

  void _goToVerification() {
    if (_verifStatus == VerifStatus.pending) return;
    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (_, _, _) => NetworkWrapper(
          child: VerificationScreen(username: widget.username),
        ),
        transitionsBuilder: (_, anim, _, child) => SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: anim, curve: Curves.easeInOut)),
          child: child,
        ),
      ),
    );
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

  // ── Supabase ──────────────────────────────────────────────────────────────
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
          try {
            faceUrl = await supabase.storage
                .from('verification-assets')
                .createSignedUrl(facePath, 3600);
          } catch (_) {
            try {
              faceUrl = supabase.storage
                  .from('verification-assets')
                  .getPublicUrl(facePath);
            } catch (_) {}
          }
        }
        if (mounted) {
          setState(() {
            _verifStatus = verifStatus;
            _facePhotoUrl = faceUrl;
            _fullName = fullName;
            _profileLoading = false;
          });
        }
      } else {
        String? fullName;
        String? faceUrl;
        try {
          final res = await supabase
              .from('profiles')
              .select('username, email')
              .eq('id', uid)
              .maybeSingle();
          if (res != null) fullName = res['username'] as String?;
        } catch (_) {}
        if (facePath != null && facePath.isNotEmpty) {
          try {
            faceUrl = await supabase.storage
                .from('verification-assets')
                .createSignedUrl(facePath, 3600);
          } catch (_) {
            try {
              faceUrl = supabase.storage
                  .from('verification-assets')
                  .getPublicUrl(facePath);
            } catch (_) {}
          }
        }
        if (mounted) {
          setState(() {
            _verifStatus = verifStatus;
            _facePhotoUrl = faceUrl;
            _fullName = fullName;
            _profileLoading = false;
          });
        }
      }
    } catch (_) {
      if (mounted) setState(() => _profileLoading = false);
    }
  }

  // ── Notifications ─────────────────────────────────────────────────────────
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

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final width = size.width;
    final height = size.height;

    return LoadingOverlay(
      isLoading: _profileLoading,
      skeletonLayout: SkeletonLayout.home,
      child: PopScope(
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
            Navigator.of(context).pop();
          }
        },
        child: Scaffold(
          backgroundColor: const Color(0xFFF3F4F6),
          body: SafeArea(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                children: [
                  _buildHeader(width),
                  _animated(
                    0,
                    Transform.translate(
                      offset: Offset(0, -width * 0.05),
                      child: HomeProfileCard(
                        username: widget.username,
                        verifStatus: _verifStatus,
                        fullName: _fullName,
                        facePhotoUrl: _facePhotoUrl,
                        profileLoading: _profileLoading,
                        notificationCount: NotificationService.count,
                        onNotificationTap: () =>
                            _showNotificationsDialog(width),
                        onVerifyTap: _goToVerification,
                      ),
                    ),
                  ),
                  SizedBox(height: width * 0.002),
                  _animated(
                    1,
                    HomeCommunitySection(
                      width: width,
                      scrollController: _communityScrollController,
                      currentDot: _currentCommunityDot,
                      onViewAll: _goToNewsFeed,
                    ),
                  ),
                  SizedBox(height: width * 0.05),
                  _animated(
                    2,
                    HomeQuickActionsSection(
                      width: width,
                      onActionTap: _handleQuickAction,
                    ),
                  ),
                  SizedBox(height: height * 0.02),
                ],
              ),
            ),
          ),
          bottomNavigationBar: HomeBottomNav(
            width: width,
            currentIndex: _navIndex,
            onTap: _handleNavTap,
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(double width) {
    return SizedBox(
      width: double.infinity,
      height: width * 0.52,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/images/bg.png', fit: BoxFit.cover),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              height: width * 0.20,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xFFF3F4F6)],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
