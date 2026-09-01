import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/auth_ready.dart';
import '../../../core/theme/citizen_ui.dart';

// ════════════════════════════════════════════════════════════════════════════
//  One report, as a row in My Reports.
//
//  Lifted verbatim out of `my_reports_screen.dart`, where it lived as the
//  private State methods _buildReportTile / _buildStatusBadge plus three
//  helpers (_categoryImagePath / _statusConfig / _formatDate). Nothing about
//  the rendering changed in the move: the widget tree, every `w * .0xx`
//  dimension and every colour are exactly as they were.
//
//  [ReportItem], [ReportStatus] and the [ReportUi] scale came along because the
//  card cannot render without them, and leaving them in the screen would mean
//  this file and the screen importing each other. `my_reports_screen.dart`
//  re-exports the model, so the four places that import it from there
//  (app_router, report_detail_screen, notification_popup, my_submissions) are
//  untouched.
//
//  The card takes an `onTap` rather than pushing '/report_detail' itself. That
//  keeps it free of route knowledge, which is what lets the persistent web
//  shell open a report without a route push while the mobile app keeps doing
//  exactly what it does today.
// ════════════════════════════════════════════════════════════════════════════

// ─── Model ────────────────────────────────────────────────────────────────────

enum ReportStatus { pending, underReview, inProgress, resolved, rejected }

class ReportItem {
  final String id;
  final String category;
  final String categoryKey;
  final String? categoryOther;
  final String? barangay;
  final String? address;
  final String remarks;
  final ReportStatus status;
  final DateTime dateReported;
  final bool isAnonymous;
  final int mediaCount;
  final String fullId;

  /// External entity this report was endorsed to (out-of-LGU scope), e.g.
  /// "DPWH". Null when the report is still handled inside the LGU. Drives the
  /// real "Endorsed to …" timeline step (never guessed from the category).
  final String? endorsedToDepartment;
  final DateTime? endorsedAt;

  /// Reason shown to the citizen when a report was rejected at triage.
  final String? rejectionNote;

  const ReportItem({
    required this.id,
    required this.category,
    required this.categoryKey,
    this.categoryOther,
    this.barangay,
    this.address,
    required this.remarks,
    required this.status,
    required this.dateReported,
    this.isAnonymous = false,
    this.mediaCount = 0,
    required this.fullId,
    this.endorsedToDepartment,
    this.endorsedAt,
    this.rejectionNote,
  });

  factory ReportItem.fromMap(Map<String, dynamic> m) {
    ReportStatus parseStatus(String? s) {
      switch (s) {
        case 'under_review':
          return ReportStatus.underReview;
        case 'in_progress':
          return ReportStatus.inProgress;
        case 'resolved':
          return ReportStatus.resolved;
        case 'rejected':
          return ReportStatus.rejected;
        default:
          return ReportStatus.pending;
      }
    }

    final categoryKey = m['category'] as String? ?? 'others';
    final categoryOther = m['category_other'] as String?;
    final categoryLabel = _categoryLabel(categoryKey, categoryOther);

    return ReportItem(
      id: (m['id'] as String).substring(0, 8).toUpperCase(),
      fullId: m['id'] as String,
      category: categoryLabel,
      categoryKey: categoryKey,
      categoryOther: categoryOther,
      barangay: m['barangay'] as String?,
      address: m['address'] as String?,
      remarks: m['remarks'] as String? ?? '',
      status: parseStatus(m['status'] as String?),
      dateReported: DateTime.parse(m['created_at'] as String).toLocal(),
      isAnonymous: m['is_anonymous'] as bool? ?? false,
      mediaCount: (m['report_media'] as List<dynamic>?)?.length ?? 0,
      endorsedToDepartment:
          (m['endorsed_to_department'] as String?)?.trim().isEmpty ?? true
          ? null
          : m['endorsed_to_department'] as String?,
      endorsedAt: m['endorsed_at'] == null
          ? null
          : DateTime.tryParse(m['endorsed_at'] as String)?.toLocal(),
      rejectionNote: (m['rejection_note'] as String?)?.trim().isEmpty ?? true
          ? null
          : (m['rejection_note'] as String?)?.trim(),
    );
  }

  /// Load one report by its id.
  ///
  /// This is what makes a report detail URL survive a hard refresh: navigating
  /// in-session hands the object straight over, but on reload there is only an
  /// id in the address bar and the object has to be rebuilt from the database.
  ///
  /// Deliberately the SAME select and the same [fromMap] the list uses, so a
  /// report opened from a URL and a report opened from the list are byte-for-byte
  /// the same object — a second mapping path is how the two quietly diverge.
  ///
  /// Returns null when the id does not exist or RLS hides it (someone else's
  /// report, a deleted one, a mistyped URL). Throws only on a genuine
  /// network/database failure, so callers can tell "not found" from "offline".
  static Future<ReportItem?> fetchById(String id) async {
    // On a cold load this can run before the persisted session is restored, and
    // an unauthenticated query is hidden by RLS — which would look like a
    // missing report rather than a race. Costs nothing once signed in.
    await awaitAuthReady();
    final row = await Supabase.instance.client
        .from('reports')
        .select('*, report_media(id)')
        .eq('id', id)
        .maybeSingle();
    if (row == null) return null;
    return ReportItem.fromMap(row);
  }

