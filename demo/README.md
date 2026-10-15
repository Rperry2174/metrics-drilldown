# metrics-drilldown #1481 repro kit

`demo-base` is pinned to 65026f0957 (pre-fix; fixed upstream in PR #1482) plus this demo/ kit and `.cursor/`.

- `demo/start.sh [--build]`: exporter :9092 (seed `demo_queue_depth`, 25 pods, 2h backfill), Prometheus 2.53.2 :9091, Grafana 13.2.4 :3320 (./dist mounted; needs >= 13.1)
- `demo/repro-check.sh`: exit 1 while the y-axis is synced to the undrawn outlier (expected pre-fix), 0 once fixed
- `demo/stop.sh [--wipe]`

No Docker needed. Grafana falls back to Docker Hub image layers when dl.grafana.com is blocked; the check falls back to system Chrome.
PRs from agents go to Rperry2174/metrics-drilldown only, never grafana/*.
