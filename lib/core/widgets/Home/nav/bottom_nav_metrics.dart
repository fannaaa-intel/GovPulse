// lib/core/widgets/Home/nav/bottom_nav_metrics.dart
//
// The size of the citizen bottom bar's icons and labels.
//
// AppBottomNav and HomeBottomNav are the same bar on two different scaffolds
// and must not drift, so the numbers that decide how big it looks live here
// once rather than being typed into both files.
//
// ── Why these are clamped, not free-scaling ───────────────────────────────
// The bar used to size both the icon and the label as a fraction of
// [uiScaleWidth] — `width * 0.065` and `width * 0.028`. Two things went wrong
// with that, and they compound:
//
//   * The icon grew without limit up to the 480dp clamp, so a 430dp handset
//     drew a 28px icon. A tab icon is a glyph, not a picture: past ~24dp it
//     stops reading as an affordance and starts reading as artwork, which is
//     what made the bar look heavy.
//
//   * The LABEL shrank on the same curve while the text it had to hold
//     stayed the same length. "My Reports" needs 140px at 11pt; a 390dp
//     handset gives each of the 5 tabs a 78px slot, so every label on every
//     handset size was being squeezed to fit — 320dp squeezed all five. A
//     crushed label under an oversized icon is the whole of the "too big"
//     look.
//
// So the icon is capped and the type is given a floor. The proportional rule
// still applies between those bounds, which is what keeps a 320dp phone from
// getting a 430dp phone's chrome; the bounds only stop it running away at the
// ends. Labels are additionally allowed to shrink-to-fit at the draw site
// rather than being clipped — see the `_NavLabel` in each bar.

import 'package:flutter/widgets.dart';

import '../../../theme/mobile_metrics.dart';

/// Side length of a bottom-bar icon.
///
/// Proportional between handset sizes, but capped: a tab icon reads as a
/// control up to about 24dp and as decoration past it.
double navIconSize(BuildContext context) =>
    (uiScaleWidth(context) * 0.058).clamp(18.0, 23.0);

/// Point size of a bottom-bar label.
///
/// Floored, because the strings are fixed-length and a label that keeps
/// shrinking with the viewport is what makes the icon look oversized by
/// comparison.
double navLabelSize(BuildContext context) =>
    (uiScaleWidth(context) * 0.029).clamp(10.0, 12.0);

/// Gap between the icon and its label.
const double kNavIconLabelGap = 4;
