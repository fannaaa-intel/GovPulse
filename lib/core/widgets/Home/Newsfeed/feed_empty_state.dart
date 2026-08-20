import 'package:flutter/material.dart';

import '../../../theme/citizen_ui.dart';

/// Which empty the feed is showing.
enum FeedEmptyKind {
  /// No community posts exist at all — what every citizen sees today, since
  /// `community_posts` is empty. Warm and civic, with a way to contribute.
  noPostsYet,

  /// Posts exist, but the active date filter excludes all of them. The user did
  /// this to themselves, so the fix is to undo it.
  filtered,
}

/// The citizen web feed's empty state.
///
/// WEB ONLY. The mobile app keeps `_buildEmptyState` in news_feed_screen.dart
/// untouched — this widget is wired into the web arm alone, so nothing here can
/// reach the Flutter mobile surface.
class FeedEmptyState extends StatelessWidget {
  final FeedEmptyKind kind;

  /// Runs the REPORT quick action. Null when there is no shell to run it in —
  /// the guest feed mounts this same body at >=900px — in which case the primary
  /// CTA is not rendered at all rather than rendered dead.
  ///
  /// Deliberately a callback rather than an action of its own: the shell hands
  /// down its `_handleQuickAction`, so this CTA inherits the verification and
  /// restriction gates every other quick action goes through.
  final VoidCallback? onReportIssue;

  /// Clears the date filter back to its default.
  final VoidCallback? onShowAll;

  const FeedEmptyState({
    super.key,
    required this.kind,
    this.onReportIssue,
    this.onShowAll,
  });

  @override
  Widget build(BuildContext context) {
    final filtered = kind == FeedEmptyKind.filtered;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(32, 44, 32, 44),
      decoration: BoxDecoration(
        color: CitizenUi.surface,
        borderRadius: BorderRadius.circular(CitizenUi.cardRadius),
        border: Border.all(color: CitizenUi.border),
        boxShadow: CitizenUi.cardShadow,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _icon(filtered),
          const SizedBox(height: 20),
          Text(
            filtered ? 'No updates in this range' : 'No community updates yet',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: CitizenUi.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Text(
              filtered
                  ? 'Try widening the time range to see more.'
                  : 'Your LGU will post news, events, and announcements here. '
                        'In the meantime, you can help improve your community.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.55,
                color: CitizenUi.textMuted,
              ),
            ),
          ),
          ..._action(filtered),
        ],
      ),
    );
  }

  /// Civic, not diagnostic: a megaphone on the brand wash for the first-run
  /// case, and a muted clock for the filter case — which is a narrower,
  /// self-inflicted situation and should not shout.
  Widget _icon(bool filtered) {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: filtered ? CitizenUi.subtle : CitizenUi.accentWash,
        shape: BoxShape.circle,
      ),
      child: Icon(
        filtered ? Icons.schedule_rounded : Icons.campaign_rounded,
        size: 34,
        color: filtered ? CitizenUi.textFaint : CitizenUi.accent,
      ),
    );
  }

  List<Widget> _action(bool filtered) {
    if (filtered) {
      if (onShowAll == null) return const [];
      return [
        const SizedBox(height: 22),
        OutlinedButton(
          onPressed: onShowAll,
          style: OutlinedButton.styleFrom(
            foregroundColor: CitizenUi.accent,
            side: const BorderSide(color: CitizenUi.borderStrong),
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(CitizenUi.controlRadius),
            ),
            textStyle: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          child: const Text('Show all'),
        ),
      ];
    }

    // No dispatcher above us (the guest feed) — copy only, never a dead button.
    if (onReportIssue == null) return const [];
    return [
      const SizedBox(height: 24),
      FilledButton.icon(
        onPressed: onReportIssue,
        // Same glyph the rail and sidebar use for 'report', so the CTA reads as
        // the quick action it actually runs.
        icon: const Icon(Icons.report_gmailerrorred_rounded, size: 18),
        label: const Text('Report an Issue'),
        style: FilledButton.styleFrom(
          backgroundColor: CitizenUi.accent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(CitizenUi.controlRadius),
          ),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
    ];
  }
}
