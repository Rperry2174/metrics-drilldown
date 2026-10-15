#!/usr/bin/env bash
# Install the Grafana Enterprise $1 tarball into $2, leaving $2/grafana-$1/bin/grafana.
# Restricted-egress sandboxes (Cursor Cloud Agents) cannot reach dl.grafana.com but can
# reach Docker Hub, so fall back to the same release's published image layers.
set -euo pipefail
GF_VER="${1:?usage: fetch-grafana.sh <version> <bin-dir>}"
BIN="${2:?usage: fetch-grafana.sh <version> <bin-dir>}"
IMAGE="${GRAFANA_IMAGE:-grafana/grafana-enterprise}"
os=$(uname -s | tr '[:upper:]' '[:lower:]'); arch=$(uname -m)
case "$arch" in x86_64|amd64) arch=amd64 ;; arm64|aarch64) arch=arm64 ;; *) echo "unsupported arch $arch"; exit 1 ;; esac
mkdir -p "$BIN"

echo "downloading Grafana $GF_VER ($os-$arch)…"
if curl -fsSL --connect-timeout 15 "https://dl.grafana.com/enterprise/release/grafana-enterprise-$GF_VER.$os-$arch.tar.gz" | tar xz -C "$BIN"; then
  [ -d "$BIN/grafana-v$GF_VER" ] && mv "$BIN/grafana-v$GF_VER" "$BIN/grafana-$GF_VER" || true
  exit 0
fi

echo "dl.grafana.com unreachable; falling back to the $IMAGE:$GF_VER image layers…"
rm -rf "${BIN:?}/grafana-$GF_VER"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
reg="https://registry-1.docker.io/v2/$IMAGE"
accept='application/vnd.docker.distribution.manifest.list.v2+json,application/vnd.docker.distribution.manifest.v2+json,application/vnd.oci.image.index.v1+json,application/vnd.oci.image.manifest.v1+json'
tok=$(curl -fsSL "https://auth.docker.io/token?service=registry.docker.io&scope=repository:$IMAGE:pull" \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["token"])')

# A multi-arch tag resolves to a per-platform manifest; a single-arch tag already is one.
manifest=$(curl -fsSL -H "Authorization: Bearer $tok" -H "Accept: $accept" "$reg/manifests/$GF_VER" \
  | python3 -c "
import json,sys
d = json.load(sys.stdin)
m = [m for m in d.get('manifests', [])
     if m['platform']['architecture'] == '$arch' and m['platform']['os'] == 'linux']
print(m[0]['digest'] if m else '')")
[ -n "$manifest" ] || manifest="$GF_VER"

layers=$(curl -fsSL -H "Authorization: Bearer $tok" -H "Accept: $accept" "$reg/manifests/$manifest" \
  | python3 -c 'import json,sys; print("\n".join(l["digest"] for l in json.load(sys.stdin)["layers"]))')

# Grafana's homepath is split across layers (bin, conf, public), so unpack each in order
# and let later layers win, exactly as the image's own filesystem would stack them.
for layer in $layers; do
  curl -fsSL -H "Authorization: Bearer $tok" "$reg/blobs/$layer" -o "$tmp/layer.tgz"
  tar xzf "$tmp/layer.tgz" -C "$tmp" usr/share/grafana 2>/dev/null || true
done

[ -x "$tmp/usr/share/grafana/bin/grafana" ] || { echo "no grafana binary in $IMAGE:$GF_VER"; exit 1; }
mkdir -p "$BIN/grafana-$GF_VER"
cp -a "$tmp/usr/share/grafana/." "$BIN/grafana-$GF_VER/"
