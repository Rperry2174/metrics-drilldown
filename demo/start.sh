#!/usr/bin/env bash
# Local repro stack for grafana/metrics-drilldown#1481 (breakdown y-axis synced to an undrawn series), no Docker.
#   demo/exporter.py :9092 (seed: demo_queue_depth, 25 pods, 2h backfill) + Prometheus 2.53.2 :9091
#   + Grafana Enterprise 13.2.4 :3320 (needs >= 13.1) with ./dist mounted.
#   demo/start.sh [--build]     demo/stop.sh [--wipe]
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
DEMO_HOME="${DEMO_HOME:-$HOME/.cache/metrics-drilldown-demo}"
GF_VER="${GF_VER:-13.2.4}"; PROM_VER=2.53.2; GRAFANA_PORT=3320
mkdir -p "$DEMO_HOME"/{bin,run/plugins,run/prov/datasources,run/prov/plugins,logs,data}
os=$(uname -s | tr '[:upper:]' '[:lower:]'); arch=$(uname -m)
case "$arch" in x86_64|amd64) arch=amd64 ;; arm64|aarch64) arch=arm64 ;; esac
[ -x "$DEMO_HOME/bin/grafana-$GF_VER/bin/grafana" ] || "$REPO/demo/fetch-grafana.sh" "$GF_VER" "$DEMO_HOME/bin"
P="$DEMO_HOME/bin/prometheus-$PROM_VER.$os-$arch"
if [ ! -x "$P/prometheus" ]; then
  echo "downloading Prometheus $PROM_VER…"
  curl -fsSL "https://github.com/prometheus/prometheus/releases/download/v$PROM_VER/prometheus-$PROM_VER.$os-$arch.tar.gz" | tar xz -C "$DEMO_HOME/bin"
fi
[ -n "${DEMO_DOWNLOAD_ONLY:-}" ] && { echo "binaries ready in $DEMO_HOME/bin"; exit 0; }
if [ "${1:-}" = "--build" ] || [ ! -f "$REPO/dist/module.js" ]; then
  (cd "$REPO" && pnpm install --frozen-lockfile --ignore-scripts && pnpm run build)
fi
R="$DEMO_HOME/run"; D="$DEMO_HOME/data"
if [ ! -f "$R/exporter.pid" ] || ! kill -0 "$(cat "$R/exporter.pid")" 2>/dev/null; then
  nohup python3 "$REPO/demo/exporter.py" > "$DEMO_HOME/logs/exporter.log" 2>&1 < /dev/null & echo $! > "$R/exporter.pid"
fi
printf 'global: { scrape_interval: 15s }\nscrape_configs:\n  - job_name: demo\n    static_configs: [ { targets: ["127.0.0.1:9092"] } ]\n' > "$R/prometheus.yml"
if ! curl -sf http://127.0.0.1:9091/-/ready >/dev/null 2>&1; then
  rm -rf "$D/prom" && mkdir -p "$D/prom"
  python3 "$REPO/demo/exporter.py" backfill > "$R/backfill.om"
  "$P/promtool" tsdb create-blocks-from openmetrics "$R/backfill.om" "$D/prom" >/dev/null
  nohup "$P/prometheus" --config.file="$R/prometheus.yml" --storage.tsdb.path="$D/prom" \
    --web.listen-address=127.0.0.1:9091 > "$DEMO_HOME/logs/prom.log" 2>&1 < /dev/null & echo $! > "$R/prom.pid"
  for _ in $(seq 30); do curl -sf http://127.0.0.1:9091/-/ready >/dev/null 2>&1 && break; sleep 1; done
fi
cat > "$R/prov/datasources/prom.yaml" <<Y
apiVersion: 1
datasources:
  - { uid: md-prom, type: prometheus, name: Demo Prometheus, url: "http://127.0.0.1:9091", isDefault: true, jsonData: { timeInterval: 15s } }
Y
printf 'apiVersion: 1\napps:\n  - { type: grafana-metricsdrilldown-app, disabled: false }\n' > "$R/prov/plugins/app.yaml"
ln -sfn "$REPO/dist" "$R/plugins/grafana-metricsdrilldown-app"
if ! curl -sf "http://127.0.0.1:$GRAFANA_PORT/api/health" >/dev/null 2>&1; then
  G="$DEMO_HOME/bin/grafana-$GF_VER"
  GF_PATHS_DATA="$D/grafana" GF_PATHS_LOGS="$DEMO_HOME/logs" GF_PATHS_PLUGINS="$R/plugins" GF_PATHS_PROVISIONING="$R/prov" \
  GF_SERVER_HTTP_PORT=$GRAFANA_PORT GF_AUTH_ANONYMOUS_ENABLED=true GF_AUTH_ANONYMOUS_ORG_ROLE=Admin GF_AUTH_DISABLE_LOGIN_FORM=true \
  GF_PLUGINS_ALLOW_LOADING_UNSIGNED_PLUGINS=grafana-metricsdrilldown-app GF_PLUGINS_PREINSTALL_DISABLED=true \
  GF_ANALYTICS_REPORTING_ENABLED=false GF_ANALYTICS_CHECK_FOR_UPDATES=false GF_NEWS_NEWS_FEED_ENABLED=false \
  nohup "$G/bin/grafana" server --homepath "$G" > "$DEMO_HOME/logs/grafana.stdout" 2>&1 < /dev/null & echo $! > "$R/grafana.pid"
  for _ in $(seq 90); do curl -sf "http://127.0.0.1:$GRAFANA_PORT/api/health" >/dev/null 2>&1 && break; sleep 1; done
fi
echo "up: Grafana :$GRAFANA_PORT, Prometheus :9091, exporter :9092"
