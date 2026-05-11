import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../profileVerification/verification_screen.dart';
import '../../../features/home/screen/notification_popup.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/overlay_exit.dart';
import '../report/report_issue_screen.dart';
import '../../../core/widgets/modal/verification_required_dialog.dart';

// ── Verification status ───────────────────────────────────────────────────────
final RouteObserver<ModalRoute<void>> homeRouteObserver =
    RouteObserver<ModalRoute<void>>();

enum _VerifStatus { none, pending, verified }

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

  // ── Verification / profile state ──────────────────────────────────────────
  _VerifStatus _verifStatus = _VerifStatus.none;
  String? _facePhotoUrl;
  String? _fullName;
  bool _profileLoading = true;

  // Community Updates scroll tracking
  final ScrollController _communityScrollController = ScrollController();
  int _currentCommunityDot = 0;

  // Quick Actions scroll tracking
  final ScrollController _quickScrollController = ScrollController();
  int _currentQuickDot = 0;

  // ── Entry animation ───────────────────────────────────────────────────────
  late final AnimationController _entryCtrl;

  // Bottom nav
  static const int _navIndex = 0;

  double _cardWidth(double width) {
    return (width * 0.86 - width * 0.04) / 3;
  }

  double _quickCardWidth(double width) {
    final available = width - width * 0.08 - width * 0.06;
    return (available - width * 0.02 * 2) / 3.35;
  }

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

    // ✅ 3 min after opening home → remind unverified users to complete verification (only once)
    Future.delayed(const Duration(minutes: 3), () {
      if (mounted && _verifStatus == _VerifStatus.none) {
        _triggerVerificationReminder();
      }
    });

    _communityScrollController.addListener(() {
      final width = MediaQuery.of(context).size.width;
      final cardWidth = _cardWidth(width);
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
    _quickScrollController.dispose();
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
  }

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

  Animation<Offset> _slide(int i) =>
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
    child: SlideTransition(position: _slide(i), child: child),
  );

  // ── Navigation helpers ────────────────────────────────────────────────────
  void _goToNewsFeed() {
    Navigator.pushNamed(
      context,
      '/newsfeed',
      arguments: {
        'username': widget.username,
        'isVerified': _verifStatus == _VerifStatus.verified,
      },
    );
  }

  void _goToReport() {
    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (context, animation, secondaryAnimation) =>
            ReportIssueScreen(username: widget.username),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final slide =
              Tween<Offset>(
                begin: const Offset(0, 1),
                end: Offset.zero,
              ).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              );
          return SlideTransition(position: slide, child: child);
        },
      ),
    );
  }

  // ── Load verification status + face photo from Supabase ───────────────────
  Future<void> _loadVerificationStatus() async {
    try {
      final supabase = Supabase.instance.client;
      final uid = supabase.auth.currentUser?.id;

      if (uid == null) {
        if (mounted) setState(() => _profileLoading = false);
        return;
      }

      // ── Step 1: Get verification status ──
      final verifRow = await supabase
          .from('verification_submissions')
          .select('status, face_photo_path')
          .eq('user_id', uid)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      _VerifStatus verifStatus = _VerifStatus.none;
      String? facePath;

      if (verifRow != null) {
        final status = verifRow['status'] as String?;
        facePath = verifRow['face_photo_path'] as String?;

        if (status == 'approved') {
          verifStatus = _VerifStatus.verified;
        } else if (status == 'pending') {
          verifStatus = _VerifStatus.pending;
        } else {
          verifStatus = _VerifStatus.none;
        }
      }

      // ── Step 2: Branch by status ──
      if (verifStatus == _VerifStatus.verified) {
        // Verified → fetch from citizen_details
        String? fullName;
        String? faceUrl;

        try {
          final citizenRes = await supabase
              .from('citizen_details')
              .select('first_name, last_name, profile_photo_path')
              .eq('user_id', uid)
              .maybeSingle();

          if (citizenRes != null) {
            final firstName = citizenRes['first_name'] as String? ?? '';
            final lastName = citizenRes['last_name'] as String? ?? '';
            fullName = '${firstName.trim()} ${lastName.trim()}'.trim();
            if (fullName.trim().isEmpty) fullName = null;

            final profilePhoto =
                citizenRes['profile_photo_path'] as String? ?? '';
            if (profilePhoto.isNotEmpty) facePath = profilePhoto;
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
        // Pending or None → fetch username/email from profiles table
        String? fullName;
        String? faceUrl;

        try {
          final profileRes = await supabase
              .from('profiles')
              .select('username, email')
              .eq('id', uid)
              .maybeSingle();

          if (profileRes != null) {
            // Use username as display name for non-verified users
            fullName = profileRes['username'] as String?;
          }
        } catch (_) {}

        // Still try to show face photo if they submitted one (pending case)
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
            _fullName =
                fullName; // username from profiles, shown as display name
            _profileLoading = false;
          });
        }
      }
    } catch (_) {
      if (mounted) setState(() => _profileLoading = false);
    }
  }

  // ── Status badge config ───────────────────────────────────────────────────
  ({String label, Color bg, Color border, Color dot, Color text})
  get _statusBadge {
    switch (_verifStatus) {
      case _VerifStatus.pending:
        return (
          label: 'Status: Pending',
          bg: const Color(0xFFFFF7ED),
          border: const Color(0xFFF59E0B),
          dot: const Color(0xFFF59E0B),
          text: const Color(0xFFB45309),
        );
      case _VerifStatus.verified:
        return (
          label: 'Status: Verified',
          bg: const Color(0xFFECFDF5),
          border: const Color(0xFF22C55E),
          dot: const Color(0xFF22C55E),
          text: const Color(0xFF15803D),
        );
      case _VerifStatus.none:
        return (
          label: 'Status: Not Verified',
          bg: const Color(0xFFFFF7ED),
          border: const Color(0xFFF59E0B),
          dot: const Color(0xFFF59E0B),
          text: const Color(0xFFB45309),
        );
    }
  }

  void _initNotifications() async {
    const AndroidInitializationSettings androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings settings = InitializationSettings(
      android: androidInit,
    );
    await notificationsPlugin.initialize(settings);
  }

  void _triggerVerificationReminder() async {
    // ✅ FIX: await add() so the notification is persisted before setState
    final added = await NotificationService.add(
      AppNotification(
        icon: Icons.verified_user,
        title: "Verification Required",
        subtitle: "Complete your identity verification now",
        time: DateTime.now(),
        color: Colors.orange,
        type: 'verification_reminder', // ✅ typed so it only fires once
      ),
    );
    if (added && mounted) {
      setState(() {});
      _showLocalNotification();
    }
  }

  Future<void> _showLocalNotification() async {
    const androidDetails = AndroidNotificationDetails(
      'verification_channel',
      'Verification Reminder',
      importance: Importance.max,
      priority: Priority.high,
    );
    const details = NotificationDetails(android: androidDetails);
    await notificationsPlugin.show(
      0,
      'Complete Verification',
      'Tap to verify your account now',
      details,
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final width = size.width;
    final height = size.height;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final now = DateTime.now();
        if (lastBackPressed == null ||
            now.difference(lastBackPressed!) > const Duration(seconds: 2)) {
          lastBackPressed = now;
          ExitOverlay.show(context, "Press again to exit");
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
                    child: _buildProfileCard(context, width),
                  ),
                ),
                SizedBox(height: width * 0.002),
                _animated(1, _buildCommunityUpdatesSection(width)),
                SizedBox(height: width * 0.05),
                _animated(2, _buildQuickActionsSection(width)),
                SizedBox(height: height * 0.02),
              ],
            ),
          ),
        ),
        bottomNavigationBar: _buildBottomNav(width),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
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

  // ── Profile Card ──────────────────────────────────────────────────────────
  Widget _buildProfileCard(BuildContext context, double width) {
    final badge = _statusBadge;
    final isVerified = _verifStatus == _VerifStatus.verified;

    const String descNone =
        'Complete your identity verification as Aparri citizen to access full local government unit of Aparri services.';

    const String descPending =
        'Your submission is currently being processed by our admin team. '
        'Sit tight — once approved, you\'ll unlock the full potential of the app and all exclusive services for Aparri citizens!';

    final String desc = _verifStatus == _VerifStatus.pending
        ? descPending
        : _verifStatus == _VerifStatus.none
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Avatar ──
                if (isVerified)
                  _VerifiedAvatarRing(
                    width: width,
                    child: _buildProfileAvatar(width),
                  )
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
                    child: ClipOval(child: _buildProfileAvatar(width)),
                  ),

                SizedBox(width: width * 0.03),

                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(top: width * 0.012),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Full name ──
                        Text(
                          _fullName ?? widget.username,
                          style: TextStyle(
                            fontSize: width * 0.052,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF1F2937),
                          ),
                        ),

                        // ── @username ──
                        if (_fullName != null) ...[
                          SizedBox(height: width * 0.004),
                          Text(
                            '@${widget.username}',
                            style: TextStyle(
                              fontSize: width * 0.030,
                              fontWeight: FontWeight.w400,
                              color: const Color(0xFF6B7280),
                            ),
                          ),
                        ],

                        // ── Status badge (non-verified only) ──
                        if (!isVerified) ...[
                          SizedBox(height: width * 0.008),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 350),
                            child: Container(
                              key: ValueKey(_verifStatus),
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
                                  _profileLoading
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
                                    _profileLoading
                                        ? 'Loading...'
                                        : badge.label,
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
                _buildNotificationBadge(context, width),
              ],
            ),

            // ── Description (non-verified) ──
            if (desc.isNotEmpty) ...[
              SizedBox(height: width * 0.04),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                child: Text(
                  desc,
                  key: ValueKey(_verifStatus),
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

            // ── Buttons (non-verified) ──
            if (!isVerified) ...[
              SizedBox(height: width * 0.045),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    if (_verifStatus == _VerifStatus.pending) return;
                    Navigator.push(
                      context,
                      PageRouteBuilder(
                        transitionDuration: const Duration(milliseconds: 400),
                        pageBuilder: (context, animation, secondaryAnimation) =>
                            VerificationScreen(username: widget.username),
                        transitionsBuilder:
                            (context, animation, secondaryAnimation, child) {
                              final slide =
                                  Tween<Offset>(
                                    begin: const Offset(1, 0),
                                    end: Offset.zero,
                                  ).animate(
                                    CurvedAnimation(
                                      parent: animation,
                                      curve: Curves.easeInOut,
                                    ),
                                  );
                              return SlideTransition(
                                position: slide,
                                child: child,
                              );
                            },
                      ),
                    );
                  },
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
                  child: _verifStatus == _VerifStatus.pending
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

  // ── Profile avatar builder ────────────────────────────────────────────────
  Widget _buildProfileAvatar(double width) {
    final size = width * 0.17;

    if (_profileLoading) {
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

    if (_facePhotoUrl != null && _facePhotoUrl!.isNotEmpty) {
      return Image.network(
        _facePhotoUrl!,
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

  // ── Notification badge ────────────────────────────────────────────────────
  Widget _buildNotificationBadge(BuildContext context, double width) {
    return GestureDetector(
      onTap: () => _showNotifications(context, width),
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
                '${NotificationService.count}',
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

  void _showNotifications(BuildContext context, double width) async {
    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: "Notifications",
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, animation, secondaryAnimation) =>
          NotificationPopup(width: width),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutBack,
            ),
            child: child,
          ),
        );
      },
    );
    setState(() {});
  }

  // ── Shared dots widget ────────────────────────────────────────────────────
  Widget _buildDots(double width, int count, int activeIndex) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final isActive = i == activeIndex;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: EdgeInsets.symmetric(horizontal: width * 0.007),
          width: isActive ? width * 0.050 : width * 0.020,
          height: width * 0.020,
          decoration: BoxDecoration(
            color: isActive ? AppColors.primaryBlue : const Color(0xFFD1D5DB),
            borderRadius: BorderRadius.circular(width * 0.010),
          ),
        );
      }),
    );
  }

  // ── Blank picture placeholder ─────────────────────────────────────────────
  Widget _buildImagePlaceholder(double width) {
    return Container(
      color: const Color(0xFFE5E7EB),
      child: Center(
        child: Icon(
          Icons.image_outlined,
          size: width * 0.10,
          color: const Color(0xFF9CA3AF),
        ),
      ),
    );
  }

  // ── Community Updates ─────────────────────────────────────────────────────
  Widget _buildCommunityUpdatesSection(double width) {
    final List<Map<String, dynamic>> updates = [
      {
        'title': 'Fire Out beside Florida Terminal',
        'location': 'Brgy. Minanga',
        'time': '45m Ago',
        'comments': '23',
        'likes': '55',
      },
      {
        'title': 'Water Supply Interruption',
        'location': 'Brgy. Maura',
        'time': '8h Ago',
        'comments': '23',
        'likes': '55',
      },
      {
        'title': 'New Barangay Health Center Inauguration',
        'location': 'Brgy. Dodan',
        'time': '8h Ago',
        'comments': '23',
        'likes': '55',
      },
      {
        'title': 'Assembly Meeting for Public Market',
        'location': 'Brgy. Centro',
        'time': '1d Ago',
        'comments': '12',
        'likes': '64',
      },
    ];

    final cardWidth = _cardWidth(width);
    final totalDots = (updates.length / 3).ceil();

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: width * 0.04),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(
          width * 0.03,
          width * 0.03,
          width * 0.03,
          width * 0.025,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(width * 0.04),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Community Updates',
                  style: TextStyle(
                    fontSize: width * 0.048,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryBlue,
                  ),
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _goToNewsFeed,
                  child: Row(
                    children: [
                      Text(
                        'View All',
                        style: TextStyle(
                          fontSize: width * 0.034,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF6B7280),
                        ),
                      ),
                      SizedBox(width: width * 0.008),
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: width * 0.030,
                        color: const Color(0xFF9CA3AF),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: width * 0.03),
            SizedBox(
              height: cardWidth * 1.95,
              child: ListView.separated(
                controller: _communityScrollController,
                scrollDirection: Axis.horizontal,
                physics: const PageScrollPhysics(),
                itemCount: updates.length,
                separatorBuilder: (context, index) =>
                    SizedBox(width: width * 0.022),
                itemBuilder: (context, index) {
                  final u = updates[index];
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _goToNewsFeed,
                    child: Container(
                      width: cardWidth,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(width * 0.03),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(width * 0.03),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              height: cardWidth * 1.03,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  _buildImagePlaceholder(width),
                                  Container(
                                    color: Colors.black.withValues(alpha: 0.05),
                                  ),
                                  Positioned(
                                    top: width * 0.015,
                                    left: width * 0.015,
                                    child: Container(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: width * 0.014,
                                        vertical: width * 0.006,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(
                                          alpha: 0.55,
                                        ),
                                        borderRadius: BorderRadius.circular(
                                          width * 0.02,
                                        ),
                                      ),
                                      child: Text(
                                        u['time'],
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: width * 0.020,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    bottom: width * 0.015,
                                    left: width * 0.015,
                                    child: Container(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: width * 0.014,
                                        vertical: width * 0.007,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF22C55E),
                                        borderRadius: BorderRadius.circular(
                                          width * 0.03,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.location_on,
                                            size: width * 0.020,
                                            color: Colors.white,
                                          ),
                                          SizedBox(width: width * 0.004),
                                          Text(
                                            u['location'],
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: width * 0.018,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: Padding(
                                padding: EdgeInsets.fromLTRB(
                                  width * 0.02,
                                  width * 0.018,
                                  width * 0.02,
                                  width * 0.015,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        u['title'],
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: width * 0.031,
                                          height: 1.22,
                                          fontWeight: FontWeight.w700,
                                          color: const Color(0xFF1F2937),
                                        ),
                                      ),
                                    ),
                                    SizedBox(height: width * 0.012),
                                    Row(
                                      children: [
                                        Image.asset(
                                          'assets/images/heart.png',
                                          width: width * 0.036,
                                          height: width * 0.036,
                                          fit: BoxFit.contain,
                                          color: AppColors.primaryBlue,
                                          errorBuilder:
                                              (context, error, stack) => Icon(
                                                Icons.favorite_rounded,
                                                size: width * 0.036,
                                                color: AppColors.primaryBlue,
                                              ),
                                        ),
                                        SizedBox(width: width * 0.007),
                                        Text(
                                          u['likes'],
                                          style: TextStyle(
                                            fontFamily: 'Poppins',
                                            fontSize: width * 0.028,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.primaryBlue,
                                            letterSpacing: 0.3,
                                            height: 1,
                                          ),
                                        ),
                                        SizedBox(width: width * 0.028),
                                        Image.asset(
                                          'assets/images/comment.png',
                                          width: width * 0.040,
                                          height: width * 0.040,
                                          fit: BoxFit.contain,
                                          color: AppColors.primaryBlue,
                                          errorBuilder:
                                              (context, error, stack) => Icon(
                                                Icons.chat_bubble_rounded,
                                                size: width * 0.040,
                                                color: AppColors.primaryBlue,
                                              ),
                                        ),
                                        SizedBox(width: width * 0.007),
                                        Text(
                                          u['comments'],
                                          style: TextStyle(
                                            fontFamily: 'Poppins',
                                            fontSize: width * 0.028,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.primaryBlue,
                                            letterSpacing: 0.3,
                                            height: 1,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            SizedBox(height: width * 0.025),
            _buildDots(width, totalDots, _currentCommunityDot),
          ],
        ),
      ),
    );
  }

  // ── Quick Actions ─────────────────────────────────────────────────────────
  Widget _buildQuickActionsSection(double width) {
    // ✅ 'key' field added to every action so onTap routing works
    final List<Map<String, dynamic>> actions = [
      {
        'key': 'chat',
        'iconPath': 'assets/images/customer.png',
        'title': 'Chat with Agent',
        'accentColor': const Color(0xFF3B82F6),
      },
      {
        'key': 'report', // ← THIS is what was missing
        'iconPath': 'assets/images/report.png',
        'title': 'Report Issue',
        'accentColor': const Color(0xFFEF4444),
      },
      {
        'key': 'events',
        'iconPath': 'assets/images/events.png',
        'title': 'Events',
        'accentColor': const Color(0xFF22C55E),
      },
      {
        'key': 'suggestion',
        'iconPath': 'assets/images/suggestions.png',
        'title': 'Suggestion',
        'accentColor': const Color(0xFF60A5FA),
      },
      {
        'key': 'feedback',
        'iconPath': 'assets/images/feedback.png',
        'title': 'Feedback',
        'accentColor': const Color(0xFF8B5CF6),
      },
      {
        'key': 'trends',
        'iconPath': 'assets/images/trends.png',
        'title': 'See Trends',
        'accentColor': const Color(0xFF06B6D4),
      },
    ];

    final cardWidth = _quickCardWidth(width);
    final gap = width * 0.02;
    final imageH = cardWidth * 0.68;
    final infoH = cardWidth * 0.58;
    final totalPageDots = (actions.length / 3).ceil();

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: width * 0.04),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(width * 0.03),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(width * 0.04),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Quick Action',
              style: TextStyle(
                color: AppColors.primaryBlue,
                fontSize: width * 0.047,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: width * 0.025),
            SizedBox(
              height: imageH + infoH,
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  final offset = notification.metrics.pixels;
                  final threshold = (_quickCardWidth(width) + width * 0.02) * 2;
                  final pageIndex = offset >= threshold ? 1 : 0;
                  if (_currentQuickDot != pageIndex) {
                    setState(() => _currentQuickDot = pageIndex);
                  }
                  return false;
                },
                child: ListView.builder(
                  controller: _quickScrollController,
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: actions.length,
                  itemBuilder: (context, index) {
                    final a = actions[index];
                    final accent = a['accentColor'] as Color;
                    final key = a['key'] as String;

                    return SizedBox(
                      width: cardWidth,
                      height: imageH + infoH,
                      child: Container(
                        margin: EdgeInsets.only(
                          right: index < actions.length - 1 ? gap : 0,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(width * 0.025),
                          border: Border.all(color: const Color(0xFFE5E7EB)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: .05),
                              blurRadius: 5,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(width * 0.025),
                          // ✅ GestureDetector now uses _handleQuickAction(key)
                          child: GestureDetector(
                            onTap: () => _handleQuickAction(key),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Container(
                                  width: cardWidth,
                                  height: imageH,
                                  color: accent.withValues(alpha: .12),
                                  child: Center(
                                    child: Container(
                                      width: cardWidth * 0.50,
                                      height: cardWidth * 0.50,
                                      decoration: BoxDecoration(
                                        color: accent.withValues(alpha: .18),
                                        borderRadius: BorderRadius.circular(
                                          cardWidth * 0.18,
                                        ),
                                      ),
                                      child: Center(
                                        child: Image.asset(
                                          a['iconPath'] as String,
                                          width: cardWidth * 0.32,
                                          height: cardWidth * 0.32,
                                          fit: BoxFit.contain,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Center(
                                    child: Padding(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: width * 0.018,
                                        vertical: width * 0.010,
                                      ),
                                      child: Text(
                                        a['title'] as String,
                                        textAlign: TextAlign.center,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: width * 0.030,
                                          fontWeight: FontWeight.w600,
                                          color: const Color(0xFF111827),
                                          height: 1.25,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            SizedBox(height: width * 0.022),
            _buildDots(width, totalPageDots, _currentQuickDot),
          ],
        ),
      ),
    );
  }

  // ── Quick action router ───────────────────────────────────────────────────
  void _handleQuickAction(String key) {
    switch (key) {
      case 'report':
        _goToReport();
        break;
      case 'chat':
        // TODO: navigate to chat screen
        break;
      case 'events':
        // TODO: navigate to events screen
        break;
      case 'suggestion':
        // TODO: navigate to suggestion screen
        break;
      case 'feedback':
        // TODO: navigate to feedback screen
        break;
      case 'trends':
        // TODO: navigate to trends screen
        break;
    }
  }

  // ── Bottom Navigation ─────────────────────────────────────────────────────
  Widget _buildBottomNav(double width) {
    final iconSize = width * 0.065;
    const activeColor = Color(0xFF60A5FA);
    const inactiveColor = Color(0xFF9CA3AF);

    Widget buildIcon(String path, bool isActive) {
      return SizedBox(
        width: iconSize,
        height: iconSize,
        child: ColorFiltered(
          colorFilter: ColorFilter.mode(
            isActive ? activeColor : inactiveColor,
            BlendMode.srcIn,
          ),
          child: Image.asset(path),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .06),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        elevation: 0,
        currentIndex: _navIndex,
        selectedItemColor: activeColor,
        unselectedItemColor: inactiveColor,
        selectedFontSize: width * 0.028,
        unselectedFontSize: width * 0.028,
        onTap: (index) {
          if (index == _navIndex) {
            return;
          } else if (index == 1) {
            if (_verifStatus != _VerifStatus.verified) {
              showVerificationRequiredDialog(
                context,
                message: 'Only verified citizens can access My Reports.',
              );
              return;
            }
            Navigator.pushNamed(
              context,
              '/my_reports',
              arguments: widget.username,
            );
          } else if (index == 2) {
            _goToNewsFeed();
          } else if (index == 3) {
            Navigator.pushNamed(
              context,
              '/emergency',
              arguments: {
                'username': widget.username,
                'isVerified': _verifStatus == _VerifStatus.verified,
              },
            );
          } else if (index == 4) {
            Navigator.pushNamed(
              context,
              '/settings',
              arguments: widget.username,
            );
          }
        },
        items: [
          BottomNavigationBarItem(
            icon: buildIcon('assets/images/home.png', _navIndex == 0),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: buildIcon('assets/images/my_reports.png', _navIndex == 1),
            label: 'My Reports',
          ),
          BottomNavigationBarItem(
            icon: buildIcon('assets/images/news_feed.png', _navIndex == 2),
            label: 'NewsFeed',
          ),
          BottomNavigationBarItem(
            icon: buildIcon('assets/images/emergency.png', _navIndex == 3),
            label: 'Emergency',
          ),
          BottomNavigationBarItem(
            icon: buildIcon('assets/images/settings.png', _navIndex == 4),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

// ── Rotating gradient ring around avatar ────────────────────────────────────
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

// ── Shimmer strip — "You're a verified Aparri citizen" ──────────────────────
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

// ── Shimmer "Verify Now" button ──────────────────────────────────────────────
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

// ── Pending button (unchanged) ───────────────────────────────────────────────
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

class _GreetingText extends StatefulWidget {
  final String text;
  final double width;
  const _GreetingText({required this.text, required this.width});

  @override
  State<_GreetingText> createState() => _GreetingTextState();
}

class _GreetingTextState extends State<_GreetingText> {
  String _displayed = '';
  int _charIndex = 0;
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    // Small delay so it starts after card appears
    Future.delayed(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      _timer = Timer.periodic(const Duration(milliseconds: 38), (t) {
        if (!mounted) {
          t.cancel();
          return;
        }
        if (_charIndex >= widget.text.length) {
          t.cancel();
          return;
        }
        setState(() {
          _charIndex++;
          _displayed = widget.text.substring(0, _charIndex);
        });
      });
    });
  }

  @override
  void dispose() {
    // Timer may not be initialized if widget disposed before delay fires
    try {
      _timer.cancel();
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _displayed,
      style: TextStyle(
        fontFamily: 'Poppins', // ← font here
        fontSize: widget.width * 0.038,
        fontWeight: FontWeight.w600, // bolder
        color: const Color(0xFF22C55E),
        letterSpacing: 0.2,
        height: 1.4,
      ),
    );
  }
}
