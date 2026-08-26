// Layout regression tests for the MOBILE notification sheet.
//
// The sheet is a FIXED-SIZE frame that content scrolls inside. A
// content-driven height was tried and reverted — a panel that resized itself
// around the row count read as the UI twitching — so "the panel is the same
// size regardless of how many notifications there are" is a REQUIREMENT here,
// not an accident, and these tests pin it.
//
// The 2026-08-26 screenshot also showed three defects inside that frame, all
// still fixed and still pinned below:
//
//   1. the card's title/subtitle had no `maxLines`, so a long title wrapped and
//      made its card taller than its neighbours;
//   2. the skeleton hardcoded a row extent that no real card matched, so the
//      list jumped on load;
//   3. cards were translucent white ON a translucent panel, so the blurred
//      home screen behind bled through and desaturated the text.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/features/home/screen/notification_popup.dart';

import '_responsive_matrix.dart';

AppNotification _notif({
  required String title,
  String subtitle = 'sub',
  bool read = false,
}) => AppNotification(
  id: title,
  icon: Icons.notifications,
  title: title,
  subtitle: subtitle,
  time: DateTime.now().subtract(const Duration(days: 1)),
  color: Colors.blue,
  type: 'general',
  read: read,
);

/// The frosted panel, found by its own decoration rather than by position in
/// the tree: it is the only Container with the sheet's 28px corner radius.
/// (The full-screen backdrop tint and the 18px cards are the near misses.)
Size _panelSize(WidgetTester tester) {
  final panel = find.byWidgetPredicate((w) {
    if (w is! Container) return false;
    final d = w.decoration;
    return d is BoxDecoration &&
        d.borderRadius == BorderRadius.circular(28);
  });
  expect(panel, findsOneWidget, reason: 'could not locate the sheet panel');
  return tester.getSize(panel);
}

Future<void> _pumpSheet(
  WidgetTester tester,
  Device device,
  List<AppNotification> notifs, {
  double textScale = 1.0,
}) async {
  NotificationService.debugSeed(notifs);
  await pumpAt(
    tester,
    device,
    () => MaterialApp(
      home: NotificationPopup(width: device.size.width, onTap: (_) {}),
    ),
    textScale: textScale,
  );
}

