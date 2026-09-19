// Throwaway preview: the report detail page's bottom action bar, rendered at
// the real web content width with a stand-in card above it, so the gutter the
// bar uses can be compared against the gutter the card uses.
//
// The bug this exists to see: the bar padded itself with `w * .04`, where w is
// uiScaleWidth — which CLAMPS AT 480 on web, making the gutter a flat 19px at
// every viewport, while the card above uses kAccountPageGutter (32px). The
// copy started 13px left of the card's edge and the button floated mid-span.
//
// Run: flutter run -d chrome -t tool/preview_report_bottom_bar.dart
import 'package:flutter/material.dart';
import 'package:govpulse/core/theme/app_colors.dart';
import 'package:govpulse/core/theme/citizen_ui.dart';
import 'package:govpulse/core/widgets/Home/Account/account_web_kit.dart';

void main() => runApp(const _App());

/// The shell's centre column at a 1920 window: 1920 - 288 rail - 340 sidebar.
const double _kColumn = 1292;

class _App extends StatelessWidget {
  const _App();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: CitizenUi.pageBg,
        body: Center(
          child: SizedBox(
            width: _kColumn,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Stand-in for the report card: same band, same gutter as the
                // real page body. The bar's copy must start exactly where this
                // card's text starts.
                Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: kAccountMaxWidth,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: kAccountPageGutter,
                      ),
                      child: Container(
                        height: 120,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: CitizenUi.sharedBorder),
                        ),
                        child: const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            'CARD EDGE — the bar below must align with this',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const _Bar(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A copy of the real `_buildBottomBar` web branch, kept in sync by hand.
class _Bar extends StatelessWidget {
  const _Bar();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        kAccountPageGutter,
        16,
        kAccountPageGutter,
        16,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: CitizenUi.sharedBorder)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kAccountMaxWidth),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Need help with this report?',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                    Text(
                      'Chat with an agent for follow-up.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              Flexible(
                child: ElevatedButton.icon(
                  onPressed: () {},
                  icon: const Icon(
                    Icons.chat_bubble_outline_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                  label: const Text(
                    'Chat with agent',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
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
}
