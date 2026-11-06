#!/usr/bin/env bash
# Install / remove the 4:3 UI mod (two new files in Archives/, no game file is overwritten).
#
#   tools/deploy-uimod.sh install    copy out/uimod/* into Archives/ (sha256-checked)
#   tools/deploy-uimod.sh remove     delete them again (= rollback; the game is then stock)
#   tools/deploy-uimod.sh --status   show whether the mod files are on the device
#
# Needs the device lock already held by twd-43aspect (tools/devrun.sh lock) for install/remove,
# and refuses while a game runs. The SD card is exFAT: new files get media_rw/0770 like the
# game's own, so no chown. ADB_SERIAL=<serial> for wireless adb.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
SD="${TWD_DEVICE_DIR:-/mnt/media_rw/6988-E33F/Android/data/com.droiddeck.launcher/files/steam/steamapps/common/The Walking Dead The Telltale Definitive Series}"
AR="$SD/Archives"
LOCK=/data/local/tmp/nova-43aspect.lock
FILES="_resdesc_50_PC_P43_Proj_01.lua WDC_pc_PC_p43_proj_compressed.ttarch2"
adbc() { adb ${ADB_SERIAL:+-s "$ADB_SERIAL"} "$@"; }
rsh() { adbc shell su 2>&1 | tr -d '\r'; }
die() { echo "deploy-uimod: $*" >&2; exit 1; }
dev_sha() { printf 'sha256sum "%s" 2>/dev/null\n' "$1" | rsh | awk '/^[0-9a-f]{64} /{print $1; exit}'; }

need_lock() {
  case "$(printf 'cat %s/owner\n' "$LOCK" | rsh)" in twd-43aspect\ *) ;; *) die "take the lock first (tools/devrun.sh lock)";; esac
  [ -z "$(printf "ps -A | grep -E 'gamescope|wineserver|WDC' | grep -v grep\n" | rsh)" ] || die "a game is running; not touching the device"
}

case "${1:-}" in
  --status)
    for f in $FILES; do echo "$f: $(dev_sha "$AR/$f")"; done;;
  install)
    need_lock
    for f in $FILES; do
      l="${UIMOD_DIR:-$REPO/out/uimod}/$f"; [ -f "$l" ] || die "$l missing (python3 tools/build_uimod.py)"
      want="$(shasum -a 256 "$l" | awk '{print $1}')"
      adbc push "$l" "/data/local/tmp/$f" >/dev/null || die "push failed"
      [ "$(dev_sha "/data/local/tmp/$f")" = "$want" ] || die "staged $f sha mismatch"
      printf 'cp "/data/local/tmp/%s" "%s/%s" && sync && rm -f "/data/local/tmp/%s"\n' "$f" "$AR" "$f" "$f" | rsh >/dev/null
      [ "$(dev_sha "$AR/$f")" = "$want" ] || die "installed $f sha mismatch"
      echo "installed $f $want"
    done
    printf 'ls -l "%s"/_resdesc_50_PC_P43* "%s"/WDC_pc_PC_p43*\n' "$AR" "$AR" | rsh;;
  remove)
    need_lock
    for f in $FILES; do printf 'rm -f "%s/%s"\n' "$AR" "$f" | rsh >/dev/null; [ -z "$(dev_sha "$AR/$f")" ] || die "could not remove $f"; echo "removed $f"; done;;
  *) sed -n '2,10p' "$0"; exit 2;;
esac
