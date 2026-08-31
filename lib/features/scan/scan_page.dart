import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/citizen_ui.dart';
import '../../core/widgets/media_viewer.dart';
import '../admin/widgets/admin_skeleton.dart';
import '../admin/widgets/report_detail_kit.dart' show NetworkVideoDialog;

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

/// The most photos the agency may attach to one update.
///
/// Enforced in three places on purpose: here (so the picker stops offering),
/// in the Edge Function (so a crafted request is refused), and inside
/// `attach_endorsement_update_media` (so the limit holds even if the function
/// is wrong). A limit only the client enforces is not a limit.
const int _kMaxPhotos = 4;

/// Per-photo ceiling, matching the Edge Function's MAX_BYTES.
///
/// The picker already re-encodes at quality 82 and caps the long edge, so a
/// photo arriving above this is not a phone snapshot. Checked client-side as
/// well so the officer is told before spending their data allowance on an
/// upload the server will refuse.
const int _kMaxPhotoBytes = 8 * 1024 * 1024;

/// What the bucket will accept. An allowlist, not a blocklist: `resolution-media`
/// is PUBLIC and serves whatever content type it is handed, so an SVG or HTML
/// file uploaded here would be a stored-XSS payload on the project's own
/// storage origin. Mirrored in the Edge Function, which has the last word.
const Map<String, String> _kAllowedPhotoTypes = {
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'webp': 'image/webp',
  'heic': 'image/heic',
  'heif': 'image/heif',
};

/// A photo picked but not yet uploaded.
///
/// Held as bytes rather than as an [XFile] path: this page is a web build
/// reached from a QR code, where an XFile is a blob with no file system behind
/// it, and the bytes are what the Edge Function needs base64'd regardless.
class _StagedPhoto {
  final String name;
  final String mime;
  final Uint8List bytes;
  const _StagedPhoto({
    required this.name,
    required this.mime,
    required this.bytes,
  });
}

/// Lifecycle the agency drives. Mirrors `report_endorsements.state`.
///
/// `withdrawn` is terminal and NOT reachable from this page — the LGU sets it
/// by taking the report back (migration 20260829000000), which rotates the
/// token so a withdrawn endorsement's QR resolves to nothing. It is modelled
/// anyway because a page already open when the withdrawal happens will see it
/// on its next refresh, and must say so rather than offering a button that
/// cannot work.
enum _State { endorsed, received, completed, withdrawn }

