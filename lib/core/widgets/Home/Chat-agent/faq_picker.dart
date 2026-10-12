import 'package:flutter/material.dart';

import '../../../services/faq_catalog.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/citizen_ui.dart';
import '../../app_dialog.dart';

/// The full FAQ list, grouped by topic. Returns the picked question, or null
/// if the citizen closed it.
///
/// A dialog rather than a bottom sheet so the chat window and the full-screen
/// chat (phone and web) open the same thing, with the app's standard blur.
Future<Faq?> showAllFaqs(BuildContext context) {
  return showAppDialog<Faq>(
    context: context,
    builder: (ctx) => const _AllFaqsDialog(),
  );
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
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
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
            ),
            const Divider(height: 1, color: CitizenUi.border),
            Flexible(
              child: ListView(
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
              ),
            ),
          ],
        ),
      ),
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
