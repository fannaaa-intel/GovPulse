import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/ai_detection_badge.dart';
import '../../../core/widgets/app_dialog.dart';
import '../../../core/widgets/media_source_badge.dart';
import '../theme/admin_ui.dart';
import 'admin_skeleton.dart';
import 'admin_submission_ui.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Report detail kit
//
//  The building blocks of a REPORT DETAIL view — the titled panes, the id
//  block, the icon-led sections, the attachment grid and its viewers, and the
//  action buttons at the foot.
//
//  Shared, because the admin console and the staff console show the SAME report
//  from two sides: the admin triages and oversees it, the office works it. They
//  differ in what they may see and do, not in what a report detail looks like,
//  so the layout lives here once and each console supplies its own content.
//  (AdminUi and StaffUi carry identical surface/border/text values, so a pane
//  built from these tokens sits correctly in either console.)
//
//  Nothing here reads a model: every widget takes plain values, so it can be
//  fed from AdminReport, StaffReport, or anything that comes next.
// ════════════════════════════════════════════════════════════════════════════

/// Width at which a report detail splits into the two-column layout.
const double kReportDetailTwoPaneFrom = 900;

/// Width a report LIST needs before it becomes a table instead of cards.
///
/// Derived, not picked: the widest cell content the table has to seat, divided
/// by that column's flex, gives the narrowest usable flex unit —
///
///   category  "Road & Infrastructure" + 30px icon ≈ 180 over flex 4  → 45.0
///   submitter "Mark Reduca" + role chip           ≈ 134 over flex 3  → 44.7
///   progress  "Awaiting triage"                   ≈  92 over flex 2  → 46.0
///   status    pill + overdue chip                 ≈ 143 over flex 3  → 47.7
///
/// — so ~48px a unit, ×16 units, plus the 30px media column and 32px of row
/// padding. Below this the table was still drawing: "Road & Infrastructu…",
/// "Awaiting tria…", and an overdue chip squeezed down to a bare clock. The
/// cards say all of it in full, so they take over sooner.
const double kReportTableFrom = 840;

// ── Category visuals — the same webp illustrations the citizen form uses ──────

String reportCategoryAsset(String key) {
  switch (key) {
    case 'road':
      return 'assets/images/report/roadtwo.webp';
    case 'waste':
      return 'assets/images/report/bin.webp';
    case 'drainage':
      return 'assets/images/report/road.webp';
    case 'streetlight':
      return 'assets/images/report/lamppost.webp';
    case 'environment':
      return 'assets/images/report/leaf.webp';
    case 'others':
    default:
      return 'assets/images/report/menu.webp';
  }
}

/// Glyph fallback for [reportCategoryAsset], and the heading icon on the
/// detail's Category section.
IconData reportCategoryIcon(String key) {
  switch (key) {
    case 'road':
      return Icons.add_road_rounded;
    case 'waste':
      return Icons.delete_outline_rounded;
    case 'drainage':
      return Icons.water_drop_rounded;
    case 'streetlight':
      return Icons.lightbulb_rounded;
    case 'environment':
      return Icons.park_rounded;
    default:
      return Icons.flag_rounded;
  }
}

Color reportCategoryColor(String key) {
  switch (key) {
    case 'road':
      return const Color(0xFF3B82F6);
    case 'waste':
      return const Color(0xFF84CC16);
    case 'drainage':
      return const Color(0xFF06B6D4);
    case 'streetlight':
      return const Color(0xFFF59E0B);
    case 'environment':
      return const Color(0xFF22C55E);
    default:
      return const Color(0xFF64748B);
  }
}

/// The rounded tile carrying a report category's illustration — the icon on a
/// list row, and the stand-in for a report with no photo.
class ReportCategoryIconBox extends StatelessWidget {
  final String categoryKey;
  final double size;
  const ReportCategoryIconBox(this.categoryKey, {super.key, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final c = reportCategoryColor(categoryKey);
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.16),
      decoration: BoxDecoration(
        color: AdminUi.subtle,
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: Image.asset(
        reportCategoryAsset(categoryKey),
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) =>
            Icon(reportCategoryIcon(categoryKey), size: size * 0.5, color: c),
      ),
    );
  }
}

// ── Panes & sections ─────────────────────────────────────────────────────────

