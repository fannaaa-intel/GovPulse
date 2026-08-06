import 'package:flutter/material.dart';

import '../theme/citizen_ui.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Rebuilds a detail view's subject from an id in the URL.
//
//  Detail routes used to be reachable only by handing the object over in memory
//  — `settings.arguments` on the legacy router, `extra` on go_router. That works
//  perfectly right up until someone refreshes the page or pastes the link to a
//  colleague, at which point the object is gone and the route has nothing to
//  render. app_router.dart carries a guard (the `argRequiredRoutes` set) whose
//  entire job is to bounce those routes to the splash screen rather than let
//  them white-screen — which is a crash being converted into a redirect, not a
//  URL that works.
//
//  [ResolveById] makes the object optional instead of required:
//
//    • [initial] non-null  → render immediately. In-session navigation still
//      hands the object over, so there is no fetch and no loading flash. This is
//      also what keeps the MOBILE app on its existing path untouched.
//    • [initial] null      → fetch by id, show [loadingLabel] while it lands,
//      and a graceful not-found panel if the id is unknown.
//
//  The object is therefore a fast-path optimisation and never a requirement,
//  which is the property a single-router cutover needs.
// ════════════════════════════════════════════════════════════════════════════

class ResolveById<T> extends StatefulWidget {
  /// The subject, when the caller already has it. Null on a cold load.
  final T? initial;

  /// Fetches the subject by id. Should return null for "no such thing" and
  /// throw only for a genuine network/database failure — the two get different
  /// messages, because "this report does not exist" and "you are offline" are
  /// not the same problem.
  final Future<T?> Function() fetch;

  final Widget Function(BuildContext context, T value) builder;

  /// Shown under the spinner, e.g. 'Loading report…'.
  final String loadingLabel;

  /// Shown when [fetch] returns null, e.g. 'Report not found'.
  final String notFoundTitle;
  final String notFoundMessage;

  const ResolveById({
    super.key,
    required this.initial,
    required this.fetch,
    required this.builder,
    required this.loadingLabel,
    required this.notFoundTitle,
    required this.notFoundMessage,
  });

  @override
  State<ResolveById<T>> createState() => _ResolveByIdState<T>();
}

class _ResolveByIdState<T> extends State<ResolveById<T>> {
  late Future<T?>? _future;

  @override
  void initState() {
    super.initState();
    // No fetch at all when the object came with us — the in-session path must
    // not pay for the reload path.
    _future = widget.initial != null ? null : widget.fetch();
  }

  void _retry() => setState(() => _future = widget.fetch());

  @override
  Widget build(BuildContext context) {
    final initial = widget.initial;
    if (initial != null) return widget.builder(context, initial);

    return FutureBuilder<T?>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return _Centered(
            children: [
              const SizedBox(
                width: 30,
                height: 30,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              const SizedBox(height: 16),
              Text(
                widget.loadingLabel,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: CitizenUi.textMuted,
                ),
              ),
            ],
          );
        }

        if (snap.hasError) {
          return _Message(
            icon: Icons.wifi_off_rounded,
            title: "Couldn't load this",
            message:
                'Something went wrong reaching the server. Check your '
                'connection and try again.',
            onRetry: _retry,
          );
        }

        final value = snap.data;
        if (value == null) {
          return _Message(
            icon: Icons.search_off_rounded,
            title: widget.notFoundTitle,
            message: widget.notFoundMessage,
          );
        }

        return widget.builder(context, value);
      },
    );
  }
}

class _Centered extends StatelessWidget {
  final List<Widget> children;
  const _Centered({required this.children});

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: CitizenUi.pageBg,
    child: Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    ),
  );
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final VoidCallback? onRetry;

  const _Message({
    required this.icon,
    required this.title,
    required this.message,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return _Centered(
      children: [
        Container(
          width: 62,
          height: 62,
          decoration: const BoxDecoration(
            color: CitizenUi.accentWash,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 28, color: CitizenUi.accent),
        ),
        const SizedBox(height: 18),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: CitizenUi.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13.5,
              height: 1.5,
              color: CitizenUi.textMuted,
            ),
          ),
        ),
        if (onRetry != null) ...[
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Try again'),
            style: FilledButton.styleFrom(backgroundColor: CitizenUi.accent),
          ),
        ],
      ],
    );
  }
}
