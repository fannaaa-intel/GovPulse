import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../../core/theme/citizen_ui.dart';
import '../../core/widgets/Home/Account/account_web_kit.dart';
import '../../core/router/legacy_nav.dart';
import '../../core/widgets/mobile_form_shell.dart';

class VerificationPhotoInstructionScreen extends StatefulWidget {
  final String username;
  final String selectedId;

  const VerificationPhotoInstructionScreen({
    super.key,
    required this.username,
    required this.selectedId,
  });

  @override
  State<VerificationPhotoInstructionScreen> createState() =>
      _VerificationPhotoInstructionScreenState();
}

class _VerificationPhotoInstructionScreenState
    extends State<VerificationPhotoInstructionScreen>
    with SingleTickerProviderStateMixin {
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
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    super.dispose();
  }

  // ==========================================================================
  //  WEB
  //
  //  Still step 1 of 3 - see [kVerificationSteps]. This screen and the two
  //  around it are all "Upload ID"; it is the instructions, not a step of its
  //  own, which is why the stepper does not advance here.
  //
  //  The phone stacks the four rejected examples above the accepted one, which
  //  is the only thing a 480 column can do. Given the width, the two sit side by
  //  side: "not this" and "this" is a comparison, and a comparison you have to
  //  scroll between is one you cannot actually make.
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
                    title: 'Get your ${widget.selectedId} ready',
                    subtitle:
                        'Your ID should be original and not modified in any '
                        'form.',
                    onBack: () => Navigator.pop(context),
                    backLabel: 'Back to Select your ID',
                  ),
                  const AccountStepper(step: 0, labels: kVerificationSteps),

                  const AccountSectionLabel('Photo requirements'),
                  AccountCard(child: _webExamples(stack)),
                  const SizedBox(height: kAccountSectionGap),

                  const AccountSectionLabel('Tips for a good photo'),
                  const AccountCard(
                    child: Column(
                      children: [
                        _WebNoteRow(
                          icon: Icons.lightbulb_outline,
                          text:
                              'Please ensure you are in a well-lit area for '
                              'best results.',
                        ),
                        SizedBox(height: 12),
                        _WebNoteRow(
                          icon: Icons.crop_free,
                          text: 'Align your ID properly within the frame.',
                        ),
                      ],
                    ),
                  ),
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

  /// "Not accepted" beside "Correct example" when there is room, stacked when
  /// there is not.
  ///
  /// -- Why the four-up decision is made HERE and passed down ----------------
  /// [_WebExampleGroup] used to measure its own box with a [LayoutBuilder].
  /// That was the tidier-looking version and it crashed the page outright:
  /// [IntrinsicHeight] has to ask its subtree how tall it wants to be, and a
  /// LayoutBuilder cannot answer, because running its callback speculatively
  /// could mutate the live render tree. It throws "LayoutBuilder does not
  /// support returning intrinsic dimensions" instead, and every ancestor layout
  /// fails behind it.
  ///
  /// Nothing needs to measure, because the parent already knows: `stack` is
  /// false exactly when the content box is at least [kAccountStackBelow] wide,
  /// and at that width the left half is comfortably wider than four tiles need.
  /// Below it there is a single column and the tiles go two-by-two.
  Widget _webExamples(bool stack) {
    final bad = _WebExampleGroup(fourUp: !stack);
    const good = _WebGoodGroup();

    if (stack) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          bad,
          const SizedBox(height: kAccountSectionGap),
          good,
        ],
      );
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 3, child: bad),
          const SizedBox(width: kAccountSectionGap),
          // A hairline between the two halves, so "not this" and "this" read as
          // two claims rather than one run-on row of pictures.
          const VerticalDivider(
            width: 1,
            thickness: 1,
            color: CitizenUi.border,
          ),
          const SizedBox(width: kAccountSectionGap),
          const Expanded(flex: 2, child: good),
        ],
      ),
    );
  }

  /// Same green as every other step of the wizard on web. See the note in
  /// verification_id_selection_screen.
  Widget _webContinueButton(bool stack) {
    final button = ElevatedButton(
      onPressed: () => pushLegacy(
        context,
        '/verification_upload_id',
        arguments: {
          'username': widget.username,
          'selectedId': widget.selectedId,
        },
      ),
      style: accountPrimaryButtonStyle().copyWith(
        backgroundColor: const WidgetStatePropertyAll(CitizenUi.accentGreen),
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
              child: Column(
                children: [
                  const SizedBox(height: 10),

                  /// LOGO
                  Center(
                    child: Image.asset(
                      "assets/images/applogocrop.webp",
                      height: (MediaQuery.of(context).size.height * 0.12).clamp(
                        44.0,
                        88.0,
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  /// TITLE
                  const Text(
                    "Aparri Citizenship Verification",
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
                        _step("1", "Upload ID", true),
                        Expanded(child: _line()),
                        _step("2", "Additional\nInformation", false),
                        Expanded(child: _line()),
                        _step("3", "Identity\nVerification", false),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  /// HEADER TEXT
                  Text(
                    "Get your ${widget.selectedId} ready",
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),

                  const SizedBox(height: 16),

                  const Divider(thickness: 1),

                  /// PHOTO INSTRUCTION
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Photo Instruction",
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF2563EB),
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          "Your ID should be original and not modified in any form.",
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),

                        const SizedBox(height: 20),

                        /// BAD EXAMPLES
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: const [
                            _BadExample(
                              image: "assets/images/idicons/expired.webp",
                              label: "Expired",
                            ),
                            _BadExample(
                              image: "assets/images/idicons/blurry.webp",
                              label: "Blurry",
                            ),
                            _BadExample(
                              image: "assets/images/idicons/withglare.webp",
                              label: "With Glare",
                            ),
                            _BadExample(
                              image: "assets/images/idicons/dark.webp",
                              label: "Dark",
                            ),
                          ],
                        ),

                        const SizedBox(height: 20),

                        /// GOOD EXAMPLE
                        const Center(
                          child: Column(
                            children: [
                              _GoodExample(
                                image:
                                    "assets/images/idicons/correctsample.webp",
                              ),
                              SizedBox(height: 6),
                              Text(
                                "Correct example",
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  const Divider(thickness: 1),

                  /// NOTE BOX
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE5E7EB),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Column(
                        children: [
                          _NoteRow(
                            icon: Icons.lightbulb_outline,
                            text:
                                "Please ensure you are in a well-lit area for best results.",
                          ),
                          SizedBox(height: 8),
                          _NoteRow(
                            icon: Icons.crop_free,
                            text:
                                "Align your ID properly within the camera frame.",
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  /// BUTTON
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          pushLegacy(
                            context,
                            '/verification_upload_id',
                            arguments: {
                              "username": widget.username,
                              "selectedId": widget.selectedId,
                            },
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF16A34A),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text("Continue"),
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Widget _step(String number, String label, bool active) {
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

  static Widget _line() {
    return Container(
      margin: const EdgeInsets.only(top: 11),
      height: 2,
      color: Colors.grey.shade300,
    );
  }
}

class _BadExample extends StatelessWidget {
  final String image;
  final String label;

  const _BadExample({required this.image, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.red),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Image.asset(image, height: 40, width: 60, fit: BoxFit.cover),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 10)),
      ],
    );
  }
}

class _GoodExample extends StatelessWidget {
  final String image;

  const _GoodExample({required this.image});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.green),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Image.asset(image, height: 70),
    );
  }
}

class _NoteRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _NoteRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.blueGrey),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 11))),
      ],
    );
  }
}

