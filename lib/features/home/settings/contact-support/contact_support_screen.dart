import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../../../../core/widgets/responsive_page.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../../../core/theme/citizen_ui.dart';
import '../../../../core/widgets/Home/Account/account_web_kit.dart';
import '../../../../core/theme/mobile_metrics.dart';
import '../../../../core/widgets/app_back_chevron.dart';

class ContactSupportScreen extends StatefulWidget {
  final String username;
  const ContactSupportScreen({super.key, required this.username});

  @override
  State<ContactSupportScreen> createState() => _ContactSupportScreenState();
}

class _ContactSupportScreenState extends State<ContactSupportScreen>
    with TickerProviderStateMixin {
  // ──────────────────────────────────────────────────────────────────────────

  // (aparri.mun.ph or the municipal office) before release.
  //   • _supportPhone / _supportPhoneDisplay → verify the trunkline number
  //   • _facebookUrl                         → the LGU's official FB page
  // ──────────────────────────────────────────────────────────────────────────
  // Confirmed from public sources.
  static const String _officeName = 'Aparri Municipal Hall';
  static const String _officeAddress = 'Luna Street, Aparri, Cagayan, 3515';
  static const String _officeHours = 'Mon – Fri, 8:00 AM – 5:00 PM';

  // VERIFY against aparri.mun.ph or the municipal office before release.
  static const String _supportPhone = '+63788882001';
  static const String _supportPhoneDisplay = '(078) 888-2001';

  // Launching the https link routes to the FB app if installed, else browser.
  static const String _facebookUrl = 'https://www.facebook.com/example';

  // ── Content slide-up animation (mirrors MySubmissionsScreen) ───────────────
  late final AnimationController _slideCtrl;
  late final Animation<Offset> _slideAnim;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();

    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.10),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic));
    _fadeAnim = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOut));

    _slideCtrl.forward();
  }

  @override
  void dispose() {
    _slideCtrl.dispose();
    super.dispose();
  }

  // ── Launch helpers ─────────────────────────────────────────────────────────
  void _snack(String msg) {
    if (!mounted) return;
    showAppSnackBar(context, msg, type: AppSnackType.info);
  }

  Future<void> _launch(Uri uri, String failMsg) async {
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) _snack(failMsg);
    } catch (_) {
      _snack(failMsg);
    }
  }

  Future<void> _openFacebook() =>
      _launch(Uri.parse(_facebookUrl), 'Could not open Facebook.');

  Future<void> _callSupport() => _launch(
    Uri(scheme: 'tel', path: _supportPhone),
    'Could not open the dialer.',
  );

  Future<void> _openMaps() {
    final query = Uri.encodeComponent('$_officeName, $_officeAddress');
    return _launch(
      Uri.parse('https://www.google.com/maps/search/?api=1&query=$query'),
      'Could not open maps.',
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // The browser always gets the web layout — `kIsWeb` alone, no width test,
    // for the reason EditProfileScreen spells out.
    if (kIsWeb) return _buildWebScaffold();

    final w = uiScaleWidth(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: ResponsivePageBody(
        shellTitle: 'Contact Support',
        shellSubtitle:
            'Reach the Aparri LGU team for help with your account, reports, '
            'or anything else on GovPulse.',
        shellIcon: Icons.support_agent_rounded,
        shellHighlights: const [
          (Icons.facebook_rounded, 'Message us on Facebook'),
          (Icons.call_outlined, 'Call the support hotline'),
          (Icons.location_on_outlined, 'Visit the municipal office'),
        ],
        child: SafeArea(
          child: Column(
            children: [
              // Header is pinned — NOT part of the slide-up animation.
              _buildHeader(w),
              Expanded(
                child: FadeTransition(
                  opacity: _fadeAnim,
                  child: SlideTransition(
                    position: _slideAnim,
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(
                        w * 0.04,
                        w * 0.035,
                        w * 0.04,
                        w * 0.08,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildIntroCard(w),
                          SizedBox(height: w * 0.05),
                          _sectionLabel(w, 'GET IN TOUCH'),
                          SizedBox(height: w * 0.02),
                          _buildCard(w, [
                            _contactTile(
                              w,
                              icon: Icons.facebook_rounded,
                              color: AppColors.primaryBlue,
                              title: 'Message on Facebook',
                              value: 'Official Aparri LGU page',
                              onTap: _openFacebook,
                            ),
                            _contactTile(
                              w,
                              icon: Icons.call_outlined,
                              color: AppColors.green,
                              title: 'Call Us',
                              value: _supportPhoneDisplay,
                              onTap: _callSupport,
                              showDivider: false,
                            ),
                          ]),
                          SizedBox(height: w * 0.05),
                          _sectionLabel(w, 'OFFICE'),
                          SizedBox(height: w * 0.02),
                          _buildCard(w, [
                            _contactTile(
                              w,
                              icon: Icons.location_on_outlined,
                              color: AppColors.orange,
                              title: _officeName,
                              value: _officeAddress,
                              onTap: _openMaps,
                            ),
                            _infoTile(
                              w,
                              icon: Icons.schedule_rounded,
                              color: AppColors.primaryBlue,
                              title: 'Office Hours',
                              value: _officeHours,
                              showDivider: false,
                            ),
                          ]),
                          SizedBox(height: w * 0.05),
                          _buildResponseNote(w),
                        ],
                      ),
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

  // ── Header — identical to MySubmissionsScreen for consistency ──────────────
  Widget _buildHeader(double w) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(w * 0.04, w * 0.04, w * 0.04, w * 0.035),
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
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: w * 0.09,
              height: w * 0.09,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(w * 0.025),
                border: Border.all(color: kBackChevronBorder),
              ),
              child: Icon(
                Icons.arrow_back_ios_new_rounded,
                size: w * 0.046,
                color: kBackChevronGlyph,
              ),
            ),
          ),
          SizedBox(width: w * 0.035),
          Text(
            'Contact Support',
            style: TextStyle(
              fontSize: w * 0.052,
              fontWeight: FontWeight.w700,
              color: kScreenTitleColor,
              letterSpacing: -0.3,
            ),
          ),
        ],
      ),
    );
  }

  // ── Intro / hero card ──────────────────────────────────────────────────────
  Widget _buildIntroCard(double w) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(w * 0.05),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(w * 0.04),
        border: Border.all(color: CitizenUi.sharedStroke),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: w * 0.16,
            height: w * 0.16,
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            // Padding keeps the artwork on the same optical size the 0.085
            // Icon had, so the circle never looks crowded on narrow phones.
            padding: EdgeInsets.all(w * 0.037),
            child: Image.asset(
              'assets/images/helpdesk.webp',
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, _, _) => Icon(
                Icons.support_agent_rounded,
                size: w * 0.085,
                color: AppColors.primaryBlue,
              ),
            ),
          ),
          SizedBox(height: w * 0.035),
          Text(
            'We\'re here to help',
            style: TextStyle(
              fontSize: w * 0.046,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1F2937),
            ),
          ),
          SizedBox(height: w * 0.018),
          Text(
            'Reach the Aparri LGU support team for help with your account, '
            'verification, or submissions. Choose any option below.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: w * 0.033,
              color: const Color(0xFF6B7280),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  // ── Section label ──────────────────────────────────────────────────────────
  Widget _sectionLabel(double w, String text) {
    return Padding(
      padding: EdgeInsets.only(left: w * 0.01),
      child: Text(
        text,
        style: TextStyle(
          fontSize: w * 0.034,
          fontWeight: FontWeight.w700,
          color: AppColors.primaryBlue,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  // ── White rounded section container ────────────────────────────────────────
  Widget _buildCard(double w, List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(w * 0.035),
        border: Border.all(color: CitizenUi.sharedStroke),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }

  // ── Tappable contact tile (launches mail / dialer / maps) ──────────────────
  Widget _contactTile(
    double w, {
    required IconData icon,
    required Color color,
    required String title,
    required String value,
    required VoidCallback onTap,
    bool showDivider = true,
  }) {
    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: w * 0.04,
                vertical: w * 0.034,
              ),
              child: Row(
                children: [
                  _iconBox(w, icon: icon, color: color),
                  SizedBox(width: w * 0.035),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: w * 0.038,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF1F2937),
                          ),
                        ),
                        SizedBox(height: w * 0.005),
                        Text(
                          value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: w * 0.032,
                            color: AppColors.hint,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: w * 0.08,
                    height: w * 0.08,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(w * 0.02),
                    ),
                    child: Icon(
                      Icons.north_east_rounded,
                      size: w * 0.04,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (showDivider)
          Padding(
            padding: EdgeInsets.only(left: w * 0.175),
            child: const Divider(height: 1, color: CitizenUi.sharedStroke),
          ),
      ],
    );
  }

  // ── Info-only tile (no launch action) ──────────────────────────────────────
  Widget _infoTile(
    double w, {
    required IconData icon,
    required Color color,
    required String title,
    required String value,
    bool showDivider = true,
  }) {
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: w * 0.04,
            vertical: w * 0.034,
          ),
          child: Row(
            children: [
              _iconBox(w, icon: icon, color: color),
              SizedBox(width: w * 0.035),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: w * 0.038,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF1F2937),
                      ),
                    ),
                    SizedBox(height: w * 0.005),
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: w * 0.032,
                        color: AppColors.hint,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          Padding(
            padding: EdgeInsets.only(left: w * 0.175),
            child: const Divider(height: 1, color: CitizenUi.sharedStroke),
          ),
      ],
    );
  }

  // ── Leading icon box (shared) ──────────────────────────────────────────────
  Widget _iconBox(double w, {required IconData icon, required Color color}) {
    return Container(
      width: w * 0.105,
      height: w * 0.105,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(w * 0.025),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 1.2),
      ),
      child: Icon(icon, size: w * 0.05, color: color),
    );
  }

  // ── Response-time note ─────────────────────────────────────────────────────
  Widget _buildResponseNote(double w) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(w * 0.04),
      decoration: BoxDecoration(
        color: AppColors.primaryBlue.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(w * 0.03),
        border: Border.all(
          color: AppColors.primaryBlue.withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: w * 0.045,
            color: AppColors.primaryBlue,
          ),
          SizedBox(width: w * 0.025),
          Expanded(
            child: Text(
              'Support requests are usually answered within 1–3 working days. '
              'For emergencies, please contact your barangay or local hotline directly.',
              style: TextStyle(
                fontSize: w * 0.030,
                color: const Color(0xFF374151),
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  //  WEB
  //
  //  Reached only from the `kIsWeb` branch of build(). The mobile layout above
  //  is untouched; this is a second layout over the same launch handlers.
  // ═════════════════════════════════════════════════════════════════════════

  Widget _buildWebScaffold() {
    // No ResponsivePageBody and so no `shellTitle`: that path wraps the page in
    // SettingsWebShell's 600px column beside a decorative brand panel, which is
    // wrong inside a pane that already has a top nav and a left rail.
    //
    // No skeleton either. This page fetches nothing — every value on it is a
    // compile-time constant — so there is no loading state to draw.
    return Scaffold(
      backgroundColor: CitizenUi.pageBg,
      body: SafeArea(child: AccountPageBody(builder: _buildWebBody)),
    );
  }

  Widget _buildWebBody(BuildContext context, bool stack) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── The intro hero card is gone on web, deliberately ────────────────
        //
        // It was an avatar circle over "We're here to help" over a sentence
        // telling you to choose an option below. The page title now says the
        // same thing in the same place every other account page says it, and a
        // second restatement of it — as a 200px card above the two rows it is
        // describing — is the "slab of colour above the thing it describes"
        // that [AccountNotice] documents as the pattern this kit rejects.
        const AccountPageTitle(
          title: 'Contact Support',
          subtitle:
              'Reach the Aparri LGU team for help with your account, your '
              'submissions, or anything else on GovPulse.',
        ),
        AccountSectionList(
          sections: [
            AccountListSection(
              title: 'Get in touch',
              children: [
                // Outbound arrow rather than the chevron [AccountRow] supplies
                // by default: these rows leave GovPulse for Facebook, the
                // dialer or Maps, and a chevron promises another page inside
                // the app.
                AccountRow(
                  icon: Icons.facebook_rounded,
                  title: 'Message on Facebook',
                  subtitle: 'Official Aparri LGU page',
                  onTap: _openFacebook,
                  trailing: _webOutboundIcon(),
                ),
                AccountRow(
                  icon: Icons.call_outlined,
                  title: 'Call us',
                  subtitle: _supportPhoneDisplay,
                  onTap: _callSupport,
                  trailing: _webOutboundIcon(),
                ),
              ],
            ),
            AccountListSection(
              title: 'Office',
              children: [
                AccountRow(
                  icon: Icons.location_on_outlined,
                  title: _officeName,
                  subtitle: _officeAddress,
                  onTap: _openMaps,
                  trailing: _webOutboundIcon(),
                ),
                // No onTap and no trailing: office hours are a value, not a
                // destination, and [AccountRow] draws no affordance for one.
                const AccountRow(
                  icon: Icons.schedule_rounded,
                  title: 'Office hours',
                  subtitle: _officeHours,
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: kAccountSectionGap),
        AccountNotice(
          icon: Icons.info_outline_rounded,
          title: 'Response times',
          message:
              'Support requests are usually answered within 1–3 working days. '
              'For emergencies, contact your barangay or local hotline '
              'directly.',
          stack: stack,
        ),
      ],
    );
  }

  Widget _webOutboundIcon() => const Icon(
    Icons.north_east_rounded,
    size: 18,
    color: CitizenUi.textFaint,
  );
}
