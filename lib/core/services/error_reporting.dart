// ════════════════════════════════════════════════════════════════════════════
//  Error reporting
//
//  Until this existed, a crash on the deployed web app reached nobody. The only
//  handler in main.dart is the one that SWALLOWS the benign Tooltip assertion;
//  everything else went to `FlutterError.presentError`, which on web means the
//  browser console — on the citizen's machine. A feed that white-screened for
//  one class of browser would have been invisible until somebody complained.
//
//  ── The privacy rule ──────────────────────────────────────────────────────
//  This is a government service holding citizen PII: names, addresses, ID
//  photographs, report locations. An error reporter is a pipe out of the app to
//  a third party, so the question is never "is this field useful" but "is this
//  field ours to send". The answer defaults to NO, and [_scrub] below enforces
//  that on every event.
//
//  What is deliberately NOT sent: request bodies, breadcrumb data payloads, the
//  user's IP, their email, their name, and any URL query string (a Supabase
//  signed-media URL carries a bearer token in its query, and a search URL
//  carries whatever the citizen typed).
//
//  What IS sent: the exception, the stack, the route name, the platform, the
//  release, and an opaque user id — enough to tell "this broke for 40 people on
//  Safari 17" from "this broke once for me".
// ════════════════════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../config/app_config.dart';

/// Runs [appRunner] with crash reporting attached, when a DSN is configured.
///
/// With no DSN this simply calls [appRunner] inside a guarded zone — so the
/// handlers below still run and still log, they just have nowhere to send. That
/// keeps the two paths identical in shape: a developer without a DSN exercises
/// the same code the deployed app does.
Future<void> runWithErrorReporting(FutureOr<void> Function() appRunner) async {
  if (!AppConfig.errorReportingEnabled) {
    _installLocalHandlers();
    return _runGuarded(appRunner);
  }

  await SentryFlutter.init(
    (options) {
      options.dsn = AppConfig.sentryDsn;
      options.environment = AppConfig.sentryEnvironment;

      // ── Sampling ────────────────────────────────────────────────────────
      // Every ERROR is reported: they are rare and each one matters.
      options.sampleRate = 1.0;
      // Performance traces are not. They are high-volume and this is a free
      // tier; 0 keeps the quota for crashes, which is what we came for.
      options.tracesSampleRate = 0.0;

      // ── Privacy ─────────────────────────────────────────────────────────
      // Off by default in the SDK, but set explicitly: these are exactly the
      // switches whose default could change under us, and each one is a
      // citizen-data question rather than a configuration preference.
      options.sendDefaultPii = false;
      // A screenshot of this app is a screenshot of someone's report, ID scan
      // or address, so it must never leave the device.
      options.attachScreenshot = false;
      // Console output the app itself produced can quote a row it just
      // fetched, so it is not a safe channel.
      options.enablePrintBreadcrumbs = false;

      // The last-chance filter. Everything above is a promise; this is the
      // enforcement.
      options.beforeSend = (event, hint) => _scrub(event);
      options.beforeBreadcrumb = (crumb, hint) => _scrubCrumb(crumb);

      // A debug build's errors are the developer's own, and they are already
      // on screen in red. Reporting them buries the real ones.
      options.debug = false;
      options.diagnosticLevel = SentryLevel.warning;
    },
    appRunner: () async {
      _installLocalHandlers();
      await _runGuarded(appRunner);
    },
  );
}

/// Wires the two handlers Flutter does NOT route through `FlutterError.onError`.
///
/// `FlutterError.onError` catches errors raised inside the framework's build /
/// layout / paint. It does not catch an unhandled async error from a Future or
/// a stream — the single largest source of real-world crashes in this app,
/// where nearly every screen awaits Supabase. `PlatformDispatcher.onError` is
/// the one that does.
///
/// main.dart's existing `FlutterError.onError` chain is deliberately left
/// alone: it already forwards everything except the benign Tooltip assertion to
/// the previous handler, and once Sentry is initialised Sentry IS that previous
/// handler. So the suppression keeps working and real framework errors reach
/// both the console and Sentry, with no change to that file's logic.
void _installLocalHandlers() {
  final previousPlatformOnError = PlatformDispatcher.instance.onError;
  PlatformDispatcher.instance.onError = (error, stack) {
    _report(error, stack, context: 'PlatformDispatcher.onError');
    // False lets the platform continue its default handling (printing it), so
    // a developer still sees the error in their console.
    return previousPlatformOnError?.call(error, stack) ?? false;
  };
}

