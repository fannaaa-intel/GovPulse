import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../../../theme/app_colors.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Above this viewport width a comment thread opens as a centred dialog rather
/// than a bottom sheet. Lives here so the citizen feed, the staff console and
/// the admin console all flip at exactly the same point — they used to
/// disagree, giving staff a bottom sheet on desktop while admin showed a dialog.
///
/// The line is "wider than a phone", not "desktop". At the old 900 a browser
/// window at 887 — an ordinary half-tiled desktop window — still got the phone
/// sheet: a drag handle and an 887px-wide expanse of white with "No comments
/// yet" marooned in the middle of it. 600 puts every tablet, landscape phone
/// and desktop window on the dialog and leaves portrait phones (≤ ~430) on the
/// sheet, which is the split that was actually intended.
const double kCommentsDialogBreakpoint = 600;

/// Whether the comments dialog should split into two columns — the post on the
/// left, the thread and composer on the right — instead of stacking them.
///
/// True for viewports that are WIDE BUT SHORT, which in practice means a
/// landscape phone (844x390) and the occasional squashed desktop window. Stacked,
/// those have ~230px left for the post AND the thread once the header and
/// composer take their cut, so you scroll past the post to reach a single
/// comment. Splitting spends the axis landscape actually has.
///
/// Tall viewports stay stacked whatever their width: a 1280x800 desktop has
/// room for the post above the thread, and that reads better than two narrow
/// columns. Same rule on citizen, staff and admin.
bool commentsUseSplitLayout(Size size) =>
    size.width >= 720 && size.height < 560;

/// Dialog width cap.
///
/// On the WEB these are Facebook's post-dialog proportions: a 700-wide stacked
/// column — the width a photo, its caption and a comment thread are actually
/// laid out at over there — and 1000 when the panel splits into two columns and
/// has to fit a post beside a thread. The old 560 came from reading-width
/// prose, and on a desktop browser it left the modal looking like a phone sheet
/// dropped into the middle of the page.
///
/// Native keeps 560/900 untouched: `kIsWeb` is a compile-time false in the app,
/// so a tablet build compiles to exactly the expression that was here before.
double commentsDialogMaxWidth(Size size) {
  if (commentsUseSplitLayout(size)) return kIsWeb ? 1000 : 900;
  return kIsWeb ? 700 : 560;
}

/// Gap left between the dialog and the edge of the viewport, vertically.
///
/// Short viewports claw the inset back: on a 390dp-tall landscape phone, 24 top
/// and bottom is an eighth of the screen. On the web the gap is Facebook's —
/// the dialog is meant to read as the page's foreground, not as a card floating
/// in it, so it stops just short of the window edge.
double commentsDialogVerticalInset(Size size) {
  if (size.height < 560) return 10;
  return kIsWeb ? 28 : 24;
}

/// Dialog height cap, always clamped to the viewport.
///
/// A fixed 720 inside a 24px inset needs a 768px-tall display just to draw, and
/// clipped the composer off the bottom of the 1366x768 laptops these consoles
/// run on — hence the clamp. The WEB cap is 940 rather than 720 so a normal
/// browser window fills the way Facebook's does (~93% of the viewport) instead
/// of leaving a band of feed showing above and below; on a very tall monitor
/// 940 still stops the thread from stretching past a readable height.
double commentsDialogMaxHeight(Size size) {
  final available = size.height - commentsDialogVerticalInset(size) * 2;
  final cap = kIsWeb ? 940.0 : 720.0;
  return available < cap ? available : cap;
}

/// The full constraint pair for a comments dialog, so the citizen feed, the
/// staff console and the admin console cannot drift apart on size the way they
/// once did on presentation. Pair it with [commentsDialogVerticalInset] for the
/// Dialog's own `insetPadding`.
BoxConstraints commentsDialogConstraints(Size size) {
  final cap = commentsDialogMaxWidth(size);
  final available = size.width - kCommentsDialogHorizontalInset * 2;
  return BoxConstraints(
    maxWidth: available < cap ? available : cap,
    maxHeight: commentsDialogMaxHeight(size),
  );
}

