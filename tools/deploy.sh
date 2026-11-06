#!/usr/bin/env bash
# Deploy a WDC.exe build to the Nova over root adb, with sha256 checks on both ends.
#
#   tools/deploy.sh <build>       build = pristine | unstub | p1 (see BUILDS below)
#   tools/deploy.sh --rollback    restore the pristine exe from WDC.exe.orig
#   tools/deploy.sh --status      report which known build is on the device (no lock, read only)
#
# Streets of Rage 4 runs in STEAM MODE ONLY: there is no DROIDDECK_NO_STEAM entry for appid
# 1449690 (no-Steam mode cannot start WDC even pristine). This script never launches anything;
# launch with the plain intent from the READY TO TEST card in CLAUDE.local.md:
#   am start -a android.intent.action.VIEW -d "droiddeck://game/1449690" com.droiddeck.launcher/.FrontEndActivity
#
# Safety: takes the shared device lock (/data/local/tmp/nova-43aspect.lock, with the || rmdir
# idiom), refuses if gamescope/wineserver is running (the user may be playing), refuses unless the
# exe on the device is a known build, never touches WDC.exe.orig, and keeps owner/mode by
# copying over the existing file (exFAT: owner media_rw, mode -rwxrwx---; no chown needed).
# Run it from anywhere. ADB_SERIAL=<serial> if more than one device is attached.
set -u

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SD="${TWD_DEVICE_DIR:-/mnt/media_rw/6988-E33F/Android/data/com.droiddeck.launcher/files/steam/steamapps/common/The Walking Dead The Telltale Definitive Series}"
EXE="$SD/WDC.exe"
ORIG="$SD/WDC.exe.orig"
STAGE="/data/local/tmp/WDC.exe.stage"
LOCK="/data/local/tmp/nova-43aspect.lock"
ADB="${ADB:-adb}"
adbc() { "$ADB" ${ADB_SERIAL:+-s "$ADB_SERIAL"} "$@"; }

# known builds: name|local file|sha256 (the local file is re-hashed before anything is pushed)
PRISTINE=5f44e53fcaec4c59c8c2f79403722076fc1c518c0d006d2a1262efeaec656782
BUILDS="pristine|original/WDC.exe|$PRISTINE
unstub|out/WDC.unstub.exe|e94771718e7a7ce709d1eea6e7f104ffe437f4019ed8636b90226062357d7327
p1|out/WDC.p1.exe|164697f8b5b186f18e83d0db2e9d43c6fc7777e194219070896a1b1df16780fb
p2|out/WDC.p2.exe|837ebcc19dfd199087519efc56b8dfdc636a4e6515c1571d0aa8e6106a65dba6
p3|out/WDC.p3.exe|81c5ae701b115bfa33dc3dc78072af71c1804fa10c5312d9da7758b5f5467cbe
p4|out/WDC.p4.exe|34057cec41760e32979982abf80f11ad3b9b68e90320b74b9827c950d9a4f89a
p5|out/WDC.p5.exe|0d28c37cda5bea3c528232a441e4da7b34435980adb6842fec55dc8673332e7c
dbg|out/WDC.dbg.exe|cd023e8f196ee240b7e62a7537086a618d68a7de3ef3e75ec9134cb60b593546
dbgv1|out/WDC.dbgv1.exe|b4185f1f3bfe4a8b734d0150945c5591e64931198a0a7eef03e916077c50612b
dbgv2|out/WDC.dbgv2.exe|00aa203f9261df72b7b21f10fb533ee99cbf07813eccc9c1a9d2dabba47ef357
dbgv4|out/WDC.dbgv4.exe|cddae604eeb29dad7de2b0c7ee11c18494f81c7d3aa832acb8fa06669bbec2d9
dbgv5|out/WDC.dbgv5.exe|f7c5d1ed1d809db6dd7a40093ca5ab037bed3bef1885e220051a09a0f2d4dba7
p6menu|out/WDC.p6menu.exe|0884f3fed72b76e70b73540357a9b7643b00853f907bfffc6377f2e984ad683b
dbg0|out/WDC.dbg0.exe|1084b4f1760a723723609e270c83900bc9ea536fd7e9a81c9fd34cba6516856a
dbgv3|out/WDC.dbgv3.exe|397f591a692778cc1ab25a482408a3b4503cd6ca844c199be0d68aa61601c302"