_State _stateFrom(String? s) => switch (s) {
  'received' => _State.received,
  'completed' => _State.completed,
  'withdrawn' => _State.withdrawn,
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

  /// The progress-update composer, and the PIN it needs. A SEPARATE PIN field
  /// from [_pin]: the two forms sit on the page at once and share no state, so
  /// typing a PIN to post an update must not half-fill the confirm-receipt box
  /// (or, worse, submit the wrong one).
  final _updateBody = TextEditingController();
  final _updatePin = TextEditingController();
  bool _postingUpdate = false;
  String? _updateError;
  bool _updatePosted = false;

  /// Photos staged for the progress update, held as BYTES rather than as XFile
  /// paths. This page is a web build reached from a QR code; there is no file
  /// system behind an XFile here, and the bytes are what has to be base64'd for
  /// the Edge Function anyway. Reading them at pick time also means a failure
  /// surfaces while the officer is still looking at the picker.
  final List<_StagedPhoto> _updatePhotos = [];

  /// The completion step's own note and photos. Separate from the progress
  /// composer's for the same reason the two PIN fields are separate: both forms
  /// can be on the page at once, and a half-typed progress note must not become
  /// the permanent record of how the work was finished.
  final _completionBody = TextEditingController();
  final List<_StagedPhoto> _completionPhotos = [];

  /// Whether the completion form is expanded. "Mark Completed" no longer acts
  /// on the first press — it opens this, and a second, explicit press inside it
  /// commits. See [_actionCard].
  bool _completing = false;

  final _picker = ImagePicker();

  Map<String, dynamic>? _data;
  bool _loading = true;
  bool _submitting = false;

  /// The citizen's attachments, once signed.
  ///
  /// Loaded SEPARATELY from the report itself and never blocking it: the
  /// signing round trip is the slowest thing on this page, and an officer
  /// standing in the road should not wait on photographs to read the address.
  /// A failure here leaves [_mediaFailed] set and the rest of the page intact.
  List<ScanMedia> _media = const [];
  bool _mediaLoading = false;
  bool _mediaFailed = false;

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
    _updateBody.dispose();
    _updatePin.dispose();
    _completionBody.dispose();
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

      // Kicked off after the report is on screen, deliberately unawaited.
      _loadMedia(map);
    } catch (_) {
      // Network or server trouble — distinct from an invalid token, because
      // one is worth retrying and the other never will be.
      setState(() {
        _loading = false;
        _fatal = 'network';
      });
    }
  }

  /// Exchanges the token for short-lived signed urls.
  ///
  /// The paths in [map] are inert on their own — `report-media` is a PRIVATE
  /// bucket with no anon SELECT policy — so they are useless until the
  /// `scan-endorsement-media` Edge Function signs them with the service key. A
  /// SECURITY DEFINER function cannot do this: signed urls are HMAC-signed by
  /// the Storage service, not by the database.
  Future<void> _loadMedia(Map<String, dynamic> map) async {
    final report = (map['report'] as Map?) ?? const {};
    final raw = (report['media'] as List?) ?? const [];
    if (raw.isEmpty) return;

    setState(() {
      _mediaLoading = true;
      _mediaFailed = false;
    });

    try {
      final res = await Supabase.instance.client.functions.invoke(
        'scan-endorsement-media',
        body: {'token': widget.token},
      );
      final out = joinScanMedia(raw, res.data);

      if (!mounted) return;
      setState(() {
        _media = out;
        _mediaLoading = false;
        // Some attachments exist but none could be signed — worth saying,
        // rather than rendering an empty space where evidence should be.
        _mediaFailed = out.isEmpty;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _mediaLoading = false;
        _mediaFailed = true;
      });
    }
  }

  Future<void> _submit() async {
    // Re-entrancy guard, and NOT redundant with the disabled button. There are
    // two paths into this method - the action button and the PIN field's
    // keyboard "done" - and a press landing in the same frame as another gets
    // here before setState has rebuilt anything to disable. Completing an
    // endorsement is irreversible and PIN-gated, so a second call is a wasted
    // attempt against the 5-try lockout at best.
    if (_submitting) return;

    final completing = _state == _State.received;
    final pin = _pin.text.trim();
    final body = _completionBody.text.trim();

    // Checked before the PIN, and mirrored by the RPC, which also checks the
    // note before it compares the hash. A missing note is the officer's
    // omission, not a bad credential, and must not burn one of their five
    // attempts.
    if (completing && body.isEmpty) {
      setState(
        () => _error = 'Describe what was done before marking this completed.',
      );
      return;
    }
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
        params: {
          'p_token': widget.token,
          'p_pin': pin,
          // Sent on both transitions. The RPC ignores it on
          // endorsed → received, where there is nothing to narrate about
          // receiving a letter.
          'p_body': completing ? body : null,
        },
      );
      final map = Map<String, dynamic>.from(res as Map);

      if (map['ok'] == true) {
        // The completion update the RPC wrote in the same transaction as the
        // state change. Photos of the finished work attach to it, which is also
        // what releases the citizen's completion gallery — §11 of
        // 20260829000001 keys that on an APPROVED completion update existing.
        String? photoError;
        final updateId = map['update_id'];
        if (completing && updateId != null) {
          photoError = await _uploadPhotos(
            updateId.toString(),
            pin,
            _completionPhotos,
          );
        }

        _pin.clear();
        _completionBody.clear();
        // Re-read rather than patching state locally: the server owns the
        // lifecycle, and a refetch also picks up the timestamps it just set.
        await _load();
        if (!mounted) return;
        setState(() {
          _completionPhotos.clear();
          _completing = false;
          _submitting = false;
          _justAdvanced = true;
          _error = photoError;
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

  // ── Photos ────────────────────────────────────────────────────────────────

  /// Stages photos into [into], validating each one before it is accepted.
  ///
  /// The validation here is a courtesy, not a control: the Edge Function
  /// re-checks the type and the size, and the bucket never sees a path this
  /// client chose. What it buys is that the officer learns about a too-large or
  /// unsupported file while the picker is still in their hand, instead of after
  /// a slow upload on mobile data.
  Future<void> _pickPhotos(List<_StagedPhoto> into) async {
    final room = _kMaxPhotos - into.length;
    if (room <= 0) return;

    try {
      // Re-encoded on the way in. The originals off a modern phone are 4-8MB
      // each and the officer is on mobile data at the roadside; 1600px at
      // quality 82 is plenty to show a patched road and a fraction of the
      // bytes.
      final picked = await _picker.pickMultiImage(
        imageQuality: 82,
        maxWidth: 1600,
      );
      if (picked.isEmpty || !mounted) return;

      final accepted = <_StagedPhoto>[];
      String? rejection;

      for (final f in picked.take(room)) {
        final ext = f.name.contains('.')
            ? f.name.split('.').last.toLowerCase()
            : '';
        // Trust the extension only as far as the allowlist. `f.mimeType` is
        // browser-supplied and absent often enough that it cannot be the
        // primary check; either way the server decides.
        final mime = _kAllowedPhotoTypes[ext];
        if (mime == null) {
          rejection = 'Only JPG, PNG, WEBP and HEIC photos can be attached.';
          continue;
        }

        final bytes = await f.readAsBytes();
        if (bytes.isEmpty) {
          rejection = 'That file could not be read. Try taking it again.';
          continue;
        }
        if (bytes.length > _kMaxPhotoBytes) {
          rejection = 'Each photo must be under 8 MB.';
          continue;
        }
        accepted.add(
          _StagedPhoto(name: f.name, mime: mime, bytes: bytes),
        );
      }

      if (!mounted) return;
      setState(() {
        into.addAll(accepted);
        // Only complain when nothing landed. A batch where three of four were
        // fine should not read as a failure.
        _updateError = accepted.isEmpty ? rejection : null;
        if (picked.length > room && accepted.isNotEmpty) {
          _updateError = 'Up to $_kMaxPhotos photos can be attached.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _updateError = 'Could not open the photo picker.');
    }
  }

  /// Uploads [photos] against an update that already exists.
  ///
  /// Returns null on success, or a message to show. Deliberately does NOT
  /// fail the whole post: the update row is already in and the words are the
  /// update, so a failed upload downgrades to "posted, photos did not attach"
  /// rather than throwing away what the officer wrote.
  Future<String?> _uploadPhotos(
    String updateId,
    String pin,
    List<_StagedPhoto> photos,
  ) async {
    if (photos.isEmpty) return null;
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'post-endorsement-media',
        body: {
          'token': widget.token,
          'pin': pin,
          'update_id': updateId,
          'files': [
            for (final p in photos)
              {'mime': p.mime, 'data': base64Encode(p.bytes)},
          ],
        },
      );
      final data = res.data;
      if (data is Map && data['ok'] == true) return null;
      if (data is Map) {
        switch (data['error'] as String?) {
          case 'file_too_large':
            return 'The update was posted, but a photo was too large to '
                'attach.';
          case 'unsupported_type':
            return 'The update was posted, but that photo format could not be '
                'attached.';
          case 'too_many_media':
            return 'The update was posted, but only $_kMaxPhotos photos can be '
                'attached.';
          case 'bad_pin':
          case 'locked':
            // The PIN passed a moment ago on the update itself, so this is a
            // race (someone else locking the code) rather than a typo.
            return 'The update was posted, but the photos could not be '
                'attached — the code was locked in the meantime.';
        }
      }
      return 'The update was posted, but the photos could not be attached.';
    } on FunctionException catch (e) {
      // functions.invoke THROWS on a non-2xx rather than handing back the body,
      // so the rate limiter's 429 and the limiter-unavailable 503 only reach
      // this branch. Without it both read as a bare network failure and the
      // officer retries immediately, which is the one thing that makes a rate
      // limit worse.
      if (e.status == 429) {
        return 'The update was posted, but too many photo uploads have been '
            'attempted. Wait a few minutes and add them to a new update.';
      }
      if (e.status == 503) {
        return 'The update was posted, but photo uploads are briefly '
            'unavailable. Try again shortly.';
      }
      return 'The update was posted, but the photos could not be attached.';
    } catch (_) {
      return 'The update was posted, but the photos could not be uploaded. '
          'Check your connection.';
    }
  }

  /// Posts a progress update as the agency.
  ///
  /// Goes to `post_endorsement_update`, which is anon-callable and authorised
  /// by the same bcrypt PIN check and attempt limiter as advancing the state.
  /// The update lands as `pending_approval` — an LGU admin reviews it before
  /// the citizen sees anything — which is also what makes an anonymous write
  /// safe here: the worst a stolen letter achieves is queuing something for a
  /// human to reject.
  Future<void> _postUpdate() async {
    // Same guard as [_submit] - the composer's PIN field also submits from the
    // keyboard, so the button being disabled is not the only thing standing
    // between a double tap and two posted updates.
    if (_postingUpdate) return;

    final body = _updateBody.text.trim();
    final pin = _updatePin.text.trim();

    if (body.isEmpty) {
      setState(() => _updateError = 'Write what has happened before posting.');
      return;
    }
    if (pin.length != 4) {
      setState(() => _updateError = 'Enter your 4-digit PIN to post an update.');
      return;
    }

    setState(() {
      _postingUpdate = true;
      _updateError = null;
      _updatePosted = false;
    });

    try {
      final res = await Supabase.instance.client.rpc(
        'post_endorsement_update',
        params: {
          'p_token': widget.token,
          'p_pin': pin,
          'p_body': body,
          // The scan page only ever posts progress notes. A completion is
          // recorded by advancing the state, which is a different button with
          // different consequences — conflating them would let an agency close
          // a report by writing a sentence.
          'p_kind': 'progress',
        },
      );
      final map = Map<String, dynamic>.from(res as Map);
      if (!mounted) return;

      if (map['ok'] == true) {
        // Photos ride the update, not the other way round: the row has to exist
        // before anything can be attached to it (report_update_media.update_id
        // is NOT NULL). A failed upload therefore leaves a text-only update
        // rather than losing the words, which is the better half of the trade.
        final photoError = await _uploadPhotos(
          map['id'].toString(),
          pin,
          _updatePhotos,
        );
        if (!mounted) return;
        _updateBody.clear();
        _updatePin.clear();
        setState(() {
          _updatePhotos.clear();
          _postingUpdate = false;
          _updatePosted = true;
          _updateError = photoError;
        });
        return;
      }
      setState(() {
        _postingUpdate = false;
        _updateError = _updateMessageFor(map);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _postingUpdate = false;
        _updateError =
            'Could not reach the server. Check your connection and try again.';
      });
    }
  }

  String _updateMessageFor(Map<String, dynamic> map) {
    switch (map['error'] as String?) {
      case 'empty_body':
        return 'Write what has happened before posting.';
      case 'rate_limited':
        return 'That is a lot of updates in one hour. Please try again later.';
      case 'withdrawn':
        return 'The Municipality has taken this report back, so updates can no '
            'longer be posted.';
      default:
        // bad_pin / locked / invalid_token all read the same either way.
        return _messageFor(map);
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
      // The client checks for this first, so reaching it means an older app
      // build called the two-argument RPC — which forwards a null body and is
      // refused here on purpose rather than completing without an account.
      case 'body_required':
        return 'Describe what was done before marking this completed. If this '
            'message persists, reload the page.';
      case 'withdrawn':
        return 'The Municipality has taken this report back, so it can no '
            'longer be updated here.';
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
    if (_loading) return const _ScanSkeleton();
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
              // The tracker hides itself when completed or withdrawn, so its
              // spacing has to travel WITH it — a const SizedBox on either side
              // would leave a 34px hole where it used to be.
              if (_state != _State.completed &&
                  _state != _State.withdrawn) ...[
                const SizedBox(height: 16),
                _tracker(),
              ],
              const SizedBox(height: 18),
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
              const SizedBox(height: 16),
              const Divider(height: 1, color: _line),
              const SizedBox(height: 14),

              // ── Location, on its own ───────────────────────────────────
              // It used to be the second of five identical label/value rows.
              // It is the only one that is not a timestamp, the only one that
              // wraps to two or three lines, and the only one the officer has
              // to ACT on — they are standing in the street trying to find the
              // place. Sharing a 116px label column with four dates made the
              // longest, most important value the most cramped.
              _placeBlock(_location(report)),
              const SizedBox(height: 14),

              // ── The timeline, as a timeline ────────────────────────────
              // Reported / Endorsed / Received / Completed are one sequence,
              // and reading them as a flat list of rows gave no sense of that.
              // Rendered as dated steps they answer "how long has this been
              // sitting with us" at a glance, which is the question an agency
              // officer and an auditor both actually have.
              _timeline(d, report),

              _block('Description as reported', report['description']),
              // Directly under the citizen's words, because the photographs
              // are the same statement in another form - and above the basis
              // for endorsement, which is the LGU's voice rather than theirs.
              _MediaStrip(
                media: _media,
                loading: _mediaLoading,
                failed: _mediaFailed,
              ),
              const SizedBox(height: 4),
              _block('Basis for endorsement', d['reason']),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (_justAdvanced) ...[_advancedBanner(), const SizedBox(height: 16)],
        // ── Why the composer comes FIRST once received ────────────────────
        // "Mark Completed" is irreversible: it closes the report and tells the
        // citizen the work is finished. Posting an update is not. With the
        // action card on top, an officer scrolling in to report progress meets
        // the terminal button first and the reversible one second — the wrong
        // way round for the thing they will do many times versus once.
        //
        // Before receipt there is nothing to report on, so the order only
        // matters in this one state.
        if (_state == _State.received) ...[
          _updateCard(),
          const SizedBox(height: 16),
        ],
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
      _State.withdrawn => (
        'Withdrawn by the LGU',
        const Color(0xFFF3F4F6),
        _muted,
      ),
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
    // Terminal, and not the agency's doing — say who ended it and why the
    // buttons are gone, rather than showing a dead form.
    if (_state == _State.withdrawn) {
      return _shell(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Icon(Icons.undo_rounded, size: 22, color: _muted),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'The Municipality has taken this report back.\nNo further '
                'action is required, and this code no longer works.',
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

    if (_state == _State.completed) {
      // The officer who JUST completed it has the green "Recorded…" banner
      // directly above this, which says the same thing in warmer words. Two
      // green panels stacked, both announcing completion, was the page
      // congratulating itself twice — so this one steps aside for the visit
      // where it is actually news, i.e. a later scan of the same code.
      if (_justAdvanced) return const SizedBox.shrink();

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

    // ── Why completing is TWO presses ──────────────────────────────────────
    // "Mark Completed" closes the report and tells the citizen the work is
    // finished. It used to happen on one press with nothing but a PIN, which
    // left the resident with a status change and no account of what was
    // actually done — and, because §11 of 20260829000001 keys the completion
    // gallery on an approved completion update existing, no photographs either.
    //
    // So the first press opens the form instead of acting. The note it asks for
    // is required (by this page AND by the RPC); photographs are optional,
    // because an office with a flat battery or no camera must still be able to
    // close a report it has genuinely finished.
    if (!confirming && !_completing) {
      return _shell(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Mark as completed',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: _ink,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'When the work on this report is finished, record it here. You '
              'will be asked what was done and can attach photographs of the '
              'completed work.',
              style: TextStyle(fontSize: 13.5, height: 1.5, color: _muted),
            ),
            const SizedBox(height: 18),
            // ── OUTLINED, not filled ──────────────────────────────────────
            // This press only OPENS the form; the commit is a second press
            // inside it. A solid green button here made the page carry two
            // equally loud primaries — a blue "Post update" and a green "Mark
            // Completed" — competing for the same attention, when one is the
            // thing an officer does many times and the other is the thing they
            // do once, irreversibly.
            //
            // Outlining the opener ranks them: the routine action is the only
            // filled button on screen, and the solid green is saved for the
            // press that actually closes the report.
            SizedBox(
              width: double.infinity,
              height: 52,
              child: OutlinedButton.icon(
                onPressed: locked
                    ? null
                    : () => setState(() {
                          _completing = true;
                          _error = null;
                        }),
                icon: const Icon(Icons.task_alt_rounded, size: 19),
                label: const Text('Mark Completed'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _green,
                  disabledForegroundColor: const Color(0xFF9CA3AF),
                  side: BorderSide(
                    color: locked
                        ? _line
                        : _green.withValues(alpha: 0.55),
                    width: 1.5,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(11),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return _shell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            confirming ? 'Confirm receipt' : 'Record the completed work',
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
                : 'Describe what was done and attach photographs if you have '
                      'them. The Municipality reviews this before the resident '
                      'who filed the report sees it.',
            style: const TextStyle(fontSize: 13.5, height: 1.5, color: _muted),
          ),

          // ── The completion account ─────────────────────────────────────
          if (!confirming) ...[
            const SizedBox(height: 16),
            TextField(
              key: const Key('scan-completion-body'),
              controller: _completionBody,
              enabled: !_submitting && !locked,
              minLines: 3,
              maxLines: 5,
              maxLength: 600,
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(fontSize: 14, height: 1.45, color: _ink),
              decoration: InputDecoration(
                hintText: 'e.g. The damaged section was excavated and '
                    'repaved on 30 August. The road is open to traffic.',
                hintStyle: const TextStyle(
                  fontSize: 13.5,
                  height: 1.45,
                  color: Color(0xFF9CA3AF),
                ),
                filled: true,
                fillColor: const Color(0xFFF9FAFB),
                counterStyle: const TextStyle(fontSize: 11, color: _muted),
                contentPadding: const EdgeInsets.all(13),
                border: _fieldBorder(_line),
                enabledBorder: _fieldBorder(_error != null ? _red : _line),
                focusedBorder: _fieldBorder(_error != null ? _red : _blue, 1.6),
                disabledBorder: _fieldBorder(_line),
              ),
            ),
            _photoPicker(
              photos: _completionPhotos,
              enabled: !_submitting && !locked,
              label: 'PHOTOS OF THE COMPLETED WORK (OPTIONAL)',
            ),
            const SizedBox(height: 16),
            const Text(
              'CONFIRM WITH YOUR PIN',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: _muted,
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (confirming) const SizedBox(height: 16),
          TextField(
            key: const Key('scan-confirm-pin'),
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
            _inlineError(_error!),
          ],
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: (_submitting || locked) ? null : _submit,
              style: _buttonStyle(confirming ? _blue : _green),
              child: _submitting
                  ? const _ButtonSpinner()
                  : Text(
                      confirming ? 'Confirm Received' : 'Submit & Complete',
                    ),
            ),
          ),
          // A way back out of a step that closes the report. Nothing has been
          // sent yet at this point, so leaving costs the officer only what they
          // typed — and being unable to leave is what makes a two-step form
          // feel like a trap rather than a confirmation.
          if (!confirming) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: TextButton(
                onPressed: _submitting
                    ? null
                    : () => setState(() {
                          _completing = false;
                          _completionPhotos.clear();
                          _error = null;
                        }),
                style: TextButton.styleFrom(
                  foregroundColor: _muted,
                  textStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: const Text('Not yet — go back'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Progress updates ──────────────────────────────────────────────────────
  //
  // Offered only in the `received` state, and that is a deliberate narrowing.
  // Before receipt the agency has not acknowledged the letter and has nothing
  // to report; after completion the work is done. In between is the whole
  // window where "we are currently excavating the drainage line" is worth
  // saying — and the only window where the LGU can pass it on to the citizen.
  Widget _updateCard() {
    return _shell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Post a progress update',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: _ink,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Tell the Municipality what has happened. They review it before it '
            'reaches the resident who filed the report.',
            style: TextStyle(fontSize: 13.5, height: 1.5, color: _muted),
          ),
          const SizedBox(height: 14),
          TextField(
            key: const Key('scan-update-body'),
            controller: _updateBody,
            enabled: !_postingUpdate,
            minLines: 3,
            maxLines: 5,
            maxLength: 600,
            textCapitalization: TextCapitalization.sentences,
            style: const TextStyle(fontSize: 14, height: 1.45, color: _ink),
            decoration: InputDecoration(
              hintText:
                  'e.g. Crew inspected the site today. Materials are on order '
                  'and patching begins Monday.',
              hintStyle: const TextStyle(
                fontSize: 13.5,
                height: 1.45,
                color: Color(0xFF9CA3AF),
              ),
              filled: true,
              fillColor: const Color(0xFFF9FAFB),
              counterStyle: const TextStyle(fontSize: 11, color: _muted),
              contentPadding: const EdgeInsets.all(13),
              border: _fieldBorder(_line),
              enabledBorder: _fieldBorder(_updateError != null ? _red : _line),
              focusedBorder:
                  _fieldBorder(_updateError != null ? _red : _blue, 1.6),
              disabledBorder: _fieldBorder(_line),
            ),
          ),
          _photoPicker(
            photos: _updatePhotos,
            enabled: !_postingUpdate,
            label: 'PHOTOS (OPTIONAL)',
          ),
          const SizedBox(height: 12),
          const Text(
            'CONFIRM WITH YOUR PIN',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: _muted,
            ),
          ),
          const SizedBox(height: 8),
          // Narrower than the confirm-receipt field and left-aligned, so the
          // two PIN boxes on this page never read as the same control.
          SizedBox(
            width: 150,
            child: TextField(
              key: const Key('scan-update-pin'),
              controller: _updatePin,
              enabled: !_postingUpdate,
              keyboardType:
                  const TextInputType.numberWithOptions(signed: false),
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(4),
              ],
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: 8,
                color: _ink,
              ),
              decoration: InputDecoration(
                hintText: '••••',
                hintStyle: const TextStyle(
                  fontSize: 20,
                  letterSpacing: 8,
                  color: Color(0xFFD1D5DB),
                ),
                filled: true,
                fillColor: const Color(0xFFF9FAFB),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: _fieldBorder(_line),
                enabledBorder: _fieldBorder(_updateError != null ? _red : _line),
                focusedBorder:
                    _fieldBorder(_updateError != null ? _red : _blue, 1.6),
                disabledBorder: _fieldBorder(_line),
              ),
            ),
          ),
          if (_updateError != null) ...[
            const SizedBox(height: 12),
            _inlineError(_updateError!),
          ],
          if (_updatePosted) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: const Color(0xFFA7F3D0)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check_circle_rounded, size: 18, color: _green),
                  SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'Update sent to the Municipality for review.',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.45,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF065F46),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              onPressed: _postingUpdate ? null : _postUpdate,
              style: _buttonStyle(_blue),
              child: _postingUpdate
                  ? const _ButtonSpinner(size: 18)
                  : const Text('Post update'),
            ),
          ),
        ],
      ),
    );
  }

  // ── Photo picker ──────────────────────────────────────────────────────────
  //
  // Shared by the progress composer and the completion form. Both attach to the
  // same table through the same Edge Function; giving them two different
  // controls would be two things to keep in step for no reason.
  //
  // ── RESPONSIVE ──────────────────────────────────────────────────────────
  // The thumbnails are a Wrap, not a Row or a fixed-count GridView. At 320px
  // two fit per line and the rest flow to the next; at 480 all four sit on one.
  // A Row would overflow at the narrow end, and a horizontal scroller would
  // hide staged photos behind a gesture nobody knows to make on a form.
  Widget _photoPicker({
    required List<_StagedPhoto> photos,
    required bool enabled,
    required String label,
  }) {
    final full = photos.length >= _kMaxPhotos;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        Text(
          label,
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            color: _muted,
          ),
        ),
        const SizedBox(height: 8),
        if (photos.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < photos.length; i++)
                _Thumb(
                  photo: photos[i],
                  // Removal stays available while an upload is in flight only
                  // in the sense that the button is disabled — pulling a photo
                  // out from under a request in progress would upload it
                  // anyway and then show it as absent.
                  onRemove: enabled
                      ? () => setState(() => photos.removeAt(i))
                      : null,
                ),
            ],
          ),
          const SizedBox(height: 10),
        ],
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: (!enabled || full) ? null : () => _pickPhotos(photos),
            icon: const Icon(Icons.add_a_photo_outlined, size: 18),
            label: Text(
              full
                  ? 'Maximum $_kMaxPhotos photos'
                  : photos.isEmpty
                      ? 'Add photos'
                      : 'Add another (${photos.length}/$_kMaxPhotos)',
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: _blue,
              disabledForegroundColor: _muted,
              side: const BorderSide(color: _line),
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(11),
              ),
              textStyle: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Shared by both forms, so an error reads identically wherever it appears.
  Widget _inlineError(String message) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, size: 17, color: _red),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 13,
                height: 1.45,
                color: _red,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      );

  // ── The three-step tracker ────────────────────────────────────────────────
  //
  // The status pill says where this endorsement stands; this says what the
  // whole journey is and how much of it is left. The officer holding the letter
  // has never seen this system before and has no other way to learn that
  // confirming receipt is step one of two.
  //
  // Hidden entirely once withdrawn: the journey stopped, and drawing a progress
  // bar through it would imply otherwise.
  Widget _tracker() {
    if (_state == _State.withdrawn) return const SizedBox.shrink();

    // Hidden once completed, too. The tracker answers "where in the process is
    // this", and the dated timeline below answers "when did each step happen" —
    // two useful questions while the work is still moving. Once every step is
    // done the tracker's answer is "at the end", which the COMPLETED pill has
    // already said and the timeline's fourth entry already shows. Three
    // renderings of one fact, stacked, on a phone held outdoors.
    //
    // It stays for endorsed/received because there the tracker shows what has
    // NOT happened yet, which the timeline deliberately omits.
    if (_state == _State.completed) return const SizedBox.shrink();

    const steps = ['Endorsed', 'Received', 'Completed'];
    final reached = switch (_state) {
      _State.endorsed => 0,
      _State.received => 1,
      _State.completed => 2,
      _State.withdrawn => 0,
    };

    // LayoutBuilder + fixed-width labels rather than Expanded text: the
    // connector lines must meet the dots, and a Row of Expanded labels puts
    // the line ends wherever the text happens to wrap.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          if (i > 0)
            Expanded(
              child: Padding(
                // Half the dot's height, so the connector meets its centre.
                padding: const EdgeInsets.only(top: 10, left: 2, right: 2),
                child: Container(
                  height: 2,
                  color: i <= reached
                      ? _green
                      : const Color(0xFFE5E7EB),
                ),
              ),
            ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i <= reached ? _green : Colors.white,
                  border: Border.all(
                    color: i <= reached ? _green : const Color(0xFFD1D5DB),
                    width: 2,
                  ),
                ),
                child: i < reached
                    ? const Icon(Icons.check_rounded,
                        size: 13, color: Colors.white)
                    : i == reached
                        ? const Center(
                            child: SizedBox(
                              width: 7,
                              height: 7,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          )
                        : null,
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: 66,
                child: Text(
                  steps[i],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.25,
                    fontWeight:
                        i == reached ? FontWeight.w800 : FontWeight.w600,
                    color: i <= reached ? _ink : _muted,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
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

  // ── Where it is ───────────────────────────────────────────────────────────
  //
  // Pulled out of the label/value list. It is the only non-timestamp fact on
  // the card, the only one that wraps to several lines, and the only one the
  // officer has to act on — they are standing in the street looking for the
  // place. Sharing a 116px label column with four dates made the longest and
  // most useful value the most cramped one.
  Widget _placeBlock(String value) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _line),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 1),
              child: Icon(Icons.place_outlined, size: 17, color: _blue),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'LOCATION',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: _muted,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.4,
                      fontWeight: FontWeight.w700,
                      color: _ink,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  // ── When things happened ──────────────────────────────────────────────────
  //
  // Reported → Endorsed → Received → Completed is ONE SEQUENCE, and rendering
  // it as four identical label/value rows hid that. Drawn as dated steps down a
  // rail it answers "how long has this been sitting with us" at a glance, which
  // is the question both the agency officer and any later auditor actually
  // have. The steps that have not happened yet are simply absent — a future
  // milestone shown as "—" is noise on a page read on a phone outdoors.
  Widget _timeline(Map<String, dynamic> d, Map<String, dynamic> report) {
    final steps = <(String, dynamic)>[
      ('Reported by resident', report['reported_at']),
      ('Endorsed to ${d['agency']}', d['endorsed_at']),
      if (d['received_at'] != null) ('Receipt confirmed', d['received_at']),
      if (d['completed_at'] != null) ('Work completed', d['completed_at']),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < steps.length; i++)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The rail: a dot per step, joined by a line that stops at the
                // last one.
                //
                // ⚠ The connector must be a SizedBox with an explicit width
                // inside a fixed-width Column, not an `Expanded` child of a
                // bare Column. An Expanded needs its parent to have a bounded
                // main-axis extent to expand INTO; inside IntrinsicHeight the
                // rail Column has no intrinsic height of its own (a dot plus an
                // Expanded is unbounded), so the line collapsed to zero and the
                // dots rendered floating and unconnected. Giving the rail a
                // fixed width and letting the ROW's IntrinsicHeight drive the
                // cross-axis is what makes the connector actually stretch to
                // whatever the label beside it needs.
                SizedBox(
                  width: 9,
                  child: Column(
                    children: [
                      Container(
                        width: 9,
                        height: 9,
                        margin: const EdgeInsets.only(top: 4),
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: _green,
                        ),
                      ),
                      if (i < steps.length - 1)
                        const Expanded(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 3),
                            child: SizedBox(
                              width: 2,
                              child: ColoredBox(color: Color(0xFFA7F3D0)),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      bottom: i < steps.length - 1 ? 13 : 0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          steps[i].$1,
                          style: const TextStyle(
                            fontSize: 13,
                            height: 1.3,
                            fontWeight: FontWeight.w700,
                            color: _ink,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          _stamp(steps[i].$2),
                          style: const TextStyle(
                            fontSize: 12.5,
                            height: 1.3,
                            color: _muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
  /// A quoted passage — the citizen's words, or the LGU's reason for handing
  /// the report on.
  ///
  /// These used to be a 10.5px all-caps label over bare body text, sitting
  /// directly under the detail rows with nothing to separate them. Two blocks
  /// of running prose in the middle of a page of short facts, with no container
  /// and no rule, read as one undifferentiated wall — and the officer skimming
  /// on a phone could not tell where the resident's description stopped and the
  /// municipality's justification began.
  ///
  /// The rule at the left is the lightest thing that says "this is quoted
  /// material, and it belongs to the heading above it".
  Widget _block(String label, dynamic value) {
    final text = (value as String?)?.trim() ?? '';
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: _muted,
            ),
          ),
          const SizedBox(height: 7),
          Container(
            padding: const EdgeInsets.only(left: 11),
            decoration: const BoxDecoration(
              border: Border(
                left: BorderSide(color: Color(0xFFE5E7EB), width: 2.5),
              ),
            ),
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.55,
                color: Color(0xFF374151),
              ),
            ),
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

// ════════════════════════════════════════════════════════════════════════════
//  Small shared pieces
// ════════════════════════════════════════════════════════════════════════════

/// One staged photo, with a remove affordance.
///
/// Renders from MEMORY ([Image.memory]) rather than from a URL: nothing has
/// been uploaded at this point, and the whole purpose of the thumbnail is to
/// let the officer check they photographed the right thing before it is sent.
class _Thumb extends StatelessWidget {
  final _StagedPhoto photo;
  final VoidCallback? onRemove;
  const _Thumb({required this.photo, this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.memory(
            photo.bytes,
            width: 78,
            height: 78,
            fit: BoxFit.cover,
            // A phone can hand back a HEIC the browser cannot decode. The
            // upload would still succeed, so this must degrade to a placeholder
            // rather than to a red error box that reads as a failed attachment.
            errorBuilder: (_, _, _) => Container(
              width: 78,
              height: 78,
              color: const Color(0xFFF3F4F6),
              child: const Icon(
                Icons.image_outlined,
                size: 22,
                color: _muted,
              ),
            ),
          ),
        ),
        Positioned(
          top: 2,
          right: 2,
          child: Material(
            color: Colors.black54,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onRemove,
              child: const Padding(
                padding: EdgeInsets.all(3),
                child: Icon(Icons.close_rounded, size: 14, color: Colors.white),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The in-button spinner. A spinner is right HERE and wrong for the page load:
/// the button has already told the officer what is happening and the layout is
/// settled, so there is nothing to reserve space for — see [_ScanSkeleton] for
/// the case that needed a shape instead.
class _ButtonSpinner extends StatelessWidget {
  final double size;
  const _ButtonSpinner({this.size = 20});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: const CircularProgressIndicator(
          strokeWidth: 2.4,
          color: Colors.white,
        ),
      );
}

// ════════════════════════════════════════════════════════════════════════════
//  Loading
// ════════════════════════════════════════════════════════════════════════════

/// The page's shape, drawn before its content arrives.
///
/// This replaced a centred [CircularProgressIndicator]. The spinner was wrong
/// here for a reason particular to this screen: it is opened by a camera app
/// handing off to a browser, on mobile data, outdoors — a slow first load is
/// the NORMAL case, not the exception. A spinner in the middle of a blank page
/// tells the officer nothing about what is coming, and then the whole layout
/// snaps into existence at once and shifts under their thumb.
///
/// The placeholder mirrors the real card almost element for element — the
/// letterhead, the status pill, the three-step tracker, the detail rows and the
/// action button — so the arriving content lands in the space already reserved
/// for it and nothing jumps.
///
/// ── RESPONSIVE ────────────────────────────────────────────────────────────
/// Everything here is either full-width or a FRACTION of the available width
/// (see [_FracBox]) rather than a fixed pixel count. The page runs from a
/// 320px phone up to the 480px cap its parent ConstrainedBox imposes, and a
/// hard-coded 300px bar that looks right at 480 overflows at 320. The only
/// fixed widths left are ones that are fixed in the real card too — the
/// tracker's 22px dots, the 116px label column.
class _ScanSkeleton extends StatelessWidget {
  const _ScanSkeleton();

  @override
  Widget build(BuildContext context) {
    // ⚠ THE SHIMMER GOES INSIDE EACH CARD, NEVER AROUND THEM.
    //
    // AdminShimmer is a ShaderMask with BlendMode.srcATop, which repaints EVERY
    // non-transparent pixel beneath it in the skeleton colour. Wrapping the
    // whole page — the obvious first shape for this widget — therefore painted
    // the white card backgrounds skeleton-grey too, and the bars inside them
    // vanished into a fill of exactly their own colour. The result was two
    // solid slabs: not a skeleton at all, and indistinguishable from a broken
    // layout. Caught by screenshotting it, not by the analyzer or a test.
    //
    // One consequence worth naming: each card drives its own controller, so the
    // sweeps are technically independent. They mount in the same frame and stay
    // visually in step, and the alternative is not having a skeleton.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Letterhead: three centred lines. Not on a card, so it can be wrapped
        // directly — there is no opaque surface under it to repaint.
        const AdminShimmer(
          child: Column(
            children: [
              Center(child: _FracBox(0.42, 9)),
              SizedBox(height: 7),
              Center(child: _FracBox(0.58, 13)),
              SizedBox(height: 7),
              Center(child: _FracBox(0.36, 9)),
            ],
          ),
        ),
        const SizedBox(height: 16),

        _shell(
          child: AdminShimmer(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Status pill.
                const SkeletonBox(width: 132, height: 24, radius: 999),
                const SizedBox(height: 18),
                _tracker(),
                const SizedBox(height: 20),
                // Category, then the reference/agency line.
                const _FracBox(0.72, 18),
                const SizedBox(height: 9),
                const _FracBox(0.55, 11),
                const SizedBox(height: 20),
                // Stands in for the Divider. A real one would be repainted by
                // the shader anyway, so draw it as a bar and keep the rhythm.
                const SkeletonBox(width: double.infinity, height: 1, radius: 0),
                const SizedBox(height: 18),
                // Three detail rows at the real 116px label column.
                _row(0.46),
                _row(0.68),
                _row(0.38),
                const SizedBox(height: 8),
                // A description block: caption over two lines of prose.
                const _FracBox(0.30, 9),
                const SizedBox(height: 8),
                const SkeletonBox(width: double.infinity, height: 10),
                const SizedBox(height: 6),
                const _FracBox(0.64, 10),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // The action card: heading, two lines of instruction, the PIN field and
        // the button. Sized to the real thing so the button does not jump up the
        // page when the content lands.
        _shell(
          child: const AdminShimmer(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _FracBox(0.40, 15),
                SizedBox(height: 12),
                SkeletonBox(width: double.infinity, height: 10),
                SizedBox(height: 6),
                _FracBox(0.72, 10),
                SizedBox(height: 18),
                SkeletonBox(width: double.infinity, height: 56, radius: 11),
                SizedBox(height: 18),
                SkeletonBox(width: double.infinity, height: 52, radius: 11),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        const AdminShimmer(child: Center(child: _FracBox(0.66, 9))),
        const SizedBox(height: 8),
      ],
    );
  }

  /// The three-step tracker: dots joined by connectors, with a label under each.
  /// Fixed 22px dots and 66px labels because those are fixed in [_tracker] too.
  static Widget _tracker() => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0)
              const Expanded(
                child: Padding(
                  padding: EdgeInsets.only(top: 10, left: 2, right: 2),
                  child: SkeletonBox(
                    width: double.infinity,
                    height: 2,
                    radius: 1,
                  ),
                ),
              ),
            const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SkeletonBox(width: 22, height: 22, radius: 11),
                SizedBox(height: 6),
                SkeletonBox(width: 52, height: 9),
              ],
            ),
          ],
        ],
      );

  /// One label/value row, matching [_row]'s 116px label column so the two
  /// columns line up between the placeholder and the real content.
  static Widget _row(double valueFraction) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: [
            const SizedBox(width: 116, child: _FracBox(0.62, 10)),
            Expanded(child: _FracBox(valueFraction, 10)),
          ],
        ),
      );

  /// Same white card the real page uses, so the placeholder occupies exactly
  /// the surface the content will.
  static Widget _shell({required Widget child}) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _line),
        ),
        child: child,
      );
}