/// Horizontal breathing room either side of the dialog. Only binds below
/// ~750px wide, where the dialog gives up its cap and tracks the window.
const double kCommentsDialogHorizontalInset = 24;

/// Small grey pill at the top of every bottom sheet.
Widget dragHandle(double width) => Container(
  margin: EdgeInsets.only(bottom: width * 0.025),
  width: width * 0.12,
  height: width * 0.012,
  decoration: BoxDecoration(
    color: const Color(0xFFD1D5DB),
    borderRadius: BorderRadius.circular(width * 0.006),
  ),
);

String formatTimeAgo(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inSeconds < 60) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m Ago';
  if (diff.inHours < 24) return '${diff.inHours}h Ago';
  if (diff.inDays < 7) return '${diff.inDays}d Ago';
  if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}w Ago';
  if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}mo Ago';
  return '${(diff.inDays / 365).floor()}y Ago';
}

Widget buildImagePlaceholder(double width) => Container(
  color: const Color(0xFFE5E7EB),
  alignment: Alignment.center,
  child: Icon(
    Icons.image_outlined,
    size: width * 0.08,
    color: const Color(0xFF9CA3AF),
  ),
);

/// Circular avatar for comments and replies.
Widget buildAvatar(double size, String? photoUrl, {String? photoPath}) {
  return Container(
    width: size,
    height: size,
    decoration: const BoxDecoration(
      shape: BoxShape.circle,
      color: Color(0xFFE5E7EB),
    ),
    clipBehavior: Clip.antiAlias,
    child: (photoUrl != null && photoUrl.isNotEmpty)
        ? CachedNetworkImage(
            imageUrl: photoUrl,
            cacheKey: photoPath ?? photoUrl,
            fit: BoxFit.cover,
            fadeInDuration: const Duration(milliseconds: 150),
            fadeOutDuration: const Duration(milliseconds: 100),
            placeholder: (context, url) => Container(
              color: const Color(0xFFE5E7EB),
              child: Icon(
                Icons.person_rounded,
                size: size * 0.6,
                color: const Color(0xFF9CA3AF),
              ),
            ),
            errorWidget: (context, url, error) => Icon(
              Icons.person_rounded,
              size: size * 0.6,
              color: const Color(0xFF9CA3AF),
            ),
          )
        : Icon(
            Icons.person_rounded,
            size: size * 0.6,
            color: const Color(0xFF9CA3AF),
          ),
  );
}

/// Post-author avatar (green border, citizen photo or institution fallback).
Widget buildAuthorAvatar(
  double size,
  String? photoUrl, {
  String? photoPath,
  bool blank = false,
  bool ring = true,
}) {
  // Masked citizen (guest view): neutral grey FB-style silhouette, no green ring.
  if (blank) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Color(0xFFE4E6EB),
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.person,
        size: size * 0.7,
        color: const Color(0xFFB0B3B8),
      ),
    );
  }
  if (photoUrl != null && photoUrl.isNotEmpty) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: ring ? Border.all(color: AppColors.green, width: 1.5) : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: CachedNetworkImage(
        imageUrl: photoUrl,
        cacheKey: photoPath ?? photoUrl,

        fit: BoxFit.cover,
        fadeInDuration: const Duration(milliseconds: 150),
        fadeOutDuration: const Duration(milliseconds: 100),
        placeholder: (context, url) => Container(
          color: AppColors.green.withValues(alpha: 0.12),
          child: Icon(
            Icons.account_balance_rounded,
            size: size * 0.5,
            color: AppColors.green,
          ),
        ),
        errorWidget: (context, url, error) => Container(
          color: AppColors.green.withValues(alpha: 0.12),
          child: Icon(
            Icons.account_balance_rounded,
            size: size * 0.5,
            color: AppColors.green,
          ),
        ),
      ),
    );
  }
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: AppColors.green.withValues(alpha: 0.12),
      border: ring ? Border.all(color: AppColors.green, width: 1.5) : null,
    ),
    child: Icon(
      Icons.account_balance_rounded,
      size: size * 0.5,
      color: AppColors.green,
    ),
  );
}
