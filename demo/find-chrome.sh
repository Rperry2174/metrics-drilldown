#!/usr/bin/env bash
# Print a Chromium-family executable Playwright can drive, or fail if there is none.
# Prefers Playwright's own download and falls back to a system Chrome, which is what
# restricted-egress sandboxes are left with when the download host is blocked.
set -euo pipefail
[ -n "${CHROME:-}" ] && { echo "$CHROME"; exit 0; }
if python3 -c 'import sys
from playwright.sync_api import sync_playwright
with sync_playwright() as p:
    sys.exit(0 if __import__("os").path.exists(p.chromium.executable_path) else 1)' 2>/dev/null; then
  exit 0   # Playwright has its own browser; callers should leave CHROME unset
fi
for c in /opt/google/chrome/chrome google-chrome google-chrome-stable chromium chromium-browser; do
  path=$(command -v "$c" 2>/dev/null || { [ -x "$c" ] && echo "$c"; }) || true
  [ -n "${path:-}" ] && { echo "$path"; exit 0; }
done
echo "no Chromium found: run 'python3 -m playwright install chromium' or set CHROME" >&2
exit 1
