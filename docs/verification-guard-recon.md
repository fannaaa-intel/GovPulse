# Verification Guard — Trace for the Feed Empty-State CTA

*Read-only recon, written 2026-08-13. No code changed.*

Traces what happens when a citizen taps **"Report an Issue"** on the newsfeed's
empty state, so the three verification states can be verified by hand.

---

## 0. Summary

The CTA is **not** bespoke. It calls the same dispatcher every rail row and every
quick-action card calls, and the gate it trips is the one shared by all five
quick actions. Nothing about `report` is special except its message wording and
its restriction key.

**One finding worth knowing before testing** (§6): a **pending** citizen is
gated identically to an unverified one — same dialog, same enabled **Verify**
button — and that button *does* let them re-enter the verification wizard. They
are only stopped several screens later, at submit. That is a pre-existing
product behaviour of the shared dialog, not something the CTA introduced, and it
differs from the left rail's "Verify now" affordance, which *does* refuse pending
up front.

---

## 1. The CTA entry path

```
FeedEmptyState  (core/widgets/Home/Newsfeed/feed_empty_state.dart)
  └─ onReportIssue                     ← null unless embedded && !isGuest
       └─ CitizenShell.runQuickAction(context, 'report')
            └─ context.findAncestorStateOfType<_CitizenShellState>()
                 └─ _handleQuickAction('report')
```

Wired at [news_feed_screen.dart](../lib/features/home/newsfeed/news_feed_screen.dart),
in `_buildWebEmptyState()` — the **web arm only**. The mobile arm still calls
`_buildEmptyState(width)`, which has no CTA at all, so none of this is reachable
from the Flutter mobile app.

`runQuickAction` is a no-op when there is no `CitizenShell` above the context
(the guest feed at `/newsfeed`), but the CTA is not rendered there anyway —
`onReportIssue` is null unless `widget.embedded && !widget.isGuest`.

## 2. What `_handleQuickAction('report')` does

