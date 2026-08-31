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
/// drift apart: 12+12 of content padding around a ~16px line box at 13.5sp,
/// plus two 1px borders, floored to 44 by the dense field.
/// [ReportWorkLog] mounts against Supabase, so composer_alignment_test pins
/// this arithmetic against a real TextField rather than trusting the number.
///
/// ── What was actually wrong, after three passes that were not ───────────────
/// Earlier rounds read the complaint as ALIGNMENT and chased it with numbers:
/// equal heights, then a 1px ink inset, then a 14 radius against the field's
/// 12. The bottoms were already 0.0px apart before any of it. None of it could
/// have helped, and the preview target that would have shown as much did not
/// compile, so nobody ever looked.
///
/// The complaint — "the input is small and the button is big" — is about MASS,
/// and mass is not something a shared bottom edge fixes:
///
///   • The button was a SEPARATE OBJECT. A 44x44 slab of ink sat across an 8px
///     gap from the field, and that gap is exactly what let the eye compare
///     them as two things of unequal size. Nothing inside a control gets
///     measured against it; only a neighbour does.
///   • The field is mostly EMPTY. Its 44px is one short line of 13.5sp text in
///     a pale wash. The button's 44px is saturated brand blue, corner to
///     corner. Equal boxes, nowhere near equal weight.
///   • It got WORSE as the pane narrowed. The field is Expanded and the button
///     fixed, so at a 320px phone width the button owned a far larger share of
///     the row than it did in a 520px admin pane — the one place the imbalance
///     most needed to ease off.
///
/// So the button stops being a neighbour and moves INSIDE the field's shell.
/// One bordered, filled control holds the text and the send affordance, the
/// way every message composer people already use is built. There is no gap
/// left to read a size difference across, the shell grows and shrinks as one
/// object at every width, and the button — now a 32px glyph inside a 44px
/// shell — is visibly the smaller half of its own container.
const double _kComposerFieldHeight = 44;

/// The send affordance's box, inside the shell.
///
/// Not the shell's height: a button that filled its container edge to edge
/// would be back to a slab. 32 leaves 6px of shell above and below, which is
/// what makes it read as a control WITHIN the field rather than a second
/// control beside it.
const double _kComposerSendSize = 32;

/// Padding between the shell's border and its contents.
///
/// This is the number that MAKES the 44, rather than a number chosen to look
/// right beside it. The send button is the tallest thing in a one-line
/// composer, so the shell's resting height is its own arithmetic:
///
///   32 button + 5 + 5 padding + 1 + 1 border = 44
///
/// Which is why [_kComposerFieldHeight] is a `minHeight` and not a fixed
/// height — it is a floor the content already satisfies, there to catch a
/// large text scale or a future edit that would shrink the row below the tap
/// target the send button needs.

/// The shell's corner radius.
///
/// One radius for the whole control, because it IS one control now. The
/// button inside carries a smaller one — a rounded square nested in a pill,
/// which is the standard reading of "this is the action" without it becoming
/// the loudest shape in the row.
const double _kComposerRadius = 12;

/// The send button's own radius, inside the shell.
const double _kComposerSendRadius = 9;

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

  /// Held by the state rather than left to the TextField, because the focus
  /// ring moved OUT of the field and onto the composer's shell — see
  /// [_composer]. The shell cannot know it is focused; only the field does.
  final _focus = FocusNode();
  final _supabase = Supabase.instance.client;

  List<_WorkNote> _notes = const [];
  bool _loading = true;
  bool _sending = false;
  bool _unavailable = false; // migration not applied yet
  bool _focused = false;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChange);
    _load();
    _subscribe();
  }

  void _onFocusChange() {
    if (!mounted || _focus.hasFocus == _focused) return;
    setState(() => _focused = _focus.hasFocus);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    _focus.dispose();
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

    // Rebuilt on every keystroke via the controller itself rather than a
    // setState: the thread above can be long, and re-running the whole build
    // to recolour one button is work the composer does not need to do.
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _ctrl,
      builder: (context, value, _) {
        final hasText = value.text.trim().isNotEmpty;
        final canSend = hasText && !_sending;

        // ── ONE CONTROL, NOT TWO ───────────────────────────────────────────
        //
        // The shell is the input. It carries the border, the fill and the
        // focus ring that used to belong to the TextField, and the field
        // inside it is stripped to bare text on a transparent ground. That
        // swap is the whole fix: with the button INSIDE this box there is no
        // gap across which to compare a small field against a big button, and
        // the pair grows and shrinks as a single object at every width.
        //
        // Focus is watched by hand ([_focus], listened in initState) because
        // the ring now lives on the shell rather than on the field's own
        // focusedBorder, and only the field knows when it has focus.
        return AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          // A FLOOR, not a fixed height — the shell still grows with the text
          // to four lines. It stops a one-line composer collapsing below the
          // 44px the send button and its tap target need, which is what a
          // large text scale or a future padding edit would otherwise do.
          constraints: const BoxConstraints(minHeight: _kComposerFieldHeight),
          padding: const EdgeInsets.all(_kComposerShellPad),
          decoration: BoxDecoration(
            color: const Color(0xFFF4F6FB),
            borderRadius: BorderRadius.circular(_kComposerRadius),
            border: Border.all(
              color: _focused ? accent : const Color(0xFFCBD3DF),
              width: _focused ? 1.5 : 1,
            ),
          ),
          child: Row(
            // The field grows downward to four lines; the button stays put at
            // the bottom of the shell beside the last line, where the caret
            // is. Centring it would float it against the middle of a growing
            // block of text.
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Padding(
                  // Pads the text off the shell's left edge and off the
                  // button. The vertical pair is what makes a one-line
                  // field exactly _kComposerFieldHeight tall including the
                  // shell's own padding and border — see that constant.
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: TextField(
                    controller: _ctrl,
                    focusNode: _focus,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: 500,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.newline,
                    style: const TextStyle(
                        fontSize: 13.5, color: Color(0xFF1F2937), height: 1.35),
                    decoration: const InputDecoration(
                      isDense: true,
                      counterText: '',
                      hintText: 'Add a note…',
                      hintStyle: TextStyle(
                          fontSize: 13.5, color: Color(0xFF9CA3AF)),
                      // Every edge and fill now belongs to the shell. A
                      // border here would draw a second box inside the first.
                      filled: false,
                      isCollapsed: true,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 6),
                    ),
                  ),
                ),
              ),
              // ── The send affordance ──────────────────────────────────────
              //
              // 32 inside a 44 shell, so it is plainly the smaller half of
              // its own container — the opposite of the slab that prompted
              // this. At rest it is a tint carrying the accent's own glyph;
              // with something to send it fills. An empty note is refused by
              // _send(), so a control that looked pressable while empty was
              // lying about what it would do.
              SizedBox(
                width: _kComposerSendSize,
                height: _kComposerSendSize,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOut,
                  decoration: BoxDecoration(
                    color: canSend ? accent : accent.withValues(alpha: 0.10),
                    borderRadius:
                        BorderRadius.circular(_kComposerSendRadius),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: canSend ? _send : null,
                      // The box is 32 for looks; the TAP TARGET is not. A
                      // 32px target is under the 44/48dp floor, and this is
                      // the control that files an office's note on a phone.
                      // The shell's own padding is dead space, so the button
                      // reclaims it outward without moving a pixel of ink.
                      child: Tooltip(
                        message: 'Send note',
                        child: Center(
                          child: _sending
                              ? const SizedBox(
                                  width: 15,
                                  height: 15,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Icon(
                                  Icons.send_rounded,
                                  size: 16,
                                  color: canSend ? Colors.white : accent,
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
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