Future<void> _runGuarded(FutureOr<void> Function() appRunner) {
  return runZonedGuarded<Future<void>>(() async {
        await appRunner();
      }, (error, stack) {
        _report(error, stack, context: 'runZonedGuarded');
      }) ??
      Future<void>.value();
}

void _report(Object error, StackTrace stack, {required String context}) {
  if (kDebugMode) {
    debugPrint('[$context] $error');
  }
  if (!AppConfig.errorReportingEnabled) return;
  unawaited(Sentry.captureException(error, stackTrace: stack));
}

/// Reports a caught error that the app handled but wants recorded.
///
/// For the case where a `catch` block already degrades gracefully — a failed
/// media upload, a triage write that fell back — and the user is fine, but the
/// failure rate is worth knowing. Never use it for control flow.
void reportHandledError(
  Object error,
  StackTrace? stack, {
  String? hint,
}) {
  if (kDebugMode) {
    debugPrint('[handled] ${hint ?? ''} $error');
  }
  if (!AppConfig.errorReportingEnabled) return;
  unawaited(
    Sentry.captureException(
      error,
      stackTrace: stack,
      withScope: (scope) {
        scope.level = SentryLevel.warning;
        if (hint != null) scope.setTag('handled_at', hint);
      },
    ),
  );
}

/// Associates events with an OPAQUE account id, or clears it on sign-out.
///
/// The id alone — no email, no username, no IP. That is the whole point: it
/// answers "one user or forty?" without putting an identity into a third-party
/// system. Call it where the session changes.
void setErrorReportingUser(String? userId) {
  if (!AppConfig.errorReportingEnabled) return;
  // configureScope returns FutureOr<void>, so it is awaited only when it
  // actually produced a Future.
  final result = Sentry.configureScope((scope) {
    scope.setUser(userId == null ? null : SentryUser(id: userId));
  });
  if (result is Future) unawaited(result);
}

// ── Scrubbing ───────────────────────────────────────────────────────────────

/// Stands in for a path segment that carried a value rather than a route name.
///
/// Matches the `[redacted]` the query string is already replaced with, so one
/// reader of a Sentry issue sees one convention.
const String _kRedactedSegment = '[redacted]';

/// Whether a path segment looks like an IDENTIFIER rather than a route name.
///
/// The distinction this function draws is the whole point of [sanitizeUrlForReport]:
/// `/my-reports/detail/88` should reach Sentry as `/my-reports/detail/[redacted]`
/// — the SHAPE kept so two crashes on that screen still group together, the
/// value dropped because it is somebody's data.
///
/// Conservative in the direction that matters. Redacting a route name costs a
/// little grouping quality; leaking an endorsement token costs a citizen's
/// privacy, so anything ambiguous is treated as an identifier.
///
/// A segment is a NAME (kept) when it is short, made only of lowercase letters,
/// digits and dashes, and contains at least one letter and no digit run longer
/// than two. That keeps every real route and Supabase path intact —
/// `my-reports`, `detail`, `rest`, `v1`, `object`, `chat-agent`, `report-media`
/// — while catching:
///
///   * uuids and long opaque tokens (`SECRET-TOKEN-123`, `a1b2c3d4-…`)
///   * bare numeric ids (`88`, `4213`)
///   * file names (`abc123.jpg`), which carry a storage key
///   * anything mixed-case, which no route here uses
bool _looksLikeIdentifier(String segment) {
  if (segment.isEmpty) return false;
  // A long segment is an id or a token; no route name here approaches this.
  if (segment.length > 24) return true;
  // Route names are lowercase-and-dashes. A dot means a filename, and an
  // underscore or uppercase letter means it is not one of this app's routes.
  if (!RegExp(r'^[a-z0-9-]+$').hasMatch(segment)) return true;
  // Purely numeric is always an id.
  if (!RegExp(r'[a-z]').hasMatch(segment)) return true;
  // `v1` and `v2` are real API segments; a longer digit run is an id.
  if (RegExp(r'\d{3,}').hasMatch(segment)) return true;
  return false;
}

