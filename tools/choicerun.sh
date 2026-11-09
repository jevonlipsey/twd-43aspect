#!/usr/bin/env bash
# One headless S1 choice-layout run (test only): swap the live S1X set for a diag set, start a fresh WalkingDead101
# via the warp tour, nudge the stick so the controller layout shows, screenshot ~every 2.5 s to +170 s, then put
# everything back (live S1X set, saves restored + verified) and release the lock.
#   ADB_SERIAL=<serial> tools/choicerun.sh <diag set dir> <live S1 set dir> <tag>
# e.g. tools/choicerun.sh out/fix43d3_S1 out/fix43s_S1 c3   -> screenshots/c3-s<sec>.png
set -u
D="$(cd "$(dirname "$0")" && pwd)"; R="$(dirname "$D")"; : "${ADB_SERIAL:?}"
DIAG="${1:?diag set}"; LIVE="${2:?live S1 set}"; TAG="${3:?tag}"; S="$ADB_SERIAL"
nudge() { printf 'N=/dev/input/event7\nsendevent $N 3 0 20000; sendevent $N 0 0 0; sleep 0.3; sendevent $N 3 0 0; sendevent $N 0 0 0\n' | adb -s "$S" shell su; }
"$D/devrun.sh" lock || exit 1
"$D/twd-saves.sh" backup "$TAG" | tail -1 || { "$D/devrun.sh" unlock; exit 1; }
"$D/deploy-sets.sh" remove "$LIVE" && "$D/deploy-sets.sh" install "$DIAG" "$R/out/tour43t" | grep installed || { echo "swap failed"; }
"$D/devrun.sh" launch | tail -1
sleep 8; "$D/devrun.sh" btn 304; T0=$(date +%s)
sleep 35; nudge & n=0
while [ $(( $(date +%s) - T0 )) -lt 170 ]; do
  t=$(( $(date +%s) - T0 )); adb -s "$S" exec-out screencap -p > "$R/screenshots/$TAG-s$(printf %03d $t).png"
  n=$((n+1)); [ $n -eq 5 ] && { nudge & }; sleep 1
done
python3 -I ~/.claude/skills/nova-43aspect/tools/dd-stop.py --owner twd-43aspect 2>&1 | tail -1
for i in $(seq 1 30); do [ -z "$(printf "ps -A | grep -E 'gamescope|wineserver|WDC' | grep -v grep\n" | adb -s "$S" shell su | tr -d '\r')" ] && break; sleep 3; done
"$D/deploy-sets.sh" remove "$DIAG" "$R/out/tour43t"
"$D/deploy-sets.sh" install "$LIVE" | grep installed
"$D/twd-saves.sh" restore "$TAG" | grep -E 'OK|FAIL'
"$D/twd-saves.sh" verify "$TAG" | tail -1
"$D/devrun.sh" unlock
