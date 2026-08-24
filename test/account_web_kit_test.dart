// Responsiveness guard for the ACCOUNT pages' web layout kit.
//
// ── WHY THIS FILE CAN EXIST WHEN A SCREEN TEST CANNOT ─────────────────────
// Edit Profile, Settings and Change Password all gate their web layout behind
// `kIsWeb`, which is false in the test VM, and all three reach for Supabase in
// initState. So the SCREENS are untestable here without a browser runner.
//
// The kit is not: it is pure Flutter, it holds every measurement those pages
// share, and `stack` — the single flag the whole responsive story hangs on — is
// computed here from a LayoutBuilder. Testing the kit tests the part that can
// actually be wrong by accident.
//
// ── The text scale ────────────────────────────────────────────────────────
// The test font draws every glyph as a full em square, so a label measures
// roughly twice its real width and rows overflow at widths where they fit
// perfectly in a browser. Scaled to 0.6 so text occupies device-like space;
// the overflow cases below are only meaningful with that in place.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:govpulse/core/widgets/Home/Account/account_web_kit.dart';

Future<void> _pumpAt(
  WidgetTester tester,
  double width,
  Widget child, {
  double height = 1000,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      builder: (context, inner) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: const TextScaler.linear(0.6)),
        child: inner!,
      ),
      home: Scaffold(body: child),
    ),
  );
  await tester.pump();
}

Widget _field(String label) => AccountTextField(
  controller: TextEditingController(),
  label: label,
  hint: 'hint',
);

Widget _threeUp(bool stack) => AccountPageBody(
  builder: (context, s) => AccountFieldSection(
    title: 'Personal information',
    stack: s,
    rows: [
      [_field('First'), _field('Middle'), _field('Last')],
    ],
  ),
);

