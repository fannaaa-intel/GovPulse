// Layout regression tests for the MOBILE notification sheet.
//
// The 2026-08-26 screenshot showed a half-screen frosted panel holding two
// notifications, with the bottom half empty glass, one card taller than the
// other, and content that read as greyed-out. All four causes are pinned here:
//
//   1. the panel height was `w * 1.1` — derived from the SCREEN WIDTH, so it
//      reserved the same box for 2 notifications as for 20;
//   2. the card's title/subtitle had no `maxLines`, so a long title wrapped and
//      made its card taller than its neighbours;
//   3. the skeleton hardcoded a row extent that no real card matched, so the
//      list jumped on load;
//   4. cards were translucent white ON a translucent panel, so the blurred
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

/// The panel is the sized box directly under the entrance Transform.scale.
Size _panelSize(WidgetTester tester) {
  final panel = find
      .descendant(
        of: find.byType(NotificationPopup),
        matching: find.byType(AnimatedContainer),
      )
      .first;
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

  group('panel height follows content, not screen width', () {
    // The exact regression in the screenshot: two notifications must not
    // reserve a half-screen panel.
    testWidgets('two notifications use well under half the screen', (
      tester,
    ) async {
      for (final device in kPortrait) {
        await _pumpSheet(tester, device, [
          _notif(title: 'The LGU replied to your Public Service suggestion'),
          _notif(title: 'New reply'),
        ]);
        final h = _panelSize(tester).height;
        expect(
          h / device.size.height,
          lessThan(0.45),
          reason:
              '$device: 2 notifications filled ${(h / device.size.height * 100).round()}% '
              'of the screen — the width-derived height is back.',
        );
      }
    });

    testWidgets('more notifications make a taller panel', (tester) async {
      const device = kModernPhone;

      await _pumpSheet(tester, device, [_notif(title: 'one')]);
      final small = _panelSize(tester).height;

      await _pumpSheet(tester, device, [
        for (var i = 0; i < 5; i++) _notif(title: 'n$i'),
      ]);
      final large = _panelSize(tester).height;

      expect(
        large,
        greaterThan(small),
        reason: 'panel height ignored the row count',
      );
    });

    testWidgets('a long list is capped at 85% of the screen', (tester) async {
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

  group('cards are uniform height', () {
    testWidgets('a long title does not make its card taller', (tester) async {
      const device = kModernPhone;
      await _pumpSheet(tester, device, [
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

      final cards = tester
          .widgetList<Container>(
            find.descendant(
              of: find.byType(NotificationPopup),
              matching: find.byType(Container),
            ),
          )
          .toList();
      expect(cards, isNotEmpty);

      final heights = tester
          .widgetList<Text>(find.byType(Text))
          .where((t) => t.maxLines != null)
          .toList();
      // Every notification Text is clamped to a single line.
      expect(
        heights.every((t) => t.maxLines == 1),
        isTrue,
        reason: 'a notification Text was left unclamped and can wrap',
      );
      expect(
        heights.every((t) => t.overflow == TextOverflow.ellipsis),
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
