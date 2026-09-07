// lib/core/widgets/Home/citizen_page_header.dart
//
// The phone header for a top-level citizen screen: the GovPulse mark, the
// page's name under it, and an optional line of supporting copy.
//
// ── Why this exists ───────────────────────────────────────────────────────
// My Reports, Community Updates, Emergency and Settings each grew their own
// copy of this block, and the copies drifted on almost every value that
// decides how it looks. Measured before this widget replaced them:
//
//                 My Reports   Community    Emergency   Settings
//   pad L/R         .04          .04          .05         .04
//   pad top         .04          .025         .038        .04
//   pad bottom      .04          .035         .038        .04
//   logo→title      .018         .045         .018        .018
//   title size      .058         .052         .058        .058
//   title weight    w700         w800         w900        w700
//   letter-spacing  -0.3         none         -0.8        -0.3
//   shadow          .05/8        .04/6        .05/8       .05/8
//
// The logo height (`w * .075`) was the ONLY value all four agreed on. Four
// screens a citizen moves between via the bottom bar were each announcing
// themselves in a different voice, and the difference read as the pages
// belonging to different apps rather than as one app.
//
// The values kept here are the majority reading — the one My Reports and
// Settings already shared, which is also what [AppScreenHeader] uses for the
// sub-screens under Settings. Emergency's heavier `w900`/`-0.8` title and
// Community Updates' lighter `w800`/`.052` were the two outliers, and both
// lose: a page title is not the place to express a page's mood.
//
// The web branches of these screens are NOT affected. They use
// AccountPageTitle, which is already shared and already consistent; this is
// the phone's equivalent of that widget, and the two are deliberately
// separate because a phone header carries the app mark and a web one does
// not (the web shell shows the mark in its own top nav, about 60px above).
//
// Change the look HERE, not at a call site.

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/citizen_ui.dart';
import '../../theme/mobile_metrics.dart';

class CitizenPageHeader extends StatelessWidget {
  /// The page's name — "Emergency", "Settings".
  final String title;

  /// One line of supporting copy under the title. Omitted on pages whose
  /// name already says everything (Settings), shown where the page needs a
  /// word about what it holds.
  final String? subtitle;

  /// Sits at the far end of the title's row — Community Updates' filter
  /// control, My Reports' count. Kept in the header so it shares the title's
  /// baseline instead of each screen re-inventing a row.
  final Widget? trailing;

  /// Layout width to scale against. Defaults to the clamped scale width, so
  /// rotating a handset does not resize the header (see mobile_metrics.dart).
  final double? width;

  const CitizenPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final w = width ?? uiScaleWidth(context);

    // The title and its subtitle, as one block, so [trailing] sits beside the
    // pair rather than beside the title alone.
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: w * .058,
            fontWeight: FontWeight.w700,
            color: AppColors.primaryBlue,
            letterSpacing: -0.3,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            subtitle!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: w * .030, color: CitizenUi.textMuted),
          ),
        ],
      ],
    );

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(w * .04, w * .04, w * .04, w * .04),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            'assets/images/newslogo.webp',
            height: w * .075,
            fit: BoxFit.contain,
            alignment: Alignment.centerLeft,
            errorBuilder: (_, _, _) => Icon(
              Icons.account_balance_rounded,
              size: w * .065,
              color: AppColors.primaryBlue,
            ),
          ),
          SizedBox(height: w * .018),
          // Expanded rather than Flexible on the heading: the title must
          // ellipsize to protect [trailing], which is a control the citizen
          // taps and must never be pushed off the gutter by a long title.
          if (trailing == null)
            heading
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: heading),
                SizedBox(width: w * .03),
                trailing!,
              ],
            ),
        ],
      ),
    );
  }
}
