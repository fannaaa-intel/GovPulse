# GovPulse Newsfeed Redesign — Phase 1 Recon

*Written 2026-08-13, against `main` @ `666d409`.*

## 0. The headline finding, first

**This is not a JavaScript web app, and the Newsfeed is not a greenfield build.**

GovPulse is a **Flutter** application that compiles to Android, iOS *and* web from
one codebase. The "citizen web app" is Flutter Web output, not React/Next/Vite.
None of Phase 2's assumptions about CSS/Tailwind/component libraries apply — there
is no CSS layer to extract tokens into.

More importantly: a three-column citizen web shell with a Facebook-style community
feed **already exists and is live**, including post cards with image galleries,
like/comment counts, "see more" truncation, comment threads, realtime updates,
deep-linkable posts, skeleton loading, an error state and an empty state.

So the useful shape of this work is **not "build the Newsfeed"** — it's a
**delta against the mockup** plus **one genuine gap** (the empty state is written
for the wrong situation). Details in §8.

---

## 1. Framework, language, build tool, package manager

| | |
|---|---|
| Framework | Flutter (Material 3 widgets, `uses-material-design: true`) |
| Language | Dart, SDK constraint `^3.11.0` |
| Build tool | `flutter build web` (also android/ios/windows/macos/linux targets present) |
| Package manager | **pub** — [pubspec.yaml](pubspec.yaml) / `pubspec.lock` |
| State management | **Riverpod** (`flutter_riverpod ^2.5.1`) + hand-rolled singleton `ChangeNotifier`s |
| Routing | **go_router ^17.4.0** (web) + legacy Navigator 1.0 route table (mobile) |
| Backend | **Supabase** (`supabase_flutter ^2.0.0`) — Postgres + RLS + Realtime + Storage |
| Auth | **Firebase Auth** (`firebase_auth ^5.0.0`) + Google/Facebook sign-in, alongside Supabase sessions |
| Hosting | Firebase Hosting ([firebase.json](firebase.json), [.firebaserc](.firebaserc)) |
| Lints | `flutter_lints ^6.0.0` via [analysis_options.yaml](analysis_options.yaml) |

There is a `package.json` at the root, but it only exists for the Supabase JS
client used by `functions/` (Deno edge functions) — it is **not** the app's build
system.

---

## 2. Styling approach and existing design tokens

Styling is **inline Dart widget composition** — `BoxDecoration`, `TextStyle`,
`EdgeInsets`. There is no stylesheet, no utility framework, no CSS-in-JS.

Tokens live in two files, and the split is deliberate and documented:

### [lib/core/theme/app_colors.dart](lib/core/theme/app_colors.dart)
Product-wide, read by **mobile and web both**. Changing anything here ripples
into the Flutter mobile app.

```
primaryBlue  #0D47A1   ← the GovPulse blue, used ~417× on the citizen web side
green        #2ECC71   ← the GovPulse green, ~91×
inputBg      #F6F7FB      stroke #E3E6EF     hint #8A8A8A
grey #B0B0B0   red #E74C3C   orange #F39C12
```

### [lib/core/theme/citizen_ui.dart](lib/core/theme/citizen_ui.dart) — `CitizenUi`
**This is the design system Phase 2 asks for, and it already exists.** It is
scoped to the citizen web surface only, so it can be retuned without touching
mobile. It even carries usage counts in comments showing which hardcoded hex each
token replaced.

| Group | Tokens |
|---|---|
| Brand | `accent` (=primaryBlue), `accentGreen` (=green), `accentWash` `#EFF6FF` |
| Surfaces | `pageBg` `#F3F4F6`, `pageBgHome` `#F3F6FC`, `surface` white, `subtle` `#F9FAFB` |
| Borders | `border` `#E5E7EB`, `borderStrong` `#D1D5DB` |
| Text | `textPrimary` `#1F2937`, `textSecondary` `#374151`, `textMuted` `#6B7280`, `textFaint` `#9CA3AF` |
| Semantic | `badge` `#22C55E`, `success` `#15803D`, `danger`, `warn` `#F59E0B`, `pending` `#B45309` |
| Shape | `cardRadius` 14, `controlRadius` 10, `cardShadow` (`#141B2A4E`, blur 16, y+4) |

