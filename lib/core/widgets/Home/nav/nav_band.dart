// lib/core/widgets/Home/nav/nav_band.dart
//
// Which navigation chrome a viewport gets. Shared by `home_screen.dart` and
// `responsive_nav_scaffold.dart` so the two can never drift apart — they used
// to each carry their own copy of this rule.
//
// Kept a dependency-free leaf (foundation + dart:ui only) precisely so both of
// those can import it: responsive_nav_scaffold already imports home_screen, so
// anything the pair shares has to live below them both or it's an import cycle.

import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:ui' show Size;

/// Which navigation chrome to show for a given viewport.
enum NavBand { phone, drawer, topNav }

/// Width at/above which the horizontal top nav is shown.
const double kNavTopBreakpoint = 900;

/// SHORTEST-SIDE below which a native device is treated as a phone.
///
/// Deliberately measured on the shortest side, not on width. A device's
/// shortest side does not change when you rotate it, so it describes the DEVICE
/// (a ~390–430dp phone vs a ~600dp+ tablet) rather than the current
/// orientation. Testing `width < 600` instead meant a phone turned landscape
/// (~750–930dp wide) stopped matching, silently lost its bottom nav, and got
/// served the tablet drawer layout in a ~390dp-tall viewport.
///
/// 600 is the Android `sw600dp` convention — the same line the platform itself
/// draws between phone and tablet.
const double kNavPhoneShortestSide = 600;

/// Legacy alias for [kNavPhoneShortestSide]. Kept only so the old name still
/// resolves; prefer the shortest-side name, which says what it measures.
@Deprecated('Use kNavPhoneShortestSide — the band is decided on shortest side')
const double kNavMobileBreakpoint = kNavPhoneShortestSide;

/// The nav chrome for [size]:
///
///   • phone  (native, shortest side < 600) → bottom nav, in EITHER orientation
///   • topNav (width >= 900)                → horizontal top nav
///   • drawer (everything else)             → side drawer + slim app bar
///
/// The phone check comes FIRST and short-circuits, which is what keeps a
/// rotated phone on the bottom nav: in landscape it is simultaneously a phone
/// AND wider than the 900 top-nav line, and without the ordering the wider-wins
/// rule would hand it desktop chrome.
///
/// Web is never "phone" — the citizen web app is desktop-first by design and a
/// narrow browser window is a small window, not a handset.
NavBand resolveNavBand(Size size) {
  if (!kIsWeb && size.shortestSide < kNavPhoneShortestSide) {
    return NavBand.phone;
  }
  if (size.width >= kNavTopBreakpoint) return NavBand.topNav;
  return NavBand.drawer;
}

// ═══════════════════════════════════════════════════════════════════════════
//  Citizen web shell — how many columns the persistent shell shows.
//
//  This lives HERE, next to [resolveNavBand], for the reason the file header
//  gives: the width rule for the citizen web chrome gets exactly one home. The
//  old `home_nav_layout.dart` was a second copy of the band rule that drifted
//  out of use entirely and was deleted; a second copy of the SHELL rule would
//  rot the same way.
//
//  The shell is an addition to the topNav band, not a replacement for it. Below
//  [kNavTopBreakpoint] nothing changes — the drawer band and the phone band
//  behave exactly as they do today, which is what keeps the mobile app and the
//  narrow-browser layout untouched by the shell work.
// ═══════════════════════════════════════════════════════════════════════════

/// How the persistent citizen shell arranges itself for a given viewport.
///
/// The columns are dropped in order of how much they earn their width: the
/// right sidebar first (quick actions fold into the centre pane), then the left
/// rail's labels (it stays, as icons). The centre pane is never dropped — it is
/// the thing the shell exists to hold.
enum ShellLayout {
  /// Left rail (labelled) + centre + right sidebar.
  threeColumn,

  /// Left rail (labelled) + centre. No right sidebar.
  railLabels,

  /// Left rail collapsed to icons + centre. No right sidebar.
  railIcons,

  /// No shell. The existing drawer / bottom-nav chrome, unchanged.
  drawer,
}

/// Width at/above which all three shell columns are shown.
const double kShellThreeColumnMin = 1280;

/// Width at/above which the left rail shows labels rather than icons only.
/// Between this and [kShellThreeColumnMin] the rail keeps its labels but the
/// right sidebar is dropped.
///
/// 920, not the 1024 it began as. At 1024 the whole 900–1024 band fell through
/// to the drawer, which left a window around 1000px showing a 680 feed column
/// stranded in grey with both sides empty and no navigation on screen at all —
/// while Facebook, at that same width, is showing its left sidebar beside the
/// feed. The band is wide enough for the real thing: 920 − 288 leaves 632 for
/// the centre, and the feed column narrows into it rather than overflowing.
///
/// 920 rather than lower because that is the MEASURED point where the top nav
/// is clean — brand + links + bell + chip overflow at exactly 900 — and in rail
/// mode there is no hamburger to pay for (the 960 figure quoted in
/// citizen_shell is the with-hamburger case, which is the drawer's problem, not
/// this one).
///
/// This does NOT resurrect the icon-only rail, which is what the band was
/// dropped for in the first place: it gets the LABELLED rail, so nothing here
/// is ~11 bare icons in three unlabelled clusters.
const double kShellRailLabelsMin = 920;

/// The shell arrangement for [size].
///
///   • width >= 1280        → three columns
///   •  920 ..< 1280        → drop the right sidebar
///   •  900 ..<  920        → [ShellLayout.railIcons], which nothing renders:
///                            the shell folds it into the drawer
///   • below 900, or phone  → [ShellLayout.drawer] (no shell at all)
///
/// Delegates its lower bound to [resolveNavBand] instead of re-testing the
/// width, so the shell can never disagree with the nav chrome about where the
/// desktop layout starts — including the shortest-side phone rule, which is why
/// a rotated handset gets [ShellLayout.drawer] rather than a three-column web
/// shell crammed into a ~390dp-tall viewport.
ShellLayout resolveShellLayout(Size size) {
  if (resolveNavBand(size) != NavBand.topNav) return ShellLayout.drawer;
  if (size.width >= kShellThreeColumnMin) return ShellLayout.threeColumn;
  if (size.width >= kShellRailLabelsMin) return ShellLayout.railLabels;
  return ShellLayout.railIcons;
}

/// Whether [layout] shows the right quick-actions sidebar.
bool shellHasRightSidebar(ShellLayout layout) =>
    layout == ShellLayout.threeColumn;

/// Whether [layout] shows a left rail at all (labelled or icon-only).
bool shellHasLeftRail(ShellLayout layout) => layout != ShellLayout.drawer;
