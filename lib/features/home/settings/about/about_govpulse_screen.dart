import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../../../../core/widgets/responsive_page.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/citizen_ui.dart';
import '../../../../core/widgets/Home/Account/account_web_kit.dart';
import '../../../../core/theme/mobile_metrics.dart';

class AboutGovPulseScreen extends StatefulWidget {
  const AboutGovPulseScreen({super.key});

  @override
  State<AboutGovPulseScreen> createState() => _AboutGovPulseScreenState();
}

class _AboutGovPulseScreenState extends State<AboutGovPulseScreen>
    with SingleTickerProviderStateMixin {
  static const String _appVersion = '1.0.0';
  static const String _buildNumber = '100';
  static const String _releaseDate = 'June 2025';

  // ── Content slide-up animation (mirrors ContactSupportScreen) ──────────────
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
        shellTitle: 'About GovPulse',
        shellSubtitle:
            'The official digital platform connecting Aparri citizens with '
            'their local government.',
        shellIcon: Icons.info_rounded,
        shellHighlights: const [
          (Icons.campaign_rounded, 'Report and track community issues'),
          (Icons.event_rounded, 'Stay updated on local events'),
          (Icons.account_balance_rounded, 'Access LGU services online'),
        ],
        shellContentWidth: 620,
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
                        children: [..._sections(w)],
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

  /// The page's content, in order — the one copy of it, rendered by both
  /// layouts.
  ///
  /// Extracted verbatim out of build(): the mobile tree below still passes it
  /// the same `w` and spreads it into the same Column, so nothing about the app
  /// layout changed. Keeping it in one place is what lets the web branch exist
  /// without a second transcription of several thousand words of policy text
  /// for the two to drift apart.
  List<Widget> _sections(double w) => [
    // Mobile only. On web this card's job — saying what the page is, at the
    // top of the scroll — is [AccountPageTitle]'s, and the web scaffold puts
    // one there. Rendering both would state it twice, the second time as a
    // 200px slab above the content it is describing.
    if (!kIsWeb) ...[_buildHeroCard(w), _gapBetweenSections(w)],
    _sectionLabel(w, 'WHAT IS GOVPULSE'),
    _gapAfterLabel(w),
    _buildCard(w, [
      _buildBodyTile(
        w,
        icon: Icons.account_balance_outlined,
        color: AppColors.primaryBlue,
        title: 'Our Mission',
        body:
            'GovPulse is the official civic engagement platform of the Local Government Unit of Aparri, Cagayan. It bridges the gap between citizens and their local government — making public services more accessible, transparent, and responsive.',
      ),
      _buildBodyTile(
        w,
        icon: Icons.groups_outlined,
        color: AppColors.primaryBlue,
        title: 'Who It\'s For',
        body:
            'Built for every verified resident of Aparri, GovPulse gives citizens a direct line to their LGU — whether to report issues, track the status of concerns, join the community conversation, or stay informed about local events.',
        showDivider: false,
      ),
    ]),
    _gapBetweenSections(w),
    _sectionLabel(w, 'FEATURES'),
    _gapAfterLabel(w),
    _buildCard(w, [
      _buildBodyTile(
        w,
        icon: Icons.report_outlined,
        color: AppColors.primaryBlue,
        title: 'Report Issues',
        body:
            'Submit civic concerns with photos, location, and descriptions. Track the status of your reports in real time and receive updates from LGU staff.',
      ),
      _buildBodyTile(
        w,
        icon: Icons.forum_outlined,
        color: AppColors.green,
        title: 'Community Newsfeed',
        body:
            'Stay connected with your barangay through a scoped community feed. Share updates, read posts from neighbors, and engage with local announcements.',
      ),
      _buildBodyTile(
        w,
        icon: Icons.smart_toy_outlined,
        color: AppColors.primaryBlue,
        title: 'Kuya Gov AI Assistant',
        body:
            'Get instant answers about LGU services, requirements, and procedures through Kuya Gov — an AI-powered chat assistant available 24/7.',
      ),
      _buildBodyTile(
        w,
        icon: Icons.support_agent_rounded,
        color: AppColors.green,
        title: 'Live Agent Support',
        body:
            'Escalate concerns to a real LGU staff member when needed. Live agent sessions connect you directly to the right department for personalized assistance.',
      ),
      _buildBodyTile(
        w,
        icon: Icons.event_outlined,
        color: AppColors.orange,
        title: 'Events & Announcements',
        body:
            'Never miss a local event, emergency alert, or official LGU announcement. Featured events and news are surfaced directly on your home feed.',
      ),
      _buildBodyTile(
        w,
        icon: Icons.verified_outlined,
        color: AppColors.primaryBlue,
        title: 'Citizen Verification',
        body:
            'A secure identity verification flow ensures that GovPulse remains a trusted space for genuine residents of Aparri to engage with their local government.',
        showDivider: false,
      ),
    ]),
    _gapBetweenSections(w),
    _sectionLabel(w, 'APP INFO'),
    _gapAfterLabel(w),
    _buildCard(w, [
      _buildInfoTile(
        w,
        icon: Icons.tag_rounded,
        color: AppColors.primaryBlue,
        title: 'Version',
        value: 'v$_appVersion (Build $_buildNumber)',
      ),
      _buildInfoTile(
        w,
        icon: Icons.calendar_today_outlined,
        color: AppColors.primaryBlue,
        title: 'Release Date',
        value: _releaseDate,
      ),
      _buildInfoTile(
        w,
        icon: Icons.location_on_outlined,
        color: AppColors.green,
        title: 'Serving',
        value: 'Aparri, Cagayan, Philippines',
      ),
      _buildInfoTile(
        w,
        icon: Icons.code_rounded,
        color: AppColors.primaryBlue,
        title: 'Platform',
        value: 'Flutter · iOS · Android · Web',
        showDivider: false,
      ),
    ]),
    _gapBetweenSections(w),
    _buildFooterCard(w),
  ];

  // ═════════════════════════════════════════════════════════════════════════
  //  WEB
  //
  //  Reached only from the `kIsWeb` branch of build(). The mobile layout is
  //  untouched; the helpers above render both, branching internally.
  // ═════════════════════════════════════════════════════════════════════════

  Widget _buildWebScaffold() {
    // No ResponsivePageBody, so no `shellTitle` and no SettingsWebShell brand
    // panel — wrong inside a pane that already has a top nav and a left rail.
    // Nothing here is fetched, so there is no loading state to draw either.
    return Scaffold(
      backgroundColor: CitizenUi.pageBg,
      body: SafeArea(
        child: AccountPageBody(
          builder: (context, stack) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The hero card is replaced by the page title, not merely hidden:
              // it sat at the top of the scroll saying what the page was, which
              // is the job [AccountPageTitle] does on every other account page.
              // Keeping both would state it twice, once as a 200px slab.
              const AccountPageTitle(
                title: 'About GovPulse',
                subtitle:
                    'The official digital platform connecting Aparri citizens with '
                    'their local government.',
              ),
              ..._sections(480),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header — identical to ContactSupportScreen for consistency ─────────────
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
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(w * 0.025),
                border: Border.all(color: CitizenUi.sharedStroke),
              ),
              child: Icon(
                Icons.arrow_back_ios_rounded,
                size: w * 0.04,
                color: AppColors.primaryBlue,
              ),
            ),
          ),
          SizedBox(width: w * 0.035),
          Text(
            'About GovPulse',
            style: TextStyle(
              fontSize: w * 0.052,
              fontWeight: FontWeight.w700,
              color: AppColors.primaryBlue,
              letterSpacing: -0.3,
            ),
          ),
        ],
      ),
    );
  }

  // ── Hero / branding card ───────────────────────────────────────────────────
  Widget _buildHeroCard(double w) {
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
          // App logo
          Container(
            width: w * 0.22,
            height: w * 0.22,
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withValues(alpha: 0.08),
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.primaryBlue.withValues(alpha: 0.15),
                width: 1.5,
              ),
            ),
            child: ClipOval(
              child: Image.asset(
                'assets/images/newslogo.webp',
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => Icon(
                  Icons.account_balance_rounded,
                  size: w * 0.10,
                  color: AppColors.primaryBlue,
                ),
              ),
            ),
          ),
          SizedBox(height: w * 0.035),
          Text(
            'GovPulse',
            style: TextStyle(
              fontSize: w * 0.055,
              fontWeight: FontWeight.w800,
              color: AppColors.primaryBlue,
              letterSpacing: -0.5,
            ),
          ),
          SizedBox(height: w * 0.008),
          Text(
            'v$_appVersion',
            style: TextStyle(
              fontSize: w * 0.032,
              fontWeight: FontWeight.w500,
              color: AppColors.hint,
            ),
          ),
          SizedBox(height: w * 0.022),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: w * 0.04,
              vertical: w * 0.016,
            ),
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(w * 0.05),
              border: Border.all(
                color: AppColors.primaryBlue.withValues(alpha: 0.20),
              ),
            ),
            child: Text(
              'Local Government Unit of Aparri, Cagayan',
              style: TextStyle(
                fontSize: w * 0.030,
                fontWeight: FontWeight.w600,
                color: AppColors.primaryBlue,
              ),
            ),
          ),
          SizedBox(height: w * 0.025),
          Text(
            'Empowering citizens through transparent, accessible, and responsive local governance.',
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
  /// On web this becomes [AccountSectionLabel] — quiet grey small-caps rather
  /// than blue and bold, for the reason that widget documents: a label names
  /// the group below it and should be lighter than the content it names.
  ///
  /// It carries its own 10px bottom padding, which is why [_gapAfterLabel]
  /// contributes nothing on web.
  Widget _sectionLabel(double w, String text) {
    if (kIsWeb) return AccountSectionLabel(text);
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

  /// Space between a section label and the card under it.
  ///
  /// Zero on web because [AccountSectionLabel] already carries it. On mobile
  /// `kIsWeb` is a compile-time false, so this is exactly the `w * 0.02` that
  /// was written inline here before.
  Widget _gapAfterLabel(double w) => SizedBox(height: kIsWeb ? 0 : w * 0.02);

  /// Space between one section and the next. `w` is clamped to 480, so the
  /// mobile value is 24 — which is [kAccountSectionGap] exactly; the branch is
  /// here so the web page keeps following the constant if either ever moves.
  Widget _gapBetweenSections(double w) =>
      SizedBox(height: kIsWeb ? kAccountSectionGap : w * 0.05);

  // ── White rounded section container ────────────────────────────────────────
  Widget _buildCard(double w, List<Widget> children) {
    // Padding zero: the tiles inside draw their own insets and their own
    // hairlines, exactly as [AccountListSection] does for rows.
    if (kIsWeb) {
      return AccountCard(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      );
    }
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

  // ── Content tile (icon + title + body paragraph) ───────────────────────────
  Widget _buildBodyTile(
    double w, {
    required IconData icon,
    required Color color,
    required String title,
    required String body,
    bool showDivider = true,
  }) {
    // The `color` argument is dropped on web on purpose. Every heading on these
    // pages arrived with its own pastel tile, and fourteen of them down a
    // policy page is decoration competing with the prose. [AccountProseBlock]
    // draws one muted glyph instead, and caps the paragraph at a readable
    // measure — an 880px card would otherwise set a 130-character line.
    if (kIsWeb) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccountProseBlock(icon: icon, title: title, body: body),
          if (showDivider)
            const Divider(
              height: 1,
              thickness: 1,
              indent: 56,
              color: CitizenUi.border,
            ),
        ],
      );
    }
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: w * 0.04,
            vertical: w * 0.038,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: w * 0.105,
                height: w * 0.105,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(w * 0.025),
                  border: Border.all(
                    color: color.withValues(alpha: 0.25),
                    width: 1.2,
                  ),
                ),
                child: Icon(icon, size: w * 0.05, color: color),
              ),
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
                    SizedBox(height: w * 0.012),
                    Text(
                      body,
                      style: TextStyle(
                        fontSize: w * 0.032,
                        color: const Color(0xFF6B7280),
                        height: 1.55,
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

  // ── Info-only tile (label + value, no body paragraph) ─────────────────────
  Widget _buildInfoTile(
    double w, {
    required IconData icon,
    required Color color,
    required String title,
    required String value,
    bool showDivider = true,
  }) {
    // A label with a value on the right is exactly [AccountRow]'s second shape:
    // pass `trailing` and no `onTap`, and it draws no chevron, because this row
    // reports something rather than going somewhere.
    if (kIsWeb) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccountRow(
            icon: icon,
            title: title,
            trailing: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: CitizenUi.textMuted,
              ),
            ),
          ),
          if (showDivider)
            const Divider(
              height: 1,
              thickness: 1,
              indent: 56,
              color: CitizenUi.border,
            ),
        ],
      );
    }
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: w * 0.04,
            vertical: w * 0.034,
          ),
          child: Row(
            children: [
              Container(
                width: w * 0.105,
                height: w * 0.105,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(w * 0.025),
                  border: Border.all(
                    color: color.withValues(alpha: 0.25),
                    width: 1.2,
                  ),
                ),
                child: Icon(icon, size: w * 0.05, color: color),
              ),
              SizedBox(width: w * 0.035),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: w * 0.038,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF1F2937),
                  ),
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: w * 0.032,
                  color: AppColors.hint,
                  fontWeight: FontWeight.w500,
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

  // ── Footer branding card ───────────────────────────────────────────────────
  Widget _buildFooterCard(double w) {
    if (kIsWeb) {
      return const AccountNotice(
        stack: false,
        icon: Icons.favorite_outline_rounded,
        title: 'Built for Aparri',
        message:
            'GovPulse is built with care for the people of Aparri, Cagayan. '
            'For feedback or concerns, visit the Contact Support page.',
      );
    }
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
            Icons.favorite_outline_rounded,
            size: w * 0.045,
            color: AppColors.primaryBlue,
          ),
          SizedBox(width: w * 0.025),
          Expanded(
            child: Text(
              'GovPulse is built with care for the people of Aparri, Cagayan. '
              'For feedback or concerns, visit the Contact Support page.',
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
}
