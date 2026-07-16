import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../providers/admin_reports_provider.dart';
import '../widgets/report_status_tracker.dart';
import 'admin_pdf.dart';

// ════════════════════════════════════════════════════════════════════════════
//  One report → print-ready PDF dossier
//
//  Replaces the single-row CSV the detail's "Download Report" used to hand out.
//  A one-line spreadsheet is the wrong artefact for one report: an admin
//  downloads a single report to ATTACH it to something — an endorsement to an
//  office, a reply to a councillor, a case file — and a CSV of one row answers
//  none of the questions that reader will have. This is the whole record: what
//  was reported, by whom, where it went, what was said about it internally, and
//  what is attached to it.
//
//  Uses the shared house style (admin_pdf.dart), so it prints as the same
//  stationery as the analytics findings report.
//
//  IDENTITY: an anonymous report prints as anonymous, full stop. The console
//  can reveal a reporter behind an audited action; a PDF cannot be audited once
//  it leaves the building, so this never carries a name the detail view is
//  hiding. See [_reporterFacts].
// ════════════════════════════════════════════════════════════════════════════

/// Build and save/share the dossier for [report].
///
/// [media] and [notes] are optional — pass them if already loaded, otherwise
/// they're fetched. Both degrade to empty rather than failing the export: a
/// dossier missing its attachment list is worth far more than no dossier.
Future<void> exportReportPdf({
  required AdminReport report,
  required List<ReportMedia> media,
  required List<ReportNote> notes,
  DateTime? now,
}) async {
  final at = now ?? DateTime.now();
  final r = report;

  final doc = pw.Document(
    title: 'GovPulse Report RPT-${r.shortId}',
    author: 'GovPulse Admin Console',
  );

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(36, 40, 36, 40),
      footer: pdfFooter,
      build: (context) => [
        pdfTitleBlock(
          title: 'Citizen Report Dossier',
          chips: [
            (label: 'Report', value: 'RPT-${r.shortId}'),
            (label: 'Status', value: reportStatusLabel(r.status)),
            (
              label: 'Generated',
              value: DateFormat('MMM d, yyyy · h:mm a').format(at),
            ),
          ],
        ),
        pw.SizedBox(height: 20),
        pdfSummaryLine(_summary(r, at)),
        pw.SizedBox(height: 20),
        ..._detailsSection(r),
        pw.SizedBox(height: 22),
        ..._descriptionSection(r),
        pw.SizedBox(height: 22),
        ..._handlingSection(r),
        pw.SizedBox(height: 22),
        ..._timelineSection(r),
        pw.SizedBox(height: 22),
        ..._attachmentsSection(media),
        pw.SizedBox(height: 22),
        ..._workLogSection(notes),
      ],
    ),
  );

  await Printing.sharePdf(
    bytes: await doc.save(),
    filename: 'GovPulse-Report-RPT-${r.shortId}.pdf',
  );
}

/// The whole report in one paragraph, for someone who reads nothing else.
String _summary(AdminReport r, DateTime now) {
  final where = _place(r);
  final filed = r.createdAt == null
      ? 'on an unrecorded date'
      : 'on ${DateFormat('MMMM d, yyyy').format(r.createdAt!)}';
  final who = r.isAnonymous
      ? 'an anonymous reporter'
      : (r.submitterName?.trim().isNotEmpty ?? false)
      ? r.submitterName!.trim()
      : 'a citizen';

  final parts = <String>[
    'A ${r.category.toLowerCase()} report filed by $who $filed'
        '${where == null ? '' : ' at $where'}.',
    'It currently stands as ${reportStatusLabel(r.status).toUpperCase()}'
        '${_owner(r) == null ? '' : ' with ${_owner(r)}'}.',
    if (r.isCorroborated)
      '${r.reporterCount} citizens have reported this same issue.',
    if (r.isOverdue) 'It is past the expected handling time.',
    if (r.isDismissed) 'It has been dismissed and excluded from analytics.',
  ];
  return parts.join(' ');
}

// ══ 1. Report details ═════════════════════════════════════════════════════════

List<pw.Widget> _detailsSection(AdminReport r) {
  final facts = <({String label, String value})>[
    (label: 'Report ID', value: 'RPT-${r.shortId}'),
    (label: 'Category', value: r.category),
    (label: 'Status', value: reportStatusLabel(r.status)),
    (label: 'Date reported', value: _dateOrDash(r.createdAt)),
    (label: 'Time reported', value: _timeOrDash(r.createdAt)),
    (label: 'Age', value: '${r.ageDays} day${r.ageDays == 1 ? '' : 's'}'),
    (label: 'Barangay', value: _orDash(r.barangay)),
    (label: 'Address', value: _orDash(r.address)),
    ..._reporterFacts(r),
    (label: 'Attachments', value: '${r.mediaCount}'),
  ];

  return [pdfH1('1. Report Details'), pdfFactTable(facts)];
}

