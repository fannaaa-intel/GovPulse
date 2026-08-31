// Preview target: the shared logout controls and the redesigned delete-account
// dialog, at the widths they have to hold.
//
//   flutter build web --release -t tool/preview_logout_controls.dart
//
// Both are pure presentation — no Supabase, no session — so they can be mounted
// directly. ?dialog=1 opens the delete dialog so its width cap can be captured
// on a desktop viewport, which is where it used to stretch to ~760px.
import 'package:flutter/material.dart';

import 'package:govpulse/core/theme/app_colors.dart';
import 'package:govpulse/core/widgets/logout_control.dart';

void main() {
  runApp(_App(openDialog: Uri.base.queryParameters['dialog'] == '1'));
}

class _App extends StatelessWidget {
  final bool openDialog;
  const _App({required this.openDialog});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        home: _Page(openDialog: openDialog),
      );
}

class _Page extends StatefulWidget {
  final bool openDialog;
  const _Page({required this.openDialog});

  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> {
  @override
  void initState() {
    super.initState();
    if (widget.openDialog) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showDelete());
    }
  }

  /// A copy of settings_screen._confirmDeleteAccount's dialog, so the preview
  /// shows the real shape without pulling in the whole login-gated screen.
  void _showDelete() {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400, minWidth: 280),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.red.withValues(alpha: 0.10),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.delete_outline_rounded,
                          size: 21, color: AppColors.red),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Text('Delete account',
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF111827))),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Text(
                  'This permanently removes your account and every report, '
                  'suggestion and comment you have submitted. It cannot be '
                  'undone.',
                  style: TextStyle(
                      fontSize: 13.5, height: 1.5, color: Color(0xFF374151)),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.support_agent_rounded,
                          size: 17, color: Color(0xFF6B7280)),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'To proceed, contact the Municipality so a staff '
                          'member can verify your identity first.',
                          style: TextStyle(
                              fontSize: 12.5,
                              height: 1.45,
                              color: Color(0xFF4B5563)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primaryBlue,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 10),
                    ),
                    child: const Text('Close',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Logout, one treatment',
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              const Text(
                'Tinted ground + hairline, so the row has an edge without '
                'being a solid red button. Same on admin, staff and citizen.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 20,
                runSpacing: 20,
                children: [
                  for (final w in const [560.0, 420.0, 320.0])
                    _Pane(width: w, onDelete: _showDelete),
                ],
              ),
              const SizedBox(height: 24),
              const Text('In a menu',
                  style:
                      TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Container(
                width: 240,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                  boxShadow: const [
                    BoxShadow(
                        color: Color(0x14000000),
                        blurRadius: 18,
                        offset: Offset(0, 6)),
                  ],
                ),
                child: const Column(
                  children: [
                    _FakeMenuRow(
                        icon: Icons.edit_rounded, label: 'Edit profile'),
                    _FakeMenuRow(
                        icon: Icons.lock_outline_rounded,
                        label: 'Change password'),
                    Divider(height: 9),
                    Padding(
                      padding: EdgeInsets.symmetric(
                          horizontal: 14, vertical: 7),
                      child: Align(
                          alignment: Alignment.centerLeft,
                          child: LogoutMenuRow()),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const Text('Collapsed rail',
                  style:
                      TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              SizedBox(
                width: 64,
                child: LogoutTile(onLogout: () {}, compact: true),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pane extends StatelessWidget {
  final double width;
  final VoidCallback onDelete;
  const _Pane({required this.width, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${width.toInt()}px',
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.black54)),
        const SizedBox(height: 6),
        SizedBox(
          width: width,
          child: Column(
            children: [
              // A settings card above it, so the contrast with an ordinary row
              // is what the screenshot actually shows.
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: const Column(
                  children: [
                    _FakeRow(
                        icon: Icons.lock_outline_rounded,
                        label: 'Change password'),
                    Divider(height: 1),
                    _FakeRow(
                        icon: Icons.notifications_none_rounded,
                        label: 'Notifications'),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              LogoutTile(onLogout: () {}),
              const SizedBox(height: 12),
              // The danger row that opens the dialog.
              Material(
                color: kLogoutTint,
                borderRadius: BorderRadius.circular(12),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onDelete,
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: kLogoutBorder),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.delete_outline_rounded,
                            size: 20, color: AppColors.red),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text('Delete account',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.red)),
                        ),
                        Icon(Icons.chevron_right_rounded,
                            size: 20, color: Colors.black26),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FakeRow extends StatelessWidget {
  final IconData icon;
  final String label;
  const _FakeRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: const Color(0xFF0D47A1)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
            ),
            const Icon(Icons.chevron_right_rounded,
                size: 20, color: Colors.black26),
          ],
        ),
      );
}

class _FakeMenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  const _FakeMenuRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Row(
          children: [
            Icon(icon, size: 18, color: const Color(0xFF6B7280)),
            const SizedBox(width: 11),
            Text(label,
                style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF6B7280),
                    fontWeight: FontWeight.w500)),
          ],
        ),
      );
}
