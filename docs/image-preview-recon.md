# Feed Image Preview Not Full-Screen — Recon

*Read-only, written 2026-08-13. No code changed.*

---

## 0. Cause, in one line

`openImageViewer` pushes onto **`Navigator.of(context)` — the *nearest* navigator**.
From a feed post card inside the shell, the nearest navigator is the
**StatefulShellRoute branch navigator**, whose viewport is the centre column —
so the route can only paint inside that column. From inside the comments sheet
the nearest navigator is the **root** navigator, because the sheet is itself a
root-navigator route — so the same viewer covers the whole viewport.

Same function, two different navigators, entirely because of where it is called
from.

## 1. The direct (broken) path

[image_grid.dart:140](../lib/core/widgets/Home/Newsfeed/image_grid.dart#L140):

```dart
void openImageViewer(
  BuildContext context,
  int imageCount,
  int initialIndex, {
  List<String> urls = const [],
}) {
  Navigator.of(context).push(          // ← nearest navigator
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black.withValues(alpha: 0.92),
      ...
      pageBuilder: (_, _, _) => _ImageViewer(...),
    ),
  );
}
```

Called from
[newsfeed_post_card.dart:174](../lib/core/widgets/Home/Newsfeed/newsfeed_post_card.dart#L174),
via `buildImageGrid(..., onImageTap:)`.

The context there sits inside:

```
CitizenShell
└─ Row
   └─ Expanded → SizedBox.expand
      └─ StatefulNavigationShell
         └─ branch Navigator            ← Navigator.of(context) finds THIS
            └─ NewsFeedBody → NewsfeedPostCard → buildImageGrid
```

`StatefulShellRoute.indexedStack` gives **each branch its own Navigator** — the
shell's own header comment says so: *"Each branch owns a Navigator, so a detail
route pushed from a pane stacks INSIDE that pane."* That is exactly the intended
behaviour for report and event detail, and exactly wrong for a lightbox.

The route's `opaque: false` + `barrierColor` at 92% black therefore fills the
**branch navigator's** box — the centre column — leaving both rails and the top
nav at full brightness. `_ImageViewer` itself is a
`Scaffold(backgroundColor: Colors.transparent)`, so it contributes no dimming of
its own; all of the darkness comes from that barrier, and the barrier is bounded.

## 2. The comment-sheet (working) path

Called from
[comment_post_recap.dart:99](../lib/core/widgets/Home/Newsfeed/comment_post_recap.dart#L99)
— **identical call, no extra arguments**.

The difference is the ancestor. `CommentPostRecap` lives inside the comments
sheet, opened by `showCommentsSheet` →
[comments_sheet.dart:75](../lib/core/widgets/Home/Newsfeed/comments_sheet.dart#L75)
→ `showAppDialog(...)`, and `showAppDialog` defaults to
[**`useRootNavigator: true`**](../lib/core/widgets/app_dialog.dart#L174).

So the sheet is a route on the ROOT navigator, and any context inside it resolves
`Navigator.of(context)` to the root navigator. The viewer pushed from there is a
sibling of the sheet on the root stack, its barrier covers the whole window, and
the lightbox looks correct.

**That is why the comment-sheet path is the reference for "correct": it reaches
the root navigator by accident of nesting, not by asking for it.**

## 3. Is the recent scroll change responsible? — No

I checked specifically, because it was the stated hypothesis.

- The `ScrollConfiguration` added in `CitizenShell.build` only overrides
  `buildScrollbar`. It changes what is *painted* for scrollbars and imposes no
  constraints on anything.
- The `SingleChildScrollView` added in P1 is inside **`_rightSidebar`** only. The
  centre column was not touched — the `Expanded → LayoutBuilder → MediaQuery →
  SizedBox.expand(navigationShell)` chain is byte-identical to before.
- Neither one is an ancestor that could newly bound a route pushed on the branch
  navigator; the branch navigator's own box has always been the centre column.

**This is pre-existing**, dating from the introduction of the
`StatefulShellRoute` shell — the bug is in *which navigator* is asked, and that
has been the branch navigator for the feed the whole time. The recent work made
the rails visually richer (quick actions, download card, events card, verify
card), which is plausibly why an undimmed rail became obvious now rather than
when the rails were nearly empty.

## 4. Who else calls `openImageViewer`

This matters, because the naive fix is to change the function itself:

| Call site | Surface | Currently |
|---|---|---|
| [newsfeed_post_card.dart:174](../lib/core/widgets/Home/Newsfeed/newsfeed_post_card.dart#L174) | citizen feed — **mobile AND web** | broken on web shell |
| [comment_post_recap.dart:99](../lib/core/widgets/Home/Newsfeed/comment_post_recap.dart#L99) | comments sheet (citizen) **and admin console** | works |
| [community_updates_page.dart:695, :1107](../lib/features/admin/pages/community_updates_page.dart#L695) | **admin** | works |
| [staff_community_page.dart:737](../lib/features/staff/pages/staff_community_page.dart#L737) | **staff** | works |

So `openImageViewer` is shared across citizen mobile, citizen web, admin and
staff. **Changing it to always use the root navigator would touch all four** —
against the hard rules for admin/staff and for mobile.

`NewsfeedPostCard` itself, though, has exactly **one** caller —
[news_feed_screen.dart:1356](../lib/features/home/newsfeed/news_feed_screen.dart#L1356)
— so it is citizen-feed-only (mobile + citizen web + guest web) and never
rendered by a console. `CommentPostRecap` **is** used by the admin console
([community_updates_page.dart:2957, :3007](../lib/features/admin/pages/community_updates_page.dart#L2957)),
so it must not be altered — and it does not need to be, being the working path.

## 5. Proposed fix

Two edits, both additive, using the default-flag pattern.

### F1 — give `openImageViewer` an opt-in, defaulting to today's behaviour

```dart
void openImageViewer(
  BuildContext context,
  int imageCount,
  int initialIndex, {
  List<String> urls = const [],
  bool useRootNavigator = false,        // ← new
}) {
  Navigator.of(context, rootNavigator: useRootNavigator).push(
    ...unchanged...
  );
}
```

`false` reproduces `Navigator.of(context)` exactly, so admin, staff and the
comments-sheet path are byte-identical and provably unaffected.

### F2 — the citizen feed opts in, on web only

At [newsfeed_post_card.dart:174](../lib/core/widgets/Home/Newsfeed/newsfeed_post_card.dart#L174):

```dart
onImageTap: (index) => openImageViewer(
  context,
  post['imageCount'] as int,
  index,
  urls: post['imageUrls'] as List<String>? ?? [],
  useRootNavigator: kIsWeb,            // ← new
),
```

`kIsWeb`, not a bare `true`, so **mobile takes the identical code path it takes
today**. Needs `import 'package:flutter/foundation.dart' show kIsWeb;` in that
file.

On web this is correct for both citizen surfaces:
- **shell feed** — escapes the branch navigator, so the barrier covers rails and
  nav. This is the fix.
- **guest feed** (`/newsfeed`) — already a top-level route on the root navigator,
  so `rootNavigator: true` resolves to the same navigator and nothing changes.

### Why root-navigator pushing is safe here

It is the same thing `showAppDialog` already does for the comments sheet, the
quick-action dialogs and the notification panel. The viewer is a **pageless**
push (`PageRouteBuilder`, not a go_router `Page`), so it adds no history entry
and does not disturb the address bar — closing pops back to exactly the same
location. The shell, both rails and the feed stay mounted underneath.

### Not proposed

- No change to `_ImageViewer` itself — it is already written as a full-screen
  surface (`Scaffold(backgroundColor: Colors.transparent)` + `Positioned.fill`
  dismiss layer) and behaves correctly once its route is not bounded.
- No change to `comment_post_recap.dart`, `community_updates_page.dart` or
  `staff_community_page.dart`.
- No `Overlay.of(context, rootOverlay: true)` hand-rolled entry — the route
  already exists and only needs the right navigator.

**Files touched: 2** — `image_grid.dart` (one parameter, one argument) and
`newsfeed_post_card.dart` (one argument, one import).

**No code written. Waiting for go.**
