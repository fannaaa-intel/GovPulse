import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../../core/widgets/responsive_page.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/citizen_ui.dart';
import '../../../core/widgets/Home/Account/account_web_kit.dart';
import '../../../core/constants/aparri_barangays.dart';
import '../../../core/widgets/loading/loading_overlay.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/widgets/app_snackbar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/user_profile_provider.dart';
import '../../../core/theme/mobile_metrics.dart';
import '../../../core/widgets/app_back_chevron.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  final String username;

  const EditProfileScreen({super.key, required this.username});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen>
    with TickerProviderStateMixin {
  // ── Animation ─────────────────────────────────────────────────────────────
  late final AnimationController _slideCtrl;
  late final Animation<Offset> _slideAnim;
  late final Animation<double> _fadeAnim;

  // ── Form ──────────────────────────────────────────────────────────────────
  final _formKey = GlobalKey<FormState>();
  final _firstNameCtrl = TextEditingController();
  final _middleNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _barangayCtrl = TextEditingController();
  final _streetCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();

  // ── State ─────────────────────────────────────────────────────────────────
  bool _loading = true;
  bool _saving = false;
  bool _isVerified = false;
  String? _errorMessage;

  // ── Stats ─────────────────────────────────────────────────────────────────
  int _reportCount = 0;
  String? _memberSince;
  String? _barangay;

  // ── Photo ─────────────────────────────────────────────────────────────────
  String? _currentPhotoUrl;
  String? _currentPhotoPath;
  String? _facePhotoPath;
  File? _pickedFile;
  Uint8List? _pickedBytes;

  // ── 30-day lock ───────────────────────────────────────────────────────────
  DateTime? _lastProfileUpdatedAt;
  bool get _isLocked {
    if (_lastProfileUpdatedAt == null) return false;
    return DateTime.now().difference(_lastProfileUpdatedAt!).inDays < 30;
  }

  int get _daysRemaining {
    if (_lastProfileUpdatedAt == null) return 0;
    final diff = 30 - DateTime.now().difference(_lastProfileUpdatedAt!).inDays;
    return diff.clamp(0, 30);
  }

  @override
  void initState() {
    super.initState();
    _isVerified = true;
    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutQuart));
    _fadeAnim = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOut));
    _loadData();
  }

  @override
  void dispose() {
    _slideCtrl.dispose();
    _firstNameCtrl.dispose();
    _middleNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _barangayCtrl.dispose();
    _streetCtrl.dispose();
    _contactCtrl.dispose();
    super.dispose();
  }

  // ── Load data ─────────────────────────────────────────────────────────────
  Future<void> _loadData() async {
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      if (user == null) {
        setState(() => _loading = false);
        return;
      }

      final verifRow = await supabase
          .from('verification_submissions')
          .select('status, face_photo_path')
          .eq('user_id', user.id)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      final status = verifRow?['status'] as String? ?? 'none';
      final verified = status == 'approved';

      if (verified) {
        final cd = await supabase
            .from('citizen_details')
            .select(
              'first_name, middle_name, last_name, '
              'contact_number, barangay, street, '
              'created_at, profile_photo_path, last_profile_updated_at',
            )
            .eq('user_id', user.id)
            .maybeSingle();

        if (cd != null) {
          _firstNameCtrl.text = cd['first_name'] as String? ?? '';
          _middleNameCtrl.text = cd['middle_name'] as String? ?? '';
          _lastNameCtrl.text = cd['last_name'] as String? ?? '';
          _contactCtrl.text = cd['contact_number'] as String? ?? '';
          _streetCtrl.text = cd['street'] as String? ?? '';

          final barangayVal = cd['barangay'] as String? ?? '';
          _barangayCtrl.text = barangayVal;
          _barangay = barangayVal;

          final createdRaw = cd['created_at'];
          if (createdRaw != null) {
            final dt = DateTime.tryParse(createdRaw.toString());
            if (dt != null) _memberSince = dt.year.toString();
          }

          final updatedRaw = cd['last_profile_updated_at'];
          if (updatedRaw != null) {
            _lastProfileUpdatedAt = DateTime.tryParse(updatedRaw.toString());
          }

          _facePhotoPath = verifRow?['face_photo_path'] as String?;

          final photoPath =
              (cd['profile_photo_path'] as String?)?.isNotEmpty == true
              ? cd['profile_photo_path'] as String
              : null;

          if (photoPath != null && photoPath.isNotEmpty) {
            _currentPhotoPath = photoPath;
            _currentPhotoUrl = supabase.storage
                .from('profile-photos')
                .getPublicUrl(photoPath);
          }
        }

        try {
          final countRes = await supabase
              .from('reports')
              .select('id')
              .eq('user_id', user.id);
          _reportCount = (countRes as List).length;
        } catch (_) {
          _reportCount = 0;
        }
      }

      if (mounted) {
        setState(() {
          _isVerified = true;
          _loading = false;
        });
        _slideCtrl.forward();
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Pick photo ────────────────────────────────────────────────────────────
  Future<void> _pickPhoto() async {
    if (_isLocked) return;
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 800,
    );
    if (picked == null) return;

    final file = File(picked.path);
    final bytes = await file.readAsBytes();
    setState(() {
      _pickedFile = file;
      _pickedBytes = bytes;
    });
  }

  // ── Save ──────────────────────────────────────────────────────────────────
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isLocked) return;

    setState(() {
      _saving = true;
      _errorMessage = null;
    });

    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      if (user == null) throw 'Not authenticated';

      String? newPhotoPath;

      if (_pickedFile != null && _pickedBytes != null) {
        final ext = _pickedFile!.path.split('.').last;
        final filePath =
            '${user.id}/profile_${DateTime.now().millisecondsSinceEpoch}.$ext';

        String mimeType;
        switch (ext.toLowerCase()) {
          case 'jpg':
          case 'jpeg':
            mimeType = 'image/jpeg';
            break;
          case 'png':
            mimeType = 'image/png';
            break;
          case 'webp':
            mimeType = 'image/webp';
            break;
          default:
            mimeType = 'image/jpeg';
        }

        await supabase.storage
            .from('profile-photos')
            .uploadBinary(
              filePath,
              _pickedBytes!,
              fileOptions: FileOptions(contentType: mimeType, upsert: true),
            );
        newPhotoPath = filePath;
      }

      final now = DateTime.now().toUtc().toIso8601String();
      final updateData = <String, dynamic>{
        'first_name': _firstNameCtrl.text.trim(),
        'middle_name': _middleNameCtrl.text.trim(),
        'last_name': _lastNameCtrl.text.trim(),
        'barangay': _barangayCtrl.text.trim(),
        'street': _streetCtrl.text.trim(),
        'contact_number': _contactCtrl.text.trim(),
        'last_profile_updated_at': now,
      };
      if (newPhotoPath != null) {
        updateData['profile_photo_path'] = newPhotoPath;
        if (_currentPhotoPath != null) {
          await CachedNetworkImage.evictFromCache(_currentPhotoPath!);
          final isFaceScan = _currentPhotoPath == _facePhotoPath;
          if (!isFaceScan) {
            try {
              await supabase.storage.from('profile-photos').remove([
                _currentPhotoPath!,
              ]);
            } catch (_) {}
          }
        }
        _currentPhotoPath = newPhotoPath;
      }
      await supabase
          .from('citizen_details')
          .update(updateData)
          .eq('user_id', user.id);

      if (!mounted) return;
      showAppSnackBar(
        context,
        "Profile updated successfully.",
        type: AppSnackType.success,
      );
      ref.read(userProfileProvider.notifier).refresh();

      // ── Web STAYS on the page; the app still pops ────────────────────────
      //
      // Popping is right on a phone: Edit Profile is a whole screen you pushed,
      // and finishing means going back to the one you came from.
      //
      // On web it was two bad things at once. The page is a pane in a shell, so
      // popping dumped you on Settings — a destination you did not ask for —
      // and because `_saving` stays true through a pop that never completes for
      // an unmounting route, the last thing you saw was the whole form greyed
      // out under a spinner while the address bar had already moved on.
      //
      // Staying puts the outcome where the action was: the snackbar confirms
      // it, the fields keep what you typed, and the 30-day lock that the save
      // just started is visible immediately rather than on your next visit.
      if (kIsWeb) {
        setState(() {
          _saving = false;
          // The row now carries this timestamp, so the banner and the disabled
          // fields must agree with the database without a refetch.
          _lastProfileUpdatedAt = DateTime.now();
        });
        return;
      }
      Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to save changes. Please try again.';
        _saving = false;
      });
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // ── The browser always gets the web layout. There is no width test ───────
    //
    // `kIsWeb` alone, and that is the whole rule: the MOBILE APP never takes
    // this branch, and a browser always does.
    //
    // It was `kIsWeb && rawWidth >= 900`, then `>= 600`, and both were wrong in
    // the same way — they handed narrow BROWSERS the phone layout. That layout
    // is built for the app: proportional type, three stat tiles, a back chevron
    // for a screen you pushed. In a browser none of that holds. The chevron in
    // particular is answering a question nobody asked, because the shell's own
    // chrome — the drawer at this width, the rail above it — already says where
    // you are and how to leave.
    //
    // The web layout does not need the rescue anyway: it collapses to one field
    // per row below [_kWebStackBelow], so it handles 400px perfectly well, and
    // it does it with real inputs rather than a 480px column stranded in the
    // middle of the page.
    //
    // [width] is still computed for the handful of mobile builders the web
    // layout borrows (the not-verified state), and is otherwise unused there —
    // the web layout measures itself with a LayoutBuilder.
    final bool wide = kIsWeb;
    final double width = wide ? 460.0 : uiScaleWidth(context);

    if (wide) {
      // ── No LoadingOverlay here, deliberately ──────────────────────────────
      //
      // The mobile branch below still wraps in one, and on a phone that is
      // right: the screen IS the task, so blocking all of it while the task
      // runs is honest.
      //
      // On web the page is a pane inside a shell that stays interactive around
      // it, and a full-page scrim over a form you already filled in reads as a
      // fault rather than as progress — the barrier greys your own answers back
      // at you and hides the thing you just pressed. The busy state belongs in
      // the control that started it, so Save carries the spinner and the fields
      // disable themselves; see [_buildWebActions].
      //
      // The initial LOAD still gets the skeleton. That is a different state:
      // there is no content to obscure yet.
      return Scaffold(
        backgroundColor: CitizenUi.pageBg,
        body: SafeArea(
          // Not SkeletonLayout.editProfile. That one draws the MOBILE screen —
          // a centred avatar over stacked bars — and since the web layout
          // stopped being the mobile layout it has been promising a shape that
          // never arrives, so the page visibly rearranged itself on load.
          //
          // [AccountPageSkeleton] is built from the same [AccountPageBody] and
          // [AccountCard] this page is, and its `sections` argument mirrors the
          // AccountFieldSection calls below one for one: Account is one row of
          // two, Personal one row of three, Contact and Address one row each.
          child: _loading
              ? const AccountPageSkeleton(
                  banner: true,
                  sections: [
                    [2],
                    [3],
                    [1],
                    [1],
                    [1],
                  ],
                  actions: true,
                )
              : _buildEditProfileWebBody(width),
        ),
      );
    }

    return LoadingOverlay(
      isLoading: _saving,
      child: Scaffold(
        backgroundColor: const Color(0xFFF3F4F6),
        body: ResponsivePageBody(
          maxWidth: 600,
          child: SafeArea(
            child: Column(
              children: [
                _buildHeader(width),
                Expanded(
                  child: LoadingOverlay.bodyOrSkeleton(
                    isLoading: _loading,
                    layout: SkeletonLayout.editProfile,
                    child: FadeTransition(
                      opacity: _fadeAnim,
                      child: SlideTransition(
                        position: _slideAnim,
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          padding: EdgeInsets.fromLTRB(
                            width * 0.04,
                            width * 0.02,
                            width * 0.04,
                            width * 0.08,
                          ),
                          child: _isVerified
                              ? _buildForm(width)
                              : _buildNotVerifiedState(width),
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
  }

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _buildHeader(double width) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        width * 0.04,
        width * 0.04,
        width * 0.04,
        width * 0.035,
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
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: width * 0.09,
              height: width * 0.09,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(width * 0.025),
                border: Border.all(color: kBackChevronBorder),
              ),
              child: Icon(
                Icons.arrow_back_ios_new_rounded,
                size: width * 0.046,
                color: kBackChevronGlyph,
              ),
            ),
          ),
          SizedBox(width: width * 0.035),
          Text(
            'Edit Profile',
            style: TextStyle(
              fontSize: width * 0.052,
              fontWeight: FontWeight.w700,
              color: kScreenTitleColor,
              letterSpacing: -0.3,
            ),
          ),
        ],
      ),
    );
  }

  // ── Not verified ──────────────────────────────────────────────────────────
  Widget _buildNotVerifiedState(double width) {
    return Column(
      children: [
        SizedBox(height: width * 0.08),
        Container(
          padding: EdgeInsets.all(width * 0.06),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(width * 0.04),
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
                width: width * 0.22,
                height: width * 0.22,
                decoration: BoxDecoration(
                  color: AppColors.orange.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.verified_user_outlined,
                  size: width * 0.12,
                  color: AppColors.orange,
                ),
              ),
              SizedBox(height: width * 0.05),
              Text(
                'Verification Required',
                style: TextStyle(
                  fontSize: width * 0.048,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1F2937),
                ),
              ),
              SizedBox(height: width * 0.025),
              Text(
                'Only verified citizens can edit their profile information. '
                'Please complete the identity verification process first.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: width * 0.034,
                  color: AppColors.hint,
                  height: 1.55,
                ),
              ),
              SizedBox(height: width * 0.055),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    elevation: 0,
                    padding: EdgeInsets.symmetric(vertical: width * 0.04),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(width * 0.03),
                    ),
                  ),
                  child: Text(
                    'Go Back',
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
        ),
      ],
    );
  }

  // ── Main form ─────────────────────────────────────────────────────────────
  Widget _buildForm(double width) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildProfileSummary(width),
        SizedBox(height: width * 0.04),
        _buildFormFields(width),
      ],
    );
  }

  // Profile summary (avatar + lock banner). Its own left column on web.
  Widget _buildProfileSummary(double width) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildAvatarCard(width),
        if (_isLocked) ...[
          SizedBox(height: width * 0.04),
          _buildLockBanner(width),
        ],
      ],
    );
  }

  // Editable fields (wrapped in the Form). Right column on web.
  Widget _buildFormFields(double width) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionLabel('ACCOUNT', width),
          SizedBox(height: width * 0.02),
          _buildCard(
            width: width,
            children: [
              _buildLockedDisplayField(
                label: 'Email',
                value: Supabase.instance.client.auth.currentUser?.email ?? '—',
                icon: 'assets/images/email.webp',
                width: width,
              ),
              _divider(width),
              _buildLockedDisplayField(
                label: 'Username',
                value: widget.username,
                icon: '@',
                width: width,
              ),
            ],
          ),
          SizedBox(height: width * 0.04),

          _buildSectionLabel('PERSONAL INFORMATION', width),
          SizedBox(height: width * 0.02),
          _buildCard(
            width: width,
            children: [
              _buildField(
                ctrl: _firstNameCtrl,
                label: 'First Name',
                hint: 'Enter first name',
                icon: 'assets/images/username.webp',
                width: width,
                enabled: !_isLocked,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              _divider(width),
              _buildField(
                ctrl: _middleNameCtrl,
                label: 'Middle Name',
                hint: 'Enter middle name (optional)',
                icon: 'assets/images/username.webp',
                width: width,
                enabled: !_isLocked,
              ),
              _divider(width),
              _buildField(
                ctrl: _lastNameCtrl,
                label: 'Last Name',
                hint: 'Enter last name',
                icon: 'assets/images/username.webp',
                width: width,
                enabled: !_isLocked,
                showDivider: false,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
            ],
          ),
          SizedBox(height: width * 0.04),

          _buildSectionLabel('CONTACT', width),
          SizedBox(height: width * 0.02),
          _buildCard(
            width: width,
            children: [
              _buildField(
                ctrl: _contactCtrl,
                label: 'Mobile Number',
                hint: 'e.g. 09XXXXXXXXX',
                icon: 'assets/images/phone.webp',
                width: width,
                enabled: !_isLocked,
                showDivider: false,
                keyboardType: TextInputType.phone,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  if (!RegExp(r'^(09|\+639)\d{9}$').hasMatch(v.trim())) {
                    return 'Enter a valid PH mobile number';
                  }
                  return null;
                },
              ),
            ],
          ),
          SizedBox(height: width * 0.04),

          _buildSectionLabel('ADDRESS', width),
          SizedBox(height: width * 0.02),
          _buildCard(
            width: width,
            children: [
              _buildBarangayField(width),
              _divider(width),
              _buildField(
                ctrl: _streetCtrl,
                label: 'Street / Zone',
                hint: 'Enter street or zone',
                icon: 'assets/images/report/location.webp',
                width: width,
                enabled: !_isLocked,
                showDivider: false,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
            ],
          ),
          SizedBox(height: width * 0.04),

          if (_errorMessage != null)
            Container(
              margin: EdgeInsets.only(bottom: width * 0.03),
              padding: EdgeInsets.all(width * 0.035),
              decoration: BoxDecoration(
                color: AppColors.red.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(width * 0.025),
                border: Border.all(color: AppColors.red.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    color: AppColors.red,
                    size: width * 0.045,
                  ),
                  SizedBox(width: width * 0.025),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(
                        fontSize: width * 0.032,
                        color: AppColors.red,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (_saving || _isLocked) ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                disabledBackgroundColor: AppColors.primaryBlue.withValues(
                  alpha: 0.4,
                ),
                elevation: 0,
                padding: EdgeInsets.symmetric(vertical: width * 0.045),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(width * 0.03),
                ),
              ),
              child: Text(
                _isLocked ? 'Profile Locked' : 'Save Changes',
                style: TextStyle(
                  fontSize: width * 0.042,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ),
          SizedBox(height: width * 0.03),

          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _saving ? null : () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: CitizenUi.sharedStroke),
                padding: EdgeInsets.symmetric(vertical: width * 0.04),
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
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  WEB LAYOUT
  //
  //  Reached only from the `wide` branch of build(), which is `kIsWeb`. The
  //  mobile builders above are untouched and still serve the app.
  //
  //  ── Why it is not the mobile form in a wider box ──────────────────────────
  //  It was, and that was the bug. The mobile builders size EVERYTHING off the
  //  page width — `width * 0.055` type, `width * 0.04` padding — which is a
  //  sound way to scale one column across phone sizes and a nonsensical one on
  //  a desktop page, where the width is 1600 and the text should not be 88pt.
  //  The rows it produces also read as a settings LIST: an icon in a rounded
  //  square, a caption, a value, no border. Nothing about them says "type
  //  here", which on a screen whose entire purpose is typing is the problem.
  //
  //  ── The layout lives in the kit, not here ────────────────────────────────
  //  Page width, the title block, the shape of a card and a field, where the
  //  buttons go and when to stop being two columns all come from
  //  account_web_kit.dart, which the other four ACCOUNT pages build from too.
  //  What stays in this file is what is genuinely Edit Profile's: which fields
  //  exist, what validates them, the identity banner and the 30-day lock.
  //
  //  All of it shares STATE with the mobile path — same controllers, same
  //  validators, same [_save], same lock — so there is one source of truth for
  //  what a profile is and two ways of drawing it.
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildEditProfileWebBody(double width) {
    return AccountPageBody(
      builder: (context, stack) => FadeTransition(
        opacity: _fadeAnim,
        child: SlideTransition(
          position: _slideAnim,
          child: _isVerified
              ? _buildWebForm(stack: stack)
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: _buildNotVerifiedState(480),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildWebForm({required bool stack}) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AccountPageTitle(
            title: 'Edit Profile',
            subtitle:
                'Keep your details current so the barangay can reach you '
                'about your reports.',
          ),
          _buildWebIdentityBanner(stack: stack),
          if (_isLocked) ...[
            const SizedBox(height: 16),
            _buildWebLockNotice(stack: stack),
          ],
          const SizedBox(height: 28),

          AccountFieldSection(
            title: 'Account',
            stack: stack,
            rows: [
              [
                AccountReadonlyField(
                  label: 'Email',
                  value:
                      Supabase.instance.client.auth.currentUser?.email ?? '—',
                ),
                AccountReadonlyField(label: 'Username', value: widget.username),
              ],
            ],
          ),
          const SizedBox(height: kAccountSectionGap),

          AccountFieldSection(
            title: 'Personal information',
            stack: stack,
            rows: [
              [
                _webField(
                  ctrl: _firstNameCtrl,
                  label: 'First name',
                  hint: 'Enter first name',
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                _webField(
                  ctrl: _middleNameCtrl,
                  label: 'Middle name',
                  hint: 'Optional',
                ),
                _webField(
                  ctrl: _lastNameCtrl,
                  label: 'Last name',
                  hint: 'Enter last name',
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
              ],
            ],
          ),
          const SizedBox(height: kAccountSectionGap),

          AccountFieldSection(
            title: 'Contact',
            stack: stack,
            rows: [
              [
                _webField(
                  ctrl: _contactCtrl,
                  label: 'Mobile number',
                  hint: 'e.g. 09XXXXXXXXX',
                  keyboardType: TextInputType.phone,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Required';
                    if (!RegExp(r'^(09|\+639)\d{9}$').hasMatch(v.trim())) {
                      return 'Enter a valid PH mobile number';
                    }
                    return null;
                  },
                ),
                // Holds the second column open so a lone phone number keeps a
                // sensible input width instead of stretching across the page.
                const SizedBox.shrink(),
              ],
            ],
          ),
          const SizedBox(height: kAccountSectionGap),

          AccountFieldSection(
            title: 'Address',
            stack: stack,
            rows: [
              [_buildWebBarangayField(), const SizedBox.shrink()],
              [
                _webField(
                  ctrl: _streetCtrl,
                  label: 'Street / Zone',
                  hint: 'Enter street or zone',
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox.shrink(),
              ],
            ],
          ),

          if (_errorMessage != null) ...[
            const SizedBox(height: 20),
            AccountErrorStrip(_errorMessage!),
          ],

          const SizedBox(height: 28),
          AccountActions(
            stack: stack,
            busy: _saving,
            primaryLabel: _isLocked ? 'Profile Locked' : 'Save Changes',
            onPrimary: (_saving || _isLocked) ? null : _save,
            secondaryLabel: 'Cancel',
            onSecondary: _saving ? null : () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  /// [AccountTextField] with this screen's two standing rules applied: nothing
  /// is editable while locked or while a save is in flight, and every keystroke
  /// rebuilds so the identity banner can show the name as it is typed.
  Widget _webField({
    required TextEditingController ctrl,
    required String label,
    required String hint,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
  }) {
    return AccountTextField(
      controller: ctrl,
      label: label,
      hint: hint,
      enabled: !_isLocked && !_saving,
      validator: validator,
      keyboardType: keyboardType,
      // Only the two name fields feed the banner, but the cost of an empty
      // setState on the others is a rebuild of one form.
      onChanged: (_) => setState(() {}),
    );
  }

  /// A real select, not the mobile bottom-sheet picker.
  ///
  /// The sheet exists because a phone has no room for 41 options; a desktop
  /// dropdown does, and it keeps the field looking and behaving like the inputs
  /// on either side of it. [_barangayCtrl] stays mirrored either way, because
  /// that is what [_save] reads.
  ///
  /// ── initialValue is read ONCE, and that is fine here ─────────────────────
  /// [FormField.didUpdateWidget] does not re-read `initialValue`, so a value
  /// that arrived after this field mounted would never show. It cannot: while
  /// `_loading` is true `LoadingOverlay.bodyOrSkeleton` returns the SKELETON
  /// INSTEAD OF this subtree — not alongside it — so the form first mounts
  /// after [_loadData] has filled [_barangayCtrl].
  ///
  /// If that ever becomes a Stack of both, this field silently goes blank for
  /// everyone with a saved barangay. Drive it from `value:` at that point
  /// rather than debugging it here.
  Widget _buildWebBarangayField() {
    final enabled = !_isLocked && !_saving;
    final current = _barangayCtrl.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AccountFieldLabel('Barangay'),
        DropdownButtonFormField<String>(
          initialValue: kAparriBarangays.contains(current) ? current : null,
          isExpanded: true,
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
          decoration: accountInputDecoration(
            hint: 'Select your barangay',
            enabled: enabled,
          ),
          hint: const Text(
            'Select your barangay',
            style: TextStyle(fontSize: 14, color: CitizenUi.textFaint),
          ),
          style: accountFieldTextStyle(),
          items: [
            for (final b in kAparriBarangays)
              DropdownMenuItem<String>(value: b, child: Text(b)),
          ],
          onChanged: enabled
              ? (v) {
                  if (v == null) return;
                  setState(() {
                    _barangayCtrl.text = v;
                    _barangay = v;
                  });
                }
              : null,
        ),
      ],
    );
  }

  /// The 30-day lock, as a one-line notice.
  ///
  /// The mobile banner ([_buildLockBanner]) is proportional: a gradient card
  /// with a 12%-of-width icon chip, a headline, a sentence, a date row and a
  /// progress bar. On a 480px phone that is reasonable ceremony for a state
  /// that blocks the whole screen. Given a 1120px page it became a ~180px slab
  /// of amber above the form — the loudest thing on a page about the form.
  ///
  /// The progress bar did not survive the move: it reads 0% for most of the
  /// month, and a bar that barely travels measures nothing. The pill states the
  /// number outright, which is all anyone wanted from the bar.
  ///
  /// Amber, not red — this is a rule working as intended, not a failure.
  Widget _buildWebLockNotice({required bool stack}) {
    final unlockDate = _lastProfileUpdatedAt?.add(const Duration(days: 30));
    final dateStr = unlockDate != null
        ? '${unlockDate.month}/${unlockDate.day}/${unlockDate.year}'
        : null;

    return AccountNotice(
      stack: stack,
      tone: AccountNoticeTone.warning,
      icon: Icons.lock_clock_rounded,
      title: 'Profile editing is locked',
      message: dateStr == null
          ? 'You can edit again in 30 days.'
          : 'You can edit again on $dateStr.',
      trailing: AccountNoticePill(
        label: '$_daysRemaining ${_daysRemaining == 1 ? 'day' : 'days'} left',
      ),
    );
  }

  // ── Identity banner ───────────────────────────────────────────────────────
  //
  // The mobile avatar card turned on its side. As a column it left a tall empty
  // gutter beside a form twice its height; across the top it introduces the
  // person, states their standing, and gets out of the way.

  Widget _buildWebIdentityBanner({required bool stack}) {
    final fullName =
        '${_firstNameCtrl.text.trim()} ${_lastNameCtrl.text.trim()}'.trim();
    final displayName = fullName.isNotEmpty ? fullName : widget.username;

    final name = Text(
      displayName,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: stack ? TextAlign.center : TextAlign.start,
      style: const TextStyle(
        fontSize: 21,
        fontWeight: FontWeight.w700,
        color: CitizenUi.textPrimary,
        letterSpacing: -0.3,
      ),
    );

    // `Wrap` rather than a second breakpoint — the pill and the stats break
    // onto their own lines only when they actually must.
    final standing = Wrap(
      alignment: stack ? WrapAlignment.center : WrapAlignment.start,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 8,
      children: [
        if (_isVerified) _buildWebVerifiedPill(),
        Text(
          _webIdentityMeta(),
          textAlign: stack ? TextAlign.center : TextAlign.start,
          style: const TextStyle(
            fontSize: 13,
            color: CitizenUi.textMuted,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );

    final busy = _isLocked || _saving;
    final photoButton = OutlinedButton.icon(
      onPressed: busy ? null : _pickPhoto,
      icon: Icon(
        _isLocked ? Icons.lock_outline_rounded : Icons.photo_camera_outlined,
        size: 17,
      ),
      label: Text(_isLocked ? 'Locked' : 'Change photo'),
      style: accountSecondaryButtonStyle().copyWith(
        foregroundColor: WidgetStatePropertyAll(CitizenUi.accent),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
        ),
      ),
    );

    return AccountCard(
      raised: true,
      padding: EdgeInsets.all(stack ? 18 : 22),
      // Narrow: the banner becomes a centred stack — avatar, name, standing,
      // then a full-width button. Beside each other at this width the name
      // would ellipsise and the button would still be clipped.
      child: stack
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(child: _buildWebAvatar()),
                const SizedBox(height: 14),
                name,
                const SizedBox(height: 10),
                standing,
                const SizedBox(height: 16),
                photoButton,
              ],
            )
          : Row(
              children: [
                _buildWebAvatar(),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [name, const SizedBox(height: 8), standing],
                  ),
                ),
                const SizedBox(width: 16),
                photoButton,
              ],
            ),
    );
  }

  /// The stats line, as prose rather than three bordered tiles.
  ///
  /// The tiles were the mobile card's way of filling a narrow column. Beside a
  /// name on a wide banner they are three boxes competing with the one thing
  /// the banner is for, so the same three facts run as a single quiet line.
  String _webIdentityMeta() {
    final parts = <String>[
      '$_reportCount ${_reportCount == 1 ? 'report' : 'reports'}',
      if (_memberSince != null && _memberSince!.isNotEmpty)
        'Member since $_memberSince',
      if (_barangay != null && _barangay!.isNotEmpty) _barangay!,
    ];
    return parts.join('  ·  ');
  }

  Widget _buildWebAvatar() {
    const size = 88.0;
    final busy = _isLocked || _saving;
    return GestureDetector(
      onTap: busy ? null : _pickPhoto,
      child: MouseRegion(
        cursor: busy ? SystemMouseCursors.basic : SystemMouseCursors.click,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: CitizenUi.border, width: 2),
          ),
          child: ClipOval(child: _buildAvatarImage(size)),
        ),
      ),
    );
  }

  Widget _buildWebVerifiedPill() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: const Color(0xFFDCFCE7),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: const Color(0xFF86EFAC)),
    ),
    child: const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.verified_rounded, size: 14, color: Color(0xFF16A34A)),
        SizedBox(width: 5),
        Text(
          'Verified Citizen',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: CitizenUi.success,
          ),
        ),
      ],
    ),
  );

  // ── Avatar card ───────────────────────────────────────────────────────────
  Widget _buildAvatarCard(double width) {
    final fullName =
        '${_firstNameCtrl.text.trim()} ${_lastNameCtrl.text.trim()}'.trim();
    final displayName = fullName.isNotEmpty ? fullName : widget.username;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        width * 0.04,
        width * 0.06,
        width * 0.04,
        width * 0.05,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(width * 0.04),
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
          GestureDetector(
            onTap: _isLocked ? null : _pickPhoto,
            child: Stack(
              children: [
                Container(
                  width: width * 0.28,
                  height: width * 0.28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: CitizenUi.sharedStroke, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ClipOval(child: _buildAvatarImage(width * 0.28)),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: width * 0.082,
                    height: width * 0.082,
                    decoration: BoxDecoration(
                      color: const Color(0xFFDBEAFE),
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
                    child: _isLocked
                        ? Icon(
                            Icons.lock_rounded,
                            color: const Color(0xFF93C5FD),
                            size: width * 0.036,
                          )
                        : Padding(
                            padding: EdgeInsets.all(width * 0.016),
                            child: ColorFiltered(
                              colorFilter: const ColorFilter.mode(
                                Color(0xFF3B82F6),
                                BlendMode.srcIn,
                              ),
                              child: Image.asset(
                                'assets/images/report/cameraicon.webp',
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),

          SizedBox(height: width * 0.032),

          Text(
            displayName,
            style: TextStyle(
              fontSize: width * 0.052,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1F2937),
            ),
          ),

          SizedBox(height: width * 0.014),

          if (_isVerified)
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: width * 0.04,
                vertical: width * 0.012,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(width * 0.06),
                border: Border.all(
                  color: AppColors.green.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.verified_rounded,
                    color: AppColors.green,
                    size: width * 0.038,
                  ),
                  SizedBox(width: width * 0.014),
                  Text(
                    'Verified Citizen',
                    style: TextStyle(
                      fontSize: width * 0.030,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF15803D),
                    ),
                  ),
                ],
              ),
            ),

          SizedBox(height: width * 0.028),

          if (_isVerified)
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: width * 0.02,
                vertical: width * 0.028,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(width * 0.03),
                border: Border.all(color: CitizenUi.sharedBorder),
              ),
              child: IntrinsicHeight(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildStatItem(
                      width: width,
                      iconPath: 'assets/images/report/report.webp',
                      iconColor: const Color(0xFF3B82F6),
                      value: '$_reportCount',
                      label: 'Reports',
                    ),
                    VerticalDivider(
                      color: CitizenUi.sharedBorder,
                      thickness: 1,
                      width: width * 0.01,
                    ),
                    _buildStatItem(
                      width: width,
                      iconPath: 'assets/images/calendar.webp',
                      iconColor: const Color(0xFF22C55E),
                      value: _memberSince ?? '—',
                      label: 'Member Since',
                    ),
                    VerticalDivider(
                      color: CitizenUi.sharedBorder,
                      thickness: 1,
                      width: width * 0.01,
                    ),
                    _buildStatItem(
                      width: width,
                      iconPath: 'assets/images/report/location.webp',
                      iconColor: const Color(0xFFF59E0B),
                      value: _barangay ?? '—',
                      label: 'Barangay',
                      isEllipsis: true,
                    ),
                  ],
                ),
              ),
            ),

          SizedBox(height: width * 0.022),

          Text(
            _isLocked
                ? 'Photo locked for $_daysRemaining more days'
                : _pickedFile != null
                ? 'New photo selected — tap Save to apply'
                : 'Tap photo to change',
            style: TextStyle(
              fontSize: width * 0.028,
              color: _isLocked ? AppColors.orange : AppColors.hint,
            ),
          ),

          if (_pickedFile != null && !_isLocked) ...[
            SizedBox(height: width * 0.012),
            GestureDetector(
              onTap: () => setState(() {
                _pickedFile = null;
                _pickedBytes = null;
              }),
              child: Text(
                'Remove new photo',
                style: TextStyle(
                  fontSize: width * 0.028,
                  color: AppColors.red,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.underline,
                  decorationColor: AppColors.red,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Stat item ─────────────────────────────────────────────────────────────
  Widget _buildStatItem({
    required double width,
    required String iconPath,
    required Color iconColor,
    required String value,
    required String label,
    bool isEllipsis = false,
  }) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            iconPath,
            width: width * 0.052,
            height: width * 0.052,
            color: iconColor,
            errorBuilder: (_, _, _) =>
                Icon(Icons.info_outline, size: width * 0.052, color: iconColor),
          ),
          SizedBox(height: width * 0.010),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: width * 0.024,
              color: const Color(0xFF6B7280),
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: width * 0.004),
          Text(
            value,
            maxLines: 1,
            overflow: isEllipsis ? TextOverflow.ellipsis : TextOverflow.clip,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: width * 0.034,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1F2937),
            ),
          ),
        ],
      ),
    );
  }

  // ── Avatar image ──────────────────────────────────────────────────────────
  /// [size] is the rendered diameter in logical pixels, NOT the page width.
  ///
  /// It used to derive one from the other (`width * 0.28`), which is fine while
  /// every caller scales with the page. The web layout does not — its avatar is
  /// a fixed 88 — so the caller passes the size it actually wants and the
  /// mobile call site passes what it always computed.
  Widget _buildAvatarImage(double size) {
    if (_pickedBytes != null) {
      return Image.memory(
        _pickedBytes!,
        width: size,
        height: size,
        fit: BoxFit.cover,
      );
    }
    if (_currentPhotoUrl != null && _currentPhotoUrl!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: _currentPhotoUrl!,
        cacheKey: _currentPhotoPath ?? _currentPhotoUrl!,
        memCacheWidth: 280,
        width: size,
        height: size,
        fit: BoxFit.cover,
        // Shimmer, not a spinner — the page's own loading state is the
        // editProfile skeleton, so the avatar keeps the same idiom while the
        // photo itself is still coming down.
        placeholder: (context, url) =>
            AppShimmerBox(width: size, height: size, radius: size / 2),
        errorWidget: (context, url, error) =>
            Image.asset('assets/images/profilenew.webp', fit: BoxFit.cover),
      );
    }
    return Image.asset('assets/images/profilenew.webp', fit: BoxFit.cover);
  }

  // ── Lock banner ───────────────────────────────────────────────────────────
  Widget _buildLockBanner(double width) {
    final unlockDate = _lastProfileUpdatedAt?.add(const Duration(days: 30));
    final dateStr = unlockDate != null
        ? '${unlockDate.month}/${unlockDate.day}/${unlockDate.year}'
        : '';

    const amber = Color(0xFFF59E0B);
    const amberDark = Color(0xFFB45309);
    const amberText = Color(0xFF92400E);
    // Fills up as the unlock date approaches (elapsed days / 30).
    final progress = ((30 - _daysRemaining) / 30.0).clamp(0.0, 1.0);

    return Container(
      padding: EdgeInsets.all(width * 0.045),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFFBEB), Color(0xFFFFF1D6)],
        ),
        borderRadius: BorderRadius.circular(width * 0.05),
        border: Border.all(color: amber.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: amber.withValues(alpha: 0.18),
            blurRadius: 18,
            offset: const Offset(0, 8),
            spreadRadius: -6,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Vivid icon chip ──────────────────────────────────────
              Container(
                width: width * 0.12,
                height: width * 0.12,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFFBBF24), Color(0xFFF59E0B)],
                  ),
                  borderRadius: BorderRadius.circular(width * 0.036),
                  boxShadow: [
                    BoxShadow(
                      color: amber.withValues(alpha: 0.40),
                      blurRadius: 12,
                      offset: const Offset(0, 5),
                      spreadRadius: -3,
                    ),
                  ],
                ),
                child: Icon(
                  Icons.lock_clock_rounded,
                  color: Colors.white,
                  size: width * 0.062,
                ),
              ),
              SizedBox(width: width * 0.035),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Profile Editing Locked',
                      style: TextStyle(
                        fontSize: width * 0.040,
                        fontWeight: FontWeight.w800,
                        color: amberDark,
                        letterSpacing: -0.2,
                      ),
                    ),
                    SizedBox(height: width * 0.012),
                    Text(
                      'Your profile was recently updated. You can edit again '
                      'in $_daysRemaining day${_daysRemaining == 1 ? '' : 's'}.',
                      style: TextStyle(
                        fontSize: width * 0.032,
                        color: amberText,
                        height: 1.5,
                      ),
                    ),
                    if (dateStr.isNotEmpty) ...[
                      SizedBox(height: width * 0.012),
                      Row(
                        children: [
                          Icon(
                            Icons.event_available_rounded,
                            size: width * 0.038,
                            color: amberDark,
                          ),
                          SizedBox(width: width * 0.015),
                          Text(
                            'Available from $dateStr',
                            style: TextStyle(
                              fontSize: width * 0.030,
                              color: amberDark,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: width * 0.04),
          // ── Progress + days-left pill ──────────────────────────────────
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(width * 0.02),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: width * 0.022,
                    backgroundColor: amber.withValues(alpha: 0.18),
                    valueColor: const AlwaysStoppedAnimation<Color>(amber),
                  ),
                ),
              ),
              SizedBox(width: width * 0.03),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: width * 0.028,
                  vertical: width * 0.012,
                ),
                decoration: BoxDecoration(
                  color: amber.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(width * 0.05),
                ),
                child: Text(
                  '$_daysRemaining day${_daysRemaining == 1 ? '' : 's'} left',
                  style: TextStyle(
                    fontSize: width * 0.028,
                    fontWeight: FontWeight.w800,
                    color: amberDark,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Locked display field ──────────────────────────────────────────────────
  /// Single source of truth for the trailing padlock so it renders at an
  /// identical size everywhere (the SizedBox + BoxFit pins it regardless of
  /// whether it sits in a Row or inside an InputDecoration suffix).
  Widget _lockBadge(double width) => SizedBox(
    width: width * 0.04,
    height: width * 0.04,
    child: Image.asset(
      'assets/images/settings/password.webp',
      fit: BoxFit.contain,
      color: const Color(0xFFD1D5DB),
      colorBlendMode: BlendMode.srcIn,
    ),
  );

  Widget _buildLockedDisplayField({
    required String label,
    required String value,
    required String icon,
    required double width,
    bool showDivider = true,
  }) {
    return Column(
      children: [
        Padding(
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
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(width * 0.022),
                  border: Border.all(color: CitizenUi.sharedStroke, width: 1.2),
                ),
                padding: EdgeInsets.all(width * 0.018),
                child: icon == '@'
                    ? FittedBox(
                        fit: BoxFit.contain,
                        child: Text(
                          '@',
                          style: TextStyle(
                            fontSize: width * 0.048,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF9CA3AF),
                          ),
                        ),
                      )
                    : ColorFiltered(
                        colorFilter: const ColorFilter.mode(
                          Color(0xFF9CA3AF),
                          BlendMode.srcIn,
                        ),
                        child: Image.asset(icon, fit: BoxFit.contain),
                      ),
              ),
              SizedBox(width: width * 0.035),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: width * 0.028,
                        color: AppColors.hint,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(height: width * 0.005),
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: width * 0.036,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF9CA3AF),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: width * 0.02),
              _lockBadge(width),
            ],
          ),
        ),
        if (showDivider) _divider(width),
      ],
    );
  }

  // ── Section label ─────────────────────────────────────────────────────────
  Widget _buildSectionLabel(String label, double width) {
    return Padding(
      padding: EdgeInsets.only(left: width * 0.01),
      child: Text(
        label,
        style: TextStyle(
          fontSize: width * 0.034,
          fontWeight: FontWeight.w700,
          color: AppColors.primaryBlue,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  // ── Card wrapper ──────────────────────────────────────────────────────────
  Widget _buildCard({required double width, required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(width * 0.035),
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

  // ── Editable text field ───────────────────────────────────────────────────
  Widget _buildField({
    required TextEditingController ctrl,
    required String label,
    required String hint,
    required String icon,
    required double width,
    int maxLines = 1,
    bool showDivider = true,
    bool enabled = true,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: width * 0.04,
            vertical: width * 0.015,
          ),
          child: Row(
            crossAxisAlignment: maxLines > 1
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.center,
            children: [
              Padding(
                padding: EdgeInsets.only(top: maxLines > 1 ? width * 0.025 : 0),
                child: Container(
                  width: width * 0.095,
                  height: width * 0.095,
                  decoration: BoxDecoration(
                    color: enabled
                        ? AppColors.primaryBlue.withValues(alpha: 0.10)
                        : const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(width * 0.022),
                    border: Border.all(
                      color: enabled
                          ? AppColors.primaryBlue.withValues(alpha: 0.25)
                          : AppColors.stroke,
                      width: 1.2,
                    ),
                  ),
                  padding: EdgeInsets.all(width * 0.018),
                  child: ColorFiltered(
                    colorFilter: ColorFilter.mode(
                      enabled ? AppColors.primaryBlue : const Color(0xFF9CA3AF),
                      BlendMode.srcIn,
                    ),
                    child: Image.asset(icon, fit: BoxFit.contain),
                  ),
                ),
              ),
              SizedBox(width: width * 0.035),
              Expanded(
                child: TextFormField(
                  controller: ctrl,
                  maxLines: maxLines,
                  enabled: enabled,
                  validator: validator,
                  keyboardType: keyboardType,
                  style: TextStyle(
                    fontSize: width * 0.038,
                    fontWeight: FontWeight.w500,
                    color: enabled
                        ? const Color(0xFF1F2937)
                        : const Color(0xFF9CA3AF),
                  ),
                  decoration: InputDecoration(
                    labelText: label,
                    hintText: hint,
                    suffixIcon: !enabled
                        ? Padding(
                            padding: EdgeInsets.only(left: width * 0.02),
                            child: _lockBadge(width),
                          )
                        : null,
                    suffixIconConstraints: BoxConstraints(
                      minWidth: width * 0.04,
                      minHeight: width * 0.04,
                    ),
                    labelStyle: TextStyle(
                      fontSize: width * 0.032,
                      color: AppColors.hint,
                      fontWeight: FontWeight.w500,
                    ),
                    hintStyle: TextStyle(
                      fontSize: width * 0.034,
                      color: AppColors.hint.withValues(alpha: 0.6),
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      vertical: width * 0.02,
                    ),
                    errorStyle: TextStyle(
                      fontSize: width * 0.028,
                      color: AppColors.red,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (showDivider) _divider(width),
      ],
    );
  }

  // ── Barangay picker field ─────────────────────────────────────────────────
  /// Mirrors the ID-verification form: residents pick from the canonical Aparri
  /// barangay list instead of free-typing. Wrapped in a [FormField] so it plugs
  /// into the same validate()/error flow as the text fields, while the picked
  /// value stays mirrored into [_barangayCtrl] for the save payload.
  Widget _buildBarangayField(double width) {
    final enabled = !_isLocked;
    return FormField<String>(
      initialValue: _barangayCtrl.text.trim().isEmpty
          ? null
          : _barangayCtrl.text.trim(),
      validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
      builder: (state) {
        final value = state.value;
        final hasValue = value != null && value.isNotEmpty;
        return Padding(
          padding: EdgeInsets.symmetric(
            horizontal: width * 0.04,
            vertical: width * 0.015,
          ),
          child: InkWell(
            onTap: enabled ? () => _showBarangayPicker(width, state) : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: width * 0.095,
                      height: width * 0.095,
                      decoration: BoxDecoration(
                        color: enabled
                            ? AppColors.primaryBlue.withValues(alpha: 0.10)
                            : const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(width * 0.022),
                        border: Border.all(
                          color: enabled
                              ? AppColors.primaryBlue.withValues(alpha: 0.25)
                              : AppColors.stroke,
                          width: 1.2,
                        ),
                      ),
                      padding: EdgeInsets.all(width * 0.018),
                      child: ColorFiltered(
                        colorFilter: ColorFilter.mode(
                          enabled
                              ? AppColors.primaryBlue
                              : const Color(0xFF9CA3AF),
                          BlendMode.srcIn,
                        ),
                        child: Image.asset(
                          'assets/images/report/location.webp',
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    SizedBox(width: width * 0.035),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Barangay',
                            style: TextStyle(
                              fontSize: width * 0.032,
                              color: AppColors.hint,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          SizedBox(height: width * 0.008),
                          Text(
                            hasValue ? value : 'Select your barangay',
                            style: TextStyle(
                              fontSize: width * 0.038,
                              fontWeight: FontWeight.w500,
                              color: !enabled
                                  ? const Color(0xFF9CA3AF)
                                  : hasValue
                                  ? const Color(0xFF1F2937)
                                  : AppColors.hint.withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: width * 0.02),
                    enabled
                        ? Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: width * 0.05,
                            color: AppColors.hint,
                          )
                        : _lockBadge(width),
                  ],
                ),
                if (state.hasError) ...[
                  SizedBox(height: width * 0.012),
                  Padding(
                    padding: EdgeInsets.only(left: width * 0.13),
                    child: Text(
                      state.errorText!,
                      style: TextStyle(
                        fontSize: width * 0.028,
                        color: AppColors.red,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showBarangayPicker(
    double width,
    FormFieldState<String> state,
  ) async {
    final searchCtrl = TextEditingController();
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(width * 0.05)),
      ),
      builder: (ctx) {
        var results = List<String>.from(kAparriBarangays);
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: DraggableScrollableSheet(
                expand: false,
                initialChildSize: 0.7,
                maxChildSize: 0.9,
                minChildSize: 0.5,
                builder: (ctx, scrollCtrl) {
                  return Column(
                    children: [
                      SizedBox(height: width * 0.03),
                      Container(
                        width: width * 0.12,
                        height: width * 0.012,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE5E7EB),
                          borderRadius: BorderRadius.circular(width * 0.01),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          width * 0.05,
                          width * 0.04,
                          width * 0.05,
                          width * 0.02,
                        ),
                        child: Row(
                          children: [
                            Text(
                              'Select Barangay',
                              style: TextStyle(
                                fontSize: width * 0.046,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF1F2937),
                              ),
                            ),
                            const Spacer(),
                            GestureDetector(
                              onTap: () => Navigator.pop(ctx),
                              child: Icon(
                                Icons.close_rounded,
                                size: width * 0.055,
                                color: AppColors.hint,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: width * 0.05),
                        child: TextField(
                          controller: searchCtrl,
                          autofocus: false,
                          style: TextStyle(fontSize: width * 0.036),
                          onChanged: (q) {
                            final query = q.trim().toLowerCase();
                            setSheetState(() {
                              results = query.isEmpty
                                  ? List<String>.from(kAparriBarangays)
                                  : kAparriBarangays
                                        .where(
                                          (b) =>
                                              b.toLowerCase().contains(query),
                                        )
                                        .toList();
                            });
                          },
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: 'Search barangay…',
                            hintStyle: TextStyle(
                              fontSize: width * 0.036,
                              color: AppColors.hint,
                            ),
                            prefixIcon: Icon(
                              Icons.search_rounded,
                              size: width * 0.05,
                              color: AppColors.hint,
                            ),
                            filled: true,
                            fillColor: const Color(0xFFF3F4F6),
                            contentPadding: EdgeInsets.symmetric(
                              vertical: width * 0.03,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(width * 0.03),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: width * 0.02),
                      Expanded(
                        child: results.isEmpty
                            ? Center(
                                child: Text(
                                  'No barangay found',
                                  style: TextStyle(
                                    fontSize: width * 0.036,
                                    color: AppColors.hint,
                                  ),
                                ),
                              )
                            : ListView.builder(
                                controller: scrollCtrl,
                                padding: EdgeInsets.only(bottom: width * 0.05),
                                itemCount: results.length,
                                itemBuilder: (ctx, i) {
                                  final b = results[i];
                                  final isSelected = b == state.value;
                                  return ListTile(
                                    title: Text(
                                      b,
                                      style: TextStyle(
                                        fontSize: width * 0.038,
                                        fontWeight: isSelected
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                        color: isSelected
                                            ? AppColors.primaryBlue
                                            : const Color(0xFF1F2937),
                                      ),
                                    ),
                                    trailing: isSelected
                                        ? Icon(
                                            Icons.check_rounded,
                                            color: AppColors.primaryBlue,
                                            size: width * 0.05,
                                          )
                                        : null,
                                    onTap: () => Navigator.pop(ctx, b),
                                  );
                                },
                              ),
                      ),
                    ],
                  );
                },
              ),
            );
          },
        );
      },
    );

    searchCtrl.dispose();
    if (selected != null) {
      state.didChange(selected);
      setState(() {
        _barangayCtrl.text = selected;
        _barangay = selected;
      });
    }
  }

  Widget _divider(double width) => Padding(
    padding: EdgeInsets.only(left: width * 0.165),
    child: const Divider(height: 1, color: CitizenUi.sharedStroke),
  );
}
