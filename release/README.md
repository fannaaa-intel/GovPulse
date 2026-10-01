# GovPulse web release

`govpulse-web.zip` is the ready-to-upload website for **govpulse.aparri.org.ph**
(Flutter web release build, commit 5dfc900, built 2026-10-01).

## How to upload

1. Download `govpulse-web.zip` from this folder.
2. On the server, delete the old files in the site's web root.
3. Extract the zip **into the web root**, so `index.html` sits directly in it
   (not inside a `web/` subfolder).
4. Open the site and hard-refresh (Ctrl+Shift+R).

Do **not** upload the project's `web/` folder — that is only the source
template and shows a blank page.
