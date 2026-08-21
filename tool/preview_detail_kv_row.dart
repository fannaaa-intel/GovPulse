// Throwaway preview: renders the details-pane id block on its own so the
// label/pill alignment can be looked at without logging into the admin app.
import 'package:flutter/material.dart';
import 'package:govpulse/core/theme/app_colors.dart';
import 'package:govpulse/features/admin/theme/admin_ui.dart';
import 'package:govpulse/features/admin/widgets/report_detail_kit.dart';
import 'package:govpulse/features/admin/widgets/admin_submission_ui.dart';

void main() => runApp(const _App());

class _App extends StatelessWidget {
  const _App();
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('report — pill + overdue chip'),
                const SizedBox(height: 8),
                DetailKvRow(
                  label: 'Status',
                  trailing: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: const [
                      StatusPill(label: 'Pending', color: AppColors.orange),
                      DetailOverdueChip(28),
                    ],
                  ),
                ),
                const DetailKvRow(label: 'ID', value: '#RPT-3D1AE001'),
                const DetailKvRow(label: 'Date Reported', value: 'Jul 23, 2026'),
                const SizedBox(height: 24),
                const Text('staff — resolved (bare pill)'),
                const SizedBox(height: 8),
                const DetailKvRow(
                  label: 'Status',
                  trailing: StatusPill(label: 'Resolved', color: AppColors.green),
                ),
                const DetailKvRow(label: 'ID', value: '#RPT-B34A6055'),
                const DetailKvRow(label: 'Date Reported', value: 'Jul 21, 2026'),
                const DetailKvRow(label: 'Time Reported', value: '10:37 PM'),
                const SizedBox(height: 24),
                const Text('suggestion — bare pill'),
                const SizedBox(height: 8),
                const DetailKvRow(
                  label: 'Status',
                  trailing: StatusPill(label: 'New', color: AppColors.orange),
                ),
                const DetailKvRow(label: 'ID', value: '#SUG-SGS-FAC9E0F9'),
                const DetailKvRow(
                  label: 'Date Submitted',
                  value: 'Jul 21, 2026',
                ),
                const SizedBox(height: 24),
                const Text('narrow — wrapped chips'),
                const SizedBox(height: 8),
                SizedBox(
                  width: 190,
                  child: DetailKvRow(
                    label: 'Status',
                    trailing: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: const [
                        StatusPill(label: 'In Progress', color: AdminUi.textSecondary),
                        DetailOverdueChip(28),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
