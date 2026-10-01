"""Zips build/web into release/govpulse-web.zip for the self-hosted server.

Not Compress-Archive: Windows zips carry no Unix permissions, and some server
unzip tools then create folders Apache cannot enter (403 "unable to read
htaccess file" on every image under assets/assets/). Every entry here carries
explicit 755 (folders) / 644 (files), and folders get their own entries so
they are created with those permissions too.

Run after `flutter build web --release ...`:  python tool/make_release_zip.py
"""
import os
import time
import zipfile

SRC = os.path.join('build', 'web')
OUT = os.path.join('release', 'govpulse-web.zip')

if not os.path.isfile(os.path.join(SRC, 'index.html')):
    raise SystemExit('build/web/index.html missing - run flutter build web first')

os.makedirs('release', exist_ok=True)
files = dirs = 0
with zipfile.ZipFile(OUT, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    for root, subdirs, names in os.walk(SRC):
        subdirs.sort()
        rel = os.path.relpath(root, SRC).replace(os.sep, '/')
        if rel != '.':
            info = zipfile.ZipInfo(rel + '/', time.localtime(os.path.getmtime(root))[:6])
            info.create_system = 3  # Unix, so external_attr is honoured
            info.external_attr = (0o040755 << 16) | 0x10
            z.writestr(info, b'')
            dirs += 1
        for name in sorted(names):
            path = os.path.join(root, name)
            arc = name if rel == '.' else rel + '/' + name
            info = zipfile.ZipInfo.from_file(path, arc)
            info.create_system = 3
            info.external_attr = 0o100644 << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            with open(path, 'rb') as f:
                z.writestr(info, f.read())
            files += 1
print(f'{OUT}: {files} files, {dirs} folders')
