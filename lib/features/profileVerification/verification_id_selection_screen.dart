import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../../core/router/legacy_nav.dart';
import '../../core/theme/citizen_ui.dart';
import '../../core/widgets/Home/Account/account_web_kit.dart';
import '../../core/widgets/mobile_form_shell.dart';

class VerificationIdSelectionScreen extends StatefulWidget {
  final String username;

  const VerificationIdSelectionScreen({super.key, required this.username});

  @override
  State<VerificationIdSelectionScreen> createState() =>
      _VerificationIdSelectionScreenState();
}

class _VerificationIdSelectionScreenState
    extends State<VerificationIdSelectionScreen>
    with SingleTickerProviderStateMixin {
  int selectedIndex = 0;
  bool isChecked = false;

  late final AnimationController _entryCtrl;
  late final Animation<Offset> _slideAnim;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutCubic));
    _fadeAnim = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) _entryCtrl.forward();
      });
    });
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    super.dispose();
  }

  final List<Map<String, String>> ids = [
    {
      "title": "PhilSys ID",
      "subtitle": "Recommended",
      "image": "assets/images/idcards/phfront.webp",
    },
    {
      "title": "Driver's License ID",
      "subtitle": "Recommended",
      "image": "assets/images/idcards/driversfront.webp",
    },
    {
      "title": "Postal ID",
      "subtitle": "Recommended",
      "image": "assets/images/idcards/postalfront.webp",
    },
    {
      "title": "Philippine Passport ID",
      "subtitle": "",
      "image": "assets/images/idcards/philpassfront.webp",
    },
    {
      "title": "PhilHealth ID",
      "subtitle": "",
      "image": "assets/images/idcards/phealthfront.webp",
    },
    {
      "title": "PRC ID",
      "subtitle": "",
      "image": "assets/images/idcards/prcharap.webp",
    },
    {
      "title": "SSS ID",
      "subtitle": "",
      "image": "assets/images/idcards/sssfront.webp",
    },
    {
      "title": "TIN ID",
      "subtitle": "",
      "image": "assets/images/idcards/tinfront.webp",
    },
    {
      "title": "UMID ID",
      "subtitle": "",
      "image": "assets/images/idcards/umidharap.webp",
    },
  ];

  // ==========================================================================
  //  WEB
  //
  //  Step 1 of 3. See [kVerificationSteps] for why the eight routes are three
  //  steps, and for the wizard's actual order.
  //
  //  The logo-and-caption block the phone opens with is dropped here, the same
  //  way it is on every other web screen in this section: it is a second GovPulse
  //  mark on a page that is already unmistakably GovPulse, and it pushed the
  //  first real content below the fold. [AccountPageTitle] says what the page is.
  // ==========================================================================

  Widget _buildWebScaffold() {
    return Scaffold(
      backgroundColor: CitizenUi.pageBg,
      body: SafeArea(
        child: AccountPageBody(
          builder: (context, stack) => FadeTransition(
            opacity: _fadeAnim,
            child: SlideTransition(
              position: _slideAnim,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AccountPageTitle(
                    title: 'Select your ID',
                    subtitle:
                        'Choose the government-issued ID you would like to '
                        'verify with.',
                    onBack: () => Navigator.pop(context),
                    backLabel: 'Back to Profile Verification',
                  ),
                  const AccountStepper(step: 0, labels: kVerificationSteps),

                  const AccountSectionLabel('Choose a government ID'),
                  AccountCard(child: _webIdGrid(stack)),
                  const SizedBox(height: kAccountSectionGap),

                  AccountNotice(
                    icon: Icons.info_outline_rounded,
                    title: 'Accepted IDs',
                    message:
                        'Only valid IDs are accepted. Verification is limited '
                        'to Aparri residents.',
                    stack: stack,
                  ),
                  const SizedBox(height: kAccountSectionGap),

                  _webConsent(),
                  const SizedBox(height: kAccountSectionGap),

                  _webContinueButton(stack),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The nine IDs: one per line when stacked, three across when there is room.
  ///
  /// Rows of [Expanded] under an [IntrinsicHeight] rather than a [GridView] with
  /// an aspect ratio. A ratio fixes the tile's HEIGHT from its width, so at 125%
  /// browser font size the longer names ("Philippine Passport ID") outgrow a box
  /// that was measured at 100%. Letting the tallest tile in a row set the height
  /// cannot overflow at any text scale.
  Widget _webIdGrid(bool stack) {
    final columns = stack ? 1 : 3;
    final rows = <Widget>[];

    for (var start = 0; start < ids.length; start += columns) {
      final slice = ids.sublist(
        start,
        (start + columns) > ids.length ? ids.length : start + columns,
      );
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < columns; i++) ...[
                if (i > 0) const SizedBox(width: kAccountGap),
                // A short final row keeps its columns open rather than letting
                // two tiles stretch across three columns' worth of space.
                Expanded(
                  child: i < slice.length
                      ? _webIdTile(start + i, slice[i])
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ),
      );
      if (start + columns < ids.length) {
        rows.add(const SizedBox(height: kAccountGap));
      }
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
  }

  Widget _webIdTile(int index, Map<String, String> item) {
    final selected = selectedIndex == index;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(CitizenUi.controlRadius),
      child: InkWell(
        onTap: () => setState(() => selectedIndex = index),
        borderRadius: BorderRadius.circular(CitizenUi.controlRadius),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected ? CitizenUi.accentWash : CitizenUi.surface,
            borderRadius: BorderRadius.circular(CitizenUi.controlRadius),
            border: Border.all(
              color: selected ? CitizenUi.accent : CitizenUi.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.asset(
                  item['image']!,
                  height: 40,
                  width: 60,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      item['title']!,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: CitizenUi.textPrimary,
                      ),
                    ),
                    if (item['subtitle']!.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      const Text(
                        'Recommended',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: CitizenUi.success,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                size: 20,
                color: selected ? CitizenUi.accent : CitizenUi.textFaint,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The consent line, with the whole sentence as the tap target.
  ///
  /// The phone's version is a bare [Checkbox] beside 10pt text, so on a desktop
  /// pointer the only thing you can click is an 18px square. The label is the
  /// part people aim at.
  Widget _webConsent() {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(CitizenUi.controlRadius),
      child: InkWell(
        onTap: () => setState(() => isChecked = !isChecked),
        borderRadius: BorderRadius.circular(CitizenUi.controlRadius),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: Checkbox(
                  value: isChecked,
                  activeColor: CitizenUi.accent,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onChanged: (val) => setState(() => isChecked = val ?? false),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'I consent to GovPulse processing my personal data.',
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.4,
                    color: CitizenUi.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Same green as the wizard's first screen.
  ///
  /// The phone uses 0xFF16A34A here and AppColors.green on the screen before it
  /// - two greens one tap apart. On web the wizard's primary action is one
  /// colour, [CitizenUi.accentGreen], and everything else about the button comes
  /// from [accountPrimaryButtonStyle] so it matches every other primary on the
  /// site. Mobile keeps both of its greens exactly as they are.
  Widget _webContinueButton(bool stack) {
    final button = ElevatedButton(
      onPressed: isChecked
          ? () => pushLegacy(
              context,
              '/verification_photo_instruction',
              arguments: {
                'username': widget.username,
                'selectedId': ids[selectedIndex]['title']!,
              },
            )
          : null,
      style: accountPrimaryButtonStyle().copyWith(
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? CitizenUi.accentGreen.withValues(alpha: 0.4)
              : CitizenUi.accentGreen,
        ),
      ),
      child: const Text('Continue'),
    );

    return stack
        ? SizedBox(width: double.infinity, child: button)
        : Row(mainAxisAlignment: MainAxisAlignment.end, children: [button]);
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return _buildWebScaffold();
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: const Color(0xFFF3F4F6),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SlideTransition(
          position: _slideAnim,
          child: SafeArea(
            child: MobileFormShell(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    const SizedBox(height: 10),

                    /// LOGO
                    Center(
                      child: Image.asset(
                        "assets/images/applogocrop.webp",
                        height: (MediaQuery.of(context).size.height * 0.12)
                            .clamp(44.0, 88.0),
                      ),
                    ),

                    const SizedBox(height: 16),

                    /// TITLE
                    const Text(
                      "Aparri Citizenship Verification",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color.fromARGB(255, 0, 106, 255),
                      ),
                    ),

                    const SizedBox(height: 25),

                    /// STEP INDICATOR
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _stepWithLabel("1", "Upload ID", true),
                          Expanded(child: _stepLine()),
                          _stepWithLabel("2", "Additional\nInformation", false),
                          Expanded(child: _stepLine()),
                          _stepWithLabel("3", "Identity\nVerification", false),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    /// SELECT ID TITLE
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        "Select ID",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Color.fromARGB(255, 0, 106, 255),
                        ),
                      ),
                    ),

                    const SizedBox(height: 6),

                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        "ID type",
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ),

                    const SizedBox(height: 10),

                    /// ID LIST
                    Column(
                      children: List.generate(ids.length, (index) {
                        final item = ids[index];
                        final isSelected = selectedIndex == index;

                        return GestureDetector(
                          onTap: () {
                            setState(() => selectedIndex = index);
                          },
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected
                                    ? const Color(0xFF2563EB)
                                    : Colors.grey.shade300,
                              ),
                            ),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: Image.asset(
                                    item["image"]!,
                                    height: 40,
                                    width: 60,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item["title"]!,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      if (item["subtitle"]!.isNotEmpty)
                                        const Text(
                                          "Recommended",
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.red,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  isSelected
                                      ? Icons.radio_button_checked
                                      : Icons.radio_button_off,
                                  color: isSelected
                                      ? const Color(0xFF2563EB)
                                      : Colors.grey,
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ),

                    /// INFO BOX
                    Container(
                      padding: const EdgeInsets.all(10),
                      margin: const EdgeInsets.only(top: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE5E7EB),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 14,
                            color: Colors.grey,
                          ),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              "Only valid IDs are accepted. Verification is limited to Aparri residents.",
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    /// CHECKBOX
                    Row(
                      children: [
                        Checkbox(
                          value: isChecked,
                          activeColor: const Color(0xFF2563EB),
                          onChanged: (val) {
                            setState(() => isChecked = val!);
                          },
                        ),
                        const Expanded(
                          child: Text(
                            "I consent to GovPulse processing my personal data.",
                            style: TextStyle(fontSize: 10),
                          ),
                        ),
                      ],
                    ),

                    /// BUTTON
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: isChecked
                            ? () {
                                pushLegacy(
                                  context,
                                  '/verification_photo_instruction',
                                  arguments: {
                                    "username": widget.username,
                                    "selectedId": ids[selectedIndex]["title"]!,
                                  },
                                );
                              }
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isChecked
                              ? const Color(0xFF16A34A)
                              : Colors.grey,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text("Continue"),
                      ),
                    ),

                    const SizedBox(height: 10),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _stepWithLabel(String number, String label, bool active) {
    return SizedBox(
      width: 54,
      child: Column(
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: active
                ? const Color(0xFF2563EB)
                : Colors.grey.shade300,
            child: Text(
              number,
              style: TextStyle(
                fontSize: 10,
                color: active ? Colors.white : Colors.black,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 8,
              color: active ? const Color(0xFF2563EB) : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepLine() {
    return Container(
      margin: const EdgeInsets.only(top: 11),
      height: 2,
      color: Colors.grey.shade300,
    );
  }
}
