import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/theme/app_colors.dart';
import '../screen/home_screen.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import '../../../../core/network/network_wrapper.dart';
import '../../../../core/widgets/modal/verification_required_dialog.dart';
import 'dart:io';

// ─────────────────────────────────────────────────────────────────────────────
// Palette
// ─────────────────────────────────────────────────────────────────────────────
class _C {
  static const Color pageBg = Color(0xFFF6F7FB);
  static const Color surface = Colors.white;
  static const Color border = Color(0xFFE3E6EF);
  static const Color text2 = Color(0xFF1A1A2E);
  static const Color text3 = Color(0xFF4B5563);
  static const Color textHint = Color(0xFF8A8A8A);
  static const Color inputBg = Color(0xFFF6F7FB);
}

// ─────────────────────────────────────────────────────────────────────────────
// Models
// ─────────────────────────────────────────────────────────────────────────────
class _Hotline {
  final String name;
  final String number;
  final String? network;
  const _Hotline({required this.name, required this.number, this.network});
}

class _Category {
  final String label;
  final String iconPath;
  final Color color;
  final List<_Hotline> hotlines;
  const _Category({
    required this.label,
    required this.iconPath,
    required this.color,
    required this.hotlines,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Main Screen
// ─────────────────────────────────────────────────────────────────────────────
class EmergencyScreen extends StatefulWidget {
  final String username;
  final bool isVerified;

  const EmergencyScreen({
    super.key,
    required this.username,
    this.isVerified = false,
  });

  @override
  State<EmergencyScreen> createState() => _EmergencyScreenState();
}

class _EmergencyScreenState extends State<EmergencyScreen>
    with TickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseScale;
  late final Animation<double> _pulseOpacity;

  late final AnimationController _breatheCtrl;
  late final Animation<double> _breatheScale;
  late final Animation<double> _breatheGlow;

  late final AnimationController _entryCtrl;

  static const int _navIndex = 3;

  static const List<_Category> _categories = [
    _Category(
      label: 'Police',
      iconPath: 'assets/images/emergency/police.png',
      color: AppColors.primaryBlue,
      hotlines: [
        _Hotline(
          name: 'Aparri Police Station',
          number: '09172032003',
          network: 'Globe',
        ),
        _Hotline(
          name: "Mayor's Office — Municipal Hall",
          number: '09954316944',
          network: 'Globe',
        ),
      ],
    ),
    _Category(
      label: 'Fire Station',
      iconPath: 'assets/images/emergency/fire.png',
      color: AppColors.red,
      hotlines: [
        _Hotline(
          name: 'Aparri Fire Station (BFP)',
          number: '09164910946',
          network: 'Globe',
        ),
      ],
    ),
    _Category(
      label: 'Hospital',
      iconPath: 'assets/images/emergency/medical.png',
      color: AppColors.green,
      hotlines: [
        _Hotline(
          name: 'Aparri Provincial Hospital',
          number: '09363748430',
          network: 'Globe',
        ),
        _Hotline(
          name: 'Aparri Medicare Community Hospital',
          number: '09278710503',
          network: 'Globe',
        ),
        _Hotline(
          name: 'Aparri Christian Hospital, Inc.',
          number: '0788882447',
          network: 'Tel',
        ),
        _Hotline(
          name: 'Municipal Health Office (East)',
          number: '09531908364',
          network: 'Smart',
        ),
        _Hotline(
          name: 'Municipal Health Office (West)',
          number: '09951868014',
          network: 'Smart',
        ),
      ],
    ),
    _Category(
      label: 'MDRRMO',
      iconPath: 'assets/images/emergency/leader.png',
      color: AppColors.orange,
      hotlines: [
        _Hotline(
          name: 'MDRRMO Aparri East (Rescue 511)',
          number: '09972404984',
          network: 'Smart',
        ),
        _Hotline(
          name: 'MDRRMO Aparri West',
          number: '09655845600',
          network: 'Globe',
        ),
        _Hotline(
          name: 'Provincial DRRMO Cagayan',
          number: '09271819424',
          network: 'Globe',
        ),
        _Hotline(
          name: 'Provincial DRRMO Cagayan (2)',
          number: '09754348083',
          network: 'Globe',
        ),
      ],
    ),
    _Category(
      label: 'National',
      iconPath: 'assets/images/emergency/philippines.png',
      color: AppColors.primaryBlue,
      hotlines: [
        _Hotline(name: 'Philippine Red Cross', number: '143'),
        _Hotline(name: 'Philippine Coast Guard', number: '5278481'),
        _Hotline(name: 'NDRRMC Operations Center', number: '02-91117600'),
      ],
    ),
  ];

  @override
  void initState() {
    super.initState();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: false);

    _pulseScale = Tween<double>(
      begin: 0.85,
      end: 1.6,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeOut));
    _pulseOpacity = Tween<double>(
      begin: 0.55,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeOut));