Sibling systems exist for the other two surfaces: `AdminUi` (features/admin/theme)
and `StaffUi` (features/staff/theme). Corner radii and shadow are matched across
all three on purpose.

**Typography** has *no* token file. Sizes are written inline, and on mobile they
are computed as a fraction of screen width (`width * 0.052` etc.). This is the one
real token gap — see §8.

**Spacing** likewise has no scale; it is inline `SizedBox`/`EdgeInsets`, again
often width-proportional on mobile.

---

## 3. Routing and the post-login landing page

Two routers coexist, and which one runs is decided by `kIsWeb` in
[lib/main.dart](lib/main.dart):

- **Web** → `GovPulseWebApp` → `citizenRouter`, a `GoRouter` that owns the address
  bar outright. Defined in
  [lib/features/home/shell/citizen_shell_router.dart](lib/features/home/shell/citizen_shell_router.dart).
- **Mobile** → the legacy `MaterialApp` with a `routes` table +
  `onGenerateRoute` in [lib/core/router/app_router.dart](lib/core/router/app_router.dart),
  reached from web code only through the `legacy_nav.dart` shim.

### The post-login landing page

`/#/home` — the `CitizenTab.home` branch of a `StatefulShellRoute.indexedStack`.

**Home *is* the newsfeed.** The router comment at
[citizen_shell_router.dart:96-102](lib/features/home/shell/citizen_shell_router.dart#L96-L102)
records that Home and NewsFeed used to be two tabs showing two halves of the same
thing, and were merged: the Home branch mounts `NewsFeedBody(embedded: true)`.

Shell tabs, in nav order (index = branch index, so order is load-bearing):

| index | path | label |
|---|---|---|
| 0 | `/home` | Home |
| 1 | `/my-reports` | My Reports |
| 2 | `/emergency` | Emergency |
| 3 | `/settings` | Settings |

Other routes: `/login`, `/signup`, `/guest`, `/newsfeed` (the **guest-only** bare
feed), `/admin`, `/staff`, `/scan/:token` (public), plus id-addressable
`/my-reports/detail/:reportId` and `/home/event/:eventId`.

Feed deep links are **query parameters** on `/home`, not nested routes:
`/#/home?post=<id>&comments=1&highlight=1` (`shellFeedPostPath()`). This makes a
community post permalinkable.

Quick actions deliberately have **no routes** — they open as dialogs over the
still-mounted feed ([citizen_shell_dialogs.dart](lib/features/home/shell/citizen_shell_dialogs.dart)).

---

## 4. Auth flow and reading the current user

Three-way classification in `_authRedirect`
([citizen_shell_router.dart:282](lib/features/home/shell/citizen_shell_router.dart#L282)),
because "guest" is neither signed-in nor signed-out:

1. **Supabase session present** → signed-in. Role from `AuthRestoration.instance.roleId`:
   `1` = admin → `/admin`, `2` = staff → `/staff`, otherwise citizen → the shell.
   If the role isn't known yet, the guard *holds* (returns null) rather than guessing.
2. **No Supabase session, restoration settled, Firebase user `isAnonymous`** → guest.
   Allowlisted to `/guest`, `/newsfeed`, `/login`, `/signup`.
3. **Otherwise** → signed out → `/login`.

`refreshListenable: AuthRestoration.instance` re-runs the guard when restoration
settles or auth changes.

### Reading the current user

**`userProfileProvider`** — a Riverpod `AsyncNotifier<UserProfile>` in
[lib/core/providers/user_profile_provider.dart](lib/core/providers/user_profile_provider.dart).

```dart
final profile = ref.watch(userProfileProvider).valueOrNull;
profile?.displayName   // verified real name, falling back to username
profile?.isVerified    // verifStatus == VerifStatus.verified
profile?.barangay      // drives feed targeting
profile?.facePhotoUrl  // avatar
```

`UserProfile` carries `verifStatus` (`VerifStatus` enum: none / pending /
verified), `fullName`, `facePhotoUrl`, `facePhotoPath`, `email`, `barangay`,
`username`. Verification status is read from `verification_submissions` (latest
row by `created_at`).

Raw identity where needed: `Supabase.instance.client.auth.currentUser?.id`.

Account enforcement (suspension / feature restriction) runs through
`CitizenGuard.I.status`, a `ValueListenable<CitizenStatus>`.

---

## 5. Existing API endpoints and data models

All data is Supabase (PostgREST tables/views + a few `SECURITY DEFINER` RPCs).
There is no REST API layer of our own.

### Posts / community updates
Owned by **`CommunityPostsProvider`** (singleton `ChangeNotifier`),
[lib/core/providers/community_posts_provider.dart](lib/core/providers/community_posts_provider.dart).

| Source | Purpose |
|---|---|
| `community_feed` (view) | citizen read, filtered `status = 'approved'`, ordered `pinned desc, created_at desc` |
| `guest_community_feed()` RPC | guest read; citizen authors masked server-side |
| `community_comments` | threaded comments (`parent_comment_id`), moderation `status` |
| `guest_community_comments()` RPC | masked comments for guests |
| `community_post_likes` / `community_comment_likes` | per-user like rows |
| `official_public_profiles(uuid[])` RPC | resolves admin/staff author name, photo, department, role |
| `public_user_profiles` | citizen author names + photo paths |
| Storage bucket `community-posts` | post images; `profile-photos` for avatars |

Post shape (a `Map<String, dynamic>`, **not** a typed model — see §8):

```
id, authorId, author, authorRole, authorDept, isOfficial, blankAvatar,
authorPhotoUrl, authorPhotoPath, barangay, tag, tagColor (Color),
title, body, likes (String!), imageCount, imageUrls (List<String>),
timestamp (DateTime?), pinned (bool), comments (List<Map>), commentCount (int)
```

Behaviour already implemented: pinned-first ordering, optimistic like/comment
counts, optimistic comment insertion with realtime reconciliation, pending-edit
protection against stale realtime overwrites, guest anonymisation, and **barangay
targeting** — city-wide posts (empty `barangay`) always show; a user with a
barangay also sees theirs; a user with no barangay yet sees city-wide only
([news_feed_screen.dart:417-442](lib/features/home/newsfeed/news_feed_screen.dart#L417-L442)).

Realtime: channel `community_feed_changes` subscribes to `community_posts` and
`community_comments` (citizens only — guests can't read those tables).

### Events
`EventsService.instance` ([lib/core/services/events_service.dart](lib/core/services/events_service.dart))
over the **`events`** table. `EventModel`, plus `fetchEvents`, `fetchEventById`,
`fetchPendingEvents`, `createEvent`, `approveEvent`, `rejectEvent`, `updateEvent`,
`deleteEvent`. UI in
[Quick-action/Events/events_screen.dart](lib/features/home/Quick-action/Events/events_screen.dart)
— which **already renders an "Upcoming Events" list**.

### Reports
**`reports`** table; `ReportItem` model with `ReportItem.fetchById`. UI in
[my_reports_screen.dart](lib/features/home/my_report/my_reports_screen.dart) and
[report_card.dart](lib/features/home/my_report/report_card.dart).

### Notifications
`NotificationService` (static) in
[lib/features/home/screen/notification_popup.dart](lib/features/home/screen/notification_popup.dart)
over the **`notifications`** table: `load`, `add`, `markRead`, `remove`,
`clearAll`, `adminSend`, `staffSend`, `startRealtime`. Model `AppNotification`.
Web panel: [citizen_web_notification_panel.dart](lib/core/widgets/Home/Newsfeed/citizen_web_notification_panel.dart).
Deep-link targets live in `reference_id` (not `post_id`).

### Profile / verification
`verification_submissions` (status + face photo), `profiles` (username, role),
`public_user_profiles`, `admin_profiles`. Push tokens via `push_service.dart`.

---

## 6. Feed/post components that already exist

Under [lib/core/widgets/Home/Newsfeed/](lib/core/widgets/Home/Newsfeed/):

| File | What it is |
|---|---|
| `newsfeed_post_card.dart` | **the post card** — author + avatar, barangay/agency tag, timestamp, body with "see more", image gallery, like/comment footer |
| `image_grid.dart` | **1 large + stacked thumbnails with `+N` overlay** — the mockup's gallery, already built |
| `comments_sheet.dart` | threaded comment sheet |
| `comment_item.dart`, `comment_options_sheet.dart`, `edit_comment_sheet.dart`, `comment_post_recap.dart` | comment sub-components |
| `citizen_web_notification_panel.dart` | web notification dropdown |
| `news_feed_helpers.dart` | shared bits (`dragHandle`, formatting) |
| `rate_limit_dialogs.dart` | like/comment rate-limit messaging |

Chrome and layout:

| File | What it is |
|---|---|
| [citizen_shell.dart](lib/features/home/shell/citizen_shell.dart) | **the three-column web shell** (top nav + left rail + centre branch + right sidebar), 1286 lines |
| [nav/home_top_nav.dart](lib/core/widgets/Home/nav/home_top_nav.dart) | top nav with **notification bell + count badge** |
| [nav/responsive_nav_scaffold.dart](lib/core/widgets/Home/nav/responsive_nav_scaffold.dart) | responsive scaffold used by standalone screens |
| [nav/home_nav_drawer.dart](lib/core/widgets/Home/nav/home_nav_drawer.dart) | drawer for the mid/narrow band |
| [sections/Web/home_quick_actions_section_web.dart](lib/core/widgets/Home/sections/Web/home_quick_actions_section_web.dart) | quick-action cards, currently in the **right** sidebar |
| [loading/loading_overlay.dart](lib/core/widgets/loading/loading_overlay.dart) | `SkeletonLayout.newsFeed` → `_NewsFeedSkeletonScreen` (mobile) / `_WebFeedSkeleton` (web) |

Base primitives Phase 2 lists also already exist in some form:
`core/widgets/buttons/`, `core/widgets/inputs/`, `core/widgets/indicators/`,
`app_dialog.dart`, `app_snackbar.dart`, `app_screen_header.dart`,
`event_status_pill.dart`, `ai_detection_badge.dart`, `media_source_badge.dart`,
plus a web kit in `core/widgets/web/` (`web_glass_card`, `web_card_grid`,
`web_outlined_button`, `web_input_field`, `web_responsive`, `web_constants`).

### The three feed states — all three exist today

| State | Where | Status |
|---|---|---|
| LOADING | `LoadingOverlay.bodyOrSkeleton(layout: SkeletonLayout.newsFeed)` | ✅ real skeletons, no spinner-only screen |
| ERROR | `_buildErrorState` ([news_feed_screen.dart:1199](lib/features/home/newsfeed/news_feed_screen.dart#L1199)) | ✅ wifi-off icon + "Could not load posts" + Retry |
| EMPTY | `_buildEmptyState` ([news_feed_screen.dart:1245](lib/features/home/newsfeed/news_feed_screen.dart#L1245)) | ⚠️ **exists but is written for the wrong situation** — see §8 |
| POPULATED | `NewsfeedPostCard` + `image_grid` | ✅ matches the mockup's card anatomy |

Responsive collapse to single column is handled: `wide = embedded || (kIsWeb && rawWidth >= 900)`,
and the shell has a labelled-rail / drawer / mobile progression.

---

## 7. Recommended integration points

Ordered by where a change actually belongs.

1. **Feed states (empty/error/loading)** →
   [lib/features/home/newsfeed/news_feed_screen.dart](lib/features/home/newsfeed/news_feed_screen.dart),
   methods `_buildEmptyState`, `_buildErrorState`. These are private methods on
   `_NewsFeedScreenState` and are called from *both* the mobile and web arms, so
   one change covers both surfaces. **Recommended: extract the empty state into
   `core/widgets/Home/Newsfeed/feed_empty_state.dart`** so it is testable and the
   1310-line screen doesn't grow.
2. **Rail composition (the mockup's biggest delta)** →
   [citizen_shell.dart](lib/features/home/shell/citizen_shell.dart), `_leftRail()`
   (line 757) and `_rightSidebar()` (line ~1100). This is where quick actions,
   the verify card and the user chip currently sit on the *right*, and the mockup
   puts them on the *left*.
3. **New right-rail cards (download promo, Upcoming Events)** → new widgets under
   `core/widgets/Home/sections/Web/`, mounted from `_rightSidebar()`. Upcoming
   Events should read `EventsService.instance.fetchEvents()` rather than
   re-fetching ad hoc.
4. **Design tokens** → add to
   [citizen_ui.dart](lib/core/theme/citizen_ui.dart). Do **not** add colours to
   `app_colors.dart` — that file is shared with mobile.
5. **Post data shape** → [community_posts_provider.dart](lib/core/providers/community_posts_provider.dart).
   Flipping empty→populated is already just data; no UI change needed.
6. **Nav labels/order** → `CitizenTab` enum
   ([citizen_shell_router.dart:103](lib/features/home/shell/citizen_shell_router.dart#L103)).
   ⚠️ Enum order **is** the go_router branch index — reordering changes routing.

---

## 8. Delta against the mockup, and the one real gap

What the mockup asks for that the code does **not** currently do:

### A. The empty state is written for the wrong situation ← *the genuine gap*
Current copy is **"No posts found" / "There are no posts from {time range}. Try a
wider time range."** with a grey `inbox_outlined` icon and **no CTA**.

That's a *filter-result* empty state. It's correct after someone narrows to "Last
Day", and it's actively wrong as the **first thing a new citizen ever sees** —
it reads like a dead end and blames a filter the user never touched. This is
exactly the case the brief calls first-class, and it is the strongest argument
for the whole redesign. It needs two distinct states:

- **no posts exist at all** → warm, civic, illustrated, with a Quick Action CTA
- **posts exist but the filter excludes them** → keep today's copy + a "show all" reset

### B. Left and right rails are swapped
Mockup: **left** = Quick Actions, Verify Your Account card, user chip;
**right** = app-download promo, Upcoming Events.
Code: **left** = navigate/account/profile rail; **right** = quick actions.

### C. Missing right-rail content
No **"Stay connected on the go" download promo card** anywhere in the citizen web
code (`Download App` only appears in admin PDF/export contexts). No **Upcoming
Events rail** — the list exists inside the Events screen but isn't surfaced on the
feed.

### D. Nav labels differ
Mockup: `Newsfeed | Emergency | My Reports`. Code: `Home | My Reports | Emergency | Settings`.
Note the mockup's *order* differs too, and Settings is absent from it.

### E. Filter affordance
Mockup shows a light "Latest" text control top-right of "Community Updates". Code
has a filled blue pill with a tune icon opening a bottom sheet of 5 ranges. Same
function, different weight.

### F. No typography or spacing scale
The one token gap. Font sizes are inline, and on mobile they're width-proportional
(`width * 0.042`), which resists a fixed type scale. A `CitizenUi` type ramp would
be genuinely new work.

### G. Post shape is untyped
Posts are `Map<String, dynamic>` with stringly-typed fields (`likes` is a
`String`, `tagColor` is a pre-parsed `Color`). The brief's "typed mock" would want
a real `CommunityPost` model. That's a refactor touching the provider, the card,
the comments sheet and the deep-link logic — **not** a prerequisite for the empty
state.

### Not a gap
Post-card anatomy, the `1 large + 3 stacked + "+N"` gallery, "see more"
truncation, like/comment counts, skeleton loading, the error state, responsive
single-column collapse, and data-driven empty→populated flipping are all already
built and working.

---

## 9. Open questions for you

1. **"GovPulse has NO posts at all"** — I could not verify this from the repo;
   it's a database-state claim and requires Supabase credentials. Worth confirming,
   because `community_feed` is filtered to `status = 'approved'` and targeted by
   barangay — a feed can read as empty while rows exist, if nothing is approved or
   the account has no barangay yet. If that's what's happening, the fix is partly
   moderation/data, not only design.
2. **Phases 2 and 3 as written assume a greenfield web app.** Given §0, do you
   want me to (a) do the mockup-delta work described in §8 against the existing
   Flutter shell, (b) do only the empty state (A), or (c) something else?
3. **Rail swap (B) is a structural change** to `citizen_shell.dart`, which is
   1286 lines carrying documented reasoning about breakpoints, drawer mode and
   gating. You asked to be consulted before structural changes to existing files —
   so I'm flagging it rather than doing it.

---

## 10. Stopping here

Per Phase 1, no feature code written. Summary in chat.
