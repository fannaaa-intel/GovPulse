import 'dart:async';

import 'package:http/http.dart' as http;

/// The default ceiling on a single Supabase request.
///
/// Long enough that a genuinely slow-but-working connection still succeeds —
/// a cold Postgres connection over 3G can legitimately take several seconds —
/// and short enough that a stalled request surfaces as an error the UI can
/// react to, instead of a spinner that never resolves.
const Duration kSupabaseRequestTimeout = Duration(seconds: 15);

/// The ceiling on a storage request — uploads and downloads.
///
/// Deliberately far more generous than [kSupabaseRequestTimeout]: an ID scan
/// or a report photo is megabytes, and on the slow connections this whole file
/// exists for that is a legitimately long transfer, not a stall.
const Duration kSupabaseUploadTimeout = Duration(minutes: 2);

/// The ceiling on an Edge Function call.
///
/// Longer than a query because these are not simple reads. `chat-agent` calls
/// Groq and waits for a model to generate a full reply, which routinely runs
/// well past the query budget on a long answer or a cold start.
///
/// Getting this wrong is quiet rather than loud: `ChatService` catches the
/// failure and falls back to the on-device brain, so too short a budget would
/// not crash anything — it would just silently downgrade the AI to the dumb
/// fallback whenever the model took a normal amount of time to think.
const Duration kSupabaseFunctionTimeout = Duration(seconds: 90);

/// An [http.Client] that fails a request rather than hanging on it forever.
///
/// ── Why this exists ────────────────────────────────────────────────────────
/// `Supabase.initialize` was called without an http client, so every query in
/// the app inherited Dart's default: a connection timeout, but NO limit on how
/// long an established connection may stay silent. On a weak-but-live network
/// that is the worst combination — the socket connects, so the app's own
/// reachability probe reports "online", and then the request simply never
/// answers.
///
/// Nothing downstream could recover from that, because nothing ever failed:
/// `AuthService.login` sat on `user_roles`, the citizen home sat on its
/// profile fetch, and the staff and admin consoles sat on their identity
/// query. All three present as the symptom users actually report — a spinner
/// or a skeleton that stays forever, with no error and no way back.
///
/// A timeout converts that silence into an ordinary error. It does not make a
/// slow network fast; it makes a stalled request *finite*, which is what lets
/// every existing error path — the cached-profile fallback, the retry button,
/// the offline overlay — do its job.
///
/// ── Scope ──────────────────────────────────────────────────────────────────
/// Per REQUEST, not per session: each call gets the full budget, so this can
/// never truncate a slow sequence of individually healthy requests. Realtime
/// runs over a WebSocket and does not pass through here.
class TimeoutHttpClient extends http.BaseClient {
  final http.Client _inner;
  final Duration timeout;
  final Duration uploadTimeout;
  final Duration functionTimeout;

  TimeoutHttpClient({
    http.Client? inner,
    this.timeout = kSupabaseRequestTimeout,
    this.uploadTimeout = kSupabaseUploadTimeout,
    this.functionTimeout = kSupabaseFunctionTimeout,
  }) : _inner = inner ?? http.Client();

  /// Storage traffic gets the longer budget.
  ///
  /// A verification selfie or an ID scan is megabytes over the same weak
  /// connection this class exists for, and can legitimately take far longer
  /// than a metadata query. Holding uploads to the query budget would break
  /// exactly the users it is meant to help — so the two are separated by the
  /// only thing available at this layer, the request path.
  ///
  /// Matched on a path SEGMENT rather than a substring, so a table or column
  /// that happens to contain the word cannot widen the upload budget.
  bool _isStorage(Uri url) => url.pathSegments.contains('storage');

  /// Edge Functions get their own budget — see [kSupabaseFunctionTimeout].
  bool _isFunction(Uri url) => url.pathSegments.contains('functions');

  Duration _budgetFor(Uri url) {
    if (_isStorage(url)) return uploadTimeout;
    if (_isFunction(url)) return functionTimeout;
    return timeout;
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final budget = _budgetFor(request.url);
    return _inner
        .send(request)
        .timeout(
          budget,
          onTimeout: () {
            // A ClientException is what the http stack already throws for a
            // failed request, and what postgrest/gotrue already translate into
            // their own error types. Throwing anything more exotic here would
            // escape every `catch (_)` that existing call sites use to mean
            // "the network did not cooperate".
            throw http.ClientException(
              'Request timed out after ${budget.inSeconds}s. '
              'The connection is too slow or unstable.',
              request.url,
            );
          },
        );
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