/// A titled white card — one of the two panes of a report detail.
class DetailPane extends StatelessWidget {
  final String title;
  final Widget child;
  const DetailPane({super.key, required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AdminUi.surface,
        borderRadius: BorderRadius.circular(AdminUi.cardRadius),
        border: Border.all(color: AdminUi.border),
        boxShadow: AdminUi.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AdminUi.textPrimary,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

/// The detail's way out, styled to sit on a pane's top-right corner.
class DetailPaneCloseButton extends StatelessWidget {
  const DetailPaneCloseButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AdminUi.subtle,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.pop(context),
        child: Tooltip(
          message: 'Close',
          child: Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              border: Border.fromBorderSide(BorderSide(color: AdminUi.border)),
            ),
            child: const Icon(
              Icons.close_rounded,
              size: 18,
              color: AdminUi.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// "Label: value" line in the details pane's id block. Pass [value] for plain
/// text or [trailing] for a widget (the status pill).
class DetailKvRow extends StatelessWidget {
  final String label;
  final String? value;
  final Widget? trailing;
  const DetailKvRow({super.key, required this.label, this.value, this.trailing});

  /// Height of one status pill — label 11px in 4px of vertical padding.
  static const double _pillLine = 21;

  @override
  Widget build(BuildContext context) {
    final labelText = Text(
      '$label: ',
      style: const TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
        color: AdminUi.textPrimary,
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // A pill stands taller than the label beside it, so tops flush left
          // the label riding above the pill's own text. Give the label the
          // pill's line height and centre it in that — trailing content that
          // wraps still grows downward from the same first line.
          if (trailing == null)
            labelText
          else
            SizedBox(
              height: _pillLine,
              child: Center(widthFactor: 1, child: labelText),
            ),
          Expanded(
            child: trailing == null
                ? Text(
                    value ?? '—',
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.35,
                      color: AdminUi.textSecondary,
                    ),
                  )
                // Loosens the Expanded's tight width so a pill keeps its own
                // width instead of stretching across the pane.
                : Align(alignment: Alignment.centerLeft, child: trailing!),
          ),
        ],
      ),
    );
  }
}

/// An icon + heading with its content indented beneath — the repeating unit of
/// the details pane (Category, Location, Reported By, Details, Attachments).
class DetailIconSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;
  final bool isLast;
  const DetailIconSection({
    super.key,
    required this.icon,
    required this.title,
    required this.child,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: AppColors.primaryBlue),
              const SizedBox(width: 7),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AdminUi.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Padding(padding: const EdgeInsets.only(left: 22), child: child),
        ],
      ),
    );
  }
}

/// The reported location as one line — "Brgy. Maura, Zone 1". Sits under the
/// Location heading, which already supplies the pin icon, so this stays plain
/// text rather than a box of its own.
class DetailLocationBlock extends StatelessWidget {
  final String? barangay;
  final String? address;
  const DetailLocationBlock({super.key, this.barangay, this.address});

  @override
  Widget build(BuildContext context) {
    final parts = [
      if (barangay != null && barangay!.isNotEmpty) barangay!,
      if (address != null && address!.isNotEmpty) address!,
    ];
    if (parts.isEmpty) {
      return const Text(
        'No location provided.',
        style: TextStyle(fontSize: 13, color: AdminUi.textMuted),
      );
    }
    return Text(
      parts.join(', '),
      style: const TextStyle(
        fontSize: 13,
        height: 1.4,
        color: AdminUi.textSecondary,
      ),
    );
  }
}

