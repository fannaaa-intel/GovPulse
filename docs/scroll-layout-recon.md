# Facebook-style Scroll — Shell Layout Recon

*Read-only, written 2026-08-13. No code changed.*

---

## 0. Headline: you already have ~80% of this, and one real bug

The shell is **already per-column**, not a single page scroll. There is no
page-level `SingleChildScrollView` around the three columns — the `Row` sits
inside an `Expanded` that fills the height under the top nav, and each column
manages its own vertical behaviour.

So of the target behaviour:

| Target | Status |
|---|---|
| Left rail pinned, scrolls internally when too tall | ✅ **already works** |
| Centre is the only column that scrolls with the feed | ✅ **already works** |
| Page does not scroll as one block | ✅ **already true** |
| Right rail pinned, scrolls internally when too tall | ❌ **missing — and it overflows today** |
| Scrollbars hidden | ❌ missing |
| Events cap 2 | ❌ currently 3 |

**The right rail has no scroll view at all**, and at common laptop sizes its
content is already taller than the viewport — see §3. That is very likely a
visible `RenderFlex overflow` stripe on a 1366×768 screen right now.

---

## 1. Where the layout is assembled, and who owns scrolling

[citizen_shell.dart:1169-1300](../lib/features/home/shell/citizen_shell.dart#L1169-L1300),
inside `_CitizenShellState.build`:

```
Scaffold(backgroundColor: CitizenUi.pageBg)
└─ body: Stack
   ├─ SafeArea
   │  └─ Column(crossAxisAlignment.stretch)
   │     ├─ Row  ── [hamburger?] + HomeTopNav            ← fixed height, never scrolls
   │     └─ Expanded                                      ← everything below fills the rest
   │        └─ Row(crossAxisAlignment: START)             ← ★ the three columns
   │           ├─ [if !isDrawerMode] _leftRail(...)
   │           ├─ Expanded → LayoutBuilder → MediaQuery → SizedBox.expand(navigationShell)
   │           └─ [if shellHasRightSidebar] _rightSidebar()
   └─ CitizenDockedChat                                   ← floats over, no barrier
```

`crossAxisAlignment: CrossAxisAlignment.start` is the load-bearing detail. In a
`Row`, a non-flex child under `start` gets **loose** vertical constraints
(`0 … maxHeight`). That is what makes each rail hug the top and size to its own
content — and it is also what decides whether a rail scrolls or overflows.

### Per-column scroll ownership today

| Column | Structure | Behaviour under loose constraints |
|---|---|---|
| **Left rail** | `SizedBox(288)` → **`SingleChildScrollView`** → `Padding` → `Column(min)` ([:795](../lib/features/home/shell/citizen_shell.dart#L795)) | Shrink-wraps when short; **scrolls internally** when content exceeds the height. Already the target behaviour. |
| **Centre** | `Expanded` → `LayoutBuilder` → `MediaQuery` override → `SizedBox.expand(navigationShell)` ([:1269](../lib/features/home/shell/citizen_shell.dart#L1269)) | Fills the height; the *pane* owns the scroll. `NewsFeedBody(embedded: true)` returns its own `SingleChildScrollView`. Already correct. |
| **Right rail** | `SizedBox(340)` → `Padding` → **`Column(mainAxisSize.min)`** — **no scroll view** ([:1097](../lib/features/home/shell/citizen_shell.dart#L1097)) | Shrink-wraps when short; **overflows** when content exceeds the height. This is the gap. |

The `// The centre must fill the height — it owns the scrolling.` comment at
[:1260](../lib/features/home/shell/citizen_shell.dart#L1260) confirms the design
intent was already Facebook-style; the right rail simply never got its scroll
view, presumably because it held only one short card when it was written.

## 2. Does this touch breakpoints, drawer mode, or gating? — No

The change is contained to scroll structure:

- **Breakpoints** — `resolveShellLayout` / `shellHasRightSidebar` /
  `shellHasLeftRail` live in `nav_band.dart` and are only *read* here. Wrapping
  `_rightSidebar`'s Column in a scroll view changes nothing about which layout is
  chosen. `ShellLayout.threeColumn` is `width >= kShellThreeColumnMin` (1280).
- **Drawer mode** — `isDrawerMode` selects `_shellDrawer` vs the inline rail. The
  right sidebar is not rendered in drawer mode at all
  (`if (shellHasRightSidebar(layout))`), so it cannot be affected.
- **Gating** — `_requireVerified`, `citizenGuardAllow`, `_handleQuickAction`,
  `CitizenGuard`, `_FeedOrRestricted` are all untouched by a scroll wrapper.
- **Column order / content** — nothing moves between rails. No rail swap.

## 3. The right-rail overflow, measured

Rough content height of `_rightSidebar` after the recent additions:

| Item | ≈ height |
|---|---|
| Padding (20 top + 20 bottom) | 40 |
| QUICK ACTIONS heading | ~23 |
| 5 action rows @ ~76px + 4 × 6px gaps | ~404 |
| Gap | 16 |
| `HomeAppDownloadCard` | ~165 |
| Gap | 16 |
| `HomeUpcomingEventsCard` (3 events) | ~185 |
| **Total** | **≈ 849px** |

Available on a 1366×768 browser: 768 − browser chrome (~90) − top nav (~64)
≈ **610px**. On a 1080p maximised window: ~1040 − 64 ≈ **890px** — only just
clears.

So the rail overflows by roughly 240px on a 1366×768 laptop **today**. The flat
quick-actions restyle (taller rows) and the two new cards each pushed this up.
Dropping the events cap 3 → 2 removes ~60px, which helps but does not fix it —
the scroll view is what fixes it.

## 4. Is any of this shared with mobile? — No

Unlike `HomeQuickActionsSectionWeb` (which turned out to be reachable from native
tablets via `_buildWebBody`), **everything in scope here is web-only**:

| Element | Scope |
|---|---|
| `_CitizenShellState.build`, `_leftRail`, `_rightSidebar` | private to `CitizenShell`, built **only** by `citizenRouter` / `GovPulseWebApp` |
| `NewsFeedBody(embedded: true)` centre scroll | the `embedded` branch is only entered from the shell |

The mobile app builds `HomePage` and the Navigator 1.0 table; it never constructs
`CitizenShell`. **No default-flag pattern is needed for the layout work** — the
`flat` flag was needed because that *widget* was shared, whereas these are shell
members.

### ⚠️ One place where a flag-equivalent IS needed: scrollbar hiding

Hiding scrollbars must **not** be done at the `MaterialApp` level.
`GovPulseWebApp` currently sets no `scrollBehavior`, and `citizenRouter` also
serves **`/admin` and `/staff`** — so a `MaterialApp.router(scrollBehavior: ...)`
would silently restyle scrollbars in **both consoles**, violating the
citizen-web-only rule. It would also hit the auth screens.

The hiding therefore has to be **scoped to the shell subtree**, via a
`ScrollConfiguration` inside `CitizenShell.build`. That covers all three columns
and every branch pane beneath them, and nothing outside.

There is one existing explicit `Scrollbar(` in the codebase
([home_community_section_web.dart:104](../lib/core/widgets/Home/sections/Web/home_community_section_web.dart#L104)).
It is an *explicit* widget, so a `ScrollConfiguration` will **not** remove it —
it is inside `HomeCommunitySectionWeb`, which the shell does not mount (only
HomePage does), so it is out of scope and unaffected either way.

## 5. Risk to <1280 drawer mode and narrow web

Low, and mostly structural rather than behavioural:

- **`ShellLayout.drawer` (<1024)** — no inline rail, no right sidebar. The
  `_shellDrawer` hosts `_leftRail`, and its comment at
  [:1067](../lib/features/home/shell/citizen_shell.dart#L1067) warns that the
  drawer deliberately adds **no** scroll view because `_leftRail` owns one and
  nesting two in the same axis gives the inner one an unbounded height. **Any
  scroll wrapper I add must go in `_rightSidebar` only, not in `_leftRail`**, or
  that constraint is violated.
- **`railLabels` / `railIcons` (1024–1280)** — left rail inline, no right
  sidebar; the rail carries the quick actions instead (`showQuickActions:
  !shellHasRightSidebar(layout)`), which makes it *taller* than at ≥1280. It
  already has its scroll view, so it is fine, and adding a right-rail scroll view
  cannot affect a band where the right rail does not render.
- **Narrow single-column web** — same as drawer mode: right sidebar absent.

The one genuine risk is **nesting scroll views in the same axis**, which produces
an unbounded-height assertion. Avoided by only touching `_rightSidebar`, whose
current child is a plain `Column`.

---

## 6. Proposed plan

Three changes, all additive and web-scoped.

### P1 — Right rail gets an internal scroll view

In `_rightSidebar` ([:1096](../lib/features/home/shell/citizen_shell.dart#L1096)),
wrap the existing `Column` in a `SingleChildScrollView`:

```dart
SizedBox(
  width: _kRightSidebarWidth,
  child: SingleChildScrollView(          // ← new
    child: Padding(
      padding: const EdgeInsets.fromLTRB(8, 20, 20, 20),
      child: Column(mainAxisSize: MainAxisSize.min, ...),  // unchanged
    ),
  ),
)
```

Mirrors `_leftRail` exactly, giving both rails identical behaviour: pinned when
short, internally scrolling when tall. No content moves.

### P2 — Hide scrollbars, scoped to the shell

Wrap the shell's `Stack` (or the `Expanded` holding the columns) in:

```dart
ScrollConfiguration(
  behavior: const _NoScrollbarBehavior(),   // ScrollBehavior with scrollbars: false
  child: ...,
)
```

where `_NoScrollbarBehavior extends MaterialScrollBehavior` and overrides
`buildScrollbar` to return the child untouched. Scrolling — wheel, trackpad,
drag, keyboard — is entirely unaffected; only the painted thumb goes.

`dragDevices` should also include mouse so trackpad/drag behaviour is unchanged
from what `MaterialScrollBehavior` gives on web.

Scoped inside `CitizenShell`, so `/admin`, `/staff` and the auth screens keep
their scrollbars.

### P3 — Events cap 3 → 2

`HomeUpcomingEventsCard.maxItems` default `3` → `2`
([home_upcoming_events_card.dart](../lib/core/widgets/Home/sections/Web/home_upcoming_events_card.dart)).
The widget has exactly one call site (the shell), and `.take(maxItems)` already
does the work. "View All" still reaches the rest.

### Not proposed

- No `Sticky`/`SliverPersistentHeader` machinery — the `Expanded` + `Row` +
  loose-constraint arrangement already produces sticky rails; adding slivers
  would be a rewrite of a working layout.
- No change to `_leftRail` (already correct, and the drawer depends on it owning
  exactly one scroll view).
- No change to the centre column or `NewsFeedBody`.

**Files touched: 2** — `citizen_shell.dart` (P1 + P2) and
`home_upcoming_events_card.dart` (P3).

**No code written. Waiting for go.**
