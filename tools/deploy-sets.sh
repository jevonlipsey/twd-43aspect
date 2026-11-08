#!/usr/bin/env bash
# Install / remove resource-set patches (descriptor + archive pairs) in Archives/, sha256-checked. No game file is
# overwritten: every file is NEW (refuses if a same-named file is already there with other content).
#
#   tools/deploy-sets.sh install <dir>...   copy <dir>/_resdesc_50_*.lua + <dir>/WDC_pc_*.ttarch2 into Archives/
#   tools/deploy-sets.sh remove  <dir>...   delete those file names from Archives/ (= rollback)
#   tools/deploy-sets.sh status  <dir>...   device sha256 of each (read only, no lock)
# e.g. the one-run test: out/fix43t_S1 out/fix43t_S2 out/fix43t_S3 out/fix43t_S4 out/fix43t_M out/tour43t
# install/remove need the device lock held by twd-43aspect (tools/devrun.sh lock) and refuse while a game runs.
# The SD card is exFAT: new files get media_rw/0770 like the game's own, so no chown. ADB_SERIAL=<serial>.
set -u
SD="${TWD_DEVICE_DIR:-/mnt/media_rw/6988-E33F/Android/data/com.droiddeck.launcher/files/steam/steamapps/common/The Walking Dead The Telltale Definitive Series}"
AR="$SD/Archives"
LOCK=/data/local/tmp/nova-43aspect.lock
adbc() { adb ${ADB_SERIAL:+-s "$ADB_SERIAL"} "$@"; }
rsh() { adbc shell su 2>&1 | tr -d '\r'; }
die() { echo "deploy-sets: $*" >&2; exit 1; }
dev_sha() { printf 'sha256sum "%s" 2>/dev/null\n' "$1" | rsh | awk '/^[0-9a-f]{64} /{print $1; exit}'; }
need_lock() {
  case "$(printf 'cat %s/owner\n' "$LOCK" | rsh)" in twd-43aspect\ *) ;; *) die "take the lock first (tools/devrun.sh lock)";; esac
  [ -z "$(printf "ps -A | grep -E 'gamescope|wineserver|WDC' | grep -v grep\n" | rsh)" ] || die "a game is running; not touching the device"
}
CMD="${1:-}"; shift || true
[ $# -gt 0 ] || { sed -n '2,10p' "$0"; exit 2; }
FILES=()
for d in "$@"; do
  for f in "$d"/_resdesc_50_*.lua "$d"/WDC_pc_*.ttarch2; do [ -f "$f" ] || die "missing set files in $d"; FILES+=("$f"); done
done
case "$CMD" in
  status)
    for l in "${FILES[@]}"; do s="$(dev_sha "$AR/$(basename "$l")")"; echo "$(basename "$l"): device ${s:-absent} local $(shasum -a 256 "$l" | awk '{print $1}')"; done;;
  install)
    need_lock
    for l in "${FILES[@]}"; do
      f="$(basename "$l")"; want="$(shasum -a 256 "$l" | awk '{print $1}')"
      have="$(dev_sha "$AR/$f")"
      [ -z "$have" ] || [ "$have" = "$want" ] || die "$f already on the device with other content ($have); not overwriting"
      adbc push "$l" "/data/local/tmp/$f" >/dev/null || die "push $f failed"
      [ "$(dev_sha "/data/local/tmp/$f")" = "$want" ] || die "staged $f sha mismatch"
      printf 'cp "/data/local/tmp/%s" "%s/%s" && sync && rm -f "/data/local/tmp/%s"\n' "$f" "$AR" "$f" "$f" | rsh >/dev/null
      [ "$(dev_sha "$AR/$f")" = "$want" ] || die "installed $f sha mismatch"
      echo "installed $f $want"
    done;;
  remove)
    need_lock
    for l in "${FILES[@]}"; do
      f="$(basename "$l")"
      printf 'rm -f "%s/%s"\n' "$AR" "$f" | rsh >/dev/null
      [ -z "$(dev_sha "$AR/$f")" ] || die "could not remove $f"; echo "removed $f"
    done;;
  *) sed -n '2,10p' "$0"; exit 2;;
esac