/// Muted placeholder for a section that has nothing to show yet.
class DetailEmptyNote extends StatelessWidget {
  final IconData icon;
  final String text;
  const DetailEmptyNote({super.key, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AdminUi.subtle,
        borderRadius: BorderRadius.circular(AdminUi.controlRadius),
        border: Border.all(color: AdminUi.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AdminUi.textMuted),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: AdminUi.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// How much room the caller can spare for a secondary chip.
///
/// Dense layouts (a table cell, a list row's meta line) get the short forms so
/// the chip sits BESIDE the status pill instead of wrapping under it — a chip
/// that drops to a second line makes one row taller than its neighbours, which
/// is what a column of pills is supposed to make easy to scan.
enum ChipDensity {
  /// The full label. Detail panes and cards, where there's room.
  full,

  /// Just the number — "8d". The icon and the colour already say "late".
  compact,

  /// The icon alone. Last resort; the meaning moves into the tooltip.
  icon,
}

/// "Overdue · Nd" — the report has been sitting too long.
class DetailOverdueChip extends StatelessWidget {
  final int days;
  final ChipDensity density;
  const DetailOverdueChip(
    this.days, {
    super.key,
    this.density = ChipDensity.full,
  });

  @override
  Widget build(BuildContext context) {
    final label = switch (density) {
      ChipDensity.full => 'Overdue · ${days}d',
      ChipDensity.compact => '${days}d',
      ChipDensity.icon => null,
    };
    return Tooltip(
      message: 'Overdue by $days day${days == 1 ? '' : 's'}',
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: label == null ? 4 : 7,
          vertical: 2,
        ),
        decoration: BoxDecoration(
          color: AppColors.orange.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.orange.withValues(alpha: 0.30)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.schedule_rounded,
              size: 11,
              color: AppColors.orange,
            ),
            if (label != null) ...[
              const SizedBox(width: 3),
              Text(
                label,
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.orange,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Actions ──────────────────────────────────────────────────────────────────

/// Lays action buttons side by side, dropping to a stack when the pane is too
/// narrow to keep both labels on one line.
class DetailActionRow extends StatelessWidget {
  final List<Widget> children;
  const DetailActionRow({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    if (children.length == 1) return children.first;
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < 300) {
          return Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                children[i],
              ],
            ],
          );
        }
        return Row(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(child: children[i]),
            ],
          ],
        );
      },
    );
  }
}

class DetailActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool outlined;
  final VoidCallback? onTap;
  const DetailActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    this.onTap,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    final style = ButtonStyle(
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 10, vertical: 13),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AdminUi.controlRadius),
        ),
      ),
    );
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 17),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );

    return SizedBox(
      width: double.infinity,
      child: outlined
          ? OutlinedButton(
              onPressed: onTap,
              style: style.merge(
                OutlinedButton.styleFrom(
                  foregroundColor: color,
                  side: BorderSide(color: color.withValues(alpha: 0.45)),
                ),
              ),
              child: content,
            )
          : FilledButton(
              onPressed: onTap,
              style: style.merge(
                FilledButton.styleFrom(backgroundColor: color),
              ),
              child: content,
            ),
    );
  }
}

/// The "Action" heading + a stack of buttons at the foot of a details pane.
class DetailActionSection extends StatelessWidget {
  final List<Widget> buttons;
  const DetailActionSection({super.key, required this.buttons});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Action',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AdminUi.textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        for (var i = 0; i < buttons.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          buttons[i],
        ],
      ],
    );
  }
}

// ── Attachments ──────────────────────────────────────────────────────────────

/// One attachment, as the gallery needs it — deliberately not a model: the
/// admin's ReportMedia and the staff's StaffReportMedia both map onto this.
class DetailMediaItem {
  final String url;
  final bool isVideo;

  /// True when the photo carries a baked-in, live GPS stamp (camera capture).
  final bool isGpsVerified;

  /// AI-generated-image likelihood 0..1 and its lifecycle status. Null where
  /// the console doesn't read the check — the badge then renders nothing.
  final double? aiScore;
  final String? aiStatus;

  const DetailMediaItem({
    required this.url,
    required this.isVideo,
    this.isGpsVerified = false,
    this.aiScore,
    this.aiStatus,
  });
}