/// A skeleton bar sized to a FRACTION of whatever width it is given.
///
/// [SkeletonBox] takes pixels, which is right inside a fixed-width column and
/// wrong for a page that has to hold together from 320px to 480px: a bar
/// written as 300px reads as "most of the line" on the wide end and overflows
/// on the narrow one. Expressing it as a proportion keeps the rhythm of the
/// placeholder identical at every width.
class _FracBox extends StatelessWidget {
  final double fraction;
  final double height;
  const _FracBox(this.fraction, this.height);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        // Unbounded width (inside a Row without Expanded, say) has no fraction
        // to take — fall back to the height so the shape is still drawn rather
        // than throwing.
        final w = c.maxWidth.isFinite ? c.maxWidth * fraction : height;
        return SkeletonBox(width: w, height: height);
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  The citizen's attachments
// ════════════════════════════════════════════════════════════════════════════

/// One signed attachment on the scanned report.
///
/// Public so scan_page_test can build one directly - see
/// [joinScanMedia] for why the widget path is untestable.
class ScanMedia {
  /// The storage path — stable, and therefore the image cache key. The signed
  /// url carries an expiry in its query string and changes on every load, so
  /// caching by url would re-download every photo on every visit.
  final String path;
  final String url;
  final bool isVideo;

  const ScanMedia({
    required this.path,
    required this.url,
    required this.isVideo,
  });
}

/// The attachment strip: photos open the shared gallery, videos open a player.
///
/// Videos are shown rather than skipped. There is no thumbnail stored for one
/// (report_media has no such column, and the citizen app's local preview is
/// never uploaded), so a video draws a PLAY tile — the same answer the admin
/// console already gives. Skipping them would mean a report whose only evidence
/// is a clip of moving floodwater reaches the agency looking like a report with
/// no evidence at all.
class _MediaStrip extends StatelessWidget {
  final List<ScanMedia> media;
  final bool loading;
  final bool failed;

