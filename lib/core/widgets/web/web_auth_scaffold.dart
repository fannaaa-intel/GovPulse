// lib/core/widgets/web/web_auth_scaffold.dart
//
// The shared "layout layer" for the WEB auth flow (verify email/phone, success,
// reset password). Now glass-backed so it matches login / signup / phone:
//   • WebAuthScaffold → WebGlassSurface behind the card column
//   • WebAuthCard     → WebGlassCard (frosted, transition-safe)
//   • WebPrimaryButton → blue fill + deepen-on-hover (login-style)
//   • WebOtpBoxes      → blue outline when a digit is present, visible gray when
//                        empty, red on error, blue on focus
//
// Mobile is never imported here — used only inside each screen's `kIsWeb` branch.

import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../../core/theme/citizen_ui.dart';
import 'web_constants.dart'; // kHeroBgBottom, kWebTwoPanelMinWidth
import 'web_hero_panel.dart'; // WebHeroPanel
import 'web_glass_card.dart'; // WebGlassSurface, WebGlassCard

// ─────────────────────────────────────────────────────────────────────────────
//  Design tokens — change here, every web auth screen updates in lockstep.
// ─────────────────────────────────────────────────────────────────────────────
class WebUi {
  WebUi._();

  // Layout
  static const double cardMaxWidth = 420; // unified (was 400 / 420 / 440)
  static const double cardPadding = 40;
  static const double pagePadNarrow = 32;
  static const double pagePadWide = 48;
  static const double pagePadVertical = 40;
  static const int heroFlex = 56;
  static const int cardFlex = 44;

  // Radii / sizes
  static const double cardRadius = 16;
  static const double buttonHeight = 50;
  static const double buttonRadius = 12; // matches WebInputField

  // Surfaces
  static const Color pageBg = Color(0xFFF8F9FC);
  static const Color divider = CitizenUi.sharedBorder;

  // Outlines (shared with WebOutlinedButton / OTP)
  static const Color outlineRest = Color(0xFFCBD2DE); // visible gray at rest

  // Text
  static const Color ink = Color(0xFF111827);
  static const Color sub = Color(0xFF6B7280);
  static const Color faint = Color(0xFF9CA3AF);

  static const TextStyle title = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    color: ink,
    letterSpacing: -0.5,
  );
  static const TextStyle subtitle = TextStyle(
    fontSize: 13,
    color: Color(0xFF374151), // darker, clearly readable
    height: 1.5,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Responsive shell — single source of truth for the page frame.
//  Narrow → centered glass card.  Wide → hero (56) + glass card column (44).
// ─────────────────────────────────────────────────────────────────────────────
class WebAuthScaffold extends StatelessWidget {
  final AnimationController heroController;
  final String headline;
  final String subtitle;
  final Widget card;

  /// true on screens that must not be popped (e.g. the new-password step).
  final bool blockBack;

  const WebAuthScaffold({
    super.key,
    required this.heroController,
    required this.headline,
    required this.subtitle,
    required this.card,
    this.blockBack = false,
  });

  @override
  Widget build(BuildContext context) {
    final bool wide = MediaQuery.of(context).size.width >= kWebTwoPanelMinWidth;

    // Below the phone threshold the card draws its own edges, so the page must
    // not add a gutter outside it — otherwise "full bleed" is a full-bleed
    // surface inset by 32px, which is just a card with no rim.
    final bool bleed = authIsFullBleed(context);

    final Widget scrollArea = SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: bleed
              ? 0
              : (wide ? WebUi.pagePadWide : WebUi.pagePadNarrow),
          vertical: bleed ? 0 : WebUi.pagePadVertical,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: bleed ? double.infinity : WebUi.cardMaxWidth,
          ),
          child: card,
        ),
    );

            // A full-bleed page must not be vertically CENTRED: Center pins
            // the scroll child to its own height, so the surface stops where
            // the form stops and the backdrop shows through above and below —
            // a full-width card rather than a page. Only the card layout wants
            // centring.
    final Widget cardArea = bleed
        ? SizedBox(
            width: double.infinity,
            height: double.infinity,
            child: scrollArea,
          )
        : Center(child: scrollArea);

    final Widget scaffold = wide
        ? Scaffold(
            backgroundColor: kHeroBgBottom,
            body: Row(
              children: [
                Expanded(
                  flex: WebUi.heroFlex,
                  child: WebHeroPanel(
                    bgController: heroController,
                    headline: headline,
                    subtitle: subtitle,
                  ),
                ),
                // Glass surface behind the card (matches login / signup).
                Expanded(
                  flex: WebUi.cardFlex,
                  child: WebGlassSurface(child: cardArea),
                ),
              ],
            ),
          )
        : Scaffold(
            backgroundColor: const Color(0xFFEFF3FB),
            body: WebGlassSurface(child: SafeArea(child: cardArea)),
          );

    return blockBack ? PopScope(canPop: false, child: scaffold) : scaffold;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Glass card — frosted translucent surface (transition-safe). Children stretch
