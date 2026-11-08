#!/bin/sh
# Back up / restore / verify the WHOLE TWD save folder on the Nova (root adb), sha256 per file.
#   ADB_SERIAL=<serial> tools/twd-saves.sh backup  <tag>   game must be STOPPED; device copy in /data/local/tmp/twd-saves-<tag>/,
#                                                          Mac copy in backup/saves-<tag>.tar + .sha256 (tar sha256 compared)
#   ADB_SERIAL=<serial> tools/twd-saves.sh restore <tag>   game must be STOPPED; the post-run folder is moved aside to
#                                                          /data/local/tmp/twd-saves-<tag>/after-run, the backup untarred,
#                                                          owner 10114:10114 + the folder's SELinux label put back, verified
#   ADB_SERIAL=<serial> tools/twd-saves.sh verify  <tag>   per-file sha256 of the live folder == the backup list
# Root-created files get the creator's label (no app categories), which the app could not open: hence the chcon.
set -eu
S=${ADB_SERIAL:-}; CMD=${1:?backup|restore|verify}; TAG=${2:?tag}
HERE=$(cd "$(dirname "$0")/.." && pwd)
P="/data/data/com.droiddeck.launcher/files/steam-libraries/71c675dbc64e2fa92fdc8a03ff254774f0fb309aa975c484f0c5d2acd9f97a9f/steamapps/compatdata/1449690/pfx/drive_c/users/steamuser/Documents/Telltale Games"
N="The Walking Dead Definitive"
B="/data/local/tmp/twd-saves-$TAG"
CTX="u:object_r:app_data_file:s0:c114,c256,c512,c768"
# TWD_SAVES_LOCAL=1 (Mac self-test): run the device half with sh against TWD_SAVES_P / TWD_SAVES_B, no chown/chcon
if [ "${TWD_SAVES_LOCAL:-}" = 1 ]; then
  P=${TWD_SAVES_P:?}; B=${TWD_SAVES_B:?}; OWN=true; LBL=true
  root() { sh; }
else
  OWN=chown; LBL=chcon
  root() { adb -s "$S" shell su; }
fi
case "$CMD" in
backup)
  root <<EOF
set -e
[ ! -e "$B/saves.tar" ] || { echo "backup $B exists, refusing to overwrite"; exit 1; }
mkdir -p "$B"
cd "$P"
tar -cf "$B/saves.tar" "$N"
cd "$P/$N" && find . -type f -exec sha256sum {} + | sort -k2 > "$B/saves.sha256"
ls -laZR "$P/$N" > "$B/saves.ls" 2>/dev/null || ls -laR "$P/$N" > "$B/saves.ls"
sha256sum "$B/saves.tar"; wc -l < "$B/saves.sha256"
EOF
  [ "${TWD_SAVES_LOCAL:-}" = 1 ] && exit 0
  mkdir -p "$HERE/backup"
  adb -s "$S" exec-out su -c "cat $B/saves.tar" > "$HERE/backup/saves-$TAG.tar"
  adb -s "$S" exec-out su -c "cat $B/saves.sha256" > "$HERE/backup/saves-$TAG.sha256"
  shasum -a 256 "$HERE/backup/saves-$TAG.tar"
  echo "compare the two tar hashes above; per-file list: backup/saves-$TAG.sha256 ($(wc -l < "$HERE/backup/saves-$TAG.sha256") files)"
  ;;
restore)
  root <<EOF
set -e
[ -s "$B/saves.tar" ] && [ -s "$B/saves.sha256" ] || { echo "no backup at $B"; exit 1; }
[ ! -e "$B/after-run" ] || { echo "$B/after-run exists (restore already ran?)"; exit 1; }
mv "$P/$N" "$B/after-run"
cd "$P" && tar -xf "$B/saves.tar"
$OWN -R 10114:10114 "$P/$N"
$LBL -R "$CTX" "$P/$N"
cd "$P/$N" && find . -type f -exec sha256sum {} + | sort -k2 > "$B/restored.sha256"
if diff "$B/saves.sha256" "$B/restored.sha256" >/dev/null; then echo "RESTORE OK (\$(wc -l < "$B/restored.sha256") files)"; else echo "RESTORE MISMATCH"; diff "$B/saves.sha256" "$B/restored.sha256" | head; exit 1; fi
ls -ldZ "$P/$N" 2>/dev/null || true
EOF
  ;;
verify)
  root <<EOF
cd "$P/$N" && find . -type f -exec sha256sum {} + | sort -k2 > "$B/now.sha256"
if diff "$B/saves.sha256" "$B/now.sha256" >/dev/null; then echo "VERIFY OK (\$(wc -l < "$B/now.sha256") files)"; else echo "VERIFY DIFF:"; diff "$B/saves.sha256" "$B/now.sha256" | head -20; fi
EOF
  ;;
*) echo "usage: $0 backup|restore|verify <tag>"; exit 2 ;;
esac