  const _MediaStrip({
    required this.media,
    required this.loading,
    required this.failed,
  });

  @override
  Widget build(BuildContext context) {
    if (!loading && !failed && media.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        const Text(
          'Attached by the resident',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: _muted,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 8),
        if (loading)
          // A shaped placeholder rather than a spinner, for the same reason the
          // page's own skeleton is shaped: the officer is on mobile data
          // outdoors and the strip should hold its space rather than appear
          // suddenly and push the buttons down under their thumb.
          Row(
            children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                const AdminShimmer(
                  child: SizedBox(
                    width: 84,
                    height: 84,
                    child: ColoredBox(color: Color(0xFFE5E7EB)),
                  ),
                ),
              ],
            ],
          )
        else if (failed)
          const Text(
            'The photographs could not be loaded. Pull to refresh, or ask the '
            'Municipality for a copy.',
            style: TextStyle(fontSize: 12.5, color: _muted, height: 1.4),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < media.length; i++)
                _MediaTile(media: media, index: i),
            ],
          ),
      ],
    );
  }
}

/// One tile: a photo thumbnail, or a play tile for a video.
class _MediaTile extends StatelessWidget {
  final List<ScanMedia> media;
  final int index;

  const _MediaTile({required this.media, required this.index});

  @override
  Widget build(BuildContext context) {
    final m = media[index];
    const size = 84.0;

    return Semantics(
      button: true,
      label: m.isVideo
          ? 'Video attachment ${index + 1}. Opens a player.'
          : 'Photo ${index + 1} of ${media.length}. Opens full screen.',
      child: Material(
        color: const Color(0xFFE5E7EB),
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _open(context),
          child: SizedBox(
            width: size,
            height: size,
            child: m.isVideo ? _videoTile() : _photoTile(m),
          ),
        ),
      ),
    );
  }

  void _open(BuildContext context) {
    if (media[index].isVideo) {
      showDialog<void>(
        context: context,
        barrierColor: Colors.black87,
        builder: (_) => NetworkVideoDialog(url: media[index].url),
      );
      return;
    }
    // Videos are skipped when building the gallery, so the index has to be
    // recomputed against the photos-only list or a tap opens the wrong image.
    final photos = [for (final s in media) if (!s.isVideo) s];
    final start = photos.indexWhere((s) => s.path == media[index].path);
    openMediaViewer(
      context,
      urls: [for (final s in photos) s.url],
      // Signed urls carry an expiry and change on every load; the storage path
      // is what stays stable enough to cache by.
      cacheKeys: [for (final s in photos) s.path],
      initialIndex: start < 0 ? 0 : start,
    );
  }

  Widget _photoTile(ScanMedia m) => Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            m.url,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const Center(
              child: Icon(Icons.broken_image_outlined,
                  size: 18, color: _muted),
            ),
          ),
          const Positioned(
            right: 3,
            bottom: 3,
            child: _TileGlyph(icon: Icons.zoom_out_map_rounded),
          ),
        ],
      );

  /// A video has no frame to show, so the tile says what it is in words as
  /// well as with the play mark — an unlabelled dark square reads as a photo
  /// that failed to load.
  Widget _videoTile() => Container(
        color: const Color(0xFF1F2937),
        alignment: Alignment.center,
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.play_circle_fill_rounded,
                size: 30, color: Colors.white),
            SizedBox(height: 3),
            Text(
              'Video',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ],
        ),
      );
}

