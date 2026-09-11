# Deploying the web build

The citizen, admin and staff web surfaces are one Flutter web build, served by
Vercel at **gov-pulse-rose.vercel.app** (project `gov-pulse`).

## Where the build config lives

`vercel.json`, at the repo root. It used to live only in the Vercel dashboard,
where it had no history and nothing recorded what it was if it got overwritten.

⚠ **`vercel.json` OVERRIDES the dashboard entirely.** It is not merged with it.
That is why the file restates `outputDirectory` and `installCommand` even
though neither is changing — omit one and it falls back to Vercel's default
rather than to what the dashboard says, which silently breaks the build.

The install command clones Flutter at a pinned version (`3.41.2`). Keep it in
step with the SDK this repo is developed against; a build agent that resolves a
newer Flutter than the one the code was written for fails in ways that look
nothing like a version problem.

## `--dart-define`s

| Define | Why |
| --- | --- |
| `SENTRY_DSN` | Turns on crash reporting. **Empty by default**, and with it empty the tree-shaker removes Sentry from the bundle entirely — so a build without this define is not merely quiet, it ships no reporting code at all. |
| `SENTRY_ENVIRONMENT` | Tags events `production`. A staging deploy sharing the DSN should set this to `staging`, or its noise lands in the same feed as real citizen crashes. |

See `lib/core/config/app_config.dart` for the full set, including
`SCAN_BASE_URL` and `LGU_MAYOR_NAME`, which currently rely on their defaults.

### Is the DSN a secret?

No. A Sentry DSN is a **write-only ingest key** and it ships inside
`main.dart.js`, which anyone who opens the site can read. It is in this repo on
purpose, so the build config is reviewable in one place.

It is not a password and grants no read access to the issue feed. The only
abuse it permits is sending junk events; if that ever happens, rotate the DSN
in Sentry (Settings → Client Keys) and update `vercel.json`.

## Sentry plan

The account starts on a 14-day **Business trial** and then drops to the free
**Developer** plan on its own — no card, no interruption. Free covers 5,000
errors/month with 30-day retention, which is far more headroom than this app's
volume needs. Nothing has to be done when the trial ends.

## Verifying a deploy

1. `curl -s https://gov-pulse-rose.vercel.app/ | grep -o "<title>[^<]*</title>"`
   — should be `GovPulse — Municipality of Aparri`, not `govpulse`.
2. Crash reporting is live when the bundle mentions the ingest host:
   `curl -s https://gov-pulse-rose.vercel.app/main.dart.js | grep -c ingest.de.sentry.io`
   A `0` means the define did not reach the build and Sentry was tree-shaken out.
3. The first-paint splash is `splash-ring` in the served `index.html`.

## What deploys

Vercel builds on every push to `main`. Old deployments can be cleared with
`npx vercel rm gov-pulse --safe -y` — `--safe` refuses to remove anything
aliased, so the live site cannot be hit by accident.
