#!/usr/bin/env bash
# One UI test run: lock, back up saves, deploy p6menu + the UI mod, launch, screenshot the boot path.
#   tools/uirun.sh NAME        screenshots/NAME-*.png; leaves the game RUNNING and the lock HELD
# Drive it further with devrun.sh btn/hat/shot, then `devrun.sh stop` (stops the game, releases the lock).
set -u
D="$(cd "$(dirname "$0")" && pwd)"; : "${ADB_SERIAL:?}"; N="${1:?name}"
"$D/devrun.sh" lock || exit 1
TWD_LOCK_HELD=1 "$D/deploy.sh" p6menu 2>&1 | grep -E "saves backed|^  |deployed|already|deploy:" || true
[ "$(adb -s "$ADB_SERIAL" exec-out su -c 'sha256sum "/mnt/media_rw/6988-E33F/Android/data/com.droiddeck.launcher/files/steam/steamapps/common/The Walking Dead The Telltale Definitive Series/WDC.exe"' | cut -c1-16)" = 0884f3fed72b76e7 ] || { echo "p6menu not live; stopping"; "$D/devrun.sh" unlock; exit 1; }
if [ "${TWD_NOMOD:-0}" = 1 ]; then "$D/deploy-uimod.sh" remove; else "$D/deploy-uimod.sh" install || { "$D/devrun.sh" unlock; exit 1; }; fi
"$D/devrun.sh" launch | tail -1
for i in 1 2 3 4; do "$D/devrun.sh" shot "$N-boot$i" >/dev/null; sleep 12; done
echo "shots: screenshots/$N-boot1..4.png; game left running, lock held"
