import 'package:flutter/material.dart';
import '../../shell/citizen_shell_dialogs.dart'
    show FormDialogGuard, kSplitDialogFullscreenBelow;
import '../../../../core/widgets/Home/Quick-action/Web/quick_action_split_panel.dart';
import '../../../../core/theme/citizen_ui.dart';
import '../../../../core/widgets/responsive_page.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/modal/media_picker_sheet.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'dart:typed_data';
import 'package:video_player/video_player.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../Report/location_picker_screen.dart';
import '../../../../core/widgets/Home/Newsfeed/rate_limit_dialogs.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../../../core/services/gps_stamp_service.dart';
import '../../../../core/widgets/reveal_loading.dart';
import '../../../../core/widgets/app_dialog.dart';
import '../../../../core/utils/submission_id.dart';
import '../../../../core/utils/picked_media.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

// ── Video preview dialog (same as Report) ─────────────────────────────────────
class _VideoPreviewDialog extends StatefulWidget {
  final XFile file;
  final double width;
  const _VideoPreviewDialog({required this.file, required this.width});

  @override
  State<_VideoPreviewDialog> createState() => _VideoPreviewDialogState();
}

class _VideoPreviewDialogState extends State<_VideoPreviewDialog> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    // On web the picked file is a blob: URL, so dart:io cannot open it.
    _controller = kIsWeb
        ? VideoPlayerController.networkUrl(Uri.parse(widget.file.path))
        : VideoPlayerController.file(File(widget.file.path));
    _controller
        .initialize()
        .then((_) {
          if (!mounted) return;
          setState(() => _isInitialized = true);
          _controller.play();
        })
        .catchError((Object e) {
          debugPrint('Video init error: $e');
          return null;
        });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: Stack(
        children: [
          Center(
            child: _isInitialized
                ? AspectRatio(
                    aspectRatio: _controller.value.aspectRatio,
                    child: VideoPlayer(_controller),
                  )
                : const CircularProgressIndicator(color: Colors.white),
          ),
          if (_isInitialized)
            Center(
              child: GestureDetector(
                onTap: () => setState(() {
                  _controller.value.isPlaying
                      ? _controller.pause()
                      : _controller.play();
                }),
                child: Container(
                  color: Colors.transparent,
                  width: double.infinity,
                  height: double.infinity,
                ),
              ),
            ),
          if (_isInitialized)
            Center(
              child: ValueListenableBuilder(
                valueListenable: _controller,
                builder: (_, VideoPlayerValue value, _) => AnimatedOpacity(
                  opacity: value.isPlaying ? 0.0 : 1.0,
                  duration: const Duration(milliseconds: 300),
                  child: Container(
                    padding: EdgeInsets.all(widget.width * 0.04),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: widget.width * 0.12,
                    ),
                  ),
                ),
              ),
            ),
          if (_isInitialized)
            Positioned(
              bottom: 60,
              left: 16,
              right: 16,
              child: VideoProgressIndicator(
                _controller,
                allowScrubbing: true,
                colors: VideoProgressColors(
                  playedColor: Colors.white,
                  bufferedColor: Colors.white38,
                  backgroundColor: Colors.white24,
                ),
              ),
            ),
          Positioned(
            top: 40,
            right: 16,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: widget.width * 0.10,
                height: widget.width * 0.10,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close_rounded, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

/// Standalone Share a Suggestion page — the full-screen route the mobile app and the
/// live web route open. Chrome only; the form itself is [SuggestionForm].
class SuggestionScreen extends StatelessWidget {
  final String username;
  const SuggestionScreen({super.key, required this.username});

  @override
  Widget build(BuildContext context) => SuggestionForm(username: username);
}

/// The Share a Suggestion form.
///
/// `embedded: false` (the default) renders the whole page — PopScope discard
/// guard, Scaffold, the ResponsivePageBody hero panel and the in-page header —
/// exactly as before, which is what mobile and the live route still get.
///
/// `embedded: true` renders ONLY the scrolling form, for the web shell's big
/// dialog: the dialog supplies the bounds, the title and the close button, and
/// the decorative hero panel is dropped because it is pure waste in a modal.
/// [guard] lets the dialog's close button reuse this form's discard
/// confirmation.
///
/// `splitPanel: true` renders the SAME sections as the two-column web panel
/// Report draws — a stepper over the working area on the left, a live summary
/// and the buttons on the right. Only the citizen web shell passes it. See
/// [_splitPanelBody] for why every section is still built on every step.
class SuggestionForm extends StatefulWidget {
  final String username;
  final bool embedded;
  final FormDialogGuard? guard;

  /// Two-column web layout. Default false, and the default is what mobile, the
  /// native-tablet home body and the standalone route all get — none of them
  /// pass this, so their widget tree is unchanged.
  final bool splitPanel;

  /// Dismisses the hosting dialog. Only read in the [splitPanel] branch, whose
  /// rail owns the × and the Cancel button.
  final VoidCallback? onClose;

  const SuggestionForm({
    super.key,
    required this.username,
    this.embedded = false,
    this.guard,
    this.splitPanel = false,
    this.onClose,
  });

  @override
  State<SuggestionForm> createState() => _SuggestionScreenState();
}

class _SuggestionScreenState extends State<SuggestionForm>
    with TickerProviderStateMixin {
  late final AnimationController _entryCtrl;

  // ── Form state ─────────────────────────────────────────────────────────────
  String? _selectedCategory;
  final TextEditingController _othersCtrl = TextEditingController();
  final TextEditingController _detailsCtrl = TextEditingController();
  final TextEditingController _streetDetailCtrl = TextEditingController();
  bool _submitAnonymously = false;
  bool _isSubmitting = false;
  final List<XFile> _attachedFiles = [];
  static const int _maxFiles = 6;
  final ImagePicker _picker = ImagePicker();
  bool _consentInEnglish = true;

  /// Paths of camera-captured attachments that carry a baked-in GPS stamp.
  /// Everything else (gallery photos, videos) is an unverified upload.
  final Set<String> _gpsVerifiedPaths = {};

  /// Paths of attachments still being processed — camera photos baking a GPS
  /// stamp, gallery images decoding, or videos generating a thumbnail. Their
  /// tile shows an in-place bottom-to-top reveal and Submit is guarded until
  /// they finish.
  final Set<String> _processingPaths = {};

  /// Paths whose work has just finished: the tile's reveal is still mounted but
  /// now plays its closing sweep to the very top + fade-out. Cleared (together
  /// with [_processingPaths]) once the reveal reports it has finished.
  final Set<String> _completedPaths = {};

  /// Generated video-thumbnail bytes, keyed by file path.
  final Map<String, Uint8List> _thumbCache = {};

  /// Minimum time a tile's reveal stays visible so quick items still animate.
  static const Duration _minReveal = Duration(milliseconds: 500);

  // ── Location state (OPTIONAL for suggestions) ──────────────────────────────
  LatLng? _pickedLatLng;
  String? _pickedBarangay;
  bool _useCurrentLocation = false;

  // ── Split-panel step (web only) ───────────────────────────────────────────
  /// Which step the two-column web panel is showing. Read ONLY by the
  /// `widget.splitPanel` branch; mobile and the standalone route never look at
  /// it, so it cannot change what they render.
  int _splitStep = 0;

  /// The working area's scroll position, so changing step can return it to the
  /// top. Web only — an unattached controller costs a mobile build nothing.
  final ScrollController _splitScrollCtrl = ScrollController();

  static const List<String> _kSplitSteps = [
    'Category',
    'Location',
    'Details',
    'Review',
  ];

  /// Which PANE the stacked panel is showing: 0 = Suggestion, 1 = Summary.
  /// A pane is never refused; a step is. See Report's `_splitTab` for why the
  /// two are drawn as visibly different controls.
  int _splitTab = 0;

  static const List<String> _kSplitTabs = ['Suggestion', 'Summary'];

  /// Inline error under the offending field on the current split-panel step,
  /// and which field it belongs under ('category' | 'details').
  ///
  /// It never reaches `_validate()` or `_submitSuggestion()` — those stay the
  /// sole authority on what may be filed.
  String? _stepError;
  String? _stepErrorField;

  /// Whether [_stepError] belongs under [field] right now.
  bool _errorOn(String field) => _stepError != null && _stepErrorField == field;

  /// Drops the inline error once the citizen acts on the field it named.
  void _clearStepError(String field) {
    if (_errorOn(field)) {
      _stepError = null;
      _stepErrorField = null;
    }
  }

  bool _hasAnyInput() {
    return _selectedCategory != null ||
        _othersCtrl.text.isNotEmpty ||
        _detailsCtrl.text.isNotEmpty ||
        _streetDetailCtrl.text.isNotEmpty ||
        _attachedFiles.isNotEmpty ||
        _submitAnonymously ||
        _pickedBarangay != null;
  }

  // ── Categories (suggestion-specific) ───────────────────────────────────────
  final List<Map<String, dynamic>> _categories = [
    {
      'key': 'public_service',
      'label': 'Public\nService',
      'icon': 'assets/images/suggestion/courthouse.webp',
      'fallbackIcon': Icons.account_balance_rounded,
    },
    {
      'key': 'community_program',
      'label': 'Community\nProgram',
      'icon': 'assets/images/suggestion/group.webp',
      'fallbackIcon': Icons.groups_rounded,
    },
    {
      'key': 'health_safety',
      'label': 'Health &\nSafety',
      'icon': 'assets/images/suggestion/health.webp',
      'fallbackIcon': Icons.health_and_safety_rounded,
    },
    {
      'key': 'infrastructure',
      'label': 'Infrastructure',
      'icon': 'assets/images/suggestion/building.webp',
      'fallbackIcon': Icons.apartment_rounded,
    },
    {
      'key': 'environment',
      'label': 'Environment &\nCleanliness',
      'icon': 'assets/images/suggestion/trees.webp',
      'fallbackIcon': Icons.eco_rounded,
    },
    {
      'key': 'others',
      'label': 'Others',
      'icon': 'assets/images/report/menu.webp',
      'fallbackIcon': Icons.more_horiz,
    },
  ];

  // ─────────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    // Let the shell's dialog reuse this form's discard confirmation when it is
    // closed from the outside. Passed DOWN via widget.guard, never looked up.
    widget.guard?.confirmDiscard = _showDiscardConfirmation;
    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 80), () {
        if (mounted) _entryCtrl.forward();
      });
    });
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    _othersCtrl.dispose();
    _detailsCtrl.dispose();
    _streetDetailCtrl.dispose();
    _splitScrollCtrl.dispose();
    super.dispose();
  }

  Future<bool> _showDiscardConfirmation() async {
    if (!_hasAnyInput()) return true;

    FocusScope.of(context).unfocus();
    await Future.delayed(const Duration(milliseconds: 50));
    if (!mounted) return false;

    final result = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Discard',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 280),
      transitionBuilder: (ctx, anim, secondAnim, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutBack);
        return FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
          child: ScaleTransition(scale: curved, child: child),
        );
      },
      pageBuilder: (ctx, anim, secondAnim) {
        final width = MediaQuery.of(ctx).size.width.clamp(0.0, 480.0);
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              // Without a cap this confirm stretches the full viewport on web,
              // leaving one short sentence spread across a metre of screen and
              // the two buttons a mouse-drag apart.
              constraints: const BoxConstraints(maxWidth: 400),
              margin: EdgeInsets.symmetric(horizontal: width * 0.07),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Theme.of(ctx).dialogBackgroundColor,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F4F6),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.edit_off_rounded,
                      color: Color(0xFF6B7280),
                      size: 30,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Discard changes?',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1F2937),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'You have unsaved information. Are you sure you want to go back? All your entries will be lost.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFF6B7280),
                      height: 1.55,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: AppColors.primaryBlue),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: Text(
                            'Keep editing',
                            style: TextStyle(
                              color: AppColors.primaryBlue,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: const Text(
                            'Discard',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    FocusManager.instance.primaryFocus?.unfocus();
    return result ?? false;
  }

  // ── Open location picker (optional for suggestions) ────────────────────────
  Future<void> _openLocationPicker() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      PageRouteBuilder(
        pageBuilder: (_, _, _) => LocationPickerScreen(
          initialPosition: _pickedLatLng,
          initialBarangay: _pickedBarangay,
        ),
        transitionDuration: const Duration(milliseconds: 380),
        reverseTransitionDuration: const Duration(milliseconds: 300),
        transitionsBuilder: (_, animation, _, child) {
          return FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: child,
          );
        },
      ),
    );

    if (result != null && mounted) {
      _applyLocationResult(result);
    }
  }

  /// Folds a confirmed pick into the form's location state.
  ///
  /// Extracted so the pushed picker (mobile, the standalone route) and the
  /// inline picker (the web split panel's step 2) run byte-identical code —
  /// they differ only in how the map gets here, never in what it does.
  void _applyLocationResult(Map<String, dynamic> result) {
    setState(() {
      _pickedLatLng = result['latLng'] as LatLng?;
      _pickedBarangay = result['barangay'] as String?;
      _useCurrentLocation = result['useCurrentLocation'] as bool? ?? false;
    });
  }

  void _clearLocation() {
    setState(() {
      _pickedLatLng = null;
      _pickedBarangay = null;
      _useCurrentLocation = false;
      _streetDetailCtrl.clear();
    });
  }

  // ── Animations ──────────────────────────────────────────────────────────────
  Animation<double> _fade(int i) => Tween<double>(begin: 0, end: 1).animate(
    CurvedAnimation(
      parent: _entryCtrl,
      curve: Interval(
        (i * 0.15).clamp(0.0, 1.0),
        ((i * 0.15) + 0.55).clamp(0.0, 1.0),
        curve: Curves.easeOut,
      ),
    ),
  );

  Animation<Offset> _slide(int i) =>
      Tween<Offset>(begin: const Offset(0, 0.28), end: Offset.zero).animate(
        CurvedAnimation(
          parent: _entryCtrl,
          curve: Interval(
            (i * 0.15).clamp(0.0, 1.0),
            ((i * 0.15) + 0.55).clamp(0.0, 1.0),
            curve: Curves.easeOutCubic,
          ),
        ),
      );

  Widget _animated(int i, Widget child) => FadeTransition(
    opacity: _fade(i),
    child: SlideTransition(position: _slide(i), child: child),
  );

  // ─────────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width.clamp(0.0, 480.0);

    // The citizen web shell's two-column panel. Checked FIRST because it is the
    // most specific host; the two branches below are untouched.
    if (widget.splitPanel) {
      return GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: _splitPanelBody(width),
      );
    }

    // Inside the shell's dialog the dialog owns the header, the close button and
    // the bounds; the form just scrolls in it. The decorative hero panel is
    // dropped — it is pure waste in a modal. The discard guard moves to the
    // dialog's close path via [widget.guard].
    if (widget.embedded) {
      return GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: _formScroll(width),
          ),
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        final shouldPop = await _showDiscardConfirmation();
        if (shouldPop && mounted) navigator.pop();
      },
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: Scaffold(
          backgroundColor: const Color(0xFFF3F4F6),
          body: ResponsivePageBody(
            maxWidth: 640,
            shellTitle: 'Share a Suggestion',
            shellSubtitle:
                'Have an idea to improve Aparri? Send it straight to your '
                'local government.',
            shellIcon: Icons.lightbulb_outline_rounded,
            shellHighlights: const [
              (Icons.edit_note_rounded, 'Describe your idea'),
              (Icons.category_outlined, 'Pick a category'),
              (Icons.how_to_vote_outlined, 'Help shape decisions'),
            ],
            shellContentWidth: 600,
            child: SafeArea(
              child: Column(
                children: [
                  _buildHeader(width),
                  Expanded(child: _formScroll(width)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The form itself — every section, scrolling, with no page chrome around it.
  /// Extracted so the shell can host it in a dialog while the standalone screen
  /// keeps rendering it under its own header.
  Widget _formScroll(double width) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.only(bottom: width * 0.06),
      child: Column(
        children: [
          SizedBox(height: width * 0.04),
          _animated(0, _buildCategorySection(width)),
          SizedBox(height: width * 0.04),
          _animated(1, _buildLocationSection(width)),
          SizedBox(height: width * 0.04),
          _animated(2, _buildDetailsSection(width)),
          SizedBox(height: width * 0.04),
          _animated(3, _buildAttachSection(width)),
          SizedBox(height: width * 0.04),
          _animated(4, _buildAnonymousSection(width)),
          SizedBox(height: width * 0.035),
          _animated(5, _buildDisclaimer(width)),
          SizedBox(height: width * 0.045),
          _animated(5, _buildSubmitButton(width)),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  Split panel (citizen web only)
  // ══════════════════════════════════════════════════════════════════════════
  //
  //  The same two-column panel Report draws, on the same shared chrome
  //  (quick_action_split_panel.dart) and with the same four steps. What differs
  //  is what the steps REQUIRE, not how they look — see [_splitStepGate].

  /// The two-column web layout.
  ///
  /// ── Every section is built on every step ─────────────────────────────────
  /// The four steps switch VISIBILITY, not construction: each group is wrapped
  /// in an [Offstage], which leaves the widget mounted and its state intact
  /// while skipping layout and paint. So no TextEditingController is torn down
  /// mid-form, no picked file or lat/lng is dropped by moving between steps,
  /// and `_validate()` at submit sees exactly the same state it sees on mobile.
  ///
  /// ── The review step has no copy of the data ──────────────────────────────
  /// [_splitReviewStep] reads `_selectedCategory`, `_pickedBarangay`,
  /// `_detailsCtrl` and friends directly on each build — the very fields the
  /// inputs write to — so it cannot drift from them.
  Widget _splitPanelBody(double width) {
    // Rebuild the summary and the review as the citizen types. Scoped to this
    // branch rather than added as initState listeners, so mobile keeps its
    // existing rebuild behaviour untouched.
    return AnimatedBuilder(
      animation: Listenable.merge([
        _detailsCtrl,
        _streetDetailCtrl,
        _othersCtrl,
      ]),
      builder: (context, _) => QaSplitPanel(
        left: (stacked) => _splitLeftPanel(width, stacked),
        right: (stacked) => _splitRightRail(stacked),
      ),
    );
  }

  // ── Left panel ────────────────────────────────────────────────────────────

  /// The instruction block's copy for the step in hand.
  ///
  /// Steps 2 and 3 say "optional" in as many words. That is the one place the
  /// panel is allowed to differ from Report's: a step whose gate will never
  /// refuse must SAY so, or a citizen reasonably assumes the Continue button is
  /// waiting on them to pin a map they have no location for.
  (String title, String body) _splitStepCopy() {
    return switch (_splitStep) {
      0 => (
        'Step 1 — What is your suggestion about?',
        'Pick the category that best fits your idea. Choose "Others" if none '
            'of them fit and tell us in a few words.',
      ),
      1 => (
        'Step 2 — Where would it apply? (Optional)',
        'If your idea is about a specific place, pin it so the Municipality '
            'of Aparri knows where you mean. You can skip this entirely.',
      ),
      2 => (
        'Step 3 — Describe your idea',
        'Tell us what you are proposing and why it would help. Photos or '
            'video are optional, but they make an idea easier to picture.',
      ),
      _ => (
        'Step 4 — Check before you send',
        'Everything below is what will be sent. Use the steps above to go '
            'back and change anything.',
      ),
    };
  }

  /// The four steps, stacked as [Offstage] siblings. Identical in both layouts —
  /// only what is wrapped AROUND it differs.
  Widget _splitStepStack(double width) {
    return Center(
      child: ConstrainedBox(
        // The location section still renders against the 480px
        // mobile-proportional scale, so the column is capped to keep it from
        // stretching into something that scale never anticipated. 700 does not
        // bind at the dialog's own maximum, which is deliberate: the category
        // grid is meant to run the full width of the panel.
        constraints: const BoxConstraints(maxWidth: 700),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Offstage, NOT `if` — see [_splitPanelBody]'s doc.
            Offstage(offstage: _splitStep != 0, child: _splitCategoryStep()),
            Offstage(
              offstage: _splitStep != 1,
              child: _splitLocationStep(width),
            ),
            Offstage(
              offstage: _splitStep != 2,
              child: Column(
                children: [
                  _buildDetailsSection(width, bare: true),
                  const SizedBox(height: 18),
                  _buildAttachSection(width, bare: true),
                  const SizedBox(height: 18),
                  _splitAnonymousRow(),
                ],
              ),
            ),
            Offstage(offstage: _splitStep != 3, child: _splitReviewStep(width)),
          ],
        ),
      ),
    );
  }

  /// The working card: a fixed head over a scrolling working area.
  ///
  /// ── What [stacked] changes, and why ──────────────────────────────────────
  /// Side by side this card is one of two columns and the rail beside it owns
  /// the panel's identity — its title, its × and its summary. Stacked there is
  /// no rail: [QaSplitPanel] reduces `right` to the pinned action zone, so this
  /// card becomes zones 1 and 2 of the three and takes on what the rail can no
  /// longer carry.
  Widget _splitLeftPanel(double width, bool stacked) {
    final (String title, String body) = _splitStepCopy();

    // Phone-web, derived LOCALLY and only where it is used: `stacked` short
    // circuits, so the side-by-side path never even reads the size. It is the
    // host's own fullscreen threshold, not a second copy that can drift.
    final bool phone =
        stacked &&
        MediaQuery.sizeOf(context).width < kSplitDialogFullscreenBelow;

    return QaPanelCard(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        // Fit the card to the step, not to the height on offer. A
        // `MainAxisSize.max` column would answer "all of it" and put the dead
        // space straight back.
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Zone 1: the fixed head ───────────────────────────────────────
          if (stacked) ...[
            QaRailHeader(
              title: 'Share a Suggestion',
              onClose: widget.onClose ?? () {},
              useBackArrow: phone,
            ),
            const SizedBox(height: 14),
            QaSegmentedTabs(
              labels: _kSplitTabs,
              selected: _splitTab,
              onSelect: (i) => setState(() => _splitTab = i),
            ),
            const SizedBox(height: 14),
          ] else ...[
            const QaPanelTitle('Share a Suggestion'),
            const SizedBox(height: 16),
            QaStepper(
              labels: _kSplitSteps,
              current: _splitStep,
              onSelect: _onStepperTap,
            ),
            const SizedBox(height: 16),
            QaInstructionBlock(title: title, body: body),
            const SizedBox(height: 16),
          ],

          // ── Zone 2: the working area, the panel's only scroller ──────────
          _splitScrollable(
            child: stacked
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Offstage, NOT `if` — keeping the pane mounted is what
                      // makes a glance at the Summary cost nothing.
                      Offstage(
                        offstage: _splitTab != 0,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            QaStepper(
                              labels: _kSplitSteps,
                              current: _splitStep,
                              onSelect: _onStepperTap,
                              compact: true,
                            ),
                            const SizedBox(height: 16),
                            QaInstructionBlock(title: title, body: body),
                            const SizedBox(height: 16),
                            _splitStepStack(width),
                          ],
                        ),
                      ),
                      Offstage(
                        offstage: _splitTab != 1,
                        child: _splitSummaryBlock(),
                      ),
                    ],
                  )
                : _splitStepStack(width),
          ),
        ],
      ),
    );
  }

  /// Wraps the working area in the panel's one scroll view.
  ///
  /// `Expanded` gives the scroll view the whole remaining column, and the
  /// `minHeight` makes its CONTENT at least that tall — so the [Center] already
  /// wrapping the step splits a short step's surplus evenly above and below
  /// instead of letting it pool at the bottom as one dead band.
  Widget _splitScrollable({required Widget child}) {
    return Expanded(
      child: LayoutBuilder(
        builder: (context, c) => SingleChildScrollView(
          controller: _splitScrollCtrl,
          physics: const BouncingScrollPhysics(),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: c.maxHeight),
            child: child,
          ),
        ),
      ),
    );
  }

  /// Moves the panel to [step] and returns the working area to the top.
  ///
  /// All four steps share ONE scroll view, so without this a citizen who
  /// scrolled to the bottom of one step arrives at the next already scrolled
  /// past its first field.
  void _goToSplitStep(int step) {
    setState(() => _splitStep = step);
    if (_splitScrollCtrl.hasClients) _splitScrollCtrl.jumpTo(0);
  }

  // ── Per-step gates ────────────────────────────────────────────────────────

  /// What [step] still needs before it may be left, or null if it is satisfied.
  /// Returns the message and the field it belongs under.
  ///
  /// The one authority on step-to-step progress: both ways forward consult it —
  /// [_continueSplitStep] for the step in hand, [_onStepperTap] for every step
  /// it would skip over — so there is exactly one set of rules and one set of
  /// words for them.
  ///
  /// ── Where this deliberately differs from Report ──────────────────────────
  /// A suggestion may be filed with no location and no attachment; a report may
  /// not. So step 1 has NO gate at all and step 2 gates only the description,
  /// which is exactly what `_validate()` already refuses to submit without.
  /// These are the SAME conditions `_validate()` checks, split across the steps
  /// that own them and worded identically, so a citizen never sees one message
  /// here and a different one at submit. Gating the optional steps anyway would
  /// make the web panel stricter than every other client — a citizen with a
  /// borough-wide idea and no map pin simply could not reach Submit.
  (String message, String field)? _splitStepGate(int step) {
    switch (step) {
      case 0:
        // Mirrors the first two checks in _validate().
        if (_selectedCategory == null) {
          return ('Please select a suggestion category.', 'category');
        }
        if (_selectedCategory == 'others' && _othersCtrl.text.trim().isEmpty) {
          return ('Please specify the category under "Others".', 'category');
        }
      // case 1 (location) is intentionally absent: optional, so never refused.
      case 2:
        // Mirrors _validate()'s description check.
        if (_detailsCtrl.text.trim().isEmpty) {
          return ('Please describe your suggestion in detail.', 'details');
        }
        // Mirrors _validate()'s processing check. Attachments themselves are
        // optional, but a HALF-BAKED one is not — the file would upload without
        // its GPS stamp.
        if (_processingPaths.isNotEmpty) {
          return ('Please wait for your photo to finish processing.', 'attach');
        }
    }
    return null;
  }

  /// A tap on one of the stepper's numbers.
  ///
  /// Backwards is free — re-reading your own answer is never blocked. Forwards
  /// walks the steps in between and stops at the first one that is not
  /// satisfied, MOVING to it and raising the same message [_continueSplitStep]
  /// raises, because a tap that appears to do nothing reads as a broken control.
  void _onStepperTap(int step) {
    if (step <= _splitStep) {
      _goToSplitStep(step);
      return;
    }
    for (var i = 0; i < step; i++) {
      final gate = _splitStepGate(i);
      if (gate == null) continue;
      setState(() {
        _stepError = gate.$1;
        _stepErrorField = gate.$2;
      });
      if (i != _splitStep) _goToSplitStep(i);
      return;
    }
    _goToSplitStep(step);
  }

  /// Continue: gate the CURRENT step, then advance. Never skips ahead, never
  /// touches the submit path.
  void _continueSplitStep() {
    final gate = _splitStepGate(_splitStep);
    if (gate != null) {
      setState(() {
        _stepError = gate.$1;
        _stepErrorField = gate.$2;
      });
      return;
    }
    setState(() {
      _stepError = null;
      _stepErrorField = null;
    });
    _goToSplitStep(_splitStep + 1);
  }

  /// The inline message under a field, when it is the one that failed AND the
  /// condition it names is still unsatisfied.
  ///
  /// Re-checking the live gate is what clears the message the instant the
  /// citizen fixes the field, without any shared handler having to know this
  /// error exists.
  Widget _splitFieldError(String field) {
    if (!_errorOn(field)) return const SizedBox.shrink();
    final live = _splitStepGate(_splitStep);
    if (live == null || live.$2 != field) return const SizedBox.shrink();
    return QaFieldError(_stepError);
  }

  // ── Step 1: category ──────────────────────────────────────────────────────

  /// The category grid, sized to the PANEL rather than to the 480px mobile
  /// scale, with the numbered section card dropped — the stepper already says
  /// this is step 1.
  ///
  /// Reads and writes `_selectedCategory` and `_othersCtrl`, the same two
  /// fields the mobile grid writes to; `_categories` is the same list.
  Widget _splitCategoryStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const QaFieldLabel(
          'Select a category',
          hint: 'Required',
          hintColor: CitizenUi.danger,
        ),
        LayoutBuilder(
          builder: (context, c) {
            // Three across, filling whatever the panel gives us, sized from
            // that width rather than from a viewport fraction. Category is the
            // SHORTEST step and the panel's frame is fixed, so the tiles are
            // what stands between "a grid of choices" and "six small boxes
            // floating in an empty card". Below ~300 the fixed 64px icon disc
            // makes three across overflow sideways, so it drops to two.
            final cols = c.maxWidth < 300 ? 2 : 3;
            const gap = 14.0;
            final tileW = (c.maxWidth - gap * (cols - 1)) / cols;
            final tileH = (tileW * 0.95).clamp(138.0, 205.0);

            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final cat in _categories)
                  SizedBox(
                    width: tileW,
                    height: tileH,
                    child: QaChoiceTile(
                      // Pinned to the CATEGORY, not to its position — without a
                      // key a rebuild can hand a tile's State, and with it its
                      // live hover flag, to a different tile.
                      key: ValueKey(cat['key']),
                      selected: _selectedCategory == cat['key'],
                      onTap: () => setState(() {
                        _selectedCategory = cat['key'] as String;
                        _clearStepError('category');
                      }),
                      // The grid labels carry a hard wrap sized for a phone
                      // tile; the web tile is wider, so let it flow.
                      label: (cat['label'] as String).replaceAll('\n', ' '),
                      icon: Image.asset(
                        cat['icon'] as String,
                        width: 34,
                        height: 34,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) =>
                            Icon(cat['fallbackIcon'] as IconData),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        if (_selectedCategory == 'others') ...[
          const SizedBox(height: 16),
          const QaFieldLabel('Specify the category'),
          TextField(
            controller: _othersCtrl,
            maxLength: 50,
            style: const TextStyle(fontSize: 13.5),
            onChanged: (_) => setState(() => _clearStepError('category')),
            decoration: qaInputDecoration(hint: 'Describe it in a few words…'),
          ),
        ],
        _splitFieldError('category'),
      ],
    );
  }

  // ── Step 2: location, hosted inline ───────────────────────────────────────

  /// The Edit Location picker, rendered INSIDE the panel instead of pushed as a
  /// route.
  ///
  /// Same widget, same GPS logic, same barangay list — the only difference is
  /// that `onConfirm` is non-null, so a pick hands the result map straight to
  /// [_applyLocationResult] rather than popping a route. Nothing here dismisses
  /// the dialog or navigates.
  ///
  /// ── Optional, and it says so ─────────────────────────────────────────────
  /// A suggestion may be filed with no location, and the panel has to make that
  /// visible rather than merely permitted: the label reads "Optional", the
  /// callout in the rail says the step can be skipped, and once a pin IS set a
  /// Remove control puts the citizen back to no location — otherwise a stray
  /// pick would be permanent, since there is no route to pop back out of.
  Widget _splitLocationStep(double width) {
    final hasLocation = _pickedLatLng != null && _pickedBarangay != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: QaFieldLabel('Pin a location', hint: 'Optional'),
            ),
            if (hasLocation)
              TextButton.icon(
                onPressed: _clearLocation,
                icon: const Icon(Icons.close_rounded, size: 15),
                label: const Text('Remove'),
                style: TextButton.styleFrom(
                  foregroundColor: CitizenUi.danger,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32),
                  textStyle: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
        LocationPickerScreen(
          key: const ValueKey('inline-picker'),
          initialPosition: _pickedLatLng,
          initialBarangay: _pickedBarangay,
          onConfirm: _applyLocationResult,
        ),

        // The optional street detail, which the mobile section also shows only
        // once a location resolves. Same `_streetDetailCtrl`, at panel scale.
        if (hasLocation) ...[
          const SizedBox(height: 18),
          const QaFieldLabel(
            'Street name & detailed location',
            hint: 'Optional',
          ),
          TextField(
            controller: _streetDetailCtrl,
            maxLines: 2,
            style: const TextStyle(fontSize: 13.5),
            decoration: qaInputDecoration(
              hint: 'e.g. Near the church, beside the market…',
            ),
          ),
        ],
      ],
    );
  }

  // ── Step 3: details ───────────────────────────────────────────────────────

  /// The description field at panel scale. Same `_detailsCtrl`, same
  /// `maxLength: 2500` (the 0/2500 counter is Flutter's, drawn from it), same
  /// `onChanged` — only the metrics differ.
  Widget _splitDetailsField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const QaFieldLabel('Describe your suggestion', hint: 'Required'),
        TextField(
          controller: _detailsCtrl,
          maxLength: 2500,
          maxLines: 6,
          style: const TextStyle(fontSize: 13.5, height: 1.45),
          onChanged: (_) => setState(() => _clearStepError('details')),
          decoration: qaInputDecoration(
            hint: 'What are you proposing, and how would it help?',
          ),
        ),
        _splitFieldError('details'),
      ],
    );
  }

  /// The panel's attachment area: one square "Add file" tile followed by the
  /// attached files as square tiles.
  ///
  /// The tiles themselves are [_attachFileTile] — the same previews, video
  /// thumbnails, processing reveal and delete buttons the mobile grid draws.
  /// Only the grid delegate and the leading tile are different.
  Widget _splitAttachGrid(double width) {
    final canAdd = _attachedFiles.length < _maxFiles;
    // Leading dropzone tile, then one tile per file.
    final itemCount = (canAdd ? 1 : 0) + _attachedFiles.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const QaFieldLabel('Photos or video', hint: 'Optional'),
        // ── Reflow, don't shrink ────────────────────────────────────────────
        // Sized by EXTENT rather than by a fixed column count, so a narrowing
        // column drops a column instead of driving the square TILE down with
        // it. 170 puts the 4→5 boundary at 720px of grid — above the 700 the
        // working column is capped at — so every side-by-side width draws
        // exactly four; below, the boundaries fall at ~540 (3 across) and ~360
        // (2). The smallest tile it can produce is ~85px, which clears the
        // ~57px the dropzone's icon/label/counter stack needs.
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 170,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1, // square
          ),
          itemCount: itemCount,
          itemBuilder: (context, index) {
            if (canAdd && index == 0) {
              return QaDropzoneTile(
                count: _attachedFiles.length,
                max: _maxFiles,
                onTap: _pickMedia,
              );
            }
            return _attachFileTile(canAdd ? index - 1 : index, width);
          },
        ),
        const SizedBox(height: 8),
        const Text(
          'Image: JPG, PNG (Max. 10MB)  ·  Video: MP4 (Max. 50MB)',
          style: TextStyle(fontSize: 11.5, color: CitizenUi.textFaint),
        ),
        _splitFieldError('attach'),
      ],
    );
  }

  /// "Submit anonymously" as a single compact row.
  ///
  /// Writes the same `_submitAnonymously` field and goes through the same
  /// `_showAnonymousConsentDialog` on the way on, so the consent copy a citizen
  /// must read is identical to mobile's — only the row around it is smaller.
  Widget _splitAnonymousRow() {
    return QaAnonymousRow(
      value: _submitAnonymously,
      // Same gate as the mobile card: turning it ON asks for consent first,
      // turning it OFF is immediate.
      onChanged: (v) {
        if (v) {
          _showAnonymousConsentDialog();
        } else {
          setState(() => _submitAnonymously = false);
        }
      },
    );
  }

  // ── Step 4: review ────────────────────────────────────────────────────────

  /// The DETAILED render of the suggestion, in the left working area.
  ///
  /// The left panel is the main area on every step and the rail is the summary
  /// on every step; Review keeps that. So this is the full, rendered
  /// suggestion — the category as its own tile, the real description in a
  /// field-shaped box, the actual photo thumbnails — while the rail goes on
  /// showing the same compact list it shows on steps 1–3. Nothing swaps sides.
  ///
  /// Every value is read straight off the fields the inputs write to, so the
  /// detail and the rail are two renderings of one state, not two copies of it.
  Widget _splitReviewStep(double width) {
    final street = _streetDetailCtrl.text.trim();
    final details = _detailsCtrl.text.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Category, as its selected tile ────────────────────────────────
        const QaFieldLabel('Category'),
        _splitReviewCategoryTile(),
        const SizedBox(height: 16),

        // ── Location ──────────────────────────────────────────────────────
        // "Not set" is not an error here, so it is worded as a statement of
        // fact rather than as the italic gap the required fields use.
        const QaFieldLabel('Location', hint: 'Optional'),
        QaReviewBox(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                _useCurrentLocation
                    ? Icons.my_location_rounded
                    : Icons.location_on_rounded,
                size: 18,
                color: _pickedBarangay == null
                    ? CitizenUi.textFaint
                    : CitizenUi.accent,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _pickedBarangay ?? 'No location — this applies anywhere',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        fontStyle: _pickedBarangay == null
                            ? FontStyle.italic
                            : FontStyle.normal,
                        color: _pickedBarangay == null
                            ? CitizenUi.textFaint
                            : CitizenUi.textPrimary,
                      ),
                    ),
                    if (_pickedBarangay != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        _useCurrentLocation
                            ? 'Via GPS · Aparri, Cagayan'
                            : 'Aparri, Cagayan',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: CitizenUi.textFaint,
                        ),
                      ),
                    ],
                    if (street.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        street,
                        style: const TextStyle(
                          fontSize: 12.5,
                          height: 1.4,
                          color: CitizenUi.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ── Description, in a box shaped like the field it was typed in ───
        const QaFieldLabel('Suggestion'),
        QaReviewBox(
          minHeight: 76,
          child: SelectableText(
            details.isEmpty ? 'Nothing written yet' : details,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.45,
              fontStyle: details.isEmpty ? FontStyle.italic : FontStyle.normal,
              color: details.isEmpty
                  ? CitizenUi.textFaint
                  : CitizenUi.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: 16),

        // ── Attachments, as the real thumbnails ───────────────────────────
        QaFieldLabel(
          'Attachments',
          hint: _splitAttachmentLabel() ?? 'Optional — nothing attached',
        ),
        if (_attachedFiles.isEmpty)
          const QaReviewEmpty('No photo or video attached')
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            // Sized by EXTENT, not by column count: a fixed four-across grid
            // stretches its thumbnails as the panel widens, and on a step whose
            // job is to be read at a glance that is a photo album rather than a
            // summary. Capping the tile keeps the row compact and, since the
            // form allows at most six files, fits every attachment on ONE row.
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 120,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 1,
            ),
            itemCount: _attachedFiles.length,
            // The same tile step 3 draws — real previews, video thumbnails and
            // the tap-to-enlarge viewers, not a second thumbnail widget.
            itemBuilder: (context, i) => _attachFileTile(i, width),
          ),
        const SizedBox(height: 16),

        // ── Submitted as ──────────────────────────────────────────────────
        const QaFieldLabel('Submitted as'),
        QaReviewBox(
          child: Row(
            children: [
              Icon(
                _submitAnonymously
                    ? Icons.visibility_off_rounded
                    : Icons.person_rounded,
                size: 18,
                color: CitizenUi.accent,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _submitAnonymously ? 'Anonymous' : widget.username,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: CitizenUi.textPrimary,
                  ),
                ),
              ),
              if (_submitAnonymously)
                const Text(
                  'Name hidden from the public feed',
                  style: TextStyle(fontSize: 11.5, color: CitizenUi.textFaint),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// The chosen category drawn as its own tile — the same illustration and
  /// label the step-1 grid uses, in the accent-selected treatment, but inert.
  Widget _splitReviewCategoryTile() {
    final key = _selectedCategory;
    if (key == null) return const QaReviewEmpty('No category selected');

    final def = _categories.firstWhere(
      (c) => c['key'] == key,
      orElse: () => const <String, dynamic>{},
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: CitizenUi.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(CitizenUi.controlRadius),
        border: Border.all(color: CitizenUi.accent, width: 2),
      ),
      child: Row(
        children: [
          if (def['icon'] != null)
            Image.asset(
              def['icon'] as String,
              width: 26,
              height: 26,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => Icon(
                def['fallbackIcon'] as IconData? ?? Icons.lightbulb_rounded,
                size: 26,
                color: CitizenUi.accent,
              ),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              // Same derivation the rail uses, so the tile and the rail can
              // never disagree about which category this is.
              _splitCategoryLabel() ?? '',
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: CitizenUi.accent,
              ),
            ),
          ),
          const Icon(
            Icons.check_circle_rounded,
            size: 18,
            color: CitizenUi.accent,
          ),
        ],
      ),
    );
  }

  // ── Summary values — derived, never stored ────────────────────────────────

  String? _splitCategoryLabel() {
    final key = _selectedCategory;
    if (key == null) return null;
    if (key == 'others') {
      final other = _othersCtrl.text.trim();
      return other.isEmpty ? 'Others' : 'Others — $other';
    }
    final match = _categories.firstWhere(
      (c) => c['key'] == key,
      orElse: () => const {'label': ''},
    );
    // The grid labels carry a hard wrap for the tile; flatten it for a line.
    return (match['label'] as String).replaceAll('\n', ' ').trim();
  }

  String? _splitLocationLabel() {
    if (_pickedBarangay == null) return null;
    final street = _streetDetailCtrl.text.trim();
    return street.isEmpty ? _pickedBarangay : '$_pickedBarangay — $street';
  }

  String? _splitAttachmentLabel() {
    if (_attachedFiles.isEmpty) return null;
    final n = _attachedFiles.length;
    final pending = _processingPaths.length;
    final base = '$n file${n == 1 ? '' : 's'} attached';
    return pending == 0 ? base : '$base · $pending still processing';
  }

  // ── Right rail ────────────────────────────────────────────────────────────

  /// The four summary rows and the step's callout.
  ///
  /// One block, two homes: the rail renders it side by side, and the stacked
  /// panel renders THE SAME widget inside its Summary pane. Every value is read
  /// live off the form's own fields on each build, so the two placements cannot
  /// drift — there is no second copy of anything here.
  Widget _splitSummaryBlock() {
    final isLast = _splitStep == _kSplitSteps.length - 1;
    final waitingOnMedia = _processingPaths.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Four ruled rows, one per field the form collects, in the order the
        // steps collect them. The two optional rows carry an `optional` flag so
        // an empty one reads as "nothing needed here" rather than as an unfilled
        // requirement — the same distinction the step gates make.
        QaSummaryRow(
          icon: Icons.grid_view_rounded,
          label: 'CATEGORY',
          value: _splitCategoryLabel(),
        ),
        QaSummaryRow(
          icon: Icons.place_rounded,
          label: 'LOCATION',
          value: _splitLocationLabel(),
          placeholder: 'Optional — not set',
        ),
        QaSummaryRow(
          icon: Icons.format_list_bulleted_rounded,
          label: 'SUGGESTION',
          value: _detailsCtrl.text,
          maxLines: 2,
        ),
        QaSummaryRow(
          icon: Icons.attach_file_rounded,
          label: 'ATTACHMENTS',
          value: _splitAttachmentLabel(),
          placeholder: 'Optional — none',
        ),

        const SizedBox(height: 26),
        // Three states, most urgent first. On Review the info line gives way to
        // the truthfulness note — the one thing to read immediately before
        // pressing Submit.
        if (waitingOnMedia)
          const QaCallout(
            icon: Icons.hourglass_top_rounded,
            accent: AppColors.orange,
            text:
                'A photo is still being prepared. Submit unlocks once it '
                'finishes.',
          )
        else if (isLast)
          const QaCallout(
            icon: Icons.gpp_maybe_rounded,
            accent: CitizenUi.warn,
            text:
                'Suggestions are reviewed by the Municipality of Aparri. Check '
                'the details before sending.',
          )
        else
          const QaCallout(
            icon: Icons.lightbulb_outline_rounded,
            accent: CitizenUi.accent,
            text:
                'Location and attachments are optional — a suggestion can be '
                'sent with neither. Track it under My Submissions.',
          ),
      ],
    );
  }

  /// Continue/Submit, Back and Cancel.
  ///
  /// Extracted for the same reason as [_splitSummaryBlock]: side by side these
  /// sit at the foot of the rail, stacked they ARE the pinned action zone, and
  /// neither placement may fork what the buttons do. [compact] is the pinned
  /// zone's sizing — the buttons, their order, their handlers and their disabled
  /// rules are the same either way.
  Widget _splitActionStack({bool compact = false}) {
    final isLast = _splitStep == _kSplitSteps.length - 1;
    final busy = _isSubmitting;
    final waitingOnMedia = _processingPaths.isNotEmpty;

    void handleCancel() {
      final close = widget.onClose;
      if (close == null) return;
      close();
    }

    return QaActionStack(
      compact: compact,
      children: [
        if (isLast)
          QaActionButton(
            label: waitingOnMedia ? 'Finishing photo…' : 'Send Suggestion',
            icon: Icons.send_rounded,
            color: AppColors.green,
            busy: busy,
            compact: compact,
            // The existing handler, unmodified — it runs `_validate()` first,
            // so an incomplete form is refused here exactly as on mobile.
            onTap: waitingOnMedia ? null : _submitSuggestion,
          )
        else
          QaActionButton(
            label: 'Continue',
            icon: Icons.arrow_forward_rounded,
            compact: compact,
            onTap: _continueSplitStep,
          ),
        if (_splitStep > 0)
          QaActionButton(
            label: 'Back',
            icon: Icons.arrow_back_rounded,
            kind: QaActionKind.secondary,
            compact: compact,
            onTap: busy ? null : () => _goToSplitStep(_splitStep - 1),
          ),
        QaActionButton(
          label: 'Cancel',
          kind: QaActionKind.danger,
          compact: compact,
          onTap: busy ? null : handleCancel,
        ),
      ],
    );
  }

  /// The right-hand column.
  ///
  /// ── Side by side ─────────────────────────────────────────────────────────
  /// The full rail: header, summary, callout, buttons, inside a
  /// [SingleChildScrollView]. That scroll view is not decoration — the rail is
  /// drawn to the panel's FIXED height, so at a narrow rail (where values wrap
  /// onto second lines) it would otherwise run a few pixels past the card.
  ///
  /// ── Stacked ──────────────────────────────────────────────────────────────
  /// Reduced to the ACTION ZONE and returned BARE — a card holding the buttons
  /// and nothing else, no scroll view of its own, because a scroll view here
  /// would share an edge with the working area's and arbitrate drags with it.
  /// The header and summary are not dropped: the working card takes them over.
  ///
  /// The Summary pane has no buttons, because the buttons act on the STEP and
  /// the Summary is not a step. The zone goes away with the pane and comes back
  /// exactly as it was.
  Widget _splitRightRail(bool stacked) {
    if (stacked) {
      if (_splitTab != 0) return const SizedBox.shrink();
      // Tighter chrome than the rail's 20 a side: this card is a bar, and every
      // pixel of padding on it is a pixel the step above loses.
      return QaPanelCard(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: _splitActionStack(compact: true),
      );
    }

    return QaPanelCard(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      // ── Head and actions fixed, only the SUMMARY scrolls ────────────────
      // The rail is drawn to the panel's fixed height, so when its contents
      // exceed that something has to give. Scrolling the whole column gave way
      // at the bottom — the buttons — which is the one part that must never be
      // out of reach: a citizen who cannot see Cancel cannot leave, and a
      // Continue below the fold reads as a form with no way forward.
      //
      // `MainAxisSize.min` + `Flexible` is what keeps this free where there is
      // room. Below the frame the column shrink-wraps exactly as it always did
      // and the summary keeps its natural height, so nothing moves; only once
      // the content genuinely overruns does the summary give up the difference
      // and scroll inside itself. The panel's ScrollConfiguration keeps the bar
      // hidden either way.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          QaRailHeader(title: 'Summary', onClose: widget.onClose ?? () {}),
          const SizedBox(height: 20),
          Flexible(child: SingleChildScrollView(child: _splitSummaryBlock())),
          const SizedBox(height: 34),
          _splitActionStack(),
        ],
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────────────────────────
  Widget _buildHeader(double width) {
    return Container(
      color: Colors.white,
      padding: EdgeInsets.symmetric(
        horizontal: width * 0.04,
        vertical: width * 0.03,
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () async {
              final shouldPop = await _showDiscardConfirmation();
              if (shouldPop && mounted) Navigator.pop(context);
            },
            child: Container(
              width: width * 0.09,
              height: width * 0.09,
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(width * 0.025),
              ),
              child: Icon(
                Icons.arrow_back_ios_new_rounded,
                size: width * 0.045,
                color: AppColors.primaryBlue,
              ),
            ),
          ),
          SizedBox(width: width * 0.03),
          Image.asset(
            'assets/images/newslogo.webp',
            height: width * 0.085,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => Row(
              children: [
                Icon(
                  Icons.account_balance_rounded,
                  size: width * 0.07,
                  color: AppColors.primaryBlue,
                ),
                SizedBox(width: width * 0.02),
                Text(
                  'GovPulse',
                  style: TextStyle(
                    fontSize: width * 0.048,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryBlue,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Hero Banner ─────────────────────────────────────────────────────────────
  Widget _buildHeroBanner(double width) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: width * 0.04),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(
          horizontal: width * 0.045,
          vertical: width * 0.045,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(width * 0.04),
          border: Border.all(color: CitizenUi.sharedBorder),
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
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Suggestion',
                    style: TextStyle(
                      fontSize: width * 0.058,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF1F2937),
                    ),
                  ),
                  SizedBox(height: width * 0.015),
                  Text(
                    'Share ideas that can help improve\nyour community and local\ngovernment services.',
                    style: TextStyle(
                      fontSize: width * 0.031,
                      color: const Color(0xFF6B7280),
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            Image.asset(
              'assets/images/suggestion/suggestion.webp',
              width: width * 0.22,
              height: width * 0.22,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => Icon(
                Icons.lightbulb_outline_rounded,
                size: width * 0.20,
                color: AppColors.orange,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Section card ────────────────────────────────────────────────────────────
  Widget _sectionCard({
    required double width,
    required String title,
    required Widget child,
    Widget? trailingTitle,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: width * 0.04),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(width * 0.04),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(width * 0.04),
          border: Border.all(color: CitizenUi.sharedBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: width * 0.040,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1F2937),
                    ),
                  ),
                ),
                ?trailingTitle,
              ],
            ),
            SizedBox(height: width * 0.035),
            child,
          ],
        ),
      ),
    );
  }

  // ── 1. Category ─────────────────────────────────────────────────────────────
  Widget _buildCategorySection(double width) {
    return Column(
      children: [
        _buildHeroBanner(width),
        SizedBox(height: width * 0.04),
        _sectionCard(
          width: width,
          title: '1. Select Suggestion Category',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: width * 0.025,
                mainAxisSpacing: width * 0.025,
                childAspectRatio: 1.05,
                children: _categories.map((cat) {
                  final isSelected = _selectedCategory == cat['key'];
                  return GestureDetector(
                    onTap: () => setState(
                      () => _selectedCategory = cat['key'] as String,
                    ),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.primaryBlue.withValues(alpha: 0.07)
                            : const Color(0xFFF9FAFB),
                        borderRadius: BorderRadius.circular(width * 0.03),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.primaryBlue
                              : const Color(0xFFE5E7EB),
                          width: isSelected ? 1.8 : 1.0,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Image.asset(
                            cat['icon'] as String,
                            width: width * 0.085,
                            height: width * 0.085,
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) => Icon(
                              cat['fallbackIcon'] as IconData,
                              size: width * 0.085,
                              color: isSelected
                                  ? AppColors.primaryBlue
                                  : const Color(0xFF6B7280),
                            ),
                          ),
                          SizedBox(height: width * 0.012),
                          Text(
                            cat['label'] as String,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: width * 0.026,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: isSelected
                                  ? AppColors.primaryBlue
                                  : const Color(0xFF374151),
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              if (_selectedCategory == 'others') ...[
                SizedBox(height: width * 0.03),
                Text(
                  'If others please specify,',
                  style: TextStyle(
                    fontSize: width * 0.032,
                    color: const Color(0xFF6B7280),
                  ),
                ),
                SizedBox(height: width * 0.015),
                TextField(
                  controller: _othersCtrl,
                  maxLength: 50,
                  style: TextStyle(fontSize: width * 0.034),
                  decoration: InputDecoration(
                    hintText:
                        'Please describe the category in shortest term if possible...',
                    hintStyle: TextStyle(
                      fontSize: width * 0.029,
                      color: const Color(0xFFD1D5DB),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(width * 0.025),
                      borderSide: const BorderSide(
                        color: CitizenUi.sharedBorder,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(width * 0.025),
                      borderSide: const BorderSide(
                        color: CitizenUi.sharedBorder,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(width * 0.025),
                      borderSide: BorderSide(color: AppColors.primaryBlue),
                    ),
                    contentPadding: EdgeInsets.all(width * 0.035),
                    counterStyle: TextStyle(
                      fontSize: width * 0.028,
                      color: const Color(0xFF9CA3AF),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ── 2. Location (OPTIONAL) ──────────────────────────────────────────────────
  Widget _buildLocationSection(double width) {
    final hasLocation = _pickedLatLng != null && _pickedBarangay != null;
    return _sectionCard(
      width: width,
      title: '2. Suggestion Location (Optional)',
      trailingTitle: hasLocation
          ? GestureDetector(
              onTap: _clearLocation,
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  'Clear',
                  style: TextStyle(
                    fontSize: width * 0.032,
                    fontWeight: FontWeight.w600,
                    color: AppColors.red,
                  ),
                ),
              ),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildLocationBody(width),
          if (hasLocation) ...[
            SizedBox(height: width * 0.04),
            Row(
              children: [
                Text(
                  'Street Name & Detailed Location',
                  style: TextStyle(
                    fontSize: width * 0.032,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF374151),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Optional',
                    style: TextStyle(
                      fontSize: width * 0.026,
                      color: const Color(0xFF9CA3AF),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: width * 0.02),
            TextField(
              controller: _streetDetailCtrl,
              style: TextStyle(fontSize: width * 0.034),
              maxLines: 2,
              decoration: InputDecoration(
                hintText: 'e.g. Near the church, beside the market…',
                hintStyle: TextStyle(
                  fontSize: width * 0.031,
                  color: const Color(0xFFD1D5DB),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(width * 0.025),
                  borderSide: const BorderSide(color: CitizenUi.sharedBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(width * 0.025),
                  borderSide: const BorderSide(color: CitizenUi.sharedBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(width * 0.025),
                  borderSide: BorderSide(color: AppColors.primaryBlue),
                ),
                contentPadding: EdgeInsets.all(width * 0.035),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLocationBody(double width) {
    // ── Empty / not yet picked ──
    if (_pickedLatLng == null || _pickedBarangay == null) {
      return _locationTile(
        width: width,
        bgColor: const Color(0xFFF9FAFB),
        borderColor: CitizenUi.sharedBorder,
        leading: Icon(
          Icons.location_on_outlined,
          size: width * 0.07,
          color: const Color(0xFF9CA3AF),
        ),
        text: 'Location',
        subText: 'Tap change to add a location',
        textColor: const Color(0xFF9CA3AF),
        onTap: _openLocationPicker,
        actionLabel: 'Change',
      );
    }

    // ── Picked via GPS ──
    if (_useCurrentLocation) {
      return _locationTile(
        width: width,
        bgColor: const Color(0xFFF0F9FF),
        borderColor: const Color(0xFFBAE6FD),
        leading: Icon(
          Icons.my_location_rounded,
          size: width * 0.07,
          color: AppColors.primaryBlue,
        ),
        text: _pickedBarangay!,
        subText: 'Via GPS · Aparri, Cagayan',
        textColor: const Color(0xFF1F2937),
        onTap: _openLocationPicker,
        actionLabel: 'Change',
      );
    }

    // ── Picked manually ──
    return _locationTile(
      width: width,
      bgColor: const Color(0xFFF9FAFB),
      borderColor: CitizenUi.sharedBorder,
      leading: Icon(
        Icons.location_on_rounded,
        size: width * 0.07,
        color: AppColors.primaryBlue,
      ),
      text: _pickedBarangay!,
      subText: 'Aparri, Cagayan',
      textColor: const Color(0xFF1F2937),
      onTap: _openLocationPicker,
      actionLabel: 'Change',
    );
  }

  Widget _locationTile({
    required double width,
    required Color bgColor,
    required Color borderColor,
    required Widget leading,
    required String text,
    String? subText,
    required Color textColor,
    VoidCallback? onTap,
    String? actionLabel,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: width * 0.035,
        vertical: width * 0.033,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(width * 0.03),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          leading,
          SizedBox(width: width * 0.03),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: TextStyle(
                    fontSize: width * 0.035,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                    height: 1.4,
                  ),
                ),
                if (subText != null) ...[
                  SizedBox(height: width * 0.005),
                  Text(
                    subText,
                    style: TextStyle(
                      fontSize: width * 0.028,
                      color: const Color(0xFF9CA3AF),
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (actionLabel != null && onTap != null) ...[
            SizedBox(width: width * 0.02),
            GestureDetector(
              onTap: onTap,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    actionLabel,
                    style: TextStyle(
                      fontSize: width * 0.034,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryBlue,
                    ),
                  ),
                  SizedBox(width: width * 0.008),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: width * 0.030,
                    color: AppColors.primaryBlue,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── 3. Details ──────────────────────────────────────────────────────────────
  /// [bare] true drops the numbered section card and sizes the field for the
  /// web panel instead of the 480px mobile scale — same controller, same
  /// `maxLength: 2500` (which is what draws the 0/2500 counter), same
  /// `onChanged`. Only the citizen web split panel passes it.
  Widget _buildDetailsSection(double width, {bool bare = false}) {
    if (bare) return _splitDetailsField();
    return _sectionCard(
      width: width,
      title: '3. Suggestion Details',
      child: TextField(
        controller: _detailsCtrl,
        maxLength: 2500,
        maxLines: 5,
        style: TextStyle(fontSize: width * 0.034),
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText: 'Please describe the issue in detail...',
          hintStyle: TextStyle(
            fontSize: width * 0.032,
            color: const Color(0xFFD1D5DB),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(width * 0.025),
            borderSide: const BorderSide(color: CitizenUi.sharedBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(width * 0.025),
            borderSide: const BorderSide(color: CitizenUi.sharedBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(width * 0.025),
            borderSide: BorderSide(color: AppColors.primaryBlue),
          ),
          contentPadding: EdgeInsets.all(width * 0.035),
          counterStyle: TextStyle(
            fontSize: width * 0.028,
            color: const Color(0xFF9CA3AF),
          ),
        ),
      ),
    );
  }

  // ── Media helpers (identical to Report) ─────────────────────────────────────
  bool _isVideo(XFile file) {
    final ext = file.name.toLowerCase();
    return ext.endsWith('.mp4') || ext.endsWith('.mov') || ext.endsWith('.avi');
  }

  Future<void> _pickMedia() async {
    final remaining = _maxFiles - _attachedFiles.length;
    if (remaining <= 0) return;

    FocusManager.instance.primaryFocus?.unfocus();

    // ── The panel goes straight to the browser's file picker ────────────────
    // On the web there is no camera path and no separate photo/video library
    // to choose between — both branches of the chooser sheet end in the same
    // OS file dialog. Asking "photos or video?" first is a pop-up on top of a
    // pop-up that only makes the citizen pick the accept filter by hand, and
    // gets it wrong if they meant the other one. `pickMultipleMedia` opens
    // that dialog directly with `image/*,video/*`, so one click reaches the
    // files and either kind can be selected.
    //
    // Mobile is untouched: it keeps the sheet, because there the choice is
    // real — camera capture is a genuinely different source, and it is the one
    // that produces a GPS-stamped photo.
    if (widget.splitPanel) {
      final picked = await _picker.pickMultipleMedia(limit: remaining);
      await _acceptPickedMedia(picked);
      return;
    }

    await Future.delayed(const Duration(milliseconds: 50));
    if (!mounted) return;

    final choice = await showMediaPickerSheet(context);

    FocusManager.instance.primaryFocus?.unfocus();
    if (choice == null) return;

    // Live camera capture → add the tile instantly and bake the GPS stamp in
    // the background (the tile shows a bottom-to-top reveal meanwhile). No
    // full-screen spinner.
    if (choice == 'camera') {
      final p = await _picker.pickImage(source: ImageSource.camera);
      if (p != null) _addCameraCapture(p);
      return;
    }

    List<XFile> picked = [];
    if (choice == 'gallery') {
      picked = await _picker.pickMultiImage(limit: remaining);
    } else if (choice == 'video') {
      final v = await _picker.pickVideo(source: ImageSource.gallery);
      if (v != null) picked = [v];
    }

    await _acceptPickedMedia(picked);
  }

  /// Size-checks [picked] and adds what survives.
  ///
  /// Extracted so the sheet's three branches and the panel's one-click picker
  /// run byte-identical code: the same 10MB image / 50MB video caps, the same
  /// "some files were too large" message, and the same `_maxFiles` ceiling.
  /// They differ only in how the files get here.
  Future<void> _acceptPickedMedia(List<XFile> picked) async {
    if (picked.isEmpty) return;

    final List<XFile> validFiles = [];
    bool hasOversized = false;

    for (final file in picked) {
      final bytes = await file.length();
      final isVid = _isVideo(file);
      final maxBytes = isVid ? 50 * 1024 * 1024 : 10 * 1024 * 1024;
      if (bytes > maxBytes) {
        hasOversized = true;
      } else {
        validFiles.add(file);
      }
    }

    if (hasOversized && mounted) {
      showAppSnackBar(
        context,
        "Some files were too large. Images must be under 10MB, videos under 50MB.",
        type: AppSnackType.error,
      );
    }

    if (validFiles.isEmpty) return;
    FocusManager.instance.primaryFocus?.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusManager.instance.primaryFocus?.unfocus();
    });
    final canAdd = _maxFiles - _attachedFiles.length;
    for (final f in validFiles.take(canAdd)) {
      _isVideo(f) ? _addGalleryVideo(f) : _addGalleryImage(f);
    }
  }

  /// Adds a gallery image instantly, showing the reveal while it decodes.
  void _addGalleryImage(XFile file) {
    if (!mounted) return;
    setState(() {
      _attachedFiles.add(file);
      _processingPaths.add(file.path);
    });
    Future.wait([
      precacheImage(pickedImageProvider(file), context),
      Future<void>.delayed(_minReveal),
    ]).whenComplete(() {
      if (!mounted) return;
      // Keep the reveal mounted; let it sweep to the top, then it clears itself.
      setState(() => _completedPaths.add(file.path));
    });
  }

  /// Adds a gallery video instantly, showing the reveal while its thumbnail is
  /// generated (then cached so the tile renders it without a spinner).
  void _addGalleryVideo(XFile file) {
    if (!mounted) return;
    setState(() {
      _attachedFiles.add(file);
      _processingPaths.add(file.path);
    });
    Future.wait([
      VideoThumbnail.thumbnailData(
            video: file.path,
            imageFormat: ImageFormat.JPEG,
            maxWidth: 200,
            quality: 75,
          )
          .then((data) {
            if (data != null) _thumbCache[file.path] = data;
          })
          .catchError((_) {}),
      Future<void>.delayed(_minReveal),
    ]).whenComplete(() {
      if (!mounted) return;
      setState(() => _completedPaths.add(file.path));
    });
  }

  /// Video thumbnail for a grid tile — cached bytes if ready, else generated
  /// (the reveal covers the plain placeholder while processing).
  Widget _videoThumb(XFile file, double width) {
    final cached = _thumbCache[file.path];
    Widget withPlay(Widget image) => Stack(
      fit: StackFit.expand,
      children: [
        image,
        Center(
          child: Container(
            padding: EdgeInsets.all(width * 0.015),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.play_arrow_rounded,
              color: Colors.white,
              size: width * 0.06,
            ),
          ),
        ),
      ],
    );

    if (cached != null) {
      return withPlay(Image.memory(cached, fit: BoxFit.cover));
    }
    return FutureBuilder<Uint8List?>(
      future: VideoThumbnail.thumbnailData(
        video: file.path,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 200,
        quality: 75,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done &&
            snapshot.data != null) {
          return withPlay(Image.memory(snapshot.data!, fit: BoxFit.cover));
        }
        return const ColoredBox(color: Color(0xFFE0F2FE));
      },
    );
  }

  /// Adds a freshly captured camera photo to the grid immediately (showing the
  /// original as a preview under a reveal animation), then bakes the GPS stamp
  /// in the background and swaps in the stamped file when ready.
  void _addCameraCapture(XFile original) {
    if (!mounted) return;
    setState(() {
      _attachedFiles.add(original);
      _processingPaths.add(original.path);
    });

    GpsStampService.stampPhoto(original).then((result) async {
      final finalFile = result.file;
      final tooLarge = await finalFile.length() > 10 * 1024 * 1024;
      if (!mounted) return;
      setState(() {
        final idx = _attachedFiles.indexWhere((f) => f.path == original.path);
        if (idx == -1) {
          _processingPaths.remove(original.path); // removed while processing
          return;
        }
        if (tooLarge) {
          _attachedFiles.removeAt(idx);
          _processingPaths.remove(original.path);
        } else {
          _attachedFiles[idx] = finalFile;
          if (result.stamped) _gpsVerifiedPaths.add(finalFile.path);
          // Hand the still-mounted reveal over to the stamped file's path and
          // let it play its closing sweep to the top.
          _processingPaths.remove(original.path);
          _processingPaths.add(finalFile.path);
          _completedPaths.add(finalFile.path);
        }
      });
      if (tooLarge) {
        showAppSnackBar(
          context,
          "That photo was too large (over 10MB) and was removed.",
          type: AppSnackType.error,
        );
      }
    });
  }

  void _previewImage(BuildContext context, XFile file, double width) {
    showAppDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                child: Image(
                  image: pickedImageProvider(file),
                  fit: BoxFit.contain,
                ),
              ),
            ),
            Positioned(
              top: 40,
              right: 16,
              child: GestureDetector(
                onTap: () => Navigator.pop(ctx),
                child: Container(
                  width: width * 0.10,
                  height: width * 0.10,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close_rounded, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _previewVideo(BuildContext context, XFile file, double width) {
    showAppDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => _VideoPreviewDialog(file: file, width: width),
    );
  }

  // ── 4. Attach (OPTIONAL for suggestions) ────────────────────────────────────
  /// [bare] true drops the numbered section card and swaps the tall mobile
  /// dropzone for a web-sized square grid. The attachment TILE below is
  /// deliberately left on the shared path — it carries the processing reveal,
  /// the delete buttons, the video thumbnails and the preview taps, and none of
  /// that is layout worth forking. `_maxFiles`, `_pickMedia` and every limit are
  /// untouched either way.
  Widget _buildAttachSection(double width, {bool bare = false}) {
    if (bare) return _splitAttachGrid(width);

    final slotCount = _attachedFiles.length < _maxFiles
        ? _attachedFiles.length + 1
        : _maxFiles;

    return _sectionCard(
      width: width,
      title: '4. Attach Image / Video (Optional)',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: _attachedFiles.length < _maxFiles ? _pickMedia : null,
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(vertical: width * 0.065),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F9FF),
                borderRadius: BorderRadius.circular(width * 0.03),
                border: Border.all(
                  color: AppColors.primaryBlue.withValues(alpha: 0.35),
                  width: 1.5,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.add_a_photo_rounded,
                    size: width * 0.095,
                    color: AppColors.primaryBlue,
                  ),
                  SizedBox(height: width * 0.02),
                  Text(
                    'Tap to upload photo or video',
                    style: TextStyle(
                      fontSize: width * 0.034,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF374151),
                    ),
                  ),
                  SizedBox(height: width * 0.008),
                  Text(
                    _attachedFiles.isEmpty
                        ? 'You can upload up to $_maxFiles files'
                        : '${_attachedFiles.length}/$_maxFiles uploaded',
                    style: TextStyle(
                      fontSize: width * 0.028,
                      color: const Color(0xFF9CA3AF),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_attachedFiles.isNotEmpty) ...[
            SizedBox(height: width * 0.03),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: width * 0.025,
                mainAxisSpacing: width * 0.025,
                childAspectRatio: 1.0,
              ),
              itemCount: slotCount,
              itemBuilder: (context, index) {
                final isPlus = index == _attachedFiles.length;
                if (isPlus) {
                  return GestureDetector(
                    onTap: _pickMedia,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0F9FF),
                        borderRadius: BorderRadius.circular(width * 0.025),
                        border: Border.all(
                          color: AppColors.primaryBlue.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Center(
                        child: Image.asset(
                          'assets/images/report/plus_sign.webp',
                          width: width * 0.07,
                          height: width * 0.07,
                          errorBuilder: (_, _, _) => Icon(
                            Icons.add_rounded,
                            size: width * 0.07,
                            color: AppColors.primaryBlue,
                          ),
                        ),
                      ),
                    ),
                  );
                }
                return _attachFileTile(index, width);
              },
            ),
          ],
          SizedBox(height: width * 0.022),
          Text(
            'Image: JPG, PNG (Max. 10MB)  •  Video: MP4 (Max. 50MB)',
            style: TextStyle(
              fontSize: width * 0.026,
              color: const Color(0xFF9CA3AF),
            ),
          ),
        ],
      ),
    );
  }

  /// One attached file's square tile — preview or video thumbnail, the
  /// processing reveal, and the delete button.
  ///
  /// Extracted verbatim from the mobile grid's itemBuilder so the web panel's
  /// square grid can lay the SAME tile out differently without a second copy of
  /// the preview, reveal or delete behaviour. Both grids call this; only the
  /// surrounding delegate differs.
  Widget _attachFileTile(int index, double width) {
    final file = _attachedFiles[index];
    final processing = _processingPaths.contains(file.path);
    return GestureDetector(
      onTap: processing
          ? null
          : () {
              _isVideo(file)
                  ? _previewVideo(context, file, width)
                  : _previewImage(context, file, width);
            },
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(width * 0.025),
            child: _isVideo(file)
                ? _videoThumb(file, width)
                : Image(image: pickedImageProvider(file), fit: BoxFit.cover),
          ),
          // Bottom-to-top reveal while the GPS stamp bakes; it fills
          // to the top the moment processing completes.
          if (processing)
            Positioned.fill(
              child: RevealLoading(
                borderRadius: BorderRadius.circular(width * 0.025),
                completed: _completedPaths.contains(file.path),
                onFinished: () {
                  if (!mounted) return;
                  setState(() {
                    _processingPaths.remove(file.path);
                    _completedPaths.remove(file.path);
                  });
                },
              ),
            ),
          if (!processing)
            Positioned(
              top: 5,
              right: 5,
              child: GestureDetector(
                onTap: () => setState(() => _attachedFiles.removeAt(index)),
                child: Container(
                  width: width * 0.055,
                  height: width * 0.055,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.close_rounded,
                    color: Colors.white,
                    size: width * 0.034,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Anonymous consent dialog (identical to Report) ─────────────────────────
  void _showAnonymousConsentDialog() {
    showAppDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final isEn = _consentInEnglish;
          final screenW = MediaQuery.of(context).size.width;
          final width = screenW.clamp(0.0, 480.0);
          // On web/desktop this is a block of terms to READ, not a banner: past
          // ~520px the lines get long enough that the eye loses its place on the
          // wrap. Cap the card there and give the surplus back as margin; on a
          // phone the cap never binds and the old 5% inset stands.
          final sideInset = ((screenW - 520) / 2).clamp(
            width * 0.05,
            screenW * 0.5,
          );

          final title = isEn
              ? 'Anonymous Suggestion Consent'
              : 'Pahintulot sa Anonymous na Suhestiyon';
          final introBold = isEn
              ? 'Anonymous Suggestion'
              : 'Anonymous na Suhestiyon';
          final introText = isEn
              ? ', you acknowledge and agree to the following:'
              : ', kinikilala mo at sumasang-ayon sa mga sumusunod:';
          final bullets = isEn
              ? [
                  'Your identity and personal profile information will remain protected and hidden from public view.',
                  'The content of your submitted suggestion, including attached files, timestamps, and related submission details, may still be securely recorded and stored.',
                  'Submitted suggestions may be used for verification, investigation, moderation, legal compliance, and maintaining system integrity and security.',
                  'Authorized administrators or personnel may access suggestion records only when necessary for review and processing.',
                  'Any abuse, false reporting, fraudulent activity, or misuse of the anonymous suggestion feature may result in appropriate action in accordance with platform policies and applicable laws.',
                ]
              : [
                  'Ang iyong pagkakakilanlan at personal na impormasyon ay mananatiling protektado at nakatago mula sa pampublikong tingin.',
                  'Ang nilalaman ng iyong isinumiteng suhestiyon, kasama ang mga nakalakip na file, timestamp, at iba pang detalye, ay maaaring ligtas na mairekord at maiimbak.',
                  'Ang mga isinumiteng suhestiyon ay maaaring gamitin para sa pagpapatunay, imbestigasyon, moderasyon, pagsunod sa batas, at pagpapanatili ng integridad ng sistema.',
                  'Ang mga awtorisadong administrador o tauhan ay maaaring ma-access ang mga rekord ng suhestiyon lamang kung kinakailangan para sa pagsusuri at pagproseso.',
                  'Ang anumang pag-abuso, maling pag-uulat, mapanlinlang na aktibidad, o maling paggamit ng tampok na ito ay maaaring magresulta sa naaangkop na aksyon ayon sa mga patakaran ng platform at naaangkop na batas.',
                ];
          final footer = isEn
              ? 'By choosing "I Agree", you confirm that you understand and agree to these terms.'
              : 'Sa pag-click ng "Sumasang-ayon Ako", kinukumpirma mo na nauunawaan at sumasang-ayon ka sa mga tuntuning ito.';
          final cancelLabel = isEn ? 'Cancel' : 'Kanselahin';
          final agreeLabel = isEn ? 'I Agree' : 'Sumasang-ayon Ako';
          final byEnabling = isEn ? 'By enabling ' : 'Sa pag-enable ng ';

          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            insetPadding: EdgeInsets.symmetric(
              horizontal: sideInset,
              vertical: 24,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1F2937),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: CitizenUi.sharedBorder),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _langPill(
                              'Eng',
                              isEn,
                              () =>
                                  setModalState(() => _consentInEnglish = true),
                            ),
                            _langPill(
                              'Fil',
                              !isEn,
                              () => setModalState(
                                () => _consentInEnglish = false,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.42,
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          RichText(
                            text: TextSpan(
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF374151),
                                height: 1.55,
                              ),
                              children: [
                                TextSpan(text: byEnabling),
                                TextSpan(
                                  text: introBold,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primaryBlue,
                                  ),
                                ),
                                TextSpan(text: introText),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          ...bullets.map(
                            (b) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    '• ',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Color(0xFF374151),
                                      height: 1.55,
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      b,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: Color(0xFF374151),
                                        height: 1.55,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            footer,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: Color(0xFF374151),
                              height: 1.55,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          setState(() => _submitAnonymously = false);
                          FocusManager.instance.primaryFocus?.unfocus();
                        },
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          cancelLabel,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primaryBlue,
                          ),
                        ),
                      ),
                      const Spacer(),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          setState(() => _submitAnonymously = true);
                          FocusManager.instance.primaryFocus?.unfocus();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryBlue,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                          elevation: 2,
                        ),
                        child: Text(
                          agreeLabel,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _langPill(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: active ? AppColors.primaryBlue : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: active ? Colors.white : const Color(0xFF6B7280),
          ),
        ),
      ),
    );
  }

  // ── 5. Anonymous toggle ─────────────────────────────────────────────────────
  Widget _buildAnonymousSection(double width) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: width * 0.04),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: width * 0.04,
          vertical: width * 0.032,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(width * 0.04),
          border: Border.all(color: CitizenUi.sharedBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Image.asset(
              'assets/images/report/padlock.webp',
              width: width * 0.07,
              height: width * 0.07,
              errorBuilder: (_, _, _) => Icon(
                Icons.lock_outline_rounded,
                size: width * 0.07,
                color: const Color(0xFF374151),
              ),
            ),
            SizedBox(width: width * 0.03),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Submit Anonymously',
                    style: TextStyle(
                      fontSize: width * 0.036,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF1F2937),
                    ),
                  ),
                  SizedBox(height: width * 0.005),
                  Text(
                    'Your identity will be hidden from the\npublic view.',
                    style: TextStyle(
                      fontSize: width * 0.028,
                      color: const Color(0xFF6B7280),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: _submitAnonymously,
              onChanged: (v) {
                if (v) {
                  _showAnonymousConsentDialog();
                } else {
                  setState(() => _submitAnonymously = false);
                }
              },
              activeThumbColor: Colors.white,
              activeTrackColor: AppColors.green,
              inactiveThumbColor: Colors.white,
              inactiveTrackColor: const Color(0xFFD1D5DB),
            ),
          ],
        ),
      ),
    );
  }

  // ── Disclaimer banner ───────────────────────────────────────────────────────
  Widget _buildDisclaimer(double width) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: width * 0.04),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: width * 0.035,
          vertical: width * 0.030,
        ),
        decoration: BoxDecoration(
          color: AppColors.orange.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(width * 0.03),
          border: Border.all(color: AppColors.orange.withValues(alpha: 0.30)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline_rounded,
              size: width * 0.05,
              color: AppColors.orange,
            ),
            SizedBox(width: width * 0.025),
            Expanded(
              child: Text(
                'Please ensure that all information submitted is accurate and truthful. False or misleading submissions may result in penalties or possible consequences.',
                style: TextStyle(
                  fontSize: width * 0.029,
                  color: const Color(0xFF7C5500),
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Validation (location & media OPTIONAL) ──────────────────────────────────
  String? _validate() {
    if (_selectedCategory == null) {
      return 'Please select a suggestion category.';
    }
    if (_selectedCategory == 'others' && _othersCtrl.text.trim().isEmpty) {
      return 'Please specify the category under "Others".';
    }
    if (_detailsCtrl.text.trim().isEmpty) {
      return 'Please describe your suggestion in detail.';
    }
    if (_processingPaths.isNotEmpty) {
      return 'Please wait for your photo to finish processing.';
    }
    return null;
  }

  Future<void> _submitSuggestion() async {
    final error = _validate();
    if (error != null) {
      _showValidationDialog(error);
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final supabase = Supabase.instance.client;

      final session = supabase.auth.currentSession;

      if (session == null) {
        setState(() => _isSubmitting = false);
        showFriendlyErrorDialog(
          context,
          'Session expired. Please log in again.',
        );
        return;
      }

      await supabase.auth.refreshSession();

      if (!mounted) return;

      final freshSession = supabase.auth.currentSession;

      if (freshSession == null) {
        setState(() => _isSubmitting = false);

        showFriendlyErrorDialog(
          context,
          'Session expired. Please log in again.',
        );

        return;
      }

      final userId = session.user.id;

      // Generated before any upload so media is keyed by the SUBMISSION rather
      // than the citizen — the old `suggestions/$userId/...` path exposed the
      // author's uuid even on anonymous suggestions. See
      // lib/core/utils/submission_id.dart.
      final suggestionId = uuidV4();

      // ── Upload media ──────────────────────────────────────────────────────
      final List<Map<String, String>> mediaItems = [];
      for (int i = 0; i < _attachedFiles.length; i++) {
        final file = _attachedFiles[i];
        final bytes = await file.readAsBytes();
        final ext = file.name.split('.').last.toLowerCase();
        final fileName =
            '${DateTime.now().millisecondsSinceEpoch}_${i}_${file.name}';
        final storagePath = 'suggestions/$suggestionId/$fileName';
        final contentType = _isVideo(file) ? 'video/$ext' : 'image/$ext';

        await supabase.storage
            .from('suggestion-media')
            .uploadBinary(
              storagePath,
              bytes,
              fileOptions: FileOptions(contentType: contentType),
            );

        mediaItems.add({
          'path': storagePath,
          'mime': contentType,
          'source': _gpsVerifiedPaths.contains(file.path) ? 'camera' : 'upload',
        });
      }

      // ── Insert suggestion ─────────────────────────────────────────────────
      final insertPayload = {
        // Explicit id — media was already uploaded under suggestions/$suggestionId/.
        // `.insert` (never `.upsert`) so a colliding id fails on the primary key.
        'id': suggestionId,
        'user_id': userId, // ← always send real user_id
        'category': _selectedCategory,
        'category_other': _selectedCategory == 'others'
            ? _othersCtrl.text.trim()
            : null,
        'barangay': _pickedBarangay,
        'address': _streetDetailCtrl.text.trim().isEmpty
            ? null
            : _streetDetailCtrl.text.trim(),
        'latitude': _pickedLatLng?.latitude,
        'longitude': _pickedLatLng?.longitude,
        'details': _detailsCtrl.text.trim(),
        'is_anonymous': _submitAnonymously,
        'status': 'pending',
      };

      final response = await supabase
          .from('suggestions')
          .insert(insertPayload)
          .select('id')
          .single();

      // Already known — generated before the upload. Kept so a failed insert
      // throws here rather than surfacing as media rows pointing at nothing.
      assert(response['id'] == suggestionId);

      // ── Insert media rows ─────────────────────────────────────────────────
      for (int i = 0; i < mediaItems.length; i++) {
        final row = <String, dynamic>{
          'suggestion_id': suggestionId,
          'storage_path': mediaItems[i]['path'],
          'mime_type': mediaItems[i]['mime'],
          'display_order': i + 1,
          'source': mediaItems[i]['source'],
        };
        // Capture the inserted row id so the AI-image check can target it.
        Map<String, dynamic> inserted;
        try {
          inserted = await supabase
              .from('suggestion_media')
              .insert(row)
              .select('id')
              .single();
        } on PostgrestException catch (e) {
          // `source` column may not be migrated yet — retry without it so
          // submitting a suggestion never breaks (media_source_column.sql).
          if ((e.message).toLowerCase().contains('source')) {
            row.remove('source');
            inserted = await supabase
                .from('suggestion_media')
                .insert(row)
                .select('id')
                .single();
          } else {
            rethrow;
          }
        }

        // Fire-and-forget AI-generated-image check (images only). NOT awaited —
        // it must never delay the success toast/navigation, and a failure (or an
        // un-migrated DB / down detector) leaves the submission untouched.
        final mime = (mediaItems[i]['mime'] ?? '').toLowerCase();
        if (mime.startsWith('image/')) {
          supabase.functions
              .invoke(
                'check-ai-image',
                body: {
                  'bucket': 'suggestion-media',
                  'path': mediaItems[i]['path'],
                  'table': 'suggestion_media',
                  'id': inserted['id'],
                },
              )
              .ignore(); // swallow errors — never disturb the submission flow
        }
      }

      if (mounted) {
        showAppSnackBar(
          context,
          "Suggestion submitted successfully.",
          type: AppSnackType.success,
        );
        Navigator.pop(context);
      }
    } on StorageException catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false); // ← FIX: reset spinner
        showAppSnackBar(
          context,
          'File upload failed: ${e.message}',
          type: AppSnackType.error,
        );
      }
    } on PostgrestException catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false); // ← FIX: reset spinner
        if ((e.hint ?? '') == 'rate_limit_exceeded') {
          showAppSnackBar(
            context,
            "You've reached your daily limit of 3 suggestions. Please come back tomorrow.",
            type: AppSnackType.error,
          );
        } else {
          showAppSnackBar(
            context,
            "Could not submit your suggestion. Please try again.",
            type: AppSnackType.error,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        showAppSnackBar(
          context,
          "Something went wrong. Please try again.",
          type: AppSnackType.error,
        );
      }
    } finally {
      // Safety net — always reset spinner
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // ── Dialogs ─────────────────────────────────────────────────────────────────

  void _showValidationDialog(String message) {
    showAppDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        // Without a cap, the full-width OK button stretches the card across the
        // whole browser window. A phone screen is narrower than this, so the
        // constraint only ever bites on web/tablet.
        constraints: const BoxConstraints(maxWidth: 400, minWidth: 280),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.info_outline_rounded,
                  color: Colors.orange,
                  size: 32,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Incomplete Form',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1F2937),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF6B7280),
                  height: 1.55,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text(
                    'OK',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
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

  // ── Submit button ───────────────────────────────────────────────────────────
  Widget _buildSubmitButton(double width) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: width * 0.04),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: (_isSubmitting || _processingPaths.isNotEmpty)
              ? null
              : _submitSuggestion,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.green,
            disabledBackgroundColor: const Color(0xFFD1D5DB),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(width * 0.035),
            ),
            padding: EdgeInsets.symmetric(vertical: width * 0.042),
            elevation: 2,
            shadowColor: AppColors.green.withValues(alpha: 0.4),
          ),
          child: _isSubmitting
              ? SizedBox(
                  height: width * 0.05,
                  width: width * 0.05,
                  child: const CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                )
              : Text(
                  _processingPaths.isNotEmpty
                      ? 'Finishing photo…'
                      : 'Submit Suggestion',
                  style: TextStyle(
                    fontSize: width * 0.042,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 0.3,
                  ),
                ),
        ),
      ),
    );
  }
}