  static String _categoryLabel(String key, String? other) {
    switch (key) {
      case 'road':
        return 'Road & Infrastructure';
      case 'waste':
        return 'Waste & Garbage';
      case 'drainage':
        return 'Drainage & Flooding';
      case 'streetlight':
        return 'Streetlight Outage';
      case 'environment':
        return 'Environment & Pollution';
      case 'others':
        return other?.isNotEmpty == true ? other! : 'Others';
      default:
        return key;
    }
  }
}

// ─── Type + colour scale ──────────────────────────────────────────────────────

/// The width-relative type scale My Reports is built on. Was the private `_T`
/// in `my_reports_screen.dart`; made public so the card can share it with the
/// screen rather than either duplicating it.
///
/// The four colours are pre-existing literals, moved unchanged. Three of them
/// are the same values as `CitizenUi.textPrimary` / `textMuted` / `textFaint`;
/// pointing them at those tokens is a deliberate follow-up, kept out of this
/// pure-move refactor so the diff stays provably behaviour-free.
class ReportUi {
  ReportUi._();

  static TextStyle heading(double w, {Color? color}) => TextStyle(
    fontSize: w * .048,
    fontWeight: FontWeight.w800,
    height: 1.0,
    color: color,
  );
  static TextStyle title(double w, {Color? color}) => TextStyle(
    fontSize: w * .038,
    fontWeight: FontWeight.w700,
    height: 1.2,
    color: color,
  );
  static TextStyle subtitle(double w, {Color? color}) => TextStyle(
    fontSize: w * .032,
    fontWeight: FontWeight.w700,
    height: 1.3,
    color: color,
  );
  static TextStyle body(double w, {Color? color}) => TextStyle(
    fontSize: w * .030,
    fontWeight: FontWeight.w500,
    height: 1.4,
    color: color,
  );
  static TextStyle caption(double w, {Color? color}) => TextStyle(
    fontSize: w * .028,
    fontWeight: FontWeight.w500,
    height: 1.3,
    color: color,
  );
  static TextStyle label(double w, {Color? color}) => TextStyle(
    fontSize: w * .026,
    fontWeight: FontWeight.w600,
    height: 1.3,
    color: color,
  );
  static TextStyle tiny(double w, {Color? color}) => TextStyle(
    fontSize: w * .022,
    fontWeight: FontWeight.w600,
    height: 1.2,
    color: color,
  );
  static double iconLG(double w) => w * .046;
  static double iconMD(double w) => w * .034;
  static double iconSM(double w) => w * .028;
  static double iconXS(double w) => w * .022;
  static const Color textPrimary = Color(0xFF1F2937);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textTertiary = Color(0xFF9CA3AF);
  static const Color textDisabled = Color(0xFFD1D5DB);
}

// ─── Card ─────────────────────────────────────────────────────────────────────

class ReportCard extends StatelessWidget {
  /// Layout base for spacing (`w * .0xx`). On mobile this is the viewport
  /// width; in the web grid it is the tile width.
  final double w;

  /// Layout base for TYPE and icon sizes. Separate from [w] because the web
  /// grid sizes text off a different measure than its padding — collapsing the
  /// two would resize every label in the grid.
  final double ww;

  final ReportItem report;

  /// Open this report. The card never navigates on its own — see the file note.
  final VoidCallback onTap;

