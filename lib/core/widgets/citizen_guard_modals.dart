import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../router/legacy_nav.dart';
import '../services/citizen_guard.dart';
import '../services/session_teardown.dart';
import '../theme/app_colors.dart';
import 'app_dialog.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Citizen enforcement modals + the per-feature gate helper.
//   • Suspension  → blocking modal (reason + until) → sign out
//   • Restriction → notice modal on login/live, and a "feature unavailable"
//     modal when a restricted feature is tapped.
// ════════════════════════════════════════════════════════════════════════════

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _untilLine(DateTime? expires) {
  if (expires == null) return 'This stays in effect until an administrator lifts it.';
  final d = expires.toLocal();
  return 'In effect until ${d.day} ${_months[d.month - 1]} ${d.year}.';
}

/// [_untilLine] for surfaces outside this file. The citizen shell's restricted-
/// feed pane reuses it so the "in effect until…" sentence is worded identically
/// whether the refusal arrives as a modal or as a full pane.
String citizenGuardUntilLine(DateTime? expires) => _untilLine(expires);

/// Gate a restricted feature. Returns true when allowed; when blocked it shows
/// the "feature unavailable" modal and returns false. Call at feature entry
/// points (report / feedback / suggest / news feed / AI chat).
bool citizenGuardAllow(BuildContext context, String feature) {
  if (!CitizenGuard.I.isRestricted(feature)) return true;
  showFeatureBlockedModal(context, feature);
  return false;
}

/// Signs a suspended citizen out from the blocking modal.
///
/// The caller pops the modal BEFORE calling this (see [showSuspendedModal]),
/// which matters: at that point no auth change is in flight, so the navigator
/// is free and the pop cannot land on a locked one.
///
/// ── The two platforms diverge after that, deliberately ─────────────────────
/// WEB has an auth guard watching the session. Signing out drops
/// [_authRedirect] onto its signed-out branch, and `_signedOutRedirect` returns
/// /login from every shell location — so the guard navigates on its own. Issuing
/// a second, imperative navigation here is exactly what raced the redirect in
/// the logout handlers, so web does not issue one. It runs the shared teardown
/// instead, which the ad-hoc sign-out here never did — without it a suspended
/// citizen's providers and singletons would survive into the next session.
///
/// MOBILE is unchanged, character for character: no guard is watching, so
/// [goToLogin] is the only thing that moves the user, and there is no teardown
/// to run (it is web-only). Written as a separate branch rather than a shared
/// tail so that path reads exactly as it did before.
Future<void> _signOut(BuildContext context) async {
  CitizenGuard.I.stop();

  if (kIsWeb) {
    // Captured before the await, while the context is certainly mounted — the
    // teardown has to outlive this widget. Same contract as the logout handlers.
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}
    await tearDownSession(container);
    return;
  }

  try {
    await Supabase.instance.client.auth.signOut();
  } catch (_) {}
  if (context.mounted) {
    goToLogin(context);
  }
}

// ── Suspension: blocking, must sign out ──────────────────────────────────────
Future<void> showSuspendedModal(BuildContext context, SuspensionInfo info) {
  return showAppDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => PopScope(
      canPop: false,
      child: _GuardDialog(
        icon: Icons.pause_circle_filled_rounded,
        accent: AppColors.red,
        title: 'Account suspended',
        lines: [
          if ((info.reason ?? '').trim().isNotEmpty) info.reason!.trim(),
          _untilLine(info.expiresAt),
          'You have been signed out. Contact the LGU if you believe this is a mistake.',
        ],
        primaryLabel: 'Sign out',
        onPrimary: () {
          Navigator.of(ctx).pop();
          _signOut(context);
        },
      ),
    ),
  );
}

// ── Restriction: informational notice (login / live) ─────────────────────────
Future<void> showRestrictionNotice(BuildContext context, RestrictionInfo info) {
  return showAppDialog<void>(
    context: context,
    builder: (ctx) => _GuardDialog(
      icon: Icons.info_rounded,
      accent: AppColors.orange,
      title: 'Some features are limited',
      lines: [
        'An administrator has limited your access to: '
            '${info.features.map(citizenFeatureLabel).join(', ')}.',
        if ((info.reason ?? '').trim().isNotEmpty) 'Reason: ${info.reason!.trim()}',
        _untilLine(info.expiresAt),
        'You can still use every other part of GovPulse.',
      ],
      primaryLabel: 'Got it',
      onPrimary: () => Navigator.of(ctx).pop(),
    ),
  );
}

// ── Restriction: a specific feature was tapped ───────────────────────────────
Future<void> showFeatureBlockedModal(BuildContext context, String feature) {
  final info = CitizenGuard.I.status.value.restriction;
  return showAppDialog<void>(
    context: context,
    builder: (ctx) => _GuardDialog(
      icon: Icons.lock_rounded,
      accent: AppColors.orange,
      title: 'Feature unavailable',
      lines: [
        'Your access to ${citizenFeatureLabel(feature)} is currently limited by an administrator.',
        if ((info?.reason ?? '').trim().isNotEmpty) 'Reason: ${info!.reason!.trim()}',
        _untilLine(info?.expiresAt),
      ],
      primaryLabel: 'OK',
      onPrimary: () => Navigator.of(ctx).pop(),
    ),
  );
}

// ── Shared dialog chrome ─────────────────────────────────────────────────────
class _GuardDialog extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final String title;
  final List<String> lines;
  final String primaryLabel;
  final VoidCallback onPrimary;
  const _GuardDialog({
    required this.icon,
    required this.accent,
    required this.title,
    required this.lines,
    required this.primaryLabel,
    required this.onPrimary,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 30, color: accent),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1F2937),
                ),
              ),
              const SizedBox(height: 10),
              for (final line in lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    line,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13.5,
                      height: 1.45,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: onPrimary,
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    primaryLabel,
                    style: const TextStyle(
                      fontSize: 15,
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
}
