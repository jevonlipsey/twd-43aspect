#!/usr/bin/env bash
# One headless warp-tour run over all five seasons (test only): swap the LIVE per-season sets for test sets, start the
# tour (101 180 s -> 201 -> 301 -> 401 -> M101, 130 s each), nudge the left stick every 30 s so controller prompts
# show, screenshot ~every 2.5 s, then put the exact live sets back, restore + verify saves, release the lock.
#   ADB_SERIAL=<serial> tools/seasonrun.sh <tag> <seconds> "<test set dirs>" "<live set dirs>"
# e.g. tools/seasonrun.sh t5 800 "out/fix43n3_S1 out/fix43t2_S2 ..." "out/fix43u_S1 out/fix43s_S2 ..."
set -u
D="$(cd "$(dirname "$0")" && pwd)"; R="$(dirname "$D")"; : "${ADB_SERIAL:?}"
TAG="${1:?tag}"; SECS="${2:?seconds}"; TEST="${3:?test sets}"; LIVE="${4:?live sets}"; S="$ADB_SERIAL"
nudge() { printf 'N=/dev/input/event7\nsendevent $N 3 0 20000; sendevent $N 0 0 0; sleep 0.3; sendevent $N 3 0 0; sendevent $N 0 0 0\n' | adb -s "$S" shell su >/dev/null 2>&1; }
"$D/devrun.sh" lock || exit 1
"$D/twd-saves.sh" backup "$TAG" | tail -1 || { "$D/devrun.sh" unlock; exit 1; }
# shellcheck disable=SC2086
"$D/deploy-sets.sh" remove $LIVE && "$D/deploy-sets.sh" install $TEST "${TOUR:-$R/out/tour43t}" | grep installed || echo "swap failed"
"$D/devrun.sh" launch | tail -1
sleep 8; "$D/devrun.sh" btn 304; T0=$(date +%s); last=0
while [ $(( $(date +%s) - T0 )) -lt "$SECS" ]; do
  t=$(( $(date +%s) - T0 ))
  [ $(( t - last )) -ge 30 ] && { nudge & last=$t; }
  # A_FROM/A_TO/A_EVERY (seconds since the title A): blind A presses, e.g. past S4's story-import screen
  if [ -n "${A_FROM:-}" ] && [ "$t" -ge "$A_FROM" ] && [ "$t" -le "${A_TO:-0}" ] && [ $(( t - ${alast:-0} )) -ge "${A_EVERY:-10}" ]; then
    "$D/devrun.sh" btn 304 >/dev/null 2>&1 & alast=$t
  fi
  adb -s "$S" exec-out screencap -p > "$R/screenshots/$TAG-s$(printf %04d $t).png"; sleep 1
done
python3 -I ~/.claude/skills/nova-43aspect/tools/dd-stop.py --owner twd-43aspect 2>&1 | tail -1
for i in $(seq 1 30); do [ -z "$(printf "ps -A | grep -E 'gamescope|wineserver|WDC' | grep -v grep\n" | adb -s "$S" shell su | tr -d '\r')" ] && break; sleep 3; done
# shellcheck disable=SC2086
"$D/deploy-sets.sh" remove $TEST "${TOUR:-$R/out/tour43t}"
# shellcheck disable=SC2086
"$D/deploy-sets.sh" install $LIVE | grep installed
"$D/twd-saves.sh" restore "$TAG" | grep -E 'OK|FAIL'
"$D/twd-saves.sh" verify "$TAG" | tail -1
"$D/devrun.sh" unlock
