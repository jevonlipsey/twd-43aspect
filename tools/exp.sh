#!/usr/bin/env bash
# exp.sh NAME : deploy out/WDC.dev.exe, launch, shots NAME-1..3 (+30s each after load), stop, redeploy p6menu (menu-good baseline).
set -u; D="$(cd "$(dirname "$0")" && pwd)"; : "${ADB_SERIAL:?}"
"$D/devrun.sh" stop >/dev/null 2>&1
"$D/deploy.sh" dev 2>&1 | grep -E "deployed|deploy:"
"$D/devrun.sh" launch >/dev/null 2>&1
for i in 1 2 3; do "$D/devrun.sh" shot "$1-$i" >/dev/null; sleep 25; done
"$D/devrun.sh" stop >/dev/null 2>&1
"$D/deploy.sh" p6menu 2>&1 | grep -E "deployed|deploy:"
echo exp-done
