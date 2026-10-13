// ════════════════════════════════════════════════════════════════════════════
//  Citizen → rate the external agency a report was endorsed to
//
//  Panel revision item 3. Shown on the report owner's detail screen while the
//  report is endorsed to DPWH / DENR / DOH / BFP / PNP. Any stage can be rated:
//  "they never acknowledged it" is feedback the LGU wants recorded.
//
//  Citizens cannot read report_endorsements, so both calls go through
//  SECURITY DEFINER functions (20261013000000_agency_feedback.sql) that take
//  the agency and its state from the server:
//    my_agency_rating(report)          → eligibility + the rating already given
//    rate_agency(report, stars, text)  → save / edit, rate-limited 10 a day
//  Ratings are read by LGU admins only; the agency never sees them.
// ════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/citizen_ui.dart';

/// What my_agency_rating() returned.
class AgencyRatingStatus {
  final bool eligible;
  final String agency;

  /// endorsed | received | completed — the agency's progress right now.
  final String state;
  final int? stars;
  final String? comment;

  const AgencyRatingStatus({
    required this.eligible,
    this.agency = '',
    this.state = 'endorsed',
    this.stars,
    this.comment,
  });

  static const ineligible = AgencyRatingStatus(eligible: false);

  factory AgencyRatingStatus.fromJson(Map<String, dynamic> j) {
    if (j['eligible'] != true) return ineligible;
    final s = j['stars'];
    return AgencyRatingStatus(
      eligible: true,
      agency: (j['agency'] as String?)?.trim() ?? '',
      state: (j['state'] as String?) ?? 'endorsed',
      stars: s is num ? s.toInt() : int.tryParse('${s ?? ''}'),
      comment: (j['comment'] as String?)?.trim(),
    );
  }
}

/// rate_agency()'s answer. [error] is one of the server's codes
/// (rate_limited, withdrawn, not_endorsed, invalid_stars, comment_too_long)
/// or null on success.
class AgencyRatingSaveResult {
  final String? error;
  const AgencyRatingSaveResult.ok() : error = null;
  const AgencyRatingSaveResult.failed(this.error);
  bool get ok => error == null;
}

/// The two server calls, injectable so tests drive the card without Supabase.
class AgencyRatingApi {
  const AgencyRatingApi();

  Future<AgencyRatingStatus> load(String reportId) async {
    try {
      final res = await Supabase.instance.client.rpc(
        'my_agency_rating',
        params: {'p_report': reportId},
      );
      return AgencyRatingStatus.fromJson(Map<String, dynamic>.from(res as Map));
    } on PostgrestException catch (e) {
      // PGRST202: the function is not deployed. The feature does not exist
      // on this database yet, so there is nothing to rate — not an error to
      // put in front of the citizen. Everything else still surfaces.
      if (isFunctionMissing(e)) return AgencyRatingStatus.ineligible;
      rethrow;
    }
  }

  static bool isFunctionMissing(PostgrestException e) => e.code == 'PGRST202';

  Future<AgencyRatingSaveResult> save(
    String reportId,
    int stars,
    String? comment,
  ) async {
    final res = await Supabase.instance.client.rpc(
      'rate_agency',
      params: {'p_report': reportId, 'p_stars': stars, 'p_comment': comment},
    );
    final j = Map<String, dynamic>.from(res as Map);
    return j['ok'] == true
        ? const AgencyRatingSaveResult.ok()
        : AgencyRatingSaveResult.failed('${j['error'] ?? 'unknown'}');
  }
}

const int kAgencyCommentMax = 500;

const List<String> _starWords = ['Poor', 'Fair', 'Okay', 'Good', 'Excellent'];

/// Below this card width the footer stacks: the note on its own line and the
/// buttons full width underneath. Side by side, the note wraps into a narrow
/// column of three or four lines next to the button on a phone.
const double kAgencyCardStackBelow = 440;

class AgencyRatingCard extends StatefulWidget {
  final String reportId;

  /// The page's scale width, so type and spacing match the cards around it.
  final double w;
  final AgencyRatingApi api;

  const AgencyRatingCard({
    super.key,
    required this.reportId,
    required this.w,
    this.api = const AgencyRatingApi(),
  });

  @override
  State<AgencyRatingCard> createState() => _AgencyRatingCardState();
}

class _AgencyRatingCardState extends State<AgencyRatingCard> {
  final _comment = TextEditingController();

