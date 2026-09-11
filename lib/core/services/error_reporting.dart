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

/// Strips everything from a URL except scheme, host and path.
///
/// The dropped parts are exactly the ones that carry data: a Supabase signed
/// media URL puts a bearer token in its QUERY — sent whole, a crash report
/// would hand a third party a working link to a citizen's ID photograph — a
/// search URL puts the citizen's own words there, and this app is hash-routed,
/// so its FRAGMENT holds route arguments like a scan token. The path is kept
/// because it is what makes two crashes groupable.
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

  final safe = Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: uri.path,
  ).toString();

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