[citizen_shell.dart:566](../lib/features/home/shell/citizen_shell.dart#L566).
In order:

| # | Step | For `'report'` |
|---|---|---|
| 1 | Resolve title + icon | `('Report an Issue', Icons.report_gmailerrorred_rounded)`; bails if title is empty (unknown key) |
| 2 | Pick the gate message | *"Only verified Aparri citizens can submit a report. Please complete your identity verification first."* |
| 3 | **Verification gate** | `if (!await _requireVerified(gateMessage)) return;` |
| 4 | `mounted` re-check | after the await |
| 5 | **Restriction gate** | `citizenGuardAllow(context, 'reports')` |
| 6 | `mounted` re-check | |
| 7 | Read `_username` | deliberately AFTER the gate, so it can never be the `''` of the loading window |
| 8 | Open the form | `showCitizenFormDialog` hosting `ReportIssueForm(username:, embedded: true, guard:)` with a `FormDialogGuard` for discard confirmation |

Both gates run **before** anything opens, so a blocked citizen never sees a form
they cannot submit.

## 3. The gate itself — `_requireVerified`

[citizen_shell.dart:508](../lib/features/home/shell/citizen_shell.dart#L508)
(pre-existing; not added for the CTA).

```dart
Future<bool> _requireVerified(String message) async {
  final profile = ref.read(userProfileProvider).valueOrNull;

  if (profile == null) {            // profile not loaded yet
    _notifyProfileStillLoading();
    return false;
  }
  if (profile.isVerified) return true;

  await showVerificationRequiredDialog(
    context,
    isVerified: false,
    username: profile.username ?? '',
    message: message,
  );
  return false;
}
```

### What is actually checked

`UserProfile.isVerified`, which is exactly:

```dart
bool get isVerified => verifStatus == VerifStatus.verified;
```

`VerifStatus` is `enum VerifStatus { none, pending, verified }`
([home_enums.dart:6](../lib/core/widgets/Home/home_enums.dart#L6)).

It is derived in `UserProfileNotifier._fetch` from the **most recent**
`verification_submissions` row for the user (`order('created_at', descending)
.limit(1)`), at [user_profile_provider.dart:124-126](../lib/core/providers/user_profile_provider.dart#L124-L126):

| `verification_submissions.status` | `VerifStatus` | Gate |
|---|---|---|
| `'approved'` | `verified` | ✅ **passes** |
| `'pending'` | `pending` | ❌ blocked |
| no row at all (`'none'`) | `none` | ❌ blocked |
| anything else (e.g. `'rejected'`) | `none` (fallthrough) | ❌ blocked |

**Only `approved` passes.** `pending` and `none` are treated identically by this
gate — it branches on the boolean, never on the enum.

`CitizenGuard` is **not** consulted here. It is the *second*, separate gate.

### The second gate — `citizenGuardAllow`

[citizen_guard_modals.dart:38](../lib/core/widgets/citizen_guard_modals.dart#L38):

```dart
bool citizenGuardAllow(BuildContext context, String feature) {
  if (!CitizenGuard.I.isRestricted(feature)) return true;
  showFeatureBlockedModal(context, feature);
  return false;
}
```

For the CTA the feature key is **`'reports'`**. This is admin-imposed restriction
(and account suspension), entirely independent of verification. Order is
deliberate and matches mobile: tell an unverified citizen to verify — something
they can act on — rather than tell them a feature they never had is restricted.

## 4. Where the dialog and the wizard live

- **Dialog:** `showVerificationRequiredDialog` in
  [core/widgets/modal/verification_required_dialog.dart:15](../lib/core/widgets/modal/verification_required_dialog.dart#L15).
  Because `_requireVerified` passes `isVerified: false` explicitly, the dialog
  does **not** re-query Supabase — it goes straight to rendering.
- **Wizard entry:** the **Verify** button pops the dialog, then
  `pushLegacyOn(navigator, '/verification', arguments: username)`.
- **Route:** `case '/verification'` in
  [core/router/app_router.dart:420](../lib/core/router/app_router.dart#L420) →
  `NetworkWrapper(child: VerificationScreen(username: username))`.
- **Flow:** `lib/features/profileVerification/` — intro (`verification_screen.dart`)
  → identity → ID selection → upload ID → photo instruction → scan → face scan →
  review. Submission happens in `verification_face_scan_screen.dart`.

Deliberately **not** a go_router route: the wizard passes `Uint8List` ID images
between steps, which don't belong in an address bar.

## 5. Is `'report'` special? — No

Every quick action funnels through the same `_handleQuickAction`, and the
verification gate is called once, unconditionally, before the switch. Only the
message and the restriction key vary:

| Key | Gate message subject | Restriction key | Verification-gated? |
|---|---|---|---|
| `report` | "submit a report" | `reports` | ✅ |
| `suggestion` | "submit a suggestion" | `suggestions` | ✅ |
| `feedback` | "submit feedback" | `feedback` | ✅ |
| `chat` | "chat with an agent" | `ai_chat` | ✅ |
| `events` | "browse community events" | *(none)* | ✅ |

Same five keys are used by the left rail (`_kQuickActions`), the right sidebar
(`HomeQuickActionsSectionWeb`), the new Upcoming Events "View All"
(`_handleQuickAction('events')`), and now the empty-state CTA. **The CTA uses the
standard shared gate — there is no bespoke path.**

Note `events` is verification-gated on web but *not* on mobile; the code marks
this as a deliberate product call, not an oversight.

---

## 6. Manual test checklist — exactly what you should see

Tapping **"Report an Issue"** on the empty feed, at ≥1280px (the CTA renders at
any shell width, but the rails need ≥1280).

### A. Verified citizen — `verification_submissions.status = 'approved'`

1. No dialog, no toast.
2. A large centred modal opens over the still-visible feed — the shell, nav and
   both rails stay mounted behind it.
3. Header: report icon + title **"Report an Issue"**, with a close (×) button.
4. Body: the `ReportIssueForm`, scrolling inside the dialog, no page hero.
5. Closing with unsaved input triggers the form's **discard confirmation**
   (via `FormDialogGuard`).
6. The URL stays `/#/home` — no history entry, no navigation.

**Fail signals:** any verification dialog; a full-page navigation; the address
bar changing.

### B. Unverified — no submission row (`VerifStatus.none`)

1. No form opens.
2. A centred dialog, max width 440px, dimmed backdrop, fading and sliding up
   over ~180ms.
3. Verified-badge artwork (`assets/images/verification/verified.webp`).
4. Title: **"Verification Required"**.
5. Body, verbatim: *"Only verified Aparri citizens can submit a report. Please
   complete your identity verification first."*
6. Two buttons: **Cancel** (outlined) and **Verify** (solid blue).
7. Backdrop is dismissible (`barrierDismissible: true`) — tapping outside closes it.
8. **Cancel** → dialog closes, back to the feed, nothing else happens.
9. **Verify** → dialog closes, then the **verification intro screen** opens.

**Fail signals:** the report form opening; the message naming a different action
(e.g. "submit a suggestion" — that would mean the wrong key was dispatched); a
`Verify` tap that goes nowhere (would mean `username` was null).

### C. Pending — `status = 'pending'` (`VerifStatus.pending`)

**Steps 1–9 are identical to state B.** Same dialog, same message, same enabled
Verify button. The gate branches on `isVerified`, so it cannot tell pending from
none.

The difference appears only if you continue:

10. **Verify** → the verification wizard **opens normally**.
    `VerificationScreen` has no status check in `initState`; it is a static intro.
11. You can walk the whole wizard — identity, ID selection, upload, photo
    instruction, scan, face scan.
12. Rejection lands at **submit**, in
    [verification_face_scan_screen.dart:339-352](../lib/features/profileVerification/verification_face_scan_screen.dart#L339-L352),
    which pre-checks for an existing `pending`/`approved` row and throws:
    > **"You already have a pending verification. Please wait for our team to review it."**

So a pending citizen is told to verify, allowed to re-enter, and refused at the
end. Worth deciding whether that's acceptable; it is **not** caused by the CTA —
every quick action, on web and mobile, behaves this way, because it is the shared
dialog's Verify button.

**Contrast — the left rail's "Verify now" pill** does gate on the enum, at
`_startVerification` ([citizen_shell.dart](../lib/features/home/shell/citizen_shell.dart)):

```dart
if (profile.verifStatus != VerifStatus.none) return;
```

and the rail only renders the affordance when `verif == VerifStatus.none`. So the
rail refuses pending up front while the dialog does not — the two disagree today.

### D. Edge — profile still loading

Tap during the window between first paint and `userProfileProvider` resolving
(easiest on a cold load / hard refresh, then tap immediately).

1. No dialog, no form.
2. An **info snackbar**: *"Still loading your profile — please try that again in
   a moment."*
3. Tapping again after the profile lands behaves as A/B/C.

This is `profile == null`, checked *before* `isVerified`, so a verified citizen
who taps too early gets the toast rather than being wrongly told to verify — and
the wizard can never be launched with an empty username.

### E. Edge — restricted or suspended (independent of verification)

For a **verified** citizen whom an admin has restricted from `reports`:

1. Passes the verification gate.
2. `citizenGuardAllow(context, 'reports')` returns false and shows the
   **feature-blocked modal** instead of the form.

An **unverified** restricted citizen sees the **verification** dialog, not the
restriction modal — verification is checked first, by design.

If the account is **suspended**, `CitizenGuard` raises its blocking modal and
signs the user out; on web that runs the shared session teardown and the auth
guard redirects to `/login`.

---

## 7. Quick reference — files

| Concern | File |
|---|---|
| CTA widget | `core/widgets/Home/Newsfeed/feed_empty_state.dart` |
| CTA wiring (web arm only) | `features/home/newsfeed/news_feed_screen.dart` → `_buildWebEmptyState()` |
| Public accessor | `features/home/shell/citizen_shell.dart` → `CitizenShell.runQuickAction` |
| Dispatcher | same file → `_handleQuickAction` (line 566) |
| Verification gate | same file → `_requireVerified` (line 508) |
| Loading toast | same file → `_notifyProfileStillLoading` |
| Rail verify affordance | same file → `_startVerification` |
| Status source | `core/providers/user_profile_provider.dart` |
| Status enum | `core/widgets/Home/home_enums.dart` |
| Dialog | `core/widgets/modal/verification_required_dialog.dart` |
| Restriction gate | `core/widgets/citizen_guard_modals.dart` → `citizenGuardAllow` |
| Guard state | `core/services/citizen_guard.dart` |
| Wizard | `features/profileVerification/` (submit check in `verification_face_scan_screen.dart`) |
| Legacy route | `core/router/app_router.dart` → `case '/verification'` |