/// Who filed it — or a plain statement that nobody may know.
///
/// An anonymous report NEVER prints a name here, even though the console can
/// reveal one: on screen that reveal is a deliberate, audited act by one admin,
/// while a PDF is copied and forwarded with no audit trail at all. The
/// promise made to the citizen at submission has to survive the export.
List<({String label, String value})> _reporterFacts(AdminReport r) {
  if (r.isAnonymous) {
    return const [
      (label: 'Reported by', value: 'Anonymous'),
      (
        label: 'Identity',
        value: 'Withheld at the reporter\'s request. Not included in this '
            'document; retrievable only from the admin console, where the '
            'reveal is recorded.',
      ),
    ];
  }
  return [
    (label: 'Reported by', value: _orDash(r.submitterName)),
    (label: 'Reporter role', value: _titleCase(r.submitterRole ?? '')),
  ];
}

// ══ 2. Description ════════════════════════════════════════════════════════════

List<pw.Widget> _descriptionSection(AdminReport r) {
  final text = r.remarks.trim();
  return [
    pdfH1('2. What Was Reported'),
    if (text.isEmpty)
      pdfEmpty('The reporter left no written description.')
    else
      pdfPara(text),
  ];
}

// ══ 3. Handling & routing ═════════════════════════════════════════════════════

List<pw.Widget> _handlingSection(AdminReport r) {
  final out = <pw.Widget>[pdfH1('3. Handling & Routing')];

  final facts = <({String label, String value})>[
    if (r.isAssigned) ...[
      (label: 'Accepted on', value: _stampOrDash(r.assignedAt)),
      (label: 'Accepted by', value: _orDash(r.assignedByName)),
      (label: 'Assigned department', value: _orDash(r.assignedToDepartment)),
    ],
    if (r.isEndorsed) ...[
      (label: 'Endorsed on', value: _stampOrDash(r.endorsedAt)),
      (label: 'Endorsed to', value: _orDash(r.endorsedToDepartment)),
    ],
    if (r.isCorroborated)
      (
        label: 'Confirmations',
        value: '${r.confirmCount} other report'
            '${r.confirmCount == 1 ? '' : 's'} link to this one '
            '(${r.reporterCount} citizens in total).',
      ),
    if (r.isDuplicate)
      (
        label: 'Duplicate of',
        value: 'RPT-${r.duplicateOf!.replaceAll('-', '').substring(0, 8).toUpperCase()} '
            '- this report confirms that one and is not triaged separately.',
      ),
    if (r.status == ReportStatus.rejected)
      (
        label: 'Reason for rejection',
        value: _orDash(r.rejectionNote),
      ),
    if (r.isDismissed) ...[
      (label: 'Dismissed on', value: _stampOrDash(r.dismissedAt)),
      (label: 'Dismissal reason', value: _orDash(r.dismissedReason)),
    ],
  ];

  if (facts.isEmpty) {
    out.add(
      pdfEmpty(
        'This report is still on the triage desk. It has not been accepted, '
        'routed to a department, or endorsed.',
      ),
    );
    return out;
  }

  out.add(pdfFactTable(facts));
  return out;
}

// ══ 4. Timeline ═══════════════════════════════════════════════════════════════

/// Built from [buildReportStages] — the same function that draws the timeline on
/// screen, so the printed lifecycle can't drift from the one the admin read.
List<pw.Widget> _timelineSection(AdminReport r) {
  final stages = buildReportStages(r, r.status, acceptedByName: r.assignedByName);

  return [
    pdfH1('4. Status Timeline'),
    pdfTable(
      const ['#', 'Stage', 'State', 'On record'],
      [
        for (final s in stages)
          [
            '${s.step}',
            s.title,
            _stageState(s.state),
            s.facts.isEmpty
                ? '-'
                : s.facts.map((f) => '${f.label}: ${f.value}').join('\n'),
          ],
      ],
      flex: const {0: 0.4, 1: 1.6, 2: 1.1, 3: 3.2},
    ),
    if (r.status == ReportStatus.rejected) ...[
      pw.SizedBox(height: 8),
      pdfPara(
        'The lifecycle stopped when this report was rejected. Stages after the '
        'point it reached were never entered.',
      ),
    ],
  ];
}

String _stageState(ReportStageState s) => switch (s) {
  ReportStageState.done => 'Completed',
  ReportStageState.current => 'In progress',
  ReportStageState.upcoming => 'Not started',
  ReportStageState.blocked => 'Not reached',
};