//  full-width; headers center themselves.
// ─────────────────────────────────────────────────────────────────────────────
class WebAuthCard extends StatelessWidget {
  final List<Widget> children;
  const WebAuthCard({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return WebGlassCard(
      padding: const EdgeInsets.all(WebUi.cardPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Logo + title + subtitle, always centered. Top of every card.
// ─────────────────────────────────────────────────────────────────────────────
class WebCardHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  const WebCardHeader({super.key, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Image.asset("assets/images/applogocrop.webp", height: 44),
        const SizedBox(height: 28),
        Text(title, textAlign: TextAlign.center, style: WebUi.title),
        const SizedBox(height: 8),
        Text(subtitle, textAlign: TextAlign.center, style: WebUi.subtitle),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Primary button — blue fill, full-width, deepen-on-hover (login-style).
// ─────────────────────────────────────────────────────────────────────────────
class WebPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  const WebPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: WebUi.buttonHeight,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        style:
            ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryBlue,
              disabledBackgroundColor: AppColors.primaryBlue.withValues(
                alpha: 0.35,
              ),
              elevation: 0,
              shadowColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(WebUi.buttonRadius),
              ),
            ).copyWith(
              // Filled blue → hover/press DEEPEN the blue (not bleach it white).
              overlayColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.pressed)) {
                  return Colors.black.withValues(alpha: 0.14);
                }
                if (states.contains(WidgetState.hovered)) {
                  return Colors.black.withValues(alpha: 0.08);
                }
                return null;
              }),
            ),
        child: loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.2,
                ),
              )
            : Text(
                label,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  letterSpacing: 0.2,
                ),
              ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  "Back to sign in" link — plain text link (no button hover, by design).
// ─────────────────────────────────────────────────────────────────────────────
class WebBackLink extends StatelessWidget {
  final VoidCallback onTap;
  final String label;
  const WebBackLink({
    super.key,
    required this.onTap,
    this.label = "Back to sign in",
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GestureDetector(
        onTap: onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.arrow_back_rounded, size: 14, color: WebUi.sub),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: WebUi.sub,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Small centered caption (e.g. "We'll send a 6-digit code…").
// ─────────────────────────────────────────────────────────────────────────────
class WebCaption extends StatelessWidget {
  final String text;
  const WebCaption(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 12, color: WebUi.faint),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Password requirements row.
// ─────────────────────────────────────────────────────────────────────────────
class WebRequirementRow extends StatelessWidget {
  final (String, bool) left;
  final (String, bool) right;
  const WebRequirementRow({super.key, required this.left, required this.right});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _WebReq(text: left.$1, met: left.$2),
        const SizedBox(width: 12),
        _WebReq(text: right.$1, met: right.$2),
      ],
    );
  }
}

class _WebReq extends StatelessWidget {
  final String text;
  final bool met;
  const _WebReq({required this.text, required this.met});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(
        children: [
          Icon(
            met ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
            size: 15,
            color: met ? AppColors.green : AppColors.grey,
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                color: met ? AppColors.green : AppColors.grey,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Shared 6-box OTP input.
//  • empty box   → visible gray outline (WebUi.outlineRest)
//  • has a digit → blue outline
//  • focused     → blue outline (focusedBorder)
//  • error       → red (wins over all)
// ─────────────────────────────────────────────────────────────────────────────
class WebOtpBoxes extends StatelessWidget {
  final List<TextEditingController> controllers;
  final List<FocusNode> focusNodes;
  final VoidCallback onChanged;
  final bool showError;
  final Animation<double>? shakeAnimation;

  const WebOtpBoxes({
    super.key,
    required this.controllers,
    required this.focusNodes,
    required this.onChanged,
    this.showError = false,
    this.shakeAnimation,
  });

  @override
  Widget build(BuildContext context) {
    Widget otpField(int index) {
      final bool filled = controllers[index].text.isNotEmpty;
      return TextField(
        controller: controllers[index],
        focusNode: focusNodes[index],
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        maxLength: 1,
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: showError ? AppColors.red : const Color(0xFF111827),
        ),
        decoration: InputDecoration(
          counterText: "",
          filled: true,
          fillColor: showError
              ? AppColors.red.withValues(alpha: 0.05)
              : const Color(0xFFF4F6FB),
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(
              color: showError
                  ? AppColors.red
                  : filled
                  ? AppColors.primaryBlue
                  : WebUi.outlineRest,
              width: filled ? 1.8 : 1.5,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(
              color: showError ? AppColors.red : AppColors.primaryBlue,
              width: 2,
            ),
          ),
        ),
        onChanged: (value) {
          if (value.isNotEmpty && index < 5) {
            focusNodes[index + 1].requestFocus();
          } else if (value.isEmpty && index > 0) {
            focusNodes[index - 1].requestFocus();
          }
          onChanged();
        },
      );
    }

    final Widget row = Row(
      children: [
        for (int index = 0; index < 6; index++) ...[
          if (index > 0) const SizedBox(width: 8), // gap BETWEEN boxes only
          Expanded(child: SizedBox(height: 62, child: otpField(index))),
        ],
      ],
    );

    if (shakeAnimation == null) return row;
    return AnimatedBuilder(
      animation: shakeAnimation!,
      builder: (context, child) => Transform.translate(
        offset: Offset(shakeAnimation!.value, 0),
        child: child,
      ),
      child: row,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Resend countdown line: "Resend code in 00:42"
// ─────────────────────────────────────────────────────────────────────────────
class WebResendTimer extends StatelessWidget {
  final int secondsLeft;
  const WebResendTimer({super.key, required this.secondsLeft});

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          const TextSpan(
            text: "Resend code in ",
            style: TextStyle(fontSize: 12, color: WebUi.sub),
          ),
          TextSpan(
            text: "00:${secondsLeft.toString().padLeft(2, '0')}",
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.primaryBlue,
            ),
          ),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}
