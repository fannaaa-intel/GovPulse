import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_colors.dart';

class VerificationReviewScreen extends StatefulWidget {
  final String username;
  final String selectedId;
  final Uint8List? frontImage;
  final Uint8List? backImage;

  const VerificationReviewScreen({
    super.key,
    required this.username,
    required this.selectedId,
    this.frontImage,
    this.backImage,
  });

  @override
  State<VerificationReviewScreen> createState() =>
      _VerificationReviewScreenState();
}

class _VerificationReviewScreenState extends State<VerificationReviewScreen> {
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

  @override
  void initState() {
    super.initState();
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
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom],
    );
  }

  @override
  void dispose() {
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
        color: error ? AppColors.red : AppColors.stroke,
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
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset("assets/images/sad.png", width: 62, height: 62),
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
      child: Padding(
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
                "assets/images/info.png",
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
                        Navigator.pushNamed(
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

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );

    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: AppColors.inputBg,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        top: true,
        bottom: false,
        child: Column(
          children: [
            _buildHeader(context),
            _buildStepper(),
            Expanded(child: _buildForm()),
            _buildBottomButton(bottomPadding),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10, bottom: 8),
    child: Column(
      children: [
        Image.asset(
          "assets/images/applogocrop.png",
          height: MediaQuery.of(context).size.height * 0.10,
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
        Center(
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.primaryBlue, width: 2),
            ),
            child: widget.frontImage != null
                ? Image.memory(
                    widget.frontImage!,
                    height: 95,
                    fit: BoxFit.fitHeight,
                  )
                : Image.asset(
                    "assets/images/idcards/phfront.png",
                    height: 95,
                    fit: BoxFit.fitHeight,
                  ),
          ),
        ),
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
        _dropdown("Barangay", _barangay, [
          "Barangay 1",
          "Barangay 2",
          "Barangay 3",
        ], (v) => setState(() => _barangay = v)),
        const SizedBox(height: 10),
        _field(_streetController, "Street / House No."),
        const SizedBox(height: 24),
      ],
    ),
  );

  // ── Bottom confirm button ─────────────────────────────────────────────────

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

  // ── Small reusable widgets ────────────────────────────────────────────────

  Widget _sectionLabel(String t) => Text(
    t,
    style: const TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      color: AppColors.primaryBlue,
    ),
  );

  /// Generic text field with auto-scroll when focused
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
        style: const TextStyle(fontSize: 13),
        decoration: _inputDec(label, error: error),
      ),
    );
  }

  /// Dropdown with error highlight support
  Widget _dropdown(
    String label,
    String? value,
    List<String> items,
    ValueChanged<String?> onChanged, {
    bool required = true,
  }) {
    final error = required && _hasDropdownError(value);
    return DropdownButtonFormField<String>(
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
        border: Border.all(color: AppColors.stroke),
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
