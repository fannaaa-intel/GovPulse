import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_colors.dart';

/// A two-way internal work-log thread on a single report, shared by the admin
/// console and the staff/external console. Staff/external post progress notes;
/// the admin reads them and can post back (instructions / questions). The
/// citizen NEVER sees these — access is gated by RLS on `report_notes`
/// (see supabase/legacy/report_triage_gate.sql).
///
/// The widget talks to Supabase directly: both admins (role 1) and staff
/// (role 2) are authenticated, and the table's policies decide what each can
/// read/insert, so no per-caller wiring is needed beyond the author identity.
class ReportWorkLog extends StatefulWidget {
  final String reportId;

  /// 'admin' or 'staff' — stored on each note and used to style the bubble.
  final String authorRole;

  /// Display label saved with the note (e.g. "LGU Admin", "Sanitation Office").
  final String authorName;

  /// The report is closed, so the thread becomes a record rather than a
  /// conversation.
  ///
  /// ⚠ This is a judgement call and it differs from the progress-updates
  /// composer, which locks unconditionally. That one is CITIZEN-FACING: a
  /// progress note on finished work is either a mistake or something nobody
  /// will read. This thread is the PRIVATE admin↔staff channel, and there are
  /// real reasons to write in it after closure — an audit query, a correction,
  /// a note for whoever reopens the report later.
  ///
  /// So the widget can be locked, but the callers decide: the admin console
  /// leaves it open (oversight continues after closure), the staff console
  /// locks it (the office's work is done and they have no standing to keep
  /// filing against it).
  final bool locked;

  const ReportWorkLog({
    super.key,
    required this.reportId,
    required this.authorRole,
    required this.authorName,
    this.locked = false,
  });

  @override
  State<ReportWorkLog> createState() => _ReportWorkLogState();
}

/// The composer's resting height — one line of input, and the send button.
///
/// Derived from the field's own metrics rather than picked, so the two cannot
/// drift apart again if the padding or type size is edited:
///
///   content padding   10 + 10  = 20
///   one line @ 13.5sp × 1.2 lh ≈ 16.2 → 16 (Material rounds the line box)
///   border            1 + 1    =  2
///                              = 38 … measured 40 with the dense field's own
///                                floor, which is what the button matches.
///
/// Measured, not assumed: composer_alignment_test pins it against a real
/// TextField so a Flutter change that moves the number fails the test rather
/// than silently re-introducing the misalignment.
const double _kComposerFieldHeight = 40;

class _WorkNote {
  final String id;
  final String authorRole;
  final String authorName;
  final String body;
  final DateTime? createdAt;
  const _WorkNote({
    required this.id,
    required this.authorRole,
    required this.authorName,
    required this.body,
    required this.createdAt,
  });
}

class _ReportWorkLogState extends State<ReportWorkLog> {
  final _ctrl = TextEditingController();
  final _supabase = Supabase.instance.client;

