import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../../core/widgets/Home/Account/account_web_kit.dart';
import '../../core/services/id_check_service.dart';
import '../../core/widgets/app_dialog.dart' show kWebDialogMaxWidth;
import 'package:flutter/services.dart';
import '../../core/router/legacy_nav.dart';
import '../../core/theme/app_colors.dart';
import '../../core/constants/aparri_barangays.dart';
import '../../core/theme/citizen_ui.dart';

class VerificationReviewScreen extends StatefulWidget {
  final String username;
  final String selectedId;
  final Uint8List? frontImage;
  final Uint8List? backImage;

  /// Carried, not read: the automated ID check travels with the wizard so the
  /// SUBMIT step can store it. This screen has no use for it.
  final IdSubmissionCheck? idCheck;
  final Map<String, String>? extractedData;

  const VerificationReviewScreen({
    super.key,
    required this.username,
    required this.selectedId,
    this.frontImage,
    this.backImage,
    this.idCheck,
    this.extractedData,
  });

  @override
  State<VerificationReviewScreen> createState() =>
      _VerificationReviewScreenState();
}

class _UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}

class _VerificationReviewScreenState extends State<VerificationReviewScreen>
    with SingleTickerProviderStateMixin {
  final _idController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _middleNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _birthdateController = TextEditingController();
  final _birthplaceController = TextEditingController();
  final _contactController = TextEditingController();
  final _streetController = TextEditingController();
  final _scrollController = ScrollController();

  String? _suffix, _status, _barangay;
  bool _isMale = true;
  bool _confirmPressed = false;
  bool _showErrors = false;
  bool _showingBack = false; // toggle which side is previewed

  // ── Entry animation ─────────────────────────────────────────────────────
  // Identical to the six other wizard steps: 420ms, fade on easeOut and a
  // 6%-of-height rise on easeOutCubic, started after the first frame.
  //
  // This was the only step without one, which is why its ROUTE slid instead -
  // the movement had to come from somewhere. With the route now at
  // Duration.zero like its neighbours, this is what makes arriving here read
  // as an arrival: the frame appears at once, then the content rises into it.
  late final AnimationController _entryCtrl;
  late final Animation<double> _entryFade;
  late final Animation<Offset> _entrySlide;

  @override
  void initState() {
    super.initState();

    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _entryFade = CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut);
    _entrySlide = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutCubic));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _entryCtrl.forward();
    });

    // ── Pre-fill from OCR ──────────────────────────────────────
    final d = widget.extractedData ?? {};

    _idController.text = (d['idNumber'] ?? '').toUpperCase();
    _firstNameController.text = (d['firstName'] ?? '').toUpperCase();
    _middleNameController.text = (d['middleName'] ?? '').toUpperCase();
    _lastNameController.text = (d['lastName'] ?? '').toUpperCase();
    _birthdateController.text = (d['birthdate'] ?? '').toUpperCase();
    _birthplaceController.text = (d['birthplace'] ?? '').toUpperCase();
    _contactController.text = (d['contactNumber'] ?? '').toUpperCase();
    _streetController.text = (d['street'] ?? '').toUpperCase();
    if (d['gender'] == 'female') _isMale = false;
    _status ??= d['civilStatus']; // ← ADD THIS LINE
    // ───────────────────────────────────────────────────────────

    for (final c in [
      _idController,
      _firstNameController,
      _middleNameController,
      _lastNameController,
      _birthdateController,
      _birthplaceController,
      _contactController,
      _streetController,
    ]) {
      c.addListener(() => setState(() {}));
    }
    Future.delayed(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom],
      );
    });
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    _scrollController.dispose();
    for (final c in [
      _idController,
      _firstNameController,
      _middleNameController,
      _lastNameController,
      _birthdateController,
      _birthplaceController,
      _contactController,
      _streetController,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  bool _hasError(TextEditingController ctrl) =>
      _showErrors && ctrl.text.trim().isEmpty;

  bool _hasDropdownError(String? value) => _showErrors && value == null;

  List<String> _getMissingFields() => [
    if (_idController.text.trim().isEmpty) "ID Number",
    if (_firstNameController.text.trim().isEmpty) "Firstname",
    if (_middleNameController.text.trim().isEmpty) "Middlename",
    if (_lastNameController.text.trim().isEmpty) "Lastname",
    if (_birthdateController.text.trim().isEmpty) "Birthdate",
    if (_birthplaceController.text.trim().isEmpty) "Birthplace",
    if (_contactController.text.trim().isEmpty) "Contact Number",
    if (_status == null) "Civil Status",
    if (_barangay == null) "Barangay",
    if (_streetController.text.trim().isEmpty) "Street / House No.",
  ];

  Future<void> _showAnimatedDialog(Widget dialog) => showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: '',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (_, _, _) => dialog,
    transitionBuilder: (_, anim, _, child) => ScaleTransition(
      scale: Tween(
        begin: 0.72,
        end: 1.0,
      ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutBack)),
      child: FadeTransition(
        opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
        child: child,
      ),
    ),
  );

  // ── Input Decoration ──────────────────────────────────────────────────────

  InputDecoration _inputDec(
    String label, {
    Widget? suffix,
    bool error = false,
  }) => InputDecoration(
    labelText: label,
    labelStyle: TextStyle(
      color: error ? AppColors.red : AppColors.hint,
      fontSize: 13,
    ),
    floatingLabelStyle: TextStyle(
      color: error ? AppColors.red : AppColors.primaryBlue,
      fontSize: 11,
      fontWeight: FontWeight.w500,
    ),
    floatingLabelBehavior: FloatingLabelBehavior.auto,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    filled: true,
    fillColor: error
        ? AppColors.red.withValues(alpha: 0.04)
        : AppColors.inputBg,
    suffixIcon: suffix,
    hintText: error ? 'Required' : null,
    hintStyle: const TextStyle(
      color: AppColors.red,
      fontSize: 12,
      fontStyle: FontStyle.italic,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.zero,
      borderSide: BorderSide(
        color: error ? AppColors.red : CitizenUi.sharedStroke,
        width: error ? 1.5 : 1.0,
      ),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.zero,
      borderSide: BorderSide(
        color: error ? AppColors.red : AppColors.primaryBlue,
        width: 1.5,
      ),
    ),
    border: const OutlineInputBorder(borderRadius: BorderRadius.zero),
  );

  // ── Dialogs ───────────────────────────────────────────────────────────────

  void _showWarningOverlay(List<String> missing) => _showAnimatedDialog(
    Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 36),
      // WEB: cap the dialog. `insetPadding` alone only guarantees a MARGIN,
      // so with nothing else to size it this box grew to the whole window -
      // one sentence stretched across a monitor above two buttons a mouse-drag
      // apart. [kWebDialogMaxWidth] is the same 380 every other citizen-web
      // confirm uses. `double.infinity` off the web is no constraint at all,
      // so the phone keeps the full-bleed dialog it was designed with.
      child: Container(
        constraints: BoxConstraints(
          maxWidth: kIsWeb ? kWebDialogMaxWidth : double.infinity,
        ),
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset("assets/images/sad.webp", width: 62, height: 62),
            const SizedBox(height: 14),
            const Text(
              "Incomplete Information",
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              "Please fill in all required fields before confirming.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.hint,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.red.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.red.withValues(alpha: 0.35),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: missing
                    .map(
                      (f) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.circle,
                              size: 5,
                              color: AppColors.red,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              f,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.red,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
            const SizedBox(height: 22),
            _PressButton(
              label: "Go Back & Fill",
              color: AppColors.red,
              onPressed: () {
                setState(() => _showErrors = true);
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    ),
  );

  void _showConfirmationOverlay() => _showAnimatedDialog(
    Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 36),
      // WEB: cap the dialog. `insetPadding` alone only guarantees a MARGIN,
      // so with nothing else to size it this box grew to the whole window -
      // one sentence stretched across a monitor above two buttons a mouse-drag
      // apart. [kWebDialogMaxWidth] is the same 380 every other citizen-web
      // confirm uses. `double.infinity` off the web is no constraint at all,
      // so the phone keeps the full-bleed dialog it was designed with.
      child: Container(
        constraints: BoxConstraints(
          maxWidth: kIsWeb ? kWebDialogMaxWidth : double.infinity,
        ),
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ColorFiltered(
              colorFilter: const ColorFilter.mode(
                AppColors.primaryBlue,
                BlendMode.srcIn,
              ),
              child: Image.asset(
                "assets/images/info.webp",
                width: 56,
                height: 56,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              "Please check your personal information is correct before confirmation.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Color(0xFF374151),
                height: 1.55,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _OutlineButton(
                    label: "Modify",
                    color: AppColors.primaryBlue,
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _PressButton(
                    label: "Confirm",
                    color: AppColors.primaryBlue,
                    onPressed: () {
                      final missing = _getMissingFields();
                      if (missing.isNotEmpty) {
                        Navigator.pop(context);
                        Future.delayed(const Duration(milliseconds: 300), () {
                          if (!mounted) return;
                          _showWarningOverlay(missing);
                        });
                      } else {
                        setState(() => _showErrors = false);
                        pushLegacy(
                          context,
                          '/verification_identity',
                          arguments: {
                            'username': widget.username,
                            'selectedId': widget.selectedId,
                            'idNumber': _idController.text.trim(),
                            'firstName': _firstNameController.text.trim(),
                            'middleName': _middleNameController.text.trim(),
                            'lastName': _lastNameController.text.trim(),
                            'suffix': _suffix,
                            'gender': _isMale ? 'male' : 'female',
                            'birthdate': _birthdateController.text.trim(),
                            'birthplace': _birthplaceController.text.trim(),
                            'civilStatus': _status,
                            'contactNumber': _contactController.text.trim(),
                            'barangay': _barangay,
                            'street': _streetController.text.trim(),
                            'frontImage': widget.frontImage,
                            'backImage': widget.backImage,
          'idCheck': widget.idCheck?.toRouteArg(),
                          },
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  // ── Build ─────────────────────────────────────────────────────────────────

  // ==========================================================================
  //  WEB
  //
  //  Step 2 of 3 - "Additional Information". This screen sits BETWEEN the scan
  //  and the identity form, which is not the order the file names suggest; see
  //  [kVerificationSteps].
  //
  //  -- The field widgets are the phone's, deliberately --------------------
  //  [_field], [_dropdown] and [_genderTile] are reused rather than rebuilt on
  //  the kit's [AccountTextField]. They carry this screen's own validation
  //  behaviour - the `Required` hint, the red wash, [_hasError] and
  //  [_hasDropdownError], the upper-casing formatter, the scroll-into-view on
  //  focus - and rebuilding them on a different field widget would mean porting
  //  all of that with no way to test the result. What was actually wrong here
  //  was the FRAME: a 560 column with a logo above it. So the frame is what
  //  changed.
  //
  //  What the width buys is the row grouping below: the three name fields go
  //  side by side instead of stacking, and so do the four short pairs.
  // ==========================================================================

  Widget _buildWebScaffold() {
    return Scaffold(
      backgroundColor: CitizenUi.pageBg,
      body: SafeArea(
        child: AccountPageBody(
          builder: (context, stack) => FadeTransition(
            opacity: _entryFade,
            child: SlideTransition(
              position: _entrySlide,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AccountPageTitle(
                    title: 'Confirm your details',
                    subtitle:
                        'Check what we read from your ID and fill in anything '
                        'that is missing.',
                    onBack: () => Navigator.pop(context),
                    backLabel: 'Back to upload your ID',
                  ),
                  const AccountStepper(step: 1, labels: kVerificationSteps),

                  const AccountSectionLabel('Your ID'),
                  AccountCard(child: Center(child: _buildIdPreview())),
                  const SizedBox(height: kAccountSectionGap),

                  const AccountSectionLabel('Personal information'),
                  AccountCard(
                    child: Column(
                      children: [
                        _webRow(stack, [
                          (2, _field(_idController, 'ID Number')),
                          (
                            1,
                            _dropdown(
                              'Suffix',
                              _suffix,
                              const ['Jr.', 'Sr.', 'II', 'III', 'IV'],
                              (v) => setState(() => _suffix = v),
                              required: false,
                            ),
                          ),
                        ]),
                        const SizedBox(height: kAccountGap),
                        _webRow(stack, [
                          (1, _field(_firstNameController, 'Firstname')),
                          (1, _field(_middleNameController, 'Middlename')),
                          (1, _field(_lastNameController, 'Lastname')),
                        ]),
                        const SizedBox(height: kAccountGap),
                        _webRow(stack, [
                          (
                            1,
                            _genderTile(
                              'Male',
                              Icons.male,
                              selected: _isMale,
                              onTap: () => setState(() => _isMale = true),
                            ),
                          ),
                          (
                            1,
                            _genderTile(
                              'Female',
                              Icons.female,
                              selected: !_isMale,
                              onTap: () => setState(() => _isMale = false),
                            ),
                          ),
                        ]),
                        const SizedBox(height: kAccountGap),
                        _webRow(stack, [
                          (1, _webBirthdateField()),
                          (
                            1,
                            _dropdown('Status', _status, const [
                              'Single',
                              'Married',
                              'Widowed',
                              'Separated',
                            ], (v) => setState(() => _status = v)),
                          ),
                        ]),
                        const SizedBox(height: kAccountGap),
                        _webRow(stack, [
                          (1, _field(_birthplaceController, 'Birthplace')),
                          (
                            1,
                            _field(
                              _contactController,
                              'Contact Number',
                              type: TextInputType.phone,
                            ),
                          ),
                        ]),
                      ],
                    ),
                  ),
                  const SizedBox(height: kAccountSectionGap),

                  const AccountSectionLabel('Home address'),
                  AccountCard(
                    child: _webRow(stack, [
                      (
                        1,
                        _dropdown(
                          'Barangay',
                          _barangay,
                          kAparriBarangays,
                          (v) => setState(() => _barangay = v),
                        ),
                      ),
                      (1, _field(_streetController, 'Street / House No.')),
                    ]),
                  ),
                  const SizedBox(height: kAccountSectionGap),

                  _webConfirmButton(stack),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// One row of fields, flattened to one per line when [stack].
  ///
  /// Every cell is given the same fixed height, because a [DropdownButtonFormField]
  /// and a [TextField] do not agree on their natural height and the difference
  /// shows as a stepped baseline across the row. 48 is what the phone's own rows
  /// already wrap these in, and [_inputDec] carries no `errorText` - the "Required"
  /// state is a hint INSIDE the field - so nothing is ever clipped by it.
  Widget _webRow(bool stack, List<(int, Widget)> cells) {
    if (stack) {
      return Column(
        children: [
          for (var i = 0; i < cells.length; i++) ...[
            if (i > 0) const SizedBox(height: kAccountGap),
            SizedBox(height: 48, child: cells[i].$2),
          ],
        ],
      );
    }
    return Row(
      children: [
        for (var i = 0; i < cells.length; i++) ...[
          if (i > 0) const SizedBox(width: kAccountGap),
          Expanded(
            flex: cells[i].$1,
            child: SizedBox(height: 48, child: cells[i].$2),
          ),
        ],
      ],
    );
  }

  /// The read-only birthdate field with its date picker.
  ///
  /// A web-only copy of the block inlined in [_buildForm] rather than an
  /// extraction of it, so the mobile widget tree is not touched at all.
  Widget _webBirthdateField() {
    return TextField(
      controller: _birthdateController,
      style: const TextStyle(fontSize: 13),
      readOnly: true,
      decoration: _inputDec(
        'Birthdate',
        suffix: const Icon(Icons.calendar_month_outlined, size: 18),
        error: _hasError(_birthdateController),
      ),
      onTap: () async {
        final d = await showDatePicker(
          context: context,
          initialDate: DateTime(1990),
          firstDate: DateTime(1900),
          lastDate: DateTime.now(),
        );
        if (d != null) {
          setState(() {
            _birthdateController.text = '${d.month}/${d.day}/${d.year}';
          });
        }
      },
    );
  }

  /// Same green as every other step of the wizard on web, and the same
  /// confirmation overlay the phone shows.
  Widget _webConfirmButton(bool stack) {
    final button = ElevatedButton(
      onPressed: _showConfirmationOverlay,
      style: accountPrimaryButtonStyle().copyWith(
        backgroundColor: const WidgetStatePropertyAll(CitizenUi.accentGreen),
      ),
      child: const Text('Confirm'),
    );

    return stack
        ? SizedBox(width: double.infinity, child: button)
        : Row(mainAxisAlignment: MainAxisAlignment.end, children: [button]);
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );

    if (kIsWeb) return _buildWebScaffold();

    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: AppColors.inputBg,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        top: true,
        bottom: false,
        // Web / large screens: cap + center the flow so form fields don't
        // stretch edge-to-edge. Phones (≤560px) render pixel-identical.
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              children: [
                _buildHeader(context),
                _buildStepper(),
                Expanded(
                  child: FadeTransition(
                    opacity: _entryFade,
                    child: SlideTransition(
                      position: _entrySlide,
                      child: _buildForm(),
                    ),
                  ),
                ),
                FadeTransition(
                  opacity: _entryFade,
                  child: SlideTransition(
                    position: _entrySlide,
                    child: _buildBottomButton(bottomPadding),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10, bottom: 8),
    child: Column(
      children: [
        Image.asset(
          "assets/images/applogocrop.webp",
          height: (MediaQuery.of(context).size.height * 0.10).clamp(40.0, 80.0),
        ),
        const SizedBox(height: 8),
        const Text(
          "Aparri Citizenship Verification",
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.primaryBlue,
          ),
        ),
      ],
    ),
  );

  Widget _buildStepper() => Padding(
    padding: const EdgeInsets.only(bottom: 12, left: 8, right: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _step("1", "Upload ID", active: true),
        Expanded(child: _divider(active: true)),
        _step("2", "Additional\nInformation", active: true),
        Expanded(child: _divider(active: false)),
        _step("3", "Identity\nVerification", active: false),
      ],
    ),
  );

  Widget _step(String n, String label, {required bool active}) => SizedBox(
    width: 54,
    child: Column(
      children: [
        CircleAvatar(
          radius: 12,
          backgroundColor: active
              ? AppColors.primaryBlue
              : Colors.grey.shade300,
          child: Text(
            n,
            style: TextStyle(
              fontSize: 10,
              color: active ? Colors.white : Colors.black54,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 9,
            color: active ? AppColors.primaryBlue : Colors.grey,
          ),
        ),
      ],
    ),
  );

  Widget _divider({required bool active}) => Container(
    margin: const EdgeInsets.only(top: 11),
    height: 2,
    color: active ? AppColors.primaryBlue : AppColors.stroke,
  );

  // ── Landscape ID preview card (rotated to landscape) ───────────────────
  Widget _buildIdPreview() {
    final shown = _showingBack ? widget.backImage : widget.frontImage;
    final hasBoth = widget.frontImage != null && widget.backImage != null;

    // Card is sized for the landscape (rotated) image.
    // The captured frame was 220x320 portrait (~0.6875 ratio) → rotate 90°
    // for landscape display: width > height.
    const previewW = 320.0;
    const previewH = 200.0;

    return Column(
      children: [
        // Side toggle
        if (hasBoth)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _SideTab(
                label: "Front",
                active: !_showingBack,
                onTap: () => setState(() => _showingBack = false),
              ),
              const SizedBox(width: 8),
              _SideTab(
                label: "Back",
                active: _showingBack,
                onTap: () => setState(() => _showingBack = true),
              ),
            ],
          ),
        const SizedBox(height: 8),

        // The card — clips a landscape view of the rotated image
        Container(
          width: previewW,
          height: previewH,
          decoration: BoxDecoration(
            color: Colors.black,
            border: Border.all(color: AppColors.primaryBlue, width: 2),
            borderRadius: BorderRadius.circular(6),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: shown != null
                ? Image.memory(
                    shown,
                    fit: BoxFit.cover,
                    width: previewW,
                    height: previewH,
                  )
                : Image.asset(
                    "assets/images/idcards/phfront.webp",
                    fit: BoxFit.cover,
                  ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _showingBack
              ? "Back of ${widget.selectedId}"
              : "Front of ${widget.selectedId}",
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.hint,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildForm() => SingleChildScrollView(
    controller: _scrollController,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        const Center(
          child: Text(
            "Confirm Details",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ),
        const SizedBox(height: 12),
        Center(child: _buildIdPreview()),
        const SizedBox(height: 20),
        _sectionLabel("Personal Information"),
        const SizedBox(height: 10),
        _field(_idController, "ID Number"),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 3, child: _field(_firstNameController, "Firstname")),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: SizedBox(
                height: 48,
                child: _dropdown(
                  "Suffix",
                  _suffix,
                  ["Jr.", "Sr.", "II", "III", "IV"],
                  (v) => setState(() => _suffix = v),
                  required: false,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _field(_middleNameController, "Middlename"),
        const SizedBox(height: 10),
        _field(_lastNameController, "Lastname"),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _genderTile(
                "Male",
                Icons.male,
                selected: _isMale,
                onTap: () => setState(() => _isMale = true),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _genderTile(
                "Female",
                Icons.female,
                selected: !_isMale,
                onTap: () => setState(() => _isMale = false),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SizedBox(
                height: 48,
                child: Focus(
                  onFocusChange: (hasFocus) {
                    if (hasFocus) {
                      Future.delayed(const Duration(milliseconds: 300), () {
                        if (!mounted) return;
                        Scrollable.ensureVisible(
                          context,
                          duration: const Duration(milliseconds: 350),
                          curve: Curves.easeOut,
                          alignment: 0.3,
                        );
                      });
                    }
                  },
                  child: TextField(
                    controller: _birthdateController,
                    style: const TextStyle(fontSize: 13),
                    readOnly: true,
                    decoration: _inputDec(
                      "Birthdate",
                      suffix: const Icon(
                        Icons.calendar_month_outlined,
                        size: 18,
                      ),
                      error: _hasError(_birthdateController),
                    ),
                    onTap: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: DateTime(1990),
                        firstDate: DateTime(1900),
                        lastDate: DateTime.now(),
                      );
                      if (d != null) {
                        setState(() {
                          _birthdateController.text =
                              "${d.month}/${d.day}/${d.year}";
                        });
                      }
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SizedBox(
                height: 48,
                child: _dropdown("Status", _status, [
                  "Single",
                  "Married",
                  "Widowed",
                  "Separated",
                ], (v) => setState(() => _status = v)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SizedBox(
                height: 48,
                child: _field(_birthplaceController, "Birthplace"),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SizedBox(
                height: 48,
                child: _field(
                  _contactController,
                  "Contact Number",
                  type: TextInputType.phone,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _sectionLabel("Home Address"),
        const SizedBox(height: 10),
        _dropdown(
          "Barangay",
          _barangay,
          kAparriBarangays,
          (v) => setState(() => _barangay = v),
        ),
        const SizedBox(height: 10),
        _field(_streetController, "Street / House No."),
        const SizedBox(height: 24),
      ],
    ),
  );

  Widget _buildBottomButton(double bottomPadding) => Container(
    padding: EdgeInsets.fromLTRB(16, 8, 16, bottomPadding + 8),
    color: Colors.white,
    child: GestureDetector(
      onTapDown: (_) => setState(() => _confirmPressed = true),
      onTapUp: (_) {
        setState(() => _confirmPressed = false);
        _showConfirmationOverlay();
      },
      onTapCancel: () => setState(() => _confirmPressed = false),
      child: AnimatedScale(
        scale: _confirmPressed ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeInOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 48,
          decoration: BoxDecoration(
            color: _confirmPressed
                ? AppColors.green.withValues(alpha: 0.80)
                : AppColors.green,
            borderRadius: BorderRadius.circular(24),
            boxShadow: _confirmPressed
                ? []
                : [
                    BoxShadow(
                      color: AppColors.green.withValues(alpha: 0.38),
                      blurRadius: 12,
                      offset: const Offset(0, 5),
                    ),
                  ],
          ),
          alignment: Alignment.center,
          child: const Text(
            "Confirm",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: Colors.white,
            ),
          ),
        ),
      ),
    ),
  );

  // ── Reusable bits ─────────────────────────────────────────────────────────

  Widget _sectionLabel(String t) => Text(
    t,
    style: const TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      color: AppColors.primaryBlue,
    ),
  );

  Widget _field(
    TextEditingController ctrl,
    String label, {
    TextInputType? type,
  }) {
    final error = _hasError(ctrl);
    return Focus(
      onFocusChange: (hasFocus) {
        if (hasFocus) {
          Future.delayed(const Duration(milliseconds: 300), () {
            if (!mounted) return;
            Scrollable.ensureVisible(
              context,
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOut,
              alignment: 0.3,
            );
          });
        }
      },
      child: TextField(
        controller: ctrl,
        keyboardType: type,
        textCapitalization: TextCapitalization.characters,
        inputFormatters: [_UpperCaseTextFormatter()],
        style: const TextStyle(fontSize: 13),
        decoration: _inputDec(label, error: error),
      ),
    );
  }

  Widget _dropdown(
    String label,
    String? value,
    List<String> items,
    ValueChanged<String?> onChanged, {
    bool required = true,
  }) {
    final error = required && _hasDropdownError(value);
    return DropdownButtonFormField<String>(
      initialValue: value,
      style: const TextStyle(fontSize: 13, color: Colors.black87),
      decoration: _inputDec(label, error: error),
      icon: const Icon(Icons.keyboard_arrow_down, size: 18),
      items: items
          .map((s) => DropdownMenuItem(value: s, child: Text(s)))
          .toList(),
      onChanged: onChanged,
    );
  }

  Widget _genderTile(
    String label,
    IconData icon, {
    required bool selected,
    required VoidCallback onTap,
  }) => GestureDetector(
    onTap: onTap,
    child: Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.inputBg,
        border: Border.all(color: CitizenUi.sharedStroke),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.black54),
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
          Icon(
            selected ? Icons.radio_button_checked : Icons.radio_button_off,
            color: selected ? AppColors.primaryBlue : AppColors.grey,
          ),
        ],
      ),
    ),
  );
}

// ── Front/Back tab pill ───────────────────────────────────────────────────────
class _SideTab extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _SideTab({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AppColors.primaryBlue : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.primaryBlue),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: active ? Colors.white : AppColors.primaryBlue,
          ),
        ),
      ),
    );
  }
}

// ── Animated filled button ────────────────────────────────────────────────────
class _PressButton extends StatefulWidget {
  final String label;
  final Color color;
  final VoidCallback onPressed;
  const _PressButton({
    required this.label,
    required this.color,
    required this.onPressed,
  });

  @override
  State<_PressButton> createState() => _PressButtonState();
}

class _PressButtonState extends State<_PressButton> {
  bool _p = false;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTapDown: (_) => setState(() => _p = true),
    onTapUp: (_) {
      setState(() => _p = false);
      widget.onPressed();
    },
    onTapCancel: () => setState(() => _p = false),
    child: AnimatedScale(
      scale: _p ? 0.93 : 1.0,
      duration: const Duration(milliseconds: 110),
      curve: Curves.easeInOut,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 110),
        height: 44,
        decoration: BoxDecoration(
          color: _p ? widget.color.withValues(alpha: 0.78) : widget.color,
          borderRadius: BorderRadius.circular(22),
          boxShadow: _p
              ? []
              : [
                  BoxShadow(
                    color: widget.color.withValues(alpha: 0.28),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
        ),
        alignment: Alignment.center,
        child: Text(
          widget.label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
    ),
  );
}

// ── Animated outlined button ──────────────────────────────────────────────────
class _OutlineButton extends StatefulWidget {
  final String label;
  final Color color;
  final VoidCallback onPressed;
  const _OutlineButton({
    required this.label,
    required this.color,
    required this.onPressed,
  });

  @override
  State<_OutlineButton> createState() => _OutlineButtonState();
}

class _OutlineButtonState extends State<_OutlineButton> {
  bool _p = false;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTapDown: (_) => setState(() => _p = true),
    onTapUp: (_) {
      setState(() => _p = false);
      widget.onPressed();
    },
    onTapCancel: () => setState(() => _p = false),
    child: AnimatedScale(
      scale: _p ? 0.93 : 1.0,
      duration: const Duration(milliseconds: 110),
      curve: Curves.easeInOut,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 110),
        height: 44,
        decoration: BoxDecoration(
          color: _p ? widget.color.withValues(alpha: 0.08) : Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: widget.color, width: 1.4),
        ),
        alignment: Alignment.center,
        child: Text(
          widget.label,
          style: TextStyle(
            color: widget.color,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
    ),
  );
}
