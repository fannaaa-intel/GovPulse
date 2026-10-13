import 'package:flutter/material.dart';

import '../../../services/faq_catalog.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/citizen_ui.dart';
import '../../app_dialog.dart';
import '../Newsfeed/news_feed_helpers.dart';

/// The full FAQ list, grouped by topic. Returns the picked question, or null
/// if the citizen closed it.
///
/// Presentation follows the app's standard rule rather than being the same
/// everywhere: **narrow (< [kCommentsDialogBreakpoint]) gets the slide-up
/// bottom sheet, wide gets the centred blurred dialog.** This was a centred
/// dialog on every width until 2026-10-13, which on a phone put a floating
/// card in the middle of the screen while every other pop-up in the app — the
/// comment thread, the media picker, the comment options — slid up from the
/// bottom.
///
/// The breakpoint is the WIDTH, never `kIsWeb`: a narrow browser window is a
/// phone-shaped surface and should behave like one, and the installed app on a
/// tablet is wide. The same call therefore fixes the mobile app and the
/// narrow web window together, which is why the fix lives here and not in
/// either caller.
Future<Faq?> showAllFaqs(BuildContext context) {
  final wide =
      MediaQuery.of(context).size.width >= kCommentsDialogBreakpoint;

  if (wide) {
    return showAppDialog<Faq>(
      context: context,
      builder: (ctx) => const _AllFaqsDialog(),
    );
  }
  // Deliberately NOT blurred: the blur belongs to the centred dialog, and the
  // bottom sheet uses the scrim instead, exactly as showCommentsSheet does.
  return showModalBottomSheet<Faq>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (_) => const _AllFaqsSheet(),
  );
}

/// The phone presentation: slides up, rounded at the top only, with a drag
/// handle. Height is capped rather than fixed so a short FAQ list does not
/// leave a tall empty sheet, and a long one still stops short of the status
/// bar.
class _AllFaqsSheet extends StatelessWidget {
  const _AllFaqsSheet();

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.of(context).size.height * 0.85;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Drag handle — the affordance that says "this slides".
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 2),
                child: Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.hint.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
              const _FaqHeader(),
              const Divider(height: 1, color: CitizenUi.border),
              const Flexible(child: _FaqList()),
            ],
          ),
        ),
      ),
    );
  }
}

/// The shared header. Identical in both presentations so the sheet and the
/// dialog read as one component.
class _FaqHeader extends StatelessWidget {
  const _FaqHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Common questions',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: CitizenUi.textPrimary,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

class _AllFaqsDialog extends StatelessWidget {
  const _AllFaqsDialog();

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.of(context).size.height * 0.8;
    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 520, maxHeight: maxH),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _FaqHeader(),
            const Divider(height: 1, color: CitizenUi.border),
            const Flexible(child: _FaqList()),
          ],
        ),
      ),
    );
  }
}

/// The grouped list of questions. Shared by both presentations, so the sheet
/// and the dialog can never drift apart.
class _FaqList extends StatelessWidget {
  const _FaqList();

  @override
  Widget build(BuildContext context) {
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      children: [
        for (final topic in FaqTopic.values) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 6),
            child: Text(
              topic.label.toUpperCase(),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: AppColors.hint,
              ),
            ),
          ),
          for (final faq in kFaqs.where((f) => f.topic == topic))
            _FaqRow(
              faq: faq,
              onTap: () => Navigator.of(context).pop(faq),
            ),
        ],
      ],
    );
  }
}

class _FaqRow extends StatelessWidget {
  final Faq faq;
  final VoidCallback onTap;
  const _FaqRow({required this.faq, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
          child: Row(
            children: [
              const Icon(
                Icons.help_outline_rounded,
                size: 18,
                color: AppColors.primaryBlue,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  faq.question,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.35,
                    color: CitizenUi.textPrimary,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: AppColors.hint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