// ══ 5. Attachments ════════════════════════════════════════════════════════════

/// The evidence list. Deliberately describes each file rather than embedding it:
/// the media sits in a PRIVATE bucket behind short-lived signed URLs, so pasting
/// those links into a document that outlives them would print dead links, and
/// embedding the images themselves would turn a filed dossier into an
/// uncontrolled copy of evidence.
List<pw.Widget> _attachmentsSection(List<ReportMedia> media) {
  final out = <pw.Widget>[pdfH1('5. Attachments')];

  if (media.isEmpty) {
    out.add(pdfEmpty('No photos or video were attached to this report.'));
    return out;
  }

  out.add(
    pdfTable(
      const ['#', 'Type', 'Captured', 'Authenticity check'],
      [
        for (var i = 0; i < media.length; i++)
          [
            '${i + 1}',
            media[i].isVideo ? 'Video' : 'Photo',
            media[i].isGpsVerified
                ? 'In-app camera, GPS-stamped'
                : 'Chosen from gallery',
            _aiVerdict(media[i]),
          ],
      ],
      flex: const {0: 0.4, 1: 1.0, 2: 2.0, 3: 2.4},
    ),
  );

  final stamped = media.where((m) => m.isGpsVerified).length;
  out.add(
    pdfFindings([
      if (stamped == media.length)
        'Every attachment was taken in-app with a GPS stamp, so the location '
            'and time of capture are corroborated by the file itself.'
      else if (stamped == 0)
        'No attachment was taken in-app. All were chosen from the device '
            'gallery, so neither the place nor the time of capture is '
            'corroborated by the files.'
      else
        '$stamped of ${media.length} attachments were taken in-app with a GPS '
            'stamp; the rest came from the gallery and carry no such proof.',
    ], heading: 'Notes on the evidence'),
  );
  return out;
}

String _aiVerdict(ReportMedia m) {
  final status = (m.aiStatus ?? '').trim().toLowerCase();
  if (status.isEmpty) return 'Not checked';
  final score = m.aiScore;
  final pct = score == null ? '' : ' (${(score * 100).toStringAsFixed(0)}%)';
  return switch (status) {
    'ai' || 'ai_generated' => 'Flagged as likely AI-generated$pct',
    'real' || 'human' => 'No sign of AI generation$pct',
    _ => '$status$pct',
  };
}

// ══ 6. Work log ═══════════════════════════════════════════════════════════════

/// The internal thread. Included because it is the only record of WHY the report
/// was handled the way it was — and the reason an admin prints a dossier is
/// usually to answer exactly that.
List<pw.Widget> _workLogSection(List<ReportNote> notes) {
  final out = <pw.Widget>[pdfH1('6. Internal Work Log')];

  if (notes.isEmpty) {
    out.add(
      pdfEmpty(
        'No internal notes were exchanged about this report.',
      ),
    );
    return out;
  }

  out.add(
    pdfPara(
      'Internal correspondence between the LGU admin and the handling office. '
      'Not visible to the citizen who filed the report.',
    ),
  );
  out.add(pw.SizedBox(height: 8));
  out.add(
    pdfTable(
      const ['When', 'Author', 'Note'],
      [
        for (final n in notes)
          [
            _stampOrDash(n.createdAt),
            '${n.authorName}\n(${_titleCase(n.authorRole)})',
            n.body,
          ],
      ],
      flex: const {0: 1.5, 1: 1.5, 2: 4.0},
    ),
  );
  return out;
}

// ── helpers ──────────────────────────────────────────────────────────────────

String? _place(AdminReport r) {
  final b = r.barangay?.trim() ?? '';
  final a = r.address?.trim() ?? '';
  if (b.isEmpty && a.isEmpty) return null;
  if (b.isEmpty) return a;
  if (a.isEmpty) return b;
  return '$a, $b';
}

String? _owner(AdminReport r) =>
    r.isEndorsed ? r.endorsedToDepartment : r.assignedToDepartment;

String _orDash(String? s) => (s == null || s.trim().isEmpty) ? '-' : s.trim();

String _dateOrDash(DateTime? d) =>
    d == null ? '-' : DateFormat('MMMM d, yyyy').format(d);

String _timeOrDash(DateTime? d) =>
    d == null ? '-' : DateFormat('h:mm a').format(d);

String _stampOrDash(DateTime? d) =>
    d == null ? '-' : DateFormat('MMM d, yyyy · h:mm a').format(d);

String _titleCase(String s) {
  final t = s.trim();
  if (t.isEmpty) return '-';
  return t[0].toUpperCase() + t.substring(1);
}
