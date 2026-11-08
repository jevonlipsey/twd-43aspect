#!/usr/bin/env bash
# The ONE-RUN device test of p10 + the per-season 4:3 UI test sets + the warp tour (only in a coordinator slot).
#   ADB_SERIAL=<serial> tools/tourrun.sh pre  <tag>   lock, back up the WHOLE save dir, deploy p10 + 12 set files,
#                                                     launch (Steam mode), start a 5 s screenshot loop -> screenshots/<tag>-<sec>.png
#   ADB_SERIAL=<serial> tools/tourrun.sh a    <tag>   one A press (title -> Definitive menu); the tour then drives itself
#   ADB_SERIAL=<serial> tools/tourrun.sh shot <tag>   one extra screenshot now
#   ADB_SERIAL=<serial> tools/tourrun.sh post <tag>   stop the loop + the game, remove the 12 files, exe back to p6menu,
#                                                     restore + verify the save dir, status, release the lock
# Every step refuses (and leaves the device as it was) when its check fails; `post` is safe to re-run after a failure.
set -u
D="$(cd "$(dirname "$0")" && pwd)"; R="$(dirname "$D")"; : "${ADB_SERIAL:?}"; CMD="${1:?pre|a|shot|post}"; TAG="${2:?tag}"
SETS="$R/out/fix43t_S1 $R/out/fix43t_S2 $R/out/fix43t_S3 $R/out/fix43t_S4 $R/out/fix43t_M $R/out/tour43t"
LOOP="$R/screenshots/$TAG.loop.pid"; T0F="$R/screenshots/$TAG.t0"
mkdir -p "$R/screenshots"
case "$CMD" in
pre)
  "$D/devrun.sh" lock || exit 1
  "$D/twd-saves.sh" backup "$TAG" || { "$D/devrun.sh" unlock; exit 1; }
  TWD_LOCK_HELD=1 "$D/deploy.sh" p10 2>&1 | grep -E "deployed|already|deploy:|pristine" || true
  [ "$(adb -s "$ADB_SERIAL" exec-out su -c 'sha256sum "/mnt/media_rw/6988-E33F/Android/data/com.droiddeck.launcher/files/steam/steamapps/common/The Walking Dead The Telltale Definitive Series/WDC.exe"' | cut -c1-16)" = 85fb1aa64867d41a ] ||
    { echo "p10 not live; run: tools/tourrun.sh post $TAG"; exit 1; }
  "$D/deploy-sets.sh" install $SETS || { echo "set install failed; run: tools/tourrun.sh post $TAG"; exit 1; }
  "$D/devrun.sh" launch | tail -1
  date +%s > "$T0F"
  ( while :; do t=$(( $(date +%s) - $(cat "$T0F") )); adb -s "$ADB_SERIAL" exec-out screencap -p > "$R/screenshots/$TAG-$(printf %04d $t).png"; sleep 4; done ) >/dev/null 2>&1 &
  echo $! > "$LOOP"; echo "screenshot loop pid $(cat "$LOOP"); shots screenshots/$TAG-<seconds since launch>.png";;
a) "$D/devrun.sh" btn 304; echo "A at +$(( $(date +%s) - $(cat "$T0F") ))s";;
shot) "$D/devrun.sh" shot "$TAG-x$(( $(date +%s) - $(cat "$T0F" 2>/dev/null || date +%s) ))";;
post)
  [ -f "$LOOP" ] && { kill "$(cat "$LOOP")" 2>/dev/null; rm -f "$LOOP"; echo "screenshot loop stopped"; }
  python3 -I ~/.claude/skills/nova-43aspect/tools/dd-stop.py --owner twd-43aspect 2>&1 | tail -1
  for i in $(seq 1 30); do   # deploy steps refuse while any game process is still tearing down
    [ -z "$(printf "ps -A | grep -E 'gamescope|wineserver|WDC' | grep -v grep\n" | adb -s "$ADB_SERIAL" shell su | tr -d '\r')" ] && break; sleep 3
  done
  "$D/deploy-sets.sh" remove $SETS
  TWD_LOCK_HELD=1 "$D/deploy.sh" p6menu 2>&1 | grep -E "deployed|already|deploy:|pristine" || true
  "$D/twd-saves.sh" restore "$TAG" || echo "SAVE RESTORE FAILED: see /data/local/tmp/twd-saves-$TAG (backup also in backup/saves-$TAG.tar)"
  "$D/twd-saves.sh" verify "$TAG"
  "$D/deploy.sh" --status 2>&1 | tail -2
  "$D/deploy-sets.sh" status $SETS | grep -v absent || echo "all 12 test files absent"
  "$D/devrun.sh" unlock;;
*) sed -n '2,10p' "$0"; exit 2;;
esac