  const ReportCard({
    super.key,
    required this.w,
    required this.ww,
    required this.report,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final iconSize = ReportUi.iconLG(ww);
    final location = [
      report.barangay,
      report.address,
    ].where((s) => s != null && s.isNotEmpty).join(', ');

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.all(w * .04),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: icon + category + status
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: iconSize,
                  height: iconSize,
                  child: Image.asset(
                    _categoryImagePath(report.categoryKey),
                    width: iconSize,
                    height: iconSize,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => Icon(
                      Icons.report_outlined,
                      size: iconSize,
                      color: ReportUi.textTertiary,
                    ),
                  ),
                ),
                SizedBox(width: w * .03),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        report.category,
                        style: ReportUi.subtitle(
                          ww,
                          color: ReportUi.textPrimary,
                        ),
                      ),
                      SizedBox(height: w * .007),
                      // ── The id yields, the Anonymous pill does not ──────
                      // Both were rigid, so on a small phone at a large text
                      // scale — and in the web grid's narrower cell — the pill
                      // was pushed past the edge. The pill is a whole word in a
                      // bordered chip: clipped it reads as a broken control,
                      // and it is the part that carries meaning about who filed
                      // the report. The reference id degrades far more
                      // gracefully, so that is what ellipsizes.
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              'RPT-${report.id}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: ReportUi.label(
                                ww,
                                color: ReportUi.textTertiary,
                              ),
                            ),
                          ),
                          if (report.isAnonymous) ...[
                            SizedBox(width: w * .018),
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: w * .020,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF3F4F6),
                                borderRadius: BorderRadius.circular(w * .04),
                                border: Border.all(
                                  color: CitizenUi.sharedBorder,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.lock_outline_rounded,
                                    size: ReportUi.iconXS(ww),
                                    color: ReportUi.textSecondary,
                                  ),
                                  SizedBox(width: w * .010),
                                  Text(
                                    'Anonymous',
                                    style: ReportUi.tiny(
                                      ww,
                                      color: ReportUi.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                ReportStatusBadge(w: w, ww: ww, status: report.status),
              ],
            ),

            SizedBox(height: w * .025),

            // Row 2: location
            if (location.isNotEmpty)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.location_on_outlined,
                    size: ReportUi.iconMD(ww),
                    color: ReportUi.textTertiary,
                  ),
                  SizedBox(width: w * .015),
                  Expanded(
                    child: Text(
                      '$location, Aparri, Cagayan',
                      style: ReportUi.body(ww, color: ReportUi.textSecondary),
                    ),
                  ),
                ],
              ),

            if (location.isNotEmpty) SizedBox(height: w * .015),

            // Row 3: remarks
            if (report.remarks.isNotEmpty)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.notes_rounded,
                    size: ReportUi.iconMD(ww),
                    color: ReportUi.textTertiary,
                  ),
                  SizedBox(width: w * .015),
                  Expanded(
                    child: Text(
                      report.remarks,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: ReportUi.body(ww, color: ReportUi.textSecondary),
                    ),
                  ),
                ],
              ),

            SizedBox(height: w * .02),

            // Row 4: date + media count
            Row(
              children: [
                Icon(
                  Icons.calendar_today_rounded,
                  size: ReportUi.iconSM(ww),
                  color: ReportUi.textDisabled,
                ),
                SizedBox(width: w * .015),
                Text(
                  _formatDate(report.dateReported),
                  style: ReportUi.label(ww, color: ReportUi.textDisabled),
                ),
                if (report.mediaCount > 0) ...[
                  SizedBox(width: w * .03),
                  Icon(
                    Icons.attach_file_rounded,
                    size: ReportUi.iconSM(ww),
                    color: ReportUi.textDisabled,
                  ),
                  SizedBox(width: w * .008),
                  Text(
                    '${report.mediaCount} file${report.mediaCount > 1 ? 's' : ''}',
                    style: ReportUi.label(ww, color: ReportUi.textDisabled),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The status pill in the card's top-right. Public because the report detail
/// header shows the same pill for the same status.
class ReportStatusBadge extends StatelessWidget {
  final double w;
  final double ww;
  final ReportStatus status;

  const ReportStatusBadge({
    super.key,
    required this.w,
    required this.ww,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    final cfg = _statusConfig(status);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: w * .025, vertical: w * .010),
      decoration: BoxDecoration(
        color: cfg['bg'] as Color,
        borderRadius: BorderRadius.circular(w * .04),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: w * .016,
            height: w * .016,
            decoration: BoxDecoration(
              color: cfg['dot'] as Color,
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: w * .012),
          Text(
            cfg['label'] as String,
            style: ReportUi.tiny(ww, color: cfg['text'] as Color),
          ),
        ],
      ),
    );
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

String _categoryImagePath(String key) {
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
    default:
      return 'assets/images/report/menu.webp';
  }
}

Map<String, dynamic> _statusConfig(ReportStatus status) {
  switch (status) {
    case ReportStatus.pending:
      return {
        'label': 'Pending',
        'bg': const Color(0xFFFFF7ED),
        'text': const Color(0xFFB45309),
        'dot': const Color(0xFFD97706),
      };
    case ReportStatus.underReview:
      return {
        'label': 'Under Review',
        'bg': const Color(0xFFEEF2FF),
        'text': const Color(0xFF3730A3),
        'dot': const Color(0xFF6366F1),
      };
    case ReportStatus.inProgress:
      return {
        'label': 'In Progress',
        'bg': const Color(0xFFEFF6FF),
        'text': const Color(0xFF1D4ED8),
        'dot': const Color(0xFF2563EB),
      };
    case ReportStatus.resolved:
      return {
        'label': 'Resolved',
        'bg': const Color(0xFFECFDF5),
        'text': const Color(0xFF047857),
        'dot': const Color(0xFF059669),
      };
    case ReportStatus.rejected:
      return {
        'label': 'Rejected',
        'bg': const Color(0xFFFEF2F2),
        'text': const Color(0xFFB91C1C),
        'dot': const Color(0xFFEF4444),
      };
  }
}

String _formatDate(DateTime date) {
  final diff = DateTime.now().difference(date);
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays == 1) return 'Yesterday';
  if (diff.inDays < 7) return '${diff.inDays} days ago';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
}