    _breatheCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _breatheScale = Tween<double>(
      begin: 0.93,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _breatheCtrl, curve: Curves.easeInOut));
    _breatheGlow = Tween<double>(
      begin: 6.0,
      end: 22.0,
    ).animate(CurvedAnimation(parent: _breatheCtrl, curve: Curves.easeInOut));

    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted) _entryCtrl.forward();
      });
    });
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _breatheCtrl.dispose();
    _entryCtrl.dispose();
    super.dispose();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  String _fmt(String raw) {
    if (raw == '911' || raw == '143') return raw;
    if (raw.startsWith('09') && raw.length == 11) {
      return '${raw.substring(0, 4)}-${raw.substring(4, 7)}-${raw.substring(7)}';
    }
    if (raw.startsWith('07') && raw.length == 10) {
      return '(${raw.substring(0, 3)}) ${raw.substring(3, 6)}-${raw.substring(6)}';
    }
    return raw;
  }

  Color _netColor(String? n) {
    switch (n?.toLowerCase()) {
      case 'smart':
        return AppColors.green;
      case 'globe':
        return AppColors.primaryBlue;
      case 'tnt':
        return AppColors.orange;
      default:
        return _C.textHint;
    }
  }

  Future<void> _call(String number) async {
    if (Platform.isAndroid) {
      final isEmergency = number == '911' || number == '112';
      if (isEmergency) {
        // Best possible for emergency — pre-fills dialer, one tap to call
        await AndroidIntent(
          action: 'android.intent.action.DIAL',
          data: 'tel:$number',
          flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
        ).launch();
        return;
      }

      // Non-emergency — direct call (already working, unchanged)
      final status = await Permission.phone.request();
      if (status.isGranted) {
        try {
          await AndroidIntent(
            action: 'android.intent.action.CALL',
            data: 'tel:$number',
            flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
          ).launch();
        } catch (_) {
          await AndroidIntent(
            action: 'android.intent.action.DIAL',
            data: 'tel:$number',
            flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
          ).launch();
        }
      } else if (mounted) {
        await AndroidIntent(
          action: 'android.intent.action.DIAL',
          data: 'tel:$number',
          flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
        ).launch();
      }
    } else {
      final uri = Uri(scheme: 'tel', path: number);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
  }

  void _copyNumber(String number) {
    Clipboard.setData(ClipboardData(text: number));
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(
                Icons.check_circle_rounded,
                color: Colors.white,
                size: 18,
              ),
              const SizedBox(width: 10),
              Text('$number copied to clipboard'),
            ],
          ),
          backgroundColor: AppColors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  void _openCategory(_Category cat) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 320),
      transitionBuilder: (ctx, anim, _, child) {
        final curve = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curve,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.08),
              end: Offset.zero,
            ).animate(curve),
            child: child,
          ),
        );
      },
      pageBuilder: (ctx, _, _) => _CategoryModal(
        category: cat,
        formatNumber: _fmt,
        networkColor: _netColor,
        onCall: (number) {
          Navigator.pop(ctx);
          Future.delayed(
            const Duration(milliseconds: 250),
            () => _call(number),
          );
        },
        onCopy: (number) {
          Navigator.pop(ctx);
          _copyNumber(number);
        },
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final scaffold = Scaffold(
      backgroundColor: _C.pageBg,
      body: SafeArea(
        child: Column(
          children: [
            _topBar(w),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  w * .04,
                  w * .04,
                  w * .04,
                  w * .08,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _hero911Card(w), // ← original sizes
                    SizedBox(height: w * .055),
                    _sectionLabel(w, 'Emergency Services'), // ← original
                    SizedBox(height: w * .032),
                    _categoryGrid(w), // ← bigger sizes only here
                    SizedBox(height: w * .04),
                    _disclaimer(w), // ← original sizes
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: widget.username.isEmpty ? null : _bottomNav(w),
    );

    if (widget.username.isEmpty) return scaffold;
    return NetworkWrapper(child: scaffold);
  }

  // ── Top bar — ORIGINAL sizes ──────────────────────────────────────────────
  Widget _topBar(double w) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(w * .05, w * .038, w * .05, w * .038),
      decoration: BoxDecoration(
        color: _C.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            'assets/images/newslogo.png',
            height: w * .075,
            fit: BoxFit.contain,
            alignment: Alignment.centerLeft,
            errorBuilder: (_, _, _) => Icon(
              Icons.account_balance_rounded,
              size: w * .065,
              color: AppColors.primaryBlue,
            ),
          ),
          SizedBox(height: w * .018),
          Text(
            'Emergency',
            style: TextStyle(
              fontSize: w * .058,
              fontWeight: FontWeight.w900,
              color: AppColors.primaryBlue,
              letterSpacing: -.8,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Aparri, Cagayan — Official Hotlines',
            style: TextStyle(fontSize: w * .030, color: _C.textHint),
          ),
        ],
      ),
    );
  }

  // ── 911 Hero Card — ORIGINAL sizes ───────────────────────────────────────
  Widget _hero911Card(double w) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFE53935), Color(0xFFB71C1C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(w * .048),
        boxShadow: [
          BoxShadow(
            color: AppColors.red.withValues(alpha: .45),
            blurRadius: 28,
            offset: const Offset(0, 10),
            spreadRadius: -6,
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -w * .06,
            top: -w * .06,
            child: Container(
              width: w * .44,
              height: w * .44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: .05),
              ),
            ),
          ),
          Positioned(
            left: -w * .04,
            bottom: -w * .04,
            child: Container(
              width: w * .28,
              height: w * .28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: .04),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(w * .05),
            child: Column(
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: w * .26,
                      height: w * .26,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          AnimatedBuilder(
                            animation: _pulseCtrl,
                            builder: (_, _) => Transform.scale(
                              scale: _pulseScale.value,
                              child: Container(
                                width: w * .18,
                                height: w * .18,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white.withValues(
                                      alpha: _pulseOpacity.value * .6,
                                    ),
                                    width: 1.5,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          AnimatedBuilder(
                            animation: _pulseCtrl,
                            builder: (_, _) {
                              final t = (_pulseCtrl.value + 0.5) % 1.0;
                              final scale = 0.85 + t * 0.75;
                              final opacity = (0.55 * (1.0 - t)).clamp(
                                0.0,
                                1.0,
                              );
                              return Transform.scale(
                                scale: scale,
                                child: Container(
                                  width: w * .18,
                                  height: w * .18,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.white.withValues(
                                      alpha: opacity * 0.12,
                                    ),
                                    border: Border.all(
                                      color: Colors.white.withValues(
                                        alpha: opacity * 0.4,
                                      ),
                                      width: 1.2,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                          AnimatedBuilder(
                            animation: _breatheCtrl,
                            builder: (_, child) => Transform.scale(
                              scale: _breatheScale.value,
                              child: Container(
                                width: w * .17,
                                height: w * .17,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.white.withValues(
                                        alpha: .45,
                                      ),
                                      blurRadius: _breatheGlow.value,
                                      spreadRadius: _breatheGlow.value * 0.3,
                                    ),
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: .22,
                                      ),
                                      blurRadius: 14,
                                      offset: const Offset(0, 5),
                                    ),
                                  ],
                                ),
                                child: child,
                              ),
                            ),
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '911',
                                    style: TextStyle(
                                      fontSize: w * .046,
                                      fontWeight: FontWeight.w900,
                                      color: AppColors.red,
                                      letterSpacing: -1.5,
                                      height: 1.0,
                                    ),
                                  ),
                                  Text(
                                    'CALL',
                                    style: TextStyle(
                                      fontSize: w * .018,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.red.withValues(
                                        alpha: .6,
                                      ),
                                      letterSpacing: 1.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: w * .024),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'National\nEmergency Hotline',
                            style: TextStyle(
                              fontSize: w * .042,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              height: 1.15,
                              letterSpacing: -.5,
                            ),
                          ),
                          SizedBox(height: w * .014),
                          Wrap(
                            spacing: w * .015,
                            children: [
                              _pill(Icons.local_police_rounded, 'Police'),
                              _pill(
                                Icons.local_fire_department_rounded,
                                'Fire',
                              ),
                              _pill(Icons.local_hospital_rounded, 'Medical'),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: w * .042),
                _Slider911(onTriggered: () => _call('911')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ORIGINAL pill
  Widget _pill(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: .3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: Colors.white.withValues(alpha: .9)),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Colors.white.withValues(alpha: .9),
            ),
          ),
        ],
      ),
    );
  }

  // ORIGINAL section label
  Widget _sectionLabel(double w, String text) {
    return Row(
      children: [
        Container(
          width: 4,
          height: w * .046,
          decoration: BoxDecoration(
            color: AppColors.primaryBlue,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        SizedBox(width: w * .025),
        Text(
          text,
          style: TextStyle(
            fontSize: w * .044,
            fontWeight: FontWeight.w800,
            color: _C.text2,
            letterSpacing: -.3,
          ),
        ),
      ],
    );
  }

  // ── Category Grid — BIGGER sizes only here ────────────────────────────────
  Widget _categoryGrid(double w) {
    // Uniform icon box size for all cards
    final double iconBoxSize = w * .14;

    Animation<double> fade(int i) => Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _entryCtrl,
        curve: Interval(
          (i * .12).clamp(0.0, 1.0),
          ((i * .12) + .5).clamp(0.0, 1.0),
          curve: Curves.easeOut,
        ),
      ),
    );
    Animation<Offset> slide(int i) =>
        Tween<Offset>(begin: const Offset(0, .3), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _entryCtrl,
            curve: Interval(
              (i * .12).clamp(0.0, 1.0),
              ((i * .12) + .5).clamp(0.0, 1.0),
              curve: Curves.easeOutCubic,
            ),
          ),
        );
    Widget animated(int i, Widget child) => FadeTransition(
      opacity: fade(i),
      child: SlideTransition(position: slide(i), child: child),
    );

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: animated(
                0,
                _CatCard(
                  cat: _categories[0],
                  iconBoxSize: iconBoxSize,
                  onTap: () => _openCategory(_categories[0]),
                ),
              ),
            ),
            SizedBox(width: w * .032),
            Expanded(
              child: animated(
                1,
                _CatCard(
                  cat: _categories[1],
                  iconBoxSize: iconBoxSize,
                  onTap: () => _openCategory(_categories[1]),
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: w * .032),
        Row(
          children: [
            Expanded(
              child: animated(
                2,
                _CatCard(
                  cat: _categories[2],
                  iconBoxSize: iconBoxSize,
                  onTap: () => _openCategory(_categories[2]),
                ),
              ),
            ),
            SizedBox(width: w * .032),
            Expanded(
              child: animated(
                3,
                _CatCard(
                  cat: _categories[3],
                  iconBoxSize: iconBoxSize,
                  onTap: () => _openCategory(_categories[3]),
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: w * .032),
        animated(
          4,
          _CatCardWide(
            cat: _categories[4],
            iconBoxSize: iconBoxSize,
            onTap: () => _openCategory(_categories[4]),
          ),
        ),
      ],
    );
  }

  // ORIGINAL disclaimer
  Widget _disclaimer(double w) {
    return Container(
      padding: EdgeInsets.all(w * .04),
      decoration: BoxDecoration(
        color: AppColors.orange.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(w * .034),
        border: Border.all(color: AppColors.orange.withValues(alpha: .28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            color: AppColors.orange,
            size: w * .045,
          ),
          SizedBox(width: w * .024),
          Expanded(
            child: Text(
              'These hotlines are for Aparri, Cagayan official use. '
              'In a life-threatening emergency, call 911 immediately.',
              style: TextStyle(
                fontSize: w * .029,
                color: _C.text3,
                height: 1.55,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomNav(double w) {
    final sz = w * .065;
    Widget ico(String path, bool active) => SizedBox(
      width: sz,
      height: sz,
      child: ColorFiltered(
        colorFilter: ColorFilter.mode(
          active ? AppColors.primaryBlue : const Color(0xFF9CA3AF),
          BlendMode.srcIn,
        ),
        child: Image.asset(path),
      ),
    );

    return Container(
      decoration: BoxDecoration(
        color: _C.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .07),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        elevation: 0,
        currentIndex: _navIndex,
        selectedItemColor: AppColors.primaryBlue,
        unselectedItemColor: const Color(0xFF9CA3AF),
        selectedFontSize: w * .028,
        unselectedFontSize: w * .028,
        onTap: (i) {
          if (i == _navIndex) return;
          if (i == 0) {
            Navigator.pushAndRemoveUntil(
              context,
              PageRouteBuilder(
                transitionDuration: const Duration(milliseconds: 400),
                pageBuilder: (_, _, _) =>
                    NetworkWrapper(child: HomePage(username: widget.username)),
                transitionsBuilder: (_, anim, _, child) => SlideTransition(
                  position: Tween(begin: const Offset(-1, 0), end: Offset.zero)
                      .animate(
                        CurvedAnimation(parent: anim, curve: Curves.easeInOut),
                      ),
                  child: child,
                ),
              ),
              (r) => false,
            );
          } else if (i == 1) {
            if (!widget.isVerified) {
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
          } else if (i == 2) {
            Navigator.pushNamed(
              context,
              '/newsfeed',
              arguments: {
                'username': widget.username,
                'isVerified': widget.isVerified,
              },
            );
          } else if (i == 4) {
            Navigator.pushNamed(
              context,
              '/settings',
              arguments: widget.username,
            );
          }
        },
        items: [
          BottomNavigationBarItem(
            icon: ico('assets/images/home.png', _navIndex == 0),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: ico('assets/images/my_reports.png', _navIndex == 1),
            label: 'My Reports',
          ),
          BottomNavigationBarItem(
            icon: ico('assets/images/news_feed.png', _navIndex == 2),
            label: 'NewsFeed',
          ),
          BottomNavigationBarItem(
            icon: ico('assets/images/emergency.png', _navIndex == 3),
            label: 'Emergency',
          ),
          BottomNavigationBarItem(
            icon: ico('assets/images/settings.png', _navIndex == 4),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 911 Slider — ORIGINAL sizes
// ─────────────────────────────────────────────────────────────────────────────
class _Slider911 extends StatefulWidget {
  final VoidCallback onTriggered;
  const _Slider911({required this.onTriggered});

  @override
  State<_Slider911> createState() => _Slider911State();
}

class _Slider911State extends State<_Slider911>
    with SingleTickerProviderStateMixin {
  double _thumbOffset = 0.0;
  bool _triggered = false;
  double _trackWidth = 0.0;

  static const double _thumbSize = 56.0;
  static const double _padding = 5.0;
  static const double _threshold = 0.90;

  double get _maxOffset =>
      (_trackWidth - _thumbSize - _padding * 2).clamp(0.0, double.infinity);
  double get _progress =>
      _maxOffset <= 0 ? 0.0 : (_thumbOffset / _maxOffset).clamp(0.0, 1.0);

  late final AnimationController _snapCtrl;
  late Animation<double> _snapAnim;

  @override
  void initState() {
    super.initState();
    _snapCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
  }

  @override
  void dispose() {
    _snapCtrl.dispose();
    super.dispose();
  }

  void _onDragStart(DragStartDetails d) {
    if (_triggered) return;
    _snapCtrl.stop();
    _snapCtrl.reset();
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (_triggered || _maxOffset <= 0) return;
    final next = (_thumbOffset + d.delta.dx).clamp(0.0, _maxOffset);
    setState(() => _thumbOffset = next);
    if (_progress >= _threshold) {
      _triggered = true;
      HapticFeedback.heavyImpact();
      setState(() => _thumbOffset = _maxOffset);
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) widget.onTriggered();
      });
      Future.delayed(const Duration(milliseconds: 900), () {
        if (mounted) {
          setState(() {
            _triggered = false;
            _thumbOffset = 0.0;
          });
        }
      });
    }
  }

  void _onDragEnd(DragEndDetails d) {
    if (_triggered) return;
    final startVal = _thumbOffset;
    _snapAnim = Tween<double>(
      begin: startVal,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _snapCtrl, curve: Curves.elasticOut));
    _snapAnim.addListener(() {
      if (mounted) {
        setState(() => _thumbOffset = _snapAnim.value.clamp(0.0, _maxOffset));
      }
    });
    _snapCtrl.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final bool done = _triggered;
    return LayoutBuilder(
      builder: (_, constraints) {
        _trackWidth = constraints.maxWidth;
        return GestureDetector(
          onHorizontalDragStart: _onDragStart,
          onHorizontalDragUpdate: _onDragUpdate,
          onHorizontalDragEnd: _onDragEnd,
          child: Container(
            height: 66,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .15),
              borderRadius: BorderRadius.circular(33),
              border: Border.all(
                color: Colors.white.withValues(alpha: .35),
                width: 1.5,
              ),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(33),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: (_thumbOffset + _thumbSize + _padding * 2).clamp(
                          0.0,
                          _trackWidth,
                        ),
                        decoration: BoxDecoration(
                          color: done
                              ? Colors.white.withValues(alpha: .30)
                              : Colors.white.withValues(alpha: .13),
                          borderRadius: BorderRadius.circular(33),
                        ),
                      ),
                    ),
                  ),
                ),
                Center(
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 160),
                    opacity: done
                        ? 0.0
                        : (1.0 - (_progress * 2.2)).clamp(0.0, 1.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.keyboard_double_arrow_right_rounded,
                          size: 20,
                          color: Colors.white.withValues(alpha: .55),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Slide to Call 911',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Colors.white.withValues(alpha: .95),
                            letterSpacing: .4,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          Icons.keyboard_double_arrow_right_rounded,
                          size: 20,
                          color: Colors.white.withValues(alpha: .30),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: _padding + _thumbOffset,
                  top: _padding,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 80),
                    width: _thumbSize,
                    height: _thumbSize,
                    decoration: BoxDecoration(
                      color: done ? AppColors.green : Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: (done ? AppColors.green : Colors.black)
                              .withValues(alpha: .28),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Icon(
                      done ? Icons.check_rounded : Icons.phone_rounded,
                      color: done ? Colors.white : AppColors.red,
                      size: 24,
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
}

// ─────────────────────────────────────────────────────────────────────────────
// Category Card — half-width  ← BIGGER fonts & sizes
// ─────────────────────────────────────────────────────────────────────────────
class _CatCard extends StatefulWidget {
  final _Category cat;
  final double iconBoxSize;
  final VoidCallback onTap;
  const _CatCard({
    required this.cat,
    required this.iconBoxSize,
    required this.onTap,
  });

  @override
  State<_CatCard> createState() => _CatCardState();
}

class _CatCardState extends State<_CatCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 140),
    );
    _scale = Tween<double>(
      begin: 1.0,
      end: .95,
    ).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final cat = widget.cat;
    final box = widget.iconBoxSize; // uniform for all cards

    return GestureDetector(
      onTapDown: (_) {
        HapticFeedback.selectionClick();
        _c.forward();
      },
      onTapUp: (_) {
        _c.reverse();
        widget.onTap();
      },
      onTapCancel: () => _c.reverse(),
      child: AnimatedBuilder(
        animation: _scale,
        builder: (_, child) =>
            Transform.scale(scale: _scale.value, child: child),
        child: Container(
          padding: EdgeInsets.all(w * .046), // bigger padding
          decoration: BoxDecoration(
            color: _C.surface,
            borderRadius: BorderRadius.circular(w * .046),
            border: Border.all(color: _C.border),
            boxShadow: [
              BoxShadow(
                color: cat.color.withValues(alpha: .10),
                blurRadius: 16,
                offset: const Offset(0, 5),
                spreadRadius: -3,
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: .04),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // ── Uniform PNG icon ──────────────────────────────────
                  Container(
                    width: box,
                    height: box,
                    decoration: BoxDecoration(
                      color: cat.color.withValues(alpha: .10),
                      borderRadius: BorderRadius.circular(w * .030),
                      border: Border.all(
                        color: cat.color.withValues(alpha: .22),
                        width: 1.2,
                      ),
                    ),
                    child: Center(
                      child: ColorFiltered(
                        colorFilter: ColorFilter.mode(
                          cat.color,
                          BlendMode.srcIn,
                        ),
                        child: Image.asset(
                          cat.iconPath,
                          width: box * .58,
                          height: box * .58,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                  // ── Count badge ───────────────────────────────────────
                  Container(
                    width: w * .080,
                    height: w * .080,
                    decoration: BoxDecoration(
                      color: cat.color.withValues(alpha: .1),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '${cat.hotlines.length}',
                        style: TextStyle(
                          fontSize: w * .036,
                          fontWeight: FontWeight.w900,
                          color: cat.color,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: w * .034),
              Text(
                cat.label, // bigger font
                style: TextStyle(
                  fontSize: w * .042,
                  fontWeight: FontWeight.w800,
                  color: _C.text2,
                  letterSpacing: -.3,
                ),
              ),
              SizedBox(height: w * .008),
              Row(
                children: [
                  Text(
                    'View hotlines', // bigger font
                    style: TextStyle(
                      fontSize: w * .030,
                      color: cat.color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(width: w * .008),
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: w * .030,
                    color: cat.color,
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

// ─────────────────────────────────────────────────────────────────────────────
// Category Card — full-width (National)  ← BIGGER fonts & sizes
// ─────────────────────────────────────────────────────────────────────────────
class _CatCardWide extends StatefulWidget {
  final _Category cat;
  final double iconBoxSize;
  final VoidCallback onTap;
  const _CatCardWide({
    required this.cat,
    required this.iconBoxSize,
    required this.onTap,
  });

  @override
  State<_CatCardWide> createState() => _CatCardWideState();
}

class _CatCardWideState extends State<_CatCardWide>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 140),
    );
    _scale = Tween<double>(
      begin: 1.0,
      end: .97,
    ).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final cat = widget.cat;
    final box = widget.iconBoxSize;

    return GestureDetector(
      onTapDown: (_) {
        HapticFeedback.selectionClick();
        _c.forward();
      },
      onTapUp: (_) {
        _c.reverse();
        widget.onTap();
      },
      onTapCancel: () => _c.reverse(),
      child: AnimatedBuilder(
        animation: _scale,
        builder: (_, child) =>
            Transform.scale(scale: _scale.value, child: child),
        child: Container(
          padding: EdgeInsets.all(w * .046),
          decoration: BoxDecoration(
            color: _C.surface,
            borderRadius: BorderRadius.circular(w * .046),
            border: Border.all(color: _C.border),
            boxShadow: [
              BoxShadow(
                color: cat.color.withValues(alpha: .1),
                blurRadius: 16,
                offset: const Offset(0, 5),
                spreadRadius: -3,
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: .04),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              // ── Uniform PNG icon ────────────────────────────────────────
              Container(
                width: box,
                height: box,
                decoration: BoxDecoration(
                  color: cat.color.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(w * .032),
                  border: Border.all(
                    color: cat.color.withValues(alpha: .22),
                    width: 1.2,
                  ),
                ),
                child: Center(
                  child: ColorFiltered(
                    colorFilter: ColorFilter.mode(cat.color, BlendMode.srcIn),
                    child: Image.asset(
                      cat.iconPath,
                      width: box * .58,
                      height: box * .58,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
              SizedBox(width: w * .038),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cat.label,
                      style: TextStyle(
                        fontSize: w * .042,
                        fontWeight: FontWeight.w800,
                        color: _C.text2,
                        letterSpacing: -.3,
                      ),
                    ),
                    SizedBox(height: w * .005),
                    Text(
                      '${cat.hotlines.length} national hotlines',
                      style: TextStyle(fontSize: w * .031, color: _C.textHint),
                    ),
                  ],
                ),
              ),
              Container(
                padding: EdgeInsets.all(w * .024),
                decoration: BoxDecoration(
                  color: cat.color.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(w * .024),
                ),
                child: Icon(
                  Icons.chevron_right_rounded,
                  color: cat.color,
                  size: w * .052,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Category Modal  ← BIGGER fonts & sizes
// ─────────────────────────────────────────────────────────────────────────────
class _CategoryModal extends StatelessWidget {
  final _Category category;
  final String Function(String) formatNumber;
  final Color Function(String?) networkColor;
  final void Function(String) onCall;
  final void Function(String) onCopy;

  const _CategoryModal({
    required this.category,
    required this.formatNumber,
    required this.networkColor,
    required this.onCall,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final cat = category;
    final box = w * .14;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: w * .045,
        vertical: w * .08,
      ),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * .80,
        ),
        decoration: BoxDecoration(
          color: _C.surface,
          borderRadius: BorderRadius.circular(w * .058),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .15),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ────────────────────────────────────────────────────
            Container(
              padding: EdgeInsets.fromLTRB(
                w * .052,
                w * .050,
                w * .042,
                w * .034,
              ),
              decoration: BoxDecoration(
                color: cat.color.withValues(alpha: .05),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(w * .058),
                  topRight: Radius.circular(w * .058),
                ),
                border: Border(bottom: BorderSide(color: _C.border)),
              ),
              child: Row(
                children: [
                  Container(
                    width: box,
                    height: box,
                    decoration: BoxDecoration(
                      color: cat.color.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(w * .032),
                      border: Border.all(
                        color: cat.color.withValues(alpha: .25),
                        width: 1.5,
                      ),
                    ),
                    child: Center(
                      child: ColorFiltered(
                        colorFilter: ColorFilter.mode(
                          cat.color,
                          BlendMode.srcIn,
                        ),
                        child: Image.asset(
                          cat.iconPath,
                          width: box * .58,
                          height: box * .58,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: w * .034),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          cat.label,
                          style: TextStyle(
                            fontSize: w * .050,
                            fontWeight: FontWeight.w800,
                            color: _C.text2,
                            letterSpacing: -.3,
                          ),
                        ),
                        Text(
                          '${cat.hotlines.length} available hotlines',
                          style: TextStyle(
                            fontSize: w * .031,
                            color: _C.textHint,
                          ),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: EdgeInsets.all(w * .020),
                      decoration: BoxDecoration(
                        color: _C.inputBg,
                        shape: BoxShape.circle,
                        border: Border.all(color: _C.border),
                      ),
                      child: Icon(
                        Icons.close_rounded,
                        size: w * .048,
                        color: _C.textHint,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // ── Hotlines ──────────────────────────────────────────────────
            Flexible(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  w * .042,
                  w * .024,
                  w * .042,
                  w * .050,
                ),
                child: Column(
                  children: cat.hotlines
                      .asMap()
                      .entries
                      .map(
                        (e) => _HotlineRow(
                          hotline: e.value,
                          accentColor: cat.color,
                          formatNumber: formatNumber,
                          networkColor: networkColor,
                          onCall: onCall,
                          onCopy: onCopy,
                          index: e.key,
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hotline Row  ← BIGGER fonts & sizes
// ─────────────────────────────────────────────────────────────────────────────
class _HotlineRow extends StatefulWidget {
  final _Hotline hotline;
  final Color accentColor;
  final String Function(String) formatNumber;
  final Color Function(String?) networkColor;
  final void Function(String) onCall;
  final void Function(String) onCopy;
  final int index;

  const _HotlineRow({
    required this.hotline,
    required this.accentColor,
    required this.formatNumber,
    required this.networkColor,
    required this.onCall,
    required this.onCopy,
    required this.index,
  });

  @override
  State<_HotlineRow> createState() => _HotlineRowState();
}

class _HotlineRowState extends State<_HotlineRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _scale;
  bool _copyFlash = false;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 130),
    );
    _scale = Tween<double>(
      begin: 1.0,
      end: .97,
    ).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _handleCopy() async {
    setState(() => _copyFlash = true);
    HapticFeedback.lightImpact();
    widget.onCopy(widget.hotline.number);
    await Future.delayed(const Duration(milliseconds: 800));
    if (mounted) setState(() => _copyFlash = false);
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final h = widget.hotline;
    final col = widget.accentColor;

    return AnimatedBuilder(
      animation: _scale,
      builder: (_, child) => Transform.scale(scale: _scale.value, child: child),
      child: Container(
        margin: EdgeInsets.only(top: w * .028),
        decoration: BoxDecoration(
          color: _C.surface,
          borderRadius: BorderRadius.circular(w * .040),
          border: Border.all(color: _C.border),
          boxShadow: [
            BoxShadow(
              color: col.withValues(alpha: .06),
              blurRadius: 10,
              offset: const Offset(0, 3),
              spreadRadius: -2,
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(w * .040),
            onTapDown: (_) => _c.forward(),
            onTapUp: (_) => _c.reverse(),
            onTapCancel: () => _c.reverse(),
            splashColor: col.withValues(alpha: .06),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: w * .044,
                vertical: w * .040,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (h.network != null) ...[
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: w * .020,
                              vertical: w * .006,
                            ),
                            decoration: BoxDecoration(
                              color: widget
                                  .networkColor(h.network)
                                  .withValues(alpha: .1),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: widget
                                    .networkColor(h.network)
                                    .withValues(alpha: .25),
                              ),
                            ),
                            child: Text(
                              h.network!,
                              style: TextStyle(
                                fontSize: w * .026,
                                fontWeight: FontWeight.w700,
                                color: widget.networkColor(h.network),
                              ),
                            ),
                          ),
                          SizedBox(height: w * .010),
                        ],
                        Text(
                          h.name,
                          style: TextStyle(
                            fontSize: w * .036,
                            fontWeight: FontWeight.w600,
                            color: _C.text2,
                            height: 1.3,
                          ),
                        ),
                        SizedBox(height: w * .007),
                        Text(
                          widget.formatNumber(h.number),
                          style: TextStyle(
                            fontSize: w * .040,
                            fontWeight: FontWeight.w800,
                            color: col,
                            letterSpacing: .8,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: w * .028),
                  // ── Copy ──────────────────────────────────────────────────
                  GestureDetector(
                    onTap: _handleCopy,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: w * .112,
                      height: w * .112,
                      decoration: BoxDecoration(
                        color: _copyFlash
                            ? AppColors.green.withValues(alpha: .12)
                            : _C.inputBg,
                        borderRadius: BorderRadius.circular(w * .028),
                        border: Border.all(
                          color: _copyFlash
                              ? AppColors.green.withValues(alpha: .4)
                              : _C.border,
                          width: 1.5,
                        ),
                      ),
                      child: Icon(
                        _copyFlash ? Icons.check_rounded : Icons.copy_rounded,
                        size: w * .042,
                        color: _copyFlash ? AppColors.green : _C.textHint,
                      ),
                    ),
                  ),
                  SizedBox(width: w * .022),
                  // ── Call ──────────────────────────────────────────────────
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.mediumImpact();
                      widget.onCall(h.number);
                    },
                    child: Container(
                      width: w * .112,
                      height: w * .112,
                      decoration: BoxDecoration(
                        color: col,
                        borderRadius: BorderRadius.circular(w * .028),
                        boxShadow: [
                          BoxShadow(
                            color: col.withValues(alpha: .38),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.phone_rounded,
                        color: Colors.white,
                        size: w * .044,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
