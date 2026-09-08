// lib/core/widgets/events/event_slide_in_card.dart
//
// The card itself: a compact, tappable summary of one event that slides in from
// the right edge of the screen. It knows nothing about WHEN it should appear or
// whether it has been seen before — that is event_popup_rules.dart's job, and
// the animation and lifecycle belong to event_slide_in.dart.
//
// Keeping it a plain StatelessWidget with no I/O is what lets the layout be
// tested at 320, 390 and 430dp without a database, a navigator or a clock.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/events_service.dart';
import '../../theme/mobile_metrics.dart';

/// Height of the card's thumbnail, and therefore of the card's content row.
const double _kThumbSize = 50;

/// Width of the category-coloured rail down the leading edge.
///
/// 4, not 3. At 3dp behind a 12dp corner radius the rail reads as a rendering
/// artifact rather than a signal — the corner eats most of its visible length,
/// so what is left looks like a seam. This was only apparent once the widget
/// was rendered for real; it measured fine in the layout tests either way.
const double _kRailWidth = 4;

/// Turns `#14B8A6` (or `FF14B8A6`) into a Color, falling back to the app blue.
///
/// Duplicated from the admin page rather than shared because the admin's copy
/// is private to that file; the shape is four lines and a shared helper would
/// couple a citizen widget to an admin screen.
Color eventColorFromHex(String hex) {
  final cleaned = hex.replaceFirst('#', '').trim();
  final full = cleaned.length == 6 ? 'FF$cleaned' : cleaned;
  final value = int.tryParse(full, radix: 16);
  return value == null ? const Color(0xFF0D47A1) : Color(value);
}

/// A single event, rendered as the floating slide-in card.
///
/// Sizing is proportional to [uiScaleWidth] and clamped, matching the rest of
/// the mobile surface: a 320dp handset must not get a 430dp phone's chrome, and
/// nothing may grow without limit on a large screen.
class EventSlideInCard extends StatelessWidget {
  /// The event being offered.
  final EventModel event;

  /// Opens the event. Called on tap.
  final VoidCallback onTap;

  /// Fraction of the dwell remaining, 1.0 → 0.0. Drives the hairline progress
  /// bar. Null hides the bar entirely, which is what a paused or finished
  /// dwell should look like.
  final double? dwellRemaining;

  const EventSlideInCard({
    super.key,
    required this.event,
    required this.onTap,
    this.dwellRemaining,
  });

  /// The card's width: proportional, but clamped at both ends.
  ///
  /// The lower bound stops a 320dp phone from getting a card too narrow to
  /// hold a title; the upper bound stops the card from covering the page it is
  /// floating over.
  ///
  /// 0.70 rather than 0.72, and capped at 290 rather than 300: rendering the
  /// card for real showed it running wider than its own content on a 390dp+
  /// handset, which read as an oversized panel rather than a notification. The
  /// title now wraps to two lines, so the extra width bought nothing.
  static double widthFor(BuildContext context) =>
      (uiScaleWidth(context) * 0.70).clamp(240.0, 290.0);

