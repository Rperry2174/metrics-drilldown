#!/usr/bin/env bash
# repro check for grafana/metrics-drilldown#1481 (breakdown y-axis synced to a series that is never drawn).
# Exit 1 while the bug exists (expected on demo-base / pre-fix), 0 once fixed. Stack must be up (demo/start.sh).
set -uo pipefail
cd "$(dirname "$0")"
CHROME="$(./find-chrome.sh)"; export CHROME
python3 repro_check.py "$@"; rc=$?
[ $rc -eq 0 ] && echo "PASS (y-axis fits drawn series)" || echo "FAIL (bug reproduced or stack not ready), exit $rc"
exit $rc
