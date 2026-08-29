// A "progress update needs review" notification that does nothing when tapped
// is worse than no notification: it tells the admin something is waiting and
// then refuses to take them there.
//
// The three surfaces route it differently, and each has its own way of
// silently swallowing an unknown topic — which is why this pins the wiring
// rather than the rendering:
//
//   * admin — every tab queries `topic IN kAllAdminTopics`, so a topic missing
//     from that list is written to the database and never shown at all. The
//     list already carries a comment recording that exact trap for
//     community_request.
//   * staff — StaffNotifCenter._routable decides whether a tap is offered;
//     anything outside it dead-ends on 'general'.
//   * citizen — routeCitizenNotificationTap switches on `type` and its default
//     arm does nothing.

import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/features/admin/widgets/admin_notifications.dart';
import 'package:govpulse/features/staff/widgets/staff_notifications.dart';

void main() {
  group('admin', () {
    // The badge and every tab filter server-side on this list. Omission here is
    // invisible: the row exists, nothing renders it.
    test('report_update is a queried topic', () {
      expect(kAllAdminTopics, contains('report_update'));
    });

    test('it appears under the Reports tab, not only under All', () {
      final reports = kPrimaryTabs.firstWhere((t) => t.label == 'Reports');
      expect(reports.topics, contains('report_update'));
    });

    // Reports must stay the tab that owns it: the notification's reference_id
    // is a REPORT id (notify_admins_of_pending_update passes new.report_id), so
    // routing it anywhere else would flash an id that tab knows nothing about.
    test('the Reports tab still owns plain report notifications too', () {
      final reports = kPrimaryTabs.firstWhere((t) => t.label == 'Reports');
      expect(reports.topics, contains('report'));
    });

    // TWO lists, and being in only one half-works: kAllAdminTopics decides
    // whether the row is QUERIED, AdminNotif._routable decides whether the tap
    // RESOLVES. report_update shipped in the first and not the second, so the
    // notification appeared and tapping it did nothing.
    test('the tap resolves rather than collapsing to general', () {
      final n = AdminNotif.fromRow({
        'id': 'n1',
        'topic': 'report_update',
        'title': 'Progress update needs review',
        'subtitle': 'Engineering Office: Hello',
        'reference_id': '3f2a1b6c-8d4e-4f7a-9b1c-2e5d6a7b8c9d',
        'created_at': '2026-08-29T12:00:00Z',
      });

      expect(n.topic, 'report_update',
          reason: 'a topic outside _routable becomes general and dead-ends');
      expect(n.referenceId, '3f2a1b6c-8d4e-4f7a-9b1c-2e5d6a7b8c9d');
    });
  });

  group('staff', () {
    // _effectiveTopic falls back to 'general' for anything the console cannot
    // route, and a 'general' row is rendered without a tap target. Surviving
    // that fallback IS the assertion — it is the only observable difference
    // between a routable topic and an unroutable one.
    test('report_update survives the routable filter', () {
      final n = StaffNotif.fromRow({
        'id': 1,
        'topic': 'report_update',
        'title': 'Your progress update was approved',
        'subtitle': 'Patching completed.',
        'reference_id': '3f2a1b6c-8d4e-4f7a-9b1c-2e5d6a7b8c9d',
        'created_at': '2026-08-29T12:00:00Z',
      });

      expect(n.topic, 'report_update',
          reason: 'a topic that falls back to general renders untappable');
      expect(n.referenceId, '3f2a1b6c-8d4e-4f7a-9b1c-2e5d6a7b8c9d',
          reason: 'the report id is what the target list flashes');
    });

    // The same row arriving with the tag in `type` instead of `topic` — the
    // shape older triggers write, and the reason _effectiveTopic consults both.
    test('it routes when the tag arrives in type instead of topic', () {
      final n = StaffNotif.fromRow({
        'id': 2,
        'type': 'report_update',
        'title': 'Your progress update was returned',
        'subtitle': 'Please attach a photo.',
        'reference_id': '3f2a1b6c-8d4e-4f7a-9b1c-2e5d6a7b8c9d',
        'created_at': '2026-08-29T12:00:00Z',
      });

      expect(n.topic, 'report_update');
    });
  });
}
