// lib/core/widgets/citizen_shell_scope.dart

import 'package:flutter/widgets.dart';

/// Marks the subtree that is mounted INSIDE the citizen web shell's centre
/// column, so a shared screen can tell "I am a pane" from "I am the page".
///
/// ── The problem this exists to solve ──────────────────────────────────────
/// The Settings sub-screens — Contact Support, Change Password, About, Terms,
/// Privacy, My Submissions — each pass a `shellTitle` to [ResponsivePageBody],
/// which above 900px swaps in `SettingsWebShell`: a 600px content column beside
/// a large decorative brand panel with a grid pattern and glow orbs.
///
/// That was right when these were standalone full-page routes and the browser
/// window was theirs. It is wrong inside the shell, where the page already has
/// a top nav and a left rail: the panel becomes a marketing hero sitting in the
/// middle of a settings pane, next to navigation that is already doing the job
/// the panel was inventing something to do.
///
/// The screens cannot tell the difference on their own — the width they see is
/// the centre column's, which is comfortably over 900 — so the shell says so.
///
/// ── Why an InheritedWidget rather than a parameter ────────────────────────
/// The alternative is a `embedded: true` flag threaded through every one of
/// those screens and every widget between them and [ResponsivePageBody]. These
/// screens are shared with the mobile app, so that flag would have to be added
/// to their public constructors and defaulted at every mobile call site, for a
/// fact none of them actually want to know. The shell is the only place that
/// knows it, so it is the only place that says it.
///
/// Deliberately does NOT reach dialogs. The quick-action forms open on the ROOT
/// navigator, whose context sits above this scope, so they keep the standalone
/// treatment they were designed with.
class CitizenShellScope extends InheritedWidget {
  const CitizenShellScope({super.key, required super.child});

  /// True when [context] is inside the citizen shell's centre column.
  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CitizenShellScope>() != null;

  @override
  bool updateShouldNotify(CitizenShellScope oldWidget) => false;
}