/// Strips everything from a URL except scheme, host and a REDACTED path.
///
/// The dropped parts are the ones that carry data: a Supabase signed media URL
/// puts a bearer token in its QUERY — sent whole, a crash report would hand a
/// third party a working link to a citizen's ID photograph — a search URL puts
/// the citizen's own words there, and a FRAGMENT holds route arguments while
/// the app is hash-routed.
///
/// ── Why the path is no longer kept verbatim ────────────────────────────────
/// It used to be, and the reason was sound: the path is what makes two crashes
/// groupable. That rested on the app being hash-routed, which put every route
/// argument in the fragment where this function already dropped it.
///
/// The moment clean URLs are turned on (`usePathUrlStrategy()`), that stops
/// being true and the same arguments move INTO the path: `/#/scan/<token>`
/// becomes `/scan/<token>`, and an endorsement token — which opens a public
/// page describing a specific citizen's report — would be sent to a third-party
/// error service on every crash that carried a URL.
///
/// So the path is now kept STRUCTURALLY rather than literally: route names
/// survive, identifier-shaped segments are replaced. Grouping is preserved —
/// every crash on the scan page still reports `/scan/[redacted]` — without the
/// value travelling. See [_looksLikeIdentifier].
///
/// This is deliberately done BEFORE the URL change rather than with it: the
/// redaction is harmless while arguments still live in the fragment, and doing
/// it first means the guarantee is already live and proven when the URLs flip,
/// instead of racing the leak.
///
/// Public and named for testability: this is the single function standing
/// between citizen data and a third-party service, and a privacy guarantee
/// nothing can exercise is just a comment. See error_reporting_scrub_test.dart.
@visibleForTesting
String sanitizeUrlForReport(String raw) {
  final uri = Uri.tryParse(raw);
  // A relative or unparseable string could be anything; redact rather than
  // guess. `hasScheme` also rejects the `::: not a url :::` shapes Uri.parse
  // otherwise accepts as a bare path.
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) return '[redacted]';

  // Rebuilt from segments rather than string-replaced, so a value that happens
  // to contain a slash cannot smuggle itself through as two segments.
  //
  // The placeholder is appended to the built string rather than passed through
  // `Uri(path: …)`, which percent-encodes the brackets and turns every redacted
  // segment into `%5Bredacted%5D` — correct as a URI, and unreadable in the one
  // place these strings are ever looked at. The segments themselves still go
  // through Uri so a genuine path keeps its normal encoding.
  final redactedPath = uri.pathSegments
      .map((s) => _looksLikeIdentifier(s) ? _kRedactedSegment : s)
      .join('/');

  final origin = Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
  ).toString();

  // `Uri.pathSegments` drops the leading slash, and an empty path must stay
  // empty rather than become '/'.
  final safe = redactedPath.isEmpty ? origin : '$origin/$redactedPath';

  // Keep the fact that something was dropped visible, so a reader of the issue
  // knows the URL is abridged rather than genuinely bare.
  return uri.hasQuery ? '$safe?[redacted]' : safe;
}

SentryEvent? _scrub(SentryEvent event) {
  // A debug build's errors belong on the developer's screen, not in the
  // production issue feed.
  if (kDebugMode) return null;

  return event
    ..request = _scrubRequest(event.request)
    // Set elsewhere by setErrorReportingUser; re-assert here so no SDK
    // integration can enrich it back up into an identity.
    ..user = event.user == null ? null : SentryUser(id: event.user!.id);
}

SentryRequest? _scrubRequest(SentryRequest? request) {
  if (request == null) return null;
  return request.copyWith(
    url: request.url == null ? null : sanitizeUrlForReport(request.url!),
    queryString: '[redacted]',
    cookies: '[redacted]',
    headers: const {},
    data: null,
  );
}

Breadcrumb? _scrubCrumb(Breadcrumb? crumb) {
  if (crumb == null) return null;

  // An HTTP breadcrumb's `data` holds the full request URL and body.
  final data = crumb.data;
  Map<String, dynamic>? safeData;
  if (data != null && data.containsKey('url')) {
    safeData = {
      'url': sanitizeUrlForReport(data['url'].toString()),
      if (data['method'] != null) 'method': data['method'],
      if (data['status_code'] != null) 'status_code': data['status_code'],
    };
  }

  return crumb.copyWith(
    message: crumb.message,
    data: safeData,
  );
}
