// "A staff reply is waiting for approval" — the notification that did nothing.
//
// The trigger (notify_admins_of_pending_reply) writes the tag as
// `type = 'suggestion_reply_pending'` with `reference_id` = the SUGGESTION id.
// The admin bell then has to clear three separate gates, and the topic cleared
// none of them:
//
//   * kAllAdminTopics — every tab queries `topic IN (...)` server-side, so an
//     unlisted topic is written and NEVER rendered.
//   * AdminNotif._routable — decides whether the tap resolves; anything outside
//     it collapses to 'general' and dead-ends.
//   * _tabIndexForTopic in the admin shell — maps the topic to a nav tab.
//
// Being in one list and not another half-works, which is how report_update
// shipped broken. This pins all three.
import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/features/admin/widgets/admin_notifications.dart';

const _suggestionId = '7c1e9a4d-2b53-4e18-9a0f-6d4c3b2a1e5f';

void main() {
  group('the row is queried at all', () {
    // Omission here is invisible in the worst way: the database row exists, the
    // badge never counts it, and no tab ever renders it.
    test('suggestion_reply_pending is a queried topic', () {
      expect(kAllAdminTopics, contains('suggestion_reply_pending'));
    });

    // "All" is kAllAdminTopics, but a notification only reachable under All is
    // one an admin filtering by subject will never find.
    test('it is reachable under a named tab, not only under All', () {
      expect(kOtherTopics, contains('suggestion_reply_pending'));
      final suggestions =
          kOtherTabs.firstWhere((t) => t.label == 'Suggestions');
      expect(suggestions.topics, contains('suggestion_reply_pending'));
    });

    // The Others tab is the parent of the Suggestions sub-tab. If the topic is
    // missing from kOtherTopics the row vanishes the moment an admin opens
    // Others, even though the sub-tab lists it.
    test('the Others tab carries it too', () {
      final others = kPrimaryTabs.firstWhere((t) => t.label == 'Others');
      expect(others.topics, contains('suggestion_reply_pending'));
    });
  });

  group('the tap resolves', () {
    // The LIVE trigger writes the tag into `type`, leaving `topic` null — the
    // shape _effectiveTopic exists to absorb. Testing the `topic` spelling
    // alone would pass while production stayed broken.
    test('it routes when the tag arrives in type, as the trigger writes it',
        () {
      final n = AdminNotif.fromRow({
        'id': 'n1',
        'type': 'suggestion_reply_pending',
        'title': 'A staff reply is waiting for approval',
        'subtitle': 'Engineering Office drafted a reply to a suggestion.',
        'reference_id': _suggestionId,
        'created_at': '2026-09-22T12:00:00Z',
      });

      expect(
        n.topic,
        'suggestion_reply_pending',
        reason: 'a topic outside _routable becomes general and dead-ends',
      );
      // reference_id is the SUGGESTION id, which is what the Suggestions page
      // flashes. A dropped reference lands the admin on an unscrolled list.
      expect(n.referenceId, _suggestionId);
    });

    test('it routes when written as topic as well', () {
      final n = AdminNotif.fromRow({
        'id': 'n2',
        'topic': 'suggestion_reply_pending',
        'title': 'A staff reply is waiting for approval',
        'subtitle': 'Sanitation Office drafted a reply to a suggestion.',
        'reference_id': _suggestionId,
        'created_at': '2026-09-22T12:00:00Z',
      });

      expect(n.topic, 'suggestion_reply_pending');
      expect(n.referenceId, _suggestionId);
    });

    // Plain citizen suggestions must keep working — the new topic is an
    // addition to that tab, not a replacement.
    test('plain suggestion notifications still resolve', () {
      final n = AdminNotif.fromRow({
        'id': 'n3',
        'type': 'suggestion',
        'title': 'New suggestion',
        'subtitle': 'A citizen submitted a suggestion.',
        'reference_id': _suggestionId,
        'created_at': '2026-09-22T12:00:00Z',
      });

      expect(n.topic, 'suggestion');
    });
  });
}
