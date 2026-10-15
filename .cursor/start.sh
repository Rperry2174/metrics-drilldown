#!/usr/bin/env bash
# Cloud Agent start step: (re)start the backend + Grafana with ./dist mounted, and seed.
set -uo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.local/node22/bin:$HOME/.local/bin:$PATH"
pkill -f "grafana server" 2>/dev/null || true   # saved grafana pids are unreliable
demo/stop.sh >/dev/null 2>&1 || true
for i in $(seq 1 30); do pgrep -f "grafana server" >/dev/null 2>&1 || break; [ "$i" -eq 20 ] && pkill -9 -f "grafana server"; sleep 1; done
demo/start.sh
