"""Fails while grafana/metrics-drilldown#1481 exists: in the Breakdown grid, the y-axis is synced to a series
that is never drawn. Seed: demo_queue_depth with 25 `pod` values; pod-24 (~1000, ranks 25th) is cut by
sliceSeries(0, 20), the 20 drawn pods sit at 30-50, the other panels (avg) top out ~80.
Pre-fix: synced max ~1000 -> the drawn pod lines are squashed into the bottom ~2% of the plot.
Post-fix: synced max ~100 -> the drawn pod lines reach well above 20% of the plot height.
Run: demo/repro-check.sh   (stack: demo/start.sh)
Env: GRAFANA_PORT (3320), SHOT (screenshot path), CHROME."""
import os, json, sys
from playwright.sync_api import sync_playwright
PORT = os.environ.get("GRAFANA_PORT", "3320")
URL = (f"http://127.0.0.1:{PORT}/a/grafana-metricsdrilldown-app/drilldown?metric=demo_queue_depth"
       "&actionView=breakdown&var-ds=md-prom&var-groupby=$__all&layout=grid&from=now-1h&to=now")
HERE = os.path.dirname(os.path.abspath(__file__))
SHOT = os.environ.get("SHOT", os.path.join(HERE, "last-run.png"))
JS = r"""() => {
  const h = [...document.querySelectorAll('h2')].find(e => e.textContent.trim().startsWith('pod ('));
  if (!h) return null;
  let panel = h; while (panel && !panel.querySelector('.u-over')) panel = panel.parentElement;
  const over = panel.querySelector('.u-over'), cv = panel.querySelector('canvas');
  const o = over.getBoundingClientRect(), c = cv.getBoundingClientRect();
  const sx = cv.width / c.width, sy = cv.height / c.height;
  const x0 = Math.round((o.left - c.left) * sx), y0 = Math.round((o.top - c.top) * sy);
  const w = Math.round(o.width * sx), hgt = Math.round(o.height * sy);
  const d = cv.getContext('2d').getImageData(x0, y0, w, hgt).data;
  let top = null;
  for (let y = 0; y < hgt && top === null; y++) for (let x = 0; x < w; x++) {
    const i = (y * w + x) * 4, r = d[i], g = d[i+1], b = d[i+2], a = d[i+3];
    if (a > 100 && Math.max(r, g, b) - Math.min(r, g, b) > 60) { top = y; break; }
  }
  const box = panel.getBoundingClientRect();
  return { title: h.textContent.trim(), plotHeightPx: hgt,
           highestDrawnLineFraction: top === null ? 0 : +(1 - top / hgt).toFixed(3),
           panel: { x: box.x, y: box.y + window.scrollY, width: box.width, height: box.height } };
}"""

def measure():
    with sync_playwright() as p:
        b = p.chromium.launch(args=["--no-sandbox"], **({"executable_path": os.environ["CHROME"]} if os.environ.get("CHROME") else {}))
        pg = b.new_page(viewport={"width": 1440, "height": 1000})
        pg.goto(URL, wait_until="load", timeout=90000)
        pg.wait_for_selector("h2:has-text('pod (')", timeout=60000)
        pg.wait_for_timeout(5000)  # let all panels load so the y-axis sync settles
        r = pg.evaluate(JS)
        pg.screenshot(path=SHOT)
        b.close()
    return r

def test_breakdown_yaxis_matches_drawn_series():
    r = measure()
    print(json.dumps(r))
    assert r, "no 'pod (N)' breakdown panel - is Prometheus seeded (kit/start.sh)?"
    assert r["highestDrawnLineFraction"] > 0.2, (
        "Breakdown y-axis is scaled by an undrawn series: the 20 drawn pod lines only reach "
        f"{r['highestDrawnLineFraction']:.1%} of the plot height (#1481)")

if __name__ == "__main__":
    try:
        test_breakdown_yaxis_matches_drawn_series(); print("PASS")
    except AssertionError as e:
        print("FAIL:", e); sys.exit(1)
