#!/usr/bin/env bash
# Cloud Agent install step (runs once per Build, from the repo root).
# Node 22 + corepack/pnpm, deps, plugin build, Grafana + backend binaries, Playwright Chromium.
set -euo pipefail
if ! node -v 2>/dev/null | grep -q '^v22'; then
  arch=$(uname -m); case "$arch" in x86_64) arch=x64;; aarch64) arch=arm64;; esac
  mkdir -p "$HOME/.local/node22"
  curl -fsSL "https://nodejs.org/dist/latest-v22.x/" | grep -o "node-v22[0-9.]*-linux-$arch.tar.xz" | head -1 \
    | xargs -I{} curl -fsSL "https://nodejs.org/dist/latest-v22.x/{}" | tar xJ -C "$HOME/.local/node22" --strip-components=1
  export PATH="$HOME/.local/node22/bin:$PATH"
  grep -q node22 "$HOME/.bashrc" 2>/dev/null || echo 'export PATH="$HOME/.local/node22/bin:$PATH"' >> "$HOME/.bashrc"
fi
mkdir -p "$HOME/.local/bin"   # corepack realpath()s --install-directory and fails if it is missing
corepack enable --install-directory "$HOME/.local/bin" 2>/dev/null || corepack enable
export PATH="$HOME/.local/bin:$PATH"
grep -q '.local/bin' "$HOME/.bashrc" 2>/dev/null || echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
pnpm install --frozen-lockfile --ignore-scripts
pnpm run build
# download Grafana + backend without starting them
DEMO_DOWNLOAD_ONLY=1 demo/start.sh
python3 -m pip install --user -q playwright pytest 2>/dev/null || python3 -m pip install --user --break-system-packages -q playwright pytest
# Playwright's own Chromium comes from storage.googleapis.com, which restricted-egress
# sandboxes block; demo/repro-check.sh falls back to a system Chrome when it is missing.
python3 -m playwright install --with-deps chromium || python3 -m playwright install chromium \
  || demo/find-chrome.sh >/dev/null
