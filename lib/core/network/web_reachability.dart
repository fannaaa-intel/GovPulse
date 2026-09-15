import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

/// Whether the browser can actually REACH the backend — as opposed to merely
/// having a network interface, which is all `navigator.onLine` reports.
///
/// ── Why this exists ─────────────────────────────────────────────────────────
/// On web, [NetworkWrapper] decided "online" from `connectivity_plus`, which
/// maps to `navigator.onLine`: true whenever any interface is up. Three common
/// situations therefore read as ONLINE while nothing loads, and in all three the
/// citizen got a spinner and no explanation:
///
///   * a captive portal (hotel, mall, campus) intercepting every request
///   * wifi up but the uplink dead — the router lost its WAN
///   * a connection so weak that requests connect and then never answer
///
/// The last one is already described, from the other end, in
/// [TimeoutHttpClient]'s own doc comment: *"the socket connects, so the app's
/// own reachability probe reports 'online', and then the request simply never
/// answers."* A timeout made those requests FAIL instead of hang, which is what
/// lets this class exist — but nothing connected that failure back to the toast.
///
/// ── Why it does not poll ────────────────────────────────────────────────────
/// A heartbeat would mean a request from every open tab forever, including for
/// the overwhelming majority of users whose connection is fine. This is
/// event-driven instead: it probes only when there is already evidence of
/// trouble, which is either
///
///   1. the browser flipping offline, or
///   2. a real Supabase request failing at the TRANSPORT level — reported by
///      [reportTransportFailure], called from [TimeoutHttpClient].
///
/// Trigger 2 is what catches the captive portal, because a captive portal is
/// precisely the situation in which ordinary requests start failing. The
/// failures ARE the signal; no heartbeat is needed to discover them.
///
/// ── The false-positive guard ────────────────────────────────────────────────
/// A failed request does NOT prove the network is down. A 500, an RLS denial or
/// one malformed query would otherwise raise "no internet" for somebody whose
/// connection is perfect — a worse bug than the one being fixed, because it
/// blames the user's network for the backend's fault. Two rules keep that from
/// happening:
///
///   * only TRANSPORT failures are admissible as a trigger. An HTTP error
///     STATUS is not a trigger — receiving a 500 proves the internet works.
///     [TimeoutHttpClient] enforces this by calling in only from its throw path.
///   * a trigger never decides anything by itself. It only schedules a probe,
///     and the PROBE's result is what flips the state.
class WebReachability {
  WebReachability._();

  static final WebReachability instance = WebReachability._();

  /// The probe endpoint: GoTrue's unauthenticated health check.
  ///
  /// Chosen over a table read because it needs no session and touches no RLS,
  /// so it answers the same way for a signed-out visitor and a signed-in
  /// citizen. Verified live to return 200 with `Access-Control-Allow-Origin`
  /// set, and a ~105-byte body — small enough that probing costs nothing.
  ///
  /// Behind a captive portal this either fails outright or returns the portal's
  /// own HTML, and the status/shape check below rejects both.
  static const String _healthPath = '/auth/v1/health';

  /// Set once from `main()`, which is where the Supabase url and key already
  /// live. Left null in tests and in any tree that never booted Supabase, and
  /// [probe] degrades to "assume reachable" rather than reporting a false
  /// outage when it is not configured.
  String? _baseUrl;
  String? _anonKey;

  void configure({required String supabaseUrl, required String anonKey}) {
    _baseUrl = supabaseUrl;
    _anonKey = anonKey;
  }

  /// Emits `true` when the backend is reachable again and `false` when a probe
  /// has CONFIRMED it is not. Never emits on a mere suspicion.
  Stream<bool> get onChanged => _controller.stream;
  final StreamController<bool> _controller = StreamController<bool>.broadcast();

  /// Last confirmed answer. Null until the first probe resolves.
  bool? get lastResult => _reachable;
  bool? _reachable;

  /// Retry delays in seconds, applied while the backend stays unreachable.
  static const List<int> _backoff = [2, 3, 5, 8, 13, 20];

  Timer? _retry;
  int _attempt = 0;
  bool _probing = false;

  /// An injection seam for the preview target and for tests.
  Future<bool> Function(Uri, Map<String, String>)? debugProbeOverride;

  /// Called by [TimeoutHttpClient] when a Supabase request failed to reach the
  /// server at all — a timeout or a connection error, never an HTTP status.
  ///
  /// Cheap and non-blocking on purpose: this sits on a hot error path, so it
  /// schedules work and returns rather than awaiting anything.
  void reportTransportFailure() {
    if (!kIsWeb) return;
    // Already known to be down and already retrying — nothing to add.
    if (_reachable == false) return;
    _probeSoon();
  }

  /// Called when the browser's own offline/online signal changes.
  ///
  /// `offline` is trusted immediately in the negative direction — if the
  /// browser says there is no interface at all, there is no interface. Only the
  /// POSITIVE direction needs confirming, which is the whole point of this
  /// class.
  void reportBrowserSignal({required bool online}) {
    if (!kIsWeb) return;
    if (!online) {
      _settle(false);
      return;
    }
    _probeSoon();
  }

  void _probeSoon() {
    if (_probing) return;
    _retry?.cancel();
    _retry = Timer(Duration.zero, _runProbe);
  }

  Future<void> _runProbe() async {
    if (_probing) return;
    _probing = true;
    try {
      final ok = await probe();
      _settle(ok);
      if (!ok) {
        // Keep checking so the toast clears on its own when the portal is
        // signed into or the uplink comes back. Backoff is capped so a long
        // outage does not stretch the recovery delay indefinitely — 20s is
        // slow enough to cost nothing and fast enough that a citizen who has
        // just signed into the portal is not left staring at a stale pill.
        //
        // Indexed by attempt-1, and clamped to the LAST index rather than to
        // the length: clamping to _backoff.length would run one past the end.
        if (_attempt < _backoff.length) _attempt++;
        final delay = Duration(seconds: _backoff[_attempt - 1]);
        _retry?.cancel();
        _retry = Timer(delay, _runProbe);
      } else {
        _attempt = 0;
      }
    } finally {
      _probing = false;
    }
  }

  void _settle(bool value) {
    if (_reachable == value) return;
    _reachable = value;
    if (value) {
      _attempt = 0;
      _retry?.cancel();
      _retry = null;
    }
    if (!_controller.isClosed) _controller.add(value);
  }

  /// One reachability check. Public so the preview target can drive it.
  ///
  /// Returns true when it cannot tell — an unconfigured base url means this is
  /// a tree that never booted Supabase, and claiming an outage there would be
  /// a false alarm invented by the diagnostic itself.
  Future<bool> probe() async {
    final base = _baseUrl;
    final key = _anonKey;
    if (base == null || key == null) return true;

    final uri = Uri.parse('$base$_healthPath');
    final headers = {'apikey': key};

    final override = debugProbeOverride;
    if (override != null) {
      try {
        return await override(uri, headers);
      } catch (_) {
        return false;
      }
    }

    try {
      final res = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 8));
      // A captive portal answers with its own page — usually a 200 carrying
      // HTML — so the status alone is not enough. The real endpoint returns a
      // small JSON body naming GoTrue; anything else is somebody impersonating
      // it.
      if (res.statusCode != 200) return false;
      return res.body.contains('GoTrue');
    } catch (_) {
      return false;
    }
  }

  /// Test/preview teardown. The singleton lives for the life of the app in
  /// production, so this is never called there.
  void debugReset() {
    _retry?.cancel();
    _retry = null;
    _attempt = 0;
    _probing = false;
    _reachable = null;
  }
}