void main() {
  group('stack threshold', () {
    testWidgets('three fields share a row above the breakpoint', (
      tester,
    ) async {
      await _pumpAt(tester, 1200, _threeUp(false));

      final first = tester.getTopLeft(find.text('First'));
      final middle = tester.getTopLeft(find.text('Middle'));
      final last = tester.getTopLeft(find.text('Last'));

      expect(first.dy, middle.dy, reason: 'same row');
      expect(middle.dy, last.dy, reason: 'same row');
      expect(first.dx < middle.dx, isTrue, reason: 'in reading order');
      expect(middle.dx < last.dx, isTrue, reason: 'in reading order');
    });

    testWidgets('the same three stack below it', (tester) async {
      await _pumpAt(tester, 480, _threeUp(true));

      final first = tester.getTopLeft(find.text('First'));
      final middle = tester.getTopLeft(find.text('Middle'));
      final last = tester.getTopLeft(find.text('Last'));

      expect(first.dx, middle.dx, reason: 'one column');
      expect(middle.dx, last.dx, reason: 'one column');
      expect(first.dy < middle.dy, isTrue, reason: 'in reading order');
      expect(middle.dy < last.dy, isTrue, reason: 'in reading order');
    });

    testWidgets('the flag flips exactly at kAccountStackBelow', (tester) async {
      late bool wideFlag;
      late bool narrowFlag;

      await _pumpAt(
        tester,
        kAccountStackBelow + 1,
        AccountPageBody(
          builder: (_, s) {
            wideFlag = s;
            return const SizedBox.shrink();
          },
        ),
      );
      await _pumpAt(
        tester,
        kAccountStackBelow - 1,
        AccountPageBody(
          builder: (_, s) {
            narrowFlag = s;
            return const SizedBox.shrink();
          },
        ),
      );

      expect(wideFlag, isFalse);
      expect(narrowFlag, isTrue);
    });
  });

  group('one centred measure', () {
    testWidgets('content caps at kAccountMaxWidth and centres', (tester) async {
      const viewport = 1600.0;
      await _pumpAt(
        tester,
        viewport,
        AccountPageBody(
          builder: (_, s) => AccountFieldSection(
            title: 'Account',
            stack: s,
            rows: [
              [_field('Email')],
            ],
          ),
        ),
      );

      final card = tester.getRect(find.byType(AccountCard).first);

      // 32px of page padding either side of the 880 measure.
      expect(card.width, closeTo(kAccountMaxWidth - 64, 1));

      // Equal air on both sides — the whole point of centring the block.
      final leftGap = card.left;
      final rightGap = viewport - card.right;
      expect(leftGap, closeTo(rightGap, 1));
    });

    testWidgets('title, section label and card share one left edge', (
      tester,
    ) async {
      await _pumpAt(
        tester,
        1400,
        AccountPageBody(
          builder: (_, s) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AccountPageTitle(title: 'Settings', subtitle: 'Subtitle'),
              AccountFieldSection(
                title: 'Account',
                stack: s,
                rows: [
                  [_field('Email')],
                ],
              ),
            ],
          ),
        ),
      );

      // The regression this pins: three edges a couple of pixels apart read as
      // a mistake, not as a hierarchy.
      final title = tester.getTopLeft(find.text('Settings')).dx;
      final label = tester.getTopLeft(find.text('ACCOUNT')).dx;
      final card = tester.getTopLeft(find.byType(AccountCard).first).dx;

      expect(label, closeTo(title, 0.5));
      expect(card, closeTo(title, 0.5));
    });
  });

  group('actions', () {
    testWidgets('right-aligned pair when there is room', (tester) async {
      await _pumpAt(
        tester,
        1200,
        AccountPageBody(
          builder: (_, s) => AccountActions(
            stack: s,
            primaryLabel: 'Save',
            onPrimary: () {},
            secondaryLabel: 'Cancel',
            onSecondary: () {},
          ),
        ),
      );

      final save = tester.getCenter(find.text('Save'));
      final cancel = tester.getCenter(find.text('Cancel'));

      expect(save.dy, closeTo(cancel.dy, 0.5), reason: 'one row');
      expect(save.dx > cancel.dx, isTrue, reason: 'primary sits last');
    });

    testWidgets('stacked with the primary first when narrow', (tester) async {
      await _pumpAt(
        tester,
        420,
        AccountPageBody(
          builder: (_, s) => AccountActions(
            stack: s,
            primaryLabel: 'Save',
            onPrimary: () {},
            secondaryLabel: 'Cancel',
            onSecondary: () {},
          ),
        ),
      );

      final save = tester.getCenter(find.text('Save'));
      final cancel = tester.getCenter(find.text('Cancel'));

      expect(save.dy < cancel.dy, isTrue, reason: 'primary on top');
      expect(save.dx, closeTo(cancel.dx, 0.5), reason: 'both full width');
    });

    testWidgets('busy swaps the label for a spinner', (tester) async {
      await _pumpAt(
        tester,
        1200,
        AccountPageBody(
          builder: (_, s) => AccountActions(
            stack: s,
            busy: true,
            primaryLabel: 'Save',
            onPrimary: null,
          ),
        ),
      );

      expect(find.text('Save'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  group('no overflow', () {
    // A full page, exercising every piece at once.
    Widget page() => AccountPageBody(
      builder: (context, s) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AccountPageTitle(
            title: 'Change Password',
            subtitle: 'Confirm your email, then choose a new password.',
          ),
          const AccountStepper(step: 1, labels: kChangePasswordSteps),
          AccountNotice(
            stack: s,
            tone: AccountNoticeTone.warning,
            icon: Icons.lock_clock_rounded,
            title: 'Profile editing is locked',
            message: 'You can edit again on 9/18/2026.',
            trailing: const AccountNoticePill(label: '30 days left'),
          ),
          const SizedBox(height: 24),
          AccountFieldSection(
            title: 'Personal information',
            stack: s,
            rows: [
              [
                _field('First name'),
                _field('Middle name'),
                _field('Last name'),
              ],
            ],
          ),
          const SizedBox(height: 24),
          const AccountListSection(
            title: 'About',
            children: [
              AccountRow(
                icon: Icons.place_outlined,
                title: 'Location',
                subtitle: 'Aparri, Cagayan',
              ),
              AccountRow(
                icon: Icons.delete_outline_rounded,
                title: 'Delete account',
                subtitle: 'Permanently removes your account and its data',
                danger: true,
              ),
            ],
          ),
          const SizedBox(height: 24),
          AccountActions(
            stack: s,
            primaryLabel: 'Update password',
            onPrimary: () {},
            secondaryLabel: 'Back',
            onSecondary: () {},
          ),
        ],
      ),
    );

    for (final width in <double>[360, 480, 719, 721, 900, 1200, 1600]) {
      testWidgets('a full page lays out at ${width.toInt()}px', (tester) async {
        await _pumpAt(tester, width, page(), height: 2400);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('skeleton', () {
    // pump(), never pumpAndSettle(): the shimmer repeats forever and settling
    // would hang.
    for (final width in <double>[400, 900, 1500]) {
      testWidgets('mirrors the page at ${width.toInt()}px', (tester) async {
        await _pumpAt(
          tester,
          width,
          const AccountPageSkeleton(
            banner: true,
            sections: [
              [2],
              [3],
              [1],
            ],
            actions: true,
          ),
          height: 2400,
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('sits at the same measure as the real page', (tester) async {
      const viewport = 1600.0;

      await _pumpAt(
        tester,
        viewport,
        const AccountPageSkeleton(
          sections: [
            [1],
          ],
        ),
        height: 1200,
      );
      final skeletonCard = tester.getRect(find.byType(AccountCard).first);

      await _pumpAt(
        tester,
        viewport,
        AccountPageBody(
          builder: (_, s) => AccountFieldSection(
            title: 'Account',
            stack: s,
            rows: [
              [_field('Email')],
            ],
          ),
        ),
        height: 1200,
      );
      final realCard = tester.getRect(find.byType(AccountCard).first);

      // The whole reason the skeleton is built from the kit: if these diverge,
      // the page visibly rearranges itself the moment it loads.
      expect(skeletonCard.left, closeTo(realCard.left, 0.5));
      expect(skeletonCard.width, closeTo(realCard.width, 0.5));
    });
  });

  // ── Tabs, filters and list states ─────────────────────────────────────────
  //
  // My Submissions is the first account page that is a LIST rather than a form,
  // so these are the pieces it added to the kit. Same reasoning as the rest of
  // this file: the screen itself is untestable here (kIsWeb is false and it
  // reaches Supabase in initState), so the guard goes on the kit.

  group('tab bar', () {
    testWidgets('reports the tapped index and nothing else', (tester) async {
      final taps = <int>[];
      await _pumpAt(
        tester,
        1200,
        AccountPageBody(
          builder: (_, s) => AccountTabBar(
            index: 0,
            stack: s,
            onChanged: taps.add,
            tabs: const [
              AccountTab('Reports', count: 3),
              AccountTab('Suggestions', count: 1),
              AccountTab('Feedback'),
            ],
          ),
        ),
      );

      await tester.tap(find.text('Suggestions'));
      await tester.pump();
      expect(taps, [1]);

      await tester.tap(find.text('Feedback'));
      await tester.pump();
      expect(taps, [1, 2]);
    });

    testWidgets('a null count draws no pill', (tester) async {
      await _pumpAt(
        tester,
        1200,
        AccountPageBody(
          builder: (_, s) => AccountTabBar(
            index: 0,
            stack: s,
            onChanged: (_) {},
            tabs: const [
              AccountTab('Reports'),
              AccountTab('Feedback', count: 0),
            ],
          ),
        ),
      );

      // The regression this pins: a page that has not loaded yet must not
      // promise "0 reports" and then correct itself to 12 a moment later.
      expect(find.text('0'), findsOneWidget);
      expect(find.text('null'), findsNothing);
    });

    testWidgets('the first tab shares the page title left edge', (
      tester,
    ) async {
      await _pumpAt(
        tester,
        1400,
        AccountPageBody(
          builder: (_, s) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AccountPageTitle(
                title: 'My Submissions',
                subtitle: 'Subtitle',
              ),
              AccountTabBar(
                index: 0,
                stack: s,
                onChanged: (_) {},
                tabs: const [
                  AccountTab('Reports', count: 3),
                  AccountTab('Feedback', count: 2),
                ],
              ),
              const SizedBox(height: 16),
              AccountChipRow(
                value: 'all',
                onChanged: (_) {},
                chips: const [AccountChip('all', 'All')],
              ),
            ],
          ),
        ),
      );

      // Rule one, extended to the two controls a list page adds: title, tabs
      // and chips all begin at the same x. Tabs are separated by a GAP rather
      // than by internal padding precisely so this holds.
      final title = tester.getTopLeft(find.text('My Submissions')).dx;
      final tab = tester.getTopLeft(find.text('Reports')).dx;
      final chip = tester.getTopLeft(find.byType(AccountChipRow)).dx;

      expect(tab, closeTo(title, 0.5));
      expect(chip, closeTo(title, 0.5));
    });

    testWidgets('trailing shows with room and is dropped when stacked', (
      tester,
    ) async {
      Widget bar(bool stack) => AccountTabBar(
        index: 0,
        stack: stack,
        onChanged: (_) {},
        trailing: const Text('Refresh'),
        tabs: const [AccountTab('Reports'), AccountTab('Feedback')],
      );

      await _pumpAt(tester, 1200, AccountPageBody(builder: (_, s) => bar(s)));
      expect(find.text('Refresh'), findsOneWidget);

      await _pumpAt(tester, 420, AccountPageBody(builder: (_, s) => bar(s)));
      expect(find.text('Refresh'), findsNothing);
    });
  });

  group('chip row', () {
    testWidgets('reports the tapped value', (tester) async {
      final picked = <String>[];
      await _pumpAt(
        tester,
        1200,
        AccountPageBody(
          builder: (_, _) => AccountChipRow(
            value: 'all',
            onChanged: picked.add,
            chips: const [
              AccountChip('all', 'All'),
              AccountChip('replied', 'Replied'),
              AccountChip('awaiting', 'No reply yet'),
            ],
          ),
        ),
      );

      await tester.tap(find.text('No reply yet'));
      await tester.pump();
      expect(picked, ['awaiting']);
    });

    testWidgets('wraps instead of overflowing at a narrow width', (
      tester,
    ) async {
      await _pumpAt(
        tester,
        380,
        AccountPageBody(
          builder: (_, _) => AccountChipRow(
            value: 'all',
            onChanged: (_) {},
            chips: const [
              AccountChip('all', 'All'),
              AccountChip('pending', 'Pending'),
              AccountChip('in_progress', 'In Progress'),
              AccountChip('resolved', 'Resolved'),
            ],
          ),
        ),
      );

      // A horizontal scroller would hide options behind an edge with no hint
      // they are there; wrapping keeps every filter visible.
      expect(tester.takeException(), isNull);
      expect(find.byType(Wrap), findsOneWidget);
    });
  });

  group('empty state', () {
    testWidgets(
      'shows the action only when both label and callback are given',
      (tester) async {
        await _pumpAt(
          tester,
          1200,
          AccountPageBody(
            builder: (_, _) => const AccountEmptyState(
              icon: Icons.flag_outlined,
              title: 'No reports found',
              message: 'You have not submitted any reports yet.',
            ),
          ),
        );
        expect(find.byType(OutlinedButton), findsNothing);

        var retried = 0;
        await _pumpAt(
          tester,
          1200,
          AccountPageBody(
            builder: (_, _) => AccountEmptyState(
              icon: Icons.cloud_off_rounded,
              title: 'Could not load submissions',
              message: 'Check your connection and try again.',
              actionLabel: 'Try again',
              onAction: () => retried++,
            ),
          ),
        );
        await tester.tap(find.text('Try again'));
        await tester.pump();
        expect(retried, 1);
      },
    );

    testWidgets('sits on the same measure as a real card', (tester) async {
      const viewport = 1600.0;

      await _pumpAt(
        tester,
        viewport,
        AccountPageBody(
          builder: (_, _) => const AccountEmptyState(
            icon: Icons.flag_outlined,
            title: 'No reports found',
            message: 'Nothing here yet.',
          ),
        ),
      );
      final empty = tester.getRect(find.byType(AccountCard).first);

      await _pumpAt(
        tester,
        viewport,
        AccountPageBody(
          builder: (_, s) => AccountFieldSection(
            title: 'Account',
            stack: s,
            rows: [
              [_field('Email')],
            ],
          ),
        ),
      );
      final real = tester.getRect(find.byType(AccountCard).first);

      // An empty tab must occupy the list's footprint, not float loose on the
      // page background where it reads as a failed render.
      expect(empty.left, closeTo(real.left, 0.5));
      expect(empty.width, closeTo(real.width, 0.5));
    });
  });

  group('list skeleton', () {
    for (final width in <double>[400, 900, 1500]) {
      testWidgets('tabbed list skeleton lays out at ${width.toInt()}px', (
        tester,
      ) async {
        await _pumpAt(
          tester,
          width,
          const AccountPageSkeleton(tabs: true, chips: true, cards: 4),
          height: 2400,
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('its cards sit on the real card measure', (tester) async {
      const viewport = 1600.0;

      await _pumpAt(
        tester,
        viewport,
        const AccountPageSkeleton(tabs: true, chips: true, cards: 1),
        height: 1600,
      );
      final skeletonCard = tester.getRect(find.byType(AccountCard).first);

      await _pumpAt(
        tester,
        viewport,
        AccountPageBody(
          builder: (_, _) => const AccountEmptyState(
            icon: Icons.flag_outlined,
            title: 'No reports found',
            message: 'Nothing here yet.',
          ),
        ),
        height: 1600,
      );
      final realCard = tester.getRect(find.byType(AccountCard).first);

      // Same contract as the form skeleton: if these diverge, the page visibly
      // rearranges itself the moment the fetch resolves.
      expect(skeletonCard.left, closeTo(realCard.left, 0.5));
      expect(skeletonCard.width, closeTo(realCard.width, 0.5));
    });
  });

  group('prose', () {
    const longBody =
        'By accessing or using GovPulse, you agree to be bound by these Terms '
        'of Service and all applicable laws and regulations. If you do not '
        'agree with any part of these terms, you are not authorized to use '
        'this application or any of the services it provides.';

    testWidgets('body stops at the prose measure inside a wider card', (
      tester,
    ) async {
      await _pumpAt(
        tester,
        1600,
        AccountPageBody(
          builder: (_, _) => const AccountCard(
            padding: EdgeInsets.zero,
            child: AccountProseBlock(
              icon: Icons.gavel_rounded,
              title: 'Agreement to Use',
              body: longBody,
            ),
          ),
        ),
        height: 1200,
      );

      final card = tester.getRect(find.byType(AccountCard).first);
      final body = tester.getRect(find.text(longBody));

      // The card keeps the page measure so it stays aligned with every other
      // card on the page; only the TEXT stops early. A paragraph set across the
      // full 880 runs about 130 characters and the eye loses the next line.
      expect(card.width, closeTo(kAccountMaxWidth - 64, 1));
      expect(body.width, lessThanOrEqualTo(kAccountProseMeasure + 1));
    });

    testWidgets('body uses the full width when the page is narrower', (
      tester,
    ) async {
      await _pumpAt(
        tester,
        520,
        AccountPageBody(
          builder: (_, _) => const AccountCard(
            padding: EdgeInsets.zero,
            child: AccountProseBlock(title: 'Agreement', body: longBody),
          ),
        ),
        height: 1600,
      );

      // The cap is a ceiling, not a fixed width — a narrow window must not end
      // up with a 660px column of text overflowing it.
      expect(tester.takeException(), isNull);
      expect(
        tester.getRect(find.text(longBody)).width,
        lessThan(kAccountProseMeasure),
      );
    });

    testWidgets('the icon is optional', (tester) async {
      await _pumpAt(
        tester,
        1200,
        AccountPageBody(
          builder: (_, _) => const AccountCard(
            padding: EdgeInsets.zero,
            child: AccountProseBlock(title: 'Agreement', body: 'Short body.'),
          ),
        ),
      );
      expect(find.byType(Icon), findsNothing);
      expect(find.text('Agreement'), findsOneWidget);
    });
  });

  group('back link', () {
    // The bug this group exists for: Terms of Service and Privacy Policy are
    // pushed by `pushLegacy`, which writes no URL. So the rail kept reading
    // Settings, the address bar never moved, and the browser's Back button left
    // the account area instead of closing the page — the two screens had no way
    // out at all until this landed.

    testWidgets('fires its callback and names its destination', (tester) async {
      var popped = 0;
      await _pumpAt(
        tester,
        1200,
        AccountPageBody(
          builder: (_, _) =>
              AccountBackLink(label: 'Back to Settings', onTap: () => popped++),
        ),
      );

      // No visible words — the page title sits beside it — but the destination
      // still has to reach anyone who cannot see that title.
      expect(find.text('Back to Settings'), findsNothing);
      expect(find.bySemanticsLabel('Back to Settings'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pump();
      expect(popped, 1);
    });
  });

  group('page title back chevron', () {
    testWidgets('rides level with the title on a narrow page', (tester) async {
      // 500 gives a ~460 content box — under kAccountBackLabelAbove, so this is
      // the compact shape.
      await _pumpAt(
        tester,
        500,
        AccountPageBody(
          builder: (_, _) => AccountPageTitle(
            title: 'Privacy Policy',
            subtitle: 'How GovPulse protects your information.',
            onBack: () {},
            backLabel: 'Back to Settings',
          ),
        ),
      );

      // No visible words here: the title is right beside it, and a label would
      // be a second heading on the same line.
      expect(find.text('Back to Settings'), findsNothing);

      final chevron = tester.getRect(find.byIcon(Icons.arrow_back_rounded));
      final title = tester.getRect(find.text('Privacy Policy'));

      // Level, not stacked: on its own line a BARE chevron reads as a stray
      // control sitting above a page. Beside the title it reads as one header.
      expect(chevron.center.dy, closeTo(title.center.dy, 2.0));
      expect(chevron.right, lessThanOrEqualTo(title.left));
    });

    testWidgets('names its destination above the title on a wide page', (
      tester,
    ) async {
      await _pumpAt(
        tester,
        1200,
        AccountPageBody(
          builder: (_, _) => AccountPageTitle(
            title: 'Privacy Policy',
            subtitle: 'How GovPulse protects your information.',
            onBack: () {},
            backLabel: 'Back to Settings',
          ),
        ),
      );

      // Where it goes is the whole point of the wide shape: on a desktop pane
      // there is room to say it, and a detail page reachable from two different
      // lists is exactly where "back" alone is ambiguous.
      expect(find.text('Back to Settings'), findsOneWidget);

      final back = tester.getRect(find.byType(AccountBackLink));
      final title = tester.getRect(find.text('Privacy Policy'));
      final subtitle = tester.getRect(
        find.text('How GovPulse protects your information.'),
      );

      // Above, not beside — a ~210px control level with the heading would shove
      // it into the middle of the header.
      expect(back.bottom, lessThanOrEqualTo(title.top));
      // And nothing is indented past it any more, so the header's three lines
      // share one left edge.
      expect(title.left, closeTo(back.left, 0.5));
      expect(subtitle.left, closeTo(back.left, 0.5));
    });

    testWidgets('the wide shape lines pills up with the title', (tester) async {
      await _pumpAt(
        tester,
        1200,
        AccountPageBody(
          builder: (_, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AccountPageTitle(
                title: 'Privacy Policy',
                subtitle: 'Subtitle',
                onBack: () {},
                backLabel: 'Back to Settings',
              ),
              const AccountHeaderIndent(child: Text('Pending')),
            ],
          ),
        ),
      );

      // AccountHeaderIndent has to agree with the title about which shape is on
      // screen. Hand-written `kAccountBackChevron + kAccountBackChevronGap`
      // padding at a call site would be 50px wrong here.
      final title = tester.getRect(find.text('Privacy Policy'));
      final pill = tester.getRect(find.text('Pending'));
      expect(pill.left, closeTo(title.left, 0.5));
    });

    testWidgets('the compact shape indents pills to the title', (tester) async {
      await _pumpAt(
        tester,
        500,
        AccountPageBody(
          builder: (_, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AccountPageTitle(
                title: 'Privacy Policy',
                subtitle: 'Subtitle',
                onBack: () {},
                backLabel: 'Back to Settings',
              ),
              const AccountHeaderIndent(child: Text('Pending')),
            ],
          ),
        ),
      );

      // Same rule, the other way round: here the title IS indented past the
      // chevron, so the pills have to be too.
      final title = tester.getRect(find.text('Privacy Policy'));
      final pill = tester.getRect(find.text('Pending'));
      expect(pill.left, closeTo(title.left, 0.5));
    });

    testWidgets('the chevron takes over the page left edge', (tester) async {
      await _pumpAt(
        tester,
        1200,
        AccountPageBody(
          builder: (_, s) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AccountPageTitle(
                title: 'Privacy Policy',
                subtitle: 'Subtitle',
                onBack: () {},
                backLabel: 'Back to Settings',
              ),
              AccountFieldSection(
                title: 'Section',
                stack: s,
                rows: [
                  [_field('Email')],
                ],
              ),
            ],
          ),
        ),
      );

      // Rule one still holds, with the chevron standing in for the title as the
      // thing that starts the page. The heading indents behind it; the cards do
      // not move.
      final back = tester.getTopLeft(find.byType(AccountBackLink)).dx;
      final card = tester.getTopLeft(find.byType(AccountCard).first).dx;
      expect(back, closeTo(card, 0.5));
    });

    testWidgets('no onBack means no chevron at all', (tester) async {
      await _pumpAt(
        tester,
        1200,
        AccountPageBody(
          builder: (_, _) => const AccountPageTitle(
            title: 'Edit Profile',
            subtitle: 'A rail destination.',
          ),
        ),
      );

      // The rail pages must not grow one by accident.
      expect(find.byType(AccountBackLink), findsNothing);
      expect(find.byIcon(Icons.arrow_back_rounded), findsNothing);
    });
  });
}
