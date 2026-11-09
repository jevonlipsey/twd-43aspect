#!/usr/bin/env bash
# ONE headless reticle-reach run (test only): swap the live sets for test sets + the warp tour, launch, A at the title,
# then right-stick sweeps (hold to an edge/corner, screenshot while held) inside the given time windows, plain
# screenshots otherwise; afterwards install the AFTER sets (the build to leave live), restore + verify saves, unlock.
#   ADB_SERIAL=<serial> tools/reachrun.sh <tag> <seconds> "<before sets>" "<test sets>" "<after sets>" "<windows>"
#   windows = "from-to from-to" in seconds since the title A, e.g. "140-215 410-600"
# Right stick = ABS_Z (2) / ABS_RZ (5) on /dev/input/event7, range +-32767. Shots: screenshots/<tag>-s<sec>[-<dir>].png
set -u
D="$(cd "$(dirname "$0")" && pwd)"; R="$(dirname "$D")"; : "${ADB_SERIAL:?}"; S="$ADB_SERIAL"
TAG="${1:?tag}"; SECS="${2:?seconds}"; BEFORE="${3:?}"; TEST="${4:?}"; AFTER="${5:?}"; WIN="${6:?}"
TOUR="${TOUR:-$R/out/tour43t}"
mkdir -p "$R/screenshots"
shot() { adb -s "$S" exec-out screencap -p > "$R/screenshots/$TAG-$1.png"; }
nudge() { printf 'N=/dev/input/event7\nsendevent $N 3 0 20000; sendevent $N 0 0 0; sleep 0.3; sendevent $N 3 0 0; sendevent $N 0 0 0\n' | adb -s "$S" shell su >/dev/null 2>&1; }
# hold the right stick at (x, y) for 2.8 s, screenshot at 2.2 s, release
sweep() {
  printf 'N=/dev/input/event7\nsendevent $N 3 2 %s; sendevent $N 3 5 %s; sendevent $N 0 0 0; sleep 2.8; sendevent $N 3 2 0; sendevent $N 3 5 0; sendevent $N 0 0 0\n' "$2" "$3" | adb -s "$S" shell su >/dev/null 2>&1 &
  sleep 2.2; shot "s$(printf %04d $(( $(date +%s) - T0 )))-$1"; wait
}
inwin() { for w in $WIN; do [ "$1" -ge "${w%-*}" ] && [ "$1" -le "${w#*-}" ] && return 0; done; return 1; }
"$D/devrun.sh" lock || exit 1
"$D/twd-saves.sh" backup "$TAG" | tail -1 || { "$D/devrun.sh" unlock; exit 1; }
# shellcheck disable=SC2086
{ "$D/deploy-sets.sh" remove $BEFORE && "$D/deploy-sets.sh" install $TEST "$TOUR" | grep -c installed; } || echo "SWAP FAILED"
"$D/devrun.sh" launch | tail -1
sleep 8; "$D/devrun.sh" btn 304 >/dev/null; T0=$(date +%s); last=0
while [ $(( $(date +%s) - T0 )) -lt "$SECS" ]; do
  t=$(( $(date +%s) - T0 ))
  [ $(( t - last )) -ge 30 ] && { nudge & last=$t; }
  if inwin "$t"; then
    sweep L -32767 0; sweep R 32767 0; sweep U 0 -32767; sweep D 0 32767; sweep UL -32767 -32767; sweep DR 32767 32767
  else
    shot "s$(printf %04d "$t")"; sleep 1.5
  fi
done
python3 -I ~/.claude/skills/nova-43aspect/tools/dd-stop.py --owner twd-43aspect 2>&1 | tail -1
for i in $(seq 1 30); do [ -z "$(printf "ps -A | grep -E 'gamescope|wineserver|WDC' | grep -v grep\n" | adb -s "$S" shell su | tr -d '\r')" ] && break; sleep 3; done
# shellcheck disable=SC2086
"$D/deploy-sets.sh" remove $TEST "$TOUR"
# shellcheck disable=SC2086
"$D/deploy-sets.sh" install $AFTER | grep -c installed
"$D/twd-saves.sh" restore "$TAG" | grep -E 'OK|FAIL'
"$D/twd-saves.sh" verify "$TAG" | tail -1
# shellcheck disable=SC2086
"$D/deploy-sets.sh" status $AFTER | awk '{print $1, ($3==$5) ? "match" : "MISMATCH"}'
"$D/devrun.sh" unlock