/// Square preview of the report's first photo, beside the id/date block.
/// Falls back to the category illustration when there's no image to show.
class DetailHeroThumb extends StatelessWidget {
  final Future<List<DetailMediaItem>> future;
  final String categoryKey;
  const DetailHeroThumb({
    super.key,
    required this.future,
    required this.categoryKey,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<DetailMediaItem>>(
      future: future,
      builder: (context, snap) {
        final media = snap.data ?? const <DetailMediaItem>[];
        final photos = media.where((m) => !m.isVideo);
        final url = photos.isEmpty ? null : photos.first.url;
        final videos = media.where((m) => m.isVideo).toList();

        Widget inner;
        if (snap.connectionState != ConnectionState.done) {
          // Shimmer, not a spinner: the box is already the image's final size,
          // so the placeholder should read as the image arriving rather than as
          // a control sitting in a hole.
          inner = const AdminShimmer(
            child: ColoredBox(color: kSkeletonBase, child: SizedBox.expand()),
          );
        } else if (url == null && videos.isNotEmpty) {
          // Video-only: there IS media here, so the category illustration would
          // read as "nothing attached". Show a play tile that opens the clip.
          inner = GestureDetector(
            onTap: () => showAppDialog(
              context: context,
              barrierColor: Colors.black87,
              builder: (_) => NetworkVideoDialog(url: videos.first.url),
            ),
            child: const Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: Color(0xFF1F2937)),
                Center(
                  child: Icon(
                    Icons.play_circle_fill_rounded,
                    color: Colors.white70,
                    size: 32,
                  ),
                ),
              ],
            ),
          );
        } else if (url == null) {
          inner = ReportCategoryIconBox(categoryKey, size: 88);
        } else {
          inner = GestureDetector(
            onTap: () => showAppDialog(
              context: context,
              barrierColor: Colors.black87,
              builder: (_) => FullscreenImageDialog(url: url),
            ),
            child: SkeletonNetworkImage(
              url: url,
              errorChild: ReportCategoryIconBox(categoryKey, size: 88),
            ),
          );
        }

        return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 88,
            height: 88,
            color: AdminUi.subtle,
            child: inner,
          ),
        );
      },
    );
  }
}

class DetailMediaGallery extends StatelessWidget {
  final Future<List<DetailMediaItem>> future;

  /// How many thumbs to shape the skeleton with. The list row already knows the
  /// media count, so the placeholder grid matches the real one and the pane
  /// doesn't reflow when the signed URLs land.
  final int placeholderCount;
  const DetailMediaGallery({
    super.key,
    required this.future,
    this.placeholderCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<DetailMediaItem>>(
      future: future,
      builder: (context, snap) {
        final media = snap.data ?? const <DetailMediaItem>[];
        final loading = snap.connectionState != ConnectionState.done;
        if (loading && placeholderCount == 0) return const SizedBox.shrink();
        if (!loading && media.isEmpty) {
          return const Text(
            'No attachments.',
            style: TextStyle(fontSize: 13, color: AdminUi.textMuted),
          );
        }
        // Tiles size to the pane rather than a hardcoded 92, so the grid ends
        // flush on a narrow details column and stays tappable on a phone. The
        // skeleton uses the same maths, so nothing reflows when the URLs land.
        return LayoutBuilder(
          builder: (context, c) {
            final tile = attachmentTileSize(c.maxWidth);
            if (loading) {
              // One shimmer over the whole group, so the sweep crosses the grid
              // as a single band rather than each tile animating on its own.
              return AdminShimmer(
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (var i = 0; i < placeholderCount; i++)
                      SkeletonBox(width: tile, height: tile, radius: 10),
                  ],
                ),
              );
            }
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final m in media) DetailMediaThumb(item: m, size: tile),
              ],
            );
          },
        );
      },
    );
  }
}

class DetailMediaThumb extends StatelessWidget {
  final DetailMediaItem item;