// ==============================================================================
//  Web-only leaves. Nothing below is reachable from the mobile app.
//
//  The phone sets these captions at 10 and 11pt because four of them share a 480
//  column. On web they are set at the kit's sizes for the same reason every other
//  web screen in this section is: phone caption scale inside a desktop card reads
//  as a screenshot of the app rather than as the page you are on.
// ==============================================================================

/// The four rejected examples, four across when there is room and two-by-two
/// when there is not.
///
/// [fourUp] is passed in rather than measured, because this sits inside an
/// [IntrinsicHeight], which cannot measure a [LayoutBuilder]. See the note on
/// `_webExamples` above.
class _WebExampleGroup extends StatelessWidget {
  final bool fourUp;

  const _WebExampleGroup({required this.fourUp});

  static const _items = [
    ('assets/images/idicons/expired.webp', 'Expired'),
    ('assets/images/idicons/blurry.webp', 'Blurry'),
    ('assets/images/idicons/withglare.webp', 'With Glare'),
    ('assets/images/idicons/dark.webp', 'Dark'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Not accepted',
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: CitizenUi.danger,
          ),
        ),
        const SizedBox(height: 12),
        Builder(
          builder: (context) {
            final rows = fourUp
                ? [_items]
                : [_items.sublist(0, 2), _items.sublist(2)];
            return Column(
              children: [
                for (var r = 0; r < rows.length; r++) ...[
                  if (r > 0) const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < rows[r].length; i++) ...[
                        if (i > 0) const SizedBox(width: 10),
                        Expanded(
                          child: _WebBadExample(
                            image: rows[r][i].$1,
                            label: rows[r][i].$2,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _WebBadExample extends StatelessWidget {
  final String image;
  final String label;

  const _WebBadExample({required this.image, required this.label});

  /// The image is capped, NOT stretched to its column.
  ///
  /// It filled the column at first, which on a 577px phone browser made each
  /// of these roughly 240 wide and 150 tall - four thumbnails the size of the
  /// real thing, pushing the correct example off the bottom of the screen. The
  /// phone draws them at 60x40. These are illustrative thumbnails; past about
  /// this size the extra pixels say nothing more.
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 132),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: CitizenUi.danger),
                borderRadius: BorderRadius.circular(8),
              ),
              // AspectRatio rather than a fixed height: the tile is as wide as its
              // column, so a fixed height would letterbox it differently at every
              // measure. 1.586 is the CR80 card ratio the scan frame also uses.
              child: AspectRatio(
                aspectRatio: 1.586,
                child: Image.asset(image, fit: BoxFit.cover),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, color: CitizenUi.textMuted),
        ),
      ],
    );
  }
}

class _WebGoodGroup extends StatelessWidget {
  const _WebGoodGroup();

  @override
  Widget build(BuildContext context) {
    // The HEADING keeps the left edge - it is a label, and it lines up with
    // "Not accepted" beside it and with the section label above the card. Only
    // the exhibit itself is centred: it is a single capped image, and pinned
    // left in a column wider than itself it just looks like it failed to fill
    // the space.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Correct example',
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: CitizenUi.success,
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Capped for the same reason as [_WebBadExample]: full-bleed, this
              // was a 300px-tall picture of a sample ID on a phone browser.
              Container(
                constraints: const BoxConstraints(maxWidth: 260),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  border: Border.all(color: CitizenUi.success),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: AspectRatio(
                    aspectRatio: 1.586,
                    child: Image.asset(
                      'assets/images/idicons/correctsample.webp',
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Sharp, evenly lit, and fully inside the frame.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: CitizenUi.textMuted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WebNoteRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _WebNoteRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 17, color: CitizenUi.textFaint),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 13.5,
              height: 1.45,
              color: CitizenUi.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}
