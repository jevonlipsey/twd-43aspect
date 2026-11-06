#!/usr/bin/env bash
# Device test helpers (root adb). ADB_SERIAL required.
#   devrun.sh lock|unlock take/release the shared device lock (launch requires it)
#   devrun.sh launch      dismiss dialog, launch TWD in Steam mode, wait for WDC.exe
#   devrun.sh shot NAME   screenshot to screenshots/NAME.png
#   devrun.sh btn CODE    tap a pad button (304 A, 305 B, 307 X, 308 Y, 315 START)
#   devrun.sh hat X Y     d-pad pulse (ABS_HAT0X/Y -1/0/1)
#   devrun.sh stop        dd-stop and release the lock
set -u
R="$(cd "$(dirname "$0")/.." && pwd)"; S="${ADB_SERIAL:?}"; LOCK=/data/local/tmp/nova-43aspect.lock
rs() { adb -s "$S" shell su; }
case "$1" in
lock)   # take the shared lock; exit 1 unless we own it and no game runs
  printf 'mkdir %s 2>/dev/null && { echo "twd-43aspect $(date +%%s)" > %s/owner || rmdir %s; }\n' $LOCK $LOCK $LOCK | rs >/dev/null
  o="$(printf 'cat %s/owner\n' $LOCK | rs | tr -d '\r')"; echo "lock owner: $o"
  case "$o" in twd-43aspect\ *) ;; *) exit 1;; esac
  p="$(printf "ps -A | grep -E 'gamescope|wineserver|WDC' | grep -v grep\n" | rs | tr -d '\r')"
  [ -z "$p" ] || { echo "game running, releasing: $p"; printf 'rm -rf %s\n' $LOCK | rs; exit 1; };;
unlock) printf 'rm -rf %s\n' $LOCK | rs; echo unlocked;;
launch)
  case "$(printf 'cat %s/owner\n' $LOCK | rs | tr -d '\r')" in twd-43aspect\ *) ;; *) echo "not our lock; run: devrun.sh lock"; exit 1;; esac
  python3 -I ~/.claude/skills/nova-43aspect/tools/dd-dismiss.py 2>&1 | tail -1
  adb -s "$S" shell input keyevent KEYCODE_WAKEUP
  printf 'wm dismiss-keyguard\nam force-stop com.droiddeck.launcher\ninput keyevent KEYCODE_HOME\nsleep 2\nam start -a android.intent.action.VIEW -d "droiddeck://game/1449690" com.droiddeck.launcher/.FrontEndActivity\n' | rs
  for i in $(seq 1 15); do sleep 10; adb -s "$S" shell su -c "ps -A | grep -c WDC.exe" | grep -q '^[1-9]' && break; done
  sleep 45; echo launched;;
shot) mkdir -p "$R/screenshots"; adb -s "$S" exec-out screencap -p > "$R/screenshots/$2.png"; echo "$R/screenshots/$2.png";;
btn) printf 'N=/dev/input/event7\nsendevent $N 1 %s 1; sendevent $N 0 0 0; sleep 0.15; sendevent $N 1 %s 0; sendevent $N 0 0 0\n' "$2" "$2" | rs;;
hat) printf 'N=/dev/input/event7\nsendevent $N 3 16 %s; sendevent $N 3 17 %s; sendevent $N 0 0 0; sleep 0.15; sendevent $N 3 16 0; sendevent $N 3 17 0; sendevent $N 0 0 0\n' "$2" "$3" | rs;;
cycle) "$0" launch >/dev/null 2>&1; sleep 30; "$0" shot "$2-g"; "$0" btn 315; sleep 5; "$0" shot "$2-m";;
stop) python3 -I ~/.claude/skills/nova-43aspect/tools/dd-stop.py --owner twd-43aspect 2>&1 | tail -1; printf 'rm -rf %s\n' $LOCK | rs;;
esac