  AgencyRatingStatus? _status;
  bool _loadFailed = false;

  int _stars = 0;

  /// A saved rating shows as a compact summary; Edit opens the form again.
  bool _editing = false;

  /// Re-entrancy guard. The button's disabled look only reaches the next
  /// frame; a double tap inside one frame would otherwise save twice and
  /// spend two of the citizen's ten daily saves.
  bool _saving = false;
  String? _error;
  bool _justSaved = false;

  @override
  void initState() {
    super.initState();
    _comment.addListener(_onEdited);
    _load();
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  void _onEdited() {
    if (!mounted) return;
    setState(() => _error = null);
  }

  Future<void> _load() async {
    setState(() => _loadFailed = false);
    try {
      final s = await widget.api.load(widget.reportId);
      if (!mounted) return;
      setState(() {
        _status = s;
        _resetDraft();
        _editing = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadFailed = true);
    }
  }

  void _resetDraft() {
    _stars = _status?.stars ?? 0;
    _comment.text = _status?.comment ?? '';
    _error = null;
  }

  bool get _rated => (_status?.stars ?? 0) > 0;

  bool get _dirty {
    final s = _status;
    if (s == null) return false;
    return _stars != (s.stars ?? 0) ||
        _comment.text.trim() != (s.comment ?? '');
  }

  bool get _canSubmit => _stars > 0 && _dirty && !_saving;

  void _pick(int v) {
    if (_saving) return;
    HapticFeedback.selectionClick();
    setState(() {
      _stars = v;
      _error = null;
    });
  }

  Future<void> _submit() async {
    if (_saving || _stars == 0) return;
    _saving = true;
    setState(() => _error = null);
    final text = _comment.text.trim();
    try {
      final r = await widget.api.save(
        widget.reportId,
        _stars,
        text.isEmpty ? null : text,
      );
      if (!mounted) return;
      if (r.ok) {
        FocusScope.of(context).unfocus();
        setState(() {
          _status = AgencyRatingStatus(
            eligible: true,
            agency: _status!.agency,
            state: _status!.state,
            stars: _stars,
            comment: text.isEmpty ? null : text,
          );
          _editing = false;
          _justSaved = true;
        });
      } else if (r.error == 'withdrawn' || r.error == 'not_endorsed') {
        // The endorsement changed under us; reload shows the truth (usually:
        // nothing to rate any more).
        await _load();
      } else {
        setState(() => _error = _messageFor(r.error));
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              "Couldn't send your rating. Check your connection and try again.",
        );
      }
    } finally {
      _saving = false;
      if (mounted) setState(() {});
    }
  }

  void _startEdit() => setState(() {
    _resetDraft();
    _editing = true;
    _justSaved = false;
  });

  void _cancelEdit() {
    FocusScope.of(context).unfocus();
    setState(() {
      _resetDraft();
      _editing = false;
    });
  }

  static String _messageFor(String? code) => switch (code) {
    'rate_limited' =>
      "You've changed ratings many times today. Please try again tomorrow.",
    'comment_too_long' =>
      'Your comment is too long. Keep it under $kAgencyCommentMax characters.',
    'invalid_stars' => 'Choose from 1 to 5 stars.',
    _ => "Couldn't send your rating. Please try again.",
  };

  String _stateLine(String state, String agency) => switch (state) {
    'completed' => '$agency has marked the work on your report as done.',
    'received' => '$agency has confirmed they received your report.',
    _ =>
      "$agency hasn't confirmed receiving your report yet. You can still "
          'rate how they have responded so far.',
  };

  /// The page scales type with [widget.w]; on a 320px phone that alone would
  /// put body text under 10px. Each size keeps a readable floor.
  double _fs(double k, double floor) {
    final v = widget.w * k;
    return v < floor ? floor : v;
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.w;
    final s = _status;

    if (_loadFailed) return _frame(w, _loadError(w));
    // Loading, or nothing to rate (withdrawn / never endorsed): take no space.
    if (s == null || !s.eligible || s.agency.isEmpty) {
      return const SizedBox.shrink();
    }

    final pad = (w * .04).clamp(14.0, 20.0);
    return _frame(
      w,
      Padding(
        padding: EdgeInsets.all(pad),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(s),
              SizedBox(height: pad * .8),
              if (_rated && !_editing) _summary(s) else _form(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(AgencyRatingStatus s) {
    final icon = _fs(.05, 20);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: icon * 1.8,
          height: icon * 1.8,
          decoration: BoxDecoration(
            color: CitizenUi.accentWash,
            borderRadius: BorderRadius.circular(CitizenUi.controlRadius),
          ),
          child: Icon(
            Icons.account_balance_outlined,
            size: icon,
            color: CitizenUi.accent,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _rated && !_editing
                    ? 'Your rating of ${s.agency}'
                    : 'How did ${s.agency} handle this?',
                style: TextStyle(
                  fontSize: _fs(.036, 15),
                  fontWeight: FontWeight.w700,
                  color: CitizenUi.textPrimary,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                _stateLine(s.state, s.agency),
                style: TextStyle(
                  fontSize: _fs(.029, 12.5),
                  color: CitizenUi.textMuted,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Saved: compact summary ────────────────────────────────────────────────

  Widget _summary(AgencyRatingStatus s) {
    final stars = s.stars ?? 0;
    final comment = s.comment ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
          decoration: BoxDecoration(
            color: CitizenUi.subtle,
            borderRadius: BorderRadius.circular(CitizenUi.controlRadius),
            border: Border.all(color: CitizenUi.sharedBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Semantics(
                      label:
                          'You rated $stars out of 5, ${_starWords[stars - 1]}',
                      child: ExcludeSemantics(
                        child: Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 2,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (var i = 1; i <= 5; i++)
                                  Icon(
                                    i <= stars
                                        ? Icons.star_rounded
                                        : Icons.star_outline_rounded,
                                    size: _fs(.05, 20),
                                    color: i <= stars
                                        ? _kStarGold
                                        : CitizenUi.textFaint,
                                  ),
                              ],
                            ),
                            Text(
                              _starWords[stars - 1],
                              style: TextStyle(
                                fontSize: _fs(.031, 13),
                                fontWeight: FontWeight.w700,
                                color: CitizenUi.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _startEdit,
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Edit'),
                    style: TextButton.styleFrom(
                      foregroundColor: CitizenUi.accent,
                      minimumSize: const Size(44, 44),
                      textStyle: TextStyle(
                        fontSize: _fs(.031, 13),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              if (comment.isNotEmpty) ...[
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Text(
                    '“$comment”',
                    style: TextStyle(
                      fontSize: _fs(.031, 13),
                      height: 1.45,
                      color: CitizenUi.textSecondary,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        _Note(
          text: _justSaved
              ? 'Thank you. Your rating was sent to the LGU.'
              : 'Only LGU administrators see ratings, not the agency.',
          success: _justSaved,
          fontSize: _fs(.027, 11.5),
        ),
      ],
    );
  }

  // ── Not rated yet, or editing ─────────────────────────────────────────────

  Widget _form() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StarRow(
          value: _stars,
          size: _fs(.075, 30),
          onPick: _saving ? null : _pick,
        ),
        const SizedBox(height: 4),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 160),
          child: Text(
            _stars == 0 ? 'Tap a star to rate' : _starWords[_stars - 1],
            key: ValueKey(_stars),
            style: TextStyle(
              fontSize: _fs(.031, 13),
              fontWeight: FontWeight.w700,
              color: _stars == 0
                  ? CitizenUi.textFaint
                  : CitizenUi.textSecondary,
            ),
          ),
        ),
        if (_stars > 0) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _comment,
            enabled: !_saving,
            maxLines: 4,
            minLines: 2,
            maxLength: kAgencyCommentMax,
            textCapitalization: TextCapitalization.sentences,
            scrollPadding: const EdgeInsets.only(bottom: 140),
            style: TextStyle(
              fontSize: _fs(.032, 14),
              color: CitizenUi.textPrimary,
              height: 1.4,
            ),
            decoration: InputDecoration(
              hintText: 'What went well, or what could be better? (optional)',
              hintStyle: TextStyle(
                fontSize: _fs(.031, 13.5),
                color: CitizenUi.textFaint,
              ),
              counterStyle: TextStyle(
                fontSize: _fs(.026, 11),
                color: CitizenUi.textFaint,
              ),
              filled: true,
              fillColor: CitizenUi.subtle,
              contentPadding: const EdgeInsets.all(12),
              border: _border(CitizenUi.sharedBorder),
              enabledBorder: _border(CitizenUi.sharedBorder),
              focusedBorder: _border(CitizenUi.accent),
              disabledBorder: _border(CitizenUi.sharedBorder),
            ),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: _fs(.036, 16),
                color: CitizenUi.danger,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _error!,
                  style: TextStyle(
                    fontSize: _fs(.029, 12.5),
                    color: CitizenUi.danger,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, c) {
            final note = _Note(
              text: 'Only LGU administrators see ratings, not the agency.',
              fontSize: _fs(.027, 11.5),
            );
            final buttons = _buttons(fill: c.maxWidth < kAgencyCardStackBelow);
            if (c.maxWidth < kAgencyCardStackBelow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [note, const SizedBox(height: 10), buttons],
              );
            }
            return Row(
              children: [
                Expanded(child: note),
                const SizedBox(width: 12),
                buttons,
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buttons({required bool fill}) {
    final send = FilledButton(
      onPressed: _canSubmit ? _submit : null,
      style: FilledButton.styleFrom(
        backgroundColor: CitizenUi.accent,
        minimumSize: const Size(0, 46),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CitizenUi.controlRadius),
        ),
      ),
      child: _saving
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Text(
              _rated ? 'Update rating' : 'Send rating',
              style: TextStyle(
                fontSize: _fs(.031, 14),
                fontWeight: FontWeight.w700,
              ),
            ),
    );
    final cancel = _editing
        ? TextButton(
            onPressed: _saving ? null : _cancelEdit,
            style: TextButton.styleFrom(
              foregroundColor: CitizenUi.textMuted,
              minimumSize: const Size(0, 46),
            ),
            child: Text(
              'Cancel',
              style: TextStyle(
                fontSize: _fs(.031, 14),
                fontWeight: FontWeight.w600,
              ),
            ),
          )
        : null;
    return Row(
      mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
      children: [
        if (cancel != null) ...[
          fill ? Expanded(child: cancel) : cancel,
          const SizedBox(width: 8),
        ],
        fill ? Expanded(flex: 2, child: send) : send,
      ],
    );
  }

  OutlineInputBorder _border(Color c) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(CitizenUi.controlRadius),
    borderSide: BorderSide(color: c),
  );

  Widget _loadError(double w) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
    child: Row(
      children: [
        Icon(
          Icons.cloud_off_rounded,
          size: _fs(.042, 18),
          color: CitizenUi.danger,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            "Couldn't load the agency rating.",
            style: TextStyle(
              fontSize: _fs(.03, 13),
              color: CitizenUi.textMuted,
            ),
          ),
        ),
        TextButton(
          onPressed: _load,
          style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
          child: const Text('Retry'),
        ),
      ],
    ),
  );

  Widget _frame(double w, Widget child) => Container(
    width: double.infinity,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular((w * .04).clamp(12.0, 16.0)),
      border: Border.all(color: CitizenUi.sharedBorder),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: child,
  );
}

const Color _kStarGold = Color(0xFFF59E0B);

class _Note extends StatelessWidget {
  final String text;
  final bool success;
  final double fontSize;
  const _Note({
    required this.text,
    required this.fontSize,
    this.success = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = success ? CitizenUi.success : CitizenUi.textFaint;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          success ? Icons.check_circle_rounded : Icons.lock_outline_rounded,
          size: fontSize + 3,
          color: color,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: fontSize,
              height: 1.35,
              color: color,
              fontWeight: success ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }
}

class _StarRow extends StatelessWidget {
  final int value;
  final double size;
  final ValueChanged<int>? onPick;
  const _StarRow({required this.value, required this.size, this.onPick});

  @override
  Widget build(BuildContext context) {
    // Each star is its own ≥44px target; the icon alone is smaller than that
    // on a phone. Scales down (never wraps) if five targets do not fit.
    final target = size < 44 ? 44.0 : size + 8;
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 1; i <= 5; i++)
            Semantics(
              button: true,
              selected: i <= value,
              label: '$i star${i == 1 ? '' : 's'}, ${_starWords[i - 1]}',
              child: InkResponse(
                onTap: onPick == null ? null : () => onPick!(i),
                radius: target / 2,
                child: SizedBox(
                  width: target,
                  height: target,
                  child: Center(
                    child: AnimatedScale(
                      scale: i == value ? 1.18 : 1.0,
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutBack,
                      child: Icon(
                        i <= value
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        size: size,
                        color: i <= value ? _kStarGold : CitizenUi.textFaint,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
