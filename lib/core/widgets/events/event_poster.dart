import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../media_viewer.dart';

/// An event poster thumbnail that opens full-screen when tapped.
///
/// ── Why this widget exists ──────────────────────────────────────────────────
/// Every citizen-facing event surface draws the poster small and with
/// `BoxFit.cover`, so the artwork is both SHRUNK and CROPPED: the detail
/// screen's is ~148px wide, the web detail pane's 200x132, the right rail's
/// 130 tall. That trade is right for the layouts — the poster must not push
/// the venue, date and time below the fold (see the call sites) — but LGU
/// event artwork routinely carries the schedule, the requirements and a
/// contact number as text baked into the image. Rendered at a third of a
/// phone's width and cropped to a letterbox, none of it is readable, and there
/// was no tap target anywhere to get a better look.
///
/// So the thumbnail stays exactly the size the layout wants and a tap opens
/// [openMediaViewer] — the SAME viewer report imagery already uses, which
/// means pinch/pan zoom, `BoxFit.contain` (no crop, whatever shape the poster
/// is), the close chip, and the web root-navigator handling are all inherited
/// rather than reimplemented here.
///
/// ── Caching ─────────────────────────────────────────────────────────────────
/// Event posters are served by `getPublicUrl` (see
/// admin_events_provider.dart), so unlike report media the url is STABLE — no
/// signed expiry in the query string. That makes the url itself a valid cache
/// key, and it is passed explicitly on both the thumbnail and the viewer so
/// the two share ONE cache entry: opening the preview re-uses the bytes the
/// thumbnail already downloaded instead of fetching the poster a second time.
/// Without the explicit key they would still collide by default today, but the
/// pairing is the thing worth stating, because it is what makes the preview
/// open instantly and cost nothing extra on a mobile connection.
///
/// [memCacheWidth] is deliberately NOT set. The thumbnail is the only consumer
/// of the decoded bitmap at this size, and capping the decode here would mean
/// the viewer re-decodes the full-resolution image on open — the opposite of
/// the point. Posters are single images per event, not a scrolled grid, so
/// there is no decode budget problem of the kind the newsfeed grid solves.
class EventPoster extends StatelessWidget {
  /// The poster's public url. Callers only build this widget when non-null.
  final String imageUrl;

  /// Drawn size. Either may be null to let the parent's constraints decide,
  /// matching what each call site already did with its own `SizedBox`.
  final double? width;
  final double? height;

  final BorderRadius borderRadius;

  /// Shown while loading and on failure, supplied by the caller so each
  /// surface keeps the empty state it already had — a shimmer on the detail
  /// screens, a muted glyph box in the panels.
  final Widget Function(BuildContext context) placeholderBuilder;
  final Widget Function(BuildContext context) errorBuilder;

  /// Accessibility label for the tap target.
  final String semanticLabel;

  /// Size of the corner expand affordance. Scaled by the caller so a 130px
  /// rail poster does not get the same badge as a full-width one.
  final double badgeSize;

  const EventPoster({
    super.key,
    required this.imageUrl,
    required this.placeholderBuilder,
    required this.errorBuilder,
    this.width,
    this.height,
    this.borderRadius = BorderRadius.zero,
    this.semanticLabel = 'Event poster. Double tap to view full screen.',
    this.badgeSize = 26,
  });

  @override
  Widget build(BuildContext context) {
    final image = CachedNetworkImage(
      imageUrl: imageUrl,
      // See the class doc: a stable public url doubles as the cache key, and
      // the viewer is handed the same one.
      cacheKey: imageUrl,
      fit: BoxFit.cover,
      fadeInDuration: const Duration(milliseconds: 300),
      fadeOutDuration: const Duration(milliseconds: 100),
      placeholder: (context, _) => placeholderBuilder(context),
      errorWidget: (context, _, _) => errorBuilder(context),
    );

    // ── Why a badge and not a tooltip ───────────────────────────────────────
    // A hover tooltip would say "View poster" on the web and NOTHING on a
    // phone, where the affordance is needed most — and the framework Tooltip's
    // "hover, then click something that rebuilds it away" path is the exact
    // flow that throws the `_zOrderIndex != null` assertion main.dart has to
    // filter. A painted corner badge is platform-neutral, visible without
    // input, and carries no overlay.
    final badge = Positioned(
      right: badgeSize * 0.23,
      bottom: badgeSize * 0.23,
      child: IgnorePointer(
        child: Container(
          padding: EdgeInsets.all(badgeSize * 0.18),
          // ── Why a LIGHT disc and not a dark scrim ────────────────────────
          // The first version was white-on-black-55%, which disappeared into
          // dark artwork — and event posters skew dark (a stage, a crowd, a
          // night shot). Only a browser screenshot showed it: at 320px on a
          // dark photo the affordance was invisible, which is the one thing it
          // cannot be. A near-opaque white disc with a dark glyph reads on any
          // artwork, light or dark, and the hairline border keeps it from
          // vanishing into a white poster.
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.92),
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.black.withValues(alpha: 0.08),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: badgeSize * 0.15,
              ),
            ],
          ),
          child: Icon(
            Icons.zoom_out_map_rounded,
            size: badgeSize * 0.6,
            color: const Color(0xFF1F2937),
          ),
        ),
      ),
    );

    return Semantics(
      button: true,
      image: true,
      label: semanticLabel,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: borderRadius,
          onTap: () => openMediaViewer(
            context,
            urls: [imageUrl],
            cacheKeys: [imageUrl],
          ),
          child: ClipRRect(
            borderRadius: borderRadius,
            child: SizedBox(
              width: width,
              height: height,
              // The badge sits INSIDE the clip so it is rounded off with the
              // poster rather than hanging over the corner.
              child: Stack(fit: StackFit.passthrough, children: [image, badge]),
            ),
          ),
        ),
      ),
    );
  }
}
