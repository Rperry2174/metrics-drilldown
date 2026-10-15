"""Demo exporter for metrics-drilldown #1481: demo_queue_depth gauge with 25 `pod` values.
pod-00..pod-23 sit around 30-50; pod-24 (sorts 25th, outside the 20 drawn) sits at ~1000."""
import math, sys, time
from http.server import BaseHTTPRequestHandler, HTTPServer
REGIONS = ["us-east", "us-west", "eu-west"]
def value(i, t):
    return 1000.0 if i == 24 else 40 + 10 * math.sin(t / 120 + i)
def lines(t, ts=None):
    out = ["# TYPE demo_queue_depth gauge"]
    for i in range(25):
        sfx = f" {ts}" if ts is not None else ""
        out.append(f'demo_queue_depth{{pod="pod-{i:02d}"}} {value(i,t):.3f}{sfx}')
    return out
class H(BaseHTTPRequestHandler):
    def do_GET(self):
        b = ("\n".join(lines(time.time())) + "\n").encode()
        self.send_response(200); self.send_header("Content-Type", "text/plain; version=0.0.4"); self.end_headers(); self.wfile.write(b)
    def log_message(self, *a): pass
if __name__ == "__main__":
    if sys.argv[1:] == ["backfill"]:  # OpenMetrics for promtool: last 2h at 15s, ending 2 min ago
        now = int(time.time()) - 120
        print("# TYPE demo_queue_depth gauge")
        for t in range(now - 7200, now, 15):
            for l in lines(t, t)[1:]: print(l.replace("{", '{instance="127.0.0.1:9092",job="demo",', 1))
        print("# EOF")
    else:
        HTTPServer(("127.0.0.1", 9092), H).serve_forever()
