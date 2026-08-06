import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/loading/loading_overlay.dart';
import '../../../core/widgets/modal/verification_required_dialog.dart';
import '../../../core/widgets/Home/nav/responsive_nav_scaffold.dart';
import '../../../core/services/citizen_logout.dart';
import '../../../core/router/legacy_nav.dart';
import '../../../core/providers/user_profile_provider.dart';
import '../../../core/widgets/Home/home_enums.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../Resets/set_password_screen.dart';
import '../../../core/widgets/app_dialog.dart';

/// Standalone Settings page — the route the mobile app and the live web routes
/// open. Owns the nav chrome; the content is [SettingsBody].
class SettingScreen extends ConsumerWidget {
  final String username;
  const SettingScreen({super.key, required this.username});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider).valueOrNull;
    return ResponsiveNavScaffold(
      currentIndex: 4,
      username: username,
      isVerified: profile?.verifStatus == VerifStatus.verified,
      backgroundColor: const Color(0xFFF3F4F6),
      fullName: profile?.fullName,
      facePhotoUrl: profile?.facePhotoUrl,
      verifStatus: profile?.verifStatus,
      onLogout: (ctx) => performCitizenLogout(ctx, ref),
      body: const SafeArea(child: SettingsBody()),
    );
  }
}

/// Settings content, with no chrome of its own. Rendered inside
/// [SettingScreen] on mobile and directly as a centre pane by the web shell.
///
/// Takes no `username`: identity comes from [userProfileProvider].
class SettingsBody extends ConsumerStatefulWidget {
  const SettingsBody({super.key});

  @override
  ConsumerState<SettingsBody> createState() => _SettingScreenState();
}

