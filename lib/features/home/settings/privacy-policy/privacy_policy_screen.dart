import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../../../../core/widgets/responsive_page.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/citizen_ui.dart';
import '../../../../core/widgets/Home/Account/account_web_kit.dart';
import '../../../../core/theme/mobile_metrics.dart';
import '../../../../core/widgets/app_back_chevron.dart';

class PrivacyPolicyScreen extends StatefulWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  State<PrivacyPolicyScreen> createState() => _PrivacyPolicyScreenState();
}

class _PrivacyPolicyScreenState extends State<PrivacyPolicyScreen>
    with SingleTickerProviderStateMixin {
  // ── Content slide-up animation (mirrors TermsOfServiceScreen) ──────────────
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
        shellTitle: 'Privacy Policy',
        shellSubtitle:
            'How GovPulse collects, uses, and protects your personal data.',
        shellIcon: Icons.privacy_tip_rounded,
        shellHighlights: const [
          (Icons.lock_rounded, 'Your data is encrypted & secure'),
          (Icons.visibility_off_rounded, 'We never sell your information'),
          (Icons.manage_accounts_rounded, 'You control your data'),
        ],
        shellContentWidth: 640,
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

  // ── Header — identical to ContactSupportScreen / TermsOfServiceScreen ───────
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
    if (!kIsWeb) ...[_buildIntroCard(w), _gapBetweenSections(w)],
    _sectionLabel(w, 'INFORMATION WE COLLECT'),
    _gapAfterLabel(w),
    _buildCard(w, [
      _buildBodyTile(
        w,
        icon: Icons.person_outline_rounded,
        color: AppColors.primaryBlue,
        title: 'Personal Information',
        body:
            'When you register, we collect your full name, email address, phone number, date of birth, and home address to create and verify your citizen account.',
      ),
      _buildBodyTile(
        w,
        icon: Icons.badge_outlined,
        color: AppColors.primaryBlue,
        title: 'Identity Verification Data',
        body:
            'To verify your identity, we collect a government-issued ID image and a face scan photo. These are stored securely and used solely for verification purposes.',
      ),
      _buildBodyTile(
        w,
        icon: Icons.photo_camera_outlined,
        color: AppColors.primaryBlue,
        title: 'User-Generated Content',
        body:
            'Reports, suggestions, feedback, community posts, and any media you upload (photos, files) are collected and stored as part of your civic activity record.',
        showDivider: false,
      ),
    ]),
    _gapBetweenSections(w),
    _sectionLabel(w, 'HOW WE USE YOUR INFORMATION'),
    _gapAfterLabel(w),
    _buildCard(w, [
      _buildBodyTile(
        w,
        icon: Icons.account_balance_outlined,
        color: AppColors.green,
        title: 'Service Delivery',
        body:
            'Your information is used to operate GovPulse, process your civic submissions, facilitate LGU responses, and provide you with relevant notifications and updates.',
      ),
      _buildBodyTile(
        w,
        icon: Icons.insights_rounded,
        color: AppColors.green,
        title: 'Service Improvement',
        body:
            'Aggregated and anonymized data may be used to analyze usage patterns, improve application features, and enhance the quality of public services delivered by the LGU.',
      ),
      _buildBodyTile(
        w,
        icon: Icons.notifications_none_rounded,
        color: AppColors.green,
        title: 'Communications',
        body:
            'We may use your contact details to send you status updates on your reports or suggestions, important announcements from the LGU, or alerts relevant to your barangay.',
        showDivider: false,
      ),
    ]),
    _gapBetweenSections(w),
    _sectionLabel(w, 'DATA SHARING & DISCLOSURE'),
    _gapAfterLabel(w),
    _buildCard(w, [
      _buildBodyTile(
        w,
        icon: Icons.share_outlined,
        color: AppColors.orange,
        title: 'Within the LGU',
        body:
            'Your submissions may be shared with relevant LGU departments and barangay officials solely for the purpose of processing and responding to your civic concerns.',
      ),
      _buildBodyTile(
        w,
        icon: Icons.business_outlined,
        color: AppColors.orange,
        title: 'Third-Party Services',
        body:
            'We use trusted third-party providers (such as cloud infrastructure and identity verification services) who process data strictly on our behalf and under confidentiality agreements.',
      ),
      _buildBodyTile(
        w,
        icon: Icons.gavel_rounded,
        color: AppColors.orange,
        title: 'Legal Requirements',
        body:
            'We may disclose your information if required by Philippine law, court order, or other governmental authority, or where necessary to protect the rights and safety of others.',
        showDivider: false,
      ),
    ]),
    _gapBetweenSections(w),
    _sectionLabel(w, 'DATA RETENTION & SECURITY'),
    _gapAfterLabel(w),
    _buildCard(w, [
      _buildBodyTile(
        w,
        icon: Icons.lock_outline_rounded,
        color: AppColors.primaryBlue,
        title: 'Security Measures',
        body:
            'We implement industry-standard security measures including encrypted storage, row-level access controls, and secure transmission protocols to protect your personal data.',
      ),
      _buildBodyTile(
        w,
        icon: Icons.history_rounded,
        color: AppColors.primaryBlue,
        title: 'Retention Period',
        body:
            'Your account data is retained for as long as your account remains active. Upon account deletion, personal data is removed within 30 days, except where retention is required by law.',
        showDivider: false,
      ),
    ]),
    _gapBetweenSections(w),
    _sectionLabel(w, 'YOUR RIGHTS'),
    _gapAfterLabel(w),
    _buildCard(w, [
      _buildBodyTile(
        w,
        icon: Icons.visibility_outlined,
        color: AppColors.green,
        title: 'Right to Access',
        body:
            'Under the Data Privacy Act of 2012, you have the right to request access to the personal data we hold about you at any time through the Contact Support page.',
      ),
      _buildBodyTile(
        w,
        icon: Icons.edit_outlined,
        color: AppColors.green,
        title: 'Right to Correction',
        body:
            'You may update your personal information directly through the Edit Profile screen. For data that cannot be self-corrected, contact support to request an amendment.',
      ),
      _buildBodyTile(
        w,
        icon: Icons.delete_outline_rounded,
        color: AppColors.red,
        title: 'Right to Erasure',
        body:
            'You may request deletion of your account and associated personal data by contacting the LGU. Note that certain records tied to official civic submissions may be retained as required by law.',
        showDivider: false,
      ),
    ]),
    _gapBetweenSections(w),
    _buildEffectiveNote(w),
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
              AccountPageTitle(
                // Pushed by `pushLegacy` from Settings, which writes no URL — so
                // the rail still reads Settings and the browser's Back button
                // leaves the account area rather than closing this page. Without
                // a door here there is no way out at all.
                onBack: () => Navigator.pop(context),
                backLabel: 'Back to Settings',
                title: 'Privacy Policy',
                subtitle:
                    'How GovPulse collects, uses and protects your personal '
                    'information.',
              ),
              ..._sections(480),
            ],
          ),
        ),
      ),
    );
  }

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
            'Privacy Policy',
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
            child: Icon(
              Icons.shield_outlined,
              size: w * 0.085,
              color: AppColors.primaryBlue,
            ),
          ),
          SizedBox(height: w * 0.035),
          Text(
            'Your Privacy Matters',
            style: TextStyle(
              fontSize: w * 0.046,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1F2937),
            ),
          ),
          SizedBox(height: w * 0.018),
          Text(
            'This policy explains how the Local Government Unit of Aparri, Cagayan '
            'collects, uses, and protects your personal information when you use GovPulse.',
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

  // ── Content tile (icon + title + body text) ────────────────────────────────
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

  // ── Effective date note ────────────────────────────────────────────────────
  Widget _buildEffectiveNote(double w) {
    if (kIsWeb) {
      // `stack` only changes how a TRAILING widget is placed, and this notice
      // has none, so the value is immaterial here.
      return AccountNotice(
        stack: false,
        icon: Icons.info_outline_rounded,
        title: 'Effective June 2025',
        message:
            'This policy is governed by the Philippine Data Privacy Act of '
            '2012 (RA 10173). For privacy concerns, contact the LGU of '
            'Aparri through the Contact Support page.',
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
            Icons.info_outline_rounded,
            size: w * 0.045,
            color: AppColors.primaryBlue,
          ),
          SizedBox(width: w * 0.025),
          Expanded(
            child: Text(
              'Effective Date: June 2025. This policy is governed by the Philippine '
              'Data Privacy Act of 2012 (RA 10173). For privacy concerns, contact '
              'the LGU of Aparri through the Contact Support page.',
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
