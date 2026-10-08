# GovPulse web release

`govpulse-web.zip` is the ready-to-upload website for **govpulse.aparri.org.ph**
(Flutter web release build, 2026-10-09, always the commit that last changed
this zip).

## How to upload

1. Download `govpulse-web.zip` from this folder.
2. On the server, delete **everything** in the site's web root, including the
   old hidden `.htaccess` file.
3. Upload the zip to the web root and **extract it there** (cPanel File
   Manager → Extract), so `index.html` sits directly in the web root, not
   inside a `web/` subfolder. Then delete the zip from the server.
4. Make sure the hidden file `.htaccess` is there (cPanel: Settings → Show
   Hidden Files). It makes links like `/login` and `/privacy_policy` work.
5. Set permissions on everything inside the web root:
   **folders 755, files 644**.
   - cPanel: select all → Permissions, or over SSH in the web root:
     ```
     find . -type d -exec chmod 755 {} \;
     find . -type f -exec chmod 644 {} \;
     ```
6. Open the site and hard-refresh (Ctrl+Shift+R).

## Check it worked

All three must load (not "Forbidden" / "Internal Server Error"):

- https://govpulse.aparri.org.ph/assets/assets/images/applogo.webp — the logo
- https://govpulse.aparri.org.ph/privacy_policy — the Privacy Policy page
- https://govpulse.aparri.org.ph/login — the login page

If the WHOLE site shows "Internal Server Error" after the upload, the server
does not allow `.htaccess` rules: delete `.htaccess` and tell the developer.

Do **not** upload the project's `web/` folder; that is only the source
template and shows a blank page.