  List<_WorkNote> _notes = const [];
  bool _loading = true;
  bool _sending = false;
  bool _unavailable = false; // migration not applied yet
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _load();
    _subscribe();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    if (_channel != null) _supabase.removeChannel(_channel!);
    super.dispose();
  }

  /// Live-append notes the OTHER side posts (RLS still scopes what arrives).
  void _subscribe() {
    _channel = _supabase
        .channel('report_notes:${widget.reportId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'report_notes',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'report_id',
            value: widget.reportId,
          ),
          callback: (payload) {
            final row = payload.newRecord;
            final id = row['id']?.toString();
            if (id == null) return;
            if (_notes.any((n) => n.id == id)) return; // dedupe our own echo
            if (!mounted) return;
            setState(() {
              _notes = [
                ..._notes,
                _WorkNote(
                  id: id,
                  authorRole: (row['author_role'] as String?) ?? 'staff',
                  authorName: (row['author_name'] as String?) ?? 'Staff',
                  body: (row['body'] as String?) ?? '',
                  createdAt:
                      DateTime.tryParse(row['created_at'].toString())?.toLocal(),
                ),
              ]..sort((a, b) => (a.createdAt ?? DateTime(0))
                  .compareTo(b.createdAt ?? DateTime(0)));
            });
          },
        )
        .subscribe();
  }

  Future<void> _load() async {
    try {
      final rows = await _supabase
          .from('report_notes')
          .select('id, author_role, author_name, body, created_at')
          .eq('report_id', widget.reportId)
          .order('created_at', ascending: true);
      if (!mounted) return;
      setState(() {
        _notes = List<Map<String, dynamic>>.from(rows)
            .map((r) => _WorkNote(
                  id: r['id'].toString(),
                  authorRole: (r['author_role'] as String?) ?? 'staff',
                  authorName: (r['author_name'] as String?) ?? 'Staff',
                  body: (r['body'] as String?) ?? '',
                  createdAt: DateTime.tryParse(r['created_at'].toString())
                      ?.toLocal(),
                ))
            .toList();
        _loading = false;
      });
    } catch (_) {
      // Table missing → migration not applied. Hide the feature gracefully.
      if (!mounted) return;
      setState(() {
        _unavailable = true;
        _loading = false;
      });
    }
  }

  Future<void> _send() async {
    final body = _ctrl.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final inserted = await _supabase
          .from('report_notes')
          .insert({
            'report_id': widget.reportId,
            'author_id': _supabase.auth.currentUser?.id,
            'author_role': widget.authorRole,
            'author_name': widget.authorName,
            'body': body,
          })
          .select('id, author_role, author_name, body, created_at')
          .single();
      if (!mounted) return;
      setState(() {
        _notes = [
          ..._notes,
          _WorkNote(
            id: inserted['id'].toString(),
            authorRole: (inserted['author_role'] as String?) ?? widget.authorRole,
            authorName: (inserted['author_name'] as String?) ?? widget.authorName,
            body: (inserted['body'] as String?) ?? body,
            createdAt:
                DateTime.tryParse(inserted['created_at'].toString())?.toLocal(),
          ),
        ];
        _ctrl.clear();
        _sending = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not post the note. Try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_unavailable) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else if (_notes.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Text(
              'No notes yet. Post progress updates or instructions here — '
              'the citizen never sees these.',
              style: TextStyle(fontSize: 12.5, color: Color(0xFF8A94A6), height: 1.4),
            ),
          )
        else
          for (final n in _notes) _bubble(n),
        if (!widget.locked) ...[
          const SizedBox(height: 8),
          _composer(),
        ],
      ],
    );
  }

  Widget _bubble(_WorkNote n) {
    final isAdmin = n.authorRole == 'admin';
    final accent = isAdmin ? AppColors.primaryBlue : const Color(0xFF0EA5A4);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isAdmin
                    ? Icons.shield_rounded
                    : Icons.engineering_rounded,
                size: 13,
                color: accent,
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  n.authorName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                _ago(n.createdAt),
                style: const TextStyle(fontSize: 10.5, color: Color(0xFF9CA3AF)),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            n.body,
            style: const TextStyle(
                fontSize: 13, color: Color(0xFF1F2937), height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _composer() {
    // The BUBBLES colour by author — teal for the office, blue for the admin —
    // so a glance at the thread says who wrote what. That distinction does not
    // belong on the composer: the same Send button rendered teal in the staff
    // console and blue in the admin one, which reads as two different controls
    // rather than one control used by two people. Brand blue in both.
    const accent = AppColors.primaryBlue;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: TextField(
            controller: _ctrl,
            minLines: 1,
            maxLines: 4,
            maxLength: 500,
            textInputAction: TextInputAction.newline,
            style: const TextStyle(fontSize: 13.5, color: Color(0xFF1F2937)),
            decoration: InputDecoration(
              isDense: true,
              counterText: '',
              hintText: 'Add a note…',
              hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
              filled: true,
              fillColor: const Color(0xFFF4F6FB),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFCBD3DF)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFCBD3DF)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: accent),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Sized to the field's own resting height rather than to its icon's
        // padding, and NOT nudged with a stray bottom margin.
        //
        // The two controls used to be built from unrelated numbers: the field
        // measured 40px (10+10 padding, a ~16px line at 13.5sp, two 1px
        // borders) while the button came out at 38 (10+10 around an 18px icon)
        // and then a `Padding(bottom: 2)` lifted it further. Under
        // CrossAxisAlignment.end that left the bottoms 2px apart and the
        // centres 1px apart — visible as a send button floating slightly high,
        // and worse as the field grew toward its 4-line maximum.
        //
        // A square of exactly _kComposerFieldHeight keeps the two bottom edges
        // on one line at every line count, and keeps the button a circle-ish
        // square rather than letting icon padding decide its shape.
        SizedBox(
          width: _kComposerFieldHeight,
          height: _kComposerFieldHeight,
          child: Material(
            color: accent,
            borderRadius: BorderRadius.circular(11),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: _sending ? null : _send,
              child: Center(
                child: _sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send_rounded,
                        size: 18, color: Colors.white),
              ),
            ),
          ),
        ),
      ],
    );
  }

  static String _ago(DateTime? t) {
    if (t == null) return '';
    final d = DateTime.now().difference(t);
    if (d.inSeconds < 60) return 'now';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    if (d.inDays < 7) return '${d.inDays}d';
    return '${t.day}/${t.month}/${t.year}';
  }
}