  /// Side of the square tile. The gallery sizes this to the pane it's in — see
  /// [attachmentTileSize].
  final double size;
  const DetailMediaThumb({super.key, required this.item, this.size = 92});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (item.isVideo) {
          showAppDialog(
            context: context,
            barrierColor: Colors.black87,
            builder: (_) => NetworkVideoDialog(url: item.url),
          );
        } else {
          showAppDialog(
            context: context,
            barrierColor: Colors.black87,
            builder: (_) => FullscreenImageDialog(url: item.url),
          );
        }
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: size,
          height: size,
          color: AdminUi.subtle,
          child: item.isVideo
              ? Stack(
                  fit: StackFit.expand,
                  children: [
                    const ColoredBox(color: Color(0xFF1F2937)),
                    const Center(
                      child: Icon(
                        Icons.play_circle_fill_rounded,
                        color: Colors.white70,
                        size: 34,
                      ),
                    ),
                    const Positioned(
                      left: 5,
                      bottom: 5,
                      child: Icon(
                        Icons.videocam_rounded,
                        size: 14,
                        color: Colors.white70,
                      ),
                    ),
                    Positioned(
                      top: 5,
                      left: 5,
                      child: MediaSourceBadge(verified: item.isGpsVerified),
                    ),
                    // AI-generated-image flag (top-right, opposite the source
                    // badge). Compact on the small thumb to avoid collision.
                    Positioned(
                      top: 5,
                      right: 5,
                      child: AiDetectionBadge(
                        score: item.aiScore,
                        status: item.aiStatus,
                        compact: true,
                      ),
                    ),
                  ],
                )
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    SkeletonNetworkImage(
                      url: item.url,
                      errorChild: const ColoredBox(
                        color: AdminUi.subtle,
                        child: Icon(
                          Icons.broken_image_rounded,
                          color: AdminUi.textMuted,
                          size: 22,
                        ),
                      ),
                    ),
                    Positioned(
                      right: 5,
                      bottom: 5,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(
                          Icons.zoom_in_rounded,
                          size: 13,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    Positioned(
                      top: 5,
                      left: 5,
                      child: MediaSourceBadge(verified: item.isGpsVerified),
                    ),
                    Positioned(
                      top: 5,
                      right: 5,
                      child: AiDetectionBadge(
                        score: item.aiScore,
                        status: item.aiStatus,
                        compact: true,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

// ── Viewers ──────────────────────────────────────────────────────────────────

class FullscreenImageDialog extends StatelessWidget {
  final String url;
  const FullscreenImageDialog({super.key, required this.url});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: Stack(
        children: [
          Center(
            child: InteractiveViewer(
              // Cached like the thumbs: the full-size photo is the console's
              // heaviest fetch, and reopening the same one shouldn't pay for it
              // twice. Shares the thumbnail's cache entry — same signed url.
              child: CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.contain,
                placeholder: (_, _) => const SizedBox(
                  width: 56,
                  height: 56,
                  child: Center(
                    child: CircularProgressIndicator(color: Colors.white54),
                  ),
                ),
                errorWidget: (_, _, _) => const Icon(
                  Icons.broken_image_rounded,
                  color: Colors.white54,
                  size: 40,
                ),
              ),
            ),
          ),
          Positioned(
            top: 40,
            right: 16,
            child: _ViewerCloseButton(onTap: () => Navigator.pop(context)),
          ),
        ],
      ),
    );
  }
}

class _ViewerCloseButton extends StatelessWidget {
  final VoidCallback onTap;
  const _ViewerCloseButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.close_rounded, color: Colors.white),
      ),
    );
  }
}

class NetworkVideoDialog extends StatefulWidget {
  final String url;
  const NetworkVideoDialog({super.key, required this.url});

  @override
  State<NetworkVideoDialog> createState() => _NetworkVideoDialogState();
}

class _NetworkVideoDialogState extends State<NetworkVideoDialog> {
  late VideoPlayerController _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _controller
        .initialize()
        .then((_) {
          if (!mounted) return;
          setState(() => _ready = true);
          _controller.play();
        })
        .catchError((Object e) {
          debugPrint('Video init error: $e');
          return null;
        });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: Stack(
        children: [
          Center(
            child: _ready
                ? AspectRatio(
                    aspectRatio: _controller.value.aspectRatio,
                    child: VideoPlayer(_controller),
                  )
                : const CircularProgressIndicator(color: Colors.white),
          ),
          if (_ready)
            Center(
              child: GestureDetector(
                onTap: () => setState(() {
                  _controller.value.isPlaying
                      ? _controller.pause()
                      : _controller.play();
                }),
                child: Container(
                  color: Colors.transparent,
                  width: double.infinity,
                  height: double.infinity,
                ),
              ),
            ),
          if (_ready)
            Positioned(
              bottom: 60,
              left: 16,
              right: 16,
              child: VideoProgressIndicator(
                _controller,
                allowScrubbing: true,
                colors: const VideoProgressColors(
                  playedColor: Colors.white,
                  bufferedColor: Colors.white38,
                  backgroundColor: Colors.white24,
                ),
              ),
            ),
          Positioned(
            top: 40,
            right: 16,
            child: _ViewerCloseButton(onTap: () => Navigator.pop(context)),
          ),
        ],
      ),
    );
  }
}
