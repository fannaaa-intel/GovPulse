import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../providers/admin_reports_provider.dart';
import '../providers/admin_users_provider.dart';
import '../theme/admin_ui.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Admin command palette (⌘K / Ctrl-K, or tapping the topbar search)
//
//  A single search surface that jumps to nav sections AND finds reports/users
//  by keyword — selecting a data result opens the section that owns it. Fully
//  self-contained: it reads the already-loaded reports/users providers.
// ════════════════════════════════════════════════════════════════════════════

typedef PaletteSection = ({IconData icon, String label});

/// Opens the palette. [sections] is the nav list (index = position); [onNavigate]
/// switches the shell to that index.
Future<void> showAdminCommandPalette(
  BuildContext context, {
  required List<PaletteSection> sections,
  required void Function(int index) onNavigate,
}) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Search',
    barrierColor: Colors.black.withValues(alpha: 0.35),
    transitionDuration: const Duration(milliseconds: 150),
    pageBuilder: (_, _, _) =>
        _CommandPalette(sections: sections, onNavigate: onNavigate),
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

/// One selectable row (a section jump or a data hit), all resolving to a nav
/// index the shell can switch to.
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

class _CommandPalette extends ConsumerStatefulWidget {
  final List<PaletteSection> sections;
  final void Function(int index) onNavigate;
  const _CommandPalette({required this.sections, required this.onNavigate});

  @override
  ConsumerState<_CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends ConsumerState<_CommandPalette> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int _indexForLabel(String label) =>
      widget.sections.indexWhere((s) => s.label == label);

  // ── Result builders ────────────────────────────────────────────────────────
  List<_Result> get _sectionResults {
    final q = _query.trim().toLowerCase();
    final matches = <_Result>[];
    for (var i = 0; i < widget.sections.length; i++) {
      final s = widget.sections[i];
      if (q.isEmpty || s.label.toLowerCase().contains(q)) {
        matches.add(_Result(icon: s.icon, title: s.label, navIndex: i));
      }
    }
    return matches;
  }

  List<_Result> get _reportResults {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final idx = _indexForLabel('Reports');
    if (idx < 0) return const [];
    final reports = ref.watch(adminReportsProvider).valueOrNull ?? const [];
    return [
      for (final r in reports)
        if (r.category.toLowerCase().contains(q) ||
            (r.barangay ?? '').toLowerCase().contains(q) ||
            (r.address ?? '').toLowerCase().contains(q) ||
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

  List<_Result> get _userResults {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final idx = _indexForLabel('Users');
    if (idx < 0) return const [];
    final users = ref.watch(adminUsersProvider).valueOrNull ?? const [];
    return [
      for (final u in users)
        if (u.displayName.toLowerCase().contains(q) ||
            (u.email ?? '').toLowerCase().contains(q) ||
            (u.barangay ?? '').toLowerCase().contains(q))
          _Result(
            icon: u.isOfficial ? Icons.badge_rounded : Icons.person_rounded,
            title: u.displayName,
            subtitle: [
              appUserRoleLabel(u.role),
              if ((u.email ?? '').isNotEmpty) u.email!,
            ].join(' · '),
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
    final users = _userResults;
    final hasAny =
        sections.isNotEmpty || reports.isNotEmpty || users.isNotEmpty;

    // First selectable result — what Enter activates.
    final first = sections.isNotEmpty
        ? sections.first
        : (reports.isNotEmpty
              ? reports.first
              : (users.isNotEmpty ? users.first : null));

    return Material(
      color: Colors.transparent,
      child: Container(
        width: w,
        constraints: BoxConstraints(maxHeight: maxH),
        decoration: BoxDecoration(
          color: AdminUi.surface,
          borderRadius: BorderRadius.circular(AdminUi.cardRadius),
          border: Border.all(color: AdminUi.border),
          boxShadow: AdminUi.cardShadow,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Search field
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 10),
              child: Row(
                children: [
                  const Icon(
                    Icons.search_rounded,
                    size: 20,
                    color: AdminUi.textMuted,
                  ),
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
                        fontSize: 15,
                        color: AdminUi.textPrimary,
                      ),
                      decoration: const InputDecoration(
                        isCollapsed: true,
                        border: InputBorder.none,
                        hintText: 'Search sections, reports, people…',
                        hintStyle: TextStyle(
                          fontSize: 15,
                          color: AdminUi.textMuted,
                        ),
                      ),
                    ),
                  ),
                  _EscHint(onTap: () => Navigator.of(context).pop()),
                ],
              ),
            ),
            const Divider(height: 1, color: AdminUi.border),
            Flexible(
              child: !hasAny
                  ? const _EmptyState()
                  : ListView(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      shrinkWrap: true,
                      children: [
                        if (sections.isNotEmpty) ...[
                          const _GroupLabel('Go to'),
                          for (final r in sections)
                            _ResultRow(result: r, onTap: () => _select(r)),
                        ],
                        if (reports.isNotEmpty) ...[
                          const _GroupLabel('Reports'),
                          for (final r in reports)
                            _ResultRow(result: r, onTap: () => _select(r)),
                        ],
                        if (users.isNotEmpty) ...[
                          const _GroupLabel('People'),
                          for (final r in users)
                            _ResultRow(result: r, onTap: () => _select(r)),
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
        color: AdminUi.textMuted,
      ),
    ),
  );
}

class _ResultRow extends StatelessWidget {
  final _Result result;
  final VoidCallback onTap;
  const _ResultRow({required this.result, required this.onTap});

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
                color: AppColors.primaryBlue.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(result.icon, size: 17, color: AppColors.primaryBlue),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AdminUi.textPrimary,
                    ),
                  ),
                  if ((result.subtitle ?? '').isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text(
                      result.subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AdminUi.textMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(
              Icons.north_east_rounded,
              size: 15,
              color: AdminUi.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 34),
    child: Center(
      child: Text(
        'No matches.',
        style: TextStyle(fontSize: 13, color: AdminUi.textMuted),
      ),
    ),
  );
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
        color: AdminUi.subtle,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AdminUi.border),
      ),
      child: const Text(
        'Esc',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AdminUi.textMuted,
        ),
      ),
    ),
  );
}