class _TileGlyph extends StatelessWidget {
  final IconData icon;
  const _TileGlyph({required this.icon});

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(
          color: Color(0x8A000000),
          shape: BoxShape.circle,
        ),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Icon(icon, size: 11, color: Colors.white),
        ),
      );
}

/// Joins the RPC's attachment list to the Edge Function's signed urls.
///
/// Split out of the widget and made top-level ON PURPOSE: `functions.invoke`
/// decodes its response inside a `YAJsonIsolate`, which does not run under
/// flutter_test's fake async — so a widget test can never observe the result of
/// a real invoke. This is where the logic worth testing lives (the join, the
/// dropping of unsigned objects, the photo/video split), and it is testable
/// directly.
///
/// [rows] is `report.media` from scan_endorsement — `{path, kind}` objects.
/// [response] is the function's body, `{ok, photos: [{path, url}]}`.
///
/// Kinds come from the RPC and urls from the function, joined ON PATH, so a
/// reordered or partial signing response can never pair a url with the wrong
/// attachment. An object that failed to sign is dropped rather than rendered
/// as a broken tile.
@visibleForTesting
List<ScanMedia> joinScanMedia(List<dynamic> rows, dynamic response) {
  final map = response is Map ? Map<String, dynamic>.from(response) : const {};
  final signed = <String, String>{
    for (final p in (map['photos'] as List? ?? const []))
      if (p is Map && p['path'] is String && p['url'] is String)
        p['path'] as String: p['url'] as String,
  };

  final out = <ScanMedia>[];
  for (final m in rows) {
    if (m is! Map) continue;
    final path = m['path'] as String?;
    if (path == null) continue;
    final url = signed[path];
    if (url == null) continue;
    out.add(ScanMedia(
      path: path,
      url: url,
      isVideo: (m['kind'] as String?) == 'video',
    ));
  }
  return out;
}
