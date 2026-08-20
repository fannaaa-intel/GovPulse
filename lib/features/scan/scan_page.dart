import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/citizen_ui.dart';

// ════════════════════════════════════════════════════════════════════════════
//  /scan/<token> — the public endorsement confirmation page
//
//  Opened by an agency officer's phone camera from the QR printed on an
//  endorsement letter. It is the one screen in this app with NO login, and it
//  is deliberately unlike every other screen here:
//
//    * No NetworkWrapper, no app shell, no chat bubble, no navigation. The
//      visitor is not a GovPulse user and has no session; anything that assumes
//      one would break or, worse, prompt them to sign in.
//    * Its own minimal Material theme rather than the admin or citizen styling —
//      this is municipal correspondence, and it should read as an official
//      acknowledgement form, not as a product.
//    * Single column, large touch targets, works at 320px. It is opened on a
//      phone held in one hand, outdoors, essentially always.
//
//  All data comes from two SECURITY DEFINER RPCs that are the only things anon
//  can reach: `scan_endorsement` (read) and `advance_endorsement` (write, PIN
//  gated). The page holds no privileges of its own — it cannot read a report
//  the token does not name, and it cannot change anything without the PIN.
// ════════════════════════════════════════════════════════════════════════════

const Color _ink = Color(0xFF111827);
const Color _muted = Color(0xFF6B7280);
const Color _line = CitizenUi.sharedBorder;
const Color _blue = Color(0xFF1D4ED8);
const Color _green = Color(0xFF15803D);
const Color _red = Color(0xFFB91C1C);
const Color _canvas = Color(0xFFF3F4F6);

/// Lifecycle the agency drives. Mirrors `report_endorsements.state`.
enum _State { endorsed, received, completed }

_State _stateFrom(String? s) => switch (s) {
  'received' => _State.received,
  'completed' => _State.completed,
  _ => _State.endorsed,
};

class ScanPage extends StatefulWidget {
  final String token;
  const ScanPage({super.key, required this.token});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  final _pin = TextEditingController();

  Map<String, dynamic>? _data;
  bool _loading = true;
  bool _submitting = false;

  /// Fatal: the token is bad or the lookup failed. Replaces the whole page.
  String? _fatal;

  /// Recoverable: wrong PIN, locked out, already advanced. Shown inline above
  /// the button with the form still usable.
  String? _error;

