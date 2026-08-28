// Does a stalled request eventually fail?
//
// ── The bug these pin ─────────────────────────────────────────────────────
// `Supabase.initialize` was called without an http client, so every query
// inherited Dart's default: a connection timeout, but NO ceiling on how long
// an ESTABLISHED connection may stay silent. On a weak-but-live network that
// is the worst combination — the socket connects, so the app's reachability
// probe reports "online", and then the request never answers.
//
// Nothing downstream could recover, because nothing ever failed: login sat on
// `user_roles`, the citizen home sat on its profile fetch, and both consoles
// sat on their identity query. All three present the same way to a user — a
// spinner or skeleton that never resolves, with no error and no way back.
//
// A timeout does not make a slow network fast. It makes a stalled request
// FINITE, which is what lets every existing error path do its job.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:govpulse/core/network/timeout_http_client.dart';

/// An inner client whose response never arrives, standing in for a socket that
/// connected and then went silent.
class _StalledClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      Completer<http.StreamedResponse>().future; // never completes
}

/// An inner client that answers after a set delay.
class _SlowClient extends http.BaseClient {
  final Duration delay;
  _SlowClient(this.delay);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    await Future<void>.delayed(delay);
    return http.StreamedResponse(const Stream<List<int>>.empty(), 200);
  }
}

final _query = Uri.parse('https://x.supabase.co/rest/v1/user_roles?select=*');
final _storage = Uri.parse('https://x.supabase.co/storage/v1/object/photos/a');

void main() {
  // Real time, not fakeAsync: `Future.timeout` schedules its timer in the zone
  // that created the future, and driving that through a fake clock made the
  // throw escape as an unhandled async error rather than landing on the
  // future. The budgets are injected instead, so these stay fast.
  const short = Duration(milliseconds: 60);
  const long = Duration(milliseconds: 400);

  test('a stalled query fails instead of hanging forever', () async {
    final client = TimeoutHttpClient(
      inner: _StalledClient(),
      timeout: short,
      uploadTimeout: long,
    );

    // The request that would once have hung forever now fails.
    await expectLater(
      client.send(http.Request('GET', _query)),
      throwsA(isA<http.ClientException>()),
    );
  });

  test('a slow but successful query is NOT cut off', () async {
    // Slow, not stalled. The point is to kill hangs, not to punish a weak
    // connection that is still working.
    final client = TimeoutHttpClient(
      inner: _SlowClient(const Duration(milliseconds: 20)),
      timeout: short,
      uploadTimeout: long,
    );

    final response = await client.send(http.Request('GET', _query));
    expect(response.statusCode, 200);
  });

  test('storage gets a longer budget than a query', () async {
    // An ID scan or report photo is megabytes over exactly the slow connection
    // this client exists for. Holding an upload to the query budget would
    // break the users it is meant to help.
    final client = TimeoutHttpClient(
      inner: _SlowClient(const Duration(milliseconds: 150)),
      timeout: short,
      uploadTimeout: long,
    );

    // Same 150ms delay, two different verdicts — that IS the separation.
    await expectLater(
      client.send(http.Request('GET', _query)),
      throwsA(isA<http.ClientException>()),
    );
    final upload = await client.send(http.Request('POST', _storage));
    expect(upload.statusCode, 200);
  });

  test('the storage budget is matched on a path segment, not a substring', () async {
    final client = TimeoutHttpClient(
      inner: _SlowClient(const Duration(milliseconds: 150)),
      timeout: short,
      uploadTimeout: long,
    );

    // A table whose NAME contains "storage" is an ordinary query and must not
    // silently inherit the upload budget.
    await expectLater(
      client.send(
        http.Request(
          'GET',
          Uri.parse('https://x.supabase.co/rest/v1/storage_audit'),
        ),
      ),
      throwsA(isA<http.ClientException>()),
    );
  });

  test('the failure is a ClientException, which callers already handle', () async {
    final client = TimeoutHttpClient(inner: _StalledClient(), timeout: short);

    // postgrest and gotrue translate ClientException into their own error
    // types, and every existing `catch (_)` already means "the network did not
    // cooperate". Throwing something more exotic would escape all of it.
    await expectLater(
      client.send(http.Request('GET', _query)),
      throwsA(
        isA<http.ClientException>().having(
          (e) => e.message,
          'message',
          contains('timed out'),
        ),
      ),
    );
  });

  test('an Edge Function gets a longer budget than a query', () async {
    // `chat-agent` calls Groq and waits for a model to generate a reply, which
    // routinely runs past the query budget. Getting this wrong would be QUIET:
    // ChatService catches the failure and falls back to the on-device brain,
    // so too short a budget silently downgrades the AI instead of erroring.
    final client = TimeoutHttpClient(
      inner: _SlowClient(const Duration(milliseconds: 150)),
      timeout: short,
      functionTimeout: long,
    );

    // Same 150ms delay, two verdicts — that IS the separation.
    await expectLater(
      client.send(http.Request('GET', _query)),
      throwsA(isA<http.ClientException>()),
    );
    final fn = await client.send(
      http.Request(
        'POST',
        Uri.parse('https://x.supabase.co/functions/v1/chat-agent'),
      ),
    );
    expect(fn.statusCode, 200);
  });

  test('the real defaults are the ones the app ships with', () {
    // The injected budgets above keep these tests fast; this pins the values
    // actually used in production, which no other test would catch drifting.
    expect(kSupabaseRequestTimeout, const Duration(seconds: 15));
    expect(kSupabaseUploadTimeout, const Duration(minutes: 2));
    expect(kSupabaseFunctionTimeout, const Duration(seconds: 90));
  });
}
