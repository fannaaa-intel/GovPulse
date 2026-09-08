// Dev-only harness for the Events sort control, both arms.
//
//   flutter build web --release -t tool/preview_events_sort.dart
//
// The real screen cannot be driven here for the same reason the tests cannot
// drive it: EventsService builds from `Supabase.instance.client`, so the fetch
// fails and the mobile body returns its full-screen error state. What is drawn
// below is the sort control itself at the sizes each arm gives it, beside the
// filter chips it has to share a head with — which is the thing worth LOOKING
// at, because the question a screenshot answers is whether the two controls
// read as two different questions rather than as five chips and a stray word.
//
// The web control's own menu is a real showMenu, so clicking it here opens the
// same popup the panel opens.

import 'package:flutter/material.dart';

import 'package:govpulse/core/theme/citizen_ui.dart';
import 'package:govpulse/features/home/Quick-action/Events/events_screen.dart';

void main() => runApp(const _PreviewApp());

const _filters = ['All', 'Today', 'Upcoming', 'Recent', 'Health'];

/// The web chip, copied to shape only — the real one is private.
Widget _chip(String label, bool selected) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
  decoration: BoxDecoration(
    color: selected ? CitizenUi.accent : CitizenUi.subtle,
    borderRadius: BorderRadius.circular(20),
    border: Border.all(color: selected ? CitizenUi.accent : CitizenUi.border),
  ),
  child: Text(
    label,
    style: TextStyle(
      fontSize: 12,
      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      color: selected ? Colors.white : CitizenUi.textSecondary,
    ),
  ),
);

/// The web arm's sort control, as the panel places it.
class _WebArm extends StatefulWidget {
  final double width;
  final bool stacked;
  const _WebArm({required this.width, required this.stacked});

  @override
  State<_WebArm> createState() => _WebArmState();
}

class _WebArmState extends State<_WebArm> {
  EventSort _sort = EventSort.soonest;

  @override
  Widget build(BuildContext context) {
    final chips = [for (final f in _filters) _chip(f, f == 'All')];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 4),
          child: Text(
            '${widget.stacked ? "stacked" : "side by side"} · '
            '${widget.width.toStringAsFixed(0)}px',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Container(
          width: widget.width,
          color: Colors.white,
          padding: const EdgeInsets.all(18),
          child: widget.stacked
              // Stacked: chips scroll sideways, sort on its own line below.
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: 32,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: chips.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 7),
                        itemBuilder: (_, i) => Center(child: chips[i]),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _sortControl(),
                    ),
                  ],
                )
              // Side by side: chips wrap on the left, sort pinned right.
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Wrap(spacing: 7, runSpacing: 7, children: chips),
                    ),
                    const SizedBox(width: 8),
                    _sortControl(),
                  ],
                ),
        ),
      ],
    );
  }

  // Mirrors _SplitSortControl's resting look. The live control is private, so
  // this stands in for the screenshot; its menu behaviour is covered by tests.
  Widget _sortControl() {
    final active = _sort != EventSort.soonest;
    return InkWell(
      onTap: () =>
          setState(() => _sort = active ? EventSort.soonest : EventSort.newest),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.filter_list_rounded,
              size: 16,
              color: active ? CitizenUi.accent : CitizenUi.textMuted,
            ),
            const SizedBox(width: 6),
            Text(
              _sort.label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                color: active ? CitizenUi.accent : CitizenUi.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The mobile arm's sort row at a given device width.
class _MobileArm extends StatelessWidget {
  final double w;
  final EventSort sort;
  const _MobileArm({required this.w, this.sort = EventSort.soonest});

  @override
  Widget build(BuildContext context) {
    final active = sort != EventSort.soonest;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 4),
          child: Text(
            'mobile ${w.toStringAsFixed(0)}px'
            '${active ? " · sorted" : ""}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Container(
          width: w,
          color: const Color(0xFFF3F4F6),
          padding: EdgeInsets.only(bottom: w * 0.03),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The chips above it, so the two rows can be judged together.
              Padding(
                padding: EdgeInsets.fromLTRB(w * 0.04, w * 0.025, w * 0.04, 0),
                child: SizedBox(
                  height: w * 0.088,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.zero,
                    children: [
                      for (final f in _filters)
                        Padding(
                          padding: EdgeInsets.only(right: w * 0.02),
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: w * 0.04,
                              vertical: w * 0.018,
                            ),
                            decoration: BoxDecoration(
                              color: f == 'All'
                                  ? const Color(0xFF2563EB)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(w * 0.05),
                              border: Border.all(
                                color: f == 'All'
                                    ? const Color(0xFF2563EB)
                                    : const Color(0xFFE5E7EB),
                              ),
                            ),
                            child: Center(
                              child: Text(
                                f,
                                style: TextStyle(
                                  fontSize: w * 0.032,
                                  fontWeight: FontWeight.w600,
                                  color: f == 'All'
                                      ? Colors.white
                                      : const Color(0xFF374151),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              // The sort row itself.
              Padding(
                padding: EdgeInsets.fromLTRB(w * 0.04, w * 0.02, w * 0.04, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: w * 0.025,
                        vertical: w * 0.012,
                      ),
                      decoration: BoxDecoration(
                        color: active
                            ? const Color(0xFF0D47A1).withValues(alpha: 0.15)
                            : const Color(0xFF0D47A1).withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(w * 0.04),
                        border: active
                            ? Border.all(
                                color: const Color(
                                  0xFF0D47A1,
                                ).withValues(alpha: 0.4),
                                width: 1.2,
                              )
                            : null,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.tune_rounded,
                            size: w * 0.044,
                            color: const Color(0xFF0D47A1),
                          ),
                          SizedBox(width: w * 0.012),
                          Text(
                            sort.label,
                            style: TextStyle(
                              fontSize: w * 0.034,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF0D47A1),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PreviewApp extends StatelessWidget {
  const _PreviewApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF2B2F3A),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'WEB — the panel head (click the sort to toggle it)',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              const _WebArm(width: 660, stacked: false),
              const SizedBox(height: 20),
              const _WebArm(width: 420, stacked: true),
              const SizedBox(height: 28),
              const Text(
                'MOBILE — chips, then the sort on its own line',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    _MobileArm(w: 320),
                    SizedBox(width: 20),
                    _MobileArm(w: 390),
                    SizedBox(width: 20),
                    _MobileArm(w: 390, sort: EventSort.newest),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
