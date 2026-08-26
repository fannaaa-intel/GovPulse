// REGRESSION GUARD — the bell badge must not survive the session it belongs to.
//
// `NotificationService` is entirely STATIC, so on web (one long-lived process,
// one set of statics across sign-in cycles) its state outlives any single
// account unless something explicitly drops it. `stopRealtime` is that
// something — it runs from main.dart on `AuthChangeEvent.signedOut`, and from
// `startRealtime` when a DIFFERENT uid signs in.
//
// The bug: it emptied `notifications` but left `_unreadOutsideWindow` set.
// The badge is `unread rows + _unreadOutsideWindow` (see `_sync`), so a user
// with unread notifications beyond the 200-row load window logged out and left
// their count on the bell — for the signed-out app, and then for whoever signed
// in next.
//
// ── NON-VACUOUS ───────────────────────────────────────────────────────────
// Verified by reverting the `_unreadOutsideWindow = 0` line in `stopRealtime`:
// the first case fails with `Expected: 0, Actual: 7`. A case that still passes
// with the fix reverted proves nothing — re-prove this way after any change to
// the badge math.
//
// ── NO NETWORK ────────────────────────────────────────────────────────────
// Nobody signs in, so `stopRealtime`'s channel teardown is a no-op on a null
// channel and `_sync` is pure arithmetic over the seeded statics. Supabase is
// never initialized here: `stopRealtime` touches no Supabase getter, and the
// service's `_uid` guard already swallows the uninitialized-SDK assert.
import 'package:flutter_test/flutter_test.dart';

import 'package:govpulse/features/home/screen/notification_popup.dart';

void main() {
  tearDown(NotificationService.debugReset);

  test('signing out clears the out-of-window unread count, not just the list',
      () {
    // A user with more unread history than one load window holds: the list half
    // of the badge is empty, the out-of-window half is not.
    NotificationService.debugSeedUnreadOutsideWindow(7);
    expect(NotificationService.unread.value, 7,
        reason: 'precondition — the badge counts rows it has not loaded');

    NotificationService.stopRealtime();

    // THE REGRESSION. This used to stay at 7.
    expect(
      NotificationService.unread.value,
      0,
      reason: 'a signed-out app must not show a badge; the count belongs to the '
          'account that just left',
    );
  });

  test('the next account does not inherit the previous badge', () {
    NotificationService.debugSeedUnreadOutsideWindow(12);
    NotificationService.stopRealtime(); // sign-out, or a uid change

    expect(
      NotificationService.unread.value,
      0,
      reason: 'startRealtime calls stopRealtime when the uid changes, so a '
          'leftover count here lands on the incoming user',
    );
  });

  test('clearing the list alone would not have been enough', () {
    // Pins WHY the fix is a separate line: the badge has two independent
    // halves, and only one of them is visible in `notifications`.
    NotificationService.debugSeed(const []);
    NotificationService.debugSeedUnreadOutsideWindow(3);

    expect(NotificationService.notifications, isEmpty);
    expect(NotificationService.unread.value, 3,
        reason: 'an empty list with a non-zero badge is exactly the state the '
            'old stopRealtime left behind');

    NotificationService.stopRealtime();
    expect(NotificationService.unread.value, 0);
  });
}
