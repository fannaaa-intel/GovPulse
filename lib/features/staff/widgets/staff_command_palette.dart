import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../admin/providers/admin_reports_provider.dart' show reportStatusLabel;
import '../providers/staff_providers.dart';
import '../theme/staff_ui.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Staff command palette (⌘K / Ctrl-K, or the topbar search).
//  Jumps to nav sections and finds department reports / conversations by
//  keyword — selecting a hit opens the section that owns it.
// ════════════════════════════════════════════════════════════════════════════

typedef StaffPaletteSection = ({IconData icon, String label});

Future<void> showStaffCommandPalette(
  BuildContext context, {
  required List<StaffPaletteSection> sections,
  required void Function(int index) onNavigate,
}) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Search',
    barrierColor: Colors.black.withValues(alpha: 0.35),
    transitionDuration: const Duration(milliseconds: 150),
    pageBuilder: (_, _, _) =>
        _Palette(sections: sections, onNavigate: onNavigate),
    transitionBuilder: (_, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 84),
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(0, -0.03),
                  end: Offset.zero,
                ).animate(curved),
                child: child,
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _Result {
  final IconData icon;
  final String title;
  final String? subtitle;
  final int navIndex;
  const _Result({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.navIndex,
  });
}

class _Palette extends ConsumerStatefulWidget {
  final List<StaffPaletteSection> sections;
  final void Function(int index) onNavigate;
  const _Palette({required this.sections, required this.onNavigate});

  @override
  ConsumerState<_Palette> createState() => _PaletteState();
}

class _PaletteState extends ConsumerState<_Palette> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int _indexForLabel(String label) =>
      widget.sections.indexWhere((s) => s.label == label);

  List<_Result> get _sectionResults {
    final q = _query.trim().toLowerCase();
    final out = <_Result>[];
    for (var i = 0; i < widget.sections.length; i++) {
      final s = widget.sections[i];
      if (q.isEmpty || s.label.toLowerCase().contains(q)) {
        out.add(_Result(icon: s.icon, title: s.label, navIndex: i));
      }
    }
    return out;
  }

  List<_Result> get _reportResults {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final idx = _indexForLabel('Reports') >= 0
        ? _indexForLabel('Reports')
        : _indexForLabel('Endorsements');
    if (idx < 0) return const [];
    final reports = ref.watch(staffReportsProvider).valueOrNull ?? const [];
    final endorsed =
        ref.watch(staffEndorsementsProvider).valueOrNull ?? const [];
    final all = [...reports, ...endorsed];
    return [
      for (final r in all)
        if (r.category.toLowerCase().contains(q) ||
            (r.barangay ?? '').toLowerCase().contains(q) ||
            r.remarks.toLowerCase().contains(q) ||
            r.shortId.toLowerCase().contains(q))
          _Result(
            icon: Icons.flag_rounded,
            title: r.category,
            subtitle: [
              if ((r.barangay ?? '').isNotEmpty) r.barangay!,
              reportStatusLabel(r.status),
            ].join(' · '),
            navIndex: idx,
          ),
    ].take(6).toList();
  }

  List<_Result> get _chatResults {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final idx = _indexForLabel('Conversations');
    if (idx < 0) return const [];
    final chats = ref.watch(staffConversationsProvider).valueOrNull ?? const [];
    return [
      for (final c in chats)
        if (c.citizenLabel.toLowerCase().contains(q) ||
            c.category.toLowerCase().contains(q) ||
            (c.referenceCode ?? '').toLowerCase().contains(q))
          _Result(
            icon: Icons.forum_rounded,
            title: c.citizenLabel,
            subtitle: c.category,
            navIndex: idx,
          ),
    ].take(6).toList();
  }

  void _select(_Result r) {
    Navigator.of(context).pop();
    widget.onNavigate(r.navIndex);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final narrow = size.width < 560;
    final w = narrow ? size.width - 28 : 560.0;
    final maxH = (size.height * 0.6).clamp(280.0, 560.0);

    final sections = _sectionResults;
    final reports = _reportResults;
    final chats = _chatResults;
    final hasAny =
        sections.isNotEmpty || reports.isNotEmpty || chats.isNotEmpty;
    final first = sections.isNotEmpty
        ? sections.first
        : (chats.isNotEmpty
            ? chats.first
            : (reports.isNotEmpty ? reports.first : null));

    return Material(
      color: Colors.transparent,
      child: Container(
        width: w,
        constraints: BoxConstraints(maxHeight: maxH),
        decoration: BoxDecoration(
          color: StaffUi.surface,
          borderRadius: BorderRadius.circular(StaffUi.cardRadius),
          border: Border.all(color: StaffUi.border),
          boxShadow: StaffUi.cardShadow,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 10),
              child: Row(
                children: [
                  const Icon(Icons.search_rounded,
                      size: 20, color: StaffUi.textMuted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      autofocus: true,
                      onChanged: (v) => setState(() => _query = v),
                      onSubmitted: (_) {
                        if (first != null) _select(first);
                      },
                      textInputAction: TextInputAction.go,
                      style: const TextStyle(
                          fontSize: 15, color: StaffUi.textPrimary),
                      decoration: const InputDecoration(
                        isCollapsed: true,
                        border: InputBorder.none,
                        hintText: 'Search sections, reports, chats…',
                        hintStyle:
                            TextStyle(fontSize: 15, color: StaffUi.textMuted),
                      ),
                    ),
                  ),
                  _EscHint(onTap: () => Navigator.of(context).pop()),
                ],
              ),
            ),
            const Divider(height: 1, color: StaffUi.border),
            Flexible(
              child: !hasAny
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 34),
                      child: Center(
                        child: Text('No matches.',
                            style: TextStyle(
                                fontSize: 13, color: StaffUi.textMuted)),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      shrinkWrap: true,
                      children: [
                        if (sections.isNotEmpty) ...[
                          const _GroupLabel('Go to'),
                          for (final r in sections)
                            _Row(result: r, onTap: () => _select(r)),
                        ],
                        if (chats.isNotEmpty) ...[
                          const _GroupLabel('Conversations'),
                          for (final r in chats)
                            _Row(result: r, onTap: () => _select(r)),
                        ],
                        if (reports.isNotEmpty) ...[
                          const _GroupLabel('Reports'),
                          for (final r in reports)
                            _Row(result: r, onTap: () => _select(r)),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  final String text;
  const _GroupLabel(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            color: StaffUi.textMuted,
          ),
        ),
      );
}

class _Row extends StatelessWidget {
  final _Result result;
  final VoidCallback onTap;
  const _Row({required this.result, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: StaffUi.accent.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(result.icon, size: 17, color: StaffUi.accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(result.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: StaffUi.textPrimary)),
                  if ((result.subtitle ?? '').isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text(result.subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12, color: StaffUi.textMuted)),
                  ],
                ],
              ),
            ),
            const Icon(Icons.north_east_rounded,
                size: 15, color: StaffUi.textMuted),
          ],
        ),
      ),
    );
  }
}

class _EscHint extends StatelessWidget {
  final VoidCallback onTap;
  const _EscHint({required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: StaffUi.subtle,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: StaffUi.border),
          ),
          child: const Text('Esc',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: StaffUi.textMuted)),
        ),
      );
}