  @override
  Widget build(BuildContext context) {
    final w = uiScaleWidth(context);
    final width = widthFor(context);
    final accent = eventColorFromHex(event.categoryColor);

    // Type sizes: proportional between handsets, floored so the card never
    // becomes unreadable on a small screen and capped so it stays compact on a
    // large one. Same reasoning as bottom_nav_metrics.
    final titleSize = (w * 0.036).clamp(13.0, 15.0);
    final metaSize = (w * 0.029).clamp(11.0, 12.5);
    final badgeSize = (w * 0.024).clamp(9.0, 10.0);
    final pad = (w * 0.028).clamp(10.0, 13.0);

    return Semantics(
      button: true,
      // Read as one sentence rather than four fragments, and explicitly says
      // what tapping does — a screen-reader user cannot see the "Tap to view".
      label:
          '${event.title}. '
          '${DateFormat('MMMM d').format(event.eventDate)}, ${event.eventTime}. '
          '${event.location}. Open event.',
      child: Material(
        color: Colors.white,
        elevation: 0,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: width,
            child: Stack(
              children: [
                Padding(
                  padding: EdgeInsets.all(pad),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _Thumbnail(event: event, accent: accent),
                      SizedBox(width: pad * 0.7),
                      // Expanded, not Flexible: the column must claim exactly
                      // the space left over, so the ellipsis has a bounded
                      // width to work against. Without it a long title would
                      // try to size the Row past the card.
                      //
                      // The text column gets the FULL remaining width, and the
                      // badge leads it.
                      //
                      // The badge shares its line with "View ›" rather than
                      // sitting on a line of its own. That is what makes a top
                      // badge affordable: the header row costs one line and
                      // carries two things, so the title still gets its two
                      // lines and the card does not grow. An earlier draft
                      // stacked the badge alone above the title, which spent a
                      // whole line on one small chip and left the title
                      // truncating while the row sat half empty.
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                // Pulled left by the badge's own inner padding
                                // so the WORD lines up with the title's first
                                // letter rather than sitting indented from it.
                                Transform.translate(
                                  offset: const Offset(-_kBadgePadX, 0),
                                  child: _Badge(
                                    // Featured wins when both apply: it is the
                                    // stronger, editorially-chosen signal.
                                    featured: event.isFeatured,
                                    size: badgeSize,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  'View ›',
                                  style: TextStyle(
                                    fontSize: badgeSize + 1,
                                    fontWeight: FontWeight.w700,
                                    color: accent,
                                    height: 1.2,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: pad * 0.3),
                            Text(
                              event.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: titleSize,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF131820),
                                height: 1.22,
                              ),
                            ),
                            SizedBox(height: pad * 0.18),
                            Text(
                              '${event.eventTime} · ${event.location}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: metaSize,
                                color: const Color(0xFF6B7688),
                                height: 1.25,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Category rail. Positioned rather than a Container border so
                // it spans the card's full height regardless of content.
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: Container(width: _kRailWidth, color: accent),
                ),

                // Full-bleed along the bottom edge rather than inset above
                // the meta line, where it read as an underline on the address.
                if (dwellRemaining != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _DwellBar(value: dwellRemaining!, color: accent),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The event's photo, or a date block when it has none.
///
/// An event without `image_url` is normal — most LGU events are posted without
/// artwork — so the empty state has to be a designed thing rather than a
/// placeholder. A day-over-month block in the category colour reads as
/// deliberate and carries information the card would otherwise repeat in text.
class _Thumbnail extends StatelessWidget {
  final EventModel event;
  final Color accent;

  const _Thumbnail({required this.event, required this.accent});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: _kThumbSize,
        height: _kThumbSize,
        child: (event.imageUrl == null || event.imageUrl!.isEmpty)
            ? _DateBlock(date: event.eventDate, accent: accent)
            : CachedNetworkImage(
                imageUrl: event.imageUrl!,
                fit: BoxFit.cover,
                // Both fallbacks are the date block rather than a spinner or a
                // broken-image icon: the card is on screen for 8 seconds, so a
                // placeholder that resolves late is worse than one that was
                // always meaningful.
                placeholder: (_, _) => _DateBlock(
                  date: event.eventDate,
                  accent: accent,
                ),
                errorWidget: (_, _, _) => _DateBlock(
                  date: event.eventDate,
                  accent: accent,
                ),
              ),
      ),
    );
  }
}

/// Day over month, on the category colour.
class _DateBlock extends StatelessWidget {
  final DateTime date;
  final Color accent;

  const _DateBlock({required this.date, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          // A two-stop gradient from the category colour gives the block some
          // depth without introducing a second hue.
          colors: [accent, Color.lerp(accent, Colors.white, 0.42)!],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            DateFormat('d').format(date),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            DateFormat('MMM').format(date).toUpperCase(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 8,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

/// Horizontal padding inside the badge pill.
///
/// Named because the header row cancels it out: see [_Badge]'s note on optical
/// alignment.
const double _kBadgePadX = 5;

/// FEATURED or NEW, never both.
///
/// ── Why the caller shifts this left ──────────────────────────────────────
/// The pill's BACKGROUND starts at the column's left edge, but its TEXT starts
/// [_kBadgePadX] further in. Against a title that has no such padding, the two
/// text runs do not line up — the badge word reads as indented by a few pixels,
/// which is exactly the kind of misalignment that looks like a mistake rather
/// than a choice. The header row pulls the badge left by that padding so the
/// TEXT edges align and the pill's fill bleeds a few pixels into the gutter,
/// which is the correct optical result.
class _Badge extends StatelessWidget {
  final bool featured;
  final double size;

  const _Badge({required this.featured, required this.size});

  @override
  Widget build(BuildContext context) {
    final bg = featured ? const Color(0xFFE8F6ED) : const Color(0xFFE7EDF9);
    final fg = featured ? const Color(0xFF0E7C56) : const Color(0xFF0A3578);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: _kBadgePadX,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        featured ? 'FEATURED' : 'NEW',
        style: TextStyle(
          fontSize: size,
          fontWeight: FontWeight.w700,
          color: fg,
          letterSpacing: 0.8,
          height: 1.2,
        ),
      ),
    );
  }
}

/// The hairline that shows the 8 seconds running out.
///
/// Deliberately quiet: it is a reassurance that the card will leave on its own,
/// not a countdown demanding attention.
class _DwellBar extends StatelessWidget {
  final double value;
  final Color color;

  const _DwellBar({required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
        height: 2.5,
        child: LinearProgressIndicator(
          value: value.clamp(0.0, 1.0),
          backgroundColor: const Color(0x14000000),
          valueColor: AlwaysStoppedAnimation<Color>(color.withValues(alpha: .55)),
        ),
    );
  }
}
