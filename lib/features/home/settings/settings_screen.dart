import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../home/screen/home_screen.dart';
import '../../../core/network/network_wrapper.dart';
import '../../../core/widgets/modal/verification_required_dialog.dart';

class SettingScreen extends StatefulWidget {
  final String username;
  const SettingScreen({super.key, required this.username});
  @override
  State<SettingScreen> createState() => _SettingScreenState();
}

// ── Changed to TickerProviderStateMixin to support multiple AnimationControllers ──
class _SettingScreenState extends State<SettingScreen>
    with TickerProviderStateMixin {
  static const int _navIndex = 4;
  static const String _appVersion = '1.0.0';

  // ── Entry animation controller ────────────────────────────────────────────
  late final AnimationController _entryCtrl;

  // ── Profile state ─────────────────────────────────────────────────────────
  String? _facePhotoUrl;
  String? _fullName;
  String? _email;
  String _verifStatus = 'none';
  bool _profileLoading = true;

  // ── Toggle state ──────────────────────────────────────────────────────────
  bool _pushNotifications = true;
  bool _communityUpdates = true;
  bool _emergencyAlerts = true;
  bool _emailNotifications = false;
  String _language = 'English';

  @override
  void initState() {
    super.initState();
    _loadProfile();

    // ── Init entry animation ──────────────────────────────────────────────
    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 80), () {
        if (mounted) _entryCtrl.forward();
      });
    });
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    super.dispose();
  }

  // ── Staggered right-to-left entry animation helper ────────────────────────
  // Each section slides in from the right with a staggered delay (index * 0.08)
  Widget _animated(int i, Widget child) {
    final start = (i * 0.08).clamp(0.0, 1.0);
    final end = (start + 0.50).clamp(0.0, 1.0);

    final fade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entryCtrl,
        curve: Interval(start, end, curve: Curves.easeOut),
      ),
    );

    final slide =
        Tween<Offset>(
          begin: const Offset(0.30, 0.0), // ← starts from right
          end: Offset.zero,
        ).animate(
          CurvedAnimation(
            parent: _entryCtrl,
            curve: Interval(start, end, curve: Curves.easeOutCubic),
          ),
        );

    return FadeTransition(
      opacity: fade,
      child: SlideTransition(position: slide, child: child),
    );
  }

  // ── Load profile data from Supabase ───────────────────────────────────────
  Future<void> _loadProfile() async {
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;

      if (user == null) {
        if (mounted) setState(() => _profileLoading = false);
        return;
      }

      _email = user.email;

      // 1. Get verification status + fallback face photo
      final verifRow = await supabase
          .from('verification_submissions')
          .select('status, face_photo_path')
          .eq('user_id', user.id)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      final status = verifRow?['status'] as String? ?? 'none';

      // 2. If approved, prefer citizen_details for name + photo
      String? resolvedPhotoPath;
      String? fullName;

      if (status == 'approved') {
        final cd = await supabase
            .from('citizen_details')
            .select('first_name, last_name, profile_photo_path')
            .eq('user_id', user.id)
            .maybeSingle();

        if (cd != null) {
          final firstName = cd['first_name'] as String? ?? '';
          final lastName = cd['last_name'] as String? ?? '';
          fullName = '${firstName.trim()} ${lastName.trim()}'.trim();

          // Prefer updated profile photo, else fall back to face scan
          resolvedPhotoPath =
              (cd['profile_photo_path'] as String?)?.isNotEmpty == true
              ? cd['profile_photo_path'] as String
              : verifRow?['face_photo_path'] as String?;
        }
      } else {
        // Pending or None → get username from profiles
        try {
          final profileRes = await supabase
              .from('profiles')
              .select('username, email')
              .eq('user_id', user.id)
              .maybeSingle();

          if (profileRes != null) {
            fullName = profileRes['username'] as String?;
          }
        } catch (_) {}

        resolvedPhotoPath = verifRow?['face_photo_path'] as String?;
      }

      // 3. Resolve signed URL
      String? photoUrl;
      if (resolvedPhotoPath != null && resolvedPhotoPath.isNotEmpty) {
        try {
          photoUrl = await supabase.storage
              .from('verification-assets')
              .createSignedUrl(resolvedPhotoPath, 3600);
        } catch (_) {
          try {
            photoUrl = supabase.storage
                .from('verification-assets')
                .getPublicUrl(resolvedPhotoPath);
          } catch (_) {}
        }
      }

      if (mounted) {
        setState(() {
          _verifStatus = status;
          _facePhotoUrl = photoUrl;
          _fullName = (fullName?.isNotEmpty == true) ? fullName : null;
          _profileLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _profileLoading = false);
    }
  }

  // ── Status badge config ───────────────────────────────────────────────────
  ({String label, Color bg, Color border, Color dot, Color text})
  get _statusBadge {
    switch (_verifStatus) {
      case 'pending':
        return (
          label: 'Pending',
          bg: const Color(0xFFFFF7ED),
          border: AppColors.orange,
          dot: AppColors.orange,
          text: const Color(0xFFB45309),
        );
      case 'approved':
        return (
          label: 'Verified',
          bg: const Color(0xFFECFDF5),
          border: AppColors.green,
          dot: AppColors.green,
          text: const Color(0xFF15803D),
        );
      default:
        return (
          label: 'Not Verified',
          bg: const Color(0xFFFFF7ED),
          border: AppColors.orange,
          dot: AppColors.orange,
          text: const Color(0xFFB45309),
        );
    }
  }

  // ── Coming soon placeholder ───────────────────────────────────────────────
  void _comingSoon(String feature) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature is coming soon'),
        backgroundColor: AppColors.primaryBlue,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ── Logout flow ───────────────────────────────────────────────────────────
  Future<void> _confirmLogout() async {
    final width = MediaQuery.of(context).size.width;

    final shouldLogout = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(width * 0.045),
        ),
        child: Padding(
          padding: EdgeInsets.all(width * 0.055),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: width * 0.16,
                height: width * 0.16,
                decoration: BoxDecoration(
                  color: AppColors.red.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.logout_rounded,
                  size: width * 0.085,
                  color: AppColors.red,
                ),
              ),
              SizedBox(height: width * 0.04),
              Text(
                'Log Out?',
                style: TextStyle(
                  fontSize: width * 0.052,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1F2937),
                ),
              ),
              SizedBox(height: width * 0.022),
              Text(
                'You\'ll need to sign in again to access your account.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: width * 0.034,
                  color: const Color(0xFF6B7280),
                  height: 1.45,
                ),
              ),
              SizedBox(height: width * 0.055),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.stroke),
                        padding: EdgeInsets.symmetric(vertical: width * 0.035),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(width * 0.03),
                        ),
                      ),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          fontSize: width * 0.038,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF374151),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: width * 0.025),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.red,
                        elevation: 0,
                        padding: EdgeInsets.symmetric(vertical: width * 0.035),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(width * 0.03),
                        ),
                      ),
                      child: Text(
                        'Log Out',
                        style: TextStyle(
                          fontSize: width * 0.038,
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
        child: CircularProgressIndicator(color: AppColors.primaryBlue),
      ),
    );

    try {
      await Supabase.instance.client.auth.signOut();
      if (!mounted) return;
      Navigator.pop(context);
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Logout failed: $e'),
          backgroundColor: AppColors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ── Delete account ────────────────────────────────────────────────────────
  Future<void> _confirmDeleteAccount() async {
    final width = MediaQuery.of(context).size.width;

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(width * 0.04),
        ),
        title: Text(
          'Delete Account',
          style: TextStyle(
            fontSize: width * 0.05,
            fontWeight: FontWeight.w700,
            color: AppColors.red,
          ),
        ),
        content: Text(
          'This will permanently remove your account and all submissions. '
          'This action cannot be undone.\n\n'
          'Please contact support to proceed with account deletion.',
          style: TextStyle(
            fontSize: width * 0.034,
            color: const Color(0xFF374151),
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'OK',
              style: TextStyle(
                color: AppColors.primaryBlue,
                fontWeight: FontWeight.w700,
                fontSize: width * 0.038,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: SafeArea(
        child: Column(
          children: [
            // Header slides in first (index 0)
            _animated(0, _buildHeader(width)),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  width * 0.04,
                  width * 0.02,
                  width * 0.04,
                  width * 0.06,
                ),
                child: Column(
                  children: [
                    _animated(1, _buildProfileCard(width)),
                    SizedBox(height: width * 0.04),
                    _animated(2, _buildAccountSection(width)),
                    SizedBox(height: width * 0.04),
                    _animated(3, _buildNotificationsSection(width)),
                    SizedBox(height: width * 0.04),
                    _animated(4, _buildPreferencesSection(width)),
                    SizedBox(height: width * 0.04),
                    _animated(5, _buildPrivacySection(width)),
                    SizedBox(height: width * 0.04),
                    _animated(6, _buildSupportSection(width)),
                    SizedBox(height: width * 0.04),
                    _animated(7, _buildLegalSection(width)),
                    SizedBox(height: width * 0.04),
                    _animated(8, _buildAboutSection(width)),
                    SizedBox(height: width * 0.05),
                    _animated(9, _buildLogoutButton(width)),
                    SizedBox(height: width * 0.025),
                    _animated(10, _buildDeleteAccountButton(width)),
                    SizedBox(height: width * 0.04),
                    _animated(11, _buildFooter(width)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNav(width),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _buildHeader(double width) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        width * 0.04,
        width * 0.04,
        width * 0.04,
        width * 0.04,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
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
            height: width * 0.075,
            fit: BoxFit.contain,
            alignment: Alignment.centerLeft,
            errorBuilder: (_, _, _) => Icon(
              Icons.account_balance_rounded,
              size: width * 0.065,
              color: AppColors.primaryBlue,
            ),
          ),
          SizedBox(height: width * 0.018),
          Text(
            'Settings',
            style: TextStyle(
              fontSize: width * 0.058,
              fontWeight: FontWeight.w700,
              color: AppColors.primaryBlue,
              letterSpacing: -0.3,
            ),
          ),
        ],
      ),
    );
  }

  // ── Profile summary card ──────────────────────────────────────────────────
  Widget _buildProfileCard(double width) {
    final badge = _statusBadge;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(width * 0.04),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(width * 0.04),
        border: Border.all(color: AppColors.stroke),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: width * 0.16,
            height: width * 0.16,
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
          SizedBox(width: width * 0.035),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _fullName ?? widget.username,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: width * 0.045,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1F2937),
                  ),
                ),
                if (_email != null) ...[
                  SizedBox(height: width * 0.005),
                  Text(
                    _email!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: width * 0.030,
                      color: AppColors.hint,
                    ),
                  ),
                ],
                SizedBox(height: width * 0.012),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: width * 0.025,
                    vertical: width * 0.012,
                  ),
                  decoration: BoxDecoration(
                    color: badge.bg,
                    borderRadius: BorderRadius.circular(width * 0.03),
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
                        _profileLoading ? 'Loading...' : badge.label,
                        style: TextStyle(
                          fontSize: width * 0.028,
                          color: badge.text,
                          fontWeight: FontWeight.w600,
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
    );
  }

  Widget _buildAvatar(double width) {
    final size = width * 0.16;

    if (_profileLoading) {
      return Container(
        color: const Color(0xFFE5E7EB),
        child: const Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
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
        errorBuilder: (_, _, _) =>
            Image.asset('assets/images/profilenew.png', fit: BoxFit.cover),
      );
    }

    return Image.asset('assets/images/profilenew.png', fit: BoxFit.cover);
  }

  // ── Section card ──────────────────────────────────────────────────────────
  Widget _buildSectionCard({
    required String title,
    required List<Widget> children,
    required double width,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(left: width * 0.01, bottom: width * 0.02),
          child: Text(
            title,
            style: TextStyle(
              fontSize: width * 0.034,
              fontWeight: FontWeight.w700,
              color: AppColors.primaryBlue,
              letterSpacing: 0.3,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(width * 0.035),
            border: Border.all(color: AppColors.stroke),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  // ── Settings tile ─────────────────────────────────────────────────────────
  Widget _buildTile({
    required String imagePath,
    required Color iconBgColor,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
    required double width,
    bool showDivider = true,
    Widget? trailing,
  }) {
    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: width * 0.04,
                vertical: width * 0.034,
              ),
              child: Row(
                children: [
                  Container(
                    width: width * 0.095,
                    height: width * 0.095,
                    decoration: BoxDecoration(
                      color: iconBgColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(width * 0.022),
                      border: Border.all(
                        color: AppColors.primaryBlue.withValues(alpha: 0.25),
                        width: 1.2,
                      ),
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(width * 0.018),
                      child: ColorFiltered(
                        colorFilter: ColorFilter.mode(
                          iconBgColor,
                          BlendMode.srcIn,
                        ),
                        child: Image.asset(imagePath, fit: BoxFit.contain),
                      ),
                    ),
                  ),
                  SizedBox(width: width * 0.035),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: width * 0.038,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF1F2937),
                          ),
                        ),
                        if (subtitle != null) ...[
                          SizedBox(height: width * 0.005),
                          Text(
                            subtitle,
                            style: TextStyle(
                              fontSize: width * 0.030,
                              color: AppColors.hint,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  trailing ??
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: width * 0.035,
                        color: const Color(0xFF9CA3AF),
                      ),
                ],
              ),
            ),
          ),
        ),
        if (showDivider)
          Padding(
            padding: EdgeInsets.only(left: width * 0.165),
            child: const Divider(height: 1, color: AppColors.stroke),
          ),
      ],
    );
  }

  // ── Toggle tile ───────────────────────────────────────────────────────────
  Widget _buildToggleTile({
    required String imagePath,
    required Color iconBgColor,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required double width,
    bool showDivider = true,
  }) {
    return _buildTile(
      imagePath: imagePath,
      iconBgColor: iconBgColor,
      title: title,
      subtitle: subtitle,
      width: width,
      showDivider: showDivider,
      onTap: () => onChanged(!value),
      trailing: Switch.adaptive(
        value: value,
        onChanged: onChanged,
        activeTrackColor: AppColors.green,
      ),
    );
  }

  // ── Account section ───────────────────────────────────────────────────────
  Widget _buildAccountSection(double width) {
    return _buildSectionCard(
      title: 'ACCOUNT',
      width: width,
      children: [
        _buildTile(
          imagePath: 'assets/images/settings/user.png',
          iconBgColor: AppColors.primaryBlue,
          title: 'Edit Profile',
          subtitle: 'Update your personal information',
          width: width,
          onTap: () async {
            if (_verifStatus != 'approved') {
              await showVerificationRequiredDialog(
                context,
                message:
                    'Only verified citizens can edit their profile information. Please complete the identity verification process first.',
              );
              return;
            }

            // ── Verified → go to Edit Profile ──────────────────────────
            final refreshed = await Navigator.pushNamed(
              context,
              '/edit_profile',
              arguments: widget.username,
            );
            if (refreshed == true && mounted) {
              setState(() => _profileLoading = true);
              _loadProfile();
            }
          },
        ),
        _buildTile(
          imagePath: 'assets/images/settings/password.png',
          iconBgColor: AppColors.primaryBlue,
          title: 'Change Password',
          width: width,
          onTap: () => _comingSoon('Change Password'),
        ),
        _buildTile(
          imagePath: 'assets/images/settings/submission.png',
          iconBgColor: AppColors.primaryBlue,
          title: 'My Submissions',
          subtitle: 'View your verification & report history',
          width: width,
          onTap: () => _comingSoon('My Submissions'),
        ),
        _buildTile(
          imagePath: 'assets/images/settings/verification_status.png',
          iconBgColor: AppColors.green,
          title: 'Verification Status',
          subtitle: _statusBadge.label,
          width: width,
          showDivider: false,
          onTap: () => _comingSoon('Verification Details'),
        ),
      ],
    );
  }

  // ── Notifications section ─────────────────────────────────────────────────
  Widget _buildNotificationsSection(double width) {
    return _buildSectionCard(
      title: 'NOTIFICATIONS',
      width: width,
      children: [
        _buildToggleTile(
          imagePath: 'assets/images/settings/notification.png',
          iconBgColor: AppColors.primaryBlue,
          title: 'Push Notifications',
          subtitle: 'Receive alerts on this device',
          value: _pushNotifications,
          onChanged: (v) => setState(() => _pushNotifications = v),
          width: width,
        ),
        _buildToggleTile(
          imagePath: 'assets/images/settings/updates.png',
          iconBgColor: AppColors.green,
          title: 'Community Updates',
          subtitle: 'Local news and announcements',
          value: _communityUpdates,
          onChanged: (v) => setState(() => _communityUpdates = v),
          width: width,
        ),
        _buildToggleTile(
          imagePath: 'assets/images/settings/emergency.png',
          iconBgColor: AppColors.red,
          title: 'Emergency Alerts',
          subtitle: 'Critical safety notifications',
          value: _emergencyAlerts,
          onChanged: (v) => setState(() => _emergencyAlerts = v),
          width: width,
        ),
        _buildToggleTile(
          imagePath: 'assets/images/settings/email.png',
          iconBgColor: AppColors.orange,
          title: 'Email Notifications',
          value: _emailNotifications,
          onChanged: (v) => setState(() => _emailNotifications = v),
          width: width,
          showDivider: false,
        ),
      ],
    );
  }

  // ── Preferences section ───────────────────────────────────────────────────
  Widget _buildPreferencesSection(double width) {
    return _buildSectionCard(
      title: 'PREFERENCES',
      width: width,
      children: [
        _buildTile(
          imagePath: 'assets/images/settings/language.png',
          iconBgColor: AppColors.primaryBlue,
          title: 'Language',
          width: width,
          onTap: () => _showLanguagePicker(width),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _language,
                style: TextStyle(
                  fontSize: width * 0.034,
                  color: AppColors.hint,
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(width: width * 0.015),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: width * 0.035,
                color: const Color(0xFF9CA3AF),
              ),
            ],
          ),
        ),
        _buildTile(
          imagePath: 'assets/images/settings/location.png',
          iconBgColor: AppColors.green,
          title: 'Location',
          subtitle: 'Aparri, Cagayan',
          width: width,
          showDivider: false,
          onTap: () => _comingSoon('Location Settings'),
        ),
      ],
    );
  }

  void _showLanguagePicker(double width) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(width * 0.05)),
      ),
      builder: (ctx) {
        final langs = ['English', 'Filipino', 'Ilocano'];
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: width * 0.03),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: width * 0.12,
                  height: width * 0.012,
                  decoration: BoxDecoration(
                    color: AppColors.stroke,
                    borderRadius: BorderRadius.circular(width * 0.01),
                  ),
                ),
                SizedBox(height: width * 0.04),
                Text(
                  'Choose Language',
                  style: TextStyle(
                    fontSize: width * 0.045,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryBlue,
                  ),
                ),
                SizedBox(height: width * 0.03),
                ...langs.map(
                  (l) => ListTile(
                    title: Text(
                      l,
                      style: TextStyle(
                        fontSize: width * 0.038,
                        fontWeight: _language == l
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: _language == l
                            ? AppColors.primaryBlue
                            : const Color(0xFF374151),
                      ),
                    ),
                    trailing: _language == l
                        ? const Icon(
                            Icons.check_circle_rounded,
                            color: AppColors.green,
                          )
                        : null,
                    onTap: () {
                      setState(() => _language = l);
                      Navigator.pop(ctx);
                    },
                  ),
                ),
                SizedBox(height: width * 0.02),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Privacy & Security section ────────────────────────────────────────────
  Widget _buildPrivacySection(double width) {
    return _buildSectionCard(
      title: 'PRIVACY & SECURITY',
      width: width,
      children: [
        _buildTile(
          imagePath: 'assets/images/settings/twofactorauth.png',
          iconBgColor: AppColors.primaryBlue,
          title: 'Two-Factor Authentication',
          subtitle: 'Add an extra layer of security',
          width: width,
          onTap: () => _comingSoon('Two-Factor Authentication'),
        ),
        _buildTile(
          imagePath: 'assets/images/settings/loginact.png',
          iconBgColor: AppColors.primaryBlue,
          title: 'Login Activity',
          width: width,
          onTap: () => _comingSoon('Login Activity'),
        ),
        _buildTile(
          imagePath: 'assets/images/settings/block_user.png',
          iconBgColor: AppColors.red,
          title: 'Blocked Users',
          width: width,
          showDivider: false,
          onTap: () => _comingSoon('Blocked Users'),
        ),
      ],
    );
  }

  // ── Support section ───────────────────────────────────────────────────────
  Widget _buildSupportSection(double width) {
    return _buildSectionCard(
      title: 'SUPPORT',
      width: width,
      children: [
        _buildTile(
          imagePath: 'assets/images/settings/helpcenter.png',
          iconBgColor: AppColors.primaryBlue,
          title: 'Help Center',
          subtitle: 'FAQs and troubleshooting',
          width: width,
          onTap: () => _comingSoon('Help Center'),
        ),
        _buildTile(
          imagePath: 'assets/images/settings/contact.png',
          iconBgColor: AppColors.green,
          title: 'Contact Support',
          width: width,
          onTap: () => _comingSoon('Contact Support'),
        ),
        _buildTile(
          imagePath: 'assets/images/settings/bug.png',
          iconBgColor: AppColors.orange,
          title: 'Report a Bug',
          width: width,
          onTap: () => _comingSoon('Report a Bug'),
        ),
        _buildTile(
          imagePath: 'assets/images/settings/feedback.png',
          iconBgColor: AppColors.primaryBlue,
          title: 'Send Feedback',
          width: width,
          showDivider: false,
          onTap: () => _comingSoon('Send Feedback'),
        ),
      ],
    );
  }

  // ── Legal section ─────────────────────────────────────────────────────────
  Widget _buildLegalSection(double width) {
    return _buildSectionCard(
      title: 'LEGAL',
      width: width,
      children: [
        _buildTile(
          imagePath: 'assets/images/settings/terms.png',
          iconBgColor: AppColors.primaryBlue,
          title: 'Terms of Service',
          width: width,
          onTap: () => _comingSoon('Terms of Service'),
        ),
        _buildTile(
          imagePath: 'assets/images/settings/privacy.png',
          iconBgColor: AppColors.primaryBlue,
          title: 'Privacy Policy',
          width: width,
          showDivider: false,
          onTap: () => _comingSoon('Privacy Policy'),
        ),
      ],
    );
  }

  // ── About section ─────────────────────────────────────────────────────────
  Widget _buildAboutSection(double width) {
    return _buildSectionCard(
      title: 'ABOUT',
      width: width,
      children: [
        _buildTile(
          imagePath: 'assets/images/settings/about.png',
          iconBgColor: AppColors.primaryBlue,
          title: 'About GovPulse',
          width: width,
          onTap: () => _comingSoon('About'),
        ),
        _buildTile(
          imagePath: 'assets/images/settings/app.png',
          iconBgColor: AppColors.green,
          title: 'App Version',
          width: width,
          showDivider: false,
          onTap: () {},
          trailing: Text(
            'v$_appVersion',
            style: TextStyle(
              fontSize: width * 0.032,
              color: AppColors.hint,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  // ── Logout button ─────────────────────────────────────────────────────────
  Widget _buildLogoutButton(double width) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _confirmLogout,
        icon: SizedBox(
          width: width * 0.05,
          height: width * 0.05,
          child: ColorFiltered(
            colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
            child: Image.asset(
              'assets/images/settings/logout.png',
              fit: BoxFit.contain,
            ),
          ),
        ),
        label: Text(
          'Log Out',
          style: TextStyle(
            fontSize: width * 0.04,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            letterSpacing: 0.2,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.red,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(width * 0.03),
          ),
          padding: EdgeInsets.symmetric(vertical: width * 0.04),
        ),
      ),
    );
  }

  // ── Delete account button ─────────────────────────────────────────────────
  Widget _buildDeleteAccountButton(double width) {
    return TextButton(
      onPressed: _confirmDeleteAccount,
      child: Text(
        'Delete Account',
        style: TextStyle(
          fontSize: width * 0.034,
          fontWeight: FontWeight.w600,
          color: AppColors.red,
          decoration: TextDecoration.underline,
          decorationColor: AppColors.red,
        ),
      ),
    );
  }

  // ── Footer ────────────────────────────────────────────────────────────────
  Widget _buildFooter(double width) {
    return Column(
      children: [
        Text(
          'GovPulse',
          style: TextStyle(
            fontSize: width * 0.030,
            color: AppColors.hint,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: width * 0.005),
        Text(
          'Local Government Unit of Aparri, Cagayan',
          style: TextStyle(fontSize: width * 0.026, color: AppColors.hint),
        ),
      ],
    );
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
            color: Colors.black.withValues(alpha: 0.06),
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
          if (index == _navIndex) return;
          if (index == 0) {
            Navigator.pushAndRemoveUntil(
              context,
              PageRouteBuilder(
                transitionDuration: const Duration(milliseconds: 400),
                pageBuilder: (_, _, _) =>
                    NetworkWrapper(child: HomePage(username: widget.username)),
                transitionsBuilder: (_, animation, _, child) {
                  final slide =
                      Tween(
                        begin: const Offset(-1, 0),
                        end: Offset.zero,
                      ).animate(
                        CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeInOut,
                        ),
                      );
                  return SlideTransition(position: slide, child: child);
                },
              ),
              (route) => false,
            );
          } else if (index == 1) {
            if (_verifStatus != 'approved') {
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
            Navigator.pushNamed(
              context,
              '/newsfeed',
              arguments: {
                'username': widget.username,
                'isVerified': _verifStatus == 'approved',
              },
            );
          } else if (index == 3) {
            Navigator.pushNamed(
              context,
              '/emergency',
              arguments: {
                'username': widget.username,
                'isVerified': _verifStatus == 'approved',
              },
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