  /// Set after a successful transition so the page can congratulate rather than
  /// just silently re-render with a different button.
  bool _justAdvanced = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  _State get _state => _stateFrom(_data?['state'] as String?);

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _fatal = null;
    });
    try {
      final res = await Supabase.instance.client.rpc(
        'scan_endorsement',
        params: {'p_token': widget.token},
      );
      final map = Map<String, dynamic>.from(res as Map);
      if (map['valid'] != true) {
        setState(() {
          _loading = false;
          _fatal = 'invalid';
        });
        return;
      }
      setState(() {
        _data = map;
        _loading = false;
      });
    } catch (_) {
      // Network or server trouble — distinct from an invalid token, because
      // one is worth retrying and the other never will be.
      setState(() {
        _loading = false;
        _fatal = 'network';
      });
    }
  }

  Future<void> _submit() async {
    final pin = _pin.text.trim();
    if (pin.length != 4) {
      setState(() => _error = 'Enter the 4-digit PIN issued to your office.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final res = await Supabase.instance.client.rpc(
        'advance_endorsement',
        params: {'p_token': widget.token, 'p_pin': pin},
      );
      final map = Map<String, dynamic>.from(res as Map);

      if (map['ok'] == true) {
        _pin.clear();
        // Re-read rather than patching state locally: the server owns the
        // lifecycle, and a refetch also picks up the timestamps it just set.
        await _load();
        if (!mounted) return;
        setState(() {
          _submitting = false;
          _justAdvanced = true;
        });
        return;
      }

      setState(() {
        _submitting = false;
        _error = _messageFor(map);
      });
      // 'already_completed' / 'already_advanced' mean this page is stale —
      // someone else scanned it. Refresh so the button matches reality.
      final err = map['error'] as String?;
      if (err == 'already_completed' || err == 'already_advanced') {
        await _load();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error =
            'Could not reach the server. Check your connection and try '
            'again.';
      });
    }
  }

  String _messageFor(Map<String, dynamic> map) {
    switch (map['error'] as String?) {
      case 'bad_pin':
        final left = map['attempts_left'];
        return left is int && left > 0
            ? 'That PIN is not correct. $left attempt'
                  '${left == 1 ? '' : 's'} remaining before this code is '
                  'locked for 15 minutes.'
            : 'That PIN is not correct.';
      case 'locked':
        return 'Too many incorrect attempts. This code is locked for 15 '
            'minutes. Contact the Municipality if you need the PIN resent.';
      case 'already_completed':
        return 'This report has already been marked completed.';
      case 'already_advanced':
        return 'This step was already recorded, possibly on another device.';
      case 'invalid_token':
        return 'This code is no longer valid. The Municipality may have '
            'reissued the endorsement.';
      default:
        return 'That action could not be completed.';
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Its own Theme: this page renders outside the app's normal shell and must
    // not inherit whatever the last screen configured.
    return Theme(
      data: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: _canvas,
        colorScheme: ColorScheme.fromSeed(seedColor: _blue),
      ),
      child: Scaffold(
        backgroundColor: _canvas,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: _content(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _content() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 80),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_fatal != null) return _fatalCard();
    return _card();
  }

  Widget _fatalCard() {
    final invalid = _fatal == 'invalid';
    return _shell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            invalid ? Icons.link_off_rounded : Icons.wifi_off_rounded,
            size: 40,
            color: _red,
          ),
          const SizedBox(height: 14),
          Text(
            invalid ? 'This code is not valid' : 'Could not load this code',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: _ink,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            invalid
                ? 'The endorsement this QR code points to could not be found. '
                      'It may have been reissued, in which case a newer letter '
                      'carries the current code. Please contact the '
                      'Municipality of Aparri.'
                : 'Something went wrong reaching the server. Check your '
                      'connection and try again.',
            style: const TextStyle(fontSize: 14, height: 1.5, color: _muted),
          ),
          if (!invalid) ...[
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _load,
                style: _buttonStyle(_blue),
                child: const Text('Try again'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _card() {
    final d = _data!;
    final report = Map<String, dynamic>.from(d['report'] as Map);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _letterhead(),
        const SizedBox(height: 16),
        _shell(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _statusPill(),
              const SizedBox(height: 16),
              Text(
                report['category'] as String? ?? 'Citizen report',
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                  color: _ink,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Reference ${d['reference']}  ·  Endorsed to ${d['agency']}',
                style: const TextStyle(fontSize: 13, color: _muted),
              ),
              const SizedBox(height: 18),
              const Divider(height: 1, color: _line),
              const SizedBox(height: 16),
              _row('Reported', _stamp(report['reported_at'])),
              _row('Location', _location(report)),
              _row('Endorsed', _stamp(d['endorsed_at'])),
              if (d['received_at'] != null)
                _row('Receipt confirmed', _stamp(d['received_at'])),
              if (d['completed_at'] != null)
                _row('Completed', _stamp(d['completed_at'])),
              const SizedBox(height: 6),
              _block('Description as reported', report['description']),
              _block('Basis for endorsement', d['reason']),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (_justAdvanced) ...[_advancedBanner(), const SizedBox(height: 16)],
        _actionCard(),
        const SizedBox(height: 20),
        const Text(
          'Municipality of Aparri · Province of Cagayan\n'
          'This page records an official acknowledgement.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11.5, height: 1.5, color: _muted),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _letterhead() {
    return Column(
      children: const [
        Text(
          'Republic of the Philippines',
          style: TextStyle(fontSize: 12, color: _muted),
        ),
        SizedBox(height: 2),
        Text(
          'MUNICIPALITY OF APARRI',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            color: _ink,
          ),
        ),
        SizedBox(height: 2),
        Text(
          'Endorsement Confirmation',
          style: TextStyle(fontSize: 12, color: _muted),
        ),
      ],
    );
  }

  Widget _statusPill() {
    final (label, bg, fg) = switch (_state) {
      _State.endorsed => ('Awaiting receipt', const Color(0xFFEFF6FF), _blue),
      _State.received => (
        'Received by agency',
        const Color(0xFFFFF7ED),
        const Color(0xFF9A3412),
      ),
      _State.completed => ('Completed', const Color(0xFFECFDF5), _green),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.7,
          color: fg,
        ),
      ),
    );
  }

  Widget _advancedBanner() {
    final done = _state == _State.completed;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFECFDF5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFA7F3D0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle_rounded, size: 20, color: _green),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              done
                  ? 'Recorded. This report is now marked completed and the '
                        'Municipality has been notified.'
                  : 'Receipt confirmed. Return to this page and enter the same '
                        'PIN once the work is finished to mark it completed.',
              style: const TextStyle(
                fontSize: 13,
                height: 1.45,
                fontWeight: FontWeight.w600,
                color: Color(0xFF065F46),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── The single action ─────────────────────────────────────────────────────

  Widget _actionCard() {
    if (_state == _State.completed) {
      return _shell(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.task_alt_rounded, size: 22, color: _green),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'This report is already completed.\nNo further action is '
                'required.',
                style: TextStyle(
                  fontSize: 14.5,
                  height: 1.5,
                  fontWeight: FontWeight.w700,
                  color: _ink,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final confirming = _state == _State.endorsed;
    final locked = _data?['locked'] == true;

    return _shell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            confirming ? 'Confirm receipt' : 'Mark as completed',
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: _ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            confirming
                ? 'Enter the 4-digit PIN issued to your office by the '
                      'Municipality to acknowledge that this endorsement has '
                      'been received.'
                : 'Enter the same 4-digit PIN to record that the work on this '
                      'report has been completed.',
            style: const TextStyle(fontSize: 13.5, height: 1.5, color: _muted),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _pin,
            enabled: !_submitting && !locked,
            keyboardType: const TextInputType.numberWithOptions(signed: false),
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(4),
            ],
            autofillHints: const [AutofillHints.oneTimeCode],
            textAlign: TextAlign.center,
            onSubmitted: (_) => _submitting ? null : _submit(),
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              letterSpacing: 16,
              color: _ink,
            ),
            decoration: InputDecoration(
              hintText: '••••',
              hintStyle: const TextStyle(
                fontSize: 30,
                letterSpacing: 16,
                color: Color(0xFFD1D5DB),
              ),
              filled: true,
              fillColor: const Color(0xFFF9FAFB),
              contentPadding: const EdgeInsets.symmetric(vertical: 16),
              border: _fieldBorder(_line),
              enabledBorder: _fieldBorder(_error != null ? _red : _line),
              focusedBorder: _fieldBorder(_error != null ? _red : _blue, 1.6),
              disabledBorder: _fieldBorder(_line),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.error_outline_rounded, size: 17, color: _red),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _error!,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: _red,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: (_submitting || locked) ? null : _submit,
              style: _buttonStyle(confirming ? _blue : _green),
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    )
                  : Text(confirming ? 'Confirm Received' : 'Mark Completed'),
            ),
          ),
        ],
      ),
    );
  }

  // ── Small pieces ──────────────────────────────────────────────────────────

  ButtonStyle _buttonStyle(Color bg) => FilledButton.styleFrom(
    backgroundColor: bg,
    disabledBackgroundColor: const Color(0xFFCBD5E1),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
    textStyle: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800),
  );

  OutlineInputBorder _fieldBorder(Color c, [double w = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: BorderSide(color: c, width: w),
      );

  Widget _shell({required Widget child}) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: _line),
    ),
    child: child,
  );

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 116,
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: _muted),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 13.5,
              height: 1.4,
              fontWeight: FontWeight.w600,
              color: _ink,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _block(String label, dynamic value) {
    final text = (value as String?)?.trim() ?? '';
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: _muted,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            text,
            style: const TextStyle(fontSize: 13.5, height: 1.5, color: _ink),
          ),
        ],
      ),
    );
  }

  String _location(Map<String, dynamic> report) {
    final b = (report['barangay'] as String?)?.trim() ?? '';
    final a = (report['address'] as String?)?.trim() ?? '';
    if (a.isNotEmpty && b.isNotEmpty) return '$a, Barangay $b';
    if (a.isNotEmpty) return a;
    if (b.isNotEmpty) return 'Barangay $b';
    return 'Not specified';
  }

  String _stamp(dynamic v) {
    final d = DateTime.tryParse(v?.toString() ?? '')?.toLocal();
    return d == null ? '—' : DateFormat('d MMM yyyy, h:mm a').format(d);
  }
}