PFX="${TWD_PREFIX_DOCS:-/data/data/com.droiddeck.launcher/files/steam-libraries/71c675dbc64e2fa92fdc8a03ff254774f0fb309aa975c484f0c5d2acd9f97a9f/steamapps/compatdata/1449690/pfx/drive_c/users/steamuser/Documents/Telltale Games/The Walking Dead Definitive}"
HAVE_LOCK=0
die() { echo "deploy: $*" >&2; exit 1; }
rsh() { adbc shell su 2>&1 | tr -d '\r'; }   # root script on stdin
name_of() { local n; n="$(echo "$BUILDS" | awk -F'|' -v h="$1" '$3==h {print $1}')"; [ -n "$n" ] || { grep -qs "^$1" "$REPO/out/dev-hashes.txt" && n=dev; }; echo "$n"; }
dev_sha() { printf 'sha256sum "%s"\n' "$1" | rsh | awk '/^[0-9a-f]{64} /{print $1; exit}'; }
dev_ls() { printf 'ls -l "%s"\n' "$1" | rsh | head -n 1 | awk '{print $1, $3, $4}'; }

release() {
  if [ "$HAVE_LOCK" = 1 ]; then
    printf 'rm -rf %s\n' "$LOCK" | rsh >/dev/null
    HAVE_LOCK=0
    echo "lock released"
  fi
}
trap release EXIT

take_lock() {
  if [ "${TWD_LOCK_HELD:-0}" = 1 ]; then   # caller already holds the lock (e.g. devrun.sh lock); verify, never release it
    case "$(printf 'cat %s/owner\n' "$LOCK" | rsh)" in twd-43aspect\ *) echo "using the lock we already hold"; return;; esac
    die "TWD_LOCK_HELD=1 but the lock is not ours"
  fi
  # mkdir is atomic; the || rmdir cleans up an owner-less lock if the owner write fails
  rsh <<LOCKEOF >/dev/null
mkdir $LOCK 2>/dev/null && { echo "twd-43aspect \$(date +%s)" > $LOCK/owner || rmdir $LOCK; }
LOCKEOF
  local o
  o="$(printf 'cat %s/owner\n' "$LOCK" | rsh)"
  case "$o" in
    twd-43aspect\ *) HAVE_LOCK=1; echo "lock taken ($o)";;
    *) die "device lock is held by another agent (owner: ${o:-<none; if the dir exists with no owner file, rmdir it after confirming no game runs>}); try again later";;
  esac
}

no_game_running() {
  local p
  p="$(printf "ps -A -f | grep -E 'gamescope|wineserver|WDC' | grep -v grep\n" | rsh)"
  [ -z "$p" ] || die "a game session looks active, the user may be playing; not touching the device:
$p"
}

check_orig() {
  local s
  s="$(dev_sha "$ORIG")"
  if [ -z "$s" ]; then   # first deploy: keep the pristine exe beside the live one (only if live is pristine)
    [ "$(dev_sha "$EXE")" = "$PRISTINE" ] || die "$ORIG missing and live exe is not pristine; refusing"
    printf 'cp "%s" "%s" && sync\n' "$EXE" "$ORIG" | rsh >/dev/null
    s="$(dev_sha "$ORIG")"
  fi
  [ "$s" = "$PRISTINE" ] || die "$ORIG sha is '${s:-missing}', expected pristine $PRISTINE; refusing"
  echo "WDC.exe.orig is pristine ($s)"
}

backup_saves() {   # small: prefs + save bundles only, copied next to nothing big; timestamped, never overwritten
  local b="/data/local/tmp/twd-saves-$(date +%Y%m%d-%H%M%S)"
  rsh <<BKEOF >/dev/null
mkdir -p $b
cd "$PFX" && for f in prefs.prop ttcd.prop wd1_saveslot*.bundle _wd1_saveslot*_autosave.bundle; do cp -p "\$f" $b/ 2>/dev/null; done
BKEOF
  echo "saves backed up to $b on device:"
  printf 'sha256sum %s/*\n' "$b" | rsh | awk '{print "  " $1 "  " $2}'
}

