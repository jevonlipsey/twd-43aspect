#!/usr/bin/env bash
# builds the browser patcher into web/dist/ (a static site). run from the repo root:
#   tools/build_web.sh
# pure JavaScript, no game files needed. web/app/twd43-data.js is generated and committed:
#   TWD_LUAC=<luac from tools/build_luac52.sh> python3 tools/gen_web_data.py
# (it needs pycryptodome for tools/patch43.py and the luac to compile mod/ProjectSeason1/Tooltip.lua).
set -euo pipefail

cd "$(dirname "$0")/.."

DIST=web/dist
rm -rf "$DIST"
mkdir -p "$DIST"

for f in index.html style.css main.js patcher-runtime.js twd43-data.js pako.min.js; do
  cp "web/app/$f" "$DIST/$f"
done

touch "$DIST/.nojekyll"

echo "[+] web/dist ready"
for f in twd43-data.js pako.min.js patcher-runtime.js main.js index.html style.css; do
  echo "    $f: $(wc -c < "$DIST/$f" | awk '{printf "%.1f KB", $1/1024}')"
done
echo "    total:      $(du -sk "$DIST" | cut -f1) KB"
