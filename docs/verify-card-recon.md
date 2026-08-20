# "Verify Your Account" Rail Card — Recon

*Read-only, written 2026-08-13. No code changed.*

Recon for adding a "Verify Your Account" card at the bottom of the citizen web
left rail.

---

## 0. The one blocking conflict

**A "Verify Now" button for PENDING cannot reuse `_startVerification` — it would
be a dead button.**

```dart
void _startVerification() {
  final profile = ref.read(userProfileProvider).valueOrNull;
  if (profile == null) { _notifyProfileStillLoading(); return; }
  if (profile.verifStatus != VerifStatus.none) return;   // ← pending: silent no-op
  pushLegacy(context, '/verification', arguments: profile.username ?? '');
}
```

A pending citizen tapping it gets **nothing** — no navigation, no dialog, no
toast. Silent.

This is not an oversight. The existing rail deliberately withholds the affordance
from pending, and says so at
[citizen_shell.dart:935-941](../lib/features/home/shell/citizen_shell.dart#L935-L941):

> *"Pending is deliberately not actionable, matching mobile, where the Verify
> button is present but disabled while a submission is under review."*

And the top profile card gates it the same way:

```dart
canVerify: profile != null && verif == VerifStatus.none,
```

So the request — *"UNVERIFIED and PENDING → … a 'Verify Now' button"* — conflicts
with a documented product decision that is currently consistent across the web
rail **and** mobile. Options in §7; my recommendation is that pending gets the
card but not the button.

---

## 1. Where the left rail is built, and the existing Verify affordance

**`_leftRail`** — [citizen_shell.dart:789](../lib/features/home/shell/citizen_shell.dart#L789),
a private method on `_CitizenShellState`.

Structure:

```
SizedBox(width: 288)
└─ SingleChildScrollView            ← the rail owns its scrolling
   └─ Padding(20, 20, 8, 20)
      └─ Column(mainAxisSize.min, crossAxisAlignment.stretch)
         ├─ _profileCard(...)       ← avatar, name, status pill  ◄ VERIFY LIVES HERE
         ├─ SizedBox(16)
         ├─ [if showNav]        'NAVIGATE'      + tab rows
         ├─ 'ACCOUNT'           + _railItems rows
         └─ [if showQuickActions] 'QUICK ACTIONS' + _kQuickActions rows
```

### The existing "Verify now" is in the TOP profile block

It is **not** a separate card. It lives inside `_profileCard` → `_statusPill`
([citizen_shell.dart:942](../lib/features/home/shell/citizen_shell.dart#L942)),
rendered as a trailing element on the status line:

`● Not verified · Verify now ›`

`_statusPill` renders a coloured dot + label for all three states, and appends
the tappable "Verify now ›" **only when `canVerify` is true**. The whole row
becomes an `InkWell` only in that case.

| State | Pill renders | Tappable? |
|---|---|---|
| verified | ● Verified (`CitizenUi.success`) | no |
| pending | ● Pending (`CitizenUi.pending`) | no |
| none | ● Not verified (`textMuted`) + "Verify now ›" | **yes** |
| profile still loading (`null`) | ● Not verified | no — guarded by `profile != null` |

A new bottom card would therefore be the **second** verify affordance in the same
rail for the unverified state. Worth deciding whether the top one stays (§7).

## 2. Verification-status source

Identical to what `_profileCard` already reads — no new source needed:

```dart
final profile = ref.watch(userProfileProvider).valueOrNull;   // in build()
final verif = profile?.verifStatus ?? VerifStatus.none;
```

- Provider: `userProfileProvider` (Riverpod `AsyncNotifier<UserProfile>`),
  `core/providers/user_profile_provider.dart`
- Enum: `VerifStatus { none, pending, verified }`,
  `core/widgets/Home/home_enums.dart`
- Derived from the newest `verification_submissions` row:
  `approved → verified`, `pending → pending`, anything else / no row → `none`

`build()` already computes both, at
[citizen_shell.dart:1139-1140](../lib/features/home/shell/citizen_shell.dart#L1139-L1140):

```dart
final profile = ref.watch(userProfileProvider).valueOrNull;
final verif = profile?.verifStatus ?? VerifStatus.none;
```

### ⚠️ The cold-load trap — must be handled

`verif` falls back to `none` while the profile is loading. A card keyed on
`verif == VerifStatus.none` alone would **flash the green "Verify Your Account"
card at a verified citizen on every cold load**. The existing code guards this
with `profile != null` and flags it explicitly in a comment
([citizen_shell.dart:918-923](../lib/features/home/shell/citizen_shell.dart#L918-L923)).

The new card needs the same guard: render **nothing** in the slot until
`profile != null`.

## 3. The verify-flow entry point

**`_startVerification`** — [citizen_shell.dart:487](../lib/features/home/shell/citizen_shell.dart#L487).
Three guards, then `pushLegacy(context, '/verification', arguments: username)`:

1. `profile == null` → `_notifyProfileStillLoading()` (info snackbar), return
2. `verifStatus != VerifStatus.none` → **silent return** (this catches pending *and* verified)
3. otherwise → push the wizard

### Does it handle pending? — Yes, by refusing, silently

And this is exactly where it **differs from the dialog path** documented in
[verification-guard-recon.md](verification-guard-recon.md):

| Entry point | Pending behaviour |
|---|---|
| `_startVerification` (rail "Verify now") | **Refuses.** Silent no-op. Affordance isn't rendered for pending anyway. |
| `showVerificationRequiredDialog` → Verify button (quick-action gate) | **Allows.** Pushes `/verification` unconditionally when `username != null`; the citizen walks the whole wizard and is refused at submit. |

The two disagree today. That pre-existing inconsistency is what makes the pending
case a decision rather than an implementation detail.

## 4. Is `_leftRail` shared with mobile? — **No. Web-only.**

`_leftRail` is a private method on `_CitizenShellState`, inside `CitizenShell`,
which is built **only** by `citizenRouter` / `GovPulseWebApp`
(`citizen_shell_router.dart`). The file header states it plainly:

> *"This is what citizens land on after signing in on web. The mobile app never
> builds it — it keeps HomePage and the Navigator 1.0 table."*

**No default-flag pattern is needed.** Adding a child to this Column cannot reach
a mobile code path.

For contrast, the shell deliberately does **not** reuse `HomeNavDrawer` for its
drawer, precisely because that widget's file *is* shared with mobile
([citizen_shell.dart:1056-1060](../lib/features/home/shell/citizen_shell.dart#L1056-L1060)).
Same reasoning protects us here.

## 5. Scroll, layout, and what sits at the rail bottom

### There is no bottom-pinned user chip in the rail

My earlier recon noted a user chip at the bottom-left of the **mockup**. In the
**code** there is none: `_profileCard` is the **first** child of the rail Column,
at the top, and the Column ends with the quick-actions block. The user chip that
exists in the product is in the **top nav** (`HomeTopNav`, collapsing to an
avatar below `_kAvatarOnlyChipBelow` = 600px), not in the rail.

**Nothing at the rail bottom can be displaced.** Appending a child is purely
additive.

### Scroll behaviour

The rail is a `SingleChildScrollView` over a `mainAxisSize.min` Column, so it
shrink-wraps and only scrolls once content would exceed the height. The existing
comment measures the rail at **~760px** of content and notes a 1366×768 laptop
leaves about **708px** — i.e. **it already scrolls at that size today**.

A compact card (~90–110px including its spacer) makes the rail ~850–870px, so:
- tall windows: still no scroll, card visible without scrolling
- 1366×768: already scrolling; the card extends the scroll extent and sits below
  the fold until scrolled
- **nothing above it moves or breaks**

The `mainAxisSize.min` + top-hugging behaviour is unaffected — that's what pins
the rail under the nav rather than centring it.

### ⚠️ Two call sites, not one

`_leftRail` is built in **two** places, so a child added to it appears in both:

| Caller | When | Params |
|---|---|---|
| [line 1267](../lib/features/home/shell/citizen_shell.dart#L1267) — inline rail | `!isDrawerMode` (≥1024) | `showNav: !showNavLinks`, `showQuickActions: !shellHasRightSidebar(layout)` |
| [line 1070](../lib/features/home/shell/citizen_shell.dart#L1070) — `_shellDrawer` | <1024 | `inDrawer: true`, `showNav: true`, `showQuickActions: true` |

This is almost certainly what you want (the card should be in the drawer too),
but it means the card renders in the hamburger drawer on narrow web as well as in
the desktop rail. If it should be desktop-only, that needs an explicit flag.

**Drawer consequence:** any tap handler must be wrapped in `_fromDrawer(...,
inDrawer: inDrawer)`, exactly as `_profileCard` already does for its Verify
affordance:

```dart
onTap: _fromDrawer(_startVerification, inDrawer: inDrawer),
```

Without it, the wizard would open behind a still-open drawer.

### Where "bottom" lands

Appending to the Column's `children` puts the card:
- **≥1280** — below the ACCOUNT section (quick actions are on the right)
- **1024–1280** — below the QUICK ACTIONS section (they've moved into the rail)
- **<1024 drawer** — below QUICK ACTIONS

Consistently the last element in all three, which matches the mockup's position.

---

## 6. Tokens available for the green card

All present in `CitizenUi` — no new colours, no `app_colors.dart` edit:

| Need | Token |
|---|---|
| green accent / button fill | `accentGreen` (`#2ECC71`) |
| verified text green | `success` (`#15803D`) |
| pending amber | `pending` (`#B45309`) / `warn` (`#F59E0B`) |
| card radius / control radius | `cardRadius` 14 / `controlRadius` 10 |
| copy | `textPrimary`, `textMuted` |
| border | `border` |

A green wash can be derived as `CitizenUi.accentGreen.withValues(alpha: .10)` —
the same approach already used by the download card added last pass.

---

## 7. Decisions needed before I write code

### D1 — Pending: what does the card do? ← **the blocker**

| Option | Behaviour | Verdict |
|---|---|---|
| **A. Card, no button** *(recommended)* | Pending sees the card with an "in review" line and **no** button — e.g. *"Your verification is being reviewed."* | Honest, matches the existing documented stance and mobile, no dead control |
| B. Button wired to `_startVerification` | Renders a "Verify Now" button that does **nothing** | ❌ dead button — do not ship |
| C. Button wired around the guard | Would need a new path bypassing `_startVerification`'s check | ❌ contradicts your "do not bypass any gate" rule |
| D. Relax `_startVerification` to allow pending | Changes the **top** affordance's behaviour too, and lets pending walk to a submit-time rejection | Possible, but it's a product change beyond this card |

### D2 — Two verify affordances for the unverified state?

Unverified citizens would see "Verify now ›" in the top profile pill **and** a
"Verify Now" button in the bottom card. Options: keep both (mockup-faithful,
slightly redundant), or suppress the top pill's affordance when the card is
showing. You said keep the existing profile block where it is — I read that as
"keep both", but confirm.

### D3 — Verified state content

You want the slot to show a verified indicator instead. Confirm the copy — e.g. a
compact green "Account Verified" row with a check icon, no button. Also confirm
whether it should show at all when verified, or collapse to nothing (the mockup
has no verified variant to copy from).

### D4 — Drawer

Confirm the card should also appear in the <1024 hamburger drawer (default if I
add it to `_leftRail`), or be inline-rail-only.

---

## 8. Proposed shape, pending your answers

- New widget file: `core/widgets/Home/sections/Web/rail_verify_card.dart`,
  taking `VerifStatus`, an `onVerify` callback, and rendering nothing when the
  profile is null.
- Mounted as the **last child** of `_leftRail`'s Column, wrapped in
  `_fromDrawer(_startVerification, inDrawer: inDrawer)`.
- Compact: ~90–110px tall, icon + title + one line + one button.

That is a two-file change — one new file, plus ~6 additive lines in `_leftRail`.
No rail swap, no column reorder, no enum change, no mobile reach.

**No code written. Waiting on D1–D4.**