current_build() {
  local s n
  s="$(dev_sha "$EXE")"
  [ -n "$s" ] || die "cannot read $EXE (device not connected, or no root?)"
  n="$(name_of "$s")"
  echo "device WDC.exe sha256 $s => ${n:-UNKNOWN}" >&2
  [ -n "$n" ] || die "the exe on the device is not a known build; investigate before overwriting"
  echo "$n"
}

case "${1:-}" in
  --status)
    adbc get-state >/dev/null 2>&1 || die "no adb device"
    current_build >/dev/null
    echo "mode owner group: $(dev_ls "$EXE")"
    exit 0;;
  --rollback)
    adbc get-state >/dev/null 2>&1 || die "no adb device"
    take_lock; no_game_running; check_orig
    before="$(dev_ls "$EXE")"
    printf 'cp "%s" "%s" && sync\n' "$ORIG" "$EXE" | rsh >/dev/null
    s="$(dev_sha "$EXE")"
    [ "$s" = "$PRISTINE" ] || die "rollback FAILED: device exe sha is $s"
    after="$(dev_ls "$EXE")"
    echo "rolled back: device exe is pristine ($s); mode/owner before '$before' after '$after'"
    exit 0;;
  ""|-h|--help|-*)
    sed -n '2,19p' "$0"; exit 2;;
esac

BUILD="$1"
if [ "$BUILD" = dev ]; then   # out/WDC.dev.exe, any content; hash recorded in out/dev-hashes.txt
  h="$(shasum -a 256 "$REPO/out/WDC.dev.exe" | awk '{print $1}')"; echo "$h" >> "$REPO/out/dev-hashes.txt"
  BUILDS="$BUILDS
dev|out/WDC.dev.exe|$h"
fi
line="$(echo "$BUILDS" | awk -F'|' -v b="$BUILD" '$1==b')"
[ -n "$line" ] || die "unknown build '$BUILD' (pristine | unstub | p1 ...)"
LOCAL="$REPO/$(echo "$line" | cut -d'|' -f2)"
WANT="$(echo "$line" | cut -d'|' -f3)"
[ -f "$LOCAL" ] || die "$LOCAL does not exist (build it: see CLAUDE.local.md)"
got="$(shasum -a 256 "$LOCAL" | awk '{print $1}')"
[ "$got" = "$WANT" ] || die "$LOCAL sha is $got, expected $WANT"
echo "local $BUILD: $LOCAL ($WANT)"

adbc get-state >/dev/null 2>&1 || die "no adb device"
take_lock
no_game_running
check_orig
backup_saves
cur="$(current_build)" || exit 1
before="$(dev_ls "$EXE")"
echo "device exe before: $cur, mode/owner/group: $before"
if [ "$cur" = "$BUILD" ] && [ "$(dev_sha "$EXE")" = "$WANT" ]; then echo "already deployed; nothing to do"; exit 0; fi

adbc push "$LOCAL" "$STAGE" >/dev/null || die "adb push failed"
s="$(dev_sha "$STAGE")"
[ "$s" = "$WANT" ] || { printf 'rm -f %s\n' "$STAGE" | rsh >/dev/null; die "staged copy sha is '$s', expected $WANT; device exe untouched"; }
echo "staged and verified on device"
printf 'cp "%s" "%s" && sync && rm -f %s\n' "$STAGE" "$EXE" "$STAGE" | rsh >/dev/null
s="$(dev_sha "$EXE")"
if [ "$s" != "$WANT" ]; then
  die "deployed sha is '$s', expected $WANT. The exe may be corrupt: run  tools/deploy.sh --rollback"
fi
after="$(dev_ls "$EXE")"
echo "deployed $BUILD; device exe sha256 $s"
echo "mode/owner/group before '$before' after '$after'"
[ "$before" = "$after" ] || echo "WARNING: mode/owner changed; fix by hand before launching" >&2
check_orig
echo "next: launch in Steam mode (see READY TO TEST in CLAUDE.local.md). Roll back with: tools/deploy.sh --rollback"
