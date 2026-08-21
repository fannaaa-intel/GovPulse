import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../../../../core/widgets/responsive_page.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/citizen_ui.dart';
import '../../../../core/widgets/Home/Account/account_web_kit.dart';
import '../../../../core/theme/mobile_metrics.dart';

class TermsOfServiceScreen extends StatefulWidget {
  const TermsOfServiceScreen({super.key});

  @override
  State<TermsOfServiceScreen> createState() => _TermsOfServiceScreenState();
}

class _TermsOfServiceScreenState extends State<TermsOfServiceScreen>
    with SingleTickerProviderStateMixin {
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
        shellTitle: 'Terms of Service',
        shellSubtitle:
            'The rules and guidelines for using GovPulse as an Aparri citizen.',
        shellIcon: Icons.description_rounded,
        shellHighlights: const [
          (Icons.gavel_rounded, 'Your rights and responsibilities'),
          (Icons.verified_user_rounded, 'Account & verification rules'),
          (Icons.handshake_rounded, 'Fair and respectful use'),
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
    _sectionLabel(w, 'ACCEPTANCE OF TERMS'),
    _gapAfterLabel(w),
    _buildCard(w, [
      _buildBodyTile(
        w,
        icon: Icons.handshake_outlined,
        color: AppColors.primaryBlue,
        title: 'Agreement to Use',
        body:
            'By accessing or using GovPulse, you agree to be bound by these Terms of Service and all applicable laws. If you do not agree, you are not authorized to use this application.',
      ),
      _buildBodyTile(
        w,
        icon: Icons.update_rounded,
        color: AppColors.primaryBlue,
        title: 'Changes to Terms',
        body:
            'The Local Government Unit of Aparri, Cagayan reserves the right to modify these terms at any time. Continued use of the application after changes are posted constitutes your acceptance of the revised terms.',
        showDivider: false,
      ),
    ]),
    _gapBetweenSections(w),
    _sectionLabel(w, 'ELIGIBILITY & ACCOUNTS'),
    _gapAfterLabel(w),
    _buildCard(w, [
      _buildBodyTile(
        w,
        icon: Icons.person_outline_rounded,
        color: AppColors.green,
        title: 'Who May Register',
        body:
            'GovPulse is available to residents of Aparri, Cagayan who are at least 18 years of age and possess a valid government-issued ID for identity verification.',
      ),
      _buildBodyTile(
        w,
        icon: Icons.verified_user_outlined,
        color: AppColors.green,
        title: 'Account Responsibility',
        body:
            'You are responsible for maintaining the confidentiality of your account credentials and for all activities that occur under your account. Notify the LGU immediately of any unauthorized access.',
        showDivider: false,
      ),
    ]),
    _gapBetweenSections(w),
    _sectionLabel(w, 'ACCEPTABLE USE'),
    _gapAfterLabel(w),
    _buildCard(w, [
      _buildBodyTile(
        w,
        icon: Icons.thumb_up_alt_outlined,
        color: AppColors.primaryBlue,
        title: 'Permitted Activities',
        body:
            'You may use GovPulse to submit legitimate civic concerns, view community news, engage with LGU services, and interact with other verified citizens in a respectful manner.',
      ),
      _buildBodyTile(
        w,
        icon: Icons.block_outlined,
        color: AppColors.red,
        title: 'Prohibited Activities',
        body:
            'You must not submit false or misleading reports, impersonate other persons, engage in harassment or hate speech, attempt to gain unauthorized access to LGU systems, or use the application for any unlawful purpose.',
        showDivider: false,
      ),
    ]),
    _gapBetweenSections(w),
    _sectionLabel(w, 'CONTENT & PRIVACY'),
    _gapAfterLabel(w),
    _buildCard(w, [
      _buildBodyTile(
        w,
        icon: Icons.photo_library_outlined,
        color: AppColors.orange,
        title: 'User-Submitted Content',
        body:
            'By submitting reports, photos, or community posts, you grant the LGU a non-exclusive license to use that content for public service purposes. You retain ownership of your content.',
      ),
      _buildBodyTile(
        w,
        icon: Icons.lock_outline_rounded,
        color: AppColors.orange,
        title: 'Data & Privacy',
        body:
            'Your personal information is collected and processed in accordance with our Privacy Policy and the Philippine Data Privacy Act of 2012 (Republic Act No. 10173). We do not sell your personal data to third parties.',
        showDivider: false,
      ),
    ]),
    _gapBetweenSections(w),
    _sectionLabel(w, 'LIABILITY & ENFORCEMENT'),
    _gapAfterLabel(w),
    _buildCard(w, [
      _buildBodyTile(
        w,
        icon: Icons.gavel_rounded,
        color: AppColors.primaryBlue,
        title: 'Limitation of Liability',
        body:
            'The LGU of Aparri shall not be liable for any indirect, incidental, or consequential damages arising from your use of GovPulse. The application is provided "as is" without warranty of any kind.',
      ),
      _buildBodyTile(
        w,
        icon: Icons.warning_amber_rounded,
        color: AppColors.red,
        title: 'Account Suspension',
        body:
            'The LGU reserves the right to suspend or terminate accounts that violate these terms, submit fraudulent reports, or engage in conduct detrimental to the civic community.',
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
                title: 'Terms of Service',
                subtitle:
                    'The rules and guidelines for using GovPulse as an Aparri '
                    'citizen.',
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
            'Terms of Service',
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
              Icons.description_outlined,
              size: w * 0.085,
              color: AppColors.primaryBlue,
            ),
          ),
          SizedBox(height: w * 0.035),
          Text(
            'Terms of Service',
            style: TextStyle(
              fontSize: w * 0.046,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1F2937),
            ),
          ),
          SizedBox(height: w * 0.018),
          Text(
            'Please read these terms carefully before using GovPulse. '
            'They govern your use of the civic engagement platform provided by the '
            'Local Government Unit of Aparri, Cagayan.',
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
            'For questions about these terms, contact the LGU of Aparri '
            'through the Contact Support page.',
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
              'Effective Date: June 2025. For questions about these terms, '
              'please contact the LGU of Aparri through the Contact Support page.',
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