void main() {
  tearDown(NotificationService.debugReset);

  group('the panel is a fixed frame', () {
    // The deliberate behaviour: the sheet must NOT resize itself around the
    // number of notifications. Two rows and twenty rows get the same box.
    testWidgets('height does not change with the row count', (tester) async {
      for (final device in kPortrait) {
        await _pumpSheet(tester, device, [_notif(title: 'one')]);
        final oneRow = _panelSize(tester).height;

        await _pumpSheet(tester, device, [
          for (var i = 0; i < 20; i++) _notif(title: 'notification $i'),
        ]);
        final manyRows = _panelSize(tester).height;

        expect(
          manyRows,
          closeTo(oneRow, 0.5),
          reason:
              '$device: the panel resized with its content ($oneRow -> '
              '$manyRows). The sheet is a fixed frame; the list scrolls.',
        );
      }
    });

    testWidgets('the empty state keeps the full-size frame', (tester) async {
      const device = kModernPhone;
      await _pumpSheet(tester, device, [_notif(title: 'one')]);
      final withRow = _panelSize(tester).height;

      await _pumpSheet(tester, device, []);
      expect(find.text('No notifications'), findsOneWidget);
      expect(
        _panelSize(tester).height,
        closeTo(withRow, 0.5),
        reason: 'an empty sheet collapsed instead of holding its frame',
      );
    });

    testWidgets('the panel never exceeds the screen', (tester) async {
      for (final device in kPortrait) {
        await _pumpSheet(tester, device, [
          for (var i = 0; i < 30; i++) _notif(title: 'notification $i'),
        ]);
        expect(
          _panelSize(tester).height,
          lessThanOrEqualTo(device.size.height * 0.85 + 0.5),
          reason: '$device: panel grew past the screen cap',
        );
      }
    });
  });

  group('overflowing content scrolls', () {
    testWidgets('a list longer than the frame is scrollable', (tester) async {
      const device = kModernPhone;
      await _pumpSheet(tester, device, [
        for (var i = 0; i < 20; i++) _notif(title: 'notification $i'),
      ]);

      final list = find.descendant(
        of: find.byType(NotificationPopup),
        matching: find.byType(Scrollable),
      );
      expect(list, findsWidgets);

      final pos = tester.state<ScrollableState>(list.first).position;
      expect(
        pos.maxScrollExtent,
        greaterThan(0),
        reason: '20 notifications did not produce a scrollable extent',
      );

      // And it actually moves.
      await tester.drag(list.first, const Offset(0, -200));
      await tester.pump();
      expect(pos.pixels, greaterThan(0), reason: 'the list did not scroll');
    });

    testWidgets('a short list does not scroll', (tester) async {
      await _pumpSheet(tester, kModernPhone, [
        _notif(title: 'only one'),
      ]);
      final list = find.descendant(
        of: find.byType(NotificationPopup),
        matching: find.byType(Scrollable),
      );
      final pos = tester.state<ScrollableState>(list.first).position;
      expect(pos.maxScrollExtent, 0);
    });
  });

  group('Clear All', () {
    testWidgets('clears every row, including a scrolled-past one', (
      tester,
    ) async {
      await _pumpSheet(tester, kModernPhone, [
        for (var i = 0; i < 12; i++) _notif(title: 'notification $i'),
      ]);
      expect(find.text('notification 0'), findsOneWidget);

      await tester.tap(find.text('Clear All'));
      await tester.pump();

      // Drive the staggered slide-out and watch the sheet empty out.
      //
      // Sampled DURING the cascade on purpose. `_clearAll` ends with
      // `_syncFromService()`, and `NotificationService.remove` only drops its
      // local copy AFTER the Supabase delete succeeds — with no Supabase in a
      // widget test every delete fails, so that trailing sync correctly
      // re-imports the rows. On a device the deletes land and they stay gone.
      // What this pins is the part that is ours: the cascade reaches every
      // row, including the ones scrolled out of view, which is where a stagger
      // driven off built children would quietly skip rows.
      var sawEmpty = false;
      for (var step = 0; step < 80 && !sawEmpty; step++) {
        await tester.pump(const Duration(milliseconds: 100));
        sawEmpty = [
          for (var i = 0; i < 12; i++)
            if (find.text('notification $i').evaluate().isNotEmpty) i,
        ].isEmpty;
      }

      expect(
        sawEmpty,
        isTrue,
        reason: 'Clear All left rows on the sheet after the full cascade',
      );

      // Drain `_clearAll`'s trailing failsafe delay; leaving it pending trips
      // the binding's "a Timer is still pending" check at teardown.
      await tester.pump(const Duration(seconds: 5));
      expect(tester.takeException(), isNull);
    });

    testWidgets('is a no-op on an empty list', (tester) async {
      await _pumpSheet(tester, kModernPhone, []);
      await tester.tap(find.text('Clear All'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    });
  });

  group('cards are uniform height', () {
    testWidgets('a long title does not make its card taller', (tester) async {
      await _pumpSheet(tester, kModernPhone, [
        _notif(
          title:
              'The LGU replied to your Public Service suggestion about the '
              'drainage on Rizal Street and would like more detail',
          subtitle:
              'Re: "Test Mingration 7" Great idea. We are looking into '
              'whether we can put it in place.',
        ),
        _notif(title: 'New reply', subtitle: 'hello test'),
      ]);

      final clamped = tester
          .widgetList<Text>(find.byType(Text))
          .where((t) => t.maxLines != null)
          .toList();
      expect(clamped, isNotEmpty);
      expect(
        clamped.every((t) => t.maxLines == 1),
        isTrue,
        reason: 'a notification Text was left unclamped and can wrap',
      );
      expect(
        clamped.every((t) => t.overflow == TextOverflow.ellipsis),
        isTrue,
        reason: 'a clamped Text has no ellipsis and will hard-cut',
      );
    });
  });

  group('content is legible, not washed out', () {
    testWidgets('cards are opaque in both read and unread states', (
      tester,
    ) async {
      await _pumpSheet(tester, kModernPhone, [
        _notif(title: 'unread one'),
        _notif(title: 'read one', read: true),
      ]);

      final fills = tester
          .widgetList<Container>(find.byType(Container))
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .map((d) => d.color)
          .whereType<Color>()
          // The card fills are the light ones; ignore the icon tint + shadow.
          .where((c) => c.computeLuminance() > 0.7)
          .toList();

      expect(fills, isNotEmpty);
      expect(
        fills.every((c) => c.a >= 0.9),
        isTrue,
        reason:
            'a card/panel fill is still translucent — the blurred backdrop '
            'shows through and dulls the notification text',
      );
    });
  });

  group('responsiveness', () {
    testWidgets('nothing overflows across the phone matrix', (tester) async {
      for (final device in kAllPhones) {
        for (final scale in const [1.0, 1.3, 2.0]) {
          NotificationService.debugSeed([
            _notif(
              title: 'The LGU replied to your Public Service suggestion',
              subtitle: 'Re: "Test Mingration 7" Great idea.',
            ),
            _notif(title: 'New reply', subtitle: 'Chanzelyn replied: "hello"'),
            _notif(title: 'Report verified', subtitle: 'Your report is live'),
          ]);
          final errors = await pumpAt(
            tester,
            device,
            () => MaterialApp(
              home: NotificationPopup(
                width: device.size.width,
                onTap: (_) {},
              ),
            ),
            textScale: scale,
          );
          expect(
            errors,
            isEmpty,
            reason: '$device @ ${scale}x text: ${errors.join(" | ")}',
          );
          NotificationService.debugReset();
        }
      }
    });
  });
}