class _SettingScreenState extends ConsumerState<SettingsBody>
    with TickerProviderStateMixin {
  /// Account handle, from the shared profile.
  String get _username =>
      ref.read(userProfileProvider).valueOrNull?.username ?? '';
  static const String _appVersion = '1.0.0';

  // ── Identity flag (reactive) ──────────────────────────────────────────────
  bool _hasPasswordLogin = false;
  bool _isFacebookUser = false;
  bool _isFacebookOnly = false;

  // ── Push-notification preference ──────────────────────────────────────────
  bool _pushEnabled = true;
  bool _pushBusy = false;

  // ── Entry animation controller ────────────────────────────────────────────
  late final AnimationController _entryCtrl;

  @override
  void initState() {
    super.initState();

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

    // ── Seed identity flags ───────────────────────────────────────────────
    _refreshIdentityFlags();
    _loadPushPref();
  }

  // ── Push preference ─────────────────────────────────────────────────────────
  Future<void> _loadPushPref() async {
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) return;
      final row = await Supabase.instance.client
          .from('notification_preferences')
          .select('push_enabled')
          .eq('user_id', uid)
          .maybeSingle();
      if (!mounted) return;
      // No row = enabled by default.
      setState(() => _pushEnabled = (row?['push_enabled'] as bool?) ?? true);
    } catch (_) {
      // Table may not exist yet (migration not run) — leave the default (on).
    }
  }

  Future<void> _togglePush(bool value) async {
    if (_pushBusy) return;
    final previous = _pushEnabled;
    setState(() {
      _pushEnabled = value; // optimistic
      _pushBusy = true;
    });
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) throw 'Not signed in';
      await Supabase.instance.client.from('notification_preferences').upsert({
        'user_id': uid,
        'push_enabled': value,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      if (!mounted) return;
      setState(() => _pushBusy = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _pushEnabled = previous; // revert on failure
        _pushBusy = false;
      });
      showAppSnackBar(context, 'Could not update notifications setting.',
          type: AppSnackType.error);
    }
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    super.dispose();
  }

  void _refreshIdentityFlags() {
    final user = Supabase.instance.client.auth.currentUser;
    final identities = user?.identities ?? [];

    // An OAuth-only (Facebook) account NEVER gets an 'email' provider added to
    // auth.identities just by calling updateUser(password:) — that's a known
    // Supabase limitation. So the identities list alone can't tell us the user
    // set a password. We also honour the `has_password` flag we stamp into
    // user_metadata in SetPasswordScreen.
    final hasPasswordMeta = user?.userMetadata?['has_password'] == true;

    setState(() {
      _hasPasswordLogin =
          hasPasswordMeta || identities.any((i) => i.provider == 'email');
      _isFacebookUser = identities.any((i) => i.provider == 'facebook');
      _isFacebookOnly = _isFacebookUser && !_hasPasswordLogin;
    });
  }

  // ── Staggered right-to-left entry animation helper ────────────────────────
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
        Tween<Offset>(begin: const Offset(0.0, 0.28), end: Offset.zero).animate(
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

  // ── Status badge config ───────────────────────────────────────────────────
  ({String label, Color bg, Color border, Color dot, Color text})
  _statusBadgeFor(String verifStatus) {
    switch (verifStatus) {
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

  // ── Logout flow ───────────────────────────────────────────────────────────
  /// Delegates to the shared citizen logout flow. It used to live here, which
  /// is why the nav chrome had to reach back down the element tree to start
  /// it; now both callers just call the function.
  Future<void> _confirmLogout() => performCitizenLogout(context, ref);

  // ── Delete account ────────────────────────────────────────────────────────
  Future<void> _confirmDeleteAccount() async {
    final width = MediaQuery.of(context).size.width.clamp(0.0, 480.0);

    await showAppDialog(
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
    final rawWidth = MediaQuery.of(context).size.width;
    // WEB / large screens: two-column settings layout that fills the width.
    // Phones & narrow web keep the original single-column body (design width
    // capped at 480), byte-for-byte unchanged.
    final bool wide = kIsWeb && rawWidth >= 900;
    final double width = wide ? 460.0 : rawWidth.clamp(0.0, 480.0);

    // ── Read from provider ────────────────────────────────────────────────
    final profileAsync = ref.watch(userProfileProvider);
    final profile = profileAsync.valueOrNull;
    final verifStatus = profile?.verifStatus == VerifStatus.verified
        ? 'approved'
        : profile?.verifStatus == VerifStatus.pending
        ? 'pending'
        : 'none';
    final facePhotoUrl = profile?.facePhotoUrl;
    final facePhotoPath = profile?.facePhotoPath;
    final fullName = profile?.fullName;
    final email = profile?.email;
    final profileLoading = profileAsync.isLoading && !profileAsync.hasValue;

    final badge = _statusBadgeFor(verifStatus);

    return wide
            ? LoadingOverlay.bodyOrSkeleton(
                isLoading: profileLoading,
                layout: SkeletonLayout.settings,
                child: _buildWebBody(
                  width,
                  verifStatus,
                  email,
                  fullName,
                  facePhotoUrl,
                  facePhotoPath,
                  profileLoading,
                  badge,
                ),
              )
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Column(
                    children: [
                      _buildHeader(width),
                      Expanded(
                        child: LoadingOverlay.bodyOrSkeleton(
                          isLoading: profileLoading,
                          layout: SkeletonLayout.settings,
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
                                _animated(
                                  1,
                                  _buildProfileCard(
                                    width,
                                    fullName,
                                    email,
                                    facePhotoUrl,
                                    facePhotoPath,
                                    profileLoading,
                                    badge,
                                  ),
                                ),
                                SizedBox(height: width * 0.04),
                                _animated(
                                  2,
                                  _buildAccountSection(
                                    width,
                                    verifStatus,
                                    email,
                                    profileLoading,
                                  ),
                                ),
                                SizedBox(height: width * 0.04),
                                _animated(3, _buildPreferencesSection(width)),
                                SizedBox(height: width * 0.04),
                                _animated(4, _buildSupportSection(width)),
                                SizedBox(height: width * 0.04),
                                _animated(5, _buildLegalSection(width)),
                                SizedBox(height: width * 0.04),
                                _animated(6, _buildAboutSection(width)),
                                SizedBox(height: width * 0.05),
                                _animated(7, _buildLogoutButton(width)),
                                SizedBox(height: width * 0.025),
                                _animated(7, _buildDeleteAccountButton(width)),
                                SizedBox(height: width * 0.04),
                                _animated(8, _buildFooter(width)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
  }

  // ── WEB body: profile banner + two-column sections ─────────────────────────
  Widget _buildWebBody(
    double width,
    String verifStatus,
    String? email,
    String? fullName,
    String? facePhotoUrl,
    String? facePhotoPath,
    bool profileLoading,
    ({String label, Color bg, Color border, Color dot, Color text}) badge,
  ) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 56),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(width),
                const SizedBox(height: 24),
                _animated(
                  1,
                  _buildProfileCard(
                    width,
                    fullName,
                    email,
                    facePhotoUrl,
                    facePhotoPath,
                    profileLoading,
                    badge,
                  ),
                ),
                const SizedBox(height: 28),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _animated(
                              2,
                              _buildAccountSection(
                                width,
                                verifStatus,
                                email,
                                profileLoading,
                              ),
                            ),
                            const SizedBox(height: 20),
                            _animated(3, _buildPreferencesSection(width)),
                            const SizedBox(height: 20),
                            _animated(4, _buildSupportSection(width)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 24),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _animated(5, _buildLegalSection(width)),
                            const SizedBox(height: 20),
                            _animated(6, _buildAboutSection(width)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: Column(
                      children: [
                        _animated(6, _buildLogoutButton(width)),
                        SizedBox(height: width * 0.025),
                        _animated(7, _buildDeleteAccountButton(width)),
                        SizedBox(height: width * 0.04),
                        _animated(8, _buildFooter(width)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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
            'assets/images/newslogo.webp',
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
  Widget _buildProfileCard(
    double width,
    String? fullName,
    String? email,
    String? facePhotoUrl,
    String? facePhotoPath,
    bool profileLoading,
    ({String label, Color bg, Color border, Color dot, Color text}) badge,
  ) {
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
            child: ClipOval(
              child: _buildAvatar(
                width,
                facePhotoUrl,
                facePhotoPath,
                profileLoading,
              ),
            ),
          ),
          SizedBox(width: width * 0.035),
          Expanded(
            child: profileLoading
                ? _buildProfileCardSkeleton(width)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fullName ?? _username,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: width * 0.045,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF1F2937),
                        ),
                      ),
                      if (email != null) ...[
                        SizedBox(height: width * 0.005),
                        Builder(
                          builder: (context) {
                            final user =
                                Supabase.instance.client.auth.currentUser;
                            final identities = user?.identities ?? [];
                            final hasPasswordMeta =
                                user?.userMetadata?['has_password'] == true;
                            final isFacebookOnly =
                                identities.any(
                                  (i) => i.provider == 'facebook',
                                ) &&
                                !hasPasswordMeta &&
                                !identities.any((i) => i.provider == 'email');
                            if (isFacebookOnly) return const SizedBox.shrink();
                            return Text(
                              email,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: width * 0.030,
                                color: AppColors.hint,
                              ),
                            );
                          },
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
                            Container(
                              width: width * 0.010,
                              height: width * 0.010,
                              decoration: BoxDecoration(
                                color: badge.dot,
                                shape: BoxShape.circle,
                              ),
                            ),
                            SizedBox(width: width * 0.012),
                            Text(
                              badge.label,
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

  /// Name · email · status pill, shimmered while the profile is in flight.
  /// Sized off the same design width as the real block so the card holds its
  /// height on phone, tablet and the wide web banner alike.
  Widget _buildProfileCardSkeleton(double width) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppShimmerBox(
          width: width * 0.46,
          height: width * 0.045,
          radius: width * 0.012,
        ),
        SizedBox(height: width * 0.016),
        AppShimmerBox(
          width: width * 0.34,
          height: width * 0.030,
          radius: width * 0.008,
        ),
        SizedBox(height: width * 0.018),
        AppShimmerBox(
          width: width * 0.30,
          height: width * 0.052,
          radius: width * 0.03,
        ),
      ],
    );
  }

  Widget _buildAvatar(
    double width,
    String? facePhotoUrl,
    String? facePhotoPath,
    bool profileLoading,
  ) {
    final size = width * 0.16;

    // Shimmer for both "profile fetching" and "photo downloading" so the avatar
    // matches the shimmered name/email beside it instead of spinning.
    Widget shimmer() =>
        AppShimmerBox(width: size, height: size, radius: size / 2);

    if (profileLoading) return shimmer();

    if (facePhotoUrl != null && facePhotoUrl.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: facePhotoUrl,
        cacheKey: facePhotoPath ?? facePhotoUrl,
        memCacheWidth: 160,
        width: size,
        height: size,
        fit: BoxFit.cover,
        placeholder: (context, url) => shimmer(),
        errorWidget: (context, url, error) =>
            Image.asset('assets/images/profilenew.webp', fit: BoxFit.cover),
      );
    }

    return Image.asset('assets/images/profilenew.webp', fit: BoxFit.cover);
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
    bool showChevron = true,
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
                      (showChevron
                          ? Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: width * 0.035,
                              color: const Color(0xFF9CA3AF),
                            )
                          : const SizedBox.shrink()),
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

  // ── Account section ───────────────────────────────────────────────────────
  Widget _buildAccountSection(
    double width,
    String verifStatus,
    String? email,
    bool profileLoading,
  ) {
    return _buildSectionCard(
      title: 'ACCOUNT',
      width: width,
      children: [
        _buildTile(
          imagePath: 'assets/images/settings/user.webp',
          iconBgColor: AppColors.primaryBlue,
          title: 'Edit Profile',
          subtitle: 'Update your personal information',
          width: width,
          onTap: () async {
            if (profileLoading) return;

            final approved = await showVerificationRequiredDialog(
              context,
              isVerified: verifStatus == 'approved',
              username: _username,
              message:
                  'Only verified citizens can edit their profile information. Please complete the identity verification process first.',
            );

            if (!approved || !mounted) return;

            final refreshed = await pushLegacy(
              context,
              '/edit_profile',
              arguments: _username,
            );
            if (refreshed == true && mounted) {
              ref.read(userProfileProvider.notifier).refresh();
            }
          },
        ),

        if (!_isFacebookOnly)
          _buildTile(
            imagePath: 'assets/images/settings/password.webp',
            iconBgColor: AppColors.primaryBlue,
            title: 'Change Password',
            width: width,
            onTap: () {
              if (email == null) return;
              pushLegacy(
                context,
                '/change_password',
                arguments: email,
              );
            },
          ),

        if (_isFacebookUser && !_hasPasswordLogin)
          _buildTile(
            imagePath: 'assets/images/settings/password.webp',
            iconBgColor: const Color(0xFF1877F2),
            title: _hasPasswordLogin ? 'Update Password' : 'Set Password',
            subtitle: _hasPasswordLogin
                ? 'Change your email login password'
                : 'Add email & password as a backup login',
            width: width,
            onTap: () async {
              final result = await Navigator.push(
                context,
                PageRouteBuilder(
                  transitionDuration: Duration.zero,
                  reverseTransitionDuration: const Duration(milliseconds: 220),
                  pageBuilder: (_, _, _) => const SetPasswordScreen(),
                  // Match the app-wide _instantInFadeOut behaviour: instant in,
                  // fade out on the way back to Settings.
                  transitionsBuilder: (_, anim, _, child) =>
                      FadeTransition(opacity: anim, child: child),
                ),
              );
              if (result == true && mounted) {
                await Supabase.instance.client.auth.getUser();
                if (!mounted) return;
                _refreshIdentityFlags();
                ref.read(userProfileProvider.notifier).refresh();
                await showSuccessDialog(
                  // ignore: use_build_context_synchronously
                  context,
                  title: 'Password Set!',
                  message:
                      'You can now log in with your email and password as a backup to Facebook.',
                  buttonLabel: 'Got it',
                  iconData: Icons.lock_rounded,
                  iconColor: AppColors.primaryBlue,
                );
              }
            },
          ),

        _buildTile(
          imagePath: 'assets/images/settings/submission.webp',
          iconBgColor: AppColors.primaryBlue,
          title: 'My Submissions',
          subtitle: 'View your verification & report history',
          width: width,
          showDivider: false,
          onTap: () async {
            if (profileLoading) return;

            final approved = await showVerificationRequiredDialog(
              context,
              isVerified: verifStatus == 'approved',
              username: _username,
              message:
                  'Only verified citizens can view their submission history. Please complete the identity verification process first.',
            );

            if (!approved || !mounted) return;

            pushLegacy(
              context,
              '/my_submissions',
              arguments: _username,
            );
          },
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
          imagePath: 'assets/images/settings/notification.webp',
          iconBgColor: AppColors.primaryBlue,
          title: 'Push notifications',
          subtitle: _pushEnabled
              ? 'Get alerts for report updates, replies & more'
              : 'Push alerts are off — you\'ll still see them in-app',
          width: width,
          showChevron: false,
          showDivider: false,
          onTap: () => _togglePush(!_pushEnabled),
          trailing: Switch.adaptive(
            value: _pushEnabled,
            onChanged: _pushBusy ? null : _togglePush,
            activeThumbColor: AppColors.primaryBlue,
          ),
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
          imagePath: 'assets/images/settings/contact.webp',
          iconBgColor: AppColors.green,
          title: 'Contact Support',
          subtitle: 'Get help from the Aparri LGU',
          width: width,
          showDivider: false,
          onTap: () => pushLegacy(
            context,
            '/contact_support',
            arguments: _username,
          ),
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
          imagePath: 'assets/images/settings/terms.webp',
          iconBgColor: AppColors.primaryBlue,
          title: 'Terms of Service',
          width: width,
          onTap: () => pushLegacy(context, '/terms_of_service'),
        ),
        _buildTile(
          imagePath: 'assets/images/settings/privacy.webp',
          iconBgColor: AppColors.primaryBlue,
          title: 'Privacy Policy',
          width: width,
          showDivider: false,
          onTap: () => pushLegacy(context, '/privacy_policy'),
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
          imagePath: 'assets/images/settings/about.webp',
          iconBgColor: AppColors.primaryBlue,
          title: 'About GovPulse',
          width: width,
          onTap: () => pushLegacy(context, '/about'),
        ),
        _buildTile(
          imagePath: 'assets/images/settings/location.webp',
          iconBgColor: AppColors.green,
          title: 'Location',
          subtitle: 'Aparri, Cagayan',
          width: width,
          showChevron: false,
          onTap: () {
            final query = Uri.encodeComponent('Aparri, Cagayan, Philippines');
            launchUrl(
              Uri.parse(
                'https://www.google.com/maps/search/?api=1&query=$query',
              ),
              mode: LaunchMode.externalApplication,
            );
          },
        ),
        _buildTile(
          imagePath: 'assets/images/settings/app.webp',
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
              'assets/images/settings/logout.webp',
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
}
