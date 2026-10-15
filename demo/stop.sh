#!/usr/bin/env bash
# Stop the demo stack (pattern-based: saved Grafana pids are unreliable). --wipe deletes data.
DEMO_HOME="${DEMO_HOME:-$HOME/.cache/metrics-drilldown-demo}"
pkill -f "$DEMO_HOME/bin/grafana-" 2>/dev/null; pkill -f "$DEMO_HOME/bin/prometheus-" 2>/dev/null
[ -f "$DEMO_HOME/run/exporter.pid" ] && kill "$(cat "$DEMO_HOME/run/exporter.pid")" 2>/dev/null
rm -f "$DEMO_HOME"/run/*.pid
[ "${1:-}" = "--wipe" ] && rm -rf "$DEMO_HOME/data" && echo "wiped $DEMO_HOME/data"
exit 0
